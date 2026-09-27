///|
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

///|
/// 构造：仅记录根目录，不打开任何库（惰性）。
pub fn MultiStore::new(data_dir? : String = ".") -> MultiStore {
  { stores: Map([]), data_dir, }
}

///|
/// 命名空间消毒：仅允许 `[A-Za-z0-9_-]`，拒绝空串及任何含（斜杠/反斜杠/点/
/// 控制字符/空白）的输入，杜绝路径遍历（`../../etc/x`）与注入。
/// 合法返回浅拷贝后的 ns；非法返回 None。
pub fn MultiStore::safe_ns(ns : String) -> String? {
  if ns == "" {
    return None
  }
  let chars = ns.to_array()
  for c in chars {
    let u = c.to_int()
    let ok = (u >= 48 && u <= 57) ||
      (u >= 65 && u <= 90) ||
      (u >= 97 && u <= 122) ||
      u == 45 ||
      u == 95
    if not(ok) {
      return None
    }
  }
  Some(ns)
}

///|
/// 库文件根目录校验（BUG-78）：只接受**相对 server 进程 cwd** 的相对路径。
/// 拒空串 / `..` 上跳 / 前导分隔符 / 盘符（`C:`）——过去这里只对 ns 走 safe_ns，
/// data_dir 原样拼进 `\{dir}/\{safe}.db` 就交给 SqliteStore::open（open 会建文件），
/// 于是"命名空间物理隔离"实际是"调用方指到哪就往哪建库"。
/// 口径与 src/server/bugreport.mbt 的 bug_project_dir_ok 保持一致：
/// 同族守卫不该有两套规则（project_dir 拒穿越、data_dir 放行，就是本次缺陷的形状）。
pub fn MultiStore::data_dir_ok(dir : String) -> Bool {
  if dir.is_empty() {
    return false
  }
  if dir.contains("..") {
    return false
  }
  let c0 = dir[0]
  if c0 == '/' || c0 == '\\' {
    return false
  }
  // 拒绝盘符（如 C: 或 D:），顺带挡掉 Windows 绝对形态
  if dir.length() >= 2 && dir[1] == ':' {
    return false
  }
  true
}

///|
/// 打开（或复用）某个命名空间对应的库文件 {data_dir}/{safe_ns}.db。
/// ns 会先经 safe_ns 消毒，非法命名空间直接失败返回 false。
/// data_dir~ 为空时回退到 self.data_dir（与 get 保持一致，避免状态分裂）；
/// **两者取用后的最终目录仍要过 data_dir_ok**（BUG-78：消毒范围覆盖实际落点，不只覆盖入参形态）。
pub fn MultiStore::open(
  self : MultiStore,
  ns~ : String,
  data_dir~ : String,
) -> Bool {
  match MultiStore::safe_ns(ns) {
    None => false
    Some(safe) => {
      // 已打开则直接复用（幂等）
      if self.stores.contains(safe) {
        return true
      }
      let dir = if data_dir == "" { self.data_dir } else { data_dir }
      if not(MultiStore::data_dir_ok(dir)) {
        return false
      }
      let path = "\{dir}/\{safe}.db"
      match SqliteStore::open(path) {
        None => false
        Some(s) => {
          self.stores.set(safe, s)
          true
        }
      }
    }
  }
}

///|
/// 获取某 ns 的存储；惰性打开：尚未打开时按 self.data_dir 首次创建/打开，
/// 并在打开成功后缓存进 self.stores，保证后续 get/ns_stats 复用同一句柄。
/// ns 非法（未过 safe_ns）或打开失败返回 None。
pub fn MultiStore::get(self : MultiStore, ns : String) -> SqliteStore? {
  match MultiStore::safe_ns(ns) {
    None => None
    Some(safe) =>
      match self.stores.get(safe) {
        Some(s) => Some(s)
        None =>
          if not(MultiStore::data_dir_ok(self.data_dir)) {
            // 构造期就把根目录写歪（如绝对路径）也不建库：与 open 同口径，别留第二条免检入口
            None
          } else {
            let path = "\{self.data_dir}/\{safe}.db"
            match SqliteStore::open(path) {
              Some(s) => {
                self.stores.set(safe, s)
                Some(s)
              }
              None => None
            }
          }
      }
  }
}

///|
/// 关闭并移除某个命名空间（不删除物理文件，可重新 open 恢复）。
pub fn MultiStore::close(self : MultiStore, ns : String) -> Unit {
  if self.stores.contains(ns) {
    self.stores.remove(ns)
  }
}

///|
/// 关闭全部命名空间。
pub fn MultiStore::close_all(self : MultiStore) -> Unit {
  let keys = self.ns_list()
  for k in keys {
    self.stores.remove(k)
  }
}

///|
/// 列出已打开的命名空间（Map 遍历顺序，不保证稳定）。
pub fn MultiStore::ns_list(self : MultiStore) -> Array[String] {
  let out : Array[String] = []
  self.stores.each(fn(k, _) { out.push(k) })
  out
}

///|
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
