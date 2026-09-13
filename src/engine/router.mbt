/// router.mbt — 成本档路由：将 complexity/cost_tier 映射到执行器与运行策略。
///
/// 路由规则：
///   free     → McpDelegateExecutor（默认客户端）
///   premium  → McpDelegateExecutor（标注高优先级，客户端可分配更多资源）
///   hold     → 返回 hold_reason，等待人类确认
///   L4 风险  → 强制 hold

///|
/// 路由结果
/// 返回 JSON：{ executor, cost_tier, hold, priority, reason }
pub fn route(complexity : String, cost_tier : String) -> Json {
  if cost_tier == "hold" || complexity == "L4_irreversible" {
    return Json::object({
      "executor": Json::string("manual"),
      "cost_tier": Json::string("hold"),
      "hold": Json::boolean(true),
      "priority": Json::string("blocked"),
      "reason": Json::string(
        "不可逆/高风险操作，需人类手动确认后执行",
      ),
    })
  }
  if cost_tier == "premium" {
    Json::object({
      "executor": Json::string("McpDelegateExecutor"),
      "cost_tier": Json::string("premium"),
      "hold": Json::boolean(false),
      "priority": Json::string("high"),
      "reason": Json::string("复杂任务，分配高优先级资源"),
    })
  } else {
    // free / L1 / L2
    Json::object({
      "executor": Json::string("McpDelegateExecutor"),
      "cost_tier": Json::string("free"),
      "hold": Json::boolean(false),
      "priority": Json::string("normal"),
      "reason": Json::string("标准任务，常规执行"),
    })
  }
}

///|
/// 组合 schedule + route：输入 description + n_files，输出完整调度+路由方案。
/// 返回 JSON：{ schedule: {...}, route: {...} }
pub fn plan_route(description : String, n_files? : Int = 1) -> Json {
  // 复用 scheduler 逻辑
  let len = description.length()
  let complexity = if contains_risk_kw(description) {
    "L4_irreversible"
  } else if n_files <= 1 && len < 50 {
    "L1_simple"
  } else if len <= 200 {
    "L2_standard"
  } else {
    "L3_complex"
  }
  let cost_tier = match complexity {
    "L1_simple" => "free"
    "L2_standard" => "free"
    "L3_complex" => "premium"
    "L4_irreversible" => "hold"
    _ => "free"
  }
  Json::object({
    "schedule": Json::object({
      "complexity": Json::string(complexity),
      "cost_tier": Json::string(cost_tier),
    }),
    "route": route(complexity, cost_tier),
  })
}

///|
fn contains_risk_kw(desc : String) -> Bool {
  let lower = desc.to_lower()
  let kws = [
    "delete", "drop", "truncate", "destroy", "publish", "deploy", "reset", "force",
  ]
  for kw in kws {
    if lower.contains(kw.to_lower()) {
      return true
    }
  }
  false
}
