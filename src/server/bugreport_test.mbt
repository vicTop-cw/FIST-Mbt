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
/// BUG-4 fix: run_check workdir 非法时应被拒绝（通过 workdir_ok 函数验证）。
test "bug4_run_check_workdir_ok" {
  assert_true(run_check_workdir_ok(".", "temp/proj"))
  assert_true(run_check_workdir_ok("temp/proj", "temp/proj"))
  assert_false(run_check_workdir_ok("", "temp/proj"))
  assert_false(run_check_workdir_ok("../outside", "temp/proj"))
  assert_false(run_check_workdir_ok("..", "temp/proj"))
  assert_false(run_check_workdir_ok("/abs/path", "temp/proj"))
  assert_false(run_check_workdir_ok("C:/Windows", "temp/proj"))
}
