/// ops_hats.mbt —— 六顶思维帽（Edward de Bono）注册表（R118，方向三 P1-b）
///
/// 纯计算、零依赖。与 ops_modes（模式注册表）同族：模式是"做什么"的语义约束，
/// 帽子是"用什么视角看同一议题"的语义约束。二者互补不重叠。
///
/// 设计要点（docs/improvement-plan-20261010.md §4）：
///   · 六帽选 ≥2；默认 3 顶（White+Black+Yellow，D3 决策点已确认），可扩到 6。
///   · 每顶帽子 = 一个 subagent，输入 = 议题 + 本模块的帽子角色模板，输出 = 结构化结论。
///   · 输出 schema 对齐 eval_feedback 的四段式契约（Defects/Evidence/Fix/Acceptance）。
///   · 终审门 = 用户拍板；debate_summary 只算「多帽一致性」为确定性结果，不代用户决定。
///   · 防课程漂移：帽子结论的聚合结果可交 evolve_critic / goal_drift_check 做同质化过滤。
///   · 单真源：debate_* 工具、CLI、文档三态都只通过本模块解析帽子字符串 → 枚举 → 模板。
///
/// 诚实边界：六顶帽是「多视角证据收敛」，不是投票民主。rate >= threshold 只说明
/// 视角一致性，不等于"结论正确"——真正裁决权在指挥官/用户。

// ---------------------------------------------------------------------------
// 六顶帽子枚举
// ---------------------------------------------------------------------------

///|
/// 六顶思维帽。枚举构造函数公开，供黑盒测试与跨包匹配。
pub enum Hat {
  White // 白帽 · 事实/数据：客观数据，不下判断、不给建议
  Red // 红帽 · 情绪/直觉：当下的感觉、直觉、审美，不解释理由
  Black // 黑帽 · 风险/反例：失败模式、风险、反例、成本
  Yellow // 黄帽 · 收益/乐观：好处、机会、价值、可行性
  Green // 绿帽 · 创意/新想法：新方案、替代、想象力、可能性
  Blue // 蓝帽 · 元认知/过程：收敛、组织、下一步、帽子本身
}

// ---------------------------------------------------------------------------
// 枚举 ↔ 字符串 互转
// ---------------------------------------------------------------------------

///|
/// 默认帽子集 = 3 顶（White+Black+Yellow，D3 已确认默认 3）。
pub fn hat_defaults() -> Array[Hat] {
  [White, Black, Yellow]
}

///|
/// 帽子字符串 → Hat。非法值返回 Err。与 ops_modes::parse_mode 同约定：
/// 大小写敏感（trim 后逐字匹配），"WHITE" 视为非法而非静默转小写。
pub fn parse_hat(s : String) -> Result[Hat, String] {
  let t = s.trim().to_string()
  match t {
    "white" => Ok(White)
    "red" => Ok(Red)
    "black" => Ok(Black)
    "yellow" => Ok(Yellow)
    "green" => Ok(Green)
    "blue" => Ok(Blue)
    _ => Err("未知帽子: " + t + ", 可选: white|red|black|yellow|green|blue")
  }
}

///|
/// 批量解析帽子字符串数组，任一非法即整批 Err（避免部分生效造成半桶结论）。
pub fn parse_hats(items : Array[String]) -> Result[Array[Hat], String] {
  let out : Array[Hat] = []
  for i = 0; i < items.length(); i = i + 1 {
    match parse_hat(items[i]) {
      Ok(h) => out.push(h)
      Err(e) => return Err(e)
    }
  }
  Ok(out)
}

// ---------------------------------------------------------------------------
// 帽子元数据
// ---------------------------------------------------------------------------

///|
/// 帽子英文 id（工具参数 / 落盘用）。
pub fn hat_id(h : Hat) -> String {
  match h {
    White => "white"
    Red => "red"
    Black => "black"
    Yellow => "yellow"
    Green => "green"
    Blue => "blue"
  }
}

///|
/// 帽子中文名 + 一句话（UI / 文档用）。
pub fn hat_name_zh(h : Hat) -> String {
  match h {
    White => "白帽 · 事实"
    Red => "红帽 · 直觉"
    Black => "黑帽 · 风险"
    Yellow => "黄帽 · 收益"
    Green => "绿帽 · 创意"
    Blue => "蓝帽 · 过程"
  }
}

///|
/// 帽子主题色（渲染/标记用；白帽中性灰、红帽红、黑帽黑、黄帽黄、绿帽绿、蓝帽蓝）。
pub fn hat_color(h : Hat) -> String {
  match h {
    White => "#9e9e9e"
    Red => "#c62828"
    Black => "#212121"
    Yellow => "#f9a825"
    Green => "#2e7d32"
    Blue => "#1565c0"
  }
}

// ---------------------------------------------------------------------------
// 帽子角色模板（单真源：发给 subagent 的角色指令正文）
// ---------------------------------------------------------------------------

///|
/// 帽子角色指令：给该顶帽子的 subagent 的角色设定。每顶帽子必须只从自己的视角看议题。
pub fn hat_role(h : Hat) -> String {
  match h {
    White =>
      "你是白帽（事实）。只陈述客观数据、已证事实、可查证据；" +
      "不推断、不给建议、不评判好坏。凡是无据可查的论断都要标注「未证实」。"
    Red =>
      "你是红帽（直觉）。只说出你当下的感觉、直觉、审美偏好；" +
      "不解释理由、不给逻辑论证、不必自圆其说。直觉也是有效信息。"
    Black =>
      "你是黑帽（风险）。只找失败模式、风险、反例、成本、合规隐患；" +
      "不提供解决方案、不权衡利弊。你的价值在于把坑挖出来。"
    Yellow =>
      "你是黄帽（收益）。只找好处、机会、价值、可行性、正向连锁反应；" +
      "不挑刺、不说成本。你的价值在于把价值说清。"
    Green =>
      "你是绿帽（创意）。只产生新方案、替代路径、可能性、想象力；" +
      "不评判可行性、不自我审查。数量优先于质量，先发散后收敛。"
    Blue =>
      "你是蓝帽（过程）。只做元认知：梳理其他帽子的结构、找遗漏视角、" +
      "提出下一步、判定是否该加帽子或收敛；不亲自讨论议题本身。"
  }
}

///|
/// 帽子禁做事项：每顶帽子明确禁做的事，防帽子漂移（六帽最怕七顶帽子说同一句话）。
pub fn hat_forbid(h : Hat) -> String {
  match h {
    White =>
      "禁止：推测、价值观判断、解决方案建议；禁止把传闻当事实。"
    Red =>
      "禁止：解释直觉背后的逻辑、为直觉辩护、把直觉包装成事实。"
    Black =>
      "禁止：给方案、唱赞歌、权衡利弊、做可行性结论。"
    Yellow =>
      "禁止：挑风险、算成本、否定；禁止与黑帽重复。"
    Green =>
      "禁止：评判、可行性分析、自我审查；禁止与黄帽只复述已有好处。"
    Blue =>
      "禁止：直接参与议题讨论、站队、给议题本身下结论。"
  }
}

///|
/// 帽子输出 schema 的关键字段（对齐 eval_feedback 的四段式契约；白帽/蓝帽允许部分字段为空）。
pub fn hat_output_keys(h : Hat) -> Array[String] {
  match h {
    White => ["evidence", "defects"] // 事实 + 未证实清单
    Red => ["feeling", "intuition"]
    Black => ["defects", "evidence"] // 反例/风险 + 依据
    Yellow => ["fix", "acceptance"] // 好处/机会 + 可接受条件
    Green => ["fix", "defects"] // 新方案 + 它想解决的反例
    Blue => ["acceptance", "evidence"] // 收敛结论 + 遗漏视角盘点
  }
}

// ---------------------------------------------------------------------------
// 帽子结论 + 多帽一致性聚合
// ---------------------------------------------------------------------------

///|
/// 单顶帽子的结论。verdict ∈ {pass, reject, abstain}；evidence 必填非空。
/// 字段全部 pub：跨包（`src/server` 的 debate_* 工具）需构造与读取。
pub struct HatVerdict {
  pub hat_id : String
  pub verdict : String // pass | reject | abstain
  pub evidence : String
}

///|
/// 多帽一致性聚合结果（确定性计算，不含 LLM 自评）。
/// rate = agree / total；pass = rate >= threshold。
pub struct DebateSummary {
  pub total : Int
  pub agree : Int // verdict == pass 的帽子数
  pub rate : Double
  pub threshold : Double
  pub pass : Bool // rate >= threshold，仅表示视角一致性，不代用户裁决
}

///|
/// 默认放行阈值（一致性门）。D3 语境下默认 0.6：三帽中至少两帽一致才视为收敛。
pub fn default_threshold() -> Double {
  0.6
}

///|
/// 聚合多帽结论：算 agree/rate/pass。threshold <= 0 时回退默认；total == 0 时 pass=false。
/// 只把 verdict == "pass" 计入 agree，abstain 与 reject 都不算达成一致。
pub fn debate_summary(verdicts : Array[HatVerdict], threshold : Double) -> DebateSummary {
  let th = if threshold > 0.0 && threshold <= 1.0 { threshold } else { default_threshold() }
  let total = verdicts.length()
  let mut agree = 0
  for i = 0; i < total; i = i + 1 {
    if verdicts[i].verdict == "pass" {
      agree = agree + 1
    }
  }
  let rate = if total == 0 {
    0.0
  } else {
    agree.to_double() / total.to_double()
  }
  { total: total, agree: agree, rate: rate, threshold: th, pass: rate >= th }
}

///|
/// 单帽结论的校验：evidence 非空才有效；verdict 只接受 pass/reject/abstain。
/// 返回 Err 说明该结论不可入聚合。
pub fn valid_verdict(v : HatVerdict) -> Result[Unit, String] {
  if v.evidence.trim().is_empty() {
    return Err("hat_id=" + v.hat_id + " evidence 不能为空")
  }
  match v.verdict {
    "pass" => Ok(())
    "reject" => Ok(())
    "abstain" => Ok(())
    _ => Err("hat_id=" + v.hat_id + " 非法 verdict: " + v.verdict)
  }
}