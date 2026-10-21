/// engine_promote_r6_test.mbt —— BUG-59 回归锁：自动提升的父节点必须带上交付物
///
/// 缺陷形态（实测于 ns=router-merge）：子叶全部 verify 后引擎把父节点自动提到「待验收」，
/// 但父节点 deliverable 为空 ⇒ Omega 成果复验门禁说"无可复验成果"，而「待验收」又不许
/// execute（合法路径只有 verify / reject / retry）⇒ 两条门互锁，只能人工 reject→retry 绕一圈。
/// 这里钉住"提升即继承子叶交付"，并保证不覆盖已有交付物。

///|
fn[T] p6_must(r : Result[T, String]) -> T {
  match r {
    Ok(v) => v
    Err(e) => abort("应成功，实际 Err: " + e)
  }
}

///|
fn p6_fetch(e : @engine.FistEngine, id : String) -> @core.Task {
  match e.get_task(id) {
    Some(t) => t
    None => abort("任务不存在: " + id)
  }
}

///|
fn p6_finish_leaf(
  e : @engine.FistEngine,
  id : String,
  deliverable : String,
  t : Int,
) -> Unit {
  let now = "2026-09-26T10:0\{t}:00Z"
  ignore(e.claim(task_id=id, assignee="worker_\{t}", now~))
  ignore(e.execute(task_id=id, deliverable~, now~))
  ignore(e.submit(task_id=id, now~))
  ignore(e.verify(task_id=id, verifier="verifier", now~))
}

///|
test "BUG-59 父节点自动提升时继承子叶交付物，且已有交付物不被覆盖" {
  let e = @engine.FistEngine::new()
  let root = p6_must(
    e.publish(
      project_dir="/proj/p6",
      description="父任务：合并模型路由",
      created_by="human_steward",
      now="2026-09-26T10:00:00Z",
    ),
  )
  ignore(e.claim(task_id=root, assignee="leader", now="2026-09-26T10:00:10Z"))
  let kids = p6_must(
    e.plan(task_id=root, split_n=2, by="leader", now="2026-09-26T10:00:20Z"),
  )
  assert_eq(kids.length(), 2)
  // 提升前：父节点还没有交付物（这正是 BUG-59 的触发条件）
  assert_eq(p6_fetch(e, root).deliverable, "")
  p6_finish_leaf(e, kids[0], "叶子一：路由核心 + 窗口重置", 1)
  // 还有一个孩子没完成 ⇒ 父节点不该被提升
  assert_eq(p6_fetch(e, root).status_to_string(), "拆分中")
  p6_finish_leaf(e, kids[1], "叶子二：执行器 argv + 四态", 2)
  let p = p6_fetch(e, root)
  assert_eq(p.status_to_string(), "待验收")
  // 关键：交付物非空且含两个孩子的原文 ⇒ Omega 成果复验有东西可复验
  assert_true(p.deliverable != "")
  assert_true(p.deliverable.contains("叶子一：路由核心 + 窗口重置"))
  assert_true(p.deliverable.contains("叶子二：执行器 argv + 四态"))
  assert_true(p.deliverable.contains(kids[0]))
}

///|
test "BUG-59 配对：父节点已有交付物时，提升不得覆盖它" {
  let e = @engine.FistEngine::new()
  let root = p6_must(
    e.publish(
      project_dir="/proj/p6b",
      description="父任务：已自述交付",
      created_by="human_steward",
      now="2026-09-26T11:00:00Z",
    ),
  )
  ignore(e.claim(task_id=root, assignee="leader", now="2026-09-26T11:00:10Z"))
  let kids = p6_must(
    e.plan(task_id=root, split_n=1, by="leader", now="2026-09-26T11:00:20Z"),
  )
  // 父节点在拆解后补记了自己的交付物（真实流程里指挥官会这么写）
  ignore(
    e.execute(
      task_id=root,
      deliverable="父节点自述交付",
      now="2026-09-26T11:00:30Z",
    ),
  )
  p6_finish_leaf(e, kids[0], "唯一叶子的交付", 3)
  let p = p6_fetch(e, root)
  assert_eq(p.status_to_string(), "待验收")
  assert_eq(p.deliverable, "父节点自述交付")
}
