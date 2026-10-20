/// core_task_force_wbtest.mbt —— BUG-227 白盒锁：Task::archive_force
/// force=false 与 Task::archive 完全同义（零回归锚）；force=true 放行
/// 已完成/已暂停/已打回 三类滞留态，拒绝在流态与终态（在途工作/终态保护）。

///|
/// 直构任意状态任务（同包字段可见，模式与 core_quickcheck_wbtest 一致）。
fn force_task_at(s : TaskStatus) -> Task {
  let t = Task::new(
    id="T_force",
    project_dir="/p",
    description="bug227 force archive",
    created_at="t0",
  )
  { ..t, status: s, }
}

///|
/// 提取 Result 的错误文案（Ok 侧哨兵，仅测试用）。
fn force_err_of(r : Result[Task, String]) -> String {
  match r {
    Err(e) => e
    Ok(_) => "<ok>"
  }
}

///|
test "archive_force/false 与 archive 同义：Paused 双双拒绝且文案一致" {
  let t = force_task_at(Paused)
  let msg1 = force_err_of(t.archive())
  let msg2 = force_err_of(t.archive_force(force=false))
  assert_eq(msg1, msg2)
  assert_eq(msg1.contains("archive 要求状态 [已完成]"), true)
}

///|
test "archive_force/true 放行 Paused/Rejected/Completed 三类滞留态入档" {
  let p = force_task_at(Paused).archive_force(force=true)
  assert_eq(p is Ok(_), true)
  assert_eq(p.unwrap().get_status(), Archived)
  let rj = force_task_at(Rejected).archive_force(force=true)
  assert_eq(rj is Ok(_), true)
  assert_eq(rj.unwrap().get_status(), Archived)
  let cp = force_task_at(Completed).archive_force(force=true)
  assert_eq(cp is Ok(_), true)
  assert_eq(cp.unwrap().get_status(), Archived)
}

///|
test "archive_force/true 拒绝在流态并给出 pause 出路文案" {
  let actives = [Pending, Claimed, Splitting, Executing, Reviewing]
  for i in 0..<5 {
    let r = force_task_at(actives[i]).archive_force(force=true)
    assert_eq(r is Err(_), true)
    assert_eq(force_err_of(r).contains("在流状态请先 pause"), true)
  }
}

///|
test "archive_force/true 对已归档终态拒绝重复归档" {
  let r = force_task_at(Archived).archive_force(force=true)
  assert_eq(r is Err(_), true)
  assert_eq(force_err_of(r).contains("force archive 仅支持"), true)
}
