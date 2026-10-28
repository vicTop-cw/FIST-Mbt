///|
/// lesson_ts_part_wbtest.mbt —— `lesson_ts_part` 的**唯一性**白盒锁（R148）。
///
/// 为什么补：该函数是 `lesson-<part>` id 的**唯一来源**（4 处调用：`evolve_lesson`、
/// `evolve_auto_wire`、`server.mbt` 两处 omega 根任务 id），而落库口径是 **upsert
/// （重复 id 覆盖）** ⇒ **id 撞车 = 静默丢一条教训**。此前**零测试**。
///
/// R148 修掉的真实缺陷：原上限 16 会切掉秒的个位，`12:34:56` 与 `12:34:59` 产出同一个
/// `20261028.12.34.5` ⇒ 同 10 秒窗口内的教训互相覆盖。

///|
/// 锁 1：**秒级唯一** —— 同一分钟内不同秒必须不同（原实现的最致命点）。
test "lesson_ts_part_seconds_are_distinct" {
  let a = lesson_ts_part("2026-10-28T12:34:56Z")
  let b = lesson_ts_part("2026-10-28T12:34:59Z")
  let c = lesson_ts_part("2026-10-28T12:34:50Z")
  assert_true(a != b)
  assert_true(a != c)
  assert_true(b != c)
}

///|
/// 锁 2：**跨分钟/跨天不同**，且同一时刻**幂等**（同输入同输出）。
test "lesson_ts_part_across_units_and_idempotent" {
  let t = "2026-10-28T12:34:56Z"
  assert_eq(lesson_ts_part(t), lesson_ts_part(t))
  assert_true(lesson_ts_part("2026-10-28T12:34:56Z") != lesson_ts_part("2026-10-28T12:35:56Z"))
  assert_true(lesson_ts_part("2026-10-28T12:34:56Z") != lesson_ts_part("2026-10-29T12:34:56Z"))
}

///|
/// 锁 3：**格式契约** —— 去 `-`、`:`→`.`、`T`→`.`，结果含日期与时分秒且不含原分隔符。
/// 变异对照：把上限从 17 改回 16，锁 1 立刻红（这正是 R148 修的那处）。
test "lesson_ts_part_format_contract" {
  let p = lesson_ts_part("2026-10-28T12:34:56Z")
  assert_true(!p.contains("-"))
  assert_true(!p.contains(":"))
  assert_true(!p.contains("T"))
  // 前缀保留到「秒」：20261028.12.34.56
  assert_true(p.has_prefix("20261028.12.34.56"))
}

///|
/// 锁 4：短串**不补齐、不崩**（缺字段时原样返回），空串返回空串。
test "lesson_ts_part_short_input_is_passthrough" {
  assert_eq(lesson_ts_part(""), "")
  assert_eq(lesson_ts_part("2026"), "2026")
  assert_eq(lesson_ts_part("2026-10-28"), "20261028")
}
