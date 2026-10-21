///|
/// display/staff.mbt —— 参谋线展示层（§8.1 参谋线：非 *长，参谋军职，挂靠 Leader 体系）。
///
/// 真源：docs/2026-10-12-fist-mbt-web-dashboard-plan.md §8.1「参谋线」表。
///
/// 设计原则：参谋军职**不是协议角色**，只是展示层标签，挂靠 Leader 体系。
/// 协议层仍只有 HumanSteward/Leader/Executor/Reminder（远期）；参谋军职用于
/// 面板展示、汇报文案、审计归因，协议与存储零改动。

///|
/// 参谋军职名数组（6 军职，顺序与 docs §8.1 表一致）。
pub fn staff_titles() -> Array[String] {
  [
    "侦察参谋", "后勤参谋", "验收宪兵", "军务文书", "监察参谋",
    "训练教官",
  ]
}

///|
/// 参谋军职数（6）。
pub fn staff_title_count() -> Int32 {
  6
}

///|
/// 参谋角色映射（展示层）：把协议角色名映射到参谋军职。
/// 按 docs §8.1 参谋线表的关键词匹配，未知回退「军务文书」（记录、台账、日志归档，最通用）。
/// 参数：role(协议角色名或自由文本关键词)。
pub fn staff_label(role : String) -> String {
  let r = role.to_lower()
  if r.is_empty() {
    return "军务文书"
  }
  let table = [
    (
      "侦察参谋",
      ["searcher", "侦察", "情报", "搜索", "调研", "research", "scout"],
    ),
    (
      "后勤参谋",
      ["allocator", "后勤", "资源", "分配", "调度", "alloc", "pool"],
    ),
    (
      "验收宪兵",
      ["verifier", "验收", "宪兵", "门禁", "审核", "verify", "gate"],
    ),
    (
      "监察参谋",
      ["observer", "监察", "异常", "上报", "监控", "observe", "alert"],
    ),
    (
      "训练教官",
      ["specauthor", "教官", "训练", "规范", "提示词", "train", "spec"],
    ),
    (
      "军务文书",
      ["recorder", "文书", "记录", "台账", "日志", "归档", "log"],
    ),
  ]
  for i = 0; i < table.length(); i = i + 1 {
    let (_, tags) = table[i]
    for j = 0; j < tags.length(); j = j + 1 {
      if r.contains(tags[j]) {
        return table[i].0
      }
    }
  }
  "军务文书"
}

///|
/// 参谋军职职责说明（展示层，供面板/汇报文案）。
pub fn staff_duty(title : String) -> String {
  match title {
    "侦察参谋" => "情报搜集、可行性调研"
    "后勤参谋" => "资源分配、池/模型调度"
    "验收宪兵" => "交付验收、门禁把关"
    "军务文书" => "记录、台账、日志归档"
    "监察参谋" => "状态监察、异常上报"
    "训练教官" => "规范/提示词编写、训练"
    _ => "未知参谋军职"
  }
}

///|
/// 参谋军职挂靠体系说明（展示层）。
pub fn staff_hierarchy(title : String) -> String {
  match title {
    "侦察参谋" => "Leader 体系 / Searcher 职能"
    "后勤参谋" => "Leader 体系 / Allocator 职能"
    "验收宪兵" => "Leader 体系 / Verifier 职能"
    "军务文书" => "Leader 体系 / Recorder 职能"
    "监察参谋" => "Leader 体系 / Observer 职能"
    "训练教官" => "Leader 体系 / SpecAuthor 职能"
    _ => "未知挂靠体系"
  }
}
