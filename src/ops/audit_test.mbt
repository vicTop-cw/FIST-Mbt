/// audit_test.mbt —— 权限与审计模块测试

/// 权限矩阵：publish/archive/delete 仅 HumanSteward
test "audit: 权限矩阵（人类主权四操作）" {
  let hs = match Role::from_string("human_steward") {
    Some(r) => r
    None => return
  }
  let leader = match Role::from_string("leader") {
    Some(r) => r
    None => return
  }
  let agent = match Role::from_string("agent") {
    Some(r) => r
    None => return
  }
  // publish
  assert_true(can_publish(hs))
  assert_false(can_publish(leader))
  assert_false(can_publish(agent))
  // archive
  assert_true(can_archive(hs))
  assert_false(can_archive(leader))
  assert_false(can_archive(agent))
  // delete
  assert_true(can_delete(hs))
  assert_false(can_delete(leader))
  assert_false(can_delete(agent))
  // claim：三角色全部放开
  assert_true(can_claim(hs))
  assert_true(can_claim(leader))
  assert_true(can_claim(agent))
}

/// enforce：合法放行 / 越权拒绝
test "audit: enforce 放行与拒绝" {
  let hs = match Role::from_string("human_steward") {
    Some(r) => r
    None => return
  }
  let leader = match Role::from_string("leader") {
    Some(r) => r
    None => return
  }
  let agent = match Role::from_string("agent") {
    Some(r) => r
    None => return
  }
  // HumanSteward 四操作全部放行
  assert_true(enforce(action="publish", role=hs).is_ok())
  assert_true(enforce(action="archive", role=hs).is_ok())
  assert_true(enforce(action="delete", role=hs).is_ok())
  assert_true(enforce(action="claim", role=hs).is_ok())
  // Leader 越权 publish/archive/delete 被拒，claim 放行
  let actions = ["publish", "archive", "delete"]
  for a in actions {
    let r = enforce(action=a, role=leader)
    assert_true(r.is_err())
    match r {
      Err(msg) => {
        assert_true(msg.contains("leader"))
        assert_true(msg.contains(a))
      }
      Ok(_) => fail("leader 不应获得 \{a} 权限")
    }
  }
  assert_true(enforce(action="claim", role=leader).is_ok())
  // Agent 同理
  assert_true(enforce(action="publish", role=agent).is_err())
  assert_true(enforce(action="delete", role=agent).is_err())
  assert_true(enforce(action="claim", role=agent).is_ok())
  // 未知动作一律拒绝
  assert_true(enforce(action="unknown_op", role=hs).is_err())
}

/// AuditLog：追加式记录与 entries 顺序
test "audit: 日志追加保持顺序" {
  let log = AuditLog::new()
  log.record(action="publish", actor="human_steward", task_id="T0", now="2026-09-05T00:00:00Z")
  log.record(
    action="claim",
    actor="leader-1",
    task_id="T0",
    detail="认领根任务",
    now="2026-09-05T00:00:10Z",
  )
  log.record(action="submit", actor="agent-1", task_id="T0.1", now="2026-09-05T00:01:00Z")
  let es = log.entries()
  assert_eq(es.length(), 3)
  assert_eq(es[0].action, "publish")
  assert_eq(es[1].actor, "leader-1")
  assert_eq(es[2].task_id, "T0.1")
  assert_eq(es[0].detail, "")
  assert_eq(es[1].detail, "认领根任务")
  assert_eq(es[0].ts, "2026-09-05T00:00:00Z")
}

/// AuditLog：by_actor / by_task 过滤互不干扰
test "audit: by_actor 与 by_task 过滤" {
  let log = AuditLog::new()
  log.record(action="publish", actor="human_steward", task_id="T0", now="t0")
  log.record(action="claim", actor="leader-1", task_id="T0", now="t1")
  log.record(action="claim", actor="agent-1", task_id="T0.1", now="t2")
  log.record(action="submit", actor="agent-1", task_id="T0.2", now="t3")
  log.record(action="archive", actor="human_steward", task_id="T0.1", now="t4")
  let hs = log.by_actor("human_steward")
  assert_eq(hs.length(), 2)
  assert_eq(hs[0].action, "publish")
  assert_eq(hs[1].action, "archive")
  assert_eq(log.by_actor("agent-1").length(), 2)
  assert_eq(log.by_actor("nobody").length(), 0)
  let t0 = log.by_task("T0")
  assert_eq(t0.length(), 2)
  assert_eq(t0[0].actor, "human_steward")
  assert_eq(t0[1].actor, "leader-1")
  assert_eq(log.by_task("T0.1").length(), 2)
  assert_eq(log.by_task("T9").length(), 0)
}

/// AuditLog：to_json 序列化字段完整
test "audit: to_json 序列化" {
  let log = AuditLog::new()
  log.record(action="publish", actor="human_steward", task_id="T0", detail="根任务发布", now="2026-09-05T00:00:00Z")
  let json = log.to_json()
  let s = json.stringify()
  assert_true(s.contains("\"action\":\"publish\""))
  assert_true(s.contains("\"actor\":\"human_steward\""))
  assert_true(s.contains("\"task_id\":\"T0\""))
  assert_true(s.contains("\"detail\":\"根任务发布\""))
  assert_true(s.contains("\"ts\":\"2026-09-05T00:00:00Z\""))
  assert_eq(AuditLog::new().to_json().stringify(), "[]")
}

/// 与引擎联动：list_all/get_task 提供审计事实来源
test "audit: 引擎任务可作为审计来源" {
  let e = @engine.FistEngine::new()
  let log = AuditLog::new()
  let hs = match Role::from_string("human_steward") {
    Some(r) => r
    None => return
  }
  ignore(
    e.publish(
      project_dir="/demo",
      description="审计联动",
      created_by="human_steward",
      now="2026-09-05T00:00:00Z",
    ),
  )
  assert_true(
    enforce(action="publish", role=hs).is_ok() &&
    e.get_task("T0") is Some(_),
  )
  for t in e.list_all() {
    log.record(
      action="audit_snapshot",
      actor="auditor",
      task_id=t.id,
      detail=t.status.to_string(),
      now="2026-09-05T00:00:01Z",
    )
  }
  let es = log.by_task("T0")
  assert_eq(es.length(), 1)
  assert_eq(es[0].detail, "待领取")
  assert_eq(log.by_task("T1").length(), 0)
}
