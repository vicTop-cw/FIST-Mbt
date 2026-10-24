/// FIST-Mbt core: task model & state machine.
/// 迁移自 FIST(Python) 的状态机与分层递归理念（七条金条第 4 条：唯一指挥官）。

///|
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
  /// 已打回（验收不通过，需重做）
  Rejected
  /// 已暂停（外部中断/等待依赖）
  Paused
} derive(Eq, Debug)

///|
pub extend TaskStatus with Eq::{not_equal, equal}

///|
pub extend TaskStatus with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub fn TaskStatus::to_string(self : TaskStatus) -> String {
  match self {
    Pending => "待领取"
    Claimed => "已领取"
    Splitting => "拆分中"
    Executing => "执行中"
    Reviewing => "待验收"
    Completed => "已完成"
    Archived => "已归档"
    Rejected => "已打回"
    Paused => "已暂停"
  }
}

///|
pub fn TaskStatus::from_string(s : String) -> TaskStatus? {
  match s {
    "待领取" => Some(Pending)
    "已领取" => Some(Claimed)
    "拆分中" => Some(Splitting)
    "执行中" => Some(Executing)
    "待验收" => Some(Reviewing)
    "已完成" => Some(Completed)
    "已归档" => Some(Archived)
    "已打回" => Some(Rejected)
    "已暂停" => Some(Paused)
    _ => None
  }
}

/// 排序权重（用于统计/展示）

///|
/// 状态谓词（供跨包业务层判断，避免直接构造变体）
pub fn TaskStatus::can_split(self : TaskStatus) -> Bool {
  match self {
    Pending | Claimed | Splitting | Rejected => true
    _ => false
  }
}

///|
/// execute 的前态谓词（engine.execute 的第一道门）。
/// BUG-2 相邻加固（守卫一致性）：这里曾多出一条 `Rejected`，而 Task::execute 并不接受
/// 已打回——两条门不一致时，调用方拿到的是引擎的"非法执行: 任务处于 [已打回]"（无出路），
/// 而不是域迁移里带 retry 出路的文案。集合与 Task::execute 逐字对齐（对外结果不变：
/// 两条门对 Rejected 都是拒，只是文案统一）。
pub fn TaskStatus::can_execute(self : TaskStatus) -> Bool {
  match self {
    Claimed | Splitting | Executing => true
    _ => false
  }
}

///|
pub fn TaskStatus::is_rejected(self : TaskStatus) -> Bool {
  self == Rejected
}

///|
pub fn TaskStatus::is_paused(self : TaskStatus) -> Bool {
  self == Paused
}

///|
pub fn TaskStatus::is_active(self : TaskStatus) -> Bool {
  match self {
    Pending | Claimed | Splitting | Executing | Reviewing => true
    _ => false
  }
}

///|
pub fn TaskStatus::is_completed(self : TaskStatus) -> Bool {
  self == Completed
}

///|
pub fn TaskStatus::is_pending(self : TaskStatus) -> Bool {
  self == Pending
}

///|
pub fn TaskStatus::is_claimed(self : TaskStatus) -> Bool {
  self == Claimed
}

///|
pub fn TaskStatus::is_splitting(self : TaskStatus) -> Bool {
  self == Splitting
}

///|
pub fn TaskStatus::is_executing(self : TaskStatus) -> Bool {
  self == Executing
}

///|
pub fn TaskStatus::is_reviewing(self : TaskStatus) -> Bool {
  self == Reviewing
}

///|
pub fn TaskStatus::is_archived(self : TaskStatus) -> Bool {
  self == Archived
}

///|
pub fn TaskStatus::order(self : TaskStatus) -> Int32 {
  match self {
    Pending => 0
    Claimed => 1
    Splitting => 2
    Executing => 3
    Reviewing => 4
    Completed => 5
    Archived => 6
    Rejected => 7
    Paused => 8
  }
}

///|
/// FIST-Mbt 任务实体
pub struct Task {
  /// 形如 T0 / T0.1 / T0.1.2 的层级 id
  id : String
  parent_id : String?
  project_dir : String
  /// 命名空间（多租户隔离键，默认 "default"）
  ns : String
  priority : String
  importance : String
  /// K 值：根=3，每拆一层减 1；K<=1 为原子任务
  depth : Int32
  /// 拆分数量（默认 3）
  split_n : Int32
  /// 军衔等级（军衔体系展示层的真数据源）：0=司令 … 7=排长，越界钳制；
  /// 默认 6（连长）；子任务 = 父级 + 1，封顶 7。**与 depth（树深/缩进）严格分离**。
  level : Int32
  status : TaskStatus
  assignee : String?
  description : String
  deliverable : String
  created_at : String
  updated_at : String
  completed_by : String?
  cleanup_mode : String
  /// 依赖的任务 id 列表（这些任务完成后，本任务才可领取）
  depends_on : Array[String]
  /// BUG-389 方向②：Omega 门禁开关判据从 description 文本移到不可覆盖的元数据列。
  /// plan_deep(omega_strong_verify=true) 写子任务时置 true；supervisor_task_upsert
  /// 覆盖描述不会影响本字段。
  omega_required : Bool
} derive(Eq, Debug)

///|
pub extend Task with Eq::{not_equal, equal}

///|
pub extend Task with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// 便捷状态访问
pub fn Task::status_to_string(self : Task) -> String {
  self.status.to_string()
}

///|
pub fn Task::get_id(self : Task) -> String {
  self.id
}

///|
pub fn Task::get_parent(self : Task) -> String? {
  self.parent_id
}

///|
pub fn Task::get_status(self : Task) -> TaskStatus {
  self.status
}

///|
pub fn Task::get_depth(self : Task) -> Int32 {
  self.depth
}

///|
/// 军衔等级（0..7）。军衔体系展示层读取此处，而非 depth。
pub fn Task::get_level(self : Task) -> Int32 {
  self.level
}

///|
pub fn Task::get_description(self : Task) -> String {
  self.description
}

///|
/// BUG-389 方向②：Omega 门禁开关元数据（description 被覆盖后仍为真）
pub fn Task::get_omega_required(self : Task) -> Bool {
  self.omega_required
}

///|
pub fn Task::get_assignee(self : Task) -> String? {
  self.assignee
}

///|
pub fn Task::get_updated_at(self : Task) -> String {
  self.updated_at
}

///|
pub fn Task::is_leaf(self : Task) -> Bool {
  self.depth <= 1
}

///|
/// 军衔等级钳制到 0..7（<0→0，>7→7）。军衔体系展示层的真数据源，
/// 与 depth（树深）语义独立，绝不用 depth 兼任 level。
fn clamp_level(l : Int32) -> Int32 {
  if l < 0 {
    0
  } else if l > 7 {
    7
  } else {
    l
  }
}

///|
/// 子任务军衔 = 父级 + 1，封顶排长（7）。
/// 连长(6)→排长(7)→士兵；不再上升。父级越界先钳制再 +1（防御）。
pub fn child_level(parent : Int32) -> Int32 {
  let p = clamp_level(parent)
  if p + 1 > 7 {
    7
  } else {
    p + 1
  }
}

///|
/// 构造器（字段带默认值）
pub fn Task::new(
  id~ : String,
  project_dir~ : String,
  description~ : String = "",
  priority~ : String = "中",
  importance~ : String = "中",
  depth~ : Int32 = 3,
  split_n~ : Int32 = 3,
  level~ : Int32 = 6,
  parent_id~ : String = "",
  assignee~ : String = "",
  cleanup_mode~ : String = "deferred",
  created_at~ : String = "",
  ns~ : String = "default",
  depends_on~ : Array[String] = [],
  omega_required~ : Bool = false,
) -> Task {
  {
    id,
    parent_id: if parent_id == "" {
      None
    } else {
      Some(parent_id)
    },
    project_dir,
    ns,
    priority,
    importance,
    depth,
    split_n,
    level: clamp_level(level),
    status: Pending,
    assignee: if assignee == "" {
      None
    } else {
      Some(assignee)
    },
    description,
    deliverable: "",
    created_at,
    updated_at: created_at,
    completed_by: None,
    cleanup_mode,
    depends_on,
    omega_required,
  }
}

///|
/// 按存储行字段直接构建任务（供 store 层反序列化使用；status 为存储字符串，非法回退 Pending）
pub fn Task::from_db(
  id : String,
  parent_id : String?,
  project_dir : String,
  ns : String,
  priority : String,
  importance : String,
  depth : Int32,
  split_n : Int32,
  level : Int32,
  status_s : String,
  assignee : String?,
  description : String,
  deliverable : String,
  created_at : String,
  updated_at : String,
  completed_by : String?,
  cleanup_mode : String,
  depends_on : Array[String],
  omega_required : Bool,
) -> Task {
  let status = match TaskStatus::from_string(status_s) {
    Some(s) => s
    None => Pending
  }
  {
    id,
    parent_id,
    project_dir,
    ns,
    priority,
    importance,
    depth,
    split_n,
    level: clamp_level(level),
    status,
    assignee,
    description,
    deliverable,
    created_at,
    updated_at,
    completed_by,
    cleanup_mode,
    depends_on,
    omega_required,
  }
}

/// —— 状态迁移 ——
/// 每个迁移都是纯函数（返回新 Task），状态机非法流转直接拒绝。
/// 返回 Err(msg) 表示非法迁移。

///|
/// 待领取 -> 已领取（角色：any active agent）
pub fn Task::claim(self : Task, assignee~ : String) -> Result[Task, String] {
  match self.status {
    Pending =>
      if assignee == "" {
        Err("claim 需要 assignee")
      } else {
        Ok({ ..self, status: Claimed, assignee: Some(assignee), })
      }
    _ =>
      Err(
        "非法迁移: claim 要求状态 [待领取]，当前是 [" +
        self.status.to_string() +
        "]",
      )
  }
}

///|
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

///|
/// 拆分中标记（AO 式拆解用，宽于 split：待领取/已领取/拆分中均可转入）
pub fn Task::mark_decomposing(self : Task) -> Result[Task, String] {
  match self.status {
    Pending | Claimed | Splitting => Ok({ ..self, status: Splitting, })
    _ => Err("非法拆解: 任务处于 [\{self.status.to_string()}]")
  }
}

///|
/// 拆分中/已领取/执行中 -> 执行中（进入/覆盖/追加交付物）
/// 执行中 -> execute = 覆盖/追加交付物（retry 后原地更新交付物的直觉行为）
/// BUG-2（Round 2 收口）：合法前态含「执行中」。retry 的落点就是执行中，若这里不收，
///   「被打回重做」这条最该更新交付物的路径会写不进 deliverable（omega_result_verify
///   随即报「尚无交付物」），诱导操作者新建任务覆盖旧账、破坏 append-only 审计。
///   选择放宽 execute 而不改 retry 的落点：retry→执行中 是**对外承诺的语义**
///   （AGENTS.md 工具表「打回后重试（→执行中）」、已发布流水线的状态判据都按它写），
///   改它等于改一条公共状态机迁移；而「执行中重复 execute」本就是幂等追加，影响面更小。
///   错误文案必须给**出路**（当前状态 → 该走哪条迁移），否则调用方只能猜或另起任务。
pub fn Task::execute(self : Task) -> Result[Task, String] {
  match self.status {
    Splitting | Claimed | Executing => Ok({ ..self, status: Executing, })
    _ =>
      Err(
        "非法迁移: execute 要求状态 [拆分中/已领取/执行中]，当前是 [" +
        self.status.to_string() +
        "]。出路：" +
        Task::execute_exit_hint(self.status),
      )
  }
}

///|
/// execute 被拒时按当前状态给出可用出路（BUG-2 文案，纯函数便于回归测试）。
pub fn Task::execute_exit_hint(status : TaskStatus) -> String {
  match status {
    Pending => "待领取→先 claim 再 execute"
    Claimed | Splitting | Executing => "已是可执行状态，直接 execute"
    Rejected =>
      "已打回→先 retry（→执行中）再 execute 覆盖交付物"
    Reviewing =>
      "待验收→若要改交付物先 reject（→已打回）再 retry（→执行中），再 execute"
    Paused => "已暂停→先 resume（→已领取）再 execute"
    Completed =>
      "已完成→原地更正交付物请 reopen_task（→待领取）后重新走链路，勿新建任务覆盖旧账"
    Archived =>
      "已归档→不可写；确需返工先 reopen_task 重开，勿新建任务覆盖旧账"
  }
}

///|
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

///|
/// 待验收 -> 已完成（人类主权：completed_by 必须 human / human_steward 或明确授权）
/// 注意：此处仅校验 completed_by 非空；不引入独立的强身份认证模型（鉴权属上层
/// MCP 工具/MCP 层职责，本域不做权宜式身份伪造防护，避免脆弱的新鉴权模型）。
pub fn Task::complete(
  self : Task,
  completed_by~ : String,
) -> Result[Task, String] {
  match self.status {
    Reviewing =>
      if completed_by == "" {
        Err("complete 需要 completed_by 身份")
      } else {
        Ok({ ..self, status: Completed, completed_by: Some(completed_by), })
      }
    _ =>
      Err(
        "非法迁移: complete 要求状态 [待验收]，当前是 [" +
        self.status.to_string() +
        "]",
      )
  }
}

///|
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

///|
/// 强制归档（BUG-227）：force=true 时放行 已完成/已暂停/已打回 三类滞留态直接入档，
/// 供运维清扫无主积压任务；force=false 时与 Task::archive 完全同义（零回归）。
/// 已领取/执行中/待验收 等在流状态不放行——它们可能仍被活跃 agent 持有，
/// 强制归档会吞掉在途工作；请先 pause 落到已暂停再走本路径。
pub fn Task::archive_force(self : Task, force~ : Bool) -> Result[Task, String] {
  if !force {
    return self.archive()
  }
  match self.status {
    Completed | Paused | Rejected => Ok({ ..self, status: Archived, })
    _ =>
      Err(
        "force archive 仅支持 [已完成/已暂停/已打回]，当前是 [" +
        self.status.to_string() +
        "]；在流状态请先 pause 再强制归档",
      )
  }
}

///|
/// 任意非归档状态 -> 已领取（被打回重做）
pub fn Task::reopen(self : Task) -> Result[Task, String] {
  match self.status {
    Archived => Err("已归档任务不可 reopen，请重新发布")
    Rejected =>
      Ok({ ..self, status: Claimed, assignee: None, deliverable: "", })
    Paused => Ok({ ..self, status: Claimed, })
    _ => Ok({ ..self, status: Claimed, })
  }
}

///|
/// 待验收 -> 已打回（验收不通过，需重做）
pub fn Task::reject(self : Task, reason~ : String = "") -> Result[Task, String] {
  match self.status {
    Reviewing =>
      Ok({
        ..self,
        status: Rejected,
        description: if reason == "" {
          self.description
        } else {
          self.description + " [打回原因: " + reason + "]"
        },
      })
    _ =>
      Err(
        "非法迁移: reject 要求状态 [待验收]，当前是 [" +
        self.status.to_string() +
        "]",
      )
  }
}

///|
/// 已打回 -> 执行中（重新执行）
pub fn Task::retry(self : Task) -> Result[Task, String] {
  match self.status {
    Rejected => Ok({ ..self, status: Executing, })
    _ =>
      Err(
        "非法迁移: retry 要求状态 [已打回]，当前是 [" +
        self.status.to_string() +
        "]",
      )
  }
}

///|
/// 任意活跃状态 -> 已暂停（外部中断/等待依赖）
pub fn Task::pause(self : Task) -> Result[Task, String] {
  match self.status {
    Pending | Claimed | Splitting | Executing | Reviewing | Rejected =>
      Ok({ ..self, status: Paused, })
    Paused => Err("任务已处于暂停状态")
    _ =>
      Err(
        "非法迁移: pause 要求活跃状态，当前是 [" +
        self.status.to_string() +
        "]",
      )
  }
}

///|
/// 已暂停 -> 已领取（恢复执行）
pub fn Task::resume_task(self : Task) -> Result[Task, String] {
  match self.status {
    Paused => Ok({ ..self, status: Claimed, })
    _ =>
      Err(
        "非法迁移: resume_task 要求状态 [已暂停]，当前是 [" +
        self.status.to_string() +
        "]",
      )
  }
}

/// 生成子任务 id：T0.1.2 -> T0.1.2.1

///|
/// 记录类复制更新（跨包不便直接构造 record，由 core 提供）
pub fn Task::with_updated_at(self : Task, now : String) -> Task {
  { ..self, updated_at: now, }
}

///|
pub fn Task::with_deliverable(
  self : Task,
  deliverable : String,
  now : String,
) -> Task {
  { ..self, deliverable, updated_at: now, }
}

///|
/// 追加一条前置依赖（去重）并更新时间戳；返回带新 depends_on 的副本。
/// 供显式 DAG 构建（dag_depend）使用——不只靠 plan_deep 的隐式父子关系。
pub fn Task::with_depends_on(
  self : Task,
  dep_id : String,
  now : String,
) -> Task {
  let deps : Array[String] = if self.depends_on.contains(dep_id) {
    self.depends_on
  } else {
    // 拷贝原依赖数组并追加（Array 可变容器，push 就地生效）
    let out : Array[String] = []
    for d in self.depends_on {
      out.push(d)
    }
    out.push(dep_id)
    out
  }
  { ..self, depends_on: deps, updated_at: now, }
}

///|
pub fn child_id(parent_id~ : String, idx~ : Int32) -> String {
  "\{parent_id}.\{idx}"
}

///|
/// 任务转 JSON（供 MCP resource / tool 输出）

///|
/// 给 AI 编排用的描述截断：**按 UTF-8 字节上限**截断并回退到字符边界。
///
/// 为什么按字节而不是按 `String` 码元（2026-10-23 实测修正）：本工具链的 `String` 内部是 UTF-16，
/// 原先的实现 `if s.length() <= desc_limit` + `s[cut]` 是**码元**语义，而本函数的契约（以及它的用途）
/// 是「控 MCP 返回**体积**」——体积是字节。旧实现在纯中文描述上会把 6 字节当成 6 个字符，
/// 实测 `desc_clip("一二三四五六七八九十", 6)` 返回 `"一二三四五六…"` 而不是 `"一二…"`，
/// 与随本函数同一提交落地的 `core_task_desc_clip_wbtest.mbt:44`（dc_3，期望 `"一二…"`）直接矛盾。
/// 现在先按 UTF-8 编码取真实字节数，超限才切，并在切点回退到 continuation byte 之前
/// （0b10xxxxxx），保证解出来仍是合法 UTF-8。
/// `desc_limit <= 0` 原样返回（零回归锚）。
fn desc_clip(s : String, desc_limit : Int32) -> String {
  if desc_limit <= 0 {
    return s
  }
  let bytes = @encoding.encode(UTF8, s)
  if bytes.length() <= desc_limit {
    return s
  }
  let mut cut = desc_limit
  // 回退：continuation byte 形如 0b10xxxxxx ⇒ 退到字符起始字节
  while cut > 0 && bytes[cut].to_int().land(0xC0) == 0x80 {
    cut = cut - 1
  }
  let sb = StringBuilder()
  @encoding.decode_to(bytes[0:cut], sb, encoding=UTF8) catch {
    _ => ()
  }
  sb.to_string() + "…"
}

///|
/// 任务 JSON。`desc_limit > 0` 时 description 被截断到该字节上限（字符边界安全），
/// 供查询/管家类工具按需控体积——否则膨胀的任务描述（gradient/父计划/边界四问等元信息
/// 递归继承后动辄数 KB）会把 MCP 返回体积炸掉。默认 -1 = 不截断（零回归）。
pub fn Task::to_json(self : Task, desc_limit~ : Int32 = -1) -> Json {
  let m : Map[String, Json] = Map([])
  m.set("id", Json::string(self.id))
  match self.parent_id {
    Some(p) => m.set("parent_id", Json::string(p))
    None => m.set("parent_id", Json::null())
  }
  m.set("project_dir", Json::string(self.project_dir))
  m.set("namespace", Json::string(self.ns))
  m.set("priority", Json::string(self.priority))
  m.set("importance", Json::string(self.importance))
  m.set("depth", Json::number(self.depth.to_double()))
  m.set("split_n", Json::number(self.split_n.to_double()))
  m.set("level", Json::number(self.level.to_double()))
  m.set("status", Json::string(self.status.to_string()))
  match self.assignee {
    Some(a) => m.set("assignee", Json::string(a))
    None => m.set("assignee", Json::null())
  }
  m.set("description", Json::string(desc_clip(self.description, desc_limit)))
  m.set("deliverable", Json::string(self.deliverable))
  m.set("created_at", Json::string(self.created_at))
  m.set("updated_at", Json::string(self.updated_at))
  match self.completed_by {
    Some(c) => m.set("completed_by", Json::string(c))
    None => m.set("completed_by", Json::null())
  }
  m.set("cleanup_mode", Json::string(self.cleanup_mode))
  m.set(
    "depends_on",
    Json::array(self.depends_on.map(fn(d) { Json::string(d) })),
  )
  m.set("is_leaf", Json::boolean(self.is_leaf()))
  m.set("omega_required", Json::boolean(self.omega_required))
  Json::object(m)
}

///|
/// 追加（覆盖）任务描述并更新时间戳；返回带新 description 的副本。
/// 供超级管家 supervisor_task_upsert 使用——只改文本，不动状态机。
pub fn Task::with_description(
  self : Task,
  description : String,
  now : String,
) -> Task {
  { ..self, description, updated_at: now, }
}

///|
/// 覆盖任务优先级（易/中/难一类的中文档位文本）并更新时间戳。
pub fn Task::with_priority(
  self : Task,
  priority : String,
  now : String,
) -> Task {
  { ..self, priority, updated_at: now, }
}
