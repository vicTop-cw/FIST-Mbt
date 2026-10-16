/// executor_register_wbtest.mbt —— BUG-232 回归锁。
///
/// 修复前：`executor_register` 把 `engine.executor_save` 的 Result 用 `ignore()` 吞掉，
/// 且回执 `persisted` 硬编码为 true——写盘失败时仍谎报落库，进程内注册表看似成功、
/// store 里却没有，重启后 `executor_route` 读不到（静默吞错家族，与 BUG-230 同族）。
///
/// 锁两件事：(1) 纯函数 `executor_persist_note` 的 Ok/Err 双分支语义；
/// (2) server.mbt 源码文本——调用点已接线、硬编码 `persisted:true` 已消除、`persist_error` 留痕。

///|
/// 纯函数语义：Ok→(true, "") 无错不留痕；Err→(false, 错误原文)。
test "BUG-232：executor_persist_note Ok/Err 双分支" {
  let (ok_p, ok_e) = executor_persist_note(Ok("executor-A"))
  assert_eq(ok_p, true)
  assert_eq(ok_e, "")
  let (bad_p, bad_e) = executor_persist_note(Err("sqlite 写入 executors 失败"))
  assert_eq(bad_p, false)
  assert_eq(bad_e, "sqlite 写入 executors 失败")
  // 空原因也照样成型（不 panic、不吞成空串之外的东西）
  let (e2_p, e2_e) = executor_persist_note(Err(""))
  assert_eq(e2_p, false)
  assert_eq(e2_e, "")
}

///|
/// 源码文本锁：接线点存在 + 硬编码 persisted:true 已消除 + persist_error 透出。
test "BUG-232：executor_register 不再硬编码 persisted:true（源码文本锁）" {
  let src = r2_read_or_abort("src/server/server.mbt")
  assert_true(r2_count(src, "= executor_persist_note(") >= 1)
  assert_eq(r2_count(src, "\"persisted\": Json::boolean(true),"), 0)
  assert_true(src.contains("m.set(\"persist_error\", Json::string(persist_error))"))
}
