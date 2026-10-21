/// hat_converge.mbt —— HexaMind 六元自驱决策 · 收敛判定（纯计算）
///
/// 收敛不是投票民主：`rate >= threshold` 只说明视角一致，不代用户裁决。
/// 三态：
///   · converged：rate >= threshold 且无 verdict_conflict（视角一致、无对冲）。
///   · partial：rate >= threshold 但仍有 verdict_conflict（一致但被对冲，需再迭代或用户拍板）。
///   · diverged：rate < threshold（视角分裂，建议再迭代或换帽）。
///
/// terminal_gate 恒为 "user"——引擎只给读数，终审门在指挥官/用户。

///|
/// 收敛结果。
pub struct ConvergeResult {
  round : Int32
  max_rounds : Int32
  agree : Int32
  // verdict == pass 的单元数
  total : Int32
  // 参与统计的单元数（不含 abstain）
  rate : Double
  // agree / total
  threshold : Double
  status : String
  // converged | partial | diverged
  blocking : Int32
  // 阻止收敛的分歧（verdict_conflict）数量
  blockers : Array[String]
  // 阻止收敛的分歧详情
  should_iterate : Bool
  // 建议再迭代（status=partial 且 round < max_rounds）
  terminal_gate : String
  // 恒 "user"
}

///|
/// 计算收敛读数。round 从 1 起；rate 只把 pass 计入 agree，abstain 不进分母。
pub fn converge(
  reports : Array[HatReport],
  policy : HatPolicy,
  round : Int32,
) -> ConvergeResult {
  let threshold = policy.converge_threshold
  let mut agree = 0
  let mut total = 0
  for r in reports {
    if r.verdict == "abstain" {
      continue
    }
    total = total + 1
    if r.verdict == "pass" {
      agree = agree + 1
    }
  }
  let rate = if total == 0 {
    0.0
  } else {
    agree.to_double() / total.to_double()
  }

  let blockers = extract_divergences(reports).filter(fn(d) {
    d.kind == "verdict_conflict"
  })
  let block_details = blockers.map(fn(d) { d.detail })
  let blocking = blockers.length()

  let status = if rate < threshold {
    "diverged"
  } else if blocking > 0 {
    "partial"
  } else {
    "converged"
  }
  let should_iterate = (status == "partial" || status == "diverged") &&
    round < policy.max_rounds

  {
    round,
    max_rounds: policy.max_rounds,
    agree,
    total,
    rate,
    threshold,
    status,
    blocking,
    blockers: block_details,
    should_iterate,
    terminal_gate: "user",
  }
}

///|
/// 是否建议追加一轮迭代（含 round 已达上限的说明，交给调用方）。
pub fn ConvergeResult::next_round_hint(self : ConvergeResult) -> String {
  if self.status == "converged" {
    return "已收敛：视角一致、无对冲，建议进入裁决/归档（终审门=用户）"
  }
  if self.should_iterate {
    return "建议再迭代一轮（当前 round=" +
      self.round.to_string() +
      "/" +
      self.max_rounds.to_string() +
      "）：把 blockers 回灌给对应帽做两两辩论"
  }
  "已达轮次上限仍未收敛：把 blockers 与分歧演化交用户拍板（不再自动迭代）"
}
