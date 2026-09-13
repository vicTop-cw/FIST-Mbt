/// scheduler.mbt — 任务分级调度：根据描述/项目特征自适应计算拆分参数。
///
/// 分级规则（对齐 FIST Python L1-L4）：
///   L1（单文件 / <50 字）  → n_split=1, depth=1, parallel=1, cost_tier=free
///   L2（多文件 / 50-200 字）→ n_split=3, depth=2, parallel=2, cost_tier=free
///   L3（重构 / >200 字）   → n_split=5, depth=3, parallel=3, cost_tier=premium
///   L4（不可逆 / 高风险）   → hold=true, cost_tier=hold
///
/// 关键词命中 delete/drop/publish/deploy/reset → 自动升至 L4。

///|
/// 复杂度分级枚举（文本常量）
pub const COMPLEXITY_L1 : String = "L1_simple"

///|
pub const COMPLEXITY_L2 : String = "L2_standard"

///|
pub const COMPLEXITY_L3 : String = "L3_complex"

///|
pub const COMPLEXITY_L4 : String = "L4_irreversible"

///|
/// 成本档枚举
pub const COST_TIER_FREE : String = "free"

///|
pub const COST_TIER_PREMIUM : String = "premium"

///|
pub const COST_TIER_HOLD : String = "hold"

///|
/// 高风险关键词表（命中即升至 L4）
fn risk_keywords() -> Array[String] {
  [
    "delete", "drop", "truncate", "destroy", "remove", "publish", "deploy", "release",
    "reset", "force", "override", "migrate", "backup-restore",
  ]
}

///|
/// 检测描述中是否包含高风险关键词
fn contains_risk_keyword(desc : String) -> Bool {
  let lower = desc.to_lower()
  let kws = risk_keywords()
  for i = 0; i < kws.length(); i = i + 1 {
    if lower.contains(kws[i].to_lower()) {
      return true
    }
  }
  false
}

///|
/// 核心调度函数：根据描述长度、文件数、风险词计算分级与参数。
///
/// 输入：
///   desc       任务描述文本
///   n_files    涉及文件数（可选，默认 1）
/// 返回 JSON：
///   { complexity, n_split, depth, parallel, cost_tier, hold, reason }
pub fn schedule_task(desc : String, n_files? : Int = 1) -> Json {
  // 1. 风险检查
  if contains_risk_keyword(desc) {
    return Json::object({
      "complexity": Json::string(COMPLEXITY_L4),
      "n_split": Json::number(0.0),
      "depth": Json::number(0.0),
      "parallel": Json::number(0.0),
      "cost_tier": Json::string(COST_TIER_HOLD),
      "hold": Json::boolean(true),
      "executor": Json::string("manual"),
      "reason": Json::string("高风险操作，需人类确认后执行"),
    })
  }
  // 2. 按描述长度 + 文件数分级
  let len = desc.length()
  if n_files <= 1 && len < 50 {
    // L1：轻量任务
    Json::object({
      "complexity": Json::string(COMPLEXITY_L1),
      "n_split": Json::number(1.0),
      "depth": Json::number(1.0),
      "parallel": Json::number(1.0),
      "cost_tier": Json::string(COST_TIER_FREE),
      "hold": Json::boolean(false),
      "executor": Json::string("McpDelegateExecutor"),
      "reason": Json::string("单文件轻量任务，快速执行"),
    })
  } else if len <= 200 {
    // L2：标准任务
    Json::object({
      "complexity": Json::string(COMPLEXITY_L2),
      "n_split": Json::number(3.0),
      "depth": Json::number(2.0),
      "parallel": Json::number(2.0),
      "cost_tier": Json::string(COST_TIER_FREE),
      "hold": Json::boolean(false),
      "executor": Json::string("McpDelegateExecutor"),
      "reason": Json::string("多文件标准任务，适度并行"),
    })
  } else {
    // L3：复杂任务
    Json::object({
      "complexity": Json::string(COMPLEXITY_L3),
      "n_split": Json::number(5.0),
      "depth": Json::number(3.0),
      "parallel": Json::number(3.0),
      "cost_tier": Json::string(COST_TIER_PREMIUM),
      "hold": Json::boolean(false),
      "executor": Json::string("McpDelegateExecutor"),
      "reason": Json::string("大规模重构或复杂任务，高资源投入"),
    })
  }
}

///|
/// 从 JSON 参数中计算 schedule（供 MCP 工具调用）。
/// 输入 JSON：{ "description": String, "n_files"? : Int }
pub fn schedule_json(args : Json) -> Json {
  let desc = match args.value("description") {
    Some(String(s)) => s
    _ => ""
  }
  let n_files = match args.value("n_files") {
    Some(Number(n, ..)) => n.to_int()
    _ => 1
  }
  schedule_task(desc, n_files~)
}
