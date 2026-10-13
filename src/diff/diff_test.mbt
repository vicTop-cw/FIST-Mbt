///|
/// diff/diff_test.mbt —— 文本 diff 单元测试。

///|
test "diff_lines 完全相同" {
  let ops = diff_lines("a\nb\nc", "a\nb\nc")
  assert_eq(ops.length(), 3)
  for op in ops {
    assert_eq(op.kind(), "equal")
  }
}

///|
test "diff_lines 单行替换" {
  let ops = diff_lines("a\nb\nc", "a\nx\nc")
  // 期望: Equal(a), Delete(b), Insert(x), Equal(c)
  assert_eq(ops.length(), 4)
  assert_eq(ops[0].kind(), "equal")
  assert_eq(ops[0].text(), "a")
  assert_eq(ops[1].kind(), "delete")
  assert_eq(ops[1].text(), "b")
  assert_eq(ops[2].kind(), "insert")
  assert_eq(ops[2].text(), "x")
  assert_eq(ops[3].kind(), "equal")
  assert_eq(ops[3].text(), "c")
}

///|
test "diff_lines 全替换" {
  let ops = diff_lines("a\nb", "x\ny")
  assert_eq(ops.length(), 4)
  assert_eq(ops[0].kind(), "delete")
  assert_eq(ops[1].kind(), "delete")
  assert_eq(ops[2].kind(), "insert")
  assert_eq(ops[3].kind(), "insert")
}

///|
test "diff_lines 空输入" {
  let ops = diff_lines("", "")
  assert_eq(ops.length(), 0)
  let ops2 = diff_lines("a", "")
  assert_eq(ops2.length(), 1)
  assert_eq(ops2[0].kind(), "delete")
  let ops3 = diff_lines("", "a")
  assert_eq(ops3.length(), 1)
  assert_eq(ops3[0].kind(), "insert")
}

///|
test "render_unified 格式" {
  let ops = diff_lines("a\nb", "a\nx")
  let s = render_unified(ops)
  assert_true(s.contains(" a"))
  assert_true(s.contains("-b"))
  assert_true(s.contains("+x"))
}

///|
test "render_json 格式与转义" {
  let ops = diff_lines("a", "b")
  let s = render_json(ops)
  assert_true(s.contains("\"kind\":\"delete\""))
  assert_true(s.contains("\"kind\":\"insert\""))
  assert_true(s.contains("\"text\":\"a\""))
  assert_true(s.contains("\"text\":\"b\""))
}

///|
test "diff_stats 计数" {
  let ops = diff_lines("a\nb\nc", "a\nx\nc\nd")
  let (eq, ins, del) = diff_stats(ops)
  assert_eq(eq, 2) // a, c
  assert_eq(ins, 2) // x, d
  assert_eq(del, 1) // b
}

///|
test "diff_lines 多行追加" {
  let ops = diff_lines("a", "a\nb\nc")
  assert_eq(ops.length(), 3)
  assert_eq(ops[0].kind(), "equal")
  assert_eq(ops[1].kind(), "insert")
  assert_eq(ops[2].kind(), "insert")
}
