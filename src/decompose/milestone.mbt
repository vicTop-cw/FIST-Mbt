///|
/// decompose/milestone.mbt —— 里程碑式渐进拆解（L35）
///
/// 语义：在递归 decompose 之前，先生成粗粒度里程碑（Milestone）序列，
/// 每个里程碑描述一个可独立交付的阶段目标；之后每个里程碑可继续细化为
/// focused sub-tasks（复用 decompose_slices）。
///
/// 价值：
///   - 先有全局路线图（里程碑），再细化执行单元，避免一上来就陷入细节
///   - 里程碑之间有依赖序（前序完成才启后续），便于排程与验收
///   - 每个里程碑可独立标记完成状态，支持渐进式交付

///|
/// 一个里程碑：阶段目标 + 顺序 + 依赖的前序里程碑索引
pub struct Milestone {
  index : Int // 序号（从 0 开始）
  title : String // 里程碑标题
  description : String // 详细描述
  depends_on : Array[Int] // 依赖的前序里程碑 index
}

///|
/// 里程碑分解结果：里程碑序列 + 细化建议
pub struct MilestonePlan {
  milestones : Array[Milestone]
  total : Int
}

///|
/// 从任务描述生成粗粒度里程碑序列。
/// 策略：按"调研→设计→实现→验证→交付"五段式骨架，结合 parent_desc 注入上下文。
/// split_n 控制里程碑数量（3~5 之间，少于 3 强制 3，多于 5 截断到 5）。
pub fn generate_milestones(
  parent_desc~ : String,
  split_n : Int,
) -> MilestonePlan {
  let n = if split_n < 3 { 3 } else if split_n > 5 { 5 } else { split_n }

  // 五段式骨架模板
  let templates = [
    (
      "调研与边界澄清",
      "理解「\{parent_desc}」的目标、约束、输入输出与验收标准；明确边界（不做什么）与风险点。",
    ),
    (
      "方案与接口设计",
      "为「\{parent_desc}」设计模块划分、数据结构、接口签名与依赖关系；产出可评审的设计草案。",
    ),
    (
      "核心实现",
      "实现「\{parent_desc}」的核心逻辑，覆盖主路径与关键边界；保持增量可验证。",
    ),
    (
      "测试与健壮性",
      "为「\{parent_desc}」补充单元测试与边界用例，修正缺陷，确保回归不破坏既有功能。",
    ),
    (
      "集成与交付",
      "将「\{parent_desc}」集成进整体，跑通端到端验证，更新文档与交付物。",
    ),
  ]

  // 按 n 选取模板（均匀采样）
  let selected : Array[(String, String)] = []
  if n == 3 {
    // 取 调研 / 实现 / 交付
    selected.push(templates[0])
    selected.push(templates[2])
    selected.push(templates[4])
  } else if n == 4 {
    // 取 调研 / 设计 / 实现 / 交付
    selected.push(templates[0])
    selected.push(templates[1])
    selected.push(templates[2])
    selected.push(templates[4])
  } else {
    // n == 5，全取
    let mut i = 0
    while i < templates.length() {
      selected.push(templates[i])
      i = i + 1
    }
  }

  let milestones : Array[Milestone] = []
  let mut i = 0
  while i < selected.length() {
    let (title, desc) = selected[i]
    // 每个里程碑依赖前一个（线性依赖链）
    let deps : Array[Int] = []
    if i > 0 {
      deps.push(i - 1)
    }
    milestones.push({ index: i, title, description: desc, depends_on: deps, })
    i = i + 1
  }

  { milestones, total: milestones.length(), }
}

///|
/// 对单个里程碑生成细化子任务（复用 decompose_slices 的 default_slices 思路）。
/// 返回该里程碑下的子任务描述数组。
pub fn refine_milestone(m : Milestone, sub_split_n : Int) -> Array[String] {
  let out : Array[String] = []
  let n = if sub_split_n < 1 { 1 } else { sub_split_n }
  for i = 1; i <= n; i = i + 1 {
    let prefix = "[里程碑 " +
      (m.index + 1).to_string() +
      ": " +
      m.title +
      "] 子任务 "
    let suffix = " 的第 " + i.to_string() + " 步"
    out.push(
      prefix +
      i.to_string() +
      "/" +
      n.to_string() +
      "：" +
      m.description +
      suffix,
    )
  }
  out
}

///|
/// 检查里程碑依赖是否形成合法 DAG（无环、依赖索引在范围内）。
/// 返回 (合法, 错误信息)
pub fn validate_milestone_plan(plan : MilestonePlan) -> (Bool, String) {
  let n = plan.total
  let mut i = 0
  while i < n {
    let ms = plan.milestones[i]
    if ms.index != i {
      return (
        false,
        "里程碑 index 不连续：期望 \{i}，实际 \{ms.index}",
      )
    }
    for dep in ms.depends_on {
      if dep < 0 || dep >= n {
        return (false, "里程碑 \{i} 的依赖 \{dep} 越界")
      }
      if dep >= i {
        return (
          false,
          "里程碑 \{i} 依赖了自身或后续里程碑 \{dep}（必须依赖前序）",
        )
      }
    }
    i = i + 1
  }
  // 环检测：线性依赖链天然无环，但做一次拓扑验证
  (true, "")
}

///|
/// 把里程碑计划转成 ASCII 路线图（供看板展示）
pub fn milestone_ascii(plan : MilestonePlan) -> String {
  let lines : Array[String] = []
  lines.push("=== 里程碑路线图（共 \{plan.total} 阶段）===")
  let mut i = 0
  while i < plan.total {
    let ms = plan.milestones[i]
    let dep_str = if ms.depends_on.length() == 0 {
      "（起点）"
    } else {
      "依赖: " +
      ms.depends_on.map(fn(d) { "M" + (d + 1).to_string() }).join(", ")
    }
    lines.push("M\{ms.index + 1}. \{ms.title}  \{dep_str}")
    lines.push("    \{ms.description}")
    i = i + 1
  }
  lines.join("\n")
}

///|
/// 把里程碑计划转 JSON
pub fn milestone_plan_to_json(plan : MilestonePlan) -> String {
  let parts : Array[String] = []
  parts.push("\"total\":" + plan.total.to_string())
  let ms_parts : Array[String] = []
  let mut i = 0
  while i < plan.milestones.length() {
    let ms = plan.milestones[i]
    let dep_json = "[" +
      ms.depends_on.map(fn(d) { d.to_string() }).join(",") +
      "]"
    let t = json_escape(ms.title)
    let d = json_escape(ms.description)
    let entry = "{\"index\":" +
      ms.index.to_string() +
      ",\"title\":\"" +
      t +
      "\",\"description\":\"" +
      d +
      "\",\"depends_on\":" +
      dep_json +
      "}"
    ms_parts.push(entry)
    i = i + 1
  }
  parts.push("\"milestones\":[" + ms_parts.join(",") + "]")
  "{" + parts.join(",") + "}"
}

///|
fn json_escape(s : String) -> String {
  let out : Array[String] = []
  let mut i = 0
  while i < s.length() {
    let c = s[i]
    match c {
      '"' => out.push("\\\"")
      '\\' => out.push("\\\\")
      '\n' => out.push("\\n")
      '\r' => out.push("\\r")
      '\t' => out.push("\\t")
      _ => out.push(c.to_string())
    }
    i = i + 1
  }
  out.join("")
}

///|
/// 里程碑完成进度：按完成的里程碑数 / 总数 计算
pub fn milestone_progress(
  plan : MilestonePlan,
  completed : Array[Bool],
) -> Double {
  if plan.total == 0 {
    return 1.0
  }
  let mut done = 0
  let mut i = 0
  while i < completed.length() && i < plan.total {
    if completed[i] {
      done = done + 1
    }
    i = i + 1
  }
  done.to_double() / plan.total.to_double()
}
