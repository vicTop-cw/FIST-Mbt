/// bugreport_test.mbt —— report_bug / bug_list 测试
///
/// 覆盖：
///   1) report_bug 写入可被 bug_list 解析的条目（BUG-n / status OPEN / 字段）
///   2) 多次上报 → 序号递增（BUG-1 -> BUG-2）
///   3) publish_task=false 不发布任务（保持默认低风险）
///
/// 目录约定：独立目录 temp/bug_c1，可重复运行。

///|
fn bug_str(j : Json, key : String) -> String {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(String(s)) => s
        _ => "<null>"
      }
    _ => "<null>"
  }
}

///|
fn bug_arr(j : Json, key : String) -> Array[Json] {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(Array(a)) => a
        _ => []
      }
    _ => []
  }
}

///|
test "bug_report_list_roundtrip" {
  @fs.create_dir("temp") catch {
    _ => ()
  }
  let d = "temp/bug_c1"
  @fs.create_dir(d) catch {
    _ => ()
  }
  @fs.create_dir(d + "/memory") catch {
    _ => ()
  }
  @fs.remove_file(d + "/memory/bugs.md") catch {
    _ => ()
  }
  let eng = @engine.FistEngine::new()
  // 上报两条
  let j1 = match
    report_bug(
      d,
      "verify 阶段崩溃",
      detail="栈回溯…",
      severity="high",
      ref_call_id="42",
      reported_by="agentX",
      publish_task=false,
      eng,
      now="2026-09-24T00:00:00Z",
    ) {
    Ok(x) => x
    Err(m) => abort(m)
  }
  assert_eq(bug_str(j1, "bug_id"), "BUG-1")
  assert_eq(bug_str(j1, "status"), "OPEN")
  assert_true(bug_str(j1, "path").contains("memory/bugs.md"))
  let j2 = match
    report_bug(
      d,
      "list 返回空数组",
      detail="",
      severity="low",
      ref_call_id="",
      reported_by="",
      publish_task=false,
      eng,
      now="2026-09-24T00:00:01Z",
    ) {
    Ok(x) => x
    Err(m) => abort(m)
  }
  assert_eq(bug_str(j2, "bug_id"), "BUG-2")

  // 落盘文件可被解析
  let body = @fs.read_file_to_string(d + "/memory/bugs.md", encoding="utf8") catch {
    _ => abort("读 bugs.md 失败")
  }
  assert_true(body.contains("## BUG-1 [2026-09-24T00:00:00Z] [high] OPEN"))
  assert_true(body.contains("- summary: verify 阶段崩溃"))
  assert_true(body.contains("- ref_call: 42"))

  // bug_list 能读回
  let lj = match bug_list(d) {
    Ok(x) => x
    Err(m) => abort(m)
  }
  let arr = bug_arr(lj, "bugs")
  assert_eq(arr.length(), 2)
  assert_eq(bug_str(arr[0], "id"), "BUG-1")
  assert_eq(bug_str(arr[0], "severity"), "high")
  assert_eq(bug_str(arr[0], "status"), "OPEN")
  assert_eq(bug_str(arr[0], "summary"), "verify 阶段崩溃")
  assert_eq(bug_str(arr[1], "id"), "BUG-2")
  assert_eq(bug_str(arr[1], "summary"), "list 返回空数组")
}

///|
/// 非法 project_dir（路径穿）被拒；非法 severity 被拒。
test "bug_report_validation" {
  let eng = @engine.FistEngine::new()
  let r1 = report_bug(
    "../../etc",
    "x",
    detail="",
    severity="open",
    ref_call_id="",
    reported_by="",
    publish_task=false,
    eng,
    now="2026-09-24T00:00:00Z",
  )
  assert_true(r1 is Err(_))
  let r2 = report_bug(
    "temp/bug_c1",
    "x",
    detail="",
    severity="urgent",
    ref_call_id="",
    reported_by="",
    publish_task=false,
    eng,
    now="2026-09-24T00:00:00Z",
  )
  assert_true(r2 is Err(_))
}

///|
/// BUG-5 fix: report_bug / bug_list 返回值补 resolved_path 和 project_dir，
/// 让落点可审；同时 contract 描述明确 "相对 server 进程 cwd"。
test "bug5_report_bug_returns_resolved_path" {
  @fs.create_dir("temp") catch {
    _ => ()
  }
  let d = "temp/bug_c5"
  @fs.create_dir(d) catch {
    _ => ()
  }
  @fs.remove_file(d + "/memory/bugs.md") catch {
    _ => ()
  }
  let eng = @engine.FistEngine::new()
  let j = match
    report_bug(
      d,
      "BUG-5 验证",
      detail="",
      severity="high",
      ref_call_id="",
      reported_by="",
      publish_task=false,
      eng,
      now="2026-09-26T00:00:00Z",
    ) {
    Ok(x) => x
    Err(m) => abort(m)
  }
  // resolved_path 存在且是规范化后的相对路径
  let resolved = bug_str(j, "resolved_path")
  assert_true(resolved.contains("bug_c5"))
  assert_false(resolved.contains("\\")) // 反斜杠已规范化
  let pd = bug_str(j, "project_dir")
  assert_eq(pd, d)
  // bug_list 也带 resolved_path
  let lj = match bug_list(d) {
    Ok(x) => x
    Err(m) => abort(m)
  }
  assert_true(bug_str(lj, "resolved_path").contains("bug_c5"))
  assert_eq(bug_str(lj, "project_dir"), d)
}

///|
/// BUG-8 / BUG-11（调用面契约，不靠模块自述）：
///   · `task_ns` 决定修复单落在哪个 ns —— 传 batch-a 时 bugs ns 里必须一条都没有
///     （BUG-8 的原状是写死 ns="bugs"，按批次 ns 永远查不到修复单）；
///   · 返回体同时给 `bug_id` 与 `id`（BUG-11：写侧只发 bug_id、读侧只发 id，
///     按另一侧字段名对账的读方静默拿到 null）；
///   · `task_namespace` 在未发单时是空串而不是 "bugs"——回显的是实际落点，不是缺省值。
/// 前提：BUG-85 之后内存后端的 list_tasks/list_tasks_in 与 SQLite 同语义，
/// 所以"路由到哪"能在同一进程内测出来；旧语义下这条断言只会得到 all=0 的假象。
test "bug8_bug11_task_ns_echo_and_id_alias" {
  @fs.create_dir("temp") catch {
    _ => ()
  }
  let d = "temp/bug_c8"
  @fs.create_dir(d + "/memory") catch {
    _ => ()
  }
  @fs.remove_file(d + "/memory/bugs.md") catch {
    _ => ()
  }
  let eng = @engine.FistEngine::new()
  let j = match
    report_bug(
      d,
      "BUG-8 验证：修复单要能落进发起 ns",
      detail="ns 写死 bugs 时上卷永不触发",
      severity="medium",
      ref_call_id="",
      reported_by="phaseC",
      publish_task=true,
      task_ns="batch-a",
      eng,
      now="2026-09-27T00:00:00Z",
    ) {
    Ok(x) => x
    Err(m) => abort(m)
  }
  assert_eq(bug_str(j, "task_namespace"), "batch-a")
  assert_eq(bug_str(j, "bug_id"), bug_str(j, "id"))
  // task_id 的形态必须钉住：bug_str 对缺失键回 "<null>"，"非空"不等于"是真实根单 id"
  assert_true(bug_str(j, "task_id").has_prefix("T0"))
  // 修复单真的落在 batch-a，而不是 ns bugs
  assert_eq(eng.list_in_ns("batch-a").length(), 1)
  assert_eq(eng.list_in_ns("bugs").length(), 0)
  // 不传 task_ns 时回落到缺省 bugs（零回归）
  let eng2 = @engine.FistEngine::new()
  let j2 = match
    report_bug(
      d,
      "BUG-8 缺省路径",
      detail="",
      severity="low",
      ref_call_id="",
      reported_by="phaseC",
      publish_task=true,
      eng2,
      now="2026-09-27T00:00:01Z",
    ) {
    Ok(x) => x
    Err(m) => abort(m)
  }
  assert_eq(bug_str(j2, "task_namespace"), "bugs")
  assert_eq(eng2.list_in_ns("bugs").length(), 1)
  // publish_task=false 时不回显成 "bugs"：没有发单就没有落点
  let eng3 = @engine.FistEngine::new()
  let j3 = match
    report_bug(
      d,
      "BUG-8 未发单",
      detail="",
      severity="low",
      ref_call_id="",
      reported_by="phaseC",
      publish_task=false,
      eng3,
      now="2026-09-27T00:00:02Z",
    ) {
    Ok(x) => x
    Err(m) => abort(m)
  }
  assert_eq(bug_str(j3, "task_namespace"), "")
}

///|
/// BUG-11 + 记账规则（memory/bugs.md 顶部「记账规则」段）的读侧解析：
///   · bug_list 每行同时给 `id` 与 `bug_id`，值相等；
///   · DUPLICATE 抬头带的 `→BUG-m` 主编号拆成 `duplicate_of`，`status` 保持单值
///     （否则读侧按 status 计数时把 "DUPLICATE →BUG-5" 当成一个没见过的状态词）；
///   · FIXED / FALSE_POSITIVE 抬头不产 duplicate_of 键——少这一条断言，
///     "只在 DUPLICATE 上产字段"这件事就没有对照（恒产也恒绿）。
test "ledger_status_vocabulary_parses_duplicate_of" {
  @fs.create_dir("temp") catch {
    _ => ()
  }
  let d = "temp/bug_c_ledger"
  @fs.create_dir(d + "/memory") catch {
    _ => ()
  }
  @fs.write_string_to_file(
    d + "/memory/bugs.md",
    "# 缺陷账本（测试夹具）\n" +
    "\n" +
    "## BUG-1 [2026-09-26T00:00:00Z] [high] FIXED\n" +
    "- summary: 已修完的一条\n" +
    "- reported_by: phaseC\n" +
    "\n" +
    "## BUG-2 [2026-09-26T00:00:01Z] [medium] DUPLICATE →BUG-1\n" +
    "- summary: 与 BUG-1 同根因的一条\n" +
    "\n" +
    "## BUG-3 [2026-09-26T00:00:02Z] [low] FALSE_POSITIVE\n" +
    "- summary: 判据作用域误读的一条\n",
    encoding="utf8",
  ) catch {
    _ => abort("写夹具失败")
  }
  let lj = match bug_list(d) {
    Ok(x) => x
    Err(m) => abort(m)
  }
  let arr = bug_arr(lj, "bugs")
  assert_eq(arr.length(), 3)
  assert_eq(bug_str(arr[0], "id"), bug_str(arr[0], "bug_id"))
  assert_eq(bug_str(arr[0], "status"), "FIXED")
  assert_eq(bug_str(arr[1], "status"), "DUPLICATE")
  assert_eq(bug_str(arr[1], "duplicate_of"), "BUG-1")
  assert_eq(bug_str(arr[2], "status"), "FALSE_POSITIVE")
  // 反向对照：非 DUPLICATE 的条目不得凭空多出一个空 duplicate_of
  match arr[0] {
    Object(m) => assert_true(m.get("duplicate_of") is None)
    _ => abort("bug_list 行不是 object")
  }
}

///|
/// 注意这里 `(".", "temp/proj")` 的期望值**从 true 改成 false**：Round 1 版只要"不上跳、不绝对"
/// 就放行，于是 project_dir=temp/proj 的任务可以在 server cwd（整个仓库根）里跑命令——
/// 那不是"项目目录子树内"。Round 2 按子树判定后这种错配必须拒（完整矩阵见
/// run_check_guard_test.mbt；实测调用面里也不存在这种传法：workdir 恒等于 project_dir 或 `.`）。
test "bug4_run_check_workdir_ok" {
  assert_false(run_check_workdir_ok(".", "temp/proj"))
  assert_true(run_check_workdir_ok("temp/proj", "temp/proj"))
  assert_true(run_check_workdir_ok("temp/proj/scripts", "temp/proj"))
  assert_false(run_check_workdir_ok("", "temp/proj"))
  assert_false(run_check_workdir_ok("../outside", "temp/proj"))
  assert_false(run_check_workdir_ok("..", "temp/proj"))
  assert_false(run_check_workdir_ok("/abs/path", "temp/proj"))
  assert_false(run_check_workdir_ok("C:/Windows", "temp/proj"))
  // Round 1 会误拒、Round 2 必须放行：绝对 project_dir 本身（实测调用面主形态）
  assert_true(
    run_check_workdir_ok("E:/IDEProjects/AI/Cypy", "E:/IDEProjects/AI/Cypy"),
  )
}
