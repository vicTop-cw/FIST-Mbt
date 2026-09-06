/// FIST-Mbt store: 仓库抽象。
/// 迁移自 FIST(Python) 的双后端（SQLite/PG）设计理念：
/// 定义统一 Store trait，提供可插拔实现。当前交付内存实现（可运行测试、可作 demo），
/// SQLite 后端见 store_sqlite.mbt（Phase 2 落地）。

/// 仓库统一接口
pub trait Store {
  /// 创建任务；id 冲突返回错误
  create_task(Self, Task) -> Result[Unit, String]
  /// 按 id 读取
  get_task(Self, String) -> Option[Task]
  /// 全量更新任务
  update_task(Self, Task) -> Result[Unit, String]
  /// 列出全部任务（任意顺序）
  list_tasks(Self) -> Array[Task]
  /// 删除任务（ARCHIVING 清理用）
  delete_task(Self, String) -> Result[Unit, String]
  /// 清空（仅供测试 / reset）
  clear(Self) -> Unit
}

/// 内存实现：进程内 Map，简单可靠，配合单机 MCP server 足够。
pub struct MemoryStore {
  tasks : Map[String, Task]
}

pub fn MemoryStore::new() -> MemoryStore {
  { tasks: Map([]) }
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
  let out : Array[Task] = []
  self.tasks.each(fn(_, t) { out.push(t) })
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
