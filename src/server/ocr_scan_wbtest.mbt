///|
/// ocr_scan_wbtest.mbt —— ocr_scan 工具白盒测试（纯计算层，不 spawn 真实进程）
///
/// 覆盖：子命令白名单 / argv 形状（scan/files/delegate/rules）/ 非法入参 Err /
/// project_dir 防御 / stdout JSON files 解析。IO 层（探测 + spawn）在 MCP 冒烟里验证。

///|
test "ocr_subcmds_whitelist" {
  let s = ocr_subcmds()
  assert_eq(s.length(), 4)
  assert_true(s.contains("scan"))
  assert_true(s.contains("files"))
  assert_true(s.contains("delegate"))
  assert_true(s.contains("rules"))
  assert_true(is_ocr_subcmd("scan"))
  assert_true(is_ocr_subcmd("files"))
  assert_true(is_ocr_subcmd("delegate"))
  assert_true(is_ocr_subcmd("rules"))
  assert_false(is_ocr_subcmd("review"))
  assert_false(is_ocr_subcmd(""))
}

///|
test "ocr_build_args_scan_shape" {
  let a = match ocr_build_args(project_dir="src", subcmd="files") {
    Ok(v) => v
    Err(e) => abort("unexpected Err: " + e)
  }
  assert_eq(a.length(), 6)
  assert_eq(a[0], "scan")
  assert_eq(a[1], "--repo")
  assert_eq(a[2], "src")
  assert_eq(a[3], "--preview")
  assert_eq(a[4], "--format")
  assert_eq(a[5], "json")
  // 带 path 与 rules_file
  let b = match
    ocr_build_args(
      project_dir=".",
      subcmd="scan",
      path="server/ocr_scan.mbt",
      rules_file="rules/moonbit-rules.json",
    ) {
    Ok(v) => v
    Err(e) => abort("unexpected Err: " + e)
  }
  assert_eq(b.length(), 10)
  assert_eq(b[6], "--path")
  assert_eq(b[7], "server/ocr_scan.mbt")
  assert_eq(b[8], "--rule")
  assert_eq(b[9], "rules/moonbit-rules.json")
}

///|
test "ocr_build_args_delegate_shape" {
  let a = match
    ocr_build_args(
      project_dir="src",
      subcmd="delegate",
      path="server/ocr_scan.mbt, server/issue_scan.mbt",
    ) {
    Ok(v) => v
    Err(e) => abort("unexpected Err: " + e)
  }
  // delegate rule --repo src server/ocr_scan.mbt server/issue_scan.mbt
  assert_eq(a.length(), 6)
  assert_eq(a[0], "delegate")
  assert_eq(a[1], "rule")
  assert_eq(a[2], "--repo")
  assert_eq(a[3], "src")
  assert_eq(a[4], "server/ocr_scan.mbt")
  assert_eq(a[5], "server/issue_scan.mbt")
}

///|
test "ocr_build_args_rules_shape" {
  let a = match
    ocr_build_args(
      project_dir="src",
      subcmd="rules",
      path="server/ocr_scan.mbt",
    ) {
    Ok(v) => v
    Err(e) => abort("unexpected Err: " + e)
  }
  assert_eq(a.length(), 3)
  assert_eq(a[0], "rules")
  assert_eq(a[1], "check")
  assert_eq(a[2], "server/ocr_scan.mbt")
}

///|
test "ocr_build_args_bad_input_err" {
  // 未知子命令
  let r1 = ocr_build_args(project_dir="src", subcmd="review")
  assert_false(r1.is_ok())
  // delegate 缺 path
  let r2 = ocr_build_args(project_dir="src", subcmd="delegate")
  assert_false(r2.is_ok())
  // rules 缺 path
  let r3 = ocr_build_args(project_dir="src", subcmd="rules")
  assert_false(r3.is_ok())
}

///|
test "ocr_dir_ok_defense" {
  assert_true(ocr_dir_ok("."))
  assert_true(ocr_dir_ok("src"))
  assert_true(ocr_dir_ok("src/server"))
  assert_false(ocr_dir_ok(""))
  assert_false(ocr_dir_ok("../etc"))
  assert_false(ocr_dir_ok("/abs/path"))
  assert_false(ocr_dir_ok("C:/windows"))
  assert_false(ocr_dir_ok("\\server\\share"))
}

///|
test "ocr_extract_files_parse" {
  let j = "{\"files\":[{\"path\":\"core/core_principle.mbt\",\"status\":\"scan\"},{\"path\":\"server/ocr_scan.mbt\",\"status\":\"scan\"}]}"
  let files = ocr_extract_files(j)
  assert_eq(files.length(), 2)
  assert_eq(files[0], "core/core_principle.mbt")
  assert_eq(files[1], "server/ocr_scan.mbt")
  // 非法 JSON → 空数组（不报错）
  assert_eq(ocr_extract_files("not json").length(), 0)
  // 无 files 键 → 空数组
  assert_eq(ocr_extract_files("{\"other\":1}").length(), 0)
}

///|
test "ocr_plan_bad_project_dir" {
  // 非法 project_dir 直接失败（不发进程）；ocr_scan_impl 的 async spawn 面由 MCP 冒烟验证
  let j = ocr_plan("../etc", subcmd="files", dry_run=true)
  let m = match j {
    Json::Object(mm) => mm
    _ => abort("not object")
  }
  assert_eq(m.get("ok"), Some(Json::boolean(false)))
  assert_eq(m.get("ocr_available"), Some(Json::boolean(false)))
  let err = match m.get("error") {
    Some(Json::String(s)) => s
    _ => abort("no error")
  }
  assert_true(err.contains("project_dir"))
}

///|
test "ocr_plan_bad_subcmd" {
  let j = ocr_plan(".", subcmd="review", dry_run=true)
  let m = match j {
    Json::Object(mm) => mm
    _ => abort("not object")
  }
  assert_eq(m.get("ok"), Some(Json::boolean(false)))
  assert_eq(m.get("ocr_available"), Some(Json::boolean(false)))
}

///|
test "ocr_plan_dry_run_argv" {
  let j = ocr_plan("src", subcmd="files", dry_run=true)
  let m = match j {
    Json::Object(mm) => mm
    _ => abort("not object")
  }
  assert_eq(m.get("ok"), Some(Json::boolean(true)))
  assert_eq(m.get("dry_run"), Some(Json::boolean(true)))
  assert_eq(m.get("exit_code"), Some(Json::number(0.0)))
  let args = match m.get("args") {
    Some(Json::Array(a)) => a
    _ => abort("no args")
  }
  assert_eq(args.length(), 6)
  let first = match args[0] {
    Json::String(s) => s
    _ => abort("args[0] not string")
  }
  assert_eq(first, "scan")
}
