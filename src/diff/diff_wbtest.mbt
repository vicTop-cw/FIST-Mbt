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
