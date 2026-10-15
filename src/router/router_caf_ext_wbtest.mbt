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

///|
/// R42 接线前置 · context 归一化契约。
/// caf_norm_1/2 证明：语义等价串经 caf_normalize_context 后 hash 一致 → 命中同一 knn 邻域。
/// caf_norm_3 证明：未归一化时 hash 碎片化（确认接线必须归一化）。
/// caf_norm_4 钉死空串与纯空白 → 空串安全（不 panic）。

///|
/// 大小写不敏感：归一化后 "PYTHON" 与 "python" hash 一致。
test "caf_norm_1_大小写归一后hash一致" {
  let a = caf_feature_hash(caf_normalize_context("PYTHON"))
  let b = caf_feature_hash(caf_normalize_context("python"))
  let c = caf_feature_hash(caf_normalize_context("Python"))
  assert_eq(a, b)
  assert_eq(a, c)
}

///|
/// 空白不敏感：归一化后 "  python  " 与 "python" hash 一致。
test "caf_norm_2_空白归一后hash一致" {
  let a = caf_feature_hash(caf_normalize_context("  python  "))
  let b = caf_feature_hash(caf_normalize_context("python"))
  let c = caf_feature_hash(caf_normalize_context("\tPython\n"))
  assert_eq(a, b)
  assert_eq(a, c)
}

///|
/// 未归一化 hash 碎片化：语义等价但字面不同的串 hash 不同，
/// 会落在 knn_search 的不同编辑距离邻域 → 接线必须经 caf_normalize_context。
test "caf_norm_3_未归一化hash碎片化" {
  assert_true(caf_feature_hash("PYTHON") != caf_feature_hash("python"))
  assert_true(caf_feature_hash("  python  ") != caf_feature_hash("python"))
}

///|
/// 空串与纯空白安全：归一化返回空串，不 panic。
test "caf_norm_4_空串与纯空白安全" {
  assert_eq(caf_normalize_context(""), "")
  assert_eq(caf_normalize_context("   "), "")
  assert_eq(caf_normalize_context("\t\n  "), "")
  // 幂等：归一化后再归一化不变
  assert_eq(
    caf_normalize_context(caf_normalize_context("  Fix Bug  ")),
    "fix bug",
  )
}

///|
/// R43 接线前置 · min_evidences 分界契约（成对互补锁）。
/// caf_pref_exact_boundary_reorder：total == min_evidences → 走重排（真源用 `>=`）。
/// caf_pref_one_below_boundary_pref：total = min_evidences - 1 → 走偏好（`<` 语义）。
/// 两锁一起钉死接线时 min_evidences 参数的分界语义：恰好达标走数据，差一档走偏好。

///|
/// 恰好边界：evidence_total == min_evidences → 记忆「够」→ 走成功率重排（偏好被忽略）
test "caf_pref_exact_boundary_reorder" {
  let candidates : Array[String] = ["m_free", "m_mid"]
  // total = 2 恰好等于 min_evidences = 2 → 走重排（非偏好）
  let stats : Array[CafModelStats] = [
    { model: "m_free", total: 1, success: 0, avg_cost: 1.0, },
    { model: "m_mid", total: 1, success: 1, avg_cost: 2.0, },
  ]
  let result = caf_soft_reorder_with_preference(
    candidates,
    stats,
    ["m_free"],
    2,
  )
  // 偏好是 m_free，但走重排后 m_mid 排第一
  assert_eq(result[0], "m_mid")
  assert_eq(result[1], "m_free")
}

///|
/// 差一档边界：evidence_total = min_evidences - 1 → 记忆「不够」→ 走偏好
test "caf_pref_one_below_boundary_pref" {
  let candidates : Array[String] = ["m_free", "m_mid"]
  // total = 1 < min_evidences = 2 → 走偏好，偏好 m_free 排第一
  let stats : Array[CafModelStats] = [
    { model: "m_free", total: 1, success: 0, avg_cost: 1.0, },
  ]
  let result = caf_soft_reorder_with_preference(
    candidates,
    stats,
    ["m_free"],
    2,
  )
  assert_eq(result[0], "m_free")
  assert_eq(result[1], "m_mid")
}

///|
/// R44 · 全角空白归一化（U+3000 全角空格）。
/// R42 的 is_ws_byte 只认 4 个 ASCII 空白字节；中文输入场景下全角空格同样起分隔作用，
/// 未归一化会导致同一语义输入产生不同 hash（碎片化同族）。
/// 钉死：全角空格被 trim，归一化后与纯 ASCII 输入的 hash 一致。
test "caf_norm_5_全角空白归一化" {
  // 直接粘贴 U+3000 全角空格，避开 escape 语法差异
  let s = "　python　"
  assert_eq(caf_normalize_context(s), "python")
  let h_ascii = caf_feature_hash(caf_normalize_context("python"))
  let h_zenkaku = caf_feature_hash(caf_normalize_context(s))
  assert_eq(h_ascii, h_zenkaku)
}

///|
/// R45 · 中间空白保留语义（接线前置语义契约）。
/// R42 契约说「trim 首尾 + lowercase」，但未锁「中间空白保留」——
/// 接线方可能误以为 normalize 删除所有空白，把 "caf model" 拼成 "cafmodel"（破坏语义）。
/// 钉死：中间空白（ASCII 空格 / 全角空格）一律保留，normalize 只 trim 首尾。

///|
/// 中间 ASCII 空格保留：trim 首尾但不删中间
test "caf_norm_6_中间空白保留" {
  assert_eq(caf_normalize_context("Py Thon"), "py thon")
  assert_eq(caf_normalize_context("a  b"), "a  b")
  assert_eq(caf_normalize_context("  a b  "), "a b")
}

///|
/// 中间全角空格保留：全角空格在中间不被删除，只在首尾被 trim
test "caf_norm_7_全角空格中间保留" {
  // 直接粘贴 U+3000 全角空格（避开 escape 语法差异）
  let s = "　Py　Thon　"
  assert_eq(caf_normalize_context(s), "py　thon")
  // 归一化后 hash 与「ASCII 空格版本」不同（全角空格非 ASCII 空白，中间保留）
  let h_zen = caf_feature_hash(caf_normalize_context("　py　thon　"))
  let h_ascii = caf_feature_hash(caf_normalize_context("py thon"))
  assert_true(h_zen != h_ascii)
}
