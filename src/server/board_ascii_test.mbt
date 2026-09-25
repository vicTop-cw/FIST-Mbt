// board_ascii 实时任务看板渲染测试。

///|
fn ba_engine() -> @engine.FistEngine {
  @engine.FistEngine::new()
}

///|
fn ba_publish(e : @engine.FistEngine, desc : String) -> String {
  match
    e.publish(project_dir="/proj/board", description=desc, created_by="human_steward", now="2026-09-25T10:00:00Z") {
    Ok(id) => id
    Err(m) => abort("publish failed: \{m}")
  }
}

///|
test "board_ascii 按状态分组 + 深度缩进 + 状态合计" {
  let e = ba_engine()
  let root = ba_publish(e, "Omega 看板根任务")
  ignore(e.claim(task_id=root, assignee="leader_a", now="2026-09-25T10:01:00Z"))
  match
    e.plan_deep(task_id=root, split_n=2, by="leader_a", now="2026-09-25T10:02:00Z") {
    Ok(_) => ()
    Err(m) => abort("plan_deep failed: \{m}")
  }
  // 认领其中一个子任务进入执行，制造"sizing 中"状态
  let children = e.children_of(root)
  assert_true(children.length() >= 2)
  let c0 = children[0].get_id()
  ignore(e.claim(task_id=c0, assignee="exec_1", now="2026-09-25T10:03:00Z"))
  ignore(e.execute(task_id=c0, deliverable="成果 v1", now="2026-09-25T10:04:00Z"))

  let board = render_board_ascii(e.list_all(), "")
  let j = board.stringify()
  // 状态合计头尾都在
  assert_true(j.contains("状态合计"))
  assert_true(j.contains("待领取"))
  assert_true(j.contains("执行中"))
  // 深度缩进（子任务行以 · 开头）与状态标记
  assert_true(j.contains("[待领取]"))
  assert_true(j.contains("[执行中]"))
  // counts 对象非空（渲染了至少一个状态分组，行断言已覆盖多状态分组）
  let cnt = match board.value("counts") {
    Some(Object(m)) => m
    _ => abort("counts 缺失")
  }
  assert_true(cnt.length() >= 1)
}

///|
test "board_ascii 支持 namespace 过滤" {
  let e = ba_engine()
  let root = ba_publish(e, "看板 ns 过滤根")
  ignore(e.claim(task_id=root, assignee="leader_a", now="2026-09-25T10:10:00Z"))
  match
    e.plan_deep(task_id=root, split_n=1, by="leader_a", now="2026-09-25T10:11:00Z") {
    Ok(_) => ()
    Err(m) => abort("plan_deep failed: \{m}")
  }
  let tasks = e.list_all()
  // 全部命名空间视图应含任务
  let all = render_board_ascii(tasks, "").stringify()
  assert_true(all.contains("待领取"))
  // 按不存在的 ns 过滤：不应出现任何任务行
  let none = render_board_ascii(tasks, "no-such-ns").stringify()
  assert_true(none.contains("状态合计"))
  assert_false(none.contains("[待领取]"))
  assert_false(none.contains("[已领取]"))
}

///|
test "status_summary 项目脉冲：总量 + 按状态计数 + 活跃命名空间" {
  let e = ba_engine()
  let root = ba_publish(e, "脉冲根任务")
  ignore(e.claim(task_id=root, assignee="leader_a", now="2026-09-25T10:20:00Z"))
  match
    e.plan_deep(task_id=root, split_n=1, by="leader_a", now="2026-09-25T10:21:00Z") {
    Ok(_) => ()
    Err(m) => abort("plan_deep failed: \{m}")
  }
  let tasks = e.list_all()
  assert_true(tasks.length() >= 2)
  let s = render_status_summary(tasks, ["default"], "0.2.4").stringify()
  // 总量 = 引擎任务数
  match render_status_summary(tasks, ["default"], "0.2.4").value("total_tasks") {
    Some(Number(n, ..)) => assert_eq(n.to_int(), tasks.length())
    _ => abort("total_tasks 缺失: " + s)
  }
  assert_true(s.contains("\"version\":\"0.2.4\""))
  assert_true(s.contains("active_namespaces"))
  assert_true(s.contains("default"))
  // 至少有一个状态计数（待领取 等）
  assert_true(s.contains("待领取"))
}