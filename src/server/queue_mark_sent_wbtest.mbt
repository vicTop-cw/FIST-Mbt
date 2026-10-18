///|
/// BUG-235 白盒回归锁：github_queue_mark_sent / gitcode_queue_mark_sent 的
/// issue_numbers / gitcode_issue_iids 解析失败不再被静默吞成空 Map，
/// 回执必须能通过 issue_numbers_error / gitcode_issue_iids_error 透出失败原因。
/// 注：源码文本锁匹配字面量，新代码注释不得包含被锁模式本身。
/// r2_read_or_abort/r2_count 为 pipeline_r2_wbtest.mbt 的包级 helper（src/server 同包白盒回归锁共用）。
test "BUG-235：github_queue_mark_sent 不再有 let issue_numbers = if ... 静默吞错（源码文本锁）" {
  let src = r2_read_or_abort("src/server/server.mbt")
  assert_eq(
    r2_count(src, "let issue_numbers = if issue_nums_raw.is_empty() {"),
    0,
  )
}

///|
test "BUG-235：gitcode_queue_mark_sent 不再有 iids_raw 静默吞成 Json::object(Map([]))（源码文本锁）" {
  let src = r2_read_or_abort("src/server/server.mbt")
  assert_eq(
    r2_count(
      src, "let j = @json.parse(iids_raw) catch { _ => Json::object(Map([])) }",
    ),
    0,
  )
}

///|
test "BUG-235：issue_numbers_error / gitcode_issue_iids_error 回执逻辑存在（源码文本锁）" {
  let src = r2_read_or_abort("src/server/server.mbt")
  assert_true(src.contains("add_parse_error_field"))
  assert_true(src.contains("issue_numbers_error"))
  assert_true(src.contains("gitcode_issue_iids_error"))
  assert_true(src.contains("\"issue_numbers_error\""))
  assert_true(src.contains("\"gitcode_issue_iids_error\""))
}

///|
test "BUG-235：两个工具描述同步提及解析失败字段" {
  let src = r2_read_or_abort("src/server/server.mbt")
  assert_true(src.contains("非法 JSON 时回执附 issue_numbers_error"))
  assert_true(src.contains("非法 JSON 时回执附 gitcode_issue_iids_error"))
}
