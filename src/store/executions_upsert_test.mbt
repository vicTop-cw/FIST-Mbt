///|
/// record_execution 幂等（upsert）黑盒测试：同一任务 + 同一 created_at 重复 execute
/// 不应因 executions.id 唯一约束抛错，而应优雅覆盖（ON CONFLICT DO UPDATE）。
fn _reset_exec(path : String) -> Unit {
  match SqliteStore::open(path) {
    Some(s) => ignore(s.clear())
    None => ()
  }
}

///|
/// 读回聚合统计中某数值键（缺失返回 -1，便于断言缺失即失败）
fn _stat_d(j : Json, key : String) -> Double {
  match j.value(key) {
    Some(Number(n, ..)) => n
    _ => -1.0
  }
}

///|
test "record_execution 幂等：同 id 重复写入优雅覆盖不抛 UNIQUE" {
  _reset_exec("tmp_exec_upsert.db")
  let s = match SqliteStore::open("tmp_exec_upsert.db") {
    Some(x) => x
    None => abort("sqlite open failed")
  }
  let r1 = s.record_execution(
    task_id="T0",
    executor="e1",
    model="m1",
    tokens_in=1,
    tokens_out=2,
    cost=0.1,
    duration_ms=3,
    rate_limited=false,
    failure_reason="",
    created_at="2026-09-05T00:00:00Z",
  )
  assert_eq(r1.is_ok(), true)
  // 首条写入：1 行，tokens_in=1
  let stats1 = @store.StoreBackend::sqlite(s).cost_stats()
  assert_eq(_stat_d(stats1, "total_records"), 1.0)
  assert_eq(_stat_d(stats1, "total_tokens_in"), 1.0)
  // 同 task + 同 created_at → execution id 相同 → 应 upsert 覆盖，而不是抛 UNIQUE
  let r2 = s.record_execution(
    task_id="T0",
    executor="e2",
    model="m2",
    tokens_in=5,
    tokens_out=6,
    cost=0.2,
    duration_ms=7,
    rate_limited=true,
    failure_reason="r",
    created_at="2026-09-05T00:00:00Z",
  )
  assert_eq(r2.is_ok(), true)
  // 覆盖生效：仍只有 1 行，且 tokens_in 是第二次的新值(5)而非两行累加(6)或旧值(1)
  let stats2 = @store.StoreBackend::sqlite(s).cost_stats()
  assert_eq(_stat_d(stats2, "total_records"), 1.0)
  assert_eq(_stat_d(stats2, "total_tokens_in"), 5.0)
  assert_eq(_stat_d(stats2, "total_tokens_out"), 6.0)
  assert_eq(_stat_d(stats2, "total_rate_limited"), 1.0)
  ignore(s.clear())
}
