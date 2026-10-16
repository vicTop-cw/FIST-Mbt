/// BUG-237 白盒回归锁：assistant_sweep 的 assistant_set_status 结果不再被 ignore
/// 吞掉，marked_dead 只计真实成功，失败经 assistants_mark_failed 条件透出。
/// 注：源码文本锁匹配字面量，新代码注释不得包含被锁模式本身。
/// r2_read_or_abort/r2_count 为 pipeline_r2_wbtest.mbt 的包级 helper（src/server 同包白盒回归锁共用）。

test "BUG-237：assistant_set_status 不再被 ignore 静默吞掉（源码文本锁）" {
  let src = r2_read_or_abort("src/server/server.mbt")
  assert_eq(r2_count(src, "ignore(engine.assistant_set_status"), 0)
}

test "BUG-237：捕获 set_status 的 Bool 结果（源码文本锁）" {
  let src = r2_read_or_abort("src/server/server.mbt")
  assert_eq(
    r2_count(src, "let ok = engine.assistant_set_status(r.agent, \"dead\")"),
    1,
  )
}

test "BUG-237：失败计数条件注入回执（源码文本锁）" {
  let src = r2_read_or_abort("src/server/server.mbt")
  assert_eq(r2_count(src, "if mark_failed > 0 {"), 1)
  assert_true(src.contains("\"assistants_mark_failed\""))
}

test "BUG-237：工具描述同步提及失败计数" {
  let src = r2_read_or_abort("src/server/server.mbt")
  assert_true(src.contains("回执附 assistants_mark_failed 计数"))
}
