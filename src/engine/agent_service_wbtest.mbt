///|
/// agent_service P0 行为锁（fist-agent-service-platform-plan.md §1.2/§3.2/§3.3）：
/// 注册表 CRUD + 会话状态机 + 会话持久化（重启恢复 running）+ 内存后端降级如实。
/// 状态机铁律：running 只由 start 进入、只由显式 stop 终止（无隐式退出路径）。

///|
/// P0-1 全生命周期：register → start → 心跳 → stop → revoke（删除）。
/// 逐格断言字段往返（capabilities/transport/exposure/session_*）与状态迁移。
test "agent_service P0: 全生命周期 register→start→heartbeat→stop→revoke" {
  let db = "temp/asvc_p0_lifecycle_wb.db"
  let e = match FistEngine::open_sqlite(db) {
    None => abort("open_sqlite 失败：" + db)
    Some(x) => x
  }
  // register（幂等 UPSERT；status 默认 registered=静态登记非拉起）
  assert_true(
    e.agent_service_upsert(
      service_id="svc-marvis",
      owner_agent="marvis",
      capabilities="\"编排\",\"问答\"",
      transport="mcp",
      exposure="local",
      status="registered",
      created_at="2026-11-21T10:00:00Z",
      updated_at="2026-11-21T10:00:00Z",
    )
    is Ok(_),
  )
  let reg = match e.agent_service_get("svc-marvis") {
    Some(r) => r
    None => abort("注册后读不到")
  }
  assert_eq(reg.status, "registered")
  assert_eq(reg.owner_agent, "marvis")
  assert_eq(reg.transport, "mcp")
  assert_eq(reg.exposure, "local")
  // start：running + 会话三件套落库（§3.2 会话持久化）
  assert_true(
    e.agent_service_patch_session(
      service_id="svc-marvis",
      status="running",
      listen_addr="127.0.0.1:18640",
      token="sess-token-p0",
      pid=4242,
      last_heartbeat="2026-11-21T10:01:00Z",
      updated_at="2026-11-21T10:01:00Z",
    )
    is Ok(_),
  )
  let run = match e.agent_service_get("svc-marvis") {
    Some(r) => r
    None => abort("start 后读不到")
  }
  assert_eq(run.status, "running")
  assert_eq(run.session_listen_addr, "127.0.0.1:18640")
  assert_eq(run.session_token, "sess-token-p0")
  assert_eq(run.session_pid, 4242)
  // 心跳：last_heartbeat 刷新、其余字段不动
  assert_true(
    e.agent_service_touch_heartbeat(
      service_id="svc-marvis",
      now="2026-11-21T10:03:00Z",
    )
    is Ok(_),
  )
  let beat = match e.agent_service_get("svc-marvis") {
    Some(r) => r
    None => abort("心跳后读不到")
  }
  assert_eq(beat.session_last_heartbeat, "2026-11-21T10:03:00Z")
  assert_eq(beat.status, "running")
  // stop：显式中断才终止（stopped 保留注册，可再 start）
  assert_true(
    e.agent_service_patch_session(
      service_id="svc-marvis",
      status="stopped",
      listen_addr="",
      token="",
      pid=0,
      last_heartbeat="",
      updated_at="2026-11-21T10:05:00Z",
    )
    is Ok(_),
  )
  let stopped = match e.agent_service_get("svc-marvis") {
    Some(r) => r
    None => abort("stop 后读不到")
  }
  assert_eq(stopped.status, "stopped")
  // revoke：删除注册行（工具层先拦「未 stop 就 revoke」，此处验证删除语义）
  assert_true(e.agent_service_delete("svc-marvis") is Ok(_))
  assert_true(e.agent_service_get("svc-marvis") is None)
}

///|
/// P0-2 会话持久化（§3.2 重启恢复 running）：两个引擎实例先后打开同一库，
/// 前者 start 后，后者（模拟网关重启）按注册表读到 running + 会话三件套。
test "agent_service P0: 重启恢复——新引擎实例读到 running 态" {
  let db = "temp/asvc_p0_restart_wb.db"
  let e1 = match FistEngine::open_sqlite(db) {
    None => abort("open_sqlite 失败：" + db)
    Some(x) => x
  }
  assert_true(
    e1.agent_service_upsert(
      service_id="svc-codearts-win",
      owner_agent="codearts",
      capabilities="[]",
      transport="cli",
      exposure="lan",
      status="registered",
      created_at="2026-11-21T11:00:00Z",
      updated_at="2026-11-21T11:00:00Z",
    )
    is Ok(_),
  )
  assert_true(
    e1.agent_service_patch_session(
      service_id="svc-codearts-win",
      status="running",
      listen_addr="0.0.0.0:18641",
      token="sess-restart",
      pid=5151,
      last_heartbeat="2026-11-21T11:00:30Z",
      updated_at="2026-11-21T11:00:30Z",
    )
    is Ok(_),
  )
  // 模拟网关重启：全新引擎实例打开同一库
  let e2 = match FistEngine::open_sqlite(db) {
    None => abort("open_sqlite(重启) 失败：" + db)
    Some(x) => x
  }
  let rec = match e2.agent_service_get("svc-codearts-win") {
    Some(r) => r
    None => abort("重启后注册行丢失（§3.2 持久化破）")
  }
  assert_eq(rec.status, "running")
  assert_eq(rec.session_listen_addr, "0.0.0.0:18641")
  assert_eq(rec.session_token, "sess-restart")
  assert_eq(rec.session_pid, 5151)
}

///|
/// P0-3 内存后端降级如实：agent_service 仅 SQLite 后端可用，内存后端
/// upsert 报 Err / get 为 None（与 BUG-119 哲学同族：降级必须如实）。
test "agent_service P0: 内存后端降级如实（Err/None，不冒充落库）" {
  let e = FistEngine::new()
  assert_true(
    e.agent_service_upsert(
      service_id="svc-mem",
      owner_agent="x",
      capabilities="[]",
      transport="mcp",
      exposure="local",
      status="registered",
    )
    is Err(_),
  )
  assert_true(e.agent_service_get("svc-mem") is None)
}

///|
/// P0-4 幂等 UPSERT + list：同 service_id 重复登记不产生第二行（§1.2 幂等语义），
/// list 全量可见且字段为最后一次登记值。
test "agent_service P0: 幂等 UPSERT 不重复，list 全量可见" {
  let db = "temp/asvc_p0_upsert_wb.db"
  let e = match FistEngine::open_sqlite(db) {
    None => abort("open_sqlite 失败：" + db)
    Some(x) => x
  }
  let _ = e.agent_service_upsert(
    service_id="svc-atomcode",
    owner_agent="atomcode",
    capabilities="[]",
    transport="cli",
    exposure="local",
    status="registered",
    created_at="2026-11-21T12:00:00Z",
    updated_at="2026-11-21T12:00:00Z",
  )
  let _ = e.agent_service_upsert(
    service_id="svc-atomcode",
    owner_agent="atomcode",
    capabilities="\"编码\"",
    transport="cli",
    exposure="lan",
    status="registered",
    created_at="2026-11-21T12:00:00Z",
    updated_at="2026-11-21T12:05:00Z",
  )
  let all = e.agent_service_list()
  let rows = all.filter(fn(r) { r.service_id == "svc-atomcode" })
  assert_eq(rows.length(), 1)
  let r = rows[0]
  assert_eq(r.exposure, "lan")
  assert_eq(r.capabilities, "\"编码\"")
}
