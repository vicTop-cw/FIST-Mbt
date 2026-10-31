///|
/// diff_wbtest.mbt —— `src/diff` 的**白盒**不变量锁（R188）。
///
/// 为什么单独建：回放不变量要用 `split_lines`（**私有**）取右侧行序，
/// 而 `diff_test.mbt` 是黑盒文件（只能看 pub 面）⇒ 放这里。

///|
/// R188：**回放不变量** —— 按 ops 回放（跳过 Delete）必须重建 `new` 的**行序**。
///
/// 为什么补：`diff_lines` 已有 18 条黑盒测试，但**没有一条**验证"操作序列真的能重建右侧"。
/// 而 LCS 回溯最容易错的地方恰恰是**丢行**或**顺序反了**（DP 表对、回溯错）。
/// 两侧都用同一个 `split_lines`，避免"尾部换行 / 空串"语义歧义干扰断言。
test "diff_lines: 回放不变量（Equal+Insert 的行序 == new 行序）" {
  let samples : Array[(String, String)] = [
    ("a\nb\nc", "a\nx\nc"),
    ("", "a\nb"),
    ("a\nb", ""),
    ("same", "same"),
    ("a\nb\na", "a\na"),
    ("x\ny\nz\nw", "x\nz\nw\nv"),
  ]
  for s in samples {
    let (old, new) = s
    let kept = diff_lines(old, new)
      .filter(fn(op) { op.kind() != "delete" })
      .map(fn(op) { op.text() })
    assert_eq(kept, split_lines(new), msg="样本: " + old + " → " + new)
  }
}

///|
/// R210：**JSON 面的危险字符逐项转义**锁。
///
/// 为什么补：`text_diff` MCP 工具把 `render_json` 的输出**直接发给客户端**，
/// 而既有测试只用 `contains` 断言三个字段；一旦某个控制字符没被转义，
/// 客户端 JSON 解析会**整体失败**（不是"少一个字符"，是整条回执不可用）。
/// 本格把 RFC 8259 要求转义的那几类逐项钉住（含 `\u00XX` 的**大写 + 4 位补齐**）。
test "render_json 危险字符逐项转义" {
  let ops : Array[DiffOp] = [
    Insert("quote:\" backslash:\\ newline:\n cr:\r tab:\t ctrl:\u{0001}"),
    Equal("中文与 emoji: 🚀"),
  ]
  let s = render_json(ops)
  // ① 双引号 / 反斜杠 / 换行 / 回车 / 制表符 必须是转义形式（不得以裸字符出现）
  assert_true(s.contains("\\\""), msg="双引号未转义")
  assert_true(s.contains("\\\\"), msg="反斜杠未转义")
  assert_true(
    s.contains("\\n"),
    msg="换行未转义（应为字面反斜杠+n）",
  )
  assert_true(
    s.contains("\\r"),
    msg="回车未转义（应为字面反斜杠+r）",
  )
  assert_true(
    s.contains("\\t"),
    msg="制表符未转义（应为字面反斜杠+t）",
  )
  // ② 控制字符必须走 \u00XX（大写十六进制 + 4 位）—— 断言里找的是**字面反斜杠 + u0001**
  assert_true(
    s.contains("\\u0001"),
    msg="控制字符未按字面 \\u00XX 转义",
  )
  // ③ 原文里**不许**出现裸换行/裸回车（那会直接破坏 JSON 字面量）
  assert_true(!s.contains("\n"), msg="输出里出现裸换行")
  assert_true(!s.contains("\r"), msg="输出里出现裸回车")
  // ④ 非 ASCII（中文/emoji）原样保留（JSON 允许 UTF-8 直出，不必转义）
  assert_true(s.contains("中文与 emoji"), msg="非 ASCII 被破坏")
}
