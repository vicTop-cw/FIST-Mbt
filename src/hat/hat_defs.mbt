/// hat_defs.mbt —— HexaMind 六元自驱决策 · 六元角色注册表（R119，方向三 P1-c）
///
/// 在 `src/ops/ops_hats.mbt`（六顶帽语义注册表，R118）之上，把每顶帽固化成
/// 「一个并行 Agent 单元」：六元代号 + 对应六顶帽 + 模型车道 + 采样参数 +
/// 输出契约 + 角色指令。**帽子即 Agent，分歧即燃料，收敛即产出**。
///
/// 设计要点（docs/fist-mbt-hexamind-design-20261012.md §3）：
///   · 每顶帽 = 一个独立 subagent，各带模型偏好与输出 schema（模型策略分池）。
///   · 分歧由程序化提取（见 hat_divergence.mbt），不等 LLM 自评"有没有分歧"。
///   · 收敛是确定性读数（见 hat_converge.mbt），终态门仍是用户。
///   · 成本取舍：探索帽走 free_pool、裁决/批判帽走 paid_pool，轮次上限默认 2。
///
/// 单真源：六元 id ↔ 六顶帽 id 的双向映射只在本文件定义；config / plan / report
/// 三态都只通过本文件解析帽子字符串 → 六元。**本包刻意自包含、零网络**：
/// 引擎只产出「每个单元该用什么模型、该给什么 prompt、该收什么 schema」，
/// 真正的模型调用交给 `executor_run`（OFM 并存 HTTP 通道，R119 接线）。
///
/// 诚实边界：六元是「多视角证据收敛」，不是投票民主。`rate >= threshold` 只说明
/// 视角一致性，不等于"结论正确"——真正裁决权在指挥官/用户（terminal_gate=user）。

// ---------------------------------------------------------------------------
// 六元元素
// ---------------------------------------------------------------------------

///|
/// 一个 HexaMind 单元（一顶帽 + 一份模型策略 + 一份输出契约）。
/// 字段全部 pub：跨包（`src/server` 的 hat_* 工具）需构造与读取。
pub struct HexaElement {
  id : String
  // 六元代号：stargazer | pulse | wallbreaker | golddigger | nova | nucleus
  hat_id : String
  // 对应六顶帽 id：white | red | black | yellow | green | blue（对齐 ops_hats）
  name_zh : String
  // 中文代号
  lane : String
  // 模型车道：free_pool | paid_pool | balanced（交给 model_route 分池）
  temperature : Double
  max_tokens : Int
  output_schema : Array[String]
  // 该元必须逐项给出的字段
  role : String
  // 角色指令（六顶帽基础角色 + 六元强化），可直接拼进发给 subagent 的 prompt
}

///|
/// 六元全量（固定顺序：白/红/黑/黄/绿/蓝 → 观星者/脉冲/破壁者/掘金者/新星/星核）。
pub fn hexa_elements() -> Array[HexaElement] {
  [stargazer(), pulse(), wallbreaker(), golddigger(), nova(), nucleus()]
}

///|
/// 六元代号 → 六顶帽 id（单真源映射，config/plan/report 三态复用）。
pub fn hexa_hat_id(hexa_id : String) -> String {
  match hexa_id {
    "stargazer" => "white"
    "pulse" => "red"
    "wallbreaker" => "black"
    "golddigger" => "yellow"
    "nova" => "green"
    "nucleus" => "blue"
    _ => ""
  }
}

///|
/// 六顶帽 id → 六元代号（单真源反向映射；未知帽 id 返回空串）。
pub fn hat_to_hexa(hat_id : String) -> String {
  match hat_id {
    "white" => "stargazer"
    "red" => "pulse"
    "black" => "wallbreaker"
    "yellow" => "golddigger"
    "green" => "nova"
    "blue" => "nucleus"
    _ => ""
  }
}

///|
/// 六元代号 → 六元元素；未知代号返回 Err。
pub fn hexa_for_id(id : String) -> Result[HexaElement, String] {
  for e in hexa_elements() {
    if e.id == id {
      return Ok(e)
    }
  }
  Err(
    "未知六元: " +
    id +
    "，可选: stargazer|pulse|wallbreaker|golddigger|nova|nucleus",
  )
}

///|
/// 把调用面给的帽子标识解析成**六元代号**：既接受六元 id（stargazer），
/// 也接受六顶帽 id（white）——单真源归一，其余一律 Err（不静默回落）。
pub fn resolve_element_id(s : String) -> Result[String, String] {
  let t = s.trim().to_string()
  if t.is_empty() {
    return Err("帽子标识不能为空")
  }
  // 先试六元 id
  match hexa_for_id(t) {
    Ok(_) => return Ok(t)
    Err(_) => ()
  }
  // 再试六顶帽 id
  match valid_hat_id(t) {
    true => Ok(hat_to_hexa(t))
    false =>
      Err(
        "未知帽子标识: " +
        t +
        "，可选六元 stargazer|pulse|wallbreaker|golddigger|nova|nucleus " +
        "或帽 white|red|black|yellow|green|blue",
      )
  }
}

///|
/// 是否是合法六顶帽 id（白名单，大小写敏感）。
pub fn valid_hat_id(s : String) -> Bool {
  match s {
    "white" => true
    "red" => true
    "black" => true
    "yellow" => true
    "green" => true
    "blue" => true
    _ => false
  }
}

///|
/// 是否是合法六元代号。
pub fn valid_hexa_id(s : String) -> Bool {
  match hexa_for_id(s) {
    Ok(_) => true
    Err(_) => false
  }
}

// ---------------------------------------------------------------------------
// 六元工厂
// ---------------------------------------------------------------------------

///|
/// 组装一个六元元素（角色 = 六顶帽基础角色 + 六元强化）。
fn mk(
  id : String,
  hat_id : String,
  name_zh : String,
  lane : String,
  temperature : Double,
  max_tokens : Int,
  output_schema : Array[String],
  hexa_note : String,
) -> HexaElement {
  {
    id,
    hat_id,
    name_zh,
    lane,
    temperature,
    max_tokens,
    output_schema,
    role: base_hat_role(hat_id) + hexa_note,
  }
}

///|
/// 六顶帽基础角色（本包自包含的内联版本，语义与 ops_hats.hat_role 对齐）。
fn base_hat_role(hat_id : String) -> String {
  match hat_id {
    "white" =>
      "你是白帽（事实）。只陈述客观数据、已证事实、可查证据；不推断、不给建议、不评判好坏。"
    "red" =>
      "你是红帽（直觉）。只说出你当下的感觉、直觉、审美偏好；不解释理由、不必自圆其说。"
    "black" =>
      "你是黑帽（风险）。只找失败模式、风险、反例、成本、合规隐患；不提供解决方案、不权衡利弊。"
    "yellow" =>
      "你是黄帽（收益）。只找好处、机会、价值、可行性、正向连锁反应；不挑刺、不说成本。"
    "green" =>
      "你是绿帽（创意）。只产生新方案、替代路径、可能性；不评判可行性、不自我审查，数量优先于质量。"
    "blue" =>
      "你是蓝帽（过程）。只做元认知：梳理其他帽子的结构、找遗漏视角、判定是否该加帽子或收敛；不亲自讨论议题本身。"
    _ => ""
  }
}

///|
/// 白帽 · 观星者 stargazer：摆事实、标来源、单列未证实项；不判断。
pub fn stargazer() -> HexaElement {
  mk(
    "stargazer",
    "white",
    "观星者",
    "free_pool",
    0.2,
    2048,
    ["facts", "sources", "unverified"],
    "（HexaMind 观星者：把已证事实与来源摆清，未证实项单列，不下判断、不给建议。）",
  )
}

///|
/// 红帽 · 脉冲 pulse：当下感觉与直觉信号；快而糙也可以。
pub fn pulse() -> HexaElement {
  mk(
    "pulse",
    "red",
    "脉冲",
    "free_pool",
    1.0,
    1024,
    ["gut_signal", "intuition"],
    "（HexaMind 脉冲：给当下的感觉与直觉信号，可以快、可以糙，不需要自圆其说。）",
  )
}

///|
/// 黑帽 · 破壁者 wallbreaker：把失败模式与致命缺陷挖干净，宁可多不可漏。
pub fn wallbreaker() -> HexaElement {
  mk(
    "wallbreaker",
    "black",
    "破壁者",
    "paid_pool",
    0.3,
    4096,
    ["risks", "fatal_flaws", "evidence"],
    "（HexaMind 破壁者：把失败模式与致命缺陷挖干净，宁可多不可漏；不给解决方案。）",
  )
}

///|
/// 黄帽 · 掘金者 golddigger：把价值、机会与可接受条件说清。
pub fn golddigger() -> HexaElement {
  mk(
    "golddigger",
    "yellow",
    "掘金者",
    "balanced",
    0.6,
    2048,
    ["benefits", "opportunities", "acceptance"],
    "（HexaMind 掘金者：把价值、机会与可接受条件说清；不挑风险、不否定。）",
  )
}

///|
/// 绿帽 · 新星 nova：先发散后收敛，数量优先于质量。
pub fn nova() -> HexaElement {
  mk(
    "nova",
    "green",
    "新星",
    "free_pool",
    1.1,
    2048,
    ["alternatives", "imaginative_paths"],
    "（HexaMind 新星：先发散后收敛，数量优先于质量；不自我审查。）",
  )
}

///|
/// 蓝帽 · 星核 nucleus：只做元收敛——梳理分歧、判定是否再迭代、给最终裁决与报告。
pub fn nucleus() -> HexaElement {
  mk(
    "nucleus",
    "blue",
    "星核",
    "paid_pool",
    0.2,
    4096,
    ["verdict", "divergence", "report"],
    "（HexaMind 星核：只做元收敛——梳理其他元的分歧、判定是否再迭代、给最终裁决与报告；不亲自讨论议题本身。）",
  )
}

///|
/// 把帽子标识数组解析成**六元代号数组**（去重、保序）；任一非法即整批 Err。
pub fn resolve_elements(items : Array[String]) -> Result[Array[String], String] {
  let out : Array[String] = []
  for i = 0; i < items.length(); i = i + 1 {
    match resolve_element_id(items[i]) {
      Ok(id) => if !out.contains(id) { out.push(id) }
      Err(e) => return Err(e)
    }
  }
  Ok(out)
}

///|
/// 默认三元（D3 决策点确认：白帽+黑帽+黄帽 = 观星者+破壁者+掘金者）。
pub fn hexa_defaults() -> Array[String] {
  ["wallbreaker", "golddigger", "stargazer"]
}
