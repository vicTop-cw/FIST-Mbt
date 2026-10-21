/// engine/engine_supervisor_reminder_test.mbt —— 超级管家提醒者轮询测试
///
/// 验证 supervisor_reminder_tick 的停滞（R2）/待处理超时（R3）检出，纯计算只读。

///|
fn reminder_test_engine() -> FistEngine {
  FistEngine::new()
}

///|
test "reminder_tick 检出停滞活跃任务与待处理超时任务" {
  let e = reminder_test_engine()
  // 2026-09-05 发布根任务（待领取）
  let id = match
    e.publish(
      project_dir="/proj/demo",
      description="根任务",
      created_by="human_steward",
      now="2026-09-05T10:00:00Z",
    ) {
    Ok(x) => x
    Err(m) => abort("publish failed: \{m}")
  }
  // 认领并拆分出子任务，推进到 09-06
  ignore(e.claim(task_id=id, assignee="leader_a", now="2026-09-06T08:00:00Z"))
  let kids = match
    e.plan(task_id=id, split_n=2, by="leader_a", now="2026-09-06T09:00:00Z") {
    Ok(c) => c
    Err(m) => abort("plan failed: \{m}")
  }
  // 认领一个子任务作为活跃但停滞的任务
  let active_id = kids[0]
  ignore(
    e.claim(task_id=active_id, assignee="worker_1", now="2026-09-06T10:00:00Z"),
  )
  // 09-09 轮询：stale_hours=24, pending_hours=48
  let tick = e.supervisor_reminder_tick(
    now="2026-09-09T12:00:00Z",
    stale_hours=24,
    pending_hours=48,
  )
  let m = match tick {
    Json::Object(o) => o
    _ => abort("tick should be object")
  }
  let reminders = match m.get("reminders") {
    Some(Json::Array(a)) => a
    _ => abort("reminders missing")
  }
  let mut stale_found = false
  let mut timeout_found = false
  for r in reminders {
    let rm = match r {
      Json::Object(o) => o
      _ => Map([])
    }
    let kind = match rm.get("kind") {
      Some(Json::String(s)) => s
      _ => ""
    }
    if kind == "stale" {
      stale_found = true
    }
    if kind == "pending_timeout" {
      timeout_found = true
    }
  }
  if !stale_found {
    abort("should find stale reminder")
  }
  if !timeout_found {
    abort("should find pending_timeout reminder")
  }
  // 近期任务不应报停滞：再建一个 09-09 当天的任务
  let id2 = match
    e.publish(
      project_dir="/proj/demo",
      description="新任务",
      created_by="human_steward",
      now="2026-09-09T11:00:00Z",
    ) {
    Ok(x) => x
    Err(m) => abort("publish failed: \{m}")
  }
  let tick2 = e.supervisor_reminder_tick(
    now="2026-09-09T12:00:00Z",
    stale_hours=24,
    pending_hours=48,
  )
  let m2 = match tick2 {
    Json::Object(o) => o
    _ => abort("tick2 should be object")
  }
  let reminders2 = match m2.get("reminders") {
    Some(Json::Array(a)) => a
    _ => abort("reminders2 missing")
  }
  let mut new_task_stale = false
  for r in reminders2 {
    let rm = match r {
      Json::Object(o) => o
      _ => Map([])
    }
    let task_id = match rm.get("task_id") {
      Some(Json::String(s)) => s
      _ => ""
    }
    if task_id == id2 {
      new_task_stale = true
    }
  }
  if new_task_stale {
    abort("new task should not be flagged stale")
  }
}
