/// omega_orphan_wbtest.mbt —— BUG-417 的成对锁：孤儿 Omega 任务的判据必须精确。
///
/// 缺陷原形：`omega_enabled` 的文本兜底（`description.contains(omega_mark())`）
/// **不区分标记归属** —— 一个 `omega_required=0` 的任务，只因描述里引用了父层文本
/// （含标记）就被判为强验证任务。
///
/// 实测（Lane T）：孤儿 `T0r636.1.2` 描述长 4683 字节，`[父计划:` 出现 4 次，
/// 两个 omega 标记**都在嵌套段内** ⇒ `strip_plan_annotations` 的单层截断有盲区。
///
/// **与 BUG-389 正相反**：那条是「标记被静默**覆盖**」（元数据列对、描述被改坏），
/// 本条是「标记被静默**继承**」（元数据列 false、描述从父层带进来）。
///
/// 本文件钉四件事：
///   ① 父已归档 + 元数据 false + 描述含标记 ⇒ 判 orphan（可豁免）
///   ② 父**未**归档 ⇒ 不判 orphan（反例格，防豁免过宽）
///   ③ **`Completed` ⇒ 不判 orphan**（「已完成」≠「已归档」，最容易写错的一格）
///   ④ 元数据列真开了 ⇒ 永不豁免（正经 Omega 任务）
///
/// 注：`TaskStatus` 的 variant 在包外是 read-only（实测 4036 `Cannot create values of
/// the read-only type`），本仓惯例是走 `TaskStatus::from_string`（见
/// engine_execute_r2_test.mbt:163）。故本文件统一用 `ow_st("已归档")`。

///|
/// 包外造 `TaskStatus` 的唯一正路（variant 直接构造会被 4036 拒）。
fn ow_st(s : String) -> @core.TaskStatus? {
  @core.TaskStatus::from_string(s)
}

///|
/// 造一个「描述含标记 + 元数据 false」的 Leaf 任务（孤儿的形状）。
fn ow_orphan_task(id : String, parent : String) -> @core.Task {
  let desc = "子任务单元 1" + " | " + omega_mark()
  @core.Task::new(
    id~,
    project_dir=".",
    description=desc,
    parent_id=parent,
    omega_required=false,
  )
}

///|
/// 锁 1：父已归档 + 元数据 false + 描述含标记 ⇒ **判 orphan**
test "omega_orphan_wb1_archived_parent_hits" {
  let t = ow_orphan_task("OW-1", "OW-P1")
  assert_true(omega_orphan_of_archived_parent(t, ow_st("已归档")))
}

///|
/// 锁 2（反例格）：父**未**归档 ⇒ **不判 orphan**（防豁免过宽）
test "omega_orphan_wb2_live_parent_does_not_hit" {
  let t = ow_orphan_task("OW-2", "OW-P2")
  // 父在流（已领取 / 执行中 / 待验收）⇒ 都不该豁免
  assert_false(omega_orphan_of_archived_parent(t, ow_st("已领取")))
  assert_false(omega_orphan_of_archived_parent(t, ow_st("执行中")))
  assert_false(omega_orphan_of_archived_parent(t, ow_st("待验收")))
  // 父取不到 ⇒ fail-closed 不豁免
  assert_false(omega_orphan_of_archived_parent(t, None))
  // 根任务（无父）⇒ 不豁免
  let root = ow_orphan_task("OW-ROOT", "")
  assert_false(omega_orphan_of_archived_parent(root, ow_st("已归档")))
}

///|
/// 锁 3（**最关键**）：**`Completed` ⇒ 不判 orphan**
///
/// 「已完成」≠「已归档」。实现里若误用 `is_completed()` 替代 `is_archived()`，
/// **本格必红** —— 这是四状态变异表里最容易写错的一格。
test "omega_orphan_wb3_completed_is_not_archived" {
  let t = ow_orphan_task("OW-3", "OW-P3")
  // Completed 是「做完了但还在台账上」，它仍可能被重开、仍可能有验收语境 ⇒ 不豁免
  assert_false(omega_orphan_of_archived_parent(t, ow_st("已完成")))
  // 对照：Archived 才豁免
  assert_true(omega_orphan_of_archived_parent(t, ow_st("已归档")))
}

///|
/// 锁 4：元数据列**真开了** ⇒ 永不豁免（正经 Omega 任务）
///
/// 防「为了清僵尸而把所有 Omega 门都关了」。
test "omega_orphan_wb4_real_omega_never_exempted" {
  let desc = "正经强验证任务 " + omega_mark()
  let t = @core.Task::new(
    id="OW-4",
    project_dir=".",
    description=desc,
    parent_id="OW-P4",
    omega_required=true,
  )
  // 即使父已归档，元数据列开了就不豁免
  assert_false(omega_orphan_of_archived_parent(t, ow_st("已归档")))
  // 描述不含标记的普通任务也不豁免（文本兜底根本没触发）
  let plain = @core.Task::new(
    id="OW-5",
    project_dir=".",
    description="普通任务没有标记",
    parent_id="OW-P5",
  )
  assert_false(omega_orphan_of_archived_parent(plain, ow_st("已归档")))
}
