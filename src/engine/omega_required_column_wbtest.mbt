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
