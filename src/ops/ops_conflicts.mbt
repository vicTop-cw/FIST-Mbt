/// ops_conflicts.mbt —— claim 冲突检测（M4 运维：AO `--no-takeover` 语义）
///
/// 语义参考 agent-orchestrator 的 spawn `--no-takeover / --claim-pr`（拒绝重复持有）：
///   - 同一子任务**不可被二次领取**：任务非"待领取"态即存在持有者；
///   - 同一执行者**不可重复持有**同一任务，跨任务多开由 list_holdings 供上层决策。
/// claim 状态机本身已拒绝非待领取认领，本模块提供可读冲突报告与持有审计。

/// 认领前冲突校验：任务不存在、已被他人/本人持有则返回冲突详情。
/// 返回 Ok(()) 表示可安全认领（状态为待领取）。
pub fn check_claim(
  engine : @engine.FistEngine,
  task_id : String,
  assignee : String,
) -> Result[Unit, String] {
  match engine.get_task(task_id) {
    None => Err("task not found: \{task_id}")
    Some(t) =>
      if t.get_status().to_string() == "待领取" {
        Ok(())
      } else {
        match t.get_assignee() {
          Some(holder) =>
            if holder == assignee {
              Err(
                "任务冲突: \{task_id} 已由 \{assignee} 认领（状态 [\{t.status_to_string()}]），重复领取被拒绝 (--no-takeover)",
              )
            } else {
              Err(
                "任务冲突: \{task_id} 已被 \{holder} 持有（状态 [\{t.status_to_string()}]），\{assignee} 不可重复领取 (--no-takeover)",
              )
            }
          None =>
            Err(
              "任务冲突: \{task_id} 处于 [\{t.status_to_string()}] 但无 assignee，需先处理状态再认领",
            )
        }
      }
  }
}

/// 列出某人当前持有中的任务（已领取/拆分中/执行中/待验收），供 --no-takeover 决策。
pub fn list_holdings(engine : @engine.FistEngine, assignee : String) -> Array[@core.Task] {
  engine.list_all().filter(fn(t) {
    match t.get_assignee() {
      Some(a) => {
        let s = t.get_status()
        a == assignee &&
          (s.is_claimed() || s.is_splitting() || s.is_executing() || s.is_reviewing())
      }
      None => false
    }
  })
}

/// 列出全部处于"被持有"（非待领取/已完成/已归档）状态的任务，供审计。
pub fn list_contested(engine : @engine.FistEngine) -> Array[@core.Task] {
  engine.list_all().filter(fn(t) {
    let s = t.get_status()
    s.is_claimed() || s.is_splitting() || s.is_executing() || s.is_reviewing()
  })
}