
///|
/// R231：`model_router` 滚动窗口的两个**时间基元**契约锁（函数级扫描 3/34 的真缺口）。
///
/// 配额窗口的语义全压在这两个函数上：`window_elapsed_secs` 算"开了多久"，
/// `window_expired` 决定"要不要重置"。**非法 ISO 的处理是协议**：两个函数都必须
/// 对 `secs_to_iso`/`iso_to_secs` 的 -1 哨兵（R189 已锁）返回 -1 / 不过期，
/// 否则一个坏时间戳就会把"无法测量"误算成"刚开窗"或"已过期"。

///|
/// elapsed：正常差值 / 两个输入各自非法 ⇒ -1（不许把非法当 0）。
test "window_elapsed_secs 的差值与非法哨兵" {
  // 正常差值
  assert_eq(window_elapsed_secs("2026-10-30T08:00:00+08:00", "2026-10-30T08:01:00+08:00"), 60)
  assert_eq(window_elapsed_secs("2026-10-30T08:00:00+08:00", "2026-10-30T08:00:00+08:00"), 0)
  // 非法 window_start ⇒ -1
  assert_eq(window_elapsed_secs("", "2026-10-30T08:00:00+08:00"), -1)
  assert_eq(window_elapsed_secs("not-a-time", "2026-10-30T08:00:00+08:00"), -1)
  // 非法 now ⇒ -1
  assert_eq(window_elapsed_secs("2026-10-30T08:00:00+08:00", ""), -1)
  assert_eq(window_elapsed_secs("2026-10-30T08:00:00+08:00", "garbage"), -1)
  // 倒挂（now < start）⇒ 负数（不是 -1 哨兵——那是"无法测量"，这是"可测但为负"）
  assert_true(window_elapsed_secs("2026-10-30T08:01:00+08:00", "2026-10-30T08:00:00+08:00") < 0,
    msg="倒挂应返回负数，与 -1 哨兵区分")
}

///|
/// expired：三段边界（< / == / > window_seconds）+ 非法输入一律**不过期**
///（非法 ⇒ elapsed=-1 ⇒ elapsed>=0 不成立 ⇒ false —— "量不出来"不能当"该重置"）。
test "window_expired 的三段边界与非法面" {
  let start = "2026-10-30T08:00:00+08:00"
  // 不足：elapsed=59 < 60
  assert_false(window_expired(start, "2026-10-30T08:00:59+08:00", 60), msg="59s 不应过期")
  // 恰好：elapsed=60 >= 60（窗口语义是 >=）
  assert_true(window_expired(start, "2026-10-30T08:01:00+08:00", 60), msg="恰 60s 应过期（>=）")
  // 超过：elapsed=61
  assert_true(window_expired(start, "2026-10-30T08:01:01+08:00", 60), msg="61s 应过期")
  // window_seconds=0 ⇒ 任何可测时刻都过期
  assert_true(window_expired(start, "2026-10-30T08:00:00+08:00", 0), msg="0 窗口即刻过期")
  // 非法输入 ⇒ 不过期（哨兵路径，-1 >= 0 为 false）
  assert_false(window_expired("", "2026-10-30T08:01:00+08:00", 60), msg="非法 start 不应过期")
  assert_false(window_expired(start, "", 60), msg="非法 now 不应过期")
  // R231 补：**哨兵可区分格** —— 非法输入(window_start="") ⇒ elapsed=-1 哨兵；
  // 配负窗口(-5)时，"删掉 >=0 哨兵"的变异会让 -1 >= -5 误判为过期 ⇒ 只有
  // 同时钉住「非法输入 + 负窗口 ⇒ 不过期」，哨兵守卫才真正被锁住
  //（R231 实测：非法面只配 w=60 时删哨兵不红 —— 变异对照必须能区分变异）。
  assert_false(window_expired("", "2026-10-30T08:01:00+08:00", -5),
    msg="非法 start + 负窗口：哨兵(-1)必须拦住，不得误判过期")
  assert_false(window_expired(start, "not-a-time", -5),
    msg="非法 now + 负窗口：同上")
}
