/// call_log_test.mbt —— call_log 持久化（SQLite 后端）round-trip 测试。
///
/// 覆盖：
///   1) write_call_log 写库后 recent_call_logs 可读回同一记录（含 ok/runtime 等字段）
///   2) 内存后端同样可读回
///   3) limit 截断（写 3 条，取 2 得 2 条，新的在前）

///|
fn clog_str(j : Json, key : String) -> String {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(String(s)) => s
        _ => "<null>"
      }
    _ => "<null>"
  }
}

///|
fn clog_bool(j : Json, key : String) -> Bool {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(True) => true
        _ => false
      }
    _ => false
  }
}

///|
test "call_log_sql_roundtrip" {
  let s = match @store.SqliteStore::open("calllog_c1.db") {
    Some(x) => x
    None => abort("sqlite open failed")
  }
  ignore(s.clear())
  ignore(
    s.write_call_log(
      ts="2026-09-24T00:00:00Z",
      tool="get",
      caller="agentX",
      ns="default",
      params_json="{\"task_id\":\"T1\"}",
      result_json="ok",
      ok=true,
      runtime_ms=3,
      seq=1,
    ),
  )
  ignore(
    s.write_call_log(
      ts="2026-09-24T00:00:01Z",
      tool="verify",
      caller="human_steward",
      ns="default",
      params_json="{}",
      result_json="boom",
      ok=false,
      runtime_ms=7,
      seq=2,
    ),
  )
  let logs = s.recent_call_logs(limit=10)
  assert_eq(logs.length(), 2)
  // 新的（seq=2）在前
  assert_eq(clog_str(logs[0], "tool"), "verify")
  assert_true(not(clog_bool(logs[0], "ok")))
  assert_eq(clog_str(logs[0], "result"), "boom")
  assert_eq(clog_str(logs[1], "tool"), "get")
  assert_true(clog_bool(logs[1], "ok"))
  ignore(s.clear())
}

///|
/// 内存后端同样 round-trip + limit 截断。
test "call_log_mem_roundtrip" {
  let b = @store.StoreBackend::memory()
  for i in 1..<=3 {
    ignore(
      b.write_call_log(
        ts="t" + i.to_string(),
        tool="t" + i.to_string(),
        caller="",
        ns="",
        params_json="{}",
        result_json="ok",
        ok=true,
        runtime_ms=0,
        seq=i,
      ),
    )
  }
  let all = b.recent_call_logs(limit=10)
  assert_eq(all.length(), 3)
  // limit=2 → 取最近 2 条，新的在前
  let two = b.recent_call_logs(limit=2)
  assert_eq(two.length(), 2)
  assert_eq(clog_str(two[0], "tool"), "t3")
  assert_eq(clog_str(two[1], "tool"), "t2")
}
