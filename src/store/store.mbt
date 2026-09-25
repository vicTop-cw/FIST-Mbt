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
  }
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
  self.call_logs.clear()
  // 作用域预订也在清空范围（防测试/scratch 预订跨次残留）
  self.reservations.clear()
  // 执行者能力注册也在清空范围（防测试/scratch 注册跨次残留，R31）
  self.executors.clear()
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

///|
/// 追加心跳间隔历史（R90：SQLite 落库，内存后端为 no-op——与心跳表同模式）。
pub fn StoreBackend::write_heartbeat_interval(
  self : StoreBackend,
  task_id~ : String,
  interval_sec~ : Int,
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
  limit? : Int = 100,
) -> Array[Int] {
  match self {
    Mem(_) => []
    Sql(s) => s.list_heartbeat_intervals(task_id, limit~)
  }
}

///|
/// 登记 Saga 补偿步骤（R92：SQLite 落库 durable action log，内存后端为 no-op）。
pub fn StoreBackend::write_saga_action(
  self : StoreBackend,
  ns? : String = "default",
  root_task_id~ : String,
  step~ : String,
  task_id? : String = "",
  compensation~ : String,
  created_at~ : String,
) -> Result[Unit, String] {
  match self {
    Mem(_) => Ok(())
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
/// 列出某根任务的 Saga 补偿步骤（R92：内存后端返回空，SQLite 前向顺序）。
pub fn StoreBackend::list_saga_actions(
  self : StoreBackend,
  ns : String,
  root_task_id : String,
) -> Array[(Int, String, String, String, String)] {
  match self {
    Mem(_) => []
    Sql(s) => s.list_saga_actions(ns, root_task_id)
  }
}

///|
/// 把指定 Saga 补偿步骤标记 done（R92：内存后端为 no-op，SQLite 幂等更新）。
pub fn StoreBackend::mark_saga_actions_done(
  self : StoreBackend,
  ns? : String = "default",
  root_task_id~ : String,
  ids~ : Array[Int],
) -> Result[Unit, String] {
  match self {
    Mem(_) => Ok(())
    Sql(s) => s.mark_saga_actions_done(ns~, root_task_id~, ids~)
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
  seq : Int,
  ts : String,
  tool : String,
  caller : String,
  ns : String,
  params_json : String,
  result_json : String,
  ok : Bool,
  runtime_ms : Int,
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
  runtime_ms~ : Int,
  seq~ : Int,
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
  limit? : Int = 50,
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
  runtime_ms~ : Int,
  seq~ : Int,
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
  limit? : Int = 50,
) -> Array[Json] {
  match self {
    Mem(m) => m.recent_call_logs(limit~)
    Sql(s) => s.recent_call_logs(limit~)
  }
}
