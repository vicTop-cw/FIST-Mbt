/// engine_execute_r2_test.mbt —— BUG-2（Round 2 收口）回归：被打回重做这条路必须能
/// 原地更新交付物。
///
/// 病灶：`retry` 落点是「执行中」，而唯一能写 deliverable 的 `execute` 曾只收
/// 「拆分中/已领取」——于是 reject→retry 之后 execute 被拒，`omega_result_verify`
/// 报「尚无交付物」，操作者被逼新建任务覆盖旧账（破坏 append-only 审计）。
/// 摘掉修复（把 Executing 从合法前态里去掉）→ 本文件第一条测试即红。

///|
/// 干净的 SQLite 引擎（先清库保证用例幂等）。
fn r2e_engine(db_path : String) -> @engine.FistEngine {
  // SQLite 只造文件、不造父目录：本文件此前依赖**别的测试文件**先把 `temp/` 建出来，
  // 于是干净树（`git archive` / 新 worktree / CI 刚 checkout）上跑赢竞速就三连红（BUG-115）。
  @fs.create_dir("temp") catch {
    _ => ()
  }
  match @store.SqliteStore::open(db_path) {
    Some(s) => ignore(s.clear())
    None => abort("sqlite open failed: " + db_path)
  }
  match @engine.FistEngine::open_sqlite(db_path) {
    None => abort("engine open failed: " + db_path)
    Some(e) => e
  }
}

///|
fn r2e_publish(e : @engine.FistEngine, now : String) -> String {
  match
    e.publish(
      project_dir="/proj/demo",
      description="BUG-2 回归：打回重做后更新交付物",
      created_by="human_steward",
      now~,
    ) {
    Ok(id) => id
    Err(m) => abort("publish failed: \{m}")
  }
}

///|
fn r2e_must(r : Result[@core.Task, String], who : String) -> @core.Task {
  match r {
    Ok(t) => t
    Err(m) => abort("\{who} 被拒（BUG-2 死角未修）: " + m)
  }
}

///|
/// 从库里读回任务（验证真的写进去了，不是只在返回值里）。
fn r2e_fetch(e : @engine.FistEngine, id : String) -> @core.Task {
  match e.get_task(id) {
    Some(t) => t
    None => abort("task missing: " + id)
  }
}

///|
test "BUG-2：执行中重复 execute = 追加/覆盖交付物（直觉行为，不再被拒）" {
  let e = r2e_engine("temp/r2_bug2_a.db")
  let id = r2e_publish(e, "2026-09-26T10:00:00Z")
  ignore(e.claim(task_id=id, assignee="fixer", now="2026-09-26T10:01:00Z"))
  ignore(
    e.execute(
      task_id=id,
      deliverable="交付物 v1",
      now="2026-09-26T10:02:00Z",
    ),
  )
  // 第二次 execute：任务已在「执行中」——旧守卫在这里直接 Err
  ignore(
    e.execute(
      task_id=id,
      deliverable="交付物 v2（覆盖）",
      now="2026-09-26T10:03:00Z",
    ),
  )
  let t = r2e_fetch(e, id)
  assert_eq(t.deliverable, "交付物 v2（覆盖）")
  assert_eq(t.status_to_string(), "执行中")
}

///|
test "BUG-2：reject→retry→execute 全链写进 deliverable（无需 pause→resume 绕行）" {
  let e = r2e_engine("temp/r2_bug2_b.db")
  let id = r2e_publish(e, "2026-09-26T10:00:00Z")
  ignore(e.claim(task_id=id, assignee="fixer", now="2026-09-26T10:01:00Z"))
  ignore(
    e.execute(
      task_id=id,
      deliverable="第一版实现",
      now="2026-09-26T10:02:00Z",
    ),
  )
  ignore(e.submit(task_id=id, now="2026-09-26T10:03:00Z"))
  let rj = r2e_must(
    e.reject_task(
      task_id=id,
      reason="缺回归测试",
      by="verifier",
      now="2026-09-26T10:04:00Z",
    ),
    "reject",
  )
  assert_eq(rj.status_to_string(), "已打回")
  let rt = r2e_must(
    e.retry_task(task_id=id, now="2026-09-26T10:05:00Z"),
    "retry",
  )
  // retry 的对外落点就是「执行中」（AGENTS.md 工具表承诺）——本用例同时钉住它
  assert_eq(rt.status_to_string(), "执行中")
  // 关键一步：重做后更新交付物
  let ex = r2e_must(
    e.execute(
      task_id=id,
      deliverable="补上回归测试后的第二版实现",
      now="2026-09-26T10:06:00Z",
    ),
    "retry 后 execute",
  )
  assert_eq(ex.deliverable, "补上回归测试后的第二版实现")
  assert_eq(
    r2e_fetch(e, id).deliverable,
    "补上回归测试后的第二版实现",
  )
  // 后续链路照常可用
  ignore(e.submit(task_id=id, now="2026-09-26T10:07:00Z"))
  assert_eq(r2e_fetch(e, id).status_to_string(), "待验收")
}

///|
/// 造一个处于指定状态的任务（纯域对象，按存储行字段构建；不碰库）。
/// 目的：把「谓词 can_execute」与「迁移 Task::execute」放在同一批状态上对拷，
/// 两条门以后只改一边就会在这里红。
fn r2e_task_in(id : String, st : @core.TaskStatus) -> @core.Task {
  @core.Task::from_db(
    id,
    None,
    "/p",
    "r2",
    "normal",
    "medium",
    1,
    3,
    st.to_string(),
    None,
    "守卫一致性夹具",
    "",
    "2026-09-26T10:00:00Z",
    "2026-09-26T10:00:00Z",
    None,
    "keep",
    [],
  )
}

///|
/// 按对外状态名取 can_execute（跨包直接构造 enum 构造子不便，且顺带锁
/// to_string/from_string 的闭环——状态名一旦被改，这里会 abort 而不是静默漏测）。
fn r2e_pred_by_name(name : String) -> Bool {
  match @core.TaskStatus::from_string(name) {
    Some(st) => st.can_execute()
    None => abort("状态名失效（to_string/from_string 漂移）: " + name)
  }
}

///|
test "BUG-2 守卫一致性：两条门对同一集合达成一致（谓词不再比迁移更宽）" {
  // 点名三态（防"全 true/全 false"的坏谓词冒充一致）
  assert_true(r2e_pred_by_name("执行中"))
  assert_true(r2e_pred_by_name("已领取"))
  assert_true(r2e_pred_by_name("拆分中"))
  assert_false(r2e_pred_by_name("已打回"))
  assert_false(r2e_pred_by_name("待领取"))
  assert_false(r2e_pred_by_name("已完成"))
  // 全量对拷：谓词与迁移在每个状态上同结论
  let names : Array[String] = [
    "待领取", "已领取", "拆分中", "执行中", "待验收", "已完成",
    "已归档", "已打回",
  ]
  for i = 0; i < names.length(); i = i + 1 {
    let nm = names[i]
    let st = match @core.TaskStatus::from_string(nm) {
      Some(s) => s
      None => abort("状态名失效: " + nm)
    }
    let t = r2e_task_in("T-guard-" + (i + 1).to_string(), st)
    // 夹具自检：状态必须真的按预期落位（否则整批对拷在比同一个状态＝假绿）
    assert_eq(t.get_status().to_string(), nm)
    let by_step = match t.execute() {
      Ok(_) => true
      Err(_) => false
    }
    assert_eq(st.can_execute(), by_step)
  }
}

///|
test "BUG-2 出路文案：已打回直接 execute 被拒，但必须告诉调用方怎么走" {
  let e = r2e_engine("temp/r2_bug2_c.db")
  let id = r2e_publish(e, "2026-09-26T10:00:00Z")
  ignore(e.claim(task_id=id, assignee="fixer", now="2026-09-26T10:01:00Z"))
  ignore(e.execute(task_id=id, deliverable="v1", now="2026-09-26T10:02:00Z"))
  ignore(e.submit(task_id=id, now="2026-09-26T10:03:00Z"))
  ignore(
    e.reject_task(
      task_id=id,
      reason="缺证据",
      by="verifier",
      now="2026-09-26T10:04:00Z",
    ),
  )
  match
    e.execute(
      task_id=id,
      deliverable="想直接盖过去",
      now="2026-09-26T10:05:00Z",
    ) {
    Ok(_) =>
      abort("已打回状态竟能直接 execute（守卫被放宽过头）")
    Err(m) => {
      assert_true(m.contains("retry"))
      assert_true(m.contains("出路"))
    }
  }
  // 未领取（待领取）也要给出 claim 出路
  let e2 = r2e_engine("temp/r2_bug2_d.db")
  let id2 = r2e_publish(e2, "2026-09-26T10:00:00Z")
  match e2.execute(task_id=id2, deliverable="x", now="2026-09-26T10:01:00Z") {
    Ok(_) => abort("待领取竟可 execute")
    Err(m) => {
      assert_true(m.contains("claim"))
      assert_true(m.contains("出路"))
    }
  }
}
