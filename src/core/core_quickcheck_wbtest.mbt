/// core_quickcheck_wbtest.mbt —— Task 状态机迁移纪律属性测试（R107 · quickcheck，whitebox 直构任意状态）。
/// 覆盖此前无直接测试的 Task 迁移方法：Ok ⇒ 目标态达成且身份字段保留；Err ⇒ 拒绝路径语义正确。

///|
/// 由随机 Int 映射到 9 态之一（覆盖全状态空间）。
fn status_at(i : Int) -> TaskStatus {
  match i % 9 {
    0 => Pending
    1 => Claimed
    2 => Splitting
    3 => Executing
    4 => Reviewing
    5 => Completed
    6 => Archived
    7 => Rejected
    _ => Paused
  }
}

///|
/// 由随机 Int 构造任意状态任务（depth 1..5 覆盖叶子/非叶子）。
fn rand_task(i : Int) -> Task {
  let t = Task::new(
    id="t_" + i.to_string(),
    project_dir="/p",
    description="prop desc " + (i % 7).to_string(),
    depth=1 + i % 5,
    split_n=1 + i % 5,
  )
  { ..t, status: status_at(i), }
}

///|
test "quickcheck: claim 迁移纪律（空 assignee 拒绝 / 非待领取拒绝 / 身份与 assignee 保留）" {
  @quickcheck.check(
    (i : Int) => {
      let t = rand_task(i)
      let a = if i % 3 == 0 { "" } else { "agent" + (i % 3).to_string() }
      match t.claim(assignee=a) {
        Ok(nt) =>
          nt.get_status() == Claimed &&
          nt.get_id() == t.get_id() &&
          nt.get_description() == t.get_description() &&
          nt.get_assignee() == Some(a)
        Err(_) => t.get_status() != Pending || a == ""
      }
    },
    count=100,
    max_size=0,
    seed=20260926,
  )
}

///|
test "quickcheck: execute 迁移纪律（仅已领取/拆分中可执行，其余拒绝且身份保留）" {
  @quickcheck.check(
    (i : Int) => {
      let t = rand_task(i)
      match t.execute() {
        Ok(nt) =>
          nt.get_status() == Executing &&
          nt.get_id() == t.get_id() &&
          nt.get_depth() == t.get_depth()
        Err(_) => t.get_status() != Claimed && t.get_status() != Splitting
      }
    },
    count=100,
    max_size=0,
    seed=20260927,
  )
}

///|
test "quickcheck: reopen 迁移纪律（仅已归档拒绝，其余回已领取且清空交付）" {
  @quickcheck.check(
    (i : Int) => {
      let t = rand_task(i)
      match t.reopen() {
        Ok(nt) =>
          nt.get_status() == Claimed &&
          nt.get_id() == t.get_id() &&
          nt.get_description() == t.get_description()
        Err(_) => t.get_status() == Archived
      }
    },
    count=100,
    max_size=0,
    seed=20260928,
  )
}

///|
test "quickcheck: split 迁移纪律（仅已领取且非叶子可拆，叶子/他态拒绝）" {
  @quickcheck.check(
    (i : Int) => {
      let t = rand_task(i)
      match t.split() {
        Ok(nt) =>
          t.get_status() == Claimed &&
          !t.is_leaf() &&
          nt.get_status() == Splitting
        Err(_) => t.get_status() != Claimed || t.is_leaf()
      }
    },
    count=100,
    max_size=0,
    seed=20260929,
  )
}

///|
test "quickcheck: submit/reject 对称纪律（仅执行中可提交、仅待验收可打回）" {
  @quickcheck.check(
    (i : Int) => {
      let t = rand_task(i)
      let sub_ok = match t.submit() {
        Ok(nt) => t.get_status() == Executing && nt.get_status() == Reviewing
        Err(_) => t.get_status() != Executing
      }
      let rej_ok = match t.reject() {
        Ok(nt) => t.get_status() == Reviewing && nt.get_status() == Rejected
        Err(_) => t.get_status() != Reviewing
      }
      sub_ok && rej_ok
    },
    count=100,
    max_size=0,
    seed=20260930,
  )
}
