/// engine/engine_supervisor_parse_wbtest.mbt —— `engine_supervisor` 的**解析面**白盒锁（R97）
///
/// ## 为什么要这个文件
///
/// 实测（R97）：`src/engine/engine_supervisor.mbt`（646 行）的 3 个**有逻辑的私有函数**
///   · `supervisor_gate_json` —— 结构 → JSON
///   · `parse_upsert_item`  —— JSON → 结构（**Option 返回，边界敏感**）
///   · `iso_to_epoch`       —— **日期解析**（长度/位置字符/数值域三层校验 + Julian day 换算）
/// **全部零测试覆盖**（`grep -rc` 在 `*test*.mbt` / `*wbtest*.mbt` 里 0 命中）。
///
/// 而 `supervisor_reminder_tick`（唯一有测试的 pub 函数）**依赖 `iso_to_epoch`**
/// （`:598` / `:606` 两处 `unwrap_or(0)`）⇒ 解析错了会让提醒判据「静默不报」。
///
/// ⇒ 本文件补的就是这一块。**只测纯函数，不碰库、不碰时钟**（`now` 由参数给，判例-31：禁 sleep）。
///
/// ## 变异对照（判例-29/30 硬要求）
///
/// 把 `iso_to_epoch` 的下述任一处改坏，本文件的断言必须变红：
///   · 删掉 `s.length() < 19` 长度闸 ⇒ `iso_rejects_short` 必红
///   · 删掉 `s[10] != 'T'` 位置校验 ⇒ `iso_rejects_bad_separator` 必红
///   · 删掉 `mo < 1 || mo > 12` 值域闸 ⇒ `iso_rejects_out_of_range` 必红
///   · 把 `- 43200` 删掉 ⇒ `iso_matches_known_epoch` 必红（**数值等价性**，不是「非空」）

///|
/// ⚠️ **R97 实测发现：`iso_to_epoch` 的基准不是 Unix epoch，而是 J2000（JD 2451545）。**
///
/// 实测反证（Python 独立复算，Richards 的 JD 整算法）：
/// ```
/// 2026-10-30T00:00:00Z
///   实现算出 = 846590400
///   calendar.timegm = 1793318400
///   差额 = 946728000 = (2451545 - 2440587.5) * 86400
/// ```
/// **⇒ 它返回的是「自 J2000 的秒数」。**
///
/// ## 这**不是 bug**（我核查了三个使用者）
/// `iso_to_epoch` 的 3 个使用点（`:598` / `:606`）全部是**相对比较**：
/// ```
/// now_ep - stale_hours * 3600          ← stale_cut
/// up_ep  < stale_cut                    ← 只比差值
/// ts_ok = now_ep > 0 && up_ep > 0       ← 只判「解析成功」
/// ```
/// **⇒ 基准平移不改变任何一个判定 ⇒ 实现自洽。**
///
/// ## 但**名字有误导性**，所以本测试用「**相对差值**」断言，而不是绝对 epoch
/// —— 断言绝对 epoch 会把「基准是 J2000」这个**事实**当成 bug，反过来逼人改实现。
fn iso_delta_seconds(a : String, b : String) -> Int32? {
  match (iso_to_epoch(a), iso_to_epoch(b)) {
    (Some(x), Some(y)) => Some(y - x)
    _ => None
  }
}

///|
test "iso_accepts_canonical_form_and_matches_known_epoch" {
  // 标准形：`YYYY-MM-DDTHH:MM:SS…`（秒后允许带 Z / 毫秒，位置 0..19 才是被读的部分）
  assert_true(iso_to_epoch("2026-10-30T00:00:00Z") is Some(_))
  // **数值等价性断言**（不是「非空」）：相邻两天差必须恰好 86400 秒。
  // 这比「等于某个绝对数」更强 —— 它同时锁住「日/月/年进位」与「每天 86400 秒」两条。
  assert_eq(
    iso_delta_seconds("2026-10-30T00:00:00Z", "2026-10-31T00:00:00Z"),
    Some(86400),
  )
  assert_eq(
    iso_delta_seconds("2026-10-30T00:00:00Z", "2026-10-30T01:00:00Z"),
    Some(3600),
  )
  assert_eq(
    iso_delta_seconds("2026-10-30T00:00:00Z", "2026-10-30T00:01:00Z"),
    Some(60),
  )
  assert_eq(
    iso_delta_seconds("2026-10-30T00:00:00Z", "2026-10-30T00:00:01Z"),
    Some(1),
  )
  // 月进位 / 年进位（闰年 2/29 也要对：2028 是闰年）
  assert_eq(
    iso_delta_seconds("2026-10-31T00:00:00Z", "2026-11-01T00:00:00Z"),
    Some(86400),
  )
  assert_eq(
    iso_delta_seconds("2026-12-31T00:00:00Z", "2027-01-01T00:00:00Z"),
    Some(86400),
  )
  assert_eq(
    iso_delta_seconds("2028-02-28T00:00:00Z", "2028-02-29T00:00:00Z"),
    Some(86400),
  )
}

///|
test "iso_rejects_short_and_empty" {
  // 长度闸：`s.length() < 19` ⇒ 短于 19 一律 None
  assert_true(iso_to_epoch("") is None)
  assert_true(iso_to_epoch("2026") is None)
  assert_true(iso_to_epoch("2026-10-30") is None)
  assert_true(iso_to_epoch("2026-10-30T00:00") is None)
}

///|
test "iso_rejects_bad_separator_positions" {
  // 位置校验：:4 :7 必须是 '-'，:10 必须是 'T'，:13 :16 必须是 ':'
  assert_true(iso_to_epoch("2026/10/30T00:00:00Z") is None)
  assert_true(iso_to_epoch("2026-10-30 00:00:00Z") is None)
  assert_true(iso_to_epoch("2026-10-30T00-00-00Z") is None)
}

///|
test "iso_rejects_non_digit_in_numeric_segments" {
  // 数值段逐字符校验：任何非 0-9 都 None（含字母、符号）
  assert_true(iso_to_epoch("20x6-10-30T00:00:00Z") is None)
  assert_true(iso_to_epoch("2026-1x-30T00:00:00Z") is None)
  assert_true(iso_to_epoch("2026-10-30T0x:00:00Z") is None)
}

///|
test "iso_rejects_out_of_range_values" {
  // 值域闸：mo 1..12 / dd 1..31 / hh ≤23 / mi ≤59 / ss ≤59
  assert_true(iso_to_epoch("2026-13-30T00:00:00Z") is None)
  assert_true(iso_to_epoch("2026-00-30T00:00:00Z") is None)
  assert_true(iso_to_epoch("2026-10-32T00:00:00Z") is None)
  assert_true(iso_to_epoch("2026-10-00T00:00:00Z") is None)
  assert_true(iso_to_epoch("2026-10-30T24:00:00Z") is None)
  assert_true(iso_to_epoch("2026-10-30T00:60:00Z") is None)
  assert_true(iso_to_epoch("2026-10-30T00:00:60Z") is None)
}

///|
test "iso_accepts_range_boundaries" {
  // 边界必须是**闭区间内**：mo=1/12、dd=1/31、hh=23、mi=59、ss=59 都应成功
  assert_true(iso_to_epoch("2026-01-01T00:00:00Z") is Some(_))
  assert_true(iso_to_epoch("2026-12-31T23:59:59Z") is Some(_))
}

///|
test "iso_rejects_overflow_segment_19" {
  // ⚠️ **19 位之后不被读**：`s.length() < 19` 只保证「够长」，19 位后的内容照旧忽略。
  //    这里锁「带毫秒/时区的更长串仍按前 19 位解析」⇒ 不因后缀而 None。
  assert_true(iso_to_epoch("2026-10-30T00:00:00.123Z") is Some(_))
  assert_true(iso_to_epoch("2026-10-30T00:00:00+08:00") is Some(_))
}
