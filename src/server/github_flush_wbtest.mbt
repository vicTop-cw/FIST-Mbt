///|
/// BUG-239 白盒回归锁：github_flush_execute 的 github_queue_mark_sent 失败不再
/// 被静默吞成空对象，失败原因经 marked_sent_error 条件透出（非空才出现）。
/// 注：源码文本锁匹配字面量，新代码注释不得包含被锁模式本身。
/// r2_read_or_abort/r2_count 为 pipeline_r2_wbtest.mbt 的包级 helper（src/server 同包白盒回归锁共用）。
test "BUG-239：队列标记失败不再被静默吞成空对象（源码文本锁）" {
  let src = r2_read_or_abort("src/server/server.mbt")
  assert_eq(r2_count(src, "Err(_) => Json::object(Map([]))"), 0)
}

///|
test "BUG-239：捕获 github_queue_mark_sent 的失败原因（源码文本锁）" {
  let src = r2_read_or_abort("src/server/server.mbt")
  assert_eq(r2_count(src, "let (mark_json, mark_sent_error) = match mark_res {"), 1)
}

///|
test "BUG-239：标记失败原因条件注入回执（源码文本锁）" {
  let src = r2_read_or_abort("src/server/server.mbt")
  assert_eq(r2_count(src, "if mark_sent_error != \"\" {"), 1)
  assert_true(src.contains("\"marked_sent_error\""))
}

///|
test "BUG-239：工具描述同步提及标记失败透出" {
  let src = r2_read_or_abort("src/server/server.mbt")
  assert_true(src.contains("标记失败时回执附 marked_sent_error"))
}
