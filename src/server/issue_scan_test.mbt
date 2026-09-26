/// issue_scan_test.mbt —— 规则驱动源码扫描（issue_scan）测试
///
/// 约定：每个用例使用独立目录 temp/lint_cN，用例间互不污染、可重复运行。

///|
/// 准备用例目录（含一个主模块文件）。
fn lint_dir(name : String) -> String {
  @fs.create_dir("temp") catch {
    _ => ()
  }
  let d = "temp/" + name
  @fs.create_dir(d) catch {
    _ => ()
  }
  d
}

///|
/// 写一个模拟 .mbt 文件（注入多类高危模式，供规则命中）。
fn lint_seed(d : String) -> Unit {
  let body = "///\nfn unused(a:Int)->Int {\n  let x = 1 / 0\n  a\n}\n" +
    "fn risky(): Int {\n  let rows: Array[Int] = []\n  rows[0]\n}\n" +
    "fn g(): Int {\n  let ot = Option::Some(1)\n  ot.unwrap()\n}\n"
  @fs.write_string_to_file(d + "/sample.mbt", body, encoding="utf8") catch {
    _ => ()
  }
}

///|
test "lint_1_scan_hits_high_risk" {
  let d = lint_dir("lint_c1")
  lint_seed(d)
  let r = issue_scan(d, "", 100)
  // 不应报非法目录错误
  assert_true(r.is_ok())
  let j = match r {
    Ok(x) => x
    Err(_) => return
  }
  // scanned_files >= 1（sample.mbt）
  let scanned = mem_int(j, "scanned_files")
  assert_true(scanned >= 1)
  let total = mem_int(j, "total_findings")
  assert_true(total >= 1)
}

///|
test "lint_2_illegal_dir_rejected" {
  // 空目录 / 绝对路径 / 穿越都应返回 Err
  assert_true(issue_scan("", "", 100).is_err())
  assert_true(issue_scan("../x", "", 100).is_err())
  assert_true(issue_scan("C:/x", "", 100).is_err())
  assert_true(issue_scan("/abs", "", 100).is_err())
}

///|
test "lint_3_empty_dir_no_findings" {
  let d = lint_dir("lint_c3")
  let r = issue_scan(d, "", 100)
  assert_true(r.is_ok())
  let j = match r {
    Ok(x) => x
    Err(_) => return
  }
  assert_eq(mem_int(j, "scanned_files"), 0)
  assert_eq(mem_int(j, "total_findings"), 0)
}

///|
test "lint_4_test_file_skipped_by_default" {
  // 目录同时含产品文件与测试文件；测试文件带高危行
  let d = lint_dir("lint_c4")
  lint_seed(d) // sample.mbt（产品文件，命中）
  @fs.write_string_to_file(
    d + "/t_test.mbt",
    "fn tf(): Int {\n  let a: Array[Int] = []\n  a[0]\n}\n",
    encoding="utf8",
  ) catch {
    _ => ()
  }
  // 默认 include_tests=false：只扫到 sample.mbt（1 个）
  let r0 = issue_scan(d, "", 100)
  assert_true(r0.is_ok())
  let j0 = match r0 {
    Ok(x) => x
    Err(_) => return
  }
  assert_eq(mem_int(j0, "scanned_files"), 1)
  assert_eq(mem_bool(j0, "include_tests"), false)
  // include_tests=true：扫到 2 个（含 t_test.mbt）
  let r1 = issue_scan(d, "", 100, include_tests=true)
  assert_true(r1.is_ok())
  let j1 = match r1 {
    Ok(x) => x
    Err(_) => return
  }
  assert_eq(mem_int(j1, "scanned_files"), 2)
  assert_eq(mem_bool(j1, "include_tests"), true)
}
