///|
/// display/rank.mbt —— 军衔体系展示层。
///
/// 真源：docs/2026-10-12-fist-mbt-web-dashboard-plan.md §8.1「军衔体系（完整 *长 总表）」。
///
/// 设计原则（引自 docs）：
///   协议层不感知军衔。除统帅/士兵/政委外，所有 *长 在协议层一律映射为 `Leader` 角色；
///   军衔（司令/军长/师长/…/排长）只是**展示层标签**，由 `rank_of(任务层级)` 动态定级，
///   协议与存储零改动，仅 Web 面板与汇报文案消费。
///
/// 定级规则（引自 docs）：
///   - `rank_of(L)` = 总表自上而下第 `L+1` 档（统帅除外），即：L=0 → 司令，L=1 → 军长，…，L=7 → 排长。
///   - **叶子恒为士兵**：`depth == 叶子` 的任务无论层级一律 `Executor` 士兵级。
///   - 当前默认 `root depth=3`，实际生效 4 档（司令→军长→师长→士兵）；其余职级（旅长及以下）**占位**，
///     调大 `root depth` 后自动激活，无需改协议。
///
/// 纯函数零依赖（仅 core），双后端通用；本模块是纯展示层，协议/存储零改动。

///|
/// 军官档位数（Leader 线，不含统帅/士兵/政委）。
/// 总表自上而下：司令(L=0)、军长(L=1)、师长(L=2)、旅长(L=3)、
/// 团长(L=4)、营长(L=5)、连长(L=6)、排长(L=7)。
const OFFICER_LEVELS : Int = 8

///|
/// 统帅军衔标签（`HumanSteward`，人类唯一主权，不下放协议层）。
const MARSHAL_RANK : String = "统帅"

///|
/// 士兵军衔标签（`Executor`，叶子原子任务固定为士兵，绝不显示军衔）。
const SOLDIER_RANK : String = "士兵"

///|
/// 政委军衔标签（`Reminder`，政工线；方向纠偏/提醒/偏离检测，呼应提醒者角色 R1-R4）。
const COMMISSAR_RANK : String = "政委"

///|
/// 军官档位数（Leader 线，不含统帅/士兵/政委）。
/// pub getter：Web 面板 / 汇报文案读取档位数。
pub fn officer_levels() -> Int {
  OFFICER_LEVELS
}

///|
/// 统帅军衔标签（pub getter）。
pub fn marshal_rank() -> String {
  MARSHAL_RANK
}

///|
/// 士兵军衔标签（pub getter）。
pub fn soldier_rank() -> String {
  SOLDIER_RANK
}

///|
/// 政委军衔标签（pub getter）。
pub fn commissar_rank() -> String {
  COMMISSAR_RANK
}

///|
/// 军官档位军衔表（pub getter，返回副本）。
pub fn officer_table() -> Array[String] {
  [
    "司令", "军长", "师长", "旅长", "团长", "营长", "连长", "排长",
  ]
}

///|
/// rank_of：由任务层级 L 得展示军衔（展示层标签，非协议枚举）。
/// L=0 → 司令，L=1 → 军长，…，L=7 → 排长。
/// 越界（L<0 或 L>=OFFICER_LEVELS）回退到士兵（防越界）。
pub fn rank_of(level : Int) -> String {
  if level < 0 || level >= OFFICER_LEVELS {
    return SOLDIER_RANK
  }
  officer_table()[level]
}

///|
/// role_label：按协议角色得军衔标签（展示层映射）。
/// `HumanSteward` → 统帅；`Reminder` → 政委；`Executor` → 士兵；
/// `Leader` → 按层级 `rank_of(L)`；其他未知角色 → 士兵（防未登记角色泄漏军衔）。
pub fn role_label(role : String, level : Int) -> String {
  match role {
    "HumanSteward" => MARSHAL_RANK
    "Reminder" => COMMISSAR_RANK
    "Executor" => SOLDIER_RANK
    "Leader" => rank_of(level)
    _ => SOLDIER_RANK
  }
}

///|
/// leaf_label：叶子原子任务固定为士兵（无论层级）。
/// 任何 `depth == 叶子` 的任务无论层级一律 `Executor` 士兵级。
pub fn leaf_label(_level : Int) -> String {
  SOLDIER_RANK
}

///|
/// is_officer：该层级是否落在军官档内（L=0..OFFICER_LEVELS-1）。
/// 士兵/越界/叶子均非军官。
pub fn is_officer(level : Int) -> Bool {
  level >= 0 && level < OFFICER_LEVELS
}
