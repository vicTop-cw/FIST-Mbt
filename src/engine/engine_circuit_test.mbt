/// engine_circuit_test.mbt —— 熔断器三态状态机（R104）测试。
/// 覆盖：Closed 窗口内计数达阈值 → Open（fail-fast）/ Half-Open 恢复（探测成功 Closed、
/// 探测失败回 Open）/ 窗口外失败复位 / clear 清空。需 SQLite 后端（Mem 后端 cb 为 no-op）。

///|
/// 构建干净的 SQLite 引擎（先清库保证用例幂等）。
fn cb_sqlite_engine(db_path : String) -> @engine.FistEngine {
  match @store.SqliteStore::open(db_path) {
    Some(s) => ignore(s.clear())
    None => abort("sqlite open failed: " + db_path)
  }
  match @engine.FistEngine::open_sqlite(db_path) {
    None => abort("engine open failed: " + db_path)
    Some(e) => e
  }
}

///|
fn cb_state(j : Json) -> String {
  match j.value("state") {
    Some(Json::String(s)) => s
    _ => abort("state 缺失: " + j.stringify())
  }
}

///|
fn cb_failures(j : Json) -> Int {
  match j.value("failures") {
    Some(Json::Number(n, ..)) => n.to_int()
    _ => abort("failures 缺失: " + j.stringify())
  }
}

///|
fn cb_allow(j : Json) -> Bool {
  match j.value("allow_call") {
    Some(jj) =>
      match jj.as_bool() {
        Some(b) => b
        None => abort("allow_call 非布尔: " + j.stringify())
      }
    _ => abort("allow_call 缺失: " + j.stringify())
  }
}

///|
test "circuit_fail：Closed 窗口内计数达阈值 → Open（fail-fast 拒绝）" {
  let e = cb_sqlite_engine("cb_r104_t1.db")
  let j1 = e.circuit_fail(circuit="http-api", now_secs=100)
  assert_eq(cb_state(j1), "closed")
  assert_eq(cb_failures(j1), 1)
  let j2 = e.circuit_fail(circuit="http-api", now_secs=110)
  assert_eq(cb_state(j2), "closed")
  assert_eq(cb_failures(j2), 2)
  let j3 = e.circuit_fail(circuit="http-api", now_secs=120)
  assert_eq(cb_state(j3), "open")
  assert_eq(cb_failures(j3), 3)
  assert_eq(cb_allow(j3), false) // fail-fast
}

///|
test "circuit_status：Open 恢复定时器到期 → Half-Open 放行探测；succeed → Closed" {
  let e = cb_sqlite_engine("cb_r104_t2.db")
  ignore(e.circuit_fail(circuit="laya", now_secs=1000))
  ignore(e.circuit_fail(circuit="laya", now_secs=1010))
  ignore(e.circuit_fail(circuit="laya", now_secs=1020))
  // Open：未到期 → 仍 open，allow_call=false
  let s1 = e.circuit_status(circuit="laya", now_secs=1030)
  assert_eq(cb_state(s1), "open")
  assert_eq(cb_allow(s1), false)
  // recovery 30s 到期（1020+30=1050）：1050 → Half-Open 放行探测
  let s2 = e.circuit_status(circuit="laya", now_secs=1050)
  assert_eq(cb_state(s2), "half_open")
  assert_eq(cb_allow(s2), true)
  // 探测成功 → Closed
  let s3 = e.circuit_succeed(circuit="laya", now_secs=1060)
  assert_eq(cb_state(s3), "closed")
  assert_eq(cb_failures(s3), 0)
}

///|
test "circuit_fail：Half-Open 探测失败 → 回 Open 重启恢复定时器" {
  let e = cb_sqlite_engine("cb_r104_t3.db")
  ignore(e.circuit_fail(circuit="db", now_secs=2000))
  ignore(e.circuit_fail(circuit="db", now_secs=2010))
  ignore(e.circuit_fail(circuit="db", now_secs=2020))
  let s2 = e.circuit_status(circuit="db", now_secs=2050)
  assert_eq(cb_state(s2), "half_open")
  // Half-Open 探测失败 → 回 Open（重启定时器，opened_at=now）
  let f = e.circuit_fail(circuit="db", now_secs=2060)
  assert_eq(cb_state(f), "open")
  assert_eq(cb_allow(f), false)
}

///|
test "circuit_fail：窗口外失败复位计数；clear 清空熔断器" {
  let e = cb_sqlite_engine("cb_r104_t4.db")
  ignore(
    e.circuit_fail(
      circuit="x",
      now_secs=100,
      window_secs=60,
      threshold=3,
      recovery_secs=30,
    ),
  )
  let j2 = e.circuit_fail(
    circuit="x",
    now_secs=200,
    window_secs=60,
    threshold=3,
    recovery_secs=30,
  )
  // 200-100=100 > 窗口 60 → 复位为 1
  assert_eq(cb_state(j2), "closed")
  assert_eq(cb_failures(j2), 1)
  // clear 清空：再查 → 默认 closed 0
  ignore(e.store.clear())
  let s = e.circuit_status(circuit="x", now_secs=300)
  assert_eq(cb_state(s), "closed")
  assert_eq(cb_failures(s), 0)
}

///|
/// 读出半开探测配额字段（probes_granted/probe_limit）
fn cb_int_field(j : Json, key : String) -> Int {
  match j.value(key) {
    Some(Json::Number(n, ..)) => n.to_int()
    _ => abort("\{key} 缺失: " + j.stringify())
  }
}

///|
test "BUG-34：Half-Open 只放行 probe_limit 次探测，其余快速失败（旧实现全量透传）" {
  let e = cb_sqlite_engine("cb_b34_t1.db")
  // 基准取非零：opened_at=0 会被状态机读成"从未开路过"，不到半开
  ignore(e.circuit_fail(circuit="gate", now_secs=1000, threshold=1))
  // 1000+recovery(30)=1030 → 到期转半开
  let a1 = e.circuit_status(circuit="gate", now_secs=1030)
  assert_eq(cb_state(a1), "half_open")
  assert_eq(cb_allow(a1), true)
  assert_eq(cb_int_field(a1, "probes_granted"), 1)
  // 病灶复现锁：恢复窗内连查 3 次，第 2 次起必须 allow_call=false
  // （旧实现 `allow = state != "open"` 在这里三次全 true ⇒ 半开退化成 closed，正是要防的踩踏）
  let a2 = e.circuit_status(circuit="gate", now_secs=1031)
  assert_eq(cb_state(a2), "half_open")
  assert_eq(cb_allow(a2), false)
  let a3 = e.circuit_status(circuit="gate", now_secs=1032)
  assert_eq(cb_allow(a3), false)
  assert_eq(cb_int_field(a3, "probes_granted"), 1)
  // 探测成功 → Closed，节流解除
  let ok = e.circuit_succeed(circuit="gate", now_secs=1033)
  assert_eq(cb_state(ok), "closed")
  assert_eq(cb_allow(e.circuit_status(circuit="gate", now_secs=1034)), true)
}

///|
test "BUG-34：probe_limit 可配；探测丢失超过一个恢复窗后配额重置（不永久锁死）" {
  let e = cb_sqlite_engine("cb_b34_t2.db")
  ignore(
    e.circuit_fail(circuit="svc", now_secs=100, threshold=1, recovery_secs=20),
  )
  // 配额 2：连查两次都放行，第三次挡下
  assert_eq(cb_allow(e.circuit_status(circuit="svc", now_secs=120)), true)
  assert_eq(
    cb_allow(e.circuit_status(circuit="svc", now_secs=121, probe_limit=2)),
    true,
  )
  let third = e.circuit_status(circuit="svc", now_secs=122, probe_limit=2)
  assert_eq(cb_allow(third), false)
  assert_eq(cb_int_field(third, "probe_limit"), 2)
  assert_eq(cb_int_field(third, "probes_granted"), 2)
  // probe_limit<=0 = 显式不节流（运维侧逃生门，语义要在返回体里看得见）
  let open_all = e.circuit_status(circuit="svc", now_secs=123, probe_limit=0)
  assert_eq(cb_allow(open_all), true)

  // 探测丢失：拿到配额后既不 succeed 也不 fail，过一整个恢复窗(20s)必须还能再探一次
  let e2 = cb_sqlite_engine("cb_b34_t3.db")
  ignore(
    e2.circuit_fail(circuit="lost", now_secs=300, threshold=1, recovery_secs=20),
  )
  assert_eq(cb_allow(e2.circuit_status(circuit="lost", now_secs=320)), true)
  assert_eq(cb_allow(e2.circuit_status(circuit="lost", now_secs=321)), false)
  let revived = e2.circuit_status(circuit="lost", now_secs=341)
  assert_eq(cb_state(revived), "half_open")
  assert_true(
    cb_allow(revived),
    msg="探测丢失后配额未重置——半开态被永久锁死（BUG-34 的新失效形状）: " +
      revived.stringify(),
  )
  assert_eq(cb_int_field(revived, "probes_granted"), 1)
}

///|
test "BUG-34：Closed 态不受节流影响（零回归）" {
  let e = cb_sqlite_engine("cb_b34_t4.db")
  let s = e.circuit_status(circuit="fresh", now_secs=1000)
  assert_eq(cb_state(s), "closed")
  assert_eq(cb_allow(s), true)
  assert_eq(cb_int_field(s, "probes_granted"), 0)
  ignore(e.circuit_fail(circuit="fresh", now_secs=1001))
  let s2 = e.circuit_status(circuit="fresh", now_secs=1002)
  assert_eq(cb_state(s2), "closed")
  assert_eq(cb_allow(s2), true)
}
