/// laya_route.mbt —— 决策分支模块（用户打磨方向：功能太多时给"该用哪些功能"的确定性决策）
///
/// 背景：fist-mbt 功能众多（104 工具、多机制家族），任务复杂/多项、不知该用哪些功能时，
/// 需要一个决策层：**有 Laya（Python ML 决策 sidecar）→ 让 Laya 决定；无 Laya → 本模块**
/// **自包含的规则式分支**（确定性、可复现、不依赖外部运行时）。
///
/// 本文件是本模块的**规则式回退**部分（纯计算、不碰文件/网络/外部进程），供：
///   - `laya_decide` 工具在探测不到 Laya 时调用，产出结构化决策（source=fallback）；
///   - 任何调用方直接复用（纯函数，无依赖）。
///
/// 决策内容两件套：
///   1) feature_route —— 从内建"机制族"里选出与任务描述最匹配的一个（按关键词重叠打分）；
///   2) split_n     —— 根据任务复杂度启发式给出建议拆分数（供 task_plan_deep 的深度参考）。

///|
/// 内建"机制族"（fist-mbt 功能全景的粗粒度分组），每族带一组识别关键词。
/// 用于"该用哪些功能/机制"的决策；关键词支持中英文、按子串匹配（不依赖正则）。
fn route_families() -> Array[(String, Array[String])] {
  let f : Array[(String, Array[String])] = [
    (
      "拆解调度",
      [
        "递归", "拆解", "分解", "任务", "子任务", "层次", "plan", "split",
        "层面", "拆分",
      ],
    ),
    (
      "深度验证",
      [
        "验证", "验收", "质量", "强验证", "spec", "contract", "测试",
        "verify", "审核", "契约",
      ],
    ),
    (
      "预算成本",
      [
        "预算", "成本", "资源", "效率", "cost", "budget", "开销", "省钱",
        "省时",
      ],
    ),
    (
      "可靠性容错",
      [
        "熔断", "补偿", "回滚", "可靠性", "容错", "看门狗", "watchdog",
        "心跳", "隔离", "故障",
      ],
    ),
    (
      "排程路由",
      [
        "排程", "依赖", "调度", "dag", "关键路径", "路由", "派单",
        "拓扑", "并行", "瓶颈", "schedule",
      ],
    ),
    (
      "目标校验",
      [
        "目标", "漂移", "规划", "修订", "计划", "goal", "drift", "偏差",
        "对齐", "plan_revise",
      ],
    ),
    (
      "代码质量扫描",
      [
        "扫描", "缺陷", "问题", "审计", "潜在", "静态", "issue", "scan",
        "review", "审查", "代码",
      ],
    ),
    (
      "自进化强化",
      [
        "进化", "学习", "课程", "蒸馏", "原则", "教训", "evolve", "lesson",
        "自进化", "成长",
      ],
    ),
  ]
  f
}

///|
/// 一族的命中分：出现的关键词越多分越高；CJK/长关键词加权（更能体现语义指向）。
fn route_score(desc : String, keywords : Array[String]) -> Int {
  let mut s = 0
  for k in keywords {
    if desc.contains(k) {
      s = s + (if k.length() >= 2 { 2 } else { 1 })
    }
  }
  s
}

///|
/// 复杂度启发式：长文本或出现复杂/多任务等信号词 → 建议更多子树深度/拆分数。
fn route_complex(description : String) -> Bool {
  if description.length() > 120 {
    return true
  }
  let signals = [
    "复杂", "多任务", "多项", "集成", "重构", "并行", "跨模块", "复杂任务",
    "large", "multi", "complex", "integrate", "refactor",
  ]
  for s in signals {
    if description.contains(s) {
      return true
    }
  }
  false
}

///|
/// 规则式决策主函数（纯计算，无外部依赖）：
/// 输入任务描述 + 拆分提示，输出 { feature_route, splits_per_family, split_n, complex, reasons }。
/// source 固定为 "fallback"（本模块即无 Laya 时的确定性分支）。
pub fn route_decision(description : String, split_n_hint : Int) -> Json {
  let families = route_families()
  // 逐族打分（避免 map 元组解构闭包，用显式循环）
  let scores : Array[(String, Int)] = []
  for f in families {
    let (name, ks) = f
    scores.push((name, route_score(description, ks)))
  }
  // 选命中分最高的族（并列取首个，稳定）
  let mut best_name = ""
  let mut best_score = -1
  let by_family : Array[Json] = []
  for pair in scores {
    let (name, sc) = pair
    by_family.push(
      Json::object({
        "family": Json::string(name),
        "score": Json::number(sc.to_double()),
      }),
    )
    if sc > best_score {
      best_score = sc
      best_name = name
    }
  }
  // 无任何命中 → 兜底取首个族
  if best_score < 0 {
    let (f0, _) = families[0]
    best_name = f0
    best_score = 0
  }
  let complex = route_complex(description)
  let base = if split_n_hint > 0 { split_n_hint } else { 3 }
  let raw = if complex { base + 1 } else { base }
  let split_n = if raw < 2 { 2 } else if raw > 6 { 6 } else { raw }
  let reasons : Array[String] = []
  reasons.push(
    "无 Laya 可用，采用规则式决策（词法子串打分，确定性可复现）",
  )
  reasons.push("feature_route 命中族 - " + best_name)
  if complex {
    reasons.push("任务复杂度高 → 建议拆分数 +1")
  }
  Json::object({
    "source": Json::string("fallback"),
    "complex": Json::boolean(complex),
    "feature_route": Json::string(best_name),
    "split_n": Json::number(split_n.to_double()),
    "splits_per_family": Json::array(by_family),
    "reasons": Json::array(reasons.map(fn(r) { Json::string(r) })),
  })
}
