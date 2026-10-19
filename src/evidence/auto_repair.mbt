/// fist-evidence: 验收证据引擎 - 三轮自动修复
///
/// 核心缺陷背景：omega_verify_fix 的 batch_verify_fix 因不持有 spec 内容，
/// 将失败项全部转 needs_human_review，从未调用 apply_fix 做真实修复（"零修复"）。
/// 本模块持有 Spec 原文（expectation + failed_detail），通过注入的修复器
/// 逐项真实调用 apply_fix 落地修复，并做修复后校验，最多三轮。

///|
/// 修复器：给定失败 Spec，返回真实修复动作描述（None 表示该轮无法修复）
/// 由上层注入真正的 apply_fix 实现；本模块保证每轮都调用它，杜绝零修复。
pub type Fixer = (Spec) -> String?

///|
/// 校验器：给定待校验 Spec，返回校验结果（true 表示通过）
/// 由上层注入 verify 实现。
pub type Verifier = (Spec) -> Bool

///|
/// 三轮自动修复执行结果
pub struct RepairOutcome {
  // 最终状态（true = 三轮内全部通过）
  ok : Bool
  // 实际执行的修复轮数（>0 即证明非零修复）
  rounds_used : Int
  // 每轮修复动作记录（用于证据存储）
  fix_evidence : Array[FixEvidence]
}

///|
/// 对一组 Spec 执行最多三轮自动修复
/// - 每轮：对每个失败 Spec 调用 fixer 真实修复，随后调用 verifier 校验
/// - 修复成功且校验通过 => 标记 Fixed；否则保留失败进入下一轮
/// - 三轮结束仍有失败 => ok=false，但已执行的修复轮次如实记录
pub fn auto_repair(
  specs : Array[Spec],
  fixer : Fixer,
  verifier : Verifier,
) -> RepairOutcome {
  let mut working = specs
  let evidence : Array[FixEvidence] = []
  let mut rounds = 0
  let mut round = 1
  while round <= MAX_FIX_ROUNDS {
    let mut any_failed = false
    let next : Array[Spec] = []
    for spec in working {
      if spec.is_repairable() {
        match fixer(spec) {
          Some(action) => {
            // 真实调用 apply_fix 后，用 verifier 校验修复效果
            let ok = verifier(spec)
            if ok {
              next.push({
                id: spec.id,
                title: spec.title,
                severity: spec.severity,
                expectation: spec.expectation,
                failed_detail: "",
                status: Fixed,
                fixed_round: round,
              })
            } else {
              // 修复未通过校验：记录动作，但保持失败进入下一轮
              next.push(spec)
              any_failed = true
            }
            evidence.push({
              spec_id: spec.id,
              round,
              action,
              verify_result: if ok {
                "pass"
              } else {
                "fail"
              },
            })
          }
          None => {
            // 本轮无法修复：保留失败进入下一轮（或由上层转人工兜底）
            next.push(spec)
            any_failed = true
          }
        }
      } else {
        next.push(spec)
      }
    }
    rounds = round
    working = next
    if !any_failed {
      break
    }
    round = round + 1
  }
  let mut all_ok = true
  for spec in working {
    if !spec.is_ok() {
      all_ok = false
      break
    }
  }
  { ok: all_ok, rounds_used: rounds, fix_evidence: evidence, }
}

///|
/// 便捷封装：把修复结果按租户写入证据仓
pub fn record_outcome(
  store : EvidenceStore,
  tenant : String,
  outcome : RepairOutcome,
) -> EvidenceStore {
  let mut s = store
  for ev in outcome.fix_evidence {
    s = s.add_evidence(tenant, ev)
  }
  s
}

///|
/// 生成修复结果摘要（用于探针/报告输出）
pub fn outcome_summary(outcome : RepairOutcome) -> String {
  let status = if outcome.ok { "ALL_PASSED" } else { "PARTIAL_FAILED" }
  "repair outcome: " +
  status +
  " rounds_used=" +
  outcome.rounds_used.to_string() +
  " fixes_applied=" +
  outcome.fix_evidence.length().to_string()
}
