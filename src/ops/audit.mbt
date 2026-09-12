/// audit.mbt —— 权限与审计模块（M5 治理：人类主权 + 追加式审计日志）
///
/// 设计要点：
///   - AuditLog 为进程内追加式日志（append-only），不落库；
///   - 时间戳由调用方传入 now（测试确定性、无隐式系统时间依赖）；
///   - 角色权限矩阵遵循"唯一指挥官/人类主权"原则：publish/archive/delete 仅 HumanSteward，
///     claim 面向 Leader / Agent / HumanSteward 全部放开。

/// 审计单条记录
pub struct AuditEntry {
  pub ts : String
  pub action : String
  pub actor : String
  pub task_id : String
  pub detail : String
} derive(Eq, Debug)

/// 进程内追加式审计日志
pub struct AuditLog {
  entries : Array[AuditEntry]
}

pub fn AuditLog::new() -> AuditLog {
  { entries: [] }
}

/// 追加一条审计记录
pub fn AuditLog::record(
  self : AuditLog,
  action~ : String,
  actor~ : String,
  task_id~ : String,
  detail~ : String = "",
  now~ : String,
) -> Unit {
  self.entries.push({ ts: now, action, actor, task_id, detail })
}

/// 全量条目（追加序）
pub fn AuditLog::entries(self : AuditLog) -> Array[AuditEntry] {
  self.entries
}

/// 按操作者过滤
pub fn AuditLog::by_actor(self : AuditLog, actor : String) -> Array[AuditEntry] {
  let out : Array[AuditEntry] = []
  for e in self.entries {
    if e.actor == actor {
      out.push(e)
    }
  }
  out
}

/// 按任务 id 过滤
pub fn AuditLog::by_task(self : AuditLog, task_id : String) -> Array[AuditEntry] {
  let out : Array[AuditEntry] = []
  for e in self.entries {
    if e.task_id == task_id {
      out.push(e)
    }
  }
  out
}

/// 序列化为 JSON 数组（供 MCP resource 输出）
pub fn AuditLog::to_json(self : AuditLog) -> Json {
  let arr : Array[Json] = []
  for e in self.entries {
    let m : Map[String, Json] = Map([])
    m.set("ts", Json::string(e.ts))
    m.set("action", Json::string(e.action))
    m.set("actor", Json::string(e.actor))
    m.set("task_id", Json::string(e.task_id))
    m.set("detail", Json::string(e.detail))
    arr.push(Json::object(m))
  }
  Json::array(arr)
}

/// —— 角色与权限矩阵 ——

pub enum Role {
  HumanSteward
  Leader
  Agent
} derive(Eq, Debug)

/// 人类可读角色名
pub fn Role::to_string(self : Role) -> String {
  match self {
    HumanSteward => "human_steward"
    Leader => "leader"
    Agent => "agent"
  }
}

/// 从字符串构造 Role（解析失败返回 None）
pub fn Role::from_string(s : String) -> Role? {
  match s {
    "human_steward" => Some(HumanSteward)
    "leader" => Some(Leader)
    "agent" => Some(Agent)
    _ => None
  }
}

/// 发布任务：仅 HumanSteward
pub fn can_publish(role : Role) -> Bool {
  match role {
    HumanSteward => true
    _ => false
  }
}

/// 归档任务：仅 HumanSteward
pub fn can_archive(role : Role) -> Bool {
  match role {
    HumanSteward => true
    _ => false
  }
}

/// 删除任务：仅 HumanSteward
pub fn can_delete(role : Role) -> Bool {
  match role {
    HumanSteward => true
    _ => false
  }
}

/// 认领任务：Leader / Agent / HumanSteward 均可
pub fn can_claim(role : Role) -> Bool {
  match role {
    HumanSteward | Leader | Agent => true
  }
}

/// 权限执行：不满足返回 Err（描述缺权操作），满足返回 Ok(())
pub fn enforce(
  action~ : String,
  role~ : Role,
) -> Result[Unit, String] {
  let ok = match action {
    "publish" => can_publish(role)
    "archive" => can_archive(role)
    "delete" => can_delete(role)
    "claim" => can_claim(role)
    _ => false
  }
  if ok {
    Ok(())
  } else {
    Err(
      "权限拒绝: 角色 [\{role.to_string()}] 不可执行 [\{action}]（该操作需 human_steward）",
    )
  }
}
