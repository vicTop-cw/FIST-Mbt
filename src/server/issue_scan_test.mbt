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
  let r = @server.issue_scan(d, "", 100)
  // 不应报非法目录错误
  assert_true(r is Ok(_))
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
<<<<<<< HEAD
<<<<<<< HEAD
=======
>>>>>>> f336923b (fix(test-idiom): 清零 0025 test_unqualified_package 全族 803 处（BUG-346）)
  assert_true(@server.issue_scan("", "", 100) is Err(_))
  assert_true(@server.issue_scan("../x", "", 100) is Err(_))
  assert_true(@server.issue_scan("C:/x", "", 100) is Err(_))
  assert_true(@server.issue_scan("/abs", "", 100) is Err(_))
<<<<<<< HEAD
=======
  assert_true(issue_scan("", "", 100) is Err(_))
  assert_true(issue_scan("../x", "", 100) is Err(_))
  assert_true(issue_scan("C:/x", "", 100) is Err(_))
  assert_true(issue_scan("/abs", "", 100) is Err(_))
>>>>>>> 5f29de2e (fix(test): 适配 moonc 0.10.16 的 Result API —— is_ok/is_err 迁移 + 拆 try? 化石语法 (BUG-328))
=======
>>>>>>> f336923b (fix(test-idiom): 清零 0025 test_unqualified_package 全族 803 处（BUG-346）)
}

///|
test "lint_3_empty_dir_no_findings" {
  let d = lint_dir("lint_c3")
<<<<<<< HEAD
<<<<<<< HEAD
  let r = @server.issue_scan(d, "", 100)
=======
  let r = issue_scan(d, "", 100)
>>>>>>> 5f29de2e (fix(test): 适配 moonc 0.10.16 的 Result API —— is_ok/is_err 迁移 + 拆 try? 化石语法 (BUG-328))
=======
  let r = @server.issue_scan(d, "", 100)
>>>>>>> f336923b (fix(test-idiom): 清零 0025 test_unqualified_package 全族 803 处（BUG-346）)
  assert_true(r is Ok(_))
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
<<<<<<< HEAD
<<<<<<< HEAD
  let r0 = @server.issue_scan(d, "", 100)
=======
  let r0 = issue_scan(d, "", 100)
>>>>>>> 5f29de2e (fix(test): 适配 moonc 0.10.16 的 Result API —— is_ok/is_err 迁移 + 拆 try? 化石语法 (BUG-328))
=======
  let r0 = @server.issue_scan(d, "", 100)
>>>>>>> f336923b (fix(test-idiom): 清零 0025 test_unqualified_package 全族 803 处（BUG-346）)
  assert_true(r0 is Ok(_))
  let j0 = match r0 {
    Ok(x) => x
    Err(_) => return
  }
  assert_eq(mem_int(j0, "scanned_files"), 1)
  assert_eq(mem_bool(j0, "include_tests"), false)
  // include_tests=true：扫到 2 个（含 t_test.mbt）
<<<<<<< HEAD
<<<<<<< HEAD
  let r1 = @server.issue_scan(d, "", 100, include_tests=true)
=======
  let r1 = issue_scan(d, "", 100, include_tests=true)
>>>>>>> 5f29de2e (fix(test): 适配 moonc 0.10.16 的 Result API —— is_ok/is_err 迁移 + 拆 try? 化石语法 (BUG-328))
=======
  let r1 = @server.issue_scan(d, "", 100, include_tests=true)
>>>>>>> f336923b (fix(test-idiom): 清零 0025 test_unqualified_package 全族 803 处（BUG-346）)
  assert_true(r1 is Ok(_))
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
<<<<<<< HEAD
<<<<<<< HEAD
  let r = @server.issue_scan(d, "", 100)
=======
  let r = issue_scan(d, "", 100)
>>>>>>> 5f29de2e (fix(test): 适配 moonc 0.10.16 的 Result API —— is_ok/is_err 迁移 + 拆 try? 化石语法 (BUG-328))
=======
  let r = @server.issue_scan(d, "", 100)
>>>>>>> f336923b (fix(test-idiom): 清零 0025 test_unqualified_package 全族 803 处（BUG-346）)
  assert_true(r is Ok(_))
  let j = match r {
    Ok(x) => x
    Err(_) => return
  }
  let items = lint_findings(j)
  // 注释行 1/2/3 一条都不该出现；允许代码行（fn/let/rows）命中
  // （含 2026-10-13 ocr-local 融合规则 moonbit-long-function "fn " 等泛 needle）
  assert_true(items.length() >= 1)
  for f in items {
    let ln = lint_line(f)
    assert_true(ln != 1 && ln != 2 && ln != 3)
  }
  assert_true(items.any(fn(f) { mem_str(f, "severity") == "high" }))
}

///|
test "lint_6_rules_table_never_self_hits_bug15" {
  // 扫真实仓库 src/server：扫描器自己的规则表文件不得再贡献命中（pattern/hint 字面量自命中）。
  // 前置哨兵：scanned_files>0 —— 否则「没扫到」会被当成「没有自噪声」而假绿。
<<<<<<< HEAD
<<<<<<< HEAD
  let r = @server.issue_scan("src/server", "", 300)
=======
  let r = issue_scan("src/server", "", 300)
>>>>>>> 5f29de2e (fix(test): 适配 moonc 0.10.16 的 Result API —— is_ok/is_err 迁移 + 拆 try? 化石语法 (BUG-328))
=======
  let r = @server.issue_scan("src/server", "", 300)
>>>>>>> f336923b (fix(test-idiom): 清零 0025 test_unqualified_package 全族 803 处（BUG-346）)
  assert_true(r is Ok(_))
  let j = match r {
    Ok(x) => x
    Err(_) => return
  }
  assert_true(mem_int(j, "scanned_files") > 0)
  assert_true(!lint_any_file_suffix(lint_findings(j), "issue_scan.mbt"))
}

///|
test "lint_7_no_high_hits_left_in_src_omega_bug15" {
  // 真实仓库 src/omega：spec.mbt:23 的 doc 注释（含 "/ 0"）曾被判 div-by-zero(high)，
  // spec.mbt:69/70 的 unsafe_get 与 :378/392 的 counts[0] 均有前置守卫（本轮逐条实跑复核为误报）。
  // 修复后 high 档应为 0（by_severity.high 与逐条 findings 双查，防聚合与明细不一致）。
<<<<<<< HEAD
<<<<<<< HEAD
  let r = @server.issue_scan("src/omega", "", 300)
=======
  let r = issue_scan("src/omega", "", 300)
>>>>>>> 5f29de2e (fix(test): 适配 moonc 0.10.16 的 Result API —— is_ok/is_err 迁移 + 拆 try? 化石语法 (BUG-328))
=======
  let r = @server.issue_scan("src/omega", "", 300)
>>>>>>> f336923b (fix(test-idiom): 清零 0025 test_unqualified_package 全族 803 处（BUG-346）)
  assert_true(r is Ok(_))
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

///|
/// 守卫感知过滤回归（2026-10-10）：`if is_empty()` / `if length() > N` 之后的
/// rows[0] / substring(0,N) 应被就地过滤；无守卫的同形代码仍须命中——证明
/// 「消噪」不是「不扫了」。
test "lint_8_guard_filter_keeps_real_hits_drops_guarded" {
  let d = lint_dir("lint_c8")
  @fs.write_string_to_file(
    d + "/sample.mbt",
    "fn guarded(): Int {\n" +
    "  let rows : Array[Int] = []\n" +
    "  if rows.is_empty() { return -1 }\n" +
    "  rows[0]\n" +
    "}\n" +
    "fn unguarded(): Int {\n" +
    "  let rows : Array[Int] = []\n" +
    "  rows[0]\n" +
    "}\n",
    encoding="utf8",
  ) catch {
    _ => ()
  }
<<<<<<< HEAD
<<<<<<< HEAD
  let r = @server.issue_scan(d, "", 100)
=======
  let r = issue_scan(d, "", 100)
>>>>>>> 5f29de2e (fix(test): 适配 moonc 0.10.16 的 Result API —— is_ok/is_err 迁移 + 拆 try? 化石语法 (BUG-328))
=======
  let r = @server.issue_scan(d, "", 100)
>>>>>>> f336923b (fix(test-idiom): 清零 0025 test_unqualified_package 全族 803 处（BUG-346）)
  assert_true(r is Ok(_))
  let j = match r {
    Ok(x) => x
    Err(_) => return
  }
  let items = lint_findings(j)
  // 守卫过滤语义：index-out-of-bounds 只应命中 unguarded 第 8 行，guarded 第 4 行被过滤；
  // ocr-local 融合规则（"fn " 等泛 needle）命中定义行不干扰本守卫语义
  assert_true(items.length() >= 1)
  for f in items {
    if mem_str(f, "rule") == "index-out-of-bounds" {
      assert_eq(lint_line(f), 8)
    }
  }
}

///|
/// 单测：scan_finding_guarded 直接行为——守卫行在上一行应判 guarded=true；
/// 无守卫应判 false。绕过整文件集成，直接测函数。
test "lint_10_guard_function_direct" {
  // guarded: 守卫在前一行
  // prev_lines 只放**命中行之前**的代码行；本函数从最近一行往回扫。
  // 守卫在 rows[0] 的**上一行**：`if rows.is_empty() { return -1 }`
  let prev_guarded : Array[String] = ["  if rows.is_empty() { return -1 }"]
  // 上一行有 is_empty() 守卫应判 guarded
  assert_true(
    @server.scan_finding_guarded("rows[0]", "index-out-of-bounds", prev_guarded),
  )
  // 无守卫：上一行只是声明
  let prev_unguarded : Array[String] = [
    "fn unguarded(): Int {", "  let rows : Array[Int] = []",
  ]
  assert_eq(
    @server.scan_finding_guarded(
      "rows[0]", "index-out-of-bounds", prev_unguarded,
    ),
    false,
  )
  // 跨函数守卫应被停：上一行是 `fn ` 边界
  let prev_cross_fn : Array[String] = [
    "  let rows : Array[Int] = []", "  if rows.is_empty() { return -1 }", "}", "fn next(): Int {",
  ]
  assert_eq(
    @server.scan_finding_guarded(
      "rows[0]", "index-out-of-bounds", prev_cross_fn,
    ),
    false,
  )
  // unguarded: 前一函数里的守卫跨了 `fn` 边界，不应算
  let unguarded_lines : Array[String] = [
    "fn guarded(): Int {", "  let rows : Array[Int] = []", "  if rows.is_empty() { return -1 }",
    "  rows[0]", "}", "fn unguarded(): Int {", "  let rows : Array[Int] = []", "  rows[0]",
    "}",
  ]
  // 第 8 行 rows[0]（unguarded）：只应看第 7/6/5 行，见到 `fn ` 边界应停
  let prev_for_8 : Array[String] = [
    "fn unguarded(): Int {", "  let rows : Array[Int] = []",
  ]
  assert_eq(
    @server.scan_finding_guarded("rows[0]", "index-out-of-bounds", prev_for_8),
    false,
  )
}

///|
/// substring 守卫回归：`if s.length() > 8` 之后的 substring(0,8) 应被过滤；
/// 无守卫的 substring(0,8) 仍须命中。
test "lint_9_substring_guard_filter" {
  let d = lint_dir("lint_c9")
  @fs.write_string_to_file(
    d + "/sample.mbt",
    "fn guarded(s : String) -> String {\n" +
    "  if s.length() > 8 { s[0:8].to_string() } else { s }\n" +
    "}\n" +
    "fn unguarded(s : String) -> String {\n" +
    "  s[0:8].to_string()\n" +
    "}\n",
    encoding="utf8",
  ) catch {
    _ => ()
  }
<<<<<<< HEAD
<<<<<<< HEAD
  let r = @server.issue_scan(d, "", 100)
=======
  let r = issue_scan(d, "", 100)
>>>>>>> 5f29de2e (fix(test): 适配 moonc 0.10.16 的 Result API —— is_ok/is_err 迁移 + 拆 try? 化石语法 (BUG-328))
=======
  let r = @server.issue_scan(d, "", 100)
>>>>>>> f336923b (fix(test-idiom): 清零 0025 test_unqualified_package 全族 803 处（BUG-346）)
  assert_true(r is Ok(_))
  let j = match r {
    Ok(x) => x
    Err(_) => return
  }
  let items = lint_findings(j)
  // 守卫过滤语义：substring-overrun 只应命中 unguarded 第 5 行，guarded 第 2 行被过滤
  assert_true(items.length() >= 1)
  for f in items {
    if mem_str(f, "rule") == "substring-overrun" {
      assert_eq(lint_line(f), 5)
    }
  }
}

///|
/// BUG-222 回归锁：目标目录不存在（或不可读）时，issue_scan 必须返回 Err，
/// 而不是 Ok(scanned_files=0) 的"假干净"结果误导调用方。
/// 该目录从不会被创建，因此必然不存在。
test "lint_10_missing_dir_returns_err" {
  let d = "temp/lint_bug222_missing_dir"
<<<<<<< HEAD
<<<<<<< HEAD
  let r = @server.issue_scan(d, "", 100)
=======
  let r = issue_scan(d, "", 100)
>>>>>>> 5f29de2e (fix(test): 适配 moonc 0.10.16 的 Result API —— is_ok/is_err 迁移 + 拆 try? 化石语法 (BUG-328))
=======
  let r = @server.issue_scan(d, "", 100)
>>>>>>> f336923b (fix(test-idiom): 清零 0025 test_unqualified_package 全族 803 处（BUG-346）)
  assert_true(r is Err(_))

  // ---------------------------------------------------------------------------
  // BUG-268：substring-overrun medium 档假阳性消除（三类守卫）+ 真阳性保留
  // ---------------------------------------------------------------------------

}

///|
/// 断言 items 中 rule=="substring-overrun" 的命中里不存在 file 与 code 都匹配的那条。
/// code 为 contains 匹配（容忍行号漂移），file 为 has_suffix（容忍相对路径前缀）。
fn lint_268_no_medium(
  items : Array[Json],
  file_suffix : String,
  code_frag : String,
) -> Unit {
  for f in items {
    let is_sub = mem_str(f, "rule") == "substring-overrun" &&
      mem_str(f, "severity") == "medium"
    if !is_sub {
      continue
    }
    let fp = match f.value("file") {
      Some(String(s)) => s.has_suffix(file_suffix)
      _ => false
    }
    if fp && mem_str(f, "code").contains(code_frag) {
      abort(
        "BUG-268 假阳性未消除：" +
        file_suffix +
        " 仍报 substring-overrun: " +
        mem_str(f, "code"),
      )
    }
  }
}

///|
/// BUG-268 形态 D：多行 if-else 长度守卫（memory_gc_logic 形状）。
/// prev_lines 故意用**生产路径的倒序近邻窗口**（最近行在前）——这正是原实现的盲区：
/// `} else {` 出现在 `if n <= max_chars {` **之前**，前向 else 扫描会漏判。
test "lint_11_bug268_multiline_ifelse_length_fp_eliminated" {
  let code = "content.substring(start=n - cut, end=n),"
  let prev : Array[String] = [
    "    (", "    let cut = if max_chars < 0 { 0 } else { max_chars }", "  } else {",
    "    (content, \"\")", "  if n <= max_chars {", "  let n = content.length()",
    "pub fn memory_gc_logic(content : String, max_chars : Int) {",
  ]
  assert_true(
    @server.scan_finding_guarded(code, "substring-overrun", prev),
    msg="BUG-268 形态 D：倒序窗口下的多行 if-else 守卫应被识别",
  )
  // 无 else 分支（或守卫与长度无关）的同形代码仍须判为未守卫
  let unguarded : Array[String] = [
    "    (", "    let cut = max_chars", "  ", "  let n = content.length()", "pub fn memory_gc_logic(content : String, max_chars : Int) {",
  ]
  assert_eq(
    @server.scan_finding_guarded(
      "content.substring(start=n - cut, end=n)", "substring-overrun", unguarded,
    ),
    false,
  )
}

///|
/// BUG-268 形态 A：模运算不变量（mcs_hex4 形状）。`d = rem % 16` 使 d ∈ [0,15]，
/// 恒为 16 字符 hex 串的合法下标。
test "lint_12_bug268_mod_invariant_fp_eliminated" {
  let code = "out = hex.substring(start=d, end=d + 1) + out"
  let prev : Array[String] = [
    "    let d = rem % 16", "  while rem > 0 {", "  let mut out = \"\"", "  let mut rem = n",
    "  let hex = \"0123456789abcdef\"", "fn mcs_hex4(n : Int) -> String {",
  ]
  assert_true(
    @server.scan_finding_guarded(code, "substring-overrun", prev),
    msg="BUG-268 形态 A：`x % k` 模运算区间应被识别",
  )
  // 无模运算定义时不得豁免
  assert_eq(
    @server.scan_finding_guarded(
      "out = hex.substring(start=d, end=d + 1) + out",
      "substring-overrun",
      ["    let d = n - 3", "  let hex = \"0123456789abcdef\""],
    ),
    false,
  )
}

///|
/// BUG-268 形态 B/C：`end` 来自 `find("]")` 的位置，守卫 `if end > 3` 通过
/// 另一变量的不等式间接保证 `substring(start=3, end~)` 安全（ops_selfdrive 形状）。
test "lint_13_bug268_find_endvar_fp_eliminated" {
  let code = "let desc = ls.substring(start=3, end~).trim().to_string()"
  let prev : Array[String] = [
    "          if end > 3 {", "        Some(end) =>", "      match ls.find(\"]\") {",
    "    let ls = l.to_string()",
  ]
  assert_true(
    @server.scan_finding_guarded(code, "substring-overrun", prev),
    msg="BUG-268 形态 B/C：find() 位置守卫应被识别",
  )
}

///|
/// BUG-268 负向锁：真越界 substring 不得因上述三类守卫被误豁免。
test "lint_14_bug268_true_positive_still_hits" {
  // 有 is_empty 守卫（不相关）但 substring 无长度守卫 → 仍应命中
  let d = lint_dir("lint_c14")
  @fs.write_string_to_file(
    d + "/sample.mbt",
    "fn risky(s : String, t : String) -> String {\n" +
    "  let rows : Array[Int] = []\n" +
    "  if rows.is_empty() { return t }\n" +
    "  let cut = max_chars\n" +
    "  let n = s.length()\n" +
    "  s.substring(start=n - cut, end=n)\n" +
    "}\n",
    encoding="utf8",
  ) catch {
    _ => ()
  }
<<<<<<< HEAD
<<<<<<< HEAD
  let r = @server.issue_scan(d, "", 100)
=======
  let r = issue_scan(d, "", 100)
>>>>>>> 5f29de2e (fix(test): 适配 moonc 0.10.16 的 Result API —— is_ok/is_err 迁移 + 拆 try? 化石语法 (BUG-328))
=======
  let r = @server.issue_scan(d, "", 100)
>>>>>>> f336923b (fix(test-idiom): 清零 0025 test_unqualified_package 全族 803 处（BUG-346）)
  assert_true(r is Ok(_))
  let j = match r {
    Ok(x) => x
    Err(_) => return
  }
  let items = lint_findings(j)
  assert_true(
    items.any(fn(f) {
      mem_str(f, "rule") == "substring-overrun" &&
      mem_str(f, "code").contains("s.substring(start=n - cut, end=n)")
    }),
    msg="无守卫的真越界 substring 仍须命中",
  )
}

///|
/// BUG-268 端到端：对真实样本点所在目录做 issue_scan，确认三个已知假阳性已消除。
/// 只按 file 后缀 + code 片段匹配（不钉行号），行号漂移不误红。
test "lint_15_bug268_real_samples_no_fp" {
<<<<<<< HEAD
<<<<<<< HEAD
  let r_server = @server.issue_scan("src/server", "", 300)
=======
  let r_server = issue_scan("src/server", "", 300)
>>>>>>> 5f29de2e (fix(test): 适配 moonc 0.10.16 的 Result API —— is_ok/is_err 迁移 + 拆 try? 化石语法 (BUG-328))
=======
  let r_server = @server.issue_scan("src/server", "", 300)
>>>>>>> f336923b (fix(test-idiom): 清零 0025 test_unqualified_package 全族 803 处（BUG-346）)
  assert_true(r_server is Ok(_))
  let j_server = match r_server {
    Ok(x) => x
    Err(_) => return
  }
  assert_true(mem_int(j_server, "scanned_files") > 0)
  // memory_gc_logic（形态 D）
  lint_268_no_medium(lint_findings(j_server), "memory.mbt", "start=n - cut")
  // mcs_hex4（形态 A）
  lint_268_no_medium(
    lint_findings(j_server),
    "mcp_config_scaffold.mbt",
    "start=d",
  )
<<<<<<< HEAD
<<<<<<< HEAD
  let r_ops = @server.issue_scan("src/ops", "", 300)
=======
  let r_ops = issue_scan("src/ops", "", 300)
>>>>>>> 5f29de2e (fix(test): 适配 moonc 0.10.16 的 Result API —— is_ok/is_err 迁移 + 拆 try? 化石语法 (BUG-328))
=======
  let r_ops = @server.issue_scan("src/ops", "", 300)
>>>>>>> f336923b (fix(test-idiom): 清零 0025 test_unqualified_package 全族 803 处（BUG-346）)
  assert_true(r_ops is Ok(_))
  let j_ops = match r_ops {
    Ok(x) => x
    Err(_) => return
  }
  assert_true(mem_int(j_ops, "scanned_files") > 0)
  // selfdrive（形态 B/C）
  lint_268_no_medium(
    lint_findings(j_ops),
    "ops_selfdrive.mbt",
    "substring(start=3, end~)",
  )
}
