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

///|
/// BUG-15 加固：取 findings 数组（结构异常返回空）。
fn lint_findings(j : Json) -> Array[Json] {
  match j.value("findings") {
    Some(Array(a)) => a
    _ => []
  }
}

///|
/// BUG-15 加固：命中是否落在指定文件后缀上。
fn lint_any_file_suffix(items : Array[Json], suffix : String) -> Bool {
  items.any(fn(f) {
    match f.value("file") {
      Some(String(s)) => s.has_suffix(suffix)
      _ => false
    }
  })
}

///|
/// 命中行号（缺失返回 -1）。
fn lint_line(f : Json) -> Int {
  match f.value("line") {
    Some(Number(n, ..)) => n.to_int()
    _ => -1
  }
}

///|
test "lint_5_comment_lines_are_not_matched_bug15" {
  // 整行注释里的 pattern 字面量（doc 注释散文含 "/ 0"、"rows[0]"）不得命中；
  // 同文件里的真实代码行仍须命中——证明是「跳注释」而不是「不扫了」。
  let d = lint_dir("lint_c5")
  @fs.write_string_to_file(
    d + "/sample.mbt",
    "/// 哈希常量与 Python 完全一致（0xcbf29ce484222325 / 0x100000001b3）\n" +
    "/// 空数组下标写法 rows[0] 会 panic\n" +
    "// 行注释里也写 rows[0]\n" +
    "fn risky(): Int {\n" +
    "  let rows : Array[Int] = []\n" +
    "  rows[0]\n" +
    "}\n",
    encoding="utf8",
  ) catch {
    _ => ()
  }
  let r = issue_scan(d, "", 100)
  assert_true(r.is_ok())
  let j = match r {
    Ok(x) => x
    Err(_) => return
  }
  let items = lint_findings(j)
  // 注释行 1/2/3 一条都不该出现；只允许真实代码行（第 6 行）命中
  assert_true(items.length() >= 1)
  for f in items {
    assert_eq(lint_line(f), 6)
  }
  assert_true(items.any(fn(f) { mem_str(f, "severity") == "high" }))
}

///|
test "lint_6_rules_table_never_self_hits_bug15" {
  // 扫真实仓库 src/server：扫描器自己的规则表文件不得再贡献命中（pattern/hint 字面量自命中）。
  // 前置哨兵：scanned_files>0 —— 否则「没扫到」会被当成「没有自噪声」而假绿。
  let r = issue_scan("src/server", "", 300)
  assert_true(r.is_ok())
  let j = match r {
    Ok(x) => x
    Err(_) => return
  }
  assert_true(mem_int(j, "scanned_files") > 0)
  assert_true(not(lint_any_file_suffix(lint_findings(j), "issue_scan.mbt")))
}

///|
test "lint_7_no_high_hits_left_in_src_omega_bug15" {
  // 真实仓库 src/omega：spec.mbt:23 的 doc 注释（含 "/ 0"）曾被判 div-by-zero(high)，
  // spec.mbt:69/70 的 unsafe_get 与 :378/392 的 counts[0] 均有前置守卫（本轮逐条实跑复核为误报）。
  // 修复后 high 档应为 0（by_severity.high 与逐条 findings 双查，防聚合与明细不一致）。
  let r = issue_scan("src/omega", "", 300)
  assert_true(r.is_ok())
  let j = match r {
    Ok(x) => x
    Err(_) => return
  }
  assert_true(mem_int(j, "scanned_files") > 0)
  let items = lint_findings(j)
  for f in items {
    if mem_str(f, "severity") == "high" {
      abort(
        "high 档不应再出现：" +
        mem_str(f, "rule") +
        " " +
        mem_str(f, "file") +
        ":" +
        lint_line(f).to_string(),
      )
    }
  }
  let high = match j.value("by_severity") {
    Some(Object(m)) =>
      match m.get("high") {
        Some(Number(n, ..)) => n.to_int()
        _ => -1
      }
    _ => -1
  }
  assert_eq(high, 0)
}
