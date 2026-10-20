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
  assert_eq(r is Ok(_), true)
  // 落库持久化：重读 store 确认状态真的变为已归档（engine 层薄包装不丢副作用）
  let got = e.store.get_task("T1").unwrap()
  assert_eq(got.get_status().to_string(), "已归档")
}
