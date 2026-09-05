// Blackbox tests run against the package's public API. Use `@fist-mbt` to import.
// Prefer high-level behaviors over implementation details.
// Run `moon test` to execute and `moon test --update` to refresh snapshots.

fn new_engine() -> FistEngine {
  FistEngine::new()
}

fn publish_root(e : FistEngine, desc~ : String = "测试根任务") -> String {
  let r = e.publish(
    project_dir="E:/proj/demo",
    description=desc,
    created_by="human_steward",
    now="2026-09-05T10:00:00Z",
  )
  match r {
    Ok(id) => id
    Err(m) => abort("publish failed: \{m}")
  }
}

test "publish 创建根任务 T0，状态为待领取" {
  let e = new_engine()
  let id = publish_root(e)
  assert_eq!(id, "T0")
  let t = e.get_task(id)
  match t {
    Some(x) => assert_eq!(x.status_to_string(), "待领取")
    None => abort("root task missing")
  }
}

test "publish 仅限人类指挥官，非授权者被拒" {
  let e = new_engine()
  let r = e.publish(
    project_dir="E:/proj/demo",
    description="x",
    created_by="evil_agent",
    now="2026-09-05T10:00:00Z",
  )
  match r {
    Err(_) => () // 期望被拒绝
    Ok(_) => abort("publish should reject non-commander")
  }
}

test "claim 将任务迁移到已领取" {
  let e = new_engine()
  let id = publish_root(e)
  match e.claim(task_id=id, assignee="leader_a", now="2026-09-05T10:01:00Z") {
    Ok(t) => assert_eq!(t.status_to_string(), "已领取")
    Err(m) => abort("claim failed: \{m}")
  }
}

test "claim 后 plan 拆分生成子任务，父任务进入拆分中" {
  let e = new_engine()
  let id = publish_root(e)
  // 未认领直接 plan 应被拒（split 要求已领取）
  match e.plan(task_id=id, split_n=2, by="leader_a", now="2026-09-05T10:01:00Z") {
    Err(_) => ()
    Ok(_) => abort("plan before claim should fail")
  }
  ignore(e.claim(task_id=id, assignee="leader_a", now="2026-09-05T10:02:00Z"))
  match e.plan(task_id=id, split_n=2, by="leader_a", now="2026-09-05T10:03:00Z") {
    Ok(children) =>
      if children.length() != 2 {
        abort("plan should produce 2 children, got \{children.length()}")
      } else {
        // 父任务进入拆分中，子任务为待领取
        match e.get_task(id) {
          Some(p) => assert_eq!(p.status_to_string(), "拆分中")
          None => abort("parent missing after plan")
        }
        for c in children {
          match e.get_task(c) {
            Some(ct) =>
              if ct.status_to_string() != "待领取" {
                abort("child should be 待领取, got \{ct.status_to_string()}")
              }
            None => abort("child missing: \{c}")
          }
        }
      }
    Err(m) => abort("plan should succeed after claim, got: \{m}")
  }
}

test "完整闭环 publish -> claim -> execute -> submit -> verify -> archive -> delete" {
  let e = new_engine()
  let id = publish_root(e)
  // 未认领 execute 应被拒（要求已领取/拆分中）
  match e.execute(task_id=id, deliverable="x", now="2026-09-05T10:01:00Z") {
    Err(_) => ()
    Ok(_) => abort("execute before claim should fail")
  }
  ignore(e.claim(task_id=id, assignee="exec_1", now="2026-09-05T10:02:00Z"))
  match e.execute(task_id=id, deliverable="实现核心逻辑", now="2026-09-05T10:03:00Z") {
    Ok(t) => assert_eq!(t.status_to_string(), "执行中")
    Err(m) => abort("execute failed: \{m}")
  }
  match e.submit(task_id=id, now="2026-09-05T10:04:00Z") {
    Ok(t) => assert_eq!(t.status_to_string(), "待验收")
    Err(m) => abort("submit failed: \{m}")
  }
  // 待验收前 verify 应能通过（由 verifier 验收）
  match e.verify(task_id=id, verifier="ver_1", now="2026-09-05T10:05:00Z") {
    Ok(t) => assert_eq!(t.status_to_string(), "已完成")
    Err(m) => abort("verify failed: \{m}")
  }
  match e.archive(task_id=id, by="human_steward", now="2026-09-05T10:06:00Z") {
    Ok(t) => assert_eq!(t.status_to_string(), "已归档")
    Err(m) => abort("archive failed: \{m}")
  }
  match e.delete_task(id) {
    Ok(_) => ()
    Err(m) => abort("delete should succeed on archived task: \{m}")
  }
  // 删除后不应再查到
  match e.get_task(id) {
    None => ()
    Some(_) => abort("task should be gone after delete")
  }
}

test "非归档状态不允许 delete" {
  let e = new_engine()
  let id = publish_root(e)
  match e.delete_task(id) {
    Err(_) => ()
    Ok(_) => abort("delete should only be allowed on archived tasks")
  }
}

fn count_status(e : FistEngine, s : String) -> Int {
  let mut n = 0
  for t in e.list_all() {
    if t.status_to_string() == s {
      n = n + 1
    }
  }
  n
}

test "list_all 与按状态过滤" {
  let e = new_engine()
  let id = publish_root(e)
  assert_eq!(e.list_all().length(), 1)
  assert_eq!(count_status(e, "待领取"), 1)
  assert_eq!(count_status(e, "已领取"), 0)
  ignore(e.claim(task_id=id, assignee="exec_1", now="2026-09-05T10:01:00Z"))
  assert_eq!(count_status(e, "已领取"), 1)
}
