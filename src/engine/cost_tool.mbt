/// cost_tool.mbt — 成本统计工具：aggregate_stats + budget_check。
///
/// 为 MCP 工具提供成本查询与预算告警能力。

///|
/// 预算检查结果
/// 返回 JSON：{ limit, current, valid, exceeded, remaining, action, reason }
///
/// BUG-181 契约（三条回归锁钉在 src/engine/cost_tool_test.mbt）：
/// ① 超支时 remaining 为负（= current - limit 的相反数，即 limit-current），
///    不静默归零——超支额必须可见；
/// ② limit<=0 视为**非法预算**：valid=false + exceeded=false + action=rejected，
///    不报误导性的 "switch_free"（旧实现里 current>=limit 恒真 ⇒ 谎报超支）。
pub fn budget_check(limit : Double, current : Double) -> Json {
  // BUG-181②：非法预算短路，不做超支判定
  if limit <= 0.0 {
    Json::object({
      "limit": Json::number(limit),
      "current": Json::number(current),
      "valid": Json::boolean(false),
      "exceeded": Json::boolean(false),
      "remaining": Json::number(limit - current),
      "action": Json::string("rejected"),
      "reason": Json::string(
        "非法预算：limit 必须为正，不做超支判定",
      ),
    })
  } else {
    let exceeded = current >= limit
    // BUG-181①：超支时保留负值（=超支额），不抹成 0
    let remaining = limit - current
    let action = if exceeded {
      "switch_free"
    } else if remaining < limit * 0.2 {
      "notify"
    } else {
      "continue"
    }
    Json::object({
      "limit": Json::number(limit),
      "current": Json::number(current),
      "valid": Json::boolean(true),
      "exceeded": Json::boolean(exceeded),
      "remaining": Json::number(remaining),
      "action": Json::string(action),
      "reason": if exceeded {
        Json::string(
          "预算超限，超支额 " +
          (current - limit).to_string() +
          "，建议切换至免费模型或暂停任务",
        )
      } else if remaining < limit * 0.2 {
        Json::string("预算即将不足（<20%），建议关注")
      } else {
        Json::string("预算充足")
      },
    })
  }
}

///|
/// 从 JSON 参数计算 budget_check（供 MCP 工具调用）。
/// 输入 JSON：{ "limit": Number, "current": Number }
pub fn budget_check_json(args : Json) -> Json {
  // BUG-211：缺 limit 时不得回退 100.0（那会谎报「预算充足」）。
  // 回退 0.0 → 走 budget_check 的非法预算分支（valid=false / rejected）。
  // 注意：MCP schema 已声明 limit 必填，本分支是直连/宽松客户端的防御面。
  let limit = match args.value("limit") {
    Some(Number(n, ..)) => n
    _ => 0.0
  }
  let current = match args.value("current") {
    Some(Number(n, ..)) => n
    _ => 0.0
  }
  budget_check(limit, current)
}
