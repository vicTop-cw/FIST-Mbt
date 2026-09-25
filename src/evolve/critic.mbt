/// evolve/critic.mbt —— Critic 防漂移门禁（SAGE 论文信号落地，AI 自进化增强）
///
/// 论文背景：SAGE 提出四智能体专家环中 Critic 负责给产物/训用于滤信号的打分与质疑，
/// 防止"课程漂移"（模型不断接受彼此趋同的错误信号、质量退化）。
///
/// 对应到 fist-mbt：`evolve_distill` 蒸馏 [principle]、`evolve_lesson` 归档 [lesson] 时，
/// 若不做把关，DGM 档案库会积累大量低质/重复资产，检索注入反而被噪声淹没。
/// 本模块提供"Critic 评审"这一纯计算门禁（复用 Archive::novelty + scoring，绝不让 LLM 自评）：
///   - critic_most_similar：在档案库中找与候选 note 最相似的既有资产（漂移/重复探测）；
///   - critic_review：综合"稳健性(score) × 新颖度(novelty)"给出 {admit/reject + 理由}，
///     近重复(重合 ≥ dup_sim)直接判 reject，阻断课程漂移；低稳健平均分也判 reject。
///
/// 纯函数、同包私有 tokens/jaccard 直接复用，无新表/依赖；供 server 的 `evolve_critic` 工具调用。

///|
/// 相似度 ≥ 该值判为"疑似重复/课程漂移"，直接建议 reject。
/// 经验阈值：Jaccard 词集重合 0.70 足可视为同一路线。
pub fn critic_dup_sim() -> Double {
  0.70
}

///|
/// 在档案库中找与候选 note 最相似的既有资产，返回 (id, note, 相似度)。
/// 找不到（空库/候选空）返回 None。
pub fn critic_most_similar(
  arc : Archive,
  note : String,
) -> (String, String, Double)? {
  let n = tokens(note)
  if n.is_empty() || arc.is_empty() {
    return None
  }
  let mut best : (String, String, Double) = ("", "", 0.0)
  for a in Archive::all(arc) {
    let t = tokens(a.note)
    if not(t.is_empty()) {
      let j = jaccard(n, t)
      if j > best.2 {
        best = (a.id, a.note, j)
      }
    }
  }
  if best.2 <= 0.0 {
    None
  } else {
    Some(best)
  }
}

///|
/// Critic 综合评审（SAGE Critic 角色，纯计算）：
///   - novelty      = Archive::novelty(note)      （相对档案库新鲜度 [0,1]）
///   - sim          = 与最相似既有资产的重合度（最相似者）
///   - combined     = 0.5*score + 0.5*novelty     （稳健性 × 新颖度，防"高分但重复"）
///   - admit        = sim < dup_sim 且 score_accept(combined, threshold)
/// 返回决策 JSON：{ admit, novelty, score, combined, threshold, sim, rank, reason, top_hit? }。
pub fn critic_review(
  arc : Archive,
  note : String,
  score : Double,
  threshold? : Double = 0.85,
) -> Json {
  let novelty = arc.novelty(note)
  let sim = match critic_most_similar(arc, note) {
    Some((_, _, j)) => j
    None => 0.0
  }
  let combined = (0.5 * score + 0.5 * novelty).clamp(min=0.0, max=1.0)
  let dup = sim >= critic_dup_sim()
  let ok = not(dup) && score_accept(combined, threshold~)
  let reason = if dup {
    "\{score_rank(combined)} 疑似课程漂移/重复：与档案库最相似资产重合 \{fmt_pct(sim)}（≥\{fmt_pct(critic_dup_sim())}），建议先赋新目标或拒绝入库"
  } else if not(ok) {
    "\{score_rank(combined)} 稳健性不足：平均分 \{fmt_pct(combined)} < 阈值 \{fmt_pct(threshold)}，暂缓入库"
  } else {
    "\{score_rank(combined)} 放行：新颖度 \{fmt_pct(novelty)}、稳健平均分 \{fmt_pct(combined)} ≥ \{fmt_pct(threshold)}，无重复漂移"
  }
  let m : Map[String, Json] = Map([
    ("admit", Json::boolean(ok)),
    ("novelty", Json::number(novelty)),
    ("score", Json::number(score.clamp(min=0.0, max=1.0))),
    ("combined", Json::number(combined)),
    ("threshold", Json::number(threshold)),
    ("sim", Json::number(sim)),
    ("rank", Json::string(score_rank(combined))),
    ("reason", Json::string(reason)),
  ])
  match critic_most_similar(arc, note) {
    Some((id, n, j)) =>
      m.set(
        "top_hit",
        Json::object({
          "id": Json::string(id),
          "note": Json::string(n),
          "sim": Json::number(j),
        }),
      )
    None => ()
  }
  Json::object(m)
}

///|
/// 辅导：把 0..1 刻度转成百分比显示（整数，如 0.85 -> "85%"）。
fn fmt_pct(x : Double) -> String {
  (x * 100.0).round().to_string() + "%"
}
