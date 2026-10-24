/// omega_required_column_wbtest.mbt —— BUG-389 方向② 的白盒锁。
///
/// 缺陷原形：`task_plan_deep(omega_strong_verify=true)` 只把 [omega:required] 写进
/// 子任务 description；随后 `supervisor_task_upsert` 更新描述时该标记被静默覆盖丢失，
/// `omega_spec_create` 误报「未开启 Omega」。
///
/// 方向①（PR#18）修的是「upsert 保留 description 标记」；本文件锁的是**方向②**：
/// Omega 门禁开关判据已移到不可覆盖的元数据列 `tasks.omega_required`（白盒直接读
/// `@core.Task::get_omega_required()` 与 `omega_enabled`，不靠 JSON 回执自证）。

///|
fn oc_engine() -> FistEngine {
  FistEngine::new()
}

///|
/// 造一个 omega_required 元数据为 true 的任务，写库后读回（走 create_task/get_task，
/// 与引擎真实路径同源；断言落在白盒字段上，而非 description 文本）。
fn oc_task_with_omega_flag(flag : Bool) -> @core.Task {
  @core.Task::new(
    id="BUG389_T0",
    project_dir="/proj/bug389",
    description="子任务：修 bug",
    parent_id="BUG389_ROOT",
    priority="高",
    importance="高",
    depth=1,
    split_n=1,
    created_at="2026-10-24T00:00:00Z",
    omega_required=flag,
  )
}

///|
/// 核心回归：任务 upsert 更新描述后 omega_required 元数据仍为 true（不再丢失）。
/// 对照缺陷原形：`with_description` 覆盖 description 时，文本标记 [omega:required]
/// 会被清掉；而 omega_required 列不受描述文本影响。
test "BUG-389 方向②: upsert 覆盖描述后 omega_required 仍为 true" {
  let e = oc_engine()
  let base = oc_task_with_omega_flag(true)
  match e.store.create_task(base) {
    Ok(_) => ()
    Err(m) => abort("create_task 失败: \{m}")
  }
  let fresh = match e.store.get_task(base.get_id()) {
    Some(t) => t
    None => abort("create_task 后读不到任务")
  }
  assert_true(fresh.get_omega_required())
  assert_true(omega_enabled(fresh))
  // 模拟 supervisor_task_upsert：只覆盖 description（不带 omega 标记），其余字段原样保留
  let updated = fresh.with_description(
    "被超级管家覆盖后的描述", "2026-10-24T00:01:00Z",
  )
  assert_false(updated.get_description().contains(omega_mark()))
  match e.store.update_task(updated) {
    Ok(_) => ()
    Err(m) => abort("update_task 失败: \{m}")
  }
  let after = match e.store.get_task(base.get_id()) {
    Some(t) => t
    None => abort("update_task 后读不到任务")
  }
  assert_true(after.get_omega_required())
  assert_true(omega_enabled(after))
}

///|
/// 默认 omega_strong_verify=false 路径：omega_required=false，零回归。
test "BUG-389 方向②: 默认路径 omega_required=false 零回归" {
  let e = oc_engine()
  let base = oc_task_with_omega_flag(false)
  match e.store.create_task(base) {
    Ok(_) => ()
    Err(m) => abort("create_task 失败: \{m}")
  }
  let fresh = match e.store.get_task(base.get_id()) {
    Some(t) => t
    None => abort("create_task 后读不到任务")
  }
  assert_false(fresh.get_omega_required())
  assert_false(omega_enabled(fresh))
}

///|
/// 向后兼容：旧数据只有 description 里的 [omega:required] 标记、元数据列默认为 0，
/// omega_enabled 仍应为 true（描述兜底仍生效）。
test "BUG-389 方向②: 旧数据 description 标记兜底仍生效" {
  let e = oc_engine()
  let legacy = @core.Task::new(
    id="BUG389_LEGACY",
    project_dir="/proj/bug389",
    description="老任务 \{omega_mark()}",
    parent_id="BUG389_ROOT",
    depth=1,
    split_n=1,
    created_at="2026-10-01T00:00:00Z",
  )
  match e.store.create_task(legacy) {
    Ok(_) => ()
    Err(m) => abort("create_task 失败: \{m}")
  }
  let fresh = match e.store.get_task(legacy.get_id()) {
    Some(t) => t
    None => abort("create_task 后读不到任务")
  }
  assert_false(fresh.get_omega_required())
  assert_true(omega_enabled(fresh))
}

///|
/// plan_deep(omega_strong_verify=true) 真路径：子任务 omega_required 落库为 true。
test "BUG-389 方向②: plan_deep 开启强验证时子任务 omega_required 为 true" {
  let e = oc_engine()
  let root = match
    e.publish(
      project_dir="/proj/bug389",
      description="BUG-389 根任务",
      created_by="human_steward",
      now="2026-10-24T00:00:00Z",
    ) {
    Ok(id) => id
    Err(m) => abort("publish 失败: \{m}")
  }
  ignore(e.claim(task_id=root, assignee="leader_a", now="2026-10-24T00:01:00Z"))
  match
    e.plan_deep(
      task_id=root,
      split_n=2,
      by="leader_a",
      now="2026-10-24T00:02:00Z",
      omega_strong_verify=true,
    ) {
    Ok(_) => ()
    Err(m) => abort("plan_deep 失败: \{m}")
  }
  let kids = e.children_of(root)
  if kids.length() == 0 {
    abort("plan_deep 未产出子任务")
  }
  for c in kids {
    assert_true(c.get_omega_required())
    assert_true(omega_enabled(c))
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// F3 继承锁（2026-10-24，在线缺陷）：上面这条只测「入参 = true」那一侧，
// 「父开着 + 不传参」零覆盖（grep 继承|inherit|parent 当时 0 命中）⇒ 1455 全绿也没抓到。
//
// δ 的复现编码：PHk2L2P1
//   P1  = 父任务开着 omega_required
//   k2  = plan_deep(split_n=2) 产出 2 个子任务
//   L2  = 其中 2 个子任务**丢失**了门禁开关
// 修前这条锁红（L2=2），修后转绿（L2=0）。**这就是本锁存在的全部理由。**
// ─────────────────────────────────────────────────────────────────────────────

///|
/// 造一个已发布 + 已认领的根任务，返回 id（两条继承锁共用同一套前置）。
fn oc_publish_claimed(e : FistEngine, desc : String) -> String {
  let root = match
    e.publish(
      project_dir="/proj/f3",
      description=desc,
      created_by="human_steward",
      now="2026-10-24T00:00:00Z",
    ) {
    Ok(id) => id
    Err(m) => abort("publish 失败: \{m}")
  }
  ignore(e.claim(task_id=root, assignee="leader_a", now="2026-10-24T00:01:00Z"))
  root
}

///|
/// 把根任务的 omega_required 元数据列置为 true（走 store.update_task，与引擎真实路径同源）。
fn oc_set_parent_omega(e : FistEngine, id : String) -> Unit {
  let t = match e.store.get_task(id) {
    Some(x) => x
    None => abort("读不到根任务 \{id}")
  }
  let flipped = t.with_omega_required(true, "2026-10-24T00:01:30Z")
  match e.store.update_task(flipped) {
    Ok(_) => ()
    Err(m) => abort("update_task 失败: \{m}")
  }
  let back = match e.store.get_task(id) {
    Some(x) => x
    None => abort("update 后读不到 \{id}")
  }
  if !omega_enabled(back) {
    abort("前置失败：父任务没有真正开着 Omega")
  }
}

///|
/// F3 wb1：**父开着 Omega + plan_deep 不传 omega_strong_verify ⇒ 子任务必须继承**。
/// 钉住的就是这次的洞：门禁在「拆分」这一步静默失效，整棵子树被 omega_* 门禁直接放行。
test "F3 继承 wb1: 父开着 Omega 且不传参时子任务继承门禁" {
  let e = oc_engine()
  let root = oc_publish_claimed(e, "F3 父任务：开着 Omega")
  oc_set_parent_omega(e, root)
  // 关键：**不传** omega_strong_verify（默认 false）——这正是缺陷的触发条件
  match
    e.plan_deep(
      task_id=root,
      split_n=2,
      by="leader_a",
      now="2026-10-24T00:02:00Z",
    ) {
    Ok(_) => ()
    Err(m) => abort("plan_deep 失败: \{m}")
  }
  let kids = e.children_of(root)
  assert_eq(kids.length(), 2)
  let mut lost = 0
  for c in kids {
    if !c.get_omega_required() {
      lost = lost + 1
    }
    // 元数据列与门禁判据两面都要成立（判据单一真源 omega_enabled 取或，这里是它的两个来源）
    assert_true(c.get_omega_required())
    assert_true(omega_enabled(c))
    // description 侧的标记同样要在（旧数据兜底面保持同形）
    assert_true(c.get_description().contains(omega_mark()))
  }
  // 读数与 δ 同编码：P1 / k2 / L<lost>。修前 lost=2（PHk2L2P1），修后 lost=0。
  assert_eq(lost, 0)
  // 门禁面端到端：子任务未建语料 ⇒ execute 门禁必须拦（修前这里会被直接放行）
  let handled = match e.omega_execute_gate(kids[0].get_id()) {
    Ok(_) => false
    Err(msg) => msg.contains("尚未创建语料")
  }
  assert_true(handled)
}

///|
/// F3 wb2：**父没开 Omega + 不传参 ⇒ 子任务默认关闭**（防过度继承，零回归）。
/// 没有这条，一个「永远继承」的修法会把所有任务的子树无差别加严——那是另一种回归。
test "F3 继承 wb2: 父没开 Omega 且不传参时子任务默认关闭" {
  let e = oc_engine()
  let root = oc_publish_claimed(e, "F3 父任务：没开 Omega")
  let parent = match e.store.get_task(root) {
    Some(x) => x
    None => abort("读不到根任务")
  }
  assert_false(omega_enabled(parent))
  match
    e.plan_deep(
      task_id=root,
      split_n=2,
      by="leader_a",
      now="2026-10-24T00:02:00Z",
    ) {
    Ok(_) => ()
    Err(m) => abort("plan_deep 失败: \{m}")
  }
  let kids = e.children_of(root)
  assert_eq(kids.length(), 2)
  for c in kids {
    assert_false(c.get_omega_required())
    assert_false(omega_enabled(c))
    assert_false(c.get_description().contains(omega_mark()))
  }
  // 零回归的另一面：没开 Omega 的子任务，execute 门禁照旧放行
  match e.omega_execute_gate(kids[0].get_id()) {
    Ok(_) => ()
    Err(m) => abort("未开 Omega 的任务不该被 execute 门禁拦: \{m}")
  }
}
