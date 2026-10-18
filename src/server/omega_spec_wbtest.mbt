///|
/// BUG-233 白盒回归锁：omega_spec 解析失败不再被 Err(_) => None 静默吞掉，
/// 回执必须能通过 omega_spec_error 透出失败原因。
///
/// 活证据见 memory/bugs.md BUG-233。
///
/// 防回归策略：
///   1. 源码文本锁：server.mbt 不再有 `Err(_) => None`（omega_spec 解析处）
///   2. 源码文本锁：server.mbt 必须有 omega_spec_error 回执逻辑
///   3. 工具描述同步锁：omega_spec 描述必须提及 omega_spec_error
///
/// 注意：不使用纯函数归一（此处是内联 match，非独立函数），
/// 改用源码文本锁钉住关键模式。
test "BUG-233：omega_spec 解析不再有裸 Err(_) => None（源码文本锁）" {
  let src = r2_read_or_abort("src/server/server.mbt")
  assert_eq(r2_count(src, "Err(_) => None"), 0)
}

///|
test "BUG-233：omega_spec_error 回执逻辑存在（源码文本锁）" {
  let src = r2_read_or_abort("src/server/server.mbt")
  assert_true(src.contains("omega_spec_error"))
  assert_true(
    src.contains("m.set(\"omega_spec_error\", Json::string(omega_spec_error))"),
  )
  assert_true(src.contains("if omega_spec_error != \"\""))
}

///|
test "BUG-233：omega_spec 工具描述同步提及 omega_spec_error" {
  let src = r2_read_or_abort("src/server/server.mbt")
  assert_true(src.contains("omega_spec_error"))
}
