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
