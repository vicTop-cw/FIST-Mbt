/// engine_dispatch_test.mbt —— 引擎层 store-backed 自治派单（dispatch_next）测试
/// 覆盖：注册执行者能力 → 有可领取任务 → dispatch_next 按能力/负载路由并认领给最佳执行者；
/// 无待领取时不派发不改动。

///|
fn d_engine() -> @engine.FistEngine {
  @engine.FistEngine::new()
}

///|
fn d_publish(e : @engine.FistEngine, desc : String) -> String {
  match
    e.publish(
      project_dir="/proj/dispatch",
      description=desc,
      created_by="human_steward",
      now="2026-09-26T10:00:00Z",
    ) {
    Ok(id) => id
    Err(m) => abort("publish failed: \{m}")
  }
}

///|
test "dispatch_next: 注册执行者能力 → 按负载路由并认领给最佳执行者（store-backed 自治派单）" {
  let e = d_engine()
  // 注册执行者能力（落 store，跨进程可复现）
  ignore(
    e.executor_save(
      name="worker-A",
      abilities_json="[\"编排\",\"js\"]",
      created_at="2026-09-26T10:00:00Z",
    ),
  )
  let id = d_publish(e, "打磨编排引擎的调度")
  let j = e.dispatch_next("", "fallback-agent", "编排", "2026-09-26T10:01:00Z")
  match j.value("dispatched") {
    Some(True) => ()
    _ => abort("应派发成功: " + j.stringify())
  }
  match j.value("task_id") {
    Some(String(tid)) => assert_eq(tid, id)
    _ => abort("task_id 缺失")
  }
  match j.value("to_executor") {
    Some(String(to)) => assert_eq(to, "worker-A")
    _ => abort("to_executor 缺失")
  }
  // 任务应已被 worker-A 认领
  match e.get_task(id) {
    Some(t) => assert_eq(t.assignee, Some("worker-A"))
    None => abort("task 缺失")
  }
}

///|
test "dispatch_next: 无可派发任务时不派发、不改动" {
  let e = d_engine()
  ignore(
    e.executor_save(
      name="worker-B",
      abilities_json="[\"编排\"]",
      created_at="2026-09-26T10:00:00Z",
    ),
  )
  // 没有发布任何待领取任务
  let j = e.dispatch_next("", "fallback-agent", "编排", "2026-09-26T10:01:00Z")
  match j.value("dispatched") {
    Some(False) => ()
    _ => abort("空仓库不应派发: " + j.stringify())
  }
  match j.value("task_id") {
    Some(String(tid)) => assert_eq(tid, "")
    _ => abort("task_id 应为空串")
  }
}

///|
test "dispatch_next: want 为空时从任务描述自动抽取能力并路由（R58 免手传）" {
  let e = d_engine()
  ignore(
    e.executor_save(
      name="nete",
      abilities_json="[\"仪表\",\"信息图\"]",
      created_at="2026-09-26T10:00:00Z",
    ),
  )
  // 描述里含能力标签"仪表"，未显式传 want
  let j = match
    e.publish(
      project_dir="/proj/dispatch-auto",
      description="打磨仪表盘图表的自动化",
      created_by="human_steward",
      now="2026-09-26T10:00:00Z",
    ) {
    Ok(_) => e.dispatch_next("", "fallback-agent", "", "2026-09-26T10:01:00Z")
    Err(m) => abort("publish failed: " + m)
  }
  match j.value("dispatched") {
    Some(True) => ()
    _ => abort("应派发成功: " + j.stringify())
  }
  // 自动抽取到"仪表"，路由命中 nete
  match j.value("want") {
    Some(String(w)) => assert_eq(w, "仪表")
    _ => abort("want 缺失: " + j.stringify())
  }
  match j.value("to_executor") {
    Some(String(to)) => assert_eq(to, "nete")
    _ => abort("to_executor 缺失")
  }
}