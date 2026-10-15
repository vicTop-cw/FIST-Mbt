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

///|
/// BUG-162 附证：issue_scan 的 moonbit-array-index-bounds 报
/// diff_lines L60 `dp[i-1][j-1]`、L62/L65 `dp[i-1][j]`/`dp[i][j-1]`、
/// L79 `dp[i][j-1]`/`dp[i-1][j]` 越界——以下边界用例直接压 DP 首格与回溯首步。
/// 任一越界（`dp[-1]` 或 `dp[n+1]`）都会 panic，测试失败即证伪修复。

///|
test "diff_lines 单字符 DP 首格边界" {
  // i=1, j=1：首格同时访问 dp[0][0]、dp[0][1]、dp[1][0]
  let eq = diff_lines("a", "a")
  assert_eq(eq.length(), 1)
  assert_eq(eq[0].kind(), "equal")
  // i=1, j=1 不同字符：else 分支取 dp[0][1] 与 dp[1][0] 的最大值
  let ne = diff_lines("a", "b")
  assert_eq(ne.length(), 2)
}

///|
test "diff_lines 单字符对空 DP 首行边界" {
  // i=1, j=0：回溯时 i>0 && j==0 走 Delete 分支
  let d = diff_lines("a", "")
  assert_eq(d.length(), 1)
  assert_eq(d[0].kind(), "delete")
  // i=0, j=1：回溯时 i==0 && j>0 走 Insert 分支，且 L79 短路不取 dp[i-1][j]
  let ins = diff_lines("", "a")
  assert_eq(ins.length(), 1)
  assert_eq(ins[0].kind(), "insert")
}

///|
test "diff_lines 长输入 DP 全表填充" {
  // 长输入压满 dp 表，确认无越界写（dp[n][m] 是最后一格）
  let old = "l1\nl2\nl3\nl4\nl5\nl6\nl7\nl8\nl9\nl10"
  let new = "l2\nl3\nl4\nl5\nl6\nl7\nl8\nl9\nl10\nl11"
  let ops = diff_lines(old, new)
  // LCS(l1..l10, l2..l11) = l2..l10 = 9 行相等
  let mut eq = 0
  for op in ops {
    if op.kind() == "equal" {
      eq = eq + 1
    }
  }
  assert_eq(eq, 9)
}

///|
test "diff_lines 尾部换行差异" {
  // 尾部换行差异：old 3 行、new 2 行，回溯走 Delete 首步
  let ops = diff_lines("a\nb\nc", "a\nb")
  assert_eq(ops.length(), 3)
  assert_eq(ops[0].kind(), "equal")
  assert_eq(ops[1].kind(), "equal")
  assert_eq(ops[2].kind(), "delete")
}

///|
test "diff_lines 完全无公共子序列" {
  // 无公共子序列时 dp 全 0，回溯首步走 L79 的 `i==0 || dp[i][j-1]>=dp[i-1][j]`
  // 短路条件必须成立，否则越界访问 dp[i-1]
  let ops = diff_lines("a\nb", "x\ny\nz")
  let mut eq = 0
  for op in ops {
    if op.kind() == "equal" {
      eq = eq + 1
    }
  }
  assert_eq(eq, 0)
}

///|
test "render_unified 空操作序列" {
  let s = render_unified([])
  assert_eq(s, "")
}

///|
test "render_json 空操作序列" {
  let s = render_json([])
  assert_eq(s, "[]")
}
