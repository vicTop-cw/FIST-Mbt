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
  // BUG-346 成对锁：json-injection 只认同一调用实参里的拼接/插值；
  // 安全构造器 Json::string(value) 必须放过（旧 pattern 裸 Json::string( 全判假阳）。
  let json_rule = {
    id: "moonbit-json-injection",
    severity: "low",
    pattern: ["Json::string("],
    why: "JSON 字符串由拼接构造",
    hint: "先转义",
  }
  let safe = "let s = Json::string(name)\n"
  assert_eq(scan_match_lines(safe, [json_rule], "sample.mbt").length(), 0)
  let concat = "let s = Json::string(name + suffix)\n"
  assert_eq(scan_match_lines(concat, [json_rule], "sample.mbt").length(), 1)
  // 字面量里的加号不是拼接（"a+b" 是安全内容）
  let plus_in_literal = "let s = Json::string(\"a+b\")\n"
  assert_eq(
    scan_match_lines(plus_in_literal, [json_rule], "sample.mbt").length(),
    0,
  )
  // 插值 \{value} 仍算拼接构造
  let interp = "let s = Json::string(\"v=\\{value}\")\n"
  assert_eq(scan_match_lines(interp, [json_rule], "sample.mbt").length(), 1)
  // BUG-348 成对锁：match-exhaustive 已有顶层 `_ =>` 兜底必须放过；缺兜底仍报。
  let me_rule = {
    id: "moonbit-match-exhaustive",
    severity: "low",
    pattern: ["match "],
    why: "match 可能非穷尽",
    hint: "补全变体",
  }
  let me_closed = "fn f(x : Int) -> Int {\n  match x {\n    0 => 0\n    _ => 1\n  }\n}\n"
  assert_eq(scan_match_lines(me_closed, [me_rule], "m.mbt").length(), 0)
  let me_open = "fn g(x : Int) -> Int {\n  match x {\n    0 => 0\n  }\n}\n"
  assert_eq(scan_match_lines(me_open, [me_rule], "m.mbt").length(), 1)
  // 嵌套 match 的兜底只算内层穷尽，外层仍须报（1 条）
  let me_nested = "fn h(x : Int, y : Int) -> Int {\n  match x {\n    0 =>\n      match y {\n        0 => 0\n        _ => 1\n      }\n  }\n}\n"
  assert_eq(scan_match_lines(me_nested, [me_rule], "m.mbt").length(), 1)
  // BUG-348：moonbit-long-function 按花括号配平实测行数，短函数不报、超 50 行才报。
  let lf_rule = {
    id: "moonbit-long-function",
    severity: "info",
    pattern: ["fn "],
    why: "超长函数",
    hint: "拆分",
  }
  let short_fn = "fn add(a : Int, b : Int) -> Int {\n  a + b\n}\n"
  assert_eq(scan_match_lines(short_fn, [lf_rule], "f.mbt").length(), 0)
  let mut long_src = "fn big() -> Int {\n"
  let mut bi = 0
  while bi < 60 {
    long_src = long_src + "  let v" + bi.to_string() + " = 0\n"
    bi = bi + 1
  }
  long_src = long_src + "  0\n}\n"
  assert_eq(scan_match_lines(long_src, [lf_rule], "f.mbt").length(), 1)
  // 单行函数（三行以内）同样不报
  let one_line = "fn id(x : Int) -> Int { x }\n"
  assert_eq(scan_match_lines(one_line, [lf_rule], "f.mbt").length(), 0)
  // 成对锁（历史注释曾误引一个从未入账、也无任何追记的编号，已按 BUG-373 口径移除该记号以免悬空引用）：empty-match 只报「整个 match 仅一条 `_ => ()` 手臂」；
  // 多臂 match 的 catch-all 空手臂是正常写法，必须放过。
  let em_rule = {
    id: "moonbit-empty-match",
    severity: "low",
    pattern: ["_ => ()"],
    why: "空转 match",
    hint: "逐变体处理",
  }
  let em_only = "fn f(x : Int) -> Unit {\n  match x {\n    _ => ()\n  }\n}\n"
  assert_eq(scan_match_lines(em_only, [em_rule], "e.mbt").length(), 1)
  let em_multi = "fn g(x : Int) -> Unit {\n  match x {\n    0 => ()\n    _ => ()\n  }\n}\n"
  assert_eq(scan_match_lines(em_multi, [em_rule], "e.mbt").length(), 0)
  // 成对锁（历史注释曾误引一个从未入账、也无任何追记的编号，已按 BUG-373 口径移除该记号以免悬空引用）：noop 只认 `self.x = self.x`；结构体字面量 `id: self.id` 与改别的字段都不报。
  let noop_rule = {
    id: "moonbit-noop-assignment",
    severity: "low",
    pattern: ["self."],
    why: "自赋值",
    hint: "确认更新源",
  }
  let noop_real = "fn h() -> Unit {\n  self.total = self.total\n}\n"
  assert_eq(scan_match_lines(noop_real, [noop_rule], "n.mbt").length(), 1)
  let noop_literal = "let p = { id: self.id }\n"
  assert_eq(scan_match_lines(noop_literal, [noop_rule], "n.mbt").length(), 0)
  let noop_different = "self.total = self.other\n"
  assert_eq(scan_match_lines(noop_different, [noop_rule], "n.mbt").length(), 0)
  // CRLF 工作树的 `\r` 视作空白，行尾判定不被它挡掉
  let noop_crlf = "self.total = self.total\r\n"
  assert_eq(scan_match_lines(noop_crlf, [noop_rule], "n.mbt").length(), 1)
  // 成对锁（历史注释曾误引一个从未入账、也无任何追记的编号，已按 BUG-373 口径移除该记号以免悬空引用）：private-field-leak 只认整词；tokens_in / max_tokens 不报。
  let pf_rule = {
    id: "moonbit-private-field-leak",
    severity: "low",
    pattern: ["password", "secret", "token"],
    why: "敏感字段",
    hint: "保持私有",
  }
  let pf_word = "let token = read_token()\n"
  assert_eq(scan_match_lines(pf_word, [pf_rule], "p.mbt").length(), 1)
  let pf_sub = "let tokens_in = 3\nlet max_tokens = 4\n"
  assert_eq(scan_match_lines(pf_sub, [pf_rule], "p.mbt").length(), 0)
  // 成对锁（历史注释曾误引一个从未入账、也无任何追记的编号，已按 BUG-373 口径移除该记号以免悬空引用）：shared-mutable 只认 `let mut x = obj.field` 形状。
  let sm_rule = {
    id: "moonbit-shared-mutable",
    severity: "low",
    pattern: ["let mut "],
    why: "共享可变",
    hint: "直接改字段",
  }
  let sm_field = "let mut round = lp.round\n"
  assert_eq(scan_match_lines(sm_field, [sm_rule], "s.mbt").length(), 1)
  let sm_zero = "let mut i = 0\n"
  assert_eq(scan_match_lines(sm_zero, [sm_rule], "s.mbt").length(), 0)
  let sm_float = "let mut sum = 0.0\nlet mut d = 1.0\n"
  assert_eq(scan_match_lines(sm_float, [sm_rule], "s.mbt").length(), 0)
  let sm_expr = "let mut total = self.total + 1\n"
  assert_eq(scan_match_lines(sm_expr, [sm_rule], "s.mbt").length(), 0)
  let sm_crlf = "let mut round = lp.round\r\n"
  assert_eq(scan_match_lines(sm_crlf, [sm_rule], "s.mbt").length(), 1)
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

///|
/// BUG-348：unused-variable 此前按裸子串 `let ` 命中每个 let 声明、不看绑定名是否真被用
/// ⇒ 已使用的 let 照样报（纯假阳）。三件纯函数各自钉死，再加端到端成对锁
/// （用了的必须不报、真没用的必须仍报——单向保守，不许翻成「不扫了」）。
test "bug348_let_binding_name_extraction" {
  assert_eq(scan_let_binding_name("let x = 1"), "x")
  assert_eq(scan_let_binding_name("let mut cost = 3"), "cost")
  assert_eq(
    scan_let_binding_name("let remaining: Int = total - used"),
    "remaining",
  )
  // 非简单形状 ⇒ 空串（调用方保持现行为照常报，不猜名字）
  assert_eq(scan_let_binding_name("let [a, b] = pair"), "")
  assert_eq(scan_let_binding_name("let _ = f()"), "")
  assert_eq(scan_let_binding_name("  let x = 1"), "")
  // mut 是更长标识符前缀时绝不能吃掉它（`let mutator = 1` 的绑定名是 mutator）
  assert_eq(scan_let_binding_name("let mutator = 1"), "mutator")
}

///|
test "bug348_word_occurrence_is_whole_word" {
  // 整词命中
  assert_true(scan_word_occurs("  let y = x + 1", "x"))
  // 左邻标识符字符 ⇒ 不算整词（真未使用的 x 不该在 totally_unused 里被看见）
  assert_false(scan_word_occurs("  let v = totally_unused", "x"))
  assert_false(scan_word_occurs("  let v = xtotal", "x"))
  // 右邻是下划线（标识符续接字符）⇒ 不算整词
  assert_false(scan_word_occurs("  let v = x_1", "x"))
  // 空词/空文本都不命中（不拿空串当万能 needle）
  assert_false(scan_word_occurs("anything", ""))
  assert_false(scan_word_occurs("", "x"))
  // 边界：行尾与行首都算整词
  assert_true(scan_word_occurs("x", "x"))
  assert_true(scan_word_occurs("  action", "action"))
}

///|
test "bug348_used_elsewhere_skips_decl_line_only" {
  // 只在声明行出现 ⇒ false（照常报真未使用）
  let cps1 : Array[String] = ["let dead = 1", "  2", "}"]
  assert_false(scan_variable_used_elsewhere(cps1, 1, "dead"))
  // 别行出现 ⇒ true（其实用了）
  let cps2 : Array[String] = [
    "fn f(): Int {", "  let cost = 3", "  cost + 1", "}",
  ]
  assert_true(scan_variable_used_elsewhere(cps2, 2, "cost"))
  // 只在声明行出现（哪怕声明行里同名重复 = 自引用）⇒ false：除声明行外没有使用点
  let cps3 : Array[String] = ["  let cost = cost", "}"]
  assert_false(scan_variable_used_elsewhere(cps3, 1, "cost"))
}

///|
/// R127：形态 F 字面量前缀/后缀守卫——`extract_needs` 的 6 条 substring 命中是
/// `let s = sv.to_owned()` + `sv.has_prefix("需要:")` + `s.substring(start="需要:".length())`。
/// 守卫成立时 start 必 ≤ 长度，应豁免；守卫缺失/字面量不匹配/副本可能缩短时仍判真阳性。
test "scan_guard_prefix_literal_字面量前后缀守卫" {
  let need = q() + "需要:" + q()
  let call = "s.substring(start=" + need + ".length()).trim()"
  let guarded = scan_finding_guarded(call, "substring-overrun", [
    "let s = sv.to_owned()",
    "} else if sv.has_prefix(" + need + ") {",
  ])
  assert_true(guarded)
  // 同变量 + has_suffix
  let guarded_suffix = scan_finding_guarded(
    "x.substring(start=" + q() + ".json" + q() + ".length())",
    "substring-overrun",
    ["if x.has_suffix(" + q() + ".json" + q() + ") {"],
  )
  assert_true(guarded_suffix)
  // 反例 1：无守卫
  let unguarded = scan_finding_guarded(call, "substring-overrun", [])
  assert_false(unguarded)
  // 反例 2：守卫的是别的字面量
  let wrong_lit = scan_finding_guarded(call, "substring-overrun", [
    "let s = sv.to_owned()",
    "if sv.has_prefix(" + q() + "能力:" + q() + ") {",
  ])
  assert_false(wrong_lit)
  // 反例 3：副本经过 trim，可能比原串短
  let trimmed_copy = scan_finding_guarded(call, "substring-overrun", [
    "let s = sv.trim()",
    "if sv.has_prefix(" + need + ") {",
  ])
  assert_false(trimmed_copy)
  // 反例 4：无副本关系，守卫的是别的变量
  let other_var = scan_finding_guarded(call, "substring-overrun", [
    "if other.has_prefix(" + need + ") {",
  ])
  assert_false(other_var)
}

///|
/// R127：近邻窗口是生产过滤与单测共用的同一构造——`engine.extract_needs` 第 6 条
/// substring（`能力：` 分支）距 `let s = sv.to_owned()` 恰好 12 行，窗口少一行就丢副本关系。
/// 下面按真实行距铺 14 行：正例必须抑制，而「旧 10 行窗口」形态必须仍判真阳性。
test "scan_prev_window_十二行窗口保住副本关系" {
  let lit = q() + "能力：" + q()
  let lines : Array[String] = [
    "fn extract_needs(desc : String) -> Array[String] {",
    "  let s = sv.to_owned()",
    "  let a = 1",
    "  let b = 2",
    "  let c = 3",
    "  let d = 4",
    "  let e = 5",
    "  let f = 6",
    "  let g = 7",
    "  let h = 8",
    "  let i = 9",
    "  let j = 10",
    "  } else if sv.has_prefix(" + lit + ") {",
    "    s.substring(start=" + lit + ".length()).trim()",
  ]
  let hit_line = lines[13]
  let window = scan_prev_window(lines, 14)
  assert_true(window.length() == 12)
  assert_true(scan_finding_guarded(hit_line, "substring-overrun", window))
  // 旧 10 行窗口（最近 10 行，副本定义被截掉）必须仍判真阳性——
  // 若有人把上限改回 10，这一格会失败。
  let old_window : Array[String] = []
  for k in 0..<10 {
    old_window.push(window[k])
  }
  assert_false(scan_finding_guarded(hit_line, "substring-overrun", old_window))
  // `fn ` 行是窗口边界：跨过函数头时不取旧函数的副本定义
  let cross : Array[String] = ["  let s = sv.to_owned()", "fn other() {"]
  let mut k = 0
  while k < 10 {
    cross.push("  let p" + k.to_string() + " = " + k.to_string())
    k = k + 1
  }
  cross.push("  s.substring(start=" + lit + ".length())")
  let cross_window = scan_prev_window(cross, 13)
  let mut has_copy = false
  for p in cross_window {
    if p.trim() == "let s = sv.to_owned()" {
      has_copy = true
    }
  }
  assert_false(has_copy)
}

///|
/// severity 档位与聚合兜底同一口径——未知档归 0（info），
/// 否则过滤和 by_severity 计数会各说各话。
test "scan_severity_rank_mapping" {
  assert_eq(scan_severity_rank("high"), 3)
  assert_eq(scan_severity_rank("medium"), 2)
  assert_eq(scan_severity_rank("low"), 1)
  assert_eq(scan_severity_rank("info"), 0)
  assert_eq(scan_severity_rank("weird"), 0)
  assert_eq(scan_severity_rank(""), 0)
}

///|
test "scan_min_severity_rank_parse" {
  let rank_of = fn(raw : String) -> Int32 {
    match scan_min_severity_rank(raw) {
      Ok(r) => r
      Err(_) => -999
    }
  }
  assert_eq(rank_of(""), -1)
  assert_eq(rank_of("   "), -1)
  assert_eq(rank_of("HIGH"), 3)
  assert_eq(rank_of("  Medium "), 2)
  assert_eq(rank_of("low"), 1)
  assert_eq(rank_of("INFO"), 0)
  match scan_min_severity_rank("severe") {
    Ok(_) => abort("非法 min_severity 必须 Err")
    Err(e) => {
      assert_true(e.contains("min_severity"))
      assert_true(e.contains("high|medium|low|info"))
    }
  }
}
