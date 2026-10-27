/// FIST-Mbt store: 仓库抽象。
/// 迁移自 FIST(Python) 的双后端（SQLite/PG）设计理念：
/// 定义统一 Store trait，提供可插拔实现。当前交付内存实现（可运行测试、可作 demo），
/// SQLite 后端见 store_sqlite.mbt（Phase 2 落地）。

///|
/// 仓库统一接口
pub trait Store {
  /// 创建任务；id 冲突返回错误
  fn create_task(Self, @core.Task) -> Result[Unit, String]
  /// 按 id 读取
  fn get_task(Self, String) -> @core.Task?
  /// 全量更新任务
  fn update_task(Self, @core.Task) -> Result[Unit, String]
  /// 列出全部任务（任意顺序）
  fn list_tasks(Self) -> Array[@core.Task]
  /// 删除任务（ARCHIVING 清理用）
  fn delete_task(Self, String) -> Result[Unit, String]
  /// 清空（仅供测试 / reset）
  fn clear(Self) -> Unit
}

///|
/// 内存实现：进程内 Map，简单可靠，配合单机 MCP server 足够。
pub struct MemoryStore {
  tasks : Map[String, @core.Task]
  specs : Map[String, SpecRecord]
  mut default_ns : String
  // 进程内调用日志（best-effort，软上限 ~500，超限丢最早一条）
  call_logs : Array[Json]
  // 作用域预订（Interlinked 拿来主义：多 agent 并发编辑冲突预防）
  // scope -> (agent, ttl_until, created_at)
  reservations : Map[String, (String, String, String)]
  // 执行者能力注册（Marketplace 雏形持久化，R31）：name -> (abilities_json, created_at)
  executors : Map[String, (String, String)]
  // 分布式文件锁：scope -> FileLock
  file_locks : Map[String, FileLock]
  // 锁违例记录（过期未续 / 被抢占）
  lock_violations : Array[LockViolation]
  // 项目助理登记（multi-agent-lock v3 阶段2）：agent -> AssistantReg
  assistant_reg : Map[String, AssistantReg]
  // BUG-439：熔断器记录（R104 的资源门，此前内存后端**从未实现**）
  //   key = "<ns>\u0000<circuit>"（与 SQLite 侧 UNIQUE(ns, circuit) 同口径），
  //   value = (state, failures, window_secs, threshold, recovery_secs, opened_at, last_fail_ts)
  //
  // 为什么必须存在：此前 `StoreBackend::cb_get(Mem)` 恒返回 `None`、
  // `cb_save(Mem)` 直接 `Ok(())` no-op ⇒ 引擎侧 `failures` 永远读到 0，
  // `nf = failures + 1` 恒为 1，`1 >= threshold(3)` 永不成立 ⇒ **内存后端永不熔断**。
  // 这是**假绿**形态：工具不报错、回执字段齐全、保护从未生效。
  circuit_breakers : Map[String, (String, Int32, Int32, Int32, Int32, Int32, Int32)]
  // BUG-441：Saga 补偿日志（R92 的 durable action log，此前内存后端**从未实现**）
  //   key   = "<ns>\u0000<root_task_id>"（与 SQLite 侧 `WHERE ns=? AND root_task_id=?` 同口径）
  //   value = 该根任务下的步骤数组（**按登记顺序**，对应 SQLite 的 `ORDER BY id ASC`）
  //   每项  = (id, step, task_id, compensation, status)
  //
  // 为什么必须存在：此前三方法在内存后端分别返回 `Ok(())` / `[]` / `Ok(())`
  // ⇒ **补偿序列静默为空**：`saga_rollback` 永远"没有待补偿步骤"、
  // `saga_repair` 永远找不到切片 —— 工具不报错、回执合法、补偿机制从未生效。
  //
  // ⚠️ 这比 BUG-439 的熔断器**更隐蔽**：熔断器的 `state` 恒 `closed` 还算有点异常，
  // 而「没有待补偿步骤」在**任何正常系统里都合法** —— 空列表不是错误信号。
  saga_log : Map[String, Array[(Int32, String, String, String, String)]]
  // 下一个 Saga 步骤 id（模拟 SQLite 的 AUTOINCREMENT：单调递增、不复用）
  mut saga_next_id : Int32
}

///|
/// BUG-441：Saga 日志的进程内复合键（与 SQLite 侧 `ns + root_task_id` 过滤同口径）。
fn saga_key(ns : String, root_task_id : String) -> String {
  ns + "\u{0}" + root_task_id
}

///|
/// BUG-439：熔断器记录的进程内复合键（与 SQLite 的 `UNIQUE(ns, circuit)` 同口径）。
/// 用 `\u{0}` 分隔而不是 `:` —— ns / circuit 名里可能出现 `:`，用 `:` 会有键碰撞。
fn cb_key(ns : String, circuit : String) -> String {
  ns + "\u{0}" + circuit
}

///|
pub fn MemoryStore::new() -> MemoryStore {
  {
    tasks: Map([]),
    specs: Map([]),
    default_ns: "default",
    call_logs: [],
    reservations: Map([]),
    executors: Map([]),
    file_locks: Map([]),
    lock_violations: [],
    assistant_reg: Map([]),
    circuit_breakers: Map([]),
    saga_log: Map([]),
    saga_next_id: 1,
  }
}

// —— 分布式文件锁类型（FileLock / LockViolation）——

///|
/// 文件锁记录（跨后端统一结构）。
pub struct FileLock {
  lock_id : String
  batch_id : String
  scope : String
  agent : String
  /// active / expired / released / violated
  status : String
  ts : String
  ttl_until : String
  meta : String
} derive(Eq, Debug)

///|
pub extend FileLock with Eq::{not_equal, equal}

///|
pub extend FileLock with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// 便捷构造。
pub fn FileLock::new(
  lock_id~ : String,
  batch_id~ : String,
  scope~ : String,
  agent~ : String,
  status~ : String = "active",
  ts~ : String = "",
  ttl_until~ : String = "",
  meta~ : String = "",
) -> FileLock {
  { lock_id, batch_id, scope, agent, status, ts, ttl_until, meta, }
}

///|
/// BUG-424：`FileLock.agent` 的**读访问器**。
///
/// 为什么需要它：本 struct 的字段都是**包内私有**（无 `pub` 修饰）⇒ engine 侧跨包
/// 既不能写 struct literal、也不能直接读字段（BUG-413 已实测编译器拒绝 4036/4033）。
/// 而 `engine_rsv.mbt` 的锁权限门必须读「谁要这把锁」来判角色。
///
/// 只读不改：不提供 setter，避免绕开 `renew` 的时序语义。
pub fn FileLock::agent_of(self : FileLock) -> String {
  self.agent
}

///|
/// BUG-424：`FileLock.scope` 的读访问器（理由同 `agent_of`）—— 权限门要拿 scope 去查规则表。
pub fn FileLock::scope_of(self : FileLock) -> String {
  self.scope
}

///|
/// BUG-424：`FileLock.status` 的读访问器。
///
/// 用途：`locks_try_acquire` 的 `legacy_grant` 特判要判「这条现有锁是不是还活着」
/// （`status == "active"`）—— 只有活着且属于自己的锁才允许在权限门之后续期。
///
/// **只读不改**：本仓惯例（同 `agent_of` / `scope_of`）—— 不给 setter，
/// 改 status 必须走 `renew` / `locks_try_acquire` 那条带时序语义的路。
pub fn FileLock::status_of(self : FileLock) -> String {
  self.status
}

///|
/// 续期：返回同锁的新 ttl_until + ts，status 重置为 active。
pub fn FileLock::renew(
  self : FileLock,
  ttl_until~ : String,
  ts~ : String,
) -> FileLock {
  {
    lock_id: self.lock_id,
    batch_id: self.batch_id,
    scope: self.scope,
    agent: self.agent,
    status: "active",
    ts,
    ttl_until,
    meta: self.meta,
  }
}

///|
/// FileLock → JSON（供 MCP 工具输出）。
pub fn FileLock::to_json(self : FileLock) -> Json {
  Json::object({
    "lock_id": Json::string(self.lock_id),
    "batch_id": Json::string(self.batch_id),
    "scope": Json::string(self.scope),
    "agent": Json::string(self.agent),
    "status": Json::string(self.status),
    "ts": Json::string(self.ts),
    "ttl_until": Json::string(self.ttl_until),
    "meta": Json::string(self.meta),
  })
}

///|
/// 锁违例记录。
pub struct LockViolation {
  ts : String
  agent : String
  scope : String
  reason : String
  lock_id : String
} derive(Eq, Debug)

///|
pub extend LockViolation with Eq::{not_equal, equal}

///|
pub extend LockViolation with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// 便捷构造（LockViolation 字段对外只读，跨包经此构造）。
pub fn LockViolation::new(
  ts~ : String,
  agent~ : String,
  scope~ : String,
  reason~ : String,
  lock_id~ : String,
) -> LockViolation {
  { ts, agent, scope, reason, lock_id, }
}

///|
/// 项目助理登记（multi-agent-lock v3 阶段2 精简版）。
pub struct AssistantReg {
  agent : String
  /// all | lock_keeper | reaper | sheriff | auditor（逗号分隔）
  mode : String
  /// 1=主助理（有 kill 权，本阶段仅登记），0=副助理
  is_primary : Bool
  registered_at : String
  heartbeat_at : String
  /// active | dead | resigned
  status : String
} derive(Eq, Debug)

///|
pub extend AssistantReg with Eq::{not_equal, equal}

///|
pub extend AssistantReg with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// AssistantReg → JSON（供 MCP 工具输出）。
pub fn AssistantReg::to_json(self : AssistantReg) -> Json {
  Json::object({
    "agent": Json::string(self.agent),
    "mode": Json::string(self.mode),
    "is_primary": Json::boolean(self.is_primary),
    "registered_at": Json::string(self.registered_at),
    "heartbeat_at": Json::string(self.heartbeat_at),
    "status": Json::string(self.status),
  })
}

///|
/// 便捷构造（AssistantReg 字段对外只读，跨包经此构造/更新）。
pub fn AssistantReg::new(
  agent~ : String,
  mode~ : String,
  is_primary~ : Bool,
  registered_at~ : String,
  heartbeat_at~ : String,
  status~ : String,
) -> AssistantReg {
  { agent, mode, is_primary, registered_at, heartbeat_at, status, }
}

///|
/// 助理选举裁决**单一真源**：给定现有 active 主助理与本次请求，判「能否当选」+动作标签。
/// 两个后端共用（SQLite 侧语义一致）。cutoff 为心跳新鲜线（ISO 字符串，字典序比较）。
/// 返回 (ok, action, prev_agent)：action ∈ elected / renewed / taken_over / conflict。
pub fn assistant_claim_action(
  prev : AssistantReg?,
  agent : String,
  _now : String,
  cutoff : String,
) -> (Bool, String, String) {
  match prev {
    None => (true, "elected", "")
    Some(r) if r.agent == agent => (true, "renewed", "")
    Some(r) if r.heartbeat_at < cutoff => (true, "taken_over", r.agent)
    Some(r) => (false, "conflict", r.agent)
  }
}

///|
/// LockViolation → JSON。
pub fn LockViolation::to_json(self : LockViolation) -> Json {
  Json::object({
    "ts": Json::string(self.ts),
    "agent": Json::string(self.agent),
    "scope": Json::string(self.scope),
    "reason": Json::string(self.reason),
    "lock_id": Json::string(self.lock_id),
  })
}

///|
impl Store for MemoryStore with fn create_task(self, task) {
  if self.tasks.contains(task.get_id()) {
    Err("task already exists: \{task.get_id()}")
  } else {
    self.tasks.set(task.get_id(), task)
    Ok(())
  }
}

///|
impl Store for MemoryStore with fn get_task(self, id) {
  self.tasks.get(id)
}

///|
impl Store for MemoryStore with fn update_task(self, task) {
  if !self.tasks.contains(task.get_id()) {
    return Err("task not found: \{task.get_id()}")
  }
  self.tasks.set(task.get_id(), task)
  Ok(())
}

///|
pub fn MemoryStore::update_task_if_status(
  self : MemoryStore,
  task : @core.Task,
  expected_status : String,
) -> Result[Unit, String] {
  match self.tasks.get(task.get_id()) {
    None => Err("task not found: \{task.get_id()}")
    Some(current) =>
      if current.get_status().to_string() == expected_status {
        self.tasks.set(task.get_id(), task)
        Ok(())
      } else {
        Err(
          "状态不匹配，期望 [" +
          expected_status +
          "]，当前 [" +
          current.get_status().to_string() +
          "]",
        )
      }
  }
}

///|
/// BUG-85：`Store::list_tasks` 的声明是「列出全部任务」，内存后端过去却按 `default_ns`
/// 悄悄过滤，而 SQLite 后端不过滤（`SELECT ... FROM tasks` 无 WHERE ns）——同一个方法名
/// 两种语义：按 list_all() 取数的 heal/board_ascii/status_summary 在测试（内存桩）里只看
/// 得到 default ns，在生产（SQLite）里看到全库；反过来显式按 ns 过滤的那几处在内存桩上恒空。
/// 按声明收敛：这里返回**全部**，要按命名空间取数用 `list_tasks_in`。
impl Store for MemoryStore with fn list_tasks(self) {
  let out : Array[@core.Task] = []
  self.tasks.each(fn(_, t) { out.push(t) })
  out
}

///|
/// 列出指定命名空间的任务
pub fn MemoryStore::list_tasks_in(
  self : MemoryStore,
  ns_filter : String,
) -> Array[@core.Task] {
  let out : Array[@core.Task] = []
  let target = if ns_filter == "" { self.default_ns } else { ns_filter }
  self.tasks.each(fn(_, t) { if t.ns == target { out.push(t) } })
  out
}

// —— 语料账本（Omega 强验证）：内存后端同样真实读写，保证测试可验证 ——

///|
/// 写入 / 覆盖一条语料记录（主键 id）。
pub fn MemoryStore::upsert_spec(
  self : MemoryStore,
  rec : SpecRecord,
) -> Result[Unit, String] {
  self.specs.set(rec.id, rec)
  Ok(())
}

///|
/// 按 id 读取单条语料记录。
pub fn MemoryStore::get_spec(self : MemoryStore, id : String) -> SpecRecord? {
  self.specs.get(id)
}

///|
/// 列出某任务的全部语料 / 复验记录。
pub fn MemoryStore::list_specs_by_task(
  self : MemoryStore,
  task_id : String,
) -> Array[SpecRecord] {
  let out : Array[SpecRecord] = []
  self.specs.each(fn(_, r) { if r.task_id == task_id { out.push(r) } })
  out
}

///|
/// 更新语料状态（可同时更新内容与时间戳）。
pub fn MemoryStore::update_spec_status(
  self : MemoryStore,
  id : String,
  status : String,
  content : String,
  updated_at : String,
) -> Result[Unit, String] {
  match self.specs.get(id) {
    None => Err("spec not found: \{id}")
    Some(r) => {
      self.specs.set(id, { ..r, status, content, updated_at, })
      Ok(())
    }
  }
}

///|
impl Store for MemoryStore with fn delete_task(self, id) {
  if !self.tasks.contains(id) {
    Err("task not found: \{id}")
  } else {
    self.tasks.remove(id)
    Ok(())
  }
}

///|
impl Store for MemoryStore with fn clear(self) {
  self.tasks.clear()
  self.specs.clear()
  self.call_logs.clear()
  // 作用域预订也在清空范围（防测试/scratch 预订跨次残留）
  self.reservations.clear()
  // 执行者能力注册也在清空范围（防测试/scratch 注册跨次残留，R31）
  self.executors.clear()
  // 文件锁与违例记录也在清空范围
  self.file_locks.clear()
  self.lock_violations.clear()
  self.assistant_reg.clear()
}

///|
/// 提升声明：允许通过具体类型直接调用 trait 方法（避免 deprecated 隐式提升）。
pub extend MemoryStore with Store::{
  create_task,
  get_task,
  update_task,
  list_tasks,
  delete_task,
  clear,
}

///|
/// 后端路由：内存版（默认，测试/演示）或 SQLite 持久化（运行时内建数据库）。
/// FistEngine 持此类型，业务层不感知具体后端。
pub enum StoreBackend {
  Mem(MemoryStore)
  Sql(SqliteStore)
}

///|
/// 后端工厂（跨包构造 StoreBackend 需经 pub 函数）
pub fn StoreBackend::memory() -> StoreBackend {
  Mem(MemoryStore::new())
}

///|
pub fn StoreBackend::sqlite(s : SqliteStore) -> StoreBackend {
  Sql(s)
}

///|
/// 提取底层 SQLite 句柄（内存后端返回 None）。
/// 供跨包复用 SqliteStore 专有能力（如 evolve_artifacts 的 evolve_upsert / evolve_list）。
pub fn StoreBackend::sqlite_store(self : StoreBackend) -> SqliteStore? {
  match self {
    Mem(_) => None
    Sql(s) => Some(s)
  }
}

///|
impl Store for StoreBackend with fn create_task(self, task) {
  match self {
    Mem(m) => m.create_task(task)
    Sql(s) => s.create_task(task)
  }
}

///|
impl Store for StoreBackend with fn get_task(self, id) {
  match self {
    Mem(m) => m.get_task(id)
    Sql(s) => s.get_task(id)
  }
}

///|
impl Store for StoreBackend with fn update_task(self, task) {
  match self {
    Mem(m) => m.update_task(task)
    Sql(s) => s.update_task(task)
  }
}

///|
pub fn StoreBackend::update_task_if_status(
  self : StoreBackend,
  task : @core.Task,
  expected_status : String,
) -> Result[Unit, String] {
  match self {
    Mem(m) => m.update_task_if_status(task, expected_status)
    Sql(s) => s.update_task_if_status(task, expected_status)
  }
}

///|
impl Store for StoreBackend with fn list_tasks(self) {
  match self {
    Mem(m) => m.list_tasks()
    Sql(s) => s.list_tasks()
  }
}

///|
/// 列出指定命名空间的任务（跨后端）
pub fn StoreBackend::list_tasks_in(
  self : StoreBackend,
  ns : String,
) -> Array[@core.Task] {
  match self {
    Mem(m) => m.list_tasks_in(ns)
    Sql(s) => s.list_tasks_in(ns)
  }
}

///|
/// 设置默认命名空间
pub fn StoreBackend::set_namespace(self : StoreBackend, ns : String) -> Unit {
  match self {
    Mem(m) => m.default_ns = ns
    Sql(_) => ()
  }
}

///|
impl Store for StoreBackend with fn delete_task(self, id) {
  match self {
    Mem(m) => m.delete_task(id)
    Sql(s) => s.delete_task(id)
  }
}

///|
impl Store for StoreBackend with fn clear(self) {
  match self {
    Mem(m) => m.clear()
    Sql(s) => s.clear()
  }
}

///|
/// 后端统一：写入/覆盖某作用域预订（拿来主义：Interlinked 文件预订）。
pub fn StoreBackend::rsv_set(
  self : StoreBackend,
  scope~ : String,
  agent~ : String,
  ttl_until~ : String,
  created_at~ : String,
) -> Result[String, String] {
  match self {
    Mem(m) => m.rsv_set(scope~, agent~, ttl_until~, created_at~)
    Sql(s) => s.rsv_set(scope~, agent~, ttl_until~, created_at~)
  }
}

///|
/// 后端统一：按裁决写预订（BUG-136）。抢不到就抢不到，绝不覆盖别人的活体预订；
/// 两个后端返回同一种结论（旧例 BUG-85：同名方法两种语义，单测永远绿而线上红）。
pub fn StoreBackend::rsv_try_set(
  self : StoreBackend,
  scope~ : String,
  agent~ : String,
  ttl_until~ : String,
  created_at~ : String,
) -> Result[RsvOutcome, String] {
  match self {
    Mem(m) => m.rsv_try_set(scope~, agent~, ttl_until~, created_at~)
    Sql(s) => s.rsv_try_set(scope~, agent~, ttl_until~, created_at~)
  }
}

///|
/// 后端统一：查询某作用域预订。
pub fn StoreBackend::rsv_get(
  self : StoreBackend,
  scope : String,
) -> (String, String, String)? {
  match self {
    Mem(m) => m.rsv_get(scope)
    Sql(s) => s.rsv_get(scope)
  }
}

///|
/// 后端统一：释放预订（仅持有者）。
pub fn StoreBackend::rsv_release(
  self : StoreBackend,
  scope : String,
  agent : String,
) -> Bool {
  match self {
    Mem(m) => m.rsv_release(scope, agent)
    Sql(s) => s.rsv_release(scope, agent)
  }
}

///|
/// 后端统一：列出全部预订。
pub fn StoreBackend::rsv_list(
  self : StoreBackend,
) -> Array[(String, String, String)] {
  match self {
    Mem(m) => m.rsv_list()
    Sql(s) => s.rsv_list()
  }
}

///|
/// 后端统一：写入/覆盖一个执行者的能力注册（幂等）。
pub fn StoreBackend::executor_save(
  self : StoreBackend,
  name~ : String,
  abilities_json~ : String,
  created_at~ : String,
) -> Result[String, String] {
  match self {
    Mem(m) => m.executor_save(name~, abilities_json~, created_at~)
    Sql(s) => s.executor_save(name~, abilities_json~, created_at~)
  }
}

///|
/// 后端统一：列出全部执行者 (name, abilities_json, created_at)。
pub fn StoreBackend::executor_list(
  self : StoreBackend,
) -> Array[(String, String, String)] {
  match self {
    Mem(m) => m.executor_list()
    Sql(s) => s.executor_list()
  }
}

///|
/// 后端统一：清空全部执行者能力注册（Marketplace 重置/整洁）。
pub fn StoreBackend::executor_clear(self : StoreBackend) -> Bool {
  match self {
    Mem(m) => m.executor_clear()
    Sql(s) => s.executor_clear()
  }
}

// —— 分布式文件锁（StoreBackend 统一分发）——

///|
pub fn StoreBackend::locks_upsert(self : StoreBackend, lock : FileLock) -> Unit {
  match self {
    Mem(m) => m.locks_upsert(lock)
    Sql(s) => s.locks_upsert(lock)
  }
}

///|
/// 后端统一：按裁决抢锁（BUG-145）——被他人 live 持有时**拒绝**，不覆盖。
/// 两后端必须同一形状（先读后写只在单进程测不出竞态，BUG-85/79 的旧例）。
pub fn StoreBackend::locks_try_acquire(
  self : StoreBackend,
  lock : FileLock,
) -> LockAcquireOutcome {
  match self {
    Mem(m) => m.locks_try_acquire(lock)
    Sql(s) => s.locks_try_acquire(lock)
  }
}

///|
pub fn StoreBackend::locks_get(
  self : StoreBackend,
  scope : String,
) -> FileLock? {
  match self {
    Mem(m) => m.locks_get(scope)
    Sql(s) => s.locks_get(scope)
  }
}

///|
pub fn StoreBackend::locks_list(self : StoreBackend) -> Array[FileLock] {
  match self {
    Mem(m) => m.locks_list()
    Sql(s) => s.locks_list()
  }
}

///|
pub fn StoreBackend::locks_release(
  self : StoreBackend,
  scope : String,
  agent : String,
) -> Bool {
  match self {
    Mem(m) => m.locks_release(scope, agent)
    Sql(s) => s.locks_release(scope, agent)
  }
}

///|
pub fn StoreBackend::locks_sweep(self : StoreBackend, now : String) -> Int32 {
  match self {
    Mem(m) => m.locks_sweep(now)
    Sql(s) => s.locks_sweep(now)
  }
}

///|
pub fn StoreBackend::lock_violations_list(
  self : StoreBackend,
) -> Array[LockViolation] {
  match self {
    Mem(m) => m.lock_violations_list()
    Sql(s) => s.lock_violations_list()
  }
}

// —— 项目助理登记（StoreBackend 统一分发，multi-agent-lock v3 阶段2）——

///|
pub fn StoreBackend::assistant_upsert(
  self : StoreBackend,
  reg : AssistantReg,
) -> Unit {
  match self {
    Mem(m) => m.assistant_upsert(reg)
    Sql(s) => s.assistant_upsert(reg)
  }
}

///|
pub fn StoreBackend::assistant_get(
  self : StoreBackend,
  agent : String,
) -> AssistantReg? {
  match self {
    Mem(m) => m.assistant_get(agent)
    Sql(s) => s.assistant_get(agent)
  }
}

///|
pub fn StoreBackend::assistant_list(self : StoreBackend) -> Array[AssistantReg] {
  match self {
    Mem(m) => m.assistant_list()
    Sql(s) => s.assistant_list()
  }
}

///|
pub fn StoreBackend::assistant_set_status(
  self : StoreBackend,
  agent : String,
  status : String,
) -> Bool {
  match self {
    Mem(m) => m.assistant_set_status(agent, status)
    Sql(s) => s.assistant_set_status(agent, status)
  }
}

///|
pub fn StoreBackend::lock_violations_push(
  self : StoreBackend,
  v : LockViolation,
) -> Unit {
  match self {
    Mem(m) => m.lock_violations_push(v)
    Sql(s) => s.lock_violations_push(v)
  }
}

///|
pub extend StoreBackend with Store::{
  create_task,
  get_task,
  update_task,
  list_tasks,
  delete_task,
  clear,
}

///|
/// 执行元数据记录（可选参数，供 execute 工具写入 executions 表）。
/// MemoryStore 为 no-op，SqliteStore 写入 executions 表。
pub fn StoreBackend::record_execution(
  self : StoreBackend,
  task_id~ : String,
  executor~ : String,
  model~ : String,
  tokens_in~ : Int32,
  tokens_out~ : Int32,
  cost~ : Double,
  duration_ms~ : Int32,
  rate_limited~ : Bool,
  failure_reason~ : String,
  created_at~ : String,
) -> Result[Unit, String] {
  match self {
    Mem(_) => Ok(())
    Sql(s) =>
      s.record_execution(
        task_id~,
        executor~,
        model~,
        tokens_in~,
        tokens_out~,
        cost~,
        duration_ms~,
        rate_limited~,
        failure_reason~,
        created_at~,
      )
  }
}

///|
/// 成本聚合统计：SQLite 后端从 executions 表聚合，内存后端返回零值。
pub fn StoreBackend::cost_stats(self : StoreBackend) -> Json {
  match self {
    Mem(_) => zero_cost_stats("memory")
    Sql(s) =>
      match s.db {
        None => zero_cost_stats("sqlite_no_db")
        // BUG-94：读路径也要 ensure。只在建表清单里补不够——存量库
        // （早于这次补表就建好的 fist-mbt.db）里没有 executions 表，js 桥的
        // prepare 遇到缺表是**抛异常**而不是返回 None，一次 cost_stats 就能打死 server。
        Some(db) =>
          if !s.ensure_executions_table() {
            zero_cost_stats("sqlite_executions_missing")
          } else {
            aggregate_stats(db)
          }
      }
  }
}

///|
fn zero_cost_stats(backend : String) -> Json {
  Json::object({
    "total_records": Json::number(0.0),
    "total_cost": Json::number(0.0),
    "total_tokens_in": Json::number(0.0),
    "total_tokens_out": Json::number(0.0),
    "total_rate_limited": Json::number(0.0),
    "by_executor": Json::object(Map([])),
    "backend": Json::string(backend),
  })
}

///|
/// 写入心跳记录（SQLite 落库，内存后端为 no-op）。
pub fn StoreBackend::write_heartbeat(
  self : StoreBackend,
  agent_id~ : String,
  task_id~ : String,
  last_seen~ : String,
  status~ : String,
) -> Result[Unit, String] {
  match self {
    Mem(_) => Ok(())
    Sql(s) => s.write_heartbeat(agent_id~, task_id~, last_seen~, status~)
  }
}

///|
/// 读取心跳记录（返回 (agent_id, last_seen, status)，无记录返回 ("", "", "")）。
pub fn StoreBackend::read_heartbeat(
  self : StoreBackend,
  task_id : String,
) -> (String, String, String) {
  match self {
    Mem(_) => ("", "", "")
    Sql(s) => s.read_heartbeat(task_id)
  }
}

///|
/// 后端自述（BUG-119）：`"sqlite"` 表示心跳真的落库、跨进程可读；`"memory"` 表示只活在本进程。
/// 看护面必须把它打进回执——否则内存后端会冒充"心跳已持久化"。
pub fn StoreBackend::backend_name(self : StoreBackend) -> String {
  match self {
    Mem(_) => "memory"
    Sql(_) => "sqlite"
  }
}

///|
/// 删除心跳记录。
pub fn StoreBackend::delete_heartbeat(
  self : StoreBackend,
  task_id : String,
) -> Result[Unit, String] {
  match self {
    Mem(_) => Ok(())
    Sql(s) => s.delete_heartbeat(task_id)
  }
}

///|
/// 列出全部心跳记录（供启动时加载）。
pub fn StoreBackend::list_all_heartbeats(
  self : StoreBackend,
) -> Array[(String, String, String, String)] {
  match self {
    Mem(_) => []
    Sql(s) => s.list_all_heartbeats()
  }
}

///|
/// 追加心跳间隔历史（R90：SQLite 落库，内存后端为 no-op——与心跳表同模式）。
pub fn StoreBackend::write_heartbeat_interval(
  self : StoreBackend,
  task_id~ : String,
  interval_sec~ : Int32,
  ts~ : String,
) -> Result[Unit, String] {
  match self {
    Mem(_) => Ok(())
    Sql(s) => s.write_heartbeat_interval(task_id~, interval_sec~, ts~)
  }
}

///|
/// 读取心跳间隔历史（R90：内存后端返回空）。
pub fn StoreBackend::list_heartbeat_intervals(
  self : StoreBackend,
  task_id : String,
  limit~ : Int32 = 100,
) -> Array[Int32] {
  match self {
    Mem(_) => []
    Sql(s) => s.list_heartbeat_intervals(task_id, limit~)
  }
}

///|
/// 登记 Saga 补偿步骤（R92：SQLite 落库 durable action log）。
/// **BUG-441：内存后端已实写**（此前 `Ok(())` no-op ⇒ 补偿序列静默为空）。
///
/// 语义与 SQLite 的 `ON CONFLICT(ns, root_task_id, step) DO UPDATE` **一致**：
/// 同一 `(ns, root_task_id, step)` 重复登记 ⇒ **就地更新**（task_id/compensation 覆盖、
/// status 复位为 `pending`），**不新增行**、**不改 id**。
pub fn StoreBackend::write_saga_action(
  self : StoreBackend,
  ns~ : String = "default",
  root_task_id~ : String,
  step~ : String,
  task_id~ : String = "",
  compensation~ : String,
  created_at~ : String,
) -> Result[Unit, String] {
  match self {
    // 内存版不存 created_at（SQLite 有该列，但 `list_saga_actions` 不返回它、
    // 它也不参与任何判定）⇒ 两侧读回形状一致。
    Mem(m) => {
      let k = saga_key(ns, root_task_id)
      let rows = match m.saga_log.get(k) {
        None => []
        Some(r) => r
      }
      // 幂等：同 step 已存在 ⇒ 就地更新（与 ON CONFLICT DO UPDATE 同口径）
      let mut found = false
      let mut i = 0
      while i < rows.length() {
        let (old_id, old_step, _, _, _) = rows[i]
        if old_step == step {
          rows[i] = (old_id, step, task_id, compensation, "pending")
          found = true
          break
        }
        i = i + 1
      }
      if !found {
        rows.push((m.saga_next_id, step, task_id, compensation, "pending"))
        m.saga_next_id = m.saga_next_id + 1
      }
      m.saga_log.set(k, rows)
      Ok(())
    }
    Sql(s) =>
      s.write_saga_action(
        ns~,
        root_task_id~,
        step~,
        task_id~,
        compensation~,
        created_at~,
      )
  }
}

///|
/// 列出某根任务的 Saga 补偿步骤（R92：**前向顺序** = 登记顺序）。
/// **BUG-441：内存后端已实读**（此前恒 `[]` ⇒ "没有待补偿步骤"永远成立）。
///
/// 返回 `(id, step, task_id, compensation, status)` 五元组数组，与 SQLite 同序同形。
pub fn StoreBackend::list_saga_actions(
  self : StoreBackend,
  ns : String,
  root_task_id : String,
) -> Array[(Int32, String, String, String, String)] {
  match self {
    // 复制一份返回：调用方拿到的是快照，后续 mark done 不会改变已返还的数组
    Mem(m) =>
      match m.saga_log.get(saga_key(ns, root_task_id)) {
        None => []
        Some(r) => r.copy()
      }
    Sql(s) => s.list_saga_actions(ns, root_task_id)
  }
}

///|
/// 把指定 Saga 补偿步骤标记 done（R92：幂等）。
/// **BUG-441：内存后端已实操作**（此前 `Ok(())` 静默无操作 ⇒ mark 了但列表不变）。
pub fn StoreBackend::mark_saga_actions_done(
  self : StoreBackend,
  ns~ : String = "default",
  root_task_id~ : String,
  ids~ : Array[Int32],
) -> Result[Unit, String] {
  if ids.is_empty() {
    return Ok(())
  }
  match self {
    Mem(m) => {
      let k = saga_key(ns, root_task_id)
      match m.saga_log.get(k) {
        None => Ok(())   // 没有该根任务的日志 ⇒ 幂等无操作（与 SQLite 的 UPDATE 0 行同口径）
        Some(rows) => {
          for i = 0; i < rows.length(); i = i + 1 {
            let (id, step, task_id, compensation, status) = rows[i]
            if ids.contains(id) && status != "done" {
              rows[i] = (id, step, task_id, compensation, "done")
            }
          }
          Ok(())
        }
      }
    }
    Sql(s) => s.mark_saga_actions_done(ns~, root_task_id~, ids~)
  }
}

///|
/// 读取某熔断器记录（R104）。**BUG-439：内存后端已实读**（此前恒 `None` ⇒ 永不熔断）。
///
/// 返回 `(state, failures, window_secs, threshold, recovery_secs, opened_at, last_fail_ts)`，
/// 与 `SqliteStore::cb_get` **逐字段同序**。
pub fn StoreBackend::cb_get(
  self : StoreBackend,
  ns : String,
  circuit : String,
) -> (String, Int32, Int32, Int32, Int32, Int32, Int32)? {
  match self {
    Mem(m) => m.circuit_breakers.get(cb_key(ns, circuit))
    Sql(s) => s.cb_get(ns, circuit)
  }
}

///|
/// 写入/覆盖熔断器记录（R104）。**BUG-439：内存后端已实写**（此前是 no-op ⇒ 计数从不累积）。
///
/// 语义与 SQLite 的 `ON CONFLICT(ns, circuit) DO UPDATE` **逐字段一致**：
/// 整体覆盖，不保留旧值（引擎侧每次 save 都写全量快照）。
pub fn StoreBackend::cb_save(
  self : StoreBackend,
  ns : String,
  circuit : String,
  state : String,
  failures : Int32,
  window_secs : Int32,
  threshold : Int32,
  recovery_secs : Int32,
  opened_at : Int32,
  last_fail_ts : Int32,
  updated_at : String,
) -> Result[Unit, String] {
  match self {
    // 内存后端不持久化 `updated_at`（SQLite 有那一列，内存版无对应字段）——
    // 这是**有意的**：`updated_at` 只用于库内审计/排序，不参与三态判定。
    // 引擎侧读回的是 `cb_get` 的 7 元组，本就不含 `updated_at` ⇒ 两侧读回形状一致。
    Mem(m) => {
      m.circuit_breakers.set(
        cb_key(ns, circuit),
        (state, failures, window_secs, threshold, recovery_secs, opened_at, last_fail_ts),
      )
      Ok(())
    }
    Sql(s) =>
      s.cb_save(
        ns, circuit, state, failures, window_secs, threshold, recovery_secs, opened_at,
        last_fail_ts, updated_at,
      )
  }
}

// —— 语料账本（Omega 强验证）：双后端统一入口 ——

///|
/// 写入 / 覆盖一条语料记录（内存与 SQLite 后端均真实落库）。
pub fn StoreBackend::upsert_spec(
  self : StoreBackend,
  rec : SpecRecord,
) -> Result[Unit, String] {
  match self {
    Mem(m) => m.upsert_spec(rec)
    Sql(s) => s.upsert_spec(rec)
  }
}

///|
/// 按 id 读取单条语料记录。
pub fn StoreBackend::get_spec(self : StoreBackend, id : String) -> SpecRecord? {
  match self {
    Mem(m) => m.get_spec(id)
    Sql(s) => s.get_spec(id)
  }
}

///|
/// 列出某任务的全部语料 / 复验记录。
pub fn StoreBackend::list_specs_by_task(
  self : StoreBackend,
  task_id : String,
) -> Array[SpecRecord] {
  match self {
    Mem(m) => m.list_specs_by_task(task_id)
    Sql(s) => s.list_specs_by_task(task_id)
  }
}

///|
/// 更新语料状态。
pub fn StoreBackend::update_spec_status(
  self : StoreBackend,
  id : String,
  status : String,
  content : String,
  updated_at : String,
) -> Result[Unit, String] {
  match self {
    Mem(m) => m.update_spec_status(id, status, content, updated_at)
    Sql(s) => s.update_spec_status(id, status, content, updated_at)
  }
}

// —— 调用日志（call_log）：双后端统一入口 ——

///|
/// 把一次工具调用固化为 call_log 条目 JSON。
fn call_log_to_json(
  seq : Int32,
  ts : String,
  tool : String,
  caller : String,
  ns : String,
  params_json : String,
  result_json : String,
  ok : Bool,
  runtime_ms : Int32,
) -> Json {
  Json::object({
    "seq": Json::number(seq.to_double()),
    "ts": Json::string(ts),
    "tool": Json::string(tool),
    "caller": Json::string(caller),
    "ns": Json::string(ns),
    "params": Json::string(params_json),
    "result": Json::string(result_json),
    "ok": Json::boolean(ok),
    "runtime_ms": Json::number(runtime_ms.to_double()),
  })
}

///|
/// 写入一条调用日志（MemoryStore 进程内 array，软上限 ~500，超限丢最早一条）。
pub fn MemoryStore::write_call_log(
  self : MemoryStore,
  ts~ : String,
  tool~ : String,
  caller~ : String,
  ns~ : String,
  params_json~ : String,
  result_json~ : String,
  ok~ : Bool,
  runtime_ms~ : Int32,
  seq~ : Int32,
) -> Result[Unit, String] {
  let j = call_log_to_json(
    seq, ts, tool, caller, ns, params_json, result_json, ok, runtime_ms,
  )
  self.call_logs.push(j)
  if self.call_logs.length() > 500 {
    ignore(self.call_logs.remove(0))
  }
  Ok(())
}

///|
/// 读取最近 N 条调用日志（新的在前）。
pub fn MemoryStore::recent_call_logs(
  self : MemoryStore,
  limit~ : Int32 = 50,
) -> Array[Json] {
  let n = self.call_logs.length()
  let take = if n > limit { limit } else { n }
  let out : Array[Json] = []
  let mut i = n - 1
  while i >= 0 && out.length() < take {
    out.push(self.call_logs[i])
    i = i - 1
  }
  out
}

///|
/// 写入一条调用日志（双后端统一入口，best-effort：失败仅返回 Err，调用方应忽略）。
pub fn StoreBackend::write_call_log(
  self : StoreBackend,
  ts~ : String,
  tool~ : String,
  caller~ : String,
  ns~ : String,
  params_json~ : String,
  result_json~ : String,
  ok~ : Bool,
  runtime_ms~ : Int32,
  seq~ : Int32,
) -> Result[Unit, String] {
  match self {
    Mem(m) =>
      m.write_call_log(
        ts~,
        tool~,
        caller~,
        ns~,
        params_json~,
        result_json~,
        ok~,
        runtime_ms~,
        seq~,
      )
    Sql(s) =>
      s.write_call_log(
        ts~,
        tool~,
        caller~,
        ns~,
        params_json~,
        result_json~,
        ok~,
        runtime_ms~,
        seq~,
      )
  }
}

///|
/// 读取最近 N 条调用日志（双后端统一入口，新的在前）。
pub fn StoreBackend::recent_call_logs(
  self : StoreBackend,
  limit~ : Int32 = 50,
) -> Array[Json] {
  match self {
    Mem(m) => m.recent_call_logs(limit~)
    Sql(s) => s.recent_call_logs(limit~)
  }
}
