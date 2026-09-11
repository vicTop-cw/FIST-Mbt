/// FIST-Mbt core: task model & state machine.
/// 迁移自 FIST(Python) 的状态机与分层递归理念（七条金条第 4 条：唯一指挥官）。

/// 任务七态状态机
pub enum TaskStatus {
  /// 待领取
  Pending
  /// 已领取
  Claimed
  /// 拆分中
  Splitting
  /// 执行中
  Executing
  /// 待验收
  Reviewing
  /// 已完成
  Completed
  /// 已归档
  Archived
} derive(Eq, Debug)

pub fn TaskStatus::to_string(self : TaskStatus) -> String {
  match self {
    Pending => "待领取"
    Claimed => "已领取"
    Splitting => "拆分中"
    Executing => "执行中"
    Reviewing => "待验收"
    Completed => "已完成"
    Archived => "已归档"
  }
}

pub fn TaskStatus::from_string(s : String) -> Option[TaskStatus] {
  match s {
    "待领取" => Some(Pending)
    "已领取" => Some(Claimed)
    "拆分中" => Some(Splitting)
    "执行中" => Some(Executing)
    "待验收" => Some(Reviewing)
    "已完成" => Some(Completed)
    "已归档" => Some(Archived)
    _ => None
  }
}

/// 排序权重（用于统计/展示）

/// 状态谓词（供跨包业务层判断，避免直接构造变体）
pub fn TaskStatus::can_split(self : TaskStatus) -> Bool {
  match self {
    Pending | Claimed | Splitting => true
    _ => false
  }
}

pub fn TaskStatus::can_execute(self : TaskStatus) -> Bool {
  match self {
    Claimed | Splitting | Executing => true
    _ => false
  }
}

pub fn TaskStatus::is_completed(self : TaskStatus) -> Bool { self == Completed }
pub fn TaskStatus::is_pending(self : TaskStatus) -> Bool { self == Pending }

pub fn TaskStatus::is_claimed(self : TaskStatus) -> Bool { self == Claimed }

pub fn TaskStatus::is_splitting(self : TaskStatus) -> Bool { self == Splitting }

pub fn TaskStatus::is_executing(self : TaskStatus) -> Bool { self == Executing }


pub fn TaskStatus::is_reviewing(self : TaskStatus) -> Bool { self == Reviewing }

pub fn TaskStatus::is_archived(self : TaskStatus) -> Bool { self == Archived }

pub fn TaskStatus::order(self : TaskStatus) -> Int {
  match self {
    Pending => 0
    Claimed => 1
    Splitting => 2
    Executing => 3
    Reviewing => 4
    Completed => 5
    Archived => 6
  }
}

/// FIST-Mbt 任务实体
pub struct Task {
  /// 形如 T0 / T0.1 / T0.1.2 的层级 id
  pub id : String
  pub parent_id : String?
  pub project_dir : String
  pub priority : String
  pub importance : String
  /// K 值：根=3，每拆一层减 1；K<=1 为原子任务
  pub depth : Int
  /// 拆分数量（默认 3）
  pub split_n : Int
  pub status : TaskStatus
  pub assignee : String?
  pub description : String
  pub deliverable : String
  pub created_at : String
  pub updated_at : String
  pub completed_by : String?
  pub cleanup_mode : String
} derive(Eq, Debug)

/// 便捷状态访问
pub fn Task::status_to_string(self : Task) -> String { self.status.to_string() }

pub fn Task::get_id(self : Task) -> String { self.id }

pub fn Task::get_parent(self : Task) -> String? { self.parent_id }

pub fn Task::get_status(self : Task) -> TaskStatus { self.status }

pub fn Task::get_depth(self : Task) -> Int { self.depth }

pub fn Task::get_description(self : Task) -> String { self.description }

pub fn Task::get_assignee(self : Task) -> String? { self.assignee }

pub fn Task::get_updated_at(self : Task) -> String { self.updated_at }

pub fn Task::is_leaf(self : Task) -> Bool { self.depth <= 1 }

/// 构造器（字段带默认值）
pub fn Task::new(
  id~ : String,
  project_dir~ : String,
  description~ : String = "",
  priority~ : String = "中",
  importance~ : String = "中",
  depth~ : Int = 3,
  split_n~ : Int = 3,
  parent_id~ : String = "",
  assignee~ : String = "",
  cleanup_mode~ : String = "deferred",
  created_at~ : String = "",
) -> Task {
  {
    id,
    parent_id: if parent_id == "" { None } else { Some(parent_id) },
    project_dir,
    priority,
    importance,
    depth,
    split_n,
    status: Pending,
    assignee: if assignee == "" { None } else { Some(assignee) },
    description,
    deliverable: "",
    created_at,
    updated_at: created_at,
    completed_by: None,
    cleanup_mode,
  }
}


/// 按存储行字段直接构建任务（供 store 层反序列化使用；status 为存储字符串，非法回退 Pending）
pub fn Task::from_db(
  id : String,
  parent_id : String?,
  project_dir : String,
  priority : String,
  importance : String,
  depth : Int,
  split_n : Int,
  status_s : String,
  assignee : String?,
  description : String,
  deliverable : String,
  created_at : String,
  updated_at : String,
  completed_by : String?,
  cleanup_mode : String,
) -> Task {
  let status = match TaskStatus::from_string(status_s) {
    Some(s) => s
    None => Pending
  }
  {
    id,
    parent_id,
    project_dir,
    priority,
    importance,
    depth,
    split_n,
    status,
    assignee,
    description,
    deliverable,
    created_at,
    updated_at,
    completed_by,
    cleanup_mode,
  }
}

/// —— 状态迁移 ——
/// 每个迁移都是纯函数（返回新 Task），状态机非法流转直接拒绝。
/// 返回 Err(msg) 表示非法迁移。

/// 待领取 -> 已领取（角色：any active agent）
pub fn Task::claim(self : Task, assignee~ : String) -> Result[Task, String] {
  match self.status {
    Pending =>
      if assignee == "" {
        Err("claim 需要 assignee")
      } else {
        Ok({
          ..self,
          status: Claimed,
          assignee: Some(assignee),
          updated_at: self.updated_at,
        })
      }
    _ =>
      Err(
        "非法迁移: claim 要求状态 [待领取]，当前是 [" +
        self.status.to_string() +
        "]",
      )
  }
}

/// 已领取 -> 拆分中（指挥官拆解）
pub fn Task::split(self : Task) -> Result[Task, String] {
  match self.status {
    Claimed =>
      if self.is_leaf() {
        Err("原子任务(K<=1)不可再拆分")
      } else {
        Ok({ ..self, status: Splitting, })
      }
    _ =>
      Err(
        "非法迁移: split 要求状态 [已领取]，当前是 [" +
        self.status.to_string() +
        "]",
      )
  }
}


/// 拆分中标记（AO 式拆解用，宽于 split：待领取/已领取/拆分中均可转入）
pub fn Task::mark_decomposing(self : Task) -> Result[Task, String] {
  match self.status {
    Pending | Claimed | Splitting => Ok({ ..self, status: Splitting, })
    _ => Err("非法拆解: 任务处于 [\{self.status.to_string()}]")
  }
}

/// 拆分中 -> 执行中（进入执行）
pub fn Task::execute(self : Task) -> Result[Task, String] {
  match self.status {
    Splitting | Claimed => Ok({ ..self, status: Executing, })
    _ =>
      Err(
        "非法迁移: execute 要求状态 [拆分中/已领取]，当前是 [" +
        self.status.to_string() +
        "]",
      )
  }
}

/// 执行中 -> 待验收
pub fn Task::submit(self : Task) -> Result[Task, String] {
  match self.status {
    Executing => Ok({ ..self, status: Reviewing, })
    _ =>
      Err(
        "非法迁移: submit 要求状态 [执行中]，当前是 [" +
        self.status.to_string() +
        "]",
      )
  }
}

/// 待验收 -> 已完成（人类主权：completed_by 必须 human / human_steward 或明确授权）
pub fn Task::complete(self : Task, completed_by~ : String) -> Result[Task, String] {
  match self.status {
    Reviewing =>
      if completed_by == "" {
        Err("complete 需要 completed_by 身份")
      } else {
        Ok({
          ..self,
          status: Completed,
          completed_by: Some(completed_by),
        })
      }
    _ =>
      Err(
        "非法迁移: complete 要求状态 [待验收]，当前是 [" +
        self.status.to_string() +
        "]",
      )
  }
}

/// 已完成 -> 已归档
pub fn Task::archive(self : Task) -> Result[Task, String] {
  match self.status {
    Completed => Ok({ ..self, status: Archived, })
    _ =>
      Err(
        "非法迁移: archive 要求状态 [已完成]，当前是 [" +
        self.status.to_string() +
        "]",
      )
  }
}

/// 任意非归档状态 -> 已领取（被打回重做）
pub fn Task::reopen(self : Task) -> Result[Task, String] {
  match self.status {
    Archived => Err("已归档任务不可 reopen，请重新发布")
    _ => Ok({ ..self, status: Claimed, })
  }
}

/// 生成子任务 id：T0.1.2 -> T0.1.2.1

/// 记录类复制更新（跨包不便直接构造 record，由 core 提供）
pub fn Task::with_updated_at(self : Task, now : String) -> Task {
  { ..self, updated_at: now, }
}

pub fn Task::with_deliverable(self : Task, deliverable : String, now : String) -> Task {
  { ..self, deliverable, updated_at: now, }
}

pub fn child_id(parent_id~ : String, idx~ : Int) -> String {
  "\{parent_id}.\{idx}"
}

/// 任务转 JSON（供 MCP resource / tool 输出）
pub fn Task::to_json(self : Task) -> Json {
  let m : Map[String, Json] = Map([])
  m.set("id", Json::string(self.id))
  match self.parent_id {
    Some(p) => m.set("parent_id", Json::string(p))
    None => m.set("parent_id", Json::null())
  }
  m.set("project_dir", Json::string(self.project_dir))
  m.set("priority", Json::string(self.priority))
  m.set("importance", Json::string(self.importance))
  m.set("depth", Json::number(self.depth.to_double()))
  m.set("split_n", Json::number(self.split_n.to_double()))
  m.set("status", Json::string(self.status.to_string()))
  match self.assignee {
    Some(a) => m.set("assignee", Json::string(a))
    None => m.set("assignee", Json::null())
  }
  m.set("description", Json::string(self.description))
  m.set("deliverable", Json::string(self.deliverable))
  m.set("created_at", Json::string(self.created_at))
  m.set("updated_at", Json::string(self.updated_at))
  match self.completed_by {
    Some(c) => m.set("completed_by", Json::string(c))
    None => m.set("completed_by", Json::null())
  }
  m.set("cleanup_mode", Json::string(self.cleanup_mode))
  m.set("is_leaf", Json::boolean(self.is_leaf()))
  Json::object(m)
}
