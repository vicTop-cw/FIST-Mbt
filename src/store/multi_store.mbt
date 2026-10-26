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
/// 默认 `".fist-mbt/data"`（**相对 server 进程 cwd**，经 data_dir_ok 校验）：server 由
/// `.mcp.json` 以目标项目根为 cwd 启动，故默认落点即 `<target>/.fist-mbt/data`
/// （`.fist-mbt/` 机器独有、gitignore；见 scripts/fist-init.py 双骨架）。调用方显式传
/// data_dir 仍完全按传入值落盘（测试/scratch 隔离零回归）。
pub fn MultiStore::new(data_dir~ : String = ".fist-mbt/data") -> MultiStore {
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
    if !ok {
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
      if !MultiStore::data_dir_ok(dir) {
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
          if !MultiStore::data_dir_ok(self.data_dir) {
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
/// 逐层创建目录（`@fs.create_dir` 只建单层，父层缺失会 raise）。
///
/// **为什么需要**（BUG-390）：`SqliteStore::open` 把 `{data_dir}/{ns}.db` 原样交给 SQLite，
/// 而 **SQLite 不创建中间目录**；干净检出上 `.fist-mbt/data` 并不存在
/// ⇒ 第一次打开命名空间库就抛 `unable to open database file`（js 侧 daqing FFI 是 **throw**，
/// 不是返回 null）⇒ 未捕获异常直接打死 serve 进程。
/// 复现（干净树）：`python scripts/mcp_smoke.py` —— 本仓对外宣称的「一键自检」——
/// `tools/list`(170 工具) 与 `issue_scan` 都 PASS，随后 ns=mcp-smoke 的库打开时进程退出，
/// 报错栈 `MultiStore::get → SqliteStore::open → new DatabaseSync`。
fn ensure_dir_tree(dir : String) -> Unit {
  let chars = dir.to_array()
  let n = chars.length()
  let mut i = 0
  while i < n {
    let c = chars[i]
    if c == '/' || c == '\\' {
      if i > 0 {
        let prefix = dir[0:i].to_owned()
        // 盘符根（`E:` / `C:`）不当目录建：建它没意义，多数系统也直接拒
        if !(prefix.length() == 2 && prefix[1] == ':') {
          @fs.create_dir(prefix) catch {
            _ => ()
          }
        }
      }
    }
    i = i + 1
  }
  if n > 0 {
    let last = chars[n - 1]
    if last != '/' && last != '\\' {
      if !(dir.length() == 2 && dir[1] == ':') {
        @fs.create_dir(dir) catch {
          _ => ()
        }
      }
    }
  }
}

///|
/// 为**任意** db 路径补建父目录（`SqliteStore::open` 的前置兜底）。
///
/// 覆盖 `MultiStore::new` 管不到的那一面：调用方把 `FIST_DB_PATH` 之类指到不存在的深层目录时，
/// 仍会抛（BUG-390）。
fn ensure_db_parent_dir(db_path : String) -> Unit {
  if db_path == "" || db_path == ":memory:" {
    return
  }
  let chars = db_path.to_array()
  let n = chars.length()
  let mut last = -1
  let mut i = 0
  while i < n {
    let c = chars[i]
    if c == '/' || c == '\\' {
      last = i
    }
    i = i + 1
  }
  if last <= 0 {
    return
  }
  let parent = db_path[0:last].to_owned()
  if parent == "" || (parent.length() == 2 && parent[1] == ':') {
    return
  }
  ensure_dir_tree(parent)
}

///|
/// 每个已打开 ns 的任务数统计（直接用该 ns 库的 tasks 表 COUNT）。
/// 返回 Json 数组，元素形如 {"ns": "...", "total": N}。
pub fn MultiStore::ns_stats(self : MultiStore) -> Json {
  let m : Map[String, Json] = Map([])
  fn count_tasks(store : SqliteStore) -> Int32 {
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

// ---------------------------------------------------------------------------
// T0r744 · BUG-78 迁移缺口：旧位置存量库 → BUG-78 新默认位置的**真迁移**
//
// 背景：BUG-78 把 store_open 的默认落点从「server cwd 根 `<ns>.db`」改成
// 「`<target>/.fist-mbt/data/<ns>.db`」，但**没有迁移存量库**。BUG-389 只补了
// 「检测到旧库就复用旧位置」（永远不搬），于是：
//   ① 旧库永远停在 cwd 根（默认路径形同虚设，且新位置留下空壳库）；
//   ② 用户先跑出 `.fist-mbt/data/<ns>.db` 空壳、旧位置又有真库时，两边歧义无裁定；
//   ③ 做了没做、做了多少，回执里看不出来。
//
// 本节补的正是这三件：判定（纯函数）/ 迁移（复制，不销毁）/ 回执（moved_tasks 等）。
// ---------------------------------------------------------------------------

///|
/// 文件名探测：是普通文件则 true。
///
/// `@fs.is_file` 在路径缺失时 raise（不是返回 false），迁移判定只关心"在不在"，
/// 所以这里一律折成 false——判定逻辑不该被一次 IO 异常打断。
pub fn db_file_exists(path : String) -> Bool {
  @fs.is_file(path) catch {
    _ => false
  }
}

///|
/// SQLite 文件头探测（16 字节 `SQLite format 3\0`）。
///
/// **为什么必须先探文件头**（实测踩到，不是防御性编程）：`node:sqlite` 的 `prepare`
/// 在非 SQLite 文件上抛的是**裸 JS 异常**（`file is not a database`），而 MoonBit 的
/// `try/catch` 只管自家 error 类型，**接不住裸 JS 异常**——一次脏文件就把 serve 打死。
/// 所以脏文件必须在 `Database::open` **之前**被挡掉。
///
/// 代价说明：`@fs` 只有整读接口，探 16 字节也要整份读盘。迁移路径本来就要整份复制
/// （read_file_to_bytes → write_bytes_to_file），量级一致；这条只在「库文件已存在」
/// 时才走，不是热路径。
fn looks_like_sqlite(path : String) -> Bool {
  let data : Bytes? = Some(@fs.read_file_to_bytes(path)) catch { _ => None }
  match data {
    None => false
    Some(b) => {
      if b.length() < 16 {
        return false
      }
      // "SQLite format 3\0" 的逐字节 ASCII
      let magic : FixedArray[Int32] = [
        83, 81, 76, 105, 116, 101, 32, 102, 111, 114, 109, 97, 116, 32, 51, 0,
      ]
      let mut i = 0
      let mut ok = true
      while i < 16 {
        if b[i].to_int() != magic[i] {
          ok = false
        }
        i = i + 1
      }
      ok
    }
  }
}

///|
/// 只读标量查询：打开库文件跑一条返回单值的 SQL。前置条件由调用方保证
/// （文件存在且过了 `looks_like_sqlite`）——这里不重复探测。
fn db_file_scalar(path : String, sql : String) -> Int32 {
  let mut n = 0
  match @sqlite.Database::open(path) {
    None => ()
    Some(db) => {
      match db.prepare(sql) {
        None => ()
        Some(stmt) => {
          if stmt.step() {
            n = stmt.column_int(0)
          }
          stmt.finalize()
        }
      }
      db.close()
    }
  }
  n
}

///|
/// 只读任务计数（迁移判定与迁移后校验共用）：打开某个库文件数 `tasks` 行数。
///
/// **不建 schema、不切 WAL、不补列**——只读探针不该改动物证。对比之下
/// `SqliteStore::open` 会顺手 CREATE TABLE + `PRAGMA journal_mode=WAL`，
/// 于是"探一下空壳"就把空壳变成了"有全套新表的新库"，判定证据被自己改掉。
///
/// 三道闸（每一道都对应一个实测会打死进程或误判的形状）：
/// 1. 文件不存在 → 0；
/// 2. 文件头不是 SQLite → 0（裸 JS 异常接不住，见 `looks_like_sqlite`）；
/// 3. 先问 `sqlite_master` 有没有 `tasks` 表——**任何合法库都有 sqlite_master**，
///    而对缺表的库直接 `SELECT ... FROM tasks` 同样抛裸 JS 异常
///    （`no such table: tasks`，BUG-94 同族），接不住 ⇒ 空壳库必须先走这一步。
pub fn db_file_task_count(path : String) -> Int32 {
  if !db_file_exists(path) {
    return 0
  }
  if !looks_like_sqlite(path) {
    return 0
  }
  let has_tasks = db_file_scalar(
    path, "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='tasks'",
  )
  if has_tasks == 0 {
    return 0
  }
  db_file_scalar(path, "SELECT COUNT(*) FROM tasks")
}

///|
/// 迁移判定（纯函数，零 IO）：给定两边的存在性与任务数，判定这次 store_open 该不该搬库。
///
/// 返回闭集（每个取值都有对应文案，见 `store_migration_note`）：
/// - `no-legacy`        旧位置没有库（全新项目，正常落新位置）
/// - `legacy-only`      **只有**旧库 → 搬（BUG-78 的正常升级路径）
/// - `empty-target`     两边都有但新位置是空壳（0 条）且旧库有数据 → 搬（本次要治的形状）
/// - `both-empty`       两边都有但都空 → 不搬（没有内容可搬）
/// - `target-has-data`  旧库空壳、新位置有数据 → 不搬
/// - `already-migrated` 新位置行数 ≥ 旧库 → 判为上次迁移的产物，不重复搬（幂等重入）
/// - `conflict`         两边都有数据且新位置不覆盖旧库 → **不自动搬**（自动覆盖会丢数据）
/// - `forced`           `migrate=true` 且旧库有数据 → 搬（新库先留档）
/// - `legacy-empty`     `migrate=true` 但旧库没有任务 → 不搬
pub fn store_migration_reason(
  legacy_present : Bool,
  legacy_tasks : Int32,
  new_present : Bool,
  new_tasks : Int32,
  force : Bool,
) -> String {
  if !legacy_present {
    return "no-legacy"
  }
  if !new_present {
    return "legacy-only"
  }
  if force {
    // 显式要求迁移：旧库有数据才动；旧库是空壳则没有可搬的东西
    if legacy_tasks > 0 {
      return "forced"
    }
    return "legacy-empty"
  }
  if new_tasks == 0 {
    if legacy_tasks > 0 {
      return "empty-target"
    }
    return "both-empty"
  }
  if legacy_tasks == 0 {
    return "target-has-data"
  }
  if new_tasks >= legacy_tasks {
    return "already-migrated"
  }
  "conflict"
}

///|
/// 该判定是否**真搬**文件（只有这三档会写目标位置，其余一律只读判定）。
pub fn store_migration_applies(reason : String) -> Bool {
  reason == "legacy-only" || reason == "empty-target" || reason == "forced"
}

///|
/// 迁移判定的人话说明（回执 `note` 字段的唯一真源）。
///
/// 每一档都必须点出**两边路径与行数**——"做了没有/做了多少"要靠回执自证，
/// 而不是让调用方去猜（T0r744 的第三项验收）。
pub fn store_migration_note(
  reason : String,
  legacy_path : String,
  new_path : String,
  legacy_tasks : Int32,
  new_tasks : Int32,
) -> String {
  match reason {
    "no-legacy" =>
      "旧位置无存量库（\{legacy_path} 不存在）：按 BUG-78 默认落新位置，无需迁移"
    "legacy-only" =>
      "旧位置有库、新位置没有：自动迁移 \{legacy_tasks} 条任务到 \{new_path}" +
      "（旧库原件保留在 \{legacy_path} 当备份，未删除/未改名）"
    "empty-target" =>
      "新位置是空壳（0 条）、旧位置有 \{legacy_tasks} 条：按空壳覆盖迁移" +
      "（旧库原件保留当备份）"
    "both-empty" => "两边都是空库，不迁移"
    "already-migrated" =>
      "新位置已有 \{new_tasks} 条 ≥ 旧位置 \{legacy_tasks} 条：判为上次迁移的产物，不重复迁移"
    "target-has-data" =>
      "旧库是空壳、新位置有 \{new_tasks} 条：不迁移"
    "conflict" =>
      "两边都有数据（新 \{new_tasks} 条 / 旧 \{legacy_tasks} 条）且新位置不覆盖旧库：" +
      "**不自动迁移**（自动覆盖会丢数据）。本次开新位置；旧库原件未动，仍在 \{legacy_path}。" +
      "两条出路：① store_open(migrate=true) 用旧库覆盖新位置（新库先留档 .replaced-bak）；" +
      "② store_open(data_dir=\".\") 继续用旧位置"
    "forced" =>
      "migrate=true 强制：用旧库（\{legacy_tasks} 条）覆盖 \{new_path}，新库原件已留档 .replaced-bak"
    "legacy-empty" =>
      "migrate=true 但旧库没有任务，没有内容可搬，不迁移"
    "invalid-ns" => "命名空间非法，不做迁移"
    "explicit-data-dir" =>
      "调用方显式指定了 data_dir（或 scratch=true）：按传入位置打开，不参与默认落点的迁移判定"
    "already-open" =>
      "该命名空间在本进程里已经打开：不在活库上搬文件（会和 WAL/锁搅在一起），本次只沿用既有句柄"
    "invalid-legacy" =>
      "旧位置存在但文件头不是 SQLite（\{legacy_path}）：不迁移——把脏文件/半截文件" +
      "搬进新默认位置只会把问题放大，也不会让任务变得可见。请人工核对旧文件后再处理"
    "same-dir" => "旧位置与新位置是同一个目录，无需迁移"
    _ => "未识别的迁移判定：\{reason}"
  }
}

///|
/// 迁移结论（回执的数据源）。字段全部是"这次 open 到底做了什么"的自证：
/// 走哪个位置、有没有搬、搬了多少条、旧库/新库各多少条、备份落在哪。
pub struct StoreMigration {
  reason : String
  applied : Bool
  from : String
  to : String
  legacy_tasks : Int32
  new_tasks : Int32
  moved_tasks : Int32
  backup : String
  note : String
}

///|
/// 不迁移的结论工厂（显式 data_dir / ns 已打开 / 非法 ns 等旁路用同一形状回执，
/// 免得调用方要在两种结构之间分支）。
pub fn StoreMigration::skipped(reason : String) -> StoreMigration {
  StoreMigration::skipped_at(reason, "", "")
}

///|
/// 同上，但点名两边路径（"为什么没迁"要能指到具体文件）。
pub fn StoreMigration::skipped_at(
  reason : String,
  from : String,
  to : String,
) -> StoreMigration {
  {
    reason,
    applied: false,
    from,
    to,
    legacy_tasks: 0,
    new_tasks: 0,
    moved_tasks: 0,
    backup: "",
    note: store_migration_note(reason, from, to, 0, 0),
  }
}

///|
/// 回执 JSON（`store_open` 的 `migration` 字段唯一真源）。
pub fn StoreMigration::to_json(self : StoreMigration) -> Json {
  Json::object({
    "reason": Json::string(self.reason),
    "applied": Json::boolean(self.applied),
    "from": Json::string(self.from),
    "to": Json::string(self.to),
    "legacy_tasks": Json::number(self.legacy_tasks.to_double()),
    "new_tasks": Json::number(self.new_tasks.to_double()),
    "migrated_tasks": Json::number(self.moved_tasks.to_double()),
    "backup": Json::string(self.backup),
    "note": Json::string(self.note),
  })
}

///|
/// 逐字节复制文件；读不出/写不进/空文件一律 false（迁移判定要据此拒绝"搬了个空壳"）。
fn copy_file_bytes(src : String, dst : String) -> Bool {
  let data : Bytes? = Some(@fs.read_file_to_bytes(src)) catch { _ => None }
  match data {
    None => false
    Some(bytes) => {
      if bytes.length() == 0 {
        return false
      }
      let wrote : Unit? = Some(@fs.write_bytes_to_file(dst, bytes)) catch {
        _ => None
      }
      match wrote {
        None => false
        Some(_) => true
      }
    }
  }
}

///|
/// 删文件（不存在/删不掉都不算错——清理侧车是"尽力而为"，失败不该阻断迁移）。
fn remove_file_quiet(path : String) -> Unit {
  @fs.remove_file(path) catch {
    _ => ()
  }
}

///|
/// 只读打开并尝试把 WAL 内容并入主库（`wal_checkpoint(TRUNCATE)`）。
///
/// 为什么需要：一个被 kill 的进程会在 `<db>-wal` 里留下最后一段已提交事务，
/// 主库文件本身**不含**那一段。只复制 `.db` 就会丢数据（"迁移完反而少了几条"）。
/// 先 checkpoint 让主库自包含；checkpoint 失败/非 WAL 库不阻断——
/// 下面的复制会把 `-wal` 侧车一并搬走当兜底。
///
/// 这里**不用 try/catch**：调用方已确认文件是合法 SQLite，且实测（node 24）
/// 对非 WAL 库跑 wal_checkpoint 不抛；而裸 JS 异常本来也接不住（见 `looks_like_sqlite`），
/// 写个 try 只会让读者以为这里有保护。
fn checkpoint_db_quiet(path : String) -> Unit {
  match @sqlite.Database::open(path) {
    None => ()
    Some(db) => {
      ignore(db.exec("PRAGMA wal_checkpoint(TRUNCATE)"))
      db.close()
    }
  }
}

///|
/// 旧位置 → BUG-78 新默认位置的**真迁移**（T0r744）。
///
/// 判定见 `store_migration_reason`：只有 `legacy-only` / `empty-target` / `forced`
/// 会真的搬。搬迁口径（每一条都对应一个实测会丢数据的坑）：
/// 1. **复制而不是移动**：旧库原字节留在旧位置当备份，不删除、不改名——
///    不可逆动作不自动做（本仓纪律），回执点名两边路径供人收尾；
/// 2. `-wal` 侧车一并复制（先试 checkpoint）：只搬主库会丢最后一段事务；
/// 3. 目标位置的 `-wal` / `-shm` **先删**：把新主库换掉却留着旧侧车，
///    SQLite 会拿陈旧 WAL 帧覆盖新内容（换库场景的标准坑）；
/// 4. `forced`（两边都有数据）覆盖前先把新库整份复制成 `<new>.db.replaced-bak`，
///    连同它的 `-wal`，不销毁新库内容；
/// 5. 落盘后做**内容级校验**（新库 `tasks` 行数 ≥ 旧库行数），不是只看文件存在——
///    "搬了个空壳/半截文件"必须判失败。
pub fn migrate_legacy_store(
  legacy_dir : String,
  new_dir : String,
  ns : String,
  force~ : Bool = false,
) -> StoreMigration {
  let legacy_path = legacy_dir + "/" + ns + ".db"
  let new_path = new_dir + "/" + ns + ".db"
  // 非法 ns 或同一个目录：直接给结论，不做任何文件动作
  if MultiStore::safe_ns(ns) is None {
    return StoreMigration::skipped("invalid-ns")
  }
  if legacy_dir == new_dir {
    return StoreMigration::skipped("same-dir")
  }
  let legacy_present = db_file_exists(legacy_path)
  let new_present = db_file_exists(new_path)
  // 旧文件不是 SQLite（脏文件/半截文件/被人换成了别的东西）：搬它只会把问题放大，
  // 且搬完 store_open 打开它同样要炸 ⇒ 明确拒绝并点名路径，不做任何写动作。
  if legacy_present && !looks_like_sqlite(legacy_path) {
    return StoreMigration::skipped_at("invalid-legacy", legacy_path, new_path)
  }
  let legacy_tasks = if legacy_present {
    db_file_task_count(legacy_path)
  } else {
    0
  }
  let new_tasks = if new_present { db_file_task_count(new_path) } else { 0 }
  let reason = store_migration_reason(
    legacy_present, legacy_tasks, new_present, new_tasks, force,
  )
  let note = store_migration_note(
    reason, legacy_path, new_path, legacy_tasks, new_tasks,
  )
  let base : StoreMigration = {
    reason,
    applied: false,
    from: legacy_path,
    to: new_path,
    legacy_tasks,
    new_tasks,
    moved_tasks: 0,
    backup: "",
    note,
  }
  if !store_migration_applies(reason) {
    return base
  }
  // —— 真搬 ——（记录字段不可变：每档返回一处构造，避免"改了一半"的半截结论）
  ensure_dir_tree(new_dir)
  let dst_wal = new_path + "-wal"
  let dst_shm = new_path + "-shm"
  // ④ 覆盖前留档（新库有内容时才留；空壳没有留档价值）
  let mut backup = ""
  if new_present && new_tasks > 0 {
    let bak = new_path + ".replaced-bak"
    if copy_file_bytes(new_path, bak) {
      if db_file_exists(dst_wal) {
        ignore(copy_file_bytes(dst_wal, bak + "-wal"))
      }
      backup = bak
    }
  }
  // ③ 换主库前清掉目标侧车
  remove_file_quiet(dst_wal)
  remove_file_quiet(dst_shm)
  // ② 让旧主库自包含，再整份搬（含兜底侧车）
  checkpoint_db_quiet(legacy_path)
  if !copy_file_bytes(legacy_path, new_path) {
    return {
      ..base,
      backup,
      note: "迁移失败：\{legacy_path} 读不出或写入 \{new_path} 失败（旧库原件未动）",
    }
  }
  if db_file_exists(legacy_path + "-wal") {
    ignore(copy_file_bytes(legacy_path + "-wal", dst_wal))
  }
  // ⑤ 内容级校验：行数没跟上就是没搬成
  let got = db_file_task_count(new_path)
  if got < legacy_tasks {
    return {
      ..base,
      backup,
      note: "迁移校验失败：\{new_path} 只有 \{got} 条 < 旧库 \{legacy_tasks} 条（旧库原件未动）",
    }
  }
  { ..base, applied: true, moved_tasks: legacy_tasks, backup, }
}

// ---------------------------------------------------------------------------
// BUG-420 · 命名空间「标签 vs 物理位置」错位诊断（C 案：止血 + 可诊断）
//
// 背景（事实见 reports/2026-10-26-bug420-ns-routing-diagnosis.md）：
//   ns 在四层里有两种角色 —— ①②③ 层把它当**路由键**（决定打开哪个物理库），
//   ④ 层（`tasks.ns` 列）把它当**纯标签**（只被 `WHERE ns=?` 过滤）。
//   当存量任务的标签与物理位置分家时，**数据既没丢也没坏，却永远查不到**：
//   带 ns 查 ⇒ 打开一个空分库 ⇒ `task not found`，而文案只说 ID 没找到，
//   看起来像调用方把 id 写错了。
//
// C 案不动数据（B 案迁移不可逆、需 owner 裁），只做两件事：
//   ① 路由到空库这件事**显式可见**（store_open 回执带 warning）；
//   ② 查不到时**给可行动的信息**（错误文案指出「任务在主库、ns 标签是 X」）。
// 两个文案都由纯函数产出，白盒可锁（multi_store_bug420_wbtest.mbt）。
// ---------------------------------------------------------------------------

///|
/// BUG-420 路由错位诊断（纯计算）。
///
/// `main_tasks` = 主库 `fist-mbt.db` 里带该 ns 标签的任务数；
/// `store_tasks` = 该 ns 物理库（`.fist-mbt/data/<ns>.db`）里的任务数。
///
/// 仅当「主库有、本库空」且 ns 非 `default`/空时返回诊断文案，其余一律返回空串：
/// - `default`/空串本来就走主库，不存在路由错位；
/// - 分库已有数据说明写入路径工作正常，不必告警（**不制造恒阳性**）。
pub fn ns_routing_warning(
  ns : String,
  main_tasks : Int32,
  store_tasks : Int32,
) -> String {
  if ns == "" || ns == "default" {
    return ""
  }
  if main_tasks <= 0 || store_tasks > 0 {
    return ""
  }
  let safe = match MultiStore::safe_ns(ns) {
    Some(s) => s
    None => ns
  }
  "BUG-420：主库 fist-mbt.db 里有 \{main_tasks} 条带 ns 标签 '\{ns}' 的历史任务，" +
  "而本命名空间库 .fist-mbt/data/\{safe}.db 为 \{store_tasks} 条 —— " +
  "**按 ns 查询会找不到它们**（ns 在这里既是路由键又是标签，两者从未对齐；" +
  "数据没丢也没坏，是物理位置与标签分家）。两条出路：" +
  "① 不传 namespace 参数即可查到（这些任务落在主库）；" +
  "② 或等 A 案（读取侧回落主库 + 按 ns 字段过滤）实现后，带 ns 也能查到。"
}

///|
/// BUG-420 查不到时的可行动文案（纯计算）。
///
/// 形状：带 ns 查不到，但主库里同 id 任务的 ns 标签**正好等于**请求的 ns。
/// 这形状下 `task not found: <id>` 是**误导性文案**（看起来像 ID 写错），
/// 必须指出「任务在主库、只是不在这个 ns 库」并给三条出路。
///
/// 前提由调用方（server 的 get/archive handler）负责核验：只在标签对得上时调用，
/// 否则真正的「ID 不存在」会被说成路由错位（那是制造假诊断）。
pub fn ns_misroute_not_found(
  task_id : String,
  ns : String,
  main_ns : String,
) -> String {
  let safe = match MultiStore::safe_ns(ns) {
    Some(s) => s
    None => ns
  }
  "task not found: \{task_id} —— 但该任务在**主库** fist-mbt.db 里" +
  "（ns 标签=\{main_ns}），不在 ns 库 '\{ns}'（.fist-mbt/data/\{safe}.db，空库）中。" +
  "这是 BUG-420（ns 标签与物理位置不一致）：历史任务的 ns 标签仍是 '\{ns}'，" +
  "物理行却留在主库，按 ns 路由只会打开那个空分库。三条出路：" +
  "① 去掉 namespace 参数即可命中（走主库）；" +
  "② get 传 resolve_from_main=true 做**只读**回落（回执带 resolved_from=default(main)）；" +
  "③ 等 A 案（读取侧统一回落 + 按 ns 字段过滤）与 B 案（数据迁移，需 owner 裁）落地。"
}

///|
/// 某个命名空间库里的任务总数（未打开 / 打开失败 / 无句柄一律 0）。
///
/// BUG-420：store_open 回执要给出「本库几条 vs 主库同标签几条」这对读数 ——
/// 过去这两个数只能靠外部 `sqlite3` 直查（诊断报告就是这么拿到 148 vs 0 的）。
/// 注意这里**是惰性打开**（复用 `MultiStore::get` 语义）：调用方应先把 ns open 好。
pub fn MultiStore::ns_task_count(self : MultiStore, ns : String) -> Int32 {
  match self.get(ns) {
    None => 0
    Some(store) =>
      match store.db {
        None => 0
        Some(db) =>
          match db.prepare("SELECT COUNT(*) FROM tasks") {
            None => 0
            Some(stmt) => {
              let n = if stmt.step() { stmt.column_int(0) } else { 0 }
              stmt.finalize()
              n
            }
          }
      }
  }
}
