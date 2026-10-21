///|
/// ops_cleanup_wbtest.mbt —— retention_days 上界回归（R12-R6，BUG-219）。
/// 病灶：`retention_days * 86400` 无上界，大值时 Int32 绕回产生负阈值，
/// 误清归档任务（数据丢失）。
/// wbtest 原因：`cleanup_archived` 是 pub，但需构造 FistEngine 来验证 Err 分支。
test "cleanup: retention_days 超过 24855 返回 Err（BUG-219）" {
  let eng = @engine.FistEngine::new()
  let r = cleanup_archived(eng, "2026-01-01T00:00:00Z", retention_days=30000)
  assert_true(r is Err(_))
}

///|
test "cleanup: retention_days 负数返回 Err" {
  let eng = @engine.FistEngine::new()
  let r = cleanup_archived(eng, "2026-01-01T00:00:00Z", retention_days=-1)
  assert_true(r is Err(_))
}

///|
test "cleanup: 正常保留期 30 天成功（空引擎 0 条清理）" {
  let eng = @engine.FistEngine::new()
  let r = cleanup_archived(eng, "2026-01-01T00:00:00Z", retention_days=30)
  if r is Ok(removed) {
    assert_eq(removed.length(), 0)
  } else {
    abort("cleanup 正常保留期应 ok，实际 err")
  }
}
