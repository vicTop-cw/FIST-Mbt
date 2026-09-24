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
  ignore(s.clear())
}