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
}

///|
pub fn MemoryStore::new() -> MemoryStore {
  { tasks: Map([]), specs: Map([]), default_ns: "default", }
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
impl Store for MemoryStore with fn list_tasks(self) {
  let out : Array[@core.Task] = []
  let ns = self.default_ns
  self.tasks.each(fn(_, t) { if t.ns == ns { out.push(t) } })
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
pub fn StoreBackend::set_namespace(
  self : StoreBackend,
  ns : String,
) -> Unit {
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
  tokens_in~ : Int,
  tokens_out~ : Int,
  cost~ : Double,
  duration_ms~ : Int,
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
        Some(db) => aggregate_stats(db)
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
