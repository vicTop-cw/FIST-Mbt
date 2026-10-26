/// engine_archive_force_wbtest.mbt —— BUG-227 engine 层 archive_force 白盒锁。
/// core 层 core_task_force_wbtest 只锁 Task::archive_force 的状态机语义；
/// 本文件补 engine 面的两条安全回归：权限门（仅人类指挥官）+ 落库持久化。
/// src/engine 此前无 wbtest；force 权限门与落库路径不可无人看护。

///|
/// 提取 Result 错误文案（Ok 侧哨兵，仅测试用；core 层同模式）。
fn force_err_of(r : Result[@core.Task, String]) -> String {
  match r {
    Err(e) => e
    Ok(_) => "<ok>"
  }
}

///|
/// 建一个已暂停任务（经 engine.pause_task 迁移到 Paused，走真实状态机）。
fn mk_paused(e : FistEngine, id : String) -> Unit {
  ignore(
    e.store.create_task(
      @core.Task::new(
        id~,
        project_dir="/proj/demo",
        description="force paused \{id}",
        created_at="2026-01-01T00:00:00Z",
      ),
    ),
  )
  ignore(e.pause_task(task_id=id, now="2026-01-01T00:00:01Z"))
}

///|
test "archive_force/权限门：非人类指挥官拒绝且不触达 store" {
  let e = FistEngine::new()
  let r = e.archive_force(
    task_id="T1",
    by="agent",
    force=true,
    now="2026-01-01T00:00:02Z",
  )
  assert_eq(force_err_of(r), "archive 仅限人类指挥官")
  // 权限门短路：未触达 store，任务不存在
  assert_eq(e.store.get_task("T1"), None)
}

///|
test "archive_force/任务不存在 → Err task not found" {
  let e = FistEngine::new()
  let r = e.archive_force(
    task_id="ghost",
    by="human_steward",
    force=true,
    now="2026-01-01T00:00:02Z",
  )
  assert_eq(force_err_of(r), "task not found: ghost")
}

///|
test "archive_force/force=false 与 archive 同义：拒暂停态（向后兼容锚）" {
  let e = FistEngine::new()
  mk_paused(e, "T1")
  let r = e.archive_force(
    task_id="T1",
    by="human_steward",
    force=false,
    now="2026-01-01T00:00:02Z",
  )
  assert_eq(
    force_err_of(r),
    "仅已完成任务可归档，当前状态: 已暂停",
  )
}

// ——— BUG-417：orphan 豁免必须**接线成立**，不能只在纯函数里绿 ———
//
// `omega_orphan_wbtest.mbt` 锁的是判据本身（纯函数、无 IO）；它绿**不证明** engine 这一侧
// 真的把「父状态」喂进去了。诊断 BUG-417 时正是这条缝隙最难查：判据层四格全绿，
// 而 engine 面的 `self.get_task(pid)` / `is_archived()` / `omega_enabled` 三处任一接线错位，
// 外部观测到的都只是同一句「尚未做成果复验」。故这里补 engine 层成对锁（判例-29：机制格 ≠ 实现路径格）。

///|
/// 造一个**已归档**父任务（描述不含标记，自身不触发 Omega 门）。
fn af_archived_parent(e : FistEngine, id : String) -> Unit {
  ignore(
    e.store.create_task(
      @core.Task::new(
        id~,
        project_dir="/proj/demo",
        description="普通父任务 \{id}",
        created_at="2026-01-01T00:00:00Z",
      ),
    ),
  )
  ignore(e.pause_task(task_id=id, now="2026-01-01T00:00:01Z"))
  match
    e.archive_force(
      task_id=id,
      by="human_steward",
      force=true,
      now="2026-01-01T00:00:02Z",
    ) {
    Ok(_) => ()
    // 造父不成功就别继续：否则后面每一格都在测一个不存在的父（假绿来源）
    Err(err) => abort("af_archived_parent 造父失败: \{err}")
  }
}

///|
/// 造一个「描述含标记、元数据列可指定」的子任务并迁到已暂停。
fn af_child(
  e : FistEngine,
  id : String,
  parent : String,
  omega_required : Bool,
) -> Unit {
  let desc = "子任务单元 1 | " + omega_mark()
  ignore(
    e.store.create_task(
      @core.Task::new(
        id~,
        project_dir="/proj/demo",
        description=desc,
        parent_id=parent,
        omega_required~,
        created_at="2026-01-01T00:00:00Z",
      ),
    ),
  )
  ignore(e.pause_task(task_id=id, now="2026-01-01T00:00:01Z"))
}

///|
/// 锁 5（接线锁·正例）：父已归档 + 元数据 false + 描述含标记 ⇒ engine 放行并落库。
/// 这一格红的形态就是 BUG-417 原报：同一句「尚未做成果复验」。
test "archive_force/BUG-417 孤儿 Omega（父已归档）在 engine 面真的放行" {
  let e = FistEngine::new()
  af_archived_parent(e, "AFP1")
  af_child(e, "AFC1", "AFP1", false)
  let r = e.archive_force(
    task_id="AFC1",
    by="human_steward",
    force=true,
    now="2026-01-01T00:00:03Z",
  )
  assert_true(r is Ok(_))
  // 落库确认：豁免不是「跳过门禁后没写」，状态真的变了
  assert_eq(
    e.store.get_task("AFC1").unwrap().get_status().to_string(),
    "已归档",
  )
}

///|
/// 锁 6（接线锁·反例）：父**未**归档 ⇒ engine 仍拦（豁免不得由「父查不到」退化成放行）。
test "archive_force/BUG-417 父未归档时 engine 仍拦孤儿形状的任务" {
  let e = FistEngine::new()
  ignore(
    e.store.create_task(
      @core.Task::new(
        id="AFP2",
        project_dir="/proj/demo",
        description="普通父任务 AFP2",
        created_at="2026-01-01T00:00:00Z",
      ),
    ),
  )
  af_child(e, "AFC2", "AFP2", false)
  let msg = force_err_of(
    e.archive_force(
      task_id="AFC2",
      by="human_steward",
      force=true,
      now="2026-01-01T00:00:03Z",
    ),
  )
  assert_true(msg.contains("Omega 门禁拦截归档"))
  assert_true(msg.contains("尚未做成果复验"))
  // 拦下就得真的没动：状态仍是已暂停
  assert_eq(
    e.store.get_task("AFC2").unwrap().get_status().to_string(),
    "已暂停",
  )
}

///|
/// 锁 7（接线锁·核心 fail-closed）：元数据列真开 ⇒ 父已归档也**不得**豁免。
test "archive_force/BUG-417 正经 Omega 任务（元数据列开）父已归档也不放行" {
  let e = FistEngine::new()
  af_archived_parent(e, "AFP3")
  af_child(e, "AFC3", "AFP3", true)
  let msg = force_err_of(
    e.archive_force(
      task_id="AFC3",
      by="human_steward",
      force=true,
      now="2026-01-01T00:00:03Z",
    ),
  )
  assert_true(msg.contains("Omega 门禁拦截归档"))
}

///|
/// 锁 8（接线锁·根任务）：无父 + 描述含标记 ⇒ 仍拦（判据必须自己确认「确实有父」）。
test "archive_force/BUG-417 根任务的标记不构成豁免理由" {
  let e = FistEngine::new()
  af_child(e, "AFC4", "", false)
  let msg = force_err_of(
    e.archive_force(
      task_id="AFC4",
      by="human_steward",
      force=true,
      now="2026-01-01T00:00:03Z",
    ),
  )
  assert_true(msg.contains("Omega 门禁拦截归档"))
}

///|
test "archive_force/force=true 归档暂停态并落库持久化" {
  let e = FistEngine::new()
  mk_paused(e, "T1")
  let r = e.archive_force(
    task_id="T1",
    by="human_steward",
    force=true,
    now="2026-01-01T00:00:02Z",
  )
  assert_true(r is Ok(_))
  // 落库持久化：重读 store 确认状态真的变为已归档（engine 层薄包装不丢副作用）
  let got = e.store.get_task("T1").unwrap()
  assert_eq(got.get_status().to_string(), "已归档")
}
