/// issue_scan_wbtest.mbt —— BUG-72 的成对锁：命中只算字符串字面量**之外**的出现。
///
/// 光看 issue_scan 的集成结果分不出"规则不命中"和"匹配器被关掉"，所以这里直接考
/// scan_outside_literal 这一层，正反两向都要钉住：
///   必须抓到：真代码行（`rows[0]`、`x / 0`、`.substring(`）
///   必须不抓：写在描述文案里的同一串字面量

///|
/// 一个双引号字符。用它拼夹具，别在字面量里连环转义（MoonBit 的 `\"` 在多层嵌套里极易写歪）。
fn q() -> String {
  "\""
}

///|
test "scan_literal_boundary_真代码行必须命中" {
  assert_true(scan_outside_literal("  rows[0]"[:], "rows[0]"))
  assert_true(scan_outside_literal("  let x = 1 / 0"[:], "/ 0"))
  assert_true(
    scan_outside_literal("  s.substring(start=0, end=n)"[:], "substring("),
  )
  // 一行里引号外也有、引号内也有：引号外那次算命中（不能因为行里有引号就整行放过）
  let mixed = "  ot.unwrap() // 文案里也写了 " + q() + ".unwrap()" + q()
  assert_true(scan_outside_literal(mixed[:], ".unwrap()"))
}

///|
test "scan_literal_boundary_文案里的字面量不得命中" {
  let hint = "  let hint = " +
    q() +
    "先校验 length() 再 substring(start=0)" +
    q()
  assert_false(scan_outside_literal(hint[:], "substring("))
  let prose = "  " + q() + "空数组下标写法 rows[0] 会 panic" + q()
  assert_false(scan_outside_literal(prose[:], "rows[0]"))
  // 反斜杠转义过的引号不闭合字面量：命中仍然在字面量内部
  let esc = "  " + q() + "a \\" + q() + " b rows[0] c" + q()
  assert_false(scan_outside_literal(esc[:], "rows[0]"))
  // 一次命中都没有时不报错、只回 false
  assert_false(scan_outside_literal("  let a = 1"[:], "rows[0]"))
  // 行尾注释里的散文不得命中（BUG-15 当年"另开 issue"的那半边，本轮还债）
  assert_false(
    scan_outside_literal(
      "  Json::Null => (d, []) // null = 没给配置，不算违例"[:],
      "/ n",
    ),
  )
  // 反向成对：同一行注释之前若真有代码命中，必须照样抓到
  assert_true(scan_outside_literal("  let r = a / n // 平均"[:], "/ n"))
  // 注释壳不能被"引号配对"骗过：注释里的引号不该把后续当成字面量
  assert_true(scan_outside_literal("  let r = a / n\n"[:], "/ n"))
}

///|
test "scan_match_lines_整行注释与字面量两道降噪同时生效" {
  let content = "/// doc 里写 rows[0]\nfn f(): Int {\n  let hint = \"rows[0]\"\n  let rows : Array[Int] = []\n  rows[0]\n}\n"
  let rule = {
    id: "empty-array-index",
    severity: "high",
    pattern: ["rows[0]"],
    why: "空数组下标",
    hint: "先判空",
  }
  let hits = scan_match_lines(content, [rule], "sample.mbt")
  // 只有第 5 行（真正的代码行）能留下：doc 注释被 scan_is_comment_line 挡，
  // 第 3 行的字面量被本轮的 scan_outside_literal 挡
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].line, 5)
}

///|
/// BUG-164 盲区 A：`X.unwrap()` 的守卫写在**上一行**（`if X.is_some()`），
/// 扫描器此前不认上一行守卫、把受保护 unwrap 误报为 unwrapped-unwrap。
test "scan_unwrap_guard_上一行 is_some 守卫必须豁免" {
  let guarded = scan_finding_guarded(
    "let prev = pending_advance.unwrap()",
    "unwrapped-unwrap",
    ["if pending_advance.is_some() {"],
  )
  assert_true(guarded)
  // is_ok() 同样算守卫（Result 侧）
  let guarded_ok = scan_finding_guarded(
    "let v = r.unwrap()",
    "unwrapped-unwrap",
    ["if r.is_ok() {"],
  )
  assert_true(guarded_ok)
  // 点链接收者：`a.b.unwrap()` 要能被上一行的 `a.b.is_some()` 覆盖
  let guarded_chain = scan_finding_guarded(
    "let x = cfg.opt.unwrap()",
    "unwrapped-unwrap",
    ["if cfg.opt.is_some() {"],
  )
  assert_true(guarded_chain)
}

///|
/// BUG-164 盲区 B 辅助：`substring(start=N, end~)` / `substring(start=N, end=<var>)` 的 start 与 end 变量名提取。
test "scan_substring_start_and_end_var_提取 start 与 end 变量名" {
  // `end~` 简写 → end 变量名是 end
  assert_eq(scan_substring_start("ls.substring(start=3, end~).trim()"), 3)
  assert_eq(scan_substring_end_var("ls.substring(start=3, end~).trim()"), "end")
  // `end=<var>` 命名变量
  assert_eq(scan_substring_start("s.substring(start=0, end=end_pos)"), 0)
  assert_eq(
    scan_substring_end_var("s.substring(start=0, end=end_pos)"),
    "end_pos",
  )
  // 无 start= 时返回 -1，无 end~ / end= 时返回空串
  assert_eq(scan_substring_start("s.substring(end=5)"), -1)
  assert_eq(scan_substring_end_var("s.substring(start=0, end=5)"), "")
  assert_eq(scan_substring_end_var("no substring here"), "")
  // BUG-188：长数字串在 acc = acc*10 + d 上溢出 Int，按解析失败返回 -1（不静默乱数）
  assert_eq(
    scan_substring_start("s.substring(start=99999999999999999999, end~)"),
    -1,
  )
  assert_eq(scan_substring_start("s.substring(start=2000000001, end~)"), -1)
  // 守卫在下一轮迭代触发：acc 到 200000000（9 位）仍有效，2000000000（10 位）即拒
  assert_eq(
    scan_substring_start("s.substring(start=200000000, end~)"),
    200000000,
  )
  assert_eq(scan_substring_start("s.substring(start=2000000000, end~)"), -1)
  assert_eq(
    scan_substring_start("s.substring(start=199999999, end~)"),
    199999999,
  )
}

///|
/// BUG-164 盲区 B：`if end > 3`（上一行）守卫 `substring(start=3, end~)` 应被判为已守卫（假阳性过滤）。
test "scan_guard_substring_end_var_if end大于 start 判已守卫" {
  // 端变量守卫：`if end > 3` + `substring(start=3, end~)`（ops_selfdrive.mbt:565-566 原形）
  let guarded = scan_finding_guarded(
    "let desc = ls.substring(start=3, end~).trim().to_string()",
    "substring-overrun",
    ["if end > 3 {"],
  )
  assert_true(guarded)
  // 命名变量：`if end_pos > 0` + `substring(start=0, end=end_pos)`——start=0 时
  // `end > 0` 只保证 end≥1，不构成上界（end 可能巨大），**不**判已守卫（盲区 C 收紧）。
  let guarded_named = scan_finding_guarded(
    "let s2 = s.substring(start=0, end=end_pos)",
    "substring-overrun",
    ["if end_pos > 0 {"],
  )
  assert_false(guarded_named)
  // `>=` 形态
  let guarded_ge = scan_finding_guarded(
    "let s2 = s.substring(start=5, end=end_pos)",
    "substring-overrun",
    ["if end_pos >= 5 {"],
  )
  assert_true(guarded_ge)
}

///|
/// BUG-164 盲区 B 的反向成对：守卫缺失 / 守卫变量不匹配 / 不是 if 前缀时仍判真阳性。
test "scan_guard_substring_end_var_无守卫或变量不匹配判真阳性" {
  // 无守卫
  let unguarded = scan_finding_guarded(
    "let desc = ls.substring(start=3, end~).trim().to_string()",
    "substring-overrun",
    [],
  )
  assert_false(unguarded)
  // 守卫的是**别的**变量（`if other > 3`），不能误豁免
  let wrong_var = scan_finding_guarded(
    "let desc = ls.substring(start=3, end~).trim().to_string()",
    "substring-overrun",
    ["if other > 3 {"],
  )
  assert_false(wrong_var)
  // 数字不等（`if end > 5` 而 start=3）——不匹配就不算守卫
  let wrong_n = scan_finding_guarded(
    "let desc = ls.substring(start=3, end~).trim().to_string()",
    "substring-overrun",
    ["if end > 5 {"],
  )
  assert_false(wrong_n)
  // 没有 `if ` 前缀（如 `end > 3` 裸表达式）不识别
  let no_if = scan_finding_guarded(
    "let desc = ls.substring(start=3, end~).trim().to_string()",
    "substring-overrun",
    ["end > 3"],
  )
  assert_false(no_if)
}

///|
/// BUG-164 盲区 A 的反向成对：无守卫的裸 unwrap 仍必须判为真阳性（不可因提速而漏检）。
test "scan_unwrap_guard_裸 unwrap 仍判真阳性" {
  let unguarded = scan_finding_guarded(
    "let prev = pending_advance.unwrap()",
    "unwrapped-unwrap",
    [],
  )
  assert_false(unguarded)
  // 上一行守卫的是**别的**变量（`other.is_some()`），不能误豁免
  let wrong_var = scan_finding_guarded(
    "let prev = pending_advance.unwrap()",
    "unwrapped-unwrap",
    ["if other.is_some() {"],
  )
  assert_false(wrong_var)
  // 上一行只有 `fn ` 边界，没有守卫
  let fn_boundary = scan_finding_guarded(
    "let prev = pending_advance.unwrap()",
    "unwrapped-unwrap",
    ["fn helper() -> Unit {"],
  )
  assert_false(fn_boundary)
}

///|
/// scan_unwrap_receiver 自身：从各种形态的 `.unwrap()` 里取出接收者。
test "scan_unwrap_receiver_提取接收者" {
  assert_eq(scan_unwrap_receiver("pending_advance.unwrap()"), "pending_advance")
  assert_eq(scan_unwrap_receiver("let v = r.unwrap()"), "r")
  assert_eq(scan_unwrap_receiver("cfg.opt.unwrap()"), "cfg.opt")
  assert_eq(scan_unwrap_receiver("let a = x.unwrap()"), "x")
  // 没有 `.unwrap(` 时返回空串
  assert_eq(scan_unwrap_receiver("let a = 1"), "")
  assert_eq(scan_unwrap_receiver(".unwrap()"), "")
}

///|
/// BUG-164 盲区 C：`max <= s.length()`（上一行）守卫 `substring(start=0, end=max)`（engine_triage.mbt:46-47 原形）。
test "scan_guard_substring_end_var_上界约束判已守卫" {
  // engine_triage.mbt:44-47 原形：`} else if max > 0 && max <= s.length() {` → `s.substring(start=0, end=max)`
  let triage_guarded = scan_finding_guarded(
    "s.substring(start=0, end=max) + \"…\"",
    "substring-overrun",
    ["} else if max > 0 && max <= s.length() {"],
  )
  assert_true(triage_guarded)
  // engine_eval.mbt:19-20 原形：`if s.length() >= 2 {` → `s.substring(start=2, end=s.length())`
  let eval_guarded = scan_finding_guarded(
    "out.push(s.substring(start=2, end=s.length()))",
    "substring-overrun",
    ["if s.length() >= 2 {"],
  )
  assert_true(eval_guarded)
  // 反向：无长度上界约束时仍判真阳性
  let unguarded = scan_finding_guarded(
    "s.substring(start=0, end=max)",
    "substring-overrun",
    ["} else if max > 0 {"],
  )
  assert_false(unguarded)
  // 反向：约束的是**别的**字符串长度（`max <= other.length()`）不误豁免
  let wrong_target = scan_finding_guarded(
    "s.substring(start=0, end=max)",
    "substring-overrun",
    ["} else if max <= other.length() {"],
  )
  assert_false(wrong_target)
}
