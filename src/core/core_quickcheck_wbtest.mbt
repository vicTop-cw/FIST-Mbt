/// core_quickcheck_wbtest.mbt —— Task 状态机迁移纪律属性测试（R107 · quickcheck，whitebox 直构任意状态）。
/// 覆盖此前无直接测试的 Task 迁移方法：Ok ⇒ 目标态达成且身份字段保留；Err ⇒ 拒绝路径语义正确。

///|
/// 由随机 Int 映射到 9 态之一（覆盖全状态空间）。
fn status_at(i : Int32) -> TaskStatus {
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
fn rand_task(i : Int32) -> Task {
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
    (i : Int32) => {
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
    (i : Int32) => {
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
    (i : Int32) => {
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
    (i : Int32) => {
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
    (i : Int32) => {
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

///|
/// BUG-2 fix: retry 后（状态=执行中）再 execute 应能成功追加/覆盖交付物。
/// 原守卫只允许 [拆分中/已领取]，retry 落在 执行中 → 死角。
test "bug2_execute_after_retry_ok" {
  let t = Task::new(
    id="T-bug2",
    project_dir="temp/bugfix",
    description="BUG-2 复现",
    created_at="2026-09-26T00:00:00Z",
  )
  // 正常路径跑一遍：pending→claimed→splitting→executing→reviewing→rejected→executing(retry)
  let c1 = match t.claim(assignee="agentX") {
    Ok(x) => x
    Err(e) => abort(e)
  }
  let c2 = match c1.split() {
    Ok(x) => x
    Err(e) => abort(e)
  }
  let c3 = match c2.execute() {
    Ok(x) => x
    Err(e) => abort(e)
  }
  let c3d = c3.with_deliverable("第一次交付物", "2026-09-26T00:01:00Z")
  let c4 = match c3d.submit() {
    Ok(x) => x
    Err(e) => abort(e)
  }
  let c5 = match c4.reject(reason="质量不过关") {
    Ok(x) => x
    Err(e) => abort(e)
  }
  assert_eq(c5.get_status().to_string(), "已打回")
  let c6 = match c5.retry() {
    Ok(x) => x
    Err(e) => abort(e)
  }
  assert_eq(c6.get_status().to_string(), "执行中")
  // 关键：在 执行中 状态再 execute 应能成功（BUG-2 修复前这里会失败）
  let c7 = match c6.execute() {
    Ok(x) => x
    Err(e) => abort("BUG-2 修复后 execute(执行中) 应成功：" + e)
  }
  let c7d = c7.with_deliverable(
    "重做后的新交付物", "2026-09-26T00:02:00Z",
  )
  assert_eq(c7d.deliverable, "重做后的新交付物")
}

///|
/// 军衔等级 `level`：Task 默认 6（连长），上游未显式声明级时即连长级。
test "level: Task 默认 6（连长），getter 回读一致" {
  let t = Task::new(id="L0", project_dir="/p")
  assert_eq(t.level, 6)
  assert_eq(t.get_level(), 6)
  // to_json 携带 level 字段（军衔展示层真数据源落 JSON）
  assert_eq(t.to_json().stringify().contains("\"level\":6"), true)
  let t2 = Task::new(id="L1", project_dir="/p", level=3)
  assert_eq(t2.get_level(), 3)
  assert_eq(t2.to_json().stringify().contains("\"level\":3"), true)
}

///|
/// 军衔等级越界钳制 0..7（<0→0，>7→7）；映射表 rank_of 不变。
test "level: 越界钳制 0..7，负值与超界回退边界档" {
  let neg = Task::new(id="Ln", project_dir="/p", level=-5)
  assert_eq(neg.get_level(), 0)
  let big = Task::new(id="Lb", project_dir="/p", level=99)
  assert_eq(big.get_level(), 7)
  // 边界档本身不钳制
  let lo = Task::new(id="Ll", project_dir="/p", level=0)
  assert_eq(lo.get_level(), 0)
  let hi = Task::new(id="Lh", project_dir="/p", level=7)
  assert_eq(hi.get_level(), 7)
  assert_eq(clamp_level(-1), 0)
  assert_eq(clamp_level(8), 7)
}

///|
/// 子任务军衔 = 父级 + 1，封顶排长（7）：连长(6)→排长(7)→士兵；不再上升。
test "child_level: 父级+1，封顶 7" {
  assert_eq(child_level(6), 7)
  assert_eq(child_level(7), 7)
  assert_eq(child_level(8), 7)
  assert_eq(child_level(0), 1)
  // 父级负值先钳到 0，再 +1（防御：真实 Task 的 level 恒 0..7）
  assert_eq(child_level(-1), 1)
}
