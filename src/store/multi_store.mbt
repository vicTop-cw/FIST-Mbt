/// FIST-Mbt store: 命名空间多库持久化管理器。
/// 按 ns 路由到独立 SQLite 文件 {data_dir}/{ns}.db，惰性打开（首次访问才建库）。
/// 每个 ns 拥有独立的物理库文件，实现多租户/多项目隔离；路径完全由参数传入，
/// 不做任何绝对路径硬编码。
///
/// 可变性模式与 AuditLog 一致：通过 self.stores.set / self.stores.remove 原地修改，
/// 无需在调用方重新赋值。这样可被模块级不可变绑定持有，供 MCP 工具闭包安全调用。

pub struct MultiStore {
  stores : Map[String, SqliteStore]
  data_dir : String
}

/// 构造：仅记录根目录，不打开任何库（惰性）。
pub fn MultiStore::new(data_dir~ : String = ".") -> MultiStore {
  { stores: Map([]), data_dir }
}

/// 打开（或复用已打开的）某个命名空间对应的库文件 {data_dir}/{ns}.db。
/// 失败返回 false，成功返回 true。
pub fn MultiStore::open(self : MultiStore, ns~ : String, data_dir~ : String) -> Bool {
  if ns == "" { return false }
  // 已打开则直接复用（幂等）
  if self.stores.contains(ns) { return true }
  let path = "\{data_dir}/\{ns}.db"
  match SqliteStore::open(path) {
    None => false
    Some(s) => {
      self.stores.set(ns, s)
      true
    }
  }
}

/// 获取某 ns 的存储；惰性打开：尚未打开时按当前 data_dir 首次创建/打开。
/// 打开失败返回 None。
pub fn MultiStore::get(self : MultiStore, ns : String) -> SqliteStore? {
  match self.stores.get(ns) {
    Some(s) => Some(s)
    None => {
      // get 不修改 self，直接尝试打开物理文件（惰性）
      let path = "\{self.data_dir}/\{ns}.db"
      match SqliteStore::open(path) {
        Some(s) => Some(s)
        None => None
      }
    }
  }
}

/// 关闭并移除某个命名空间（不删除物理文件，可重新 open 恢复）。
pub fn MultiStore::close(self : MultiStore, ns : String) -> Unit {
  if self.stores.contains(ns) {
    self.stores.remove(ns)
  }
}

/// 关闭全部命名空间。
pub fn MultiStore::close_all(self : MultiStore) -> Unit {
  let keys = self.ns_list()
  for k in keys {
    self.stores.remove(k)
  }
}

/// 列出已打开的命名空间（Map 遍历顺序，不保证稳定）。
pub fn MultiStore::ns_list(self : MultiStore) -> Array[String] {
  let out : Array[String] = []
  self.stores.each(fn(k, _) { out.push(k) })
  out
}

/// 每个已打开 ns 的任务数统计（直接用该 ns 库的 tasks 表 COUNT）。
/// 返回 Json 数组，元素形如 {"ns": "...", "total": N}。
pub fn MultiStore::ns_stats(self : MultiStore) -> Json {
  let m : Map[String, Json] = Map([])
  fn count_tasks(store : SqliteStore) -> Int {
    let mut n = 0
    match store.db {
      None => n = 0
      Some(db) =>
        match db.prepare("SELECT COUNT(*) FROM tasks") {
          None => n = 0
          Some(stmt) => {
            if stmt.step() {
              n = stmt.column_int(0)
            }
            stmt.finalize()
          }
        }
    }
    n
  }

  self.stores.each(fn(ns, store) {
    let item : Map[String, Json] = Map([])
    item.set("ns", Json::string(ns))
    item.set("total", Json::number(count_tasks(store).to_double()))
    ignore(m.set(ns, Json::object(item)))
  })
  Json::object(m)
}
