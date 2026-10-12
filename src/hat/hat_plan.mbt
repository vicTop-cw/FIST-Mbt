/// hat_plan.mbt —— HexaMind 六元自驱决策 · 编排计划（纯计算，可 dry-run）
///
/// 引擎不自己发 HTTP：它只产出「每个单元该用什么模型、该给什么 prompt、该收什么 schema」，
/// 真正的模型调用交给 `executor_run`（ofm 并存通道）。`build_plan` 一次给出：
///   · tasks：每个已选六元一个单元任务（含 lane / temperature / max_tokens / prompt）；
///   · nucleus：星核（蓝帽）合成任务，恒在，负责收敛与报告；
///   · debate_pairs：由分歧潜势生成的「两两辩论」计划（黑黄、红绿），按 hat_policy 开关。
///
/// prompt 是可直接喂给 executor_run 的正文：角色指令 + 议题 + 输出契约 + 终审门边界。
/// executor_hint 恒 "ofm"（走并存 HTTP 通道）；dry_run_shape 说明调用形状供 dry_run 校验。

///|
/// 一个单元任务（可交给 executor_run 执行）。
pub struct ElementTask {
  pub element_id : String
  pub lane : String
  // free_pool | paid_pool | balanced
  pub temperature : Double
  pub max_tokens : Int
  pub output_schema : Array[String]
  pub prompt : String
  // 可直接喂 executor_run 的正文
  pub executor_hint : String
  // 恒 "ofm"（并存 HTTP 通道）
  pub dry_run_shape : String
  // 调用形状说明（dry_run 校验用）
}

///|
/// 一对帽子就该议题交锋的辩论计划。
pub struct DebatePair {
  pub left : String
  // 六元代号 A
  pub right : String
  // 六元代号 B
  pub issue : String
  // 交锋议题
  pub rounds : Int
}

///|
/// 一次 HexaMind 编排计划。
pub struct HatPlan {
  pub topic : String
  pub config : HatConfig
  pub tasks : Array[ElementTask]
  pub debate_pairs : Array[DebatePair]
  pub nucleus : ElementTask
}

///|
/// 生成编排计划：每帽一任务 + 星核合成任务 + 分歧潜势驱动的辩论对。
pub fn build_plan(topic : String, config : HatConfig) -> HatPlan {
  let tasks = config.elements.map(fn(e) { element_task(topic, e) })
  let nucleus_task = element_task(topic, nucleus())
  let pairs = if config.policy.debate_enabled {
    debate_pairs_of(config)
  } else {
    []
  }
  { topic, config, tasks, debate_pairs: pairs, nucleus: nucleus_task, }
}

///|
/// 给一个六元生成单元任务（prompt = 角色 + 议题 + 输出契约 + 终审门边界）。
pub fn element_task(topic : String, e : HexaElement) -> ElementTask {
  let schema = join_schema(e.output_schema)
  let prompt = e.role +
    "\n\n【议题】" +
    topic +
    "\n\n【输出契约：必须逐项给出，缺一退回】" +
    schema +
    "\n\n【终审门】你只负责从本视角给出结构化结论；是否采纳由星核收敛 + 指挥官/用户裁决。" +
    "\n【输出格式】返回 JSON 对象，键为上述 schema 字段；verdict ∈ {pass,reject,abstain}，" +
    "confidence ∈ [0,1]，evidence 必填非空。"
  {
    element_id: e.id,
    lane: e.lane,
    temperature: e.temperature,
    max_tokens: e.max_tokens,
    output_schema: e.output_schema,
    prompt,
    executor_hint: "ofm",
    dry_run_shape: "executor_run(executor=ofm, model=<" +
    e.lane +
    " 路由>, temperature=" +
    e.temperature.to_string() +
    ", max_tokens=" +
    e.max_tokens.to_string() +
    ", prompt=<本 prompt>)",
  }
}

///|
/// 由分歧潜势生成辩论对：黑↔黄（风险 vs 价值）、红↔绿（直觉 vs 创意）。
fn debate_pairs_of(config : HatConfig) -> Array[DebatePair] {
  let out : Array[DebatePair] = []
  if has(config, "wallbreaker") && has(config, "golddigger") {
    out.push(
      debate_pair(
        "wallbreaker", "golddigger", "风险 vs 价值：该议题的致命缺陷与核心价值可否对冲（破壁者先摆坑，掘金者说清价值）",
        1,
      ),
    )
  }
  if has(config, "pulse") && has(config, "nova") {
    out.push(
      debate_pair(
        "pulse", "nova", "直觉 vs 创意：发散方向是否偏离可行性（脉冲给感觉信号，新星给替代路径）",
        1,
      ),
    )
  }
  out
}

///|
/// 构造辩论对。**跨包构造必需**。
pub fn debate_pair(
  left : String,
  right : String,
  issue : String,
  rounds : Int,
) -> DebatePair {
  { left, right, issue, rounds, }
}

///|
fn has(config : HatConfig, id : String) -> Bool {
  config.elements.any(fn(e) { e.id == id })
}

///|
fn join_schema(items : Array[String]) -> String {
  let mut out = ""
  for i = 0; i < items.length(); i = i + 1 {
    if i > 0 {
      out = out + ", "
    }
    out = out + items[i]
  }
  out
}
