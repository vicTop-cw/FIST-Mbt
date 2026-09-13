/// cost_tool.mbt — 成本统计工具：aggregate_stats + budget_check。
///
/// 为 MCP 工具提供成本查询与预算告警能力。

///|
/// 预算检查结果
/// 返回 JSON：{ limit, current, exceeded, remaining, action }
pub fn budget_check(limit : Double, current : Double) -> Json {
  let exceeded = current >= limit
  let remaining = if current < limit { limit - current } else { 0.0 }
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
    "exceeded": Json::boolean(exceeded),
    "remaining": Json::number(remaining),
    "action": Json::string(action),
    "reason": if exceeded {
      Json::string("预算超限，建议切换至免费模型或暂停任务")
    } else if remaining < limit * 0.2 {
      Json::string("预算即将不足（<20%），建议关注")
    } else {
      Json::string("预算充足")
    },
  })
}

///|
/// 从 JSON 参数计算 budget_check（供 MCP 工具调用）。
/// 输入 JSON：{ "limit": Number, "current": Number }
pub fn budget_check_json(args : Json) -> Json {
  let limit = match args.value("limit") {
    Some(Number(n, ..)) => n
    _ => 100.0
  }
  let current = match args.value("current") {
    Some(Number(n, ..)) => n
    _ => 0.0
  }
  budget_check(limit, current)
}
