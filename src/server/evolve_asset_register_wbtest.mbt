/// BUG-236 白盒回归锁：do_evolve_asset_register_with_search 的落库失败与
/// 搜索失败不再被静默吞掉，回执必须能通过 persist_error / search_error 透出。
/// 注：源码文本锁匹配字面量，新代码注释不得包含被锁模式本身。
/// r2_read_or_abort/r2_count 为 pipeline_r2_wbtest.mbt 的包级 helper（src/server 同包白盒回归锁共用）。

test "BUG-236：evolve_upsert 不再被 ignore 静默吞掉（源码文本锁）" {
  let src = r2_read_or_abort("src/server/self_search_evolve_bridge.mbt")
  assert_eq(r2_count(src, "ignore(\n    match evolve_store {"), 0)
}

test "BUG-236：persist_error 捕获落库结果并注入回执（源码文本锁）" {
  let src = r2_read_or_abort("src/server/self_search_evolve_bridge.mbt")
  assert_eq(r2_count(src, "let persist_error = match evolve_store {"), 1)
  assert_true(
    src.contains("add_parse_error_field(enriched, \"persist_error\", persist_error)"),
  )
}

test "BUG-236：search_error 捕获注入 runner 的搜索失败并注入回执（源码文本锁）" {
  let src = r2_read_or_abort("src/server/self_search_evolve_bridge.mbt")
  assert_eq(r2_count(src, "let (candidates, search_error)"), 1)
  assert_true(
    src.contains("add_parse_error_field(enriched, \"search_error\", search_error)"),
  )
}

test "BUG-236：工具描述同步提及 persist_error / search_error" {
  let src = r2_read_or_abort("src/server/server.mbt")
  assert_true(src.contains("回执附 persist_error 说明原因"))
  assert_true(src.contains("检索失败附 search_error"))
}
