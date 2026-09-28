/// plan_remedy_wbtest.mbt —— BUG-99 的成对锁：`plan` 的第二道门拒绝时必须自带出路。
///
/// 缺陷原形：第一道门 `TaskStatus::can_split` 收 待领取/已领取/拆分中/已打回，
/// 第二道门 `Task::split` 只收 已领取 ⇒ 待领取/拆分中/已打回三态穿过第一道门后被
/// 第二道门拒，回执只说"要求状态 [已领取]"、不说怎么到达那一态。
/// 巡回播种链实测（temp/bug92_probe.log，installed 产物 sha256:eb18f4f0）：
///   publish → plan            被拒，调用方只能猜；
///   publish → claim → plan    ok（["T0.1","T0.2"]）。
/// 同时钉住 BUG-92 那条**误报**的正身：文案的"要求态"与"当前态"本就不同
/// （`要求状态 [已领取]，当前是 [待领取]`），报错的是"没有出路"，不是"自相矛盾"。

///|
fn pr_engine() -> FistEngine {
  FistEngine::new()
}

///|
fn pr_publish(e : FistEngine, desc : String) -> String {
  match
    e.publish(
      project_dir=".",
      description=desc,
      created_by="human_steward",
      now="2026-09-28T06:00:00Z",
    ) {
    Ok(id) => id
    Err(m) => abort("publish failed: \{m}")
  }
}

///|
/// 只收拒绝分支：成功即 abort，防"门没关也报绿"。
fn pr_err(r : Result[Array[String], String]) -> String {
  match r {
    Ok(_) => abort("预期 plan 被拒，却成功了")
    Err(m) => m
  }
}

///|
test "plan @待领取：要求态不等于当前态，且点名 claim 出路" {
  let e = pr_engine()
  let tid = pr_publish(e, "BUG-99 出路锁：待领取直接 plan")
  let msg = pr_err(e.plan(task_id=tid, split_n=2, by="leader", now="2026-09-28T06:00:01Z"))
  assert_true(msg.contains("要求状态 [已领取]"))
  assert_true(msg.contains("当前是 [待领取]"))
  // 成对判据：BUG-92 误报的那句形状是「要求状态 [待领取]，当前是 [待领取]」——不得复现
  assert_true(!msg.contains("要求状态 [待领取]"))
  assert_true(msg.contains("出路："))
  assert_true(msg.contains("claim(task_id=" + tid))
}

///|
test "plan @拆分中（重复 plan）：出路点名 get 与 task_plan_deep，不再抛无出路的迁移错误" {
  let e = pr_engine()
  let tid = pr_publish(e, "BUG-99 出路锁：重复 plan")
  match e.claim(task_id=tid, assignee="pr-agent", now="2026-09-28T06:00:02Z") {
    Ok(_) => ()
    Err(m) => abort("claim failed: \{m}")
  }
  match e.plan(task_id=tid, split_n=2, by="leader", now="2026-09-28T06:00:03Z") {
    Ok(kids) => assert_eq(kids.length(), 2)
    Err(m) => abort("首次 plan 应放行: \{m}")
  }
  let msg = pr_err(e.plan(task_id=tid, split_n=2, by="leader", now="2026-09-28T06:00:04Z"))
  assert_true(msg.contains("当前是 [拆分中]"))
  assert_true(msg.contains("出路："))
  assert_true(msg.contains("task_plan_deep"))
}
