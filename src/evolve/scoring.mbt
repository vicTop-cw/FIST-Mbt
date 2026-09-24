/// scoring.mbt —— 自进化闭环的可计算评分模块（域无关）
///
/// 原则：**评测是计算，绝不让 LLM 自评**。评分是纯函数，给定可复现的数值/布尔判据
/// （可对接 Omega gate / run_check 产出的 coverage、fingerprint、schema、accuracy），
/// 输出确定性的综合分、档位与门禁，保证"评分数值可复现、非 LLM 自评"。
///
/// 三个公开接口：
///   - score_artifact：综合评分（0.0~1.0）
///   - score_rank：分档（L1/L2/L3/L4）
///   - score_accept：门禁放行（供 evolve 落库 / Omega gate 复用）
/// 另附谓词 is_robust（稳健性判定）。

///|
/// 综合评分公式（返回 [0,1]）：
///
///   structural   = (fingerprint_ok ? 0.25 : 0) + (schema_ok ? 0.25 : 0)  // 结构完整分量，max 0.5
///   completeness = coverage.clamp(0,1) * 0.25                             // 覆盖度分量，max 0.25
///   correctness  = accuracy.clamp(0,1) * 0.25                             // 正确度分量，max 0.25
///
///   score = clamp(structural + completeness + correctness, 0, 1)
///
/// 理由：
///   - 结构完整性（fingerprint + schema）是硬前提，合占 0.5。产物若连"可被验证"都满足不了，
///     即便内容正确也不该排到前列；故两个结构位每个按 0.25 硬惩罚。
///   - 覆盖度与正确度各占 0.25，奖励"解得全、解得对"，线性映射可复现。
///   - 满分 1.0 当且仅当四项全优（coverage=1、fingerprint、schema、accuracy=1）。
pub fn score_artifact(
  coverage : Double,
  fingerprint_ok : Bool,
  schema_ok : Bool,
  accuracy : Double,
) -> Double {
  let structural = (if fingerprint_ok { 0.25 } else { 0.0 }) +
    (if schema_ok { 0.25 } else { 0.0 })
  let completeness = coverage.clamp(min=0.0, max=1.0) * 0.25
  let correctness = accuracy.clamp(min=0.0, max=1.0) * 0.25
  (structural + completeness + correctness).clamp(min=0.0, max=1.0)
}

///|
/// 档位分档（L4 最高），阈值自定、docstring 写明：
///   L4  score ≥ 0.85        —— 优（放行进入 DGM 高分候选）
///   L3  0.70 ≤ score < 0.85 —— 良
///   L2  0.55 ≤ score < 0.70 —— 中
///   L1  score < 0.55        —— 弱（档案库仍保留，作谱系垫脚石）
pub fn score_rank(score : Double) -> String {
  let s = score.clamp(min=0.0, max=1.0)
  if s >= 0.85 {
    "L4"
  } else if s >= 0.70 {
    "L3"
  } else if s >= 0.55 {
    "L2"
  } else {
    "L1"
  }
}

///|
/// 门禁放行：score 达到阈值（默认 0.85）即通过。
/// 供 evolve_submit 落库前 / Omega gate 复用——决策来自可计算分数，而非 LLM 主观判断。
pub fn score_accept(score : Double, threshold? : Double = 0.85) -> Bool {
  score >= threshold
}

///|
/// 稳健性谓词：score 不低于 floor（默认 0.70）视为稳健产物。
/// 用于在采样/蒸馏前过滤掉脆弱产物。
pub fn is_robust(score : Double, floor? : Double = 0.70) -> Bool {
  score >= floor
}
