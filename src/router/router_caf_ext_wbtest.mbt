///|
/// CAF P2d 冷启动启发式测试（新增函数层，独立文件）
/// 设计文档：docs/2026-10-15-fist-mbt-caf-p2d-cold-start-design.md
/// 验收标准：零回归 + 冷启动偏好 + 记忆充足退化 + 未知偏好安全

///|
/// P2d-1 零回归：preference 空 + 记忆不足 → 返回原序
test "caf_pref_empty_baseline" {
  let candidates : Array[String] = ["m_free", "m_mid", "m_premium"]
  let stats : Array[CafModelStats] = []
  let result = caf_soft_reorder_with_preference(candidates, stats, [], 10)
  assert_eq(result.length(), 3)
  assert_eq(result[0], "m_free")
  assert_eq(result[1], "m_mid")
  assert_eq(result[2], "m_premium")
}

///|
/// P2d-2 记忆充足退化：统计足够 → 与 caf_soft_reorder 一致（成功率排序）
test "caf_pref_memory_enough_fallback" {
  let candidates : Array[String] = ["m_free", "m_mid", "m_premium"]
  // m_mid 成功率 100%，应排第一
  let stats : Array[CafModelStats] = [
    { model: "m_free", total: 10, success: 5, avg_cost: 1.0, },
    { model: "m_mid", total: 10, success: 10, avg_cost: 2.0, },
    { model: "m_premium", total: 10, success: 8, avg_cost: 3.0, },
  ]
  let result = caf_soft_reorder_with_preference(
    candidates,
    stats,
    ["m_premium"],
    5,
  )
  // 记忆充足 → 退化到 caf_soft_reorder → m_mid 排第一（成功率最高）
  assert_eq(result[0], "m_mid")
}

///|
/// P2d-3 偏好生效：记忆不足 + preference=[m_premium, m_mid, m_free] → 按偏好排序
test "caf_pref_orders_preference" {
  let candidates : Array[String] = ["m_free", "m_mid", "m_premium"]
  let stats : Array[CafModelStats] = []
  let pref : Array[String] = ["m_premium", "m_mid", "m_free"]
  let result = caf_soft_reorder_with_preference(candidates, stats, pref, 10)
  assert_eq(result[0], "m_premium")
  assert_eq(result[1], "m_mid")
  assert_eq(result[2], "m_free")
}

///|
/// P2d-4 未知偏好安全：preference 里的模型不在候选 → 跳过，不 panic
test "caf_pref_unknown_preference" {
  let candidates : Array[String] = ["m_free", "m_mid"]
  let stats : Array[CafModelStats] = []
  let pref : Array[String] = ["ghost"]
  let result = caf_soft_reorder_with_preference(candidates, stats, pref, 10)
  assert_eq(result.length(), 2)
  assert_eq(result[0], "m_free")
  assert_eq(result[1], "m_mid")
}

///|
/// P2d-5 偏好外保持原序：preference=[m_premium]，候选 [m_free, m_mid, m_premium]
/// → 结果 [m_premium, m_free, m_mid]（偏好外按原序）
test "caf_pref_preserves_unmatched" {
  let candidates : Array[String] = ["m_free", "m_mid", "m_premium"]
  let stats : Array[CafModelStats] = []
  let pref : Array[String] = ["m_premium"]
  let result = caf_soft_reorder_with_preference(candidates, stats, pref, 10)
  assert_eq(result[0], "m_premium")
  assert_eq(result[1], "m_free")
  assert_eq(result[2], "m_mid")
}

///|
/// P2d-6 记忆不足但非空：stats 有 1 条但 < min_evidences → 走偏好路径
test "caf_pref_insufficient_evidences_fallback" {
  let candidates : Array[String] = ["m_free", "m_mid", "m_premium"]
  // 只有 1 条 evidence，min_evidences=10 → 记忆不足 → 走偏好
  let stats : Array[CafModelStats] = [
    { model: "m_free", total: 1, success: 1, avg_cost: 1.0, },
  ]
  let pref : Array[String] = ["m_premium", "m_free"]
  let result = caf_soft_reorder_with_preference(candidates, stats, pref, 10)
  assert_eq(result[0], "m_premium")
  assert_eq(result[1], "m_free")
  assert_eq(result[2], "m_mid")
}

///|
/// P2d-7 重复偏好：preference 里同一模型多次 → 只取一次，不 panic
test "caf_pref_duplicate_preference" {
  let candidates : Array[String] = ["m_free", "m_mid"]
  let stats : Array[CafModelStats] = []
  let pref : Array[String] = ["m_mid", "m_mid"]
  let result = caf_soft_reorder_with_preference(candidates, stats, pref, 10)
  assert_eq(result.length(), 2)
  assert_eq(result[0], "m_mid")
  assert_eq(result[1], "m_free")
}

///|
/// P2d-8 空候选集安全：候选集空 + 非空偏好 + 空记忆 → 返回空，不 panic
test "caf_pref_empty_candidates_safe" {
  let candidates : Array[String] = []
  let stats : Array[CafModelStats] = []
  let result = caf_soft_reorder_with_preference(
    candidates,
    stats,
    ["m_free"],
    10,
  )
  assert_eq(result.length(), 0)
}

///|
/// P2d-9 min_evidences=0 语义：stats 非空即视为证据充足 → 退化到成功率排序
/// （文档：0 = any evidence counts）
test "caf_pref_zero_min_evidences_any_counts" {
  let candidates : Array[String] = ["m_free", "m_mid"]
  // m_mid 成功率 100% → 退化到成功率排序后应排第一（即使偏好是 m_free）
  let stats : Array[CafModelStats] = [
    { model: "m_free", total: 1, success: 0, avg_cost: 1.0, },
    { model: "m_mid", total: 1, success: 1, avg_cost: 2.0, },
  ]
  let result = caf_soft_reorder_with_preference(
    candidates,
    stats,
    ["m_free"],
    0,
  )
  assert_eq(result[0], "m_mid")
}

///|
/// P2d-10 全零 stats 仍按记忆不足处理：stats 有记录但 total 全 0 + min_evidences=10
/// → evidence_total=0 < 10 → 走偏好路径
test "caf_pref_zero_evidence_insufficient" {
  let candidates : Array[String] = ["m_free", "m_mid"]
  let stats : Array[CafModelStats] = [
    { model: "m_free", total: 0, success: 0, avg_cost: 1.0, },
    { model: "m_mid", total: 0, success: 0, avg_cost: 2.0, },
  ]
  let pref : Array[String] = ["m_mid"]
  let result = caf_soft_reorder_with_preference(candidates, stats, pref, 10)
  assert_eq(result[0], "m_mid")
  assert_eq(result[1], "m_free")
}
