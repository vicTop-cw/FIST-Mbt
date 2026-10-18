///|
/// BUG-234 白盒回归锁：evolve_submit 的 parts 解析失败不再被静默吞成空对象，
/// 回执必须能通过 parts_error 透出失败原因。
/// 注：源码文本锁匹配字面量，新代码注释不得包含被锁模式本身。
/// r2_read_or_abort/r2_count 为 pipeline_r2_wbtest.mbt 的包级 helper（src/server 同包白盒回归锁共用）。
test "BUG-234：parts 解析不再有 let parts : Map[String, Double] = Map([]) 静默吞错（源码文本锁）" {
  let src = r2_read_or_abort("src/server/server.mbt")
  assert_eq(r2_count(src, "let parts : Map[String, Double] = Map([])"), 0)
}

///|
test "BUG-234：parts_error 回执逻辑存在（源码文本锁）" {
  let src = r2_read_or_abort("src/server/server.mbt")
  assert_true(src.contains("parts_error"))
  assert_true(src.contains("m.set(\"parts_error\", Json::string(parts_error))"))
  assert_true(src.contains("if parts_error != \"\""))
}

///|
test "BUG-234：evolve_submit 工具描述同步提及 parts_error" {
  let src = r2_read_or_abort("src/server/server.mbt")
  assert_true(src.contains("parts_error"))
}
