/// engine_circuit_wbtest.mbt —— BUG-230 的白盒锁：熔断器写盘不留静默吞错。
///
/// 缺陷原形：circuit_fail / circuit_succeed / circuit_status 的四处 cb_save 调用
/// 以 ignore() 丢弃 Result[Unit, String]；SQLite 写盘失败时回执仍展示内存新状态
/// 且无任何错误线索，调用方无法区分「已落库」与「状态变更丢失」（BUG-228/229 同族）。
///
/// 注：SqliteStore.db 为私有字段、无公开 db=None 构造子，Err 路径无法在测试中直接
/// 构造，故按 BUG-229 先例锁定纯函数形态：cb_persist_note / cb_note_join 的直接
/// 断言 + Mem 后端成功路径不出 persist_error 字段的零回归断言。

///|
test "bug230_熔断器写盘不留静默吞错" {
  // cb_persist_note：Ok→""（无错不留痕），Err→错误原文
  assert_eq(cb_persist_note(Ok(())), "")
  assert_eq(cb_persist_note(Err("sqlite 写入熔断器失败")), "sqlite 写入熔断器失败")
  // cb_note_join：都空→""，一空取另一，都非空→"a；b"
  assert_eq(cb_note_join("", ""), "")
  assert_eq(cb_note_join("a", ""), "a")
  assert_eq(cb_note_join("", "b"), "b")
  assert_eq(cb_note_join("a", "b"), "a；b")
  // Mem 后端 cb_save 恒 Ok：成功路径不出 persist_error 字段（零回归）
  let e = FistEngine::new()
  let j = e.circuit_fail(circuit="mem-c1", now_secs=100)
  assert_eq(j.value("persist_error").is_none(), true)
  let s = e.circuit_status(circuit="mem-c1", now_secs=200)
  assert_eq(s.value("persist_error").is_none(), true)
}
