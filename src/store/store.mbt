/// FIST-Mbt store: 仓库抽象。
/// 迁移自 FIST(Python) 的双后端（SQLite/PG）设计理念：
/// 定义统一 Store trait，提供可插拔实现。当前交付内存实现（可运行测试、可作 demo），
/// SQLite 后端见 store_sqlite.mbt（Phase 2 落地）。

/// 仓库统一接口
pub trait Store {
  /// 创建任务；id 冲突返回错误
  create_task(Self, @core.Task) -> Result[Unit, String]
  /// 按 id 读取
  get_task(Self, String) -> Option[@core.Task]
  /// 全量更新任务
  update_task(Self, @core.Task) -> Result[Unit, String]
  /// 列出全部任务（任意顺序）
  list_tasks(Self) -> Array[@core.Task]
  /// 删除任务（ARCHIVING 清理用）
  delete_task(Self, String) -> Result[Unit, String]
  /// 清空（仅供测试 / reset）
  clear(Self) -> Unit
}

/// 内存实现：进程内 Map，简单可靠，配合单机 MCP server 足够。
pub struct MemoryStore {
  tasks : Map[String, @core.Task]
  mut default_ns : String
}

pub fn MemoryStore::new() -> MemoryStore {
  { tasks: Map([]), default_ns: "default" }
}

impl Store for MemoryStore with create_task(self, task) {
  if self.tasks.contains(task.get_id()) {
    Err("task already exists: \{task.get_id()}")
  } else {
    self.tasks.set(task.get_id(), task)
    Ok(())
  }
}

impl Store for MemoryStore with get_task(self, id) {
  self.tasks.get(id)
}

impl Store for MemoryStore with update_task(self, task) {
  if !(self.tasks.contains(task.get_id())) {
    return Err("task not found: \{task.get_id()}")
  }
  self.tasks.set(task.get_id(), task)
  Ok(())
}

impl Store for MemoryStore with list_tasks(self) {
  let out : Array[@core.Task] = []
  let ns = self.default_ns
  self.tasks.each(fn(_, t) {
    if t.ns == ns { out.push(t) }
  })
  out
}

/// 列出指定命名空间的任务
pub fn MemoryStore::list_tasks_in(self : MemoryStore, ns_filter : String) -> Array[@core.Task] {
  let out : Array[@core.Task] = []
  let target = if ns_filter == "" { self.default_ns } else { ns_filter }
  self.tasks.each(fn(_, t) {
    if t.ns == target { out.push(t) }
  })
  out
}

impl Store for MemoryStore with delete_task(self, id) {
  if !(self.tasks.contains(id)) {
    Err("task not found: \{id}")
  } else {
    self.tasks.remove(id)
    Ok(())
  }
}

impl Store for MemoryStore with clear(self) {
  self.tasks.clear()
}

/// 提升声明：允许通过具体类型直接调用 trait 方法（避免 deprecated 隐式提升）。
pub extend MemoryStore with Store::{create_task, get_task, update_task, list_tasks, delete_task, clear}

/// 后端路由：内存版（默认，测试/演示）或 SQLite 持久化（运行时内建数据库）。
/// FistEngine 持此类型，业务层不感知具体后端。
pub enum StoreBackend {
  Mem(MemoryStore)
  Sql(SqliteStore)
}

/// 后端工厂（跨包构造 StoreBackend 需经 pub 函数）
pub fn StoreBackend::memory() -> StoreBackend { Mem(MemoryStore::new()) }

pub fn StoreBackend::sqlite(s : SqliteStore) -> StoreBackend { Sql(s) }

impl Store for StoreBackend with create_task(self, task) {
  match self {
    Mem(m) => m.create_task(task)
    Sql(s) => s.create_task(task)
  }
}

impl Store for StoreBackend with get_task(self, id) {
  match self {
    Mem(m) => m.get_task(id)
    Sql(s) => s.get_task(id)
  }
}

impl Store for StoreBackend with update_task(self, task) {
  match self {
    Mem(m) => m.update_task(task)
    Sql(s) => s.update_task(task)
  }
}

impl Store for StoreBackend with list_tasks(self) {
  match self {
    Mem(m) => m.list_tasks()
    Sql(s) => s.list_tasks()
  }
}

/// 列出指定命名空间的任务（跨后端）
pub fn StoreBackend::list_tasks_in(self : StoreBackend, namespace : String) -> Array[@core.Task] {
  match self {
    Mem(m) => m.list_tasks_in(namespace)
    Sql(s) => s.list_tasks_in(namespace)
  }
}

/// 设置默认命名空间
pub fn StoreBackend::set_namespace(self : StoreBackend, namespace : String) -> Unit {
  match self {
    Mem(m) => m.default_ns = namespace
    Sql(_) => ()
  }
}

impl Store for StoreBackend with delete_task(self, id) {
  match self {
    Mem(m) => m.delete_task(id)
    Sql(s) => s.delete_task(id)
  }
}

impl Store for StoreBackend with clear(self) {
  match self {
    Mem(m) => m.clear()
    Sql(s) => s.clear()
  }
}

pub extend StoreBackend with Store::{create_task, get_task, update_task, list_tasks, delete_task, clear}