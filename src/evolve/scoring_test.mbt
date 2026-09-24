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
  let s = score_artifact(1.0, true, true, 1.0)
  assert_eq(s, 1.0)
  assert_eq(score_rank(s), "L4")
  assert_true(score_accept(s))
}

///|
/// accuracy 拉低 -> 综合分下降且低于满分；数值可复现（0.5+0.25+0.25+0.125=0.875）。
test "scoring_low_accuracy" {
  let full = score_artifact(1.0, true, true, 1.0)
  let low = score_artifact(1.0, true, true, 0.5)
  assert_true(low < full)
  assert_eq(low, 0.875)
}

///|
/// fingerprint 缺失 -> 结构分 -0.25，惩罚到 0.75，门禁不通过。
test "scoring_fingerprint_false_penalty" {
  let s = score_artifact(1.0, false, true, 1.0)
  assert_eq(s, 0.75)
  assert_true(not(score_accept(s)))
}

///|
/// schema 缺失 -> 结构分 -0.25，惩罚到 0.75，档位落 L3。
test "scoring_schema_false_penalty" {
  let s = score_artifact(1.0, true, false, 1.0)
  assert_eq(s, 0.75)
  assert_eq(score_rank(s), "L3")
}

///|
/// 两个结构位都缺失 -> 结构分归零，综合分仅剩覆盖+正确 = 0.5。
test "scoring_both_structural_fail" {
  let s = score_artifact(1.0, false, false, 1.0)
  assert_eq(s, 0.5)
  assert_eq(score_rank(s), "L1")
}

///|
/// 档位边界（含端点）：0.00/L1、0.55/L2、0.70/L3、0.85/L4。
test "scoring_rank_boundary" {
  assert_eq(score_rank(0.0), "L1")
  assert_eq(score_rank(0.54), "L1")
  assert_eq(score_rank(0.55), "L2")
  assert_eq(score_rank(0.70), "L3")
  assert_eq(score_rank(0.85), "L4")
  assert_eq(score_rank(1.0), "L4")
}

///|
/// 门禁阈值：默认 0.85（端点含），自定义阈值生效。
test "scoring_accept_threshold" {
  assert_true(score_accept(0.85))
  assert_true(not(score_accept(0.84)))
  assert_true(not(score_accept(0.90, threshold=0.95)))
  assert_true(score_accept(0.96, threshold=0.95))
}

///|
/// rank 单调：score 越大档位只升不降（抽查两对）。
test "scoring_rank_order" {
  assert_eq(score_rank(0.86), "L4")
  assert_eq(score_rank(0.72), "L3")
  assert_eq(score_rank(0.60), "L2")
  assert_eq(score_rank(0.30), "L1")
}

///|
/// 稳健性谓词（默认 floor=0.70，可自定义）。
test "scoring_is_robust" {
  assert_true(is_robust(0.80))
  assert_true(not(is_robust(0.60)))
  assert_true(is_robust(0.69, floor=0.60))
}
