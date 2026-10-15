///|
/// ops_watchdog_wbtest.mbt —— watchdog_tick 续轮选 prev_task 的白盒测试（BUG-166）
///
/// 病根：续轮选 prev_task 原本依赖 `list_in_ns` 的返回顺序，而 SqliteStore 无
/// ORDER BY、MemoryStore 走 Map.each（皆插入序），多个未标记完成的根任务时
/// `pending_advance = Some(t)` 无条件覆盖会串错续轮链。修复：显式按
/// `updated_at` 保留「最近完成的一条」，解析失败保守不覆盖。

///|
test "watchdog_ts_newer: 晚时间戳 > 早时间戳" {
  assert_true(watchdog_ts_newer("2026-09-17T00:00:00Z", "2026-09-18T00:00:00Z"))
  assert_false(
    watchdog_ts_newer("2026-09-18T00:00:00Z", "2026-09-17T00:00:00Z"),
  )
  // 相同时间戳不覆盖（保守）
  assert_false(
    watchdog_ts_newer("2026-09-17T00:00:00Z", "2026-09-17T00:00:00Z"),
  )
  // 空串 / 非法 ISO 保守返回 false
  assert_false(watchdog_ts_newer("", "2026-09-17T00:00:00Z"))
  assert_false(watchdog_ts_newer("2026-09-17T00:00:00Z", ""))
  assert_false(watchdog_ts_newer("not a date", "2026-09-17T00:00:00Z"))
  assert_false(watchdog_ts_newer("", ""))
}

///|
test "watchdog_newer_task: 续轮选 prev_task 保留最近完成的根任务" {
  let early = @core.Task::new(
    id="T0",
    project_dir="/watchdog-demo",
    created_at="2026-09-17T00:00:00Z",
  )
  let late = @core.Task::new(
    id="T0r2",
    project_dir="/watchdog-demo",
    created_at="2026-09-18T00:00:00Z",
  )
  // Task::new 令 updated_at = created_at，直接用 with_updated_at 盖不同完成时刻
  let done_early = early.with_updated_at("2026-09-17T01:00:00Z")
  let done_late = late.with_updated_at("2026-09-18T01:00:00Z")
  // 晚完成应被选为 prev_task
  assert_true(watchdog_newer_task(done_early, done_late))
  assert_false(watchdog_newer_task(done_late, done_early))
  // 空 updated_at 保守不覆盖
  let broken = done_early.with_updated_at("")
  assert_false(watchdog_newer_task(broken, done_early))
  assert_false(watchdog_newer_task(done_early, broken))
}
