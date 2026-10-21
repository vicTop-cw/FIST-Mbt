///|
/// evolve/curriculum.mbt —— 课程式自进化（L41 核心组件）
///
/// 无人值守自进化闭环的三个支柱：
///   1. curriculum：按评分档位组织"由易到难"的学习路径（课程）
///   2. mutation：对已有 artifact 生成文本变体（变异算子）
///   3. skill_lib：技能库——把高分 artifact 的 note 蒸馏为可复用 skill
///
/// 评分驱动：scoring.mbt 的 score_rank 输出 L1~L4，curriculum 据此决定
/// 下一轮该从哪个档位采样父代、生成什么难度的子代。

///|
/// 课程阶段：从 L1（入门）到 L4（精通），由易到难
pub enum CurriculumLevel {
  L1 // 入门：基础正确性
  L2 // 进阶：覆盖度
  L3 // 熟练：结构完整性
  L4 // 精通：高正确率 + 稳健性
} derive(Eq, Debug)

///|
pub extend CurriculumLevel with Eq::{not_equal, equal}

///|
pub extend CurriculumLevel with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// 课程条目：一个阶段 + 该阶段的学习目标
pub struct CurriculumItem {
  level : CurriculumLevel
  goal : String
  min_score : Double // 进入下一阶段的最低分
}

///|
/// 生成标准四阶段课程
pub fn standard_curriculum() -> Array[CurriculumItem] {
  [
    {
      level: L1,
      goal: "实现基础功能，保证核心路径正确",
      min_score: 0.55,
    },
    {
      level: L2,
      goal: "提升测试覆盖度，处理边界条件",
      min_score: 0.70,
    },
    {
      level: L3,
      goal: "完善结构（fingerprint/schema），保证可验证性",
      min_score: 0.85,
    },
    {
      level: L4,
      goal: "追求高正确率与稳健性，可蒸馏为 skill",
      min_score: 0.95,
    },
  ]
}

///|
/// 根据当前评分决定下一步该在哪个阶段学习
pub fn next_level(current_score : Double) -> CurriculumLevel {
  if current_score < 0.55 {
    L1
  } else if current_score < 0.70 {
    L2
  } else if current_score < 0.85 {
    L3
  } else {
    L4
  }
}

///|
/// 给定当前评分，返回建议的下一阶段目标描述
pub fn suggest_next_goal(current_score : Double) -> String {
  match next_level(current_score) {
    L1 =>
      "当前评分偏低，先保证基础功能正确性（覆盖率与正确率）"
    L2 => "已有基础，重点提升测试覆盖度与边界处理"
    L3 =>
      "覆盖度达标，完善结构完整性（fingerprint/schema）以进入可验证状态"
    L4 =>
      "已达精通档，重点追求稳健性并可蒸馏为可复用 skill"
  }
}

///|
/// 判断是否可以从当前阶段"毕业"进入下一阶段
pub fn can_graduate(
  current_score : Double,
  current_level : CurriculumLevel,
) -> Bool {
  match current_level {
    L1 => current_score >= 0.55
    L2 => current_score >= 0.70
    L3 => current_score >= 0.85
    L4 => current_score >= 0.95 // L4 已是最高，"毕业"意味着可蒸馏
  }
}

///|
/// 课程进度：已达阶段 / 总阶段数（0.0 ~ 1.0）
pub fn curriculum_progress(current_score : Double) -> Double {
  let level = next_level(current_score)
  match level {
    L1 => 0.0
    L2 => 0.33
    L3 => 0.66
    L4 => 1.0
  }
}

///|
/// 变异算子类型
pub enum MutationKind {
  Rewrite // 重写（保留意图，换实现）
  Simplify // 简化（移除冗余）
  Generalize // 泛化（参数化硬编码值）
  Specialize // 特化（针对特定场景优化）
  Combine // 组合（融合两个父代的特征）
} derive(Eq, Debug)

///|
pub extend MutationKind with Eq::{not_equal, equal}

///|
pub extend MutationKind with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// 对 artifact 的 note/goal 生成变异提示词（供外部执行器使用）
/// 注意：这里只生成"变异指令"，真正的代码变异由外部执行器完成
pub fn mutation_prompt(
  kind : MutationKind,
  goal : String,
  note : String,
) -> String {
  let base = "对以下产物执行变异，目标：" +
    goal +
    "。原设计意图：" +
    note +
    "。\n"
  match kind {
    Rewrite =>
      base +
      "【重写】保留功能语义，用不同的实现方式重写代码，保持接口不变。"
    Simplify =>
      base +
      "【简化】识别并移除冗余代码、重复逻辑、不必要的抽象，保持行为等价。"
    Generalize =>
      base +
      "【泛化】把硬编码的值/逻辑参数化，提取可复用的抽象，扩大适用范围。"
    Specialize =>
      base +
      "【特化】针对特定高频场景做专门优化，牺牲通用性换取性能/简洁。"
    Combine =>
      base +
      "【组合】融合多个父代的优点，取长补短，产出一个更优的综合版本。"
  }
}

///|
/// 选择变异算子：根据当前评分档位选择合适的变异策略
///   - 低分（L1/L2）：偏向 Simplify / Rewrite（先搞对、搞简）
///   - 中分（L3）：偏向 Generalize / Rewrite（完善结构）
///   - 高分（L4）：偏向 Specialize / Combine（追求极致）
pub fn select_mutation(score : Double) -> MutationKind {
  let r = score.clamp(min=0.0, max=1.0)
  if r < 0.55 {
    Simplify
  } else if r < 0.70 {
    Rewrite
  } else if r < 0.85 {
    Generalize
  } else {
    Specialize
  }
}

///|
/// 技能库条目：从高分 artifact 蒸馏出的可复用技能
pub struct SkillEntry {
  name : String
  description : String
  source_artifact_id : String
  score : Double
  tags : Array[String]
}

///|
/// 判断 artifact 是否值得蒸馏为 skill（评分 ≥ 0.85 且非空 note）
pub fn is_distillable(score : Double, note : String) -> Bool {
  score >= 0.85 && note.trim() != ""
}

///|
/// 从 artifact 的 goal + note 生成 skill 名称
pub fn derive_skill_name(goal : String, note : String) -> String {
  // 取 note 的前 8 个字符作为 skill 名前缀
  let prefix = if note.length() > 8 { note[0:8].to_owned() } else { note }
  let cleaned = prefix.trim().replace(old=" ", new="_").to_owned()
  "skill_" + cleaned
}

///|
/// 从 artifact 蒸馏出 skill 条目
pub fn distill_skill(
  artifact_id : String,
  goal : String,
  note : String,
  score : Double,
) -> SkillEntry? {
  if !is_distillable(score, note) {
    return None
  }
  let name = derive_skill_name(goal, note)
  let desc = goal + " | " + note
  Some({
    name,
    description: desc,
    source_artifact_id: artifact_id,
    score,
    tags: [],
  })
}

///|
/// 给 skill 打标签（从 description 关键词提取）
pub fn tag_skill(skill : SkillEntry, keywords : Array[String]) -> SkillEntry {
  let tags : Array[String] = []
  let desc_lower = skill.description.to_lower()
  for kw in keywords {
    if desc_lower.contains(kw.to_lower()) {
      tags.push(kw)
    }
  }
  {
    name: skill.name,
    description: skill.description,
    source_artifact_id: skill.source_artifact_id,
    score: skill.score,
    tags,
  }
}

///|
/// 课程 + 变异 + 蒸馏的一体化决策：给定当前评分，返回
/// (建议阶段, 建议变异算子, 是否可蒸馏)
pub fn evolve_decision(
  current_score : Double,
) -> (CurriculumLevel, MutationKind, Bool) {
  let level = next_level(current_score)
  let mutation = select_mutation(current_score)
  let distillable = current_score >= 0.85
  (level, mutation, distillable)
}

///|
/// 把 evolve_decision 转可读字符串
pub fn decision_to_string(
  level : CurriculumLevel,
  mutation : MutationKind,
  distillable : Bool,
) -> String {
  let level_str = match level {
    L1 => "L1(入门)"
    L2 => "L2(进阶)"
    L3 => "L3(熟练)"
    L4 => "L4(精通)"
  }
  let mut_str = match mutation {
    Rewrite => "重写"
    Simplify => "简化"
    Generalize => "泛化"
    Specialize => "特化"
    Combine => "组合"
  }
  let distill_str = if distillable { "可蒸馏" } else { "暂不蒸馏" }
  "阶段=" + level_str + ", 变异=" + mut_str + ", " + distill_str
}
