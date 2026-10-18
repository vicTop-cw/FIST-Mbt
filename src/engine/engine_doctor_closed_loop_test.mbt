///|
/// 探针：复现 doctor 七态机闭环，逐步打印每步 Err（不静默吞错）。
/// 本文件位于 src/engine 包内，FistEngine 为同包本地符号。
test "engine_doctor_closed_loop_regression" {
  let e = FistEngine::new()
  let now = "2026-09-27T10:00:00Z"
  let c4 = e.publish(
    project_dir="./",
    description="doctor 闭环最小版",
    created_by="human_steward",
    now~,
    ns="doctor-check",
  )
  let root_id = match c4 {
    Err(m) => abort("publish: \{m}")
    Ok(id) => id
  }
  println("  root = \{root_id}")
  match e.claim(task_id=root_id, assignee="leader", now~) {
    Err(m) => abort("claim(root): \{m}")
    Ok(_) => ()
  }
  match e.plan(task_id=root_id, split_n=1, by="agent", now~) {
    Err(m) => abort("plan: \{m}")
    Ok(_) => ()
  }
  let kids = e.children_of(root_id)
  if kids.is_empty() {
    abort("无子任务")
  }
  let kid_id = kids[0].get_id()
  println("  kid = \{kid_id}")
  match e.claim(task_id=kid_id, assignee="w", now~) {
    Err(m) => abort("claim(kid): \{m}")
    Ok(_) => ()
  }
  match
    e.execute(
      task_id=kid_id,
      deliverable="doctor 闭环探针：七态机最小闭环通过",
      now~,
    ) {
    Err(m) => abort("execute(kid, real): \{m}")
    Ok(_) => ()
  }
  match e.submit(task_id=kid_id, now~) {
    Err(m) => abort("submit(kid): \{m}")
    Ok(_) => ()
  }
  match e.verify(task_id=kid_id, verifier="leader", now~) {
    Err(m) => abort("verify(kid): \{m}")
    Ok(_) => ()
  }
  match e.verify(task_id=root_id, verifier="leader", now~) {
    Err(m) => abort("verify(root): \{m}")
    Ok(_) => ()
  }
  match e.archive(task_id=root_id, by="human_steward", now~) {
    Err(m) => abort("archive(root): \{m}")
    Ok(_) => ()
  }
  println("  === 全流程通过 ===")
}
