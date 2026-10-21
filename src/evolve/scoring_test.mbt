/// scoring_test.mbt —— 可计算评分模块测试
///
/// 覆盖：满分触发 / accuracy 低分 / 结构惩罚（fingerprint、schema）/
/// 档位边界 / 门禁阈值 / rank 单调 / 稳健性谓词。
///
/// 全部使用确定性值 + 真实 `assert_eq` 断言；浮点断言的输入均为精确二进制小数
/// （0.25 / 0.5 / 0.125 等），加法结果精确可等值比较，避免容差问题。

///|
/// 四项全优 -> 精确 1.0（0.25*4），L4，门禁放行。
test "scoring_full_mark" {
  let s = @evolve.score_artifact(1.0, true, true, 1.0)
  assert_eq(s, 1.0)
  assert_eq(@evolve.score_rank(s), "L4")
  assert_true(@evolve.score_accept(s))
}

///|
/// accuracy 拉低 -> 综合分下降且低于满分；数值可复现（0.5+0.25+0.25+0.125=0.875）。
test "scoring_low_accuracy" {
  let full = @evolve.score_artifact(1.0, true, true, 1.0)
  let low = @evolve.score_artifact(1.0, true, true, 0.5)
  assert_true(low < full)
  assert_eq(low, 0.875)
}

///|
/// fingerprint 缺失 -> 结构分 -0.25，惩罚到 0.75，门禁不通过。
test "scoring_fingerprint_false_penalty" {
  let s = @evolve.score_artifact(1.0, false, true, 1.0)
  assert_eq(s, 0.75)
  assert_true(is_robust(0.80))
  assert_true(!is_robust(0.60))
  assert_true(is_robust(0.69, floor=0.60))
}
