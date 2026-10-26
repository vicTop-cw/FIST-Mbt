/// FIST-Mbt store: SQLite 持久化后端（M1 内建数据库）。
/// 依赖 mizchi/sqlite（native+js 双端）。五表骨架单调落盘，其中 tasks 完整接入 Store trait；
/// specs / heartbeats / archive 已接线；**runs 是建了表但全仓零写入零读取的预留骨架**（BUG-28），
/// 别再把它当成"验收有记录可查"——门禁与验收运行实际落 `specs`（gate_check_record 写 spec_type='gate'）。
/// schema-reserved: runs
/// 列约定：parent_id / assignee / completed_by 等可空字段用空串 "" 表示 None。
/// 上面那行 `schema-reserved:` 是机器可读声明，由 scripts/check_store_tables_wired.py 对表：
/// 每张表要么有写入点、要么在这里点名预留，两者都占或都不占一律红灯（防再长出第二张 runs）。

///|
/// SQLite 后端：持有打开的 Database（Option 以承载 open 失败场景）。
pub struct SqliteStore {
  db : @sqlite.Database?
}

///|
/// 打开数据库并初始化五表 schema。失败返回 None（调用方决定是否 abort / 回退内存）。
pub fn SqliteStore::open(db_path : String) -> SqliteStore? {
  // SQLite **不创建中间目录**：`FIST_DB_PATH`（或任何调用方）指到不存在的深层目录时，
  // js 侧 daqing FFI 会在 `DatabaseSync` 构造时 **throw**（不是返回 null），而本函数下面的
  // `match @sqlite.Database::open(...)` 接不住 ⇒ 未捕获异常打死 serve 进程。
  // 命名空间库那条路径已由 `MultiStore::new` 补建 data_dir 覆盖（见 multi_store.mbt）；
  // 这里兜住「任意 db 路径」这一面（BUG-390 报告里点名的遗留项 ①）。
  ensure_db_parent_dir(db_path)
  match @sqlite.Database::open(db_path) {
    None => None
    Some(db) => {
      let s = { db: Some(db), }
      if s.create_schema() {
        // 幂等迁移：旧库升级补现役必需列（见 ensure_task_columns）。
        // BUG-374：补列失败必须**拒载**而非静默降级——缺列库（旧 schema 根库）
        // 会在按 task_id 的读路径 prepare 抛未捕获 SQL 异常、直接打死 serve 进程。
        if !s.ensure_task_columns() {
          db.close()
          return None
        }
        // 启用 WAL 模式提升并发读写性能
        s.exec_if_ok("PRAGMA journal_mode=WAL")
        s.exec_if_ok("PRAGMA synchronous=NORMAL")
        // BUG-136：WAL 只解决「读写不互斥」，不解决「写写撞锁」。没有 busy_timeout 时，
        // 第二个写连接立刻拿 SQLITE_BUSY，而 `mizchi/sqlite` 的 js 桥不 catch（`Statement::execute`
        // 是 `stmt.run(...) |> ignore; true`），异常一路穿透 ⇒ **server 进程 rc=1 死掉**
        // （实测两进程并发 reserve_scope：20 轮里 17 轮打死对端，逐字 `Error: database is locked`）。
        // busy_timeout 让撞锁方**等**而不是抛；这把闸是任何跨进程协调（F094 的文件绑定层）的前提。
        // 5000ms 与本仓 RPC 调用面的 25s 探针超时之间留了 5 倍余量，且远小于一次工具调用的可接受等待。
        s.exec_if_ok("PRAGMA busy_timeout=5000")
        Some(s)
      } else {
        db.close()
        None
      }
    }
  }
}

///|
/// 执行一条 SQL（忽略返回值，仅供 PRAGMA 等 DDL 使用）。
fn SqliteStore::exec_if_ok(self : SqliteStore, sql : String) -> Unit {
  match self.db {
    None => ()
    Some(db) =>
      match db.prepare(sql) {
        None => ()
        Some(stmt) => {
          ignore(stmt.execute())
          stmt.finalize()
        }
      }
  }
}

///|
/// 默认库路径（相对 server 进程 cwd）。
let default_db_path : String = "fist-mbt.db"

///|
/// 由环境值决定库路径（纯函数，便于白盒判据；空串视为未设置）。
pub fn SqliteStore::db_path_from_env(env_value : String?) -> String {
  match env_value {
    Some(p) => if p.is_empty() { default_db_path } else { p }
    None => default_db_path
  }
}

///|
/// 进程默认库路径回显（只读，供工具与 CLI 说明"这一轮的行到底落在哪个文件"）。
pub fn SqliteStore::default_db_path() -> String {
  SqliteStore::db_path_from_env(@env.get_env_var("FIST_DB_PATH"))
}

///|
/// 以默认路径打开的便捷构造。
/// BUG-90：默认路径过去写死 `fist-mbt.db`，调用面没有任何合规出口把一整轮验证
/// 收进独立库 —— `store_open(scratch=true)` 自称"库落 temp/ 临时区，不污染仓库根"，
/// 实测任务行仍落仓库根 `fist-mbt.db`（工具闭包用的是模块级 engine，而非 mstore 里的 ns 库）。
/// 这里补的是**运维侧**出口：`FIST_DB_PATH` 环境变量，与 `FIST_RUN_CHECK_ALLOW` 同族
/// （扩权位只在进程环境里，调用方传参不能自我扩权）。未设置时行为逐字不变。
pub fn SqliteStore::new() -> SqliteStore? {
  SqliteStore::open(SqliteStore::default_db_path())
}

///|
/// 初始化 schema：tasks 为完整任务表，specs/runs/heartbeats/archive 为后续阶段预置骨架。
fn SqliteStore::create_schema(self : SqliteStore) -> Bool {
  let sqls : Array[String] = [
    "CREATE TABLE IF NOT EXISTS tasks (id TEXT PRIMARY KEY, parent_id TEXT DEFAULT '', project_dir TEXT NOT NULL DEFAULT '', ns TEXT NOT NULL DEFAULT 'default', priority TEXT NOT NULL DEFAULT '中', importance TEXT NOT NULL DEFAULT '中', depth INTEGER NOT NULL DEFAULT 3, split_n INTEGER NOT NULL DEFAULT 3, level INTEGER NOT NULL DEFAULT 6, status TEXT NOT NULL DEFAULT '待领取', assignee TEXT DEFAULT '', description TEXT NOT NULL DEFAULT '', deliverable TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL DEFAULT '', updated_at TEXT NOT NULL DEFAULT '', completed_by TEXT DEFAULT '', cleanup_mode TEXT NOT NULL DEFAULT 'deferred', depends_on TEXT NOT NULL DEFAULT '[]', omega_required INTEGER NOT NULL DEFAULT 0)",
    "CREATE TABLE IF NOT EXISTS specs (id TEXT PRIMARY KEY, task_id TEXT NOT NULL DEFAULT '', spec_type TEXT NOT NULL DEFAULT 'spec', content TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'pending', created_at TEXT NOT NULL DEFAULT '', updated_at TEXT NOT NULL DEFAULT '')",
    "CREATE TABLE IF NOT EXISTS runs (id TEXT PRIMARY KEY, task_id TEXT NOT NULL DEFAULT '', run_type TEXT NOT NULL DEFAULT 'verify', status TEXT NOT NULL DEFAULT 'running', detail TEXT NOT NULL DEFAULT '', started_at TEXT NOT NULL DEFAULT '', finished_at TEXT DEFAULT '')",
    "CREATE TABLE IF NOT EXISTS heartbeats (agent_id TEXT NOT NULL, task_id TEXT NOT NULL, last_seen TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'active', PRIMARY KEY (agent_id, task_id))",
    "CREATE TABLE IF NOT EXISTS heartbeat_history (id INTEGER PRIMARY KEY AUTOINCREMENT, task_id TEXT NOT NULL DEFAULT '', interval_sec INTEGER NOT NULL DEFAULT 0, ts TEXT NOT NULL DEFAULT '')",
    "CREATE TABLE IF NOT EXISTS saga_log (id INTEGER PRIMARY KEY AUTOINCREMENT, ns TEXT NOT NULL DEFAULT 'default', root_task_id TEXT NOT NULL DEFAULT '', step TEXT NOT NULL DEFAULT '', task_id TEXT NOT NULL DEFAULT '', compensation TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'pending', created_at TEXT NOT NULL DEFAULT '', UNIQUE(ns, root_task_id, step))",
    "CREATE TABLE IF NOT EXISTS archive (id TEXT PRIMARY KEY, task_json TEXT NOT NULL DEFAULT '', archived_at TEXT NOT NULL DEFAULT '')",
    "CREATE TABLE IF NOT EXISTS evolve_artifacts (id TEXT PRIMARY KEY, parent_id TEXT DEFAULT '', goal TEXT NOT NULL DEFAULT '', note TEXT NOT NULL DEFAULT '', code TEXT NOT NULL DEFAULT '', score TEXT NOT NULL DEFAULT '0', parts_json TEXT NOT NULL DEFAULT '{}', children INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL DEFAULT '')",
    "CREATE TABLE IF NOT EXISTS call_log (id INTEGER PRIMARY KEY AUTOINCREMENT, seq INTEGER, ts TEXT, tool TEXT, caller TEXT, ns TEXT, params_json TEXT, result_json TEXT, ok INTEGER, runtime_ms INTEGER)",
    "CREATE TABLE IF NOT EXISTS reservations (scope TEXT PRIMARY KEY, agent TEXT NOT NULL DEFAULT '', ttl_until TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL DEFAULT '')",
    "CREATE TABLE IF NOT EXISTS executors (name TEXT PRIMARY KEY, abilities_json TEXT NOT NULL DEFAULT '[]', created_at TEXT NOT NULL DEFAULT '')",
    // 分布式文件锁：scope 为主键，同一作用域只保留最新一笔
    "CREATE TABLE IF NOT EXISTS file_locks (scope TEXT PRIMARY KEY, lock_id TEXT NOT NULL DEFAULT '', batch_id TEXT NOT NULL DEFAULT '', agent TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'active', ts TEXT NOT NULL DEFAULT '', ttl_until TEXT NOT NULL DEFAULT '', meta TEXT NOT NULL DEFAULT '')",
    // 锁违例记录（过期未续 / 被抢占），追加式
    "CREATE TABLE IF NOT EXISTS lock_violations (id INTEGER PRIMARY KEY AUTOINCREMENT, ts TEXT NOT NULL DEFAULT '', agent TEXT NOT NULL DEFAULT '', scope TEXT NOT NULL DEFAULT '', reason TEXT NOT NULL DEFAULT '', lock_id TEXT NOT NULL DEFAULT '')",
    // 项目助理登记（multi-agent-lock v3 阶段2）：agent 为主键，同一助理一行
    "CREATE TABLE IF NOT EXISTS assistant_reg (agent TEXT PRIMARY KEY, mode TEXT NOT NULL DEFAULT 'all', is_primary INTEGER NOT NULL DEFAULT 0, registered_at TEXT NOT NULL DEFAULT '', heartbeat_at TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'active')",
    // BUG-94：executions 过去**不在**建表清单里，只在**写**路径上 ensure
    // （record_execution 调 ensure_executions_table）。读路径 `cost_stats` 直接
    // prepare `FROM executions` ⇒ 新库（没写过任何执行记录）上一次 cost_stats 就
    // `Error: no such table: executions`，而 js 桥的 prepare 是**抛异常**不是返回 None
    // ⇒ 未捕获异常一路打死 server 进程（实测 2026-09-28 三格全复现：仓库根/无参、
    // 仓库根/带 ns、临时 box/无参）。表要么一开始就在，要么读写两侧都 ensure——
    // 这里两条都做：新库由建表清单覆盖，旧库由 cost_stats 的 ensure 兜住。
    executions_table_sql(),
    "CREATE TABLE IF NOT EXISTS circuit_breakers (ns TEXT NOT NULL DEFAULT 'default', circuit TEXT NOT NULL DEFAULT '', state TEXT NOT NULL DEFAULT 'closed', failures INTEGER NOT NULL DEFAULT 0, window_secs INTEGER NOT NULL DEFAULT 60, threshold INTEGER NOT NULL DEFAULT 3, recovery_secs INTEGER NOT NULL DEFAULT 30, opened_at INTEGER NOT NULL DEFAULT 0, last_fail_ts INTEGER NOT NULL DEFAULT 0, updated_at TEXT NOT NULL DEFAULT '', PRIMARY KEY (ns, circuit))",
    // Agent 指纹注册表（进程级身份）：agent_id 即指纹哈希，跨进程持久；pid 可换绑
    "CREATE TABLE IF NOT EXISTS agents (agent_id TEXT PRIMARY KEY, agent_type TEXT NOT NULL DEFAULT 'unknown', role TEXT NOT NULL DEFAULT 'Executor', soldier TEXT NOT NULL DEFAULT '工兵', pid INTEGER NOT NULL DEFAULT 0, pubkey_fp TEXT NOT NULL DEFAULT '', first_seen TEXT NOT NULL DEFAULT '', last_seen TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'active')",
    // Agent ACL：默认 can_write=0（fail-closed），按 ns 授权
    "CREATE TABLE IF NOT EXISTS agent_acl (agent_id TEXT NOT NULL, ns TEXT NOT NULL, can_read INTEGER NOT NULL DEFAULT 1, can_write INTEGER NOT NULL DEFAULT 0, pid_bound INTEGER NOT NULL DEFAULT 0, revoked_at TEXT NOT NULL DEFAULT '', revoked_by TEXT NOT NULL DEFAULT '', PRIMARY KEY (agent_id, ns))",
  ]
  match self.db {
    None => false
    Some(db) => {
      let mut ok = true
      for s in sqls {
        if !db.exec(s) {
          ok = false
        }
      }
      ok
    }
  }
}

///|
/// 幂等迁移：确保 tasks 表含全部**现役必需列**（BUG-374 升级 ensure_level_column）。
/// 旧代际库缺列时按 task_id 的读路径（get_task prepare 18 列 SELECT）会抛
/// 未捕获 SQL 异常 ⇒ 直接打死 serve 进程。这里启动期探测并补列；补不动返回
/// false，由 open 决定**拒载**（明确失败，而不是留一颗运行期炸弹）。
/// 重复调用不报错、不加多列（命中已有列直接跳过）；已有任务自动拿到默认值
/// （level=6 连长 / ns=default / depends_on=[] 等）。**绝不抛未捕获异常**——
/// 整段用 catch 兜底，探测失败视为迁移失败返回 false。
fn SqliteStore::ensure_task_columns(self : SqliteStore) -> Bool {
  match self.db {
    None => false
    Some(db) => {
      let cols : Map[String, Bool] = Map([])
      let mut probe_ok = true
      try {
        match db.prepare("PRAGMA table_info(tasks)") {
          None => probe_ok = false
          Some(stmt) => {
            while stmt.step() {
              let name = str_from_bytes(stmt.column_text(1))
              cols.set(name, true)
            }
            stmt.finalize()
          }
        }
      } catch {
        _ => probe_ok = false
      }
      if !probe_ok {
        return false
      }
      // 现役 19 列中旧代际库可能缺失的列：
      // 16 列版（无 ns/depends_on）、17 列版（有 ns 无 level）、18 列版（无 omega_required）。
      // 其余列（parent_id/priority/importance/...）自 16 列版起即存在，无需补。
      // BUG-389 方向②：Omega 门禁开关判据从 description 文本移到不可覆盖的元数据列
      // omega_required（旧库缺列时默认 0=关闭，向后兼容）。
      let needed : Array[(String, String)] = [
        (
          "ns", "ALTER TABLE tasks ADD COLUMN ns TEXT NOT NULL DEFAULT 'default'",
        ),
        (
          "level", "ALTER TABLE tasks ADD COLUMN level INTEGER NOT NULL DEFAULT 6",
        ),
        (
          "completed_by", "ALTER TABLE tasks ADD COLUMN completed_by TEXT DEFAULT ''",
        ),
        (
          "cleanup_mode", "ALTER TABLE tasks ADD COLUMN cleanup_mode TEXT NOT NULL DEFAULT 'deferred'",
        ),
        (
          "depends_on", "ALTER TABLE tasks ADD COLUMN depends_on TEXT NOT NULL DEFAULT '[]'",
        ),
        (
          "omega_required", "ALTER TABLE tasks ADD COLUMN omega_required INTEGER NOT NULL DEFAULT 0",
        ),
      ]
      let mut ok = true
      for (name, sql) in needed {
        if !cols.contains(name) {
          match db.exec(sql) {
            true => ()
            false => ok = false
          }
          cols.set(name, true)
        }
      }
      ok
    }
  }
}

// —— 行 <-> Task 序列化辅助 ——

///|
fn SqliteStore::task_columns() -> String {
  "id, parent_id, project_dir, ns, priority, importance, depth, split_n, level, status, assignee, description, deliverable, created_at, updated_at, completed_by, cleanup_mode, depends_on, omega_required"
}

///|
fn SqliteStore::bind_task_values(
  stmt : @sqlite.Statement,
  t : @core.Task,
) -> Unit {
  ignore(
    stmt.bind(1, @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.get_id()))),
  )
  ignore(
    stmt.bind(
      2,
      @sqlite.SqlValue::Text(@encoding.encode(UTF8, _opt_str(t.get_parent()))),
    ),
  )
  ignore(
    stmt.bind(3, @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.project_dir))),
  )
  ignore(stmt.bind(4, @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.ns))))
  ignore(
    stmt.bind(5, @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.priority))),
  )
  ignore(
    stmt.bind(6, @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.importance))),
  )
  ignore(stmt.bind(7, @sqlite.SqlValue::Int(t.depth)))
  ignore(stmt.bind(8, @sqlite.SqlValue::Int(t.split_n)))
  ignore(stmt.bind(9, @sqlite.SqlValue::Int(t.get_level())))
  ignore(
    stmt.bind(
      10,
      @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.status.to_string())),
    ),
  )
  ignore(
    stmt.bind(
      11,
      @sqlite.SqlValue::Text(@encoding.encode(UTF8, _opt_str(t.get_assignee()))),
    ),
  )
  ignore(
    stmt.bind(12, @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.description))),
  )
  ignore(
    stmt.bind(13, @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.deliverable))),
  )
  ignore(
    stmt.bind(14, @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.created_at))),
  )
  ignore(
    stmt.bind(15, @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.updated_at))),
  )
  ignore(
    stmt.bind(
      16,
      @sqlite.SqlValue::Text(@encoding.encode(UTF8, _opt_str(t.completed_by))),
    ),
  )
  ignore(
    stmt.bind(
      17,
      @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.cleanup_mode)),
    ),
  )
  ignore(
    stmt.bind(
      18,
      @sqlite.SqlValue::Text(
        @encoding.encode(UTF8, _array_to_json(t.depends_on)),
      ),
    ),
  )
  ignore(
    stmt.bind(
      19,
      @sqlite.SqlValue::Int(if t.get_omega_required() { 1 } else { 0 }),
    ),
  )
}

///|
/// UPDATE 专用绑定：SET 列顺序（parent_id..cleanup_mode）+ WHERE id
fn SqliteStore::bind_task_update_values(
  stmt : @sqlite.Statement,
  t : @core.Task,
) -> Unit {
  ignore(
    stmt.bind(
      1,
      @sqlite.SqlValue::Text(@encoding.encode(UTF8, _opt_str(t.get_parent()))),
    ),
  )
  ignore(
    stmt.bind(2, @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.project_dir))),
  )
  ignore(stmt.bind(3, @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.ns))))
  ignore(
    stmt.bind(4, @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.priority))),
  )
  ignore(
    stmt.bind(5, @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.importance))),
  )
  ignore(stmt.bind(6, @sqlite.SqlValue::Int(t.depth)))
  ignore(stmt.bind(7, @sqlite.SqlValue::Int(t.split_n)))
  ignore(
    stmt.bind(
      8,
      @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.status.to_string())),
    ),
  )
  ignore(
    stmt.bind(
      9,
      @sqlite.SqlValue::Text(@encoding.encode(UTF8, _opt_str(t.get_assignee()))),
    ),
  )
  ignore(
    stmt.bind(10, @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.description))),
  )
  ignore(
    stmt.bind(11, @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.deliverable))),
  )
  ignore(
    stmt.bind(12, @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.created_at))),
  )
  ignore(
    stmt.bind(13, @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.updated_at))),
  )
  ignore(
    stmt.bind(
      14,
      @sqlite.SqlValue::Text(@encoding.encode(UTF8, _opt_str(t.completed_by))),
    ),
  )
  ignore(
    stmt.bind(
      15,
      @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.cleanup_mode)),
    ),
  )
  ignore(
    stmt.bind(
      16,
      @sqlite.SqlValue::Text(
        @encoding.encode(UTF8, _array_to_json(t.depends_on)),
      ),
    ),
  )
  ignore(
    stmt.bind(
      17,
      @sqlite.SqlValue::Int(if t.get_omega_required() { 1 } else { 0 }),
    ),
  )
}

///|
fn str_from_bytes(b : Bytes) -> String {
  let sb = StringBuilder()
  @encoding.decode_to(b, sb, encoding=UTF8) catch {
    _ => ()
  }
  sb.to_string()
}

///|
fn _opt_str(o : String?) -> String {
  match o {
    Some(s) => s
    None => ""
  }
}

///|
/// 序列化 Array[String] 为 JSON 数组（经 Json 库转义引号/反斜杠/控制字符，
/// 避免 id 含特殊字符时产生非法 JSON）。
fn _array_to_json(arr : Array[String]) -> String {
  Json::array(arr.map(fn(s) { Json::string(s) })).stringify()
}

///|
fn _json_to_array(json : String) -> Array[String] {
  let parsed = @json.parse(json) catch { _ => Json::null() }
  match parsed {
    Json::Array(arr) =>
      arr.map(fn(v) {
        match v {
          Json::String(s) => s
          _ => ""
        }
      })
    _ => []
  }
}

///|
fn row_to_task(stmt : @sqlite.Statement) -> @core.Task {
  let parent_raw = str_from_bytes(stmt.column_text(1))
  let assignee_raw = str_from_bytes(stmt.column_text(10))
  let completed_raw = str_from_bytes(stmt.column_text(15))
  let depends_raw = str_from_bytes(stmt.column_text(17))
  let omega_raw = stmt.column_int(18)
  @core.Task::from_db(
    str_from_bytes(stmt.column_text(0)),
    if parent_raw == "" {
      None
    } else {
      Some(parent_raw)
    },
    str_from_bytes(stmt.column_text(2)),
    str_from_bytes(stmt.column_text(3)),
    str_from_bytes(stmt.column_text(4)),
    str_from_bytes(stmt.column_text(5)),
    stmt.column_int(6),
    stmt.column_int(7),
    stmt.column_int(8),
    str_from_bytes(stmt.column_text(9)),
    if assignee_raw == "" {
      None
    } else {
      Some(assignee_raw)
    },
    str_from_bytes(stmt.column_text(11)),
    str_from_bytes(stmt.column_text(12)),
    str_from_bytes(stmt.column_text(13)),
    str_from_bytes(stmt.column_text(14)),
    if completed_raw == "" {
      None
    } else {
      Some(completed_raw)
    },
    str_from_bytes(stmt.column_text(16)),
    _json_to_array(depends_raw),
    omega_raw != 0,
  )
}

// —— Store trait 实现 ——

///|
impl Store for SqliteStore with fn create_task(self, task) {
  match self.db {
    None => Err("sqlite store 未打开")
    Some(db) => {
      match self.get_task(task.get_id()) {
        Some(_) => return Err("task already exists: \{task.get_id()}")
        None => ()
      }
      let sql = "INSERT INTO tasks (\{SqliteStore::task_columns()}) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)"
      match db.prepare(sql) {
        None => Err("sqlite prepare 失败: create_task")
        Some(stmt) => {
          SqliteStore::bind_task_values(stmt, task)
          let exec_ok = stmt.execute()
          stmt.finalize()
          if exec_ok {
            Ok(())
          } else {
            Err("sqlite 写入失败: \{task.get_id()}")
          }
        }
      }
    }
  }
}

///|
impl Store for SqliteStore with fn get_task(self, id) {
  match self.db {
    None => None
    Some(db) => {
      let sql = "SELECT \{SqliteStore::task_columns()} FROM tasks WHERE id = ?"
      match db.prepare(sql) {
        None => None
        Some(stmt) => {
          ignore(
            stmt.bind(1, @sqlite.SqlValue::Text(@encoding.encode(UTF8, id))),
          )
          let found = if stmt.step() { Some(row_to_task(stmt)) } else { None }
          stmt.finalize()
          found
        }
      }
    }
  }
}

///|
impl Store for SqliteStore with fn update_task(self, task) {
  match self.db {
    None => Err("sqlite store 未打开")
    Some(db) => {
      if self.get_task(task.get_id()) is None {
        return Err("task not found: \{task.get_id()}")
      }
      let sql = "UPDATE tasks SET parent_id = ?, project_dir = ?, ns = ?, priority = ?, importance = ?, depth = ?, split_n = ?, status = ?, assignee = ?, description = ?, deliverable = ?, created_at = ?, updated_at = ?, completed_by = ?, cleanup_mode = ?, depends_on = ?, omega_required = ? WHERE id = ?"
      match db.prepare(sql) {
        None => Err("sqlite prepare 失败: update_task")
        Some(stmt) => {
          SqliteStore::bind_task_update_values(stmt, task)
          ignore(
            stmt.bind(
              18,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, task.get_id())),
            ),
          )
          let exec_ok = stmt.execute()
          stmt.finalize()
          if exec_ok {
            Ok(())
          } else {
            Err("sqlite 更新失败: \{task.get_id()}")
          }
        }
      }
    }
  }
}

///|
pub fn SqliteStore::update_task_if_status(
  self : SqliteStore,
  task : @core.Task,
  expected_status : String,
) -> Result[Unit, String] {
  match self.db {
    None => Err("sqlite store 未打开")
    Some(db) => {
      let sql = "UPDATE tasks SET parent_id = ?, project_dir = ?, ns = ?, priority = ?, importance = ?, depth = ?, split_n = ?, status = ?, assignee = ?, description = ?, deliverable = ?, created_at = ?, updated_at = ?, completed_by = ?, cleanup_mode = ?, depends_on = ?, omega_required = ? WHERE id = ? AND status = ?"
      match db.prepare(sql) {
        None => Err("sqlite prepare 失败: update_task_if_status")
        Some(stmt) => {
          SqliteStore::bind_task_update_values(stmt, task)
          ignore(
            stmt.bind(
              18,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, task.get_id())),
            ),
          )
          ignore(
            stmt.bind(
              19,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, expected_status)),
            ),
          )
          let exec_ok = stmt.execute()
          stmt.finalize()
          if exec_ok {
            Ok(())
          } else {
            Err(
              "状态不匹配或任务不存在: \{task.get_id()} (期望 [" +
              expected_status +
              "])",
            )
          }
        }
      }
    }
  }
}

///|
impl Store for SqliteStore with fn list_tasks(self) {
  let out : Array[@core.Task] = []
  match self.db {
    None => out
    Some(db) => {
      let sql = "SELECT \{SqliteStore::task_columns()} FROM tasks"
      match db.prepare(sql) {
        None => out
        Some(stmt) => {
          while stmt.step() {
            out.push(row_to_task(stmt))
          }
          stmt.finalize()
          out
        }
      }
    }
  }
}

///|
/// 列出指定命名空间的任务。
/// BUG-85：空 ns 的回退口径与内存后端对齐（`list_tasks_in("")` = 默认命名空间），
/// 否则同一个入参在两个后端上一个是 default 行、一个是零行。
pub fn SqliteStore::list_tasks_in(
  self : SqliteStore,
  ns_filter : String,
) -> Array[@core.Task] {
  let target = if ns_filter == "" { "default" } else { ns_filter }
  let out : Array[@core.Task] = []
  match self.db {
    None => out
    Some(db) => {
      let sql = "SELECT \{SqliteStore::task_columns()} FROM tasks WHERE ns = ?"
      match db.prepare(sql) {
        None => out
        Some(stmt) => {
          ignore(
            stmt.bind(1, @sqlite.SqlValue::Text(@encoding.encode(UTF8, target))),
          )
          while stmt.step() {
            out.push(row_to_task(stmt))
          }
          stmt.finalize()
          out
        }
      }
    }
  }
}

// =====================================================================
// DGM 档案库（evolve_artifacts 表）持久化
// 详见 src/evolve/ —— evolve 包调用这些方法做 SQLite 落库。
// =====================================================================

///|
/// 插入一个 DGM 产物（evolve_artifacts 表）。失败返回 Err。
pub fn SqliteStore::evolve_upsert(
  self : SqliteStore,
  id~ : String,
  parent_id~ : String,
  goal~ : String,
  note~ : String,
  code~ : String,
  score~ : Double,
  parts_json~ : String,
  created_at~ : String,
) -> Result[Unit, String] {
  match self.db {
    None => Err("sqlite store 未打开")
    Some(db) => {
      let sql = "INSERT INTO evolve_artifacts (id, parent_id, goal, note, code, score, parts_json, children, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?) ON CONFLICT(id) DO UPDATE SET goal=excluded.goal, note=excluded.note, code=excluded.code, score=excluded.score, parts_json=excluded.parts_json, created_at=excluded.created_at"
      match db.prepare(sql) {
        None => Err("sqlite prepare 失败: evolve_upsert")
        Some(stmt) => {
          ignore(
            stmt.bind(1, @sqlite.SqlValue::Text(@encoding.encode(UTF8, id))),
          )
          ignore(
            stmt.bind(
              2,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, parent_id)),
            ),
          )
          ignore(
            stmt.bind(3, @sqlite.SqlValue::Text(@encoding.encode(UTF8, goal))),
          )
          ignore(
            stmt.bind(4, @sqlite.SqlValue::Text(@encoding.encode(UTF8, note))),
          )
          ignore(
            stmt.bind(5, @sqlite.SqlValue::Text(@encoding.encode(UTF8, code))),
          )
          ignore(
            stmt.bind(
              6,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, score.to_string())),
            ),
          )
          ignore(
            stmt.bind(
              7,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, parts_json)),
            ),
          )
          ignore(
            stmt.bind(
              8,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, created_at)),
            ),
          )
          let ok = stmt.execute()
          stmt.finalize()
          if ok {
            Ok(())
          } else {
            Err("evolve_upsert 写入失败: \{id}")
          }
        }
      }
    }
  }
}

///|
/// 读取全部 DGM 产物（evolve_artifacts 表），按 created_at 升序。
/// 返回 JSON 数组（供 MCP/展示）。
pub fn SqliteStore::evolve_list(self : SqliteStore) -> Array[Json] {
  let out : Array[Json] = []
  match self.db {
    None => out
    Some(db) => {
      let sql = "SELECT id, parent_id, goal, note, code, score, parts_json, children, created_at FROM evolve_artifacts ORDER BY created_at ASC"
      match db.prepare(sql) {
        None => out
        Some(stmt) => {
          while stmt.step() {
            let m : Map[String, Json] = Map([])
            m.set("id", Json::string(evolve_col_text(stmt, 0)))
            m.set("parent_id", Json::string(evolve_col_text(stmt, 1)))
            m.set("goal", Json::string(evolve_col_text(stmt, 2)))
            m.set("note", Json::string(evolve_col_text(stmt, 3)))
            m.set("code", Json::string(evolve_col_text(stmt, 4)))
            let score_raw = evolve_col_text(stmt, 5)
            m.set("score", Json::number(evolve_parse_double(score_raw)))
            let parts_raw = evolve_col_text(stmt, 6)
            m.set(
              "parts",
              @json.parse(parts_raw) catch {
                _ => Json::object(Map([]))
              },
            )
            m.set("children", Json::number(evolve_col_int(stmt, 7).to_double()))
            m.set("created_at", Json::string(evolve_col_text(stmt, 8)))
            out.push(Json::object(m))
          }
          stmt.finalize()
          out
        }
      }
    }
  }
}

///|
/// 递增某产物的 children 计数（每次新增子代 +1）。返回是否成功。
pub fn SqliteStore::evolve_bump_child(self : SqliteStore, id : String) -> Bool {
  match self.db {
    None => false
    Some(db) => {
      let sql = "UPDATE evolve_artifacts SET children = children + 1 WHERE id = ?"
      match db.prepare(sql) {
        None => false
        Some(stmt) => {
          ignore(
            stmt.bind(1, @sqlite.SqlValue::Text(@encoding.encode(UTF8, id))),
          )
          let ok = stmt.execute()
          stmt.finalize()
          ok
        }
      }
    }
  }
}

///|
/// 取 evolve_artifacts 某列文本（列索引从 0 起）。
fn evolve_col_text(stmt : @sqlite.Statement, i : Int32) -> String {
  str_from_bytes(stmt.column_text(i))
}

///|
/// 解析 evolve_artifacts 的 score 文本为 Double（复用同包 executions 的解析器）。
fn evolve_parse_double(raw : String) -> Double {
  parse_simple_double(raw)
}

///|
/// 取 evolve_artifacts 某列 int。
fn evolve_col_int(stmt : @sqlite.Statement, i : Int32) -> Int32 {
  stmt.column_int(i)
}

///|
impl Store for SqliteStore with fn delete_task(self, id) {
  match self.db {
    None => Err("sqlite store 未打开")
    Some(db) => {
      if self.get_task(id) is None {
        return Err("task not found: \{id}")
      }
      let sql = "DELETE FROM tasks WHERE id = ?"
      match db.prepare(sql) {
        None => Err("sqlite prepare 失败: delete_task")
        Some(stmt) => {
          ignore(
            stmt.bind(1, @sqlite.SqlValue::Text(@encoding.encode(UTF8, id))),
          )
          let exec_ok = stmt.execute()
          stmt.finalize()
          if exec_ok {
            Ok(())
          } else {
            Err("sqlite 删除失败: \{id}")
          }
        }
      }
    }
  }
}

///|
impl Store for SqliteStore with fn clear(self) {
  match self.db {
    None => ()
    Some(db) => {
      ignore(
        db.exec(
          "CREATE TABLE IF NOT EXISTS tasks (id TEXT PRIMARY KEY, parent_id TEXT NOT NULL DEFAULT '', project_dir TEXT NOT NULL DEFAULT '', ns TEXT NOT NULL DEFAULT 'default', priority INTEGER NOT NULL DEFAULT 0, importance INTEGER NOT NULL DEFAULT 0, depth INTEGER NOT NULL DEFAULT 0, split_n INTEGER NOT NULL DEFAULT 1, status TEXT NOT NULL DEFAULT 'Creating', assignee TEXT NOT NULL DEFAULT '', description TEXT NOT NULL DEFAULT '', deliverable TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL DEFAULT '', updated_at TEXT NOT NULL DEFAULT '', completed_by TEXT NOT NULL DEFAULT '', cleanup_mode TEXT NOT NULL DEFAULT '', depends_on TEXT NOT NULL DEFAULT '[]')",
        ),
      )
      ignore(
        db.exec(
          "CREATE TABLE IF NOT EXISTS archive (id TEXT PRIMARY KEY, task_json TEXT NOT NULL DEFAULT '', archived_at TEXT NOT NULL DEFAULT '')",
        ),
      )
      ignore(
        db.exec(
          "CREATE TABLE IF NOT EXISTS call_log (id INTEGER PRIMARY KEY AUTOINCREMENT, seq INTEGER, ts TEXT, tool TEXT, caller TEXT, ns TEXT, params_json TEXT, result_json TEXT, ok INTEGER, runtime_ms INTEGER)",
        ),
      )
      ignore(self.ensure_specs_table())
      ignore(
        db.exec(
          "CREATE TABLE IF NOT EXISTS reservations (scope TEXT PRIMARY KEY, agent TEXT NOT NULL DEFAULT '', ttl_until TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL DEFAULT '')",
        ),
      )
      ignore(
        db.exec(
          "CREATE TABLE IF NOT EXISTS executors (name TEXT PRIMARY KEY, abilities_json TEXT NOT NULL DEFAULT '[]', created_at TEXT NOT NULL DEFAULT '')",
        ),
      )
      ignore(
        db.exec(
          "CREATE TABLE IF NOT EXISTS heartbeat_history (id INTEGER PRIMARY KEY AUTOINCREMENT, task_id TEXT NOT NULL DEFAULT '', interval_sec INTEGER NOT NULL DEFAULT 0, ts TEXT NOT NULL DEFAULT '')",
        ),
      )
      ignore(
        db.exec(
          "CREATE TABLE IF NOT EXISTS saga_log (id INTEGER PRIMARY KEY AUTOINCREMENT, ns TEXT NOT NULL DEFAULT 'default', root_task_id TEXT NOT NULL DEFAULT '', step TEXT NOT NULL DEFAULT '', task_id TEXT NOT NULL DEFAULT '', compensation TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'pending', created_at TEXT NOT NULL DEFAULT '', UNIQUE(ns, root_task_id, step))",
        ),
      )
      ignore(
        db.exec(
          "CREATE TABLE IF NOT EXISTS circuit_breakers (ns TEXT NOT NULL DEFAULT 'default', circuit TEXT NOT NULL DEFAULT '', state TEXT NOT NULL DEFAULT 'closed', failures INTEGER NOT NULL DEFAULT 0, window_secs INTEGER NOT NULL DEFAULT 60, threshold INTEGER NOT NULL DEFAULT 3, recovery_secs INTEGER NOT NULL DEFAULT 30, opened_at INTEGER NOT NULL DEFAULT 0, last_fail_ts INTEGER NOT NULL DEFAULT 0, updated_at TEXT NOT NULL DEFAULT '', PRIMARY KEY (ns, circuit))",
        ),
      )
      ignore(
        db.exec(
          "CREATE TABLE IF NOT EXISTS assistant_reg (agent TEXT PRIMARY KEY, mode TEXT NOT NULL DEFAULT 'all', is_primary INTEGER NOT NULL DEFAULT 0, registered_at TEXT NOT NULL DEFAULT '', heartbeat_at TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'active')",
        ),
      )
      ignore(
        db.exec(
          "CREATE TABLE IF NOT EXISTS file_locks (scope TEXT PRIMARY KEY, lock_id TEXT NOT NULL DEFAULT '', batch_id TEXT NOT NULL DEFAULT '', agent TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'active', ts TEXT NOT NULL DEFAULT '', ttl_until TEXT NOT NULL DEFAULT '', meta TEXT NOT NULL DEFAULT '')",
        ),
      )
      ignore(
        db.exec(
          "CREATE TABLE IF NOT EXISTS lock_violations (id INTEGER PRIMARY KEY AUTOINCREMENT, ts TEXT NOT NULL DEFAULT '', agent TEXT NOT NULL DEFAULT '', scope TEXT NOT NULL DEFAULT '', reason TEXT NOT NULL DEFAULT '', lock_id TEXT NOT NULL DEFAULT '')",
        ),
      )
      ignore(
        db.exec(
          "CREATE TABLE IF NOT EXISTS agents (agent_id TEXT PRIMARY KEY, agent_type TEXT NOT NULL DEFAULT 'unknown', role TEXT NOT NULL DEFAULT 'Executor', soldier TEXT NOT NULL DEFAULT '工兵', pid INTEGER NOT NULL DEFAULT 0, pubkey_fp TEXT NOT NULL DEFAULT '', first_seen TEXT NOT NULL DEFAULT '', last_seen TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'active')",
        ),
      )
      ignore(
        db.exec(
          "CREATE TABLE IF NOT EXISTS agent_acl (agent_id TEXT NOT NULL, ns TEXT NOT NULL, can_read INTEGER NOT NULL DEFAULT 1, can_write INTEGER NOT NULL DEFAULT 0, pid_bound INTEGER NOT NULL DEFAULT 0, revoked_at TEXT NOT NULL DEFAULT '', revoked_by TEXT NOT NULL DEFAULT '', PRIMARY KEY (agent_id, ns))",
        ),
      )
      ignore(db.exec("DELETE FROM tasks"))
      ignore(db.exec("DELETE FROM archive"))
      ignore(db.exec("DELETE FROM call_log"))
      ignore(db.exec("DELETE FROM specs"))
      ignore(db.exec("DELETE FROM reservations"))
      ignore(db.exec("DELETE FROM executors"))
      ignore(db.exec("DELETE FROM heartbeat_history"))
      ignore(db.exec("DELETE FROM saga_log"))
      ignore(db.exec("DELETE FROM circuit_breakers"))
      ignore(db.exec("DELETE FROM assistant_reg"))
      ignore(db.exec("DELETE FROM file_locks"))
      ignore(db.exec("DELETE FROM lock_violations"))
    }
  }
}

///|
/// SQLite 后端：写入/覆盖某作用域预订（ON CONFLICT DO UPDATE）。
pub fn SqliteStore::rsv_set(
  self : SqliteStore,
  scope~ : String,
  agent~ : String,
  ttl_until~ : String,
  created_at~ : String,
) -> Result[String, String] {
  match self.db {
    None => Err("sqlite store 未打开")
    Some(db) => {
      let sql = "INSERT INTO reservations (scope, agent, ttl_until, created_at) VALUES (?, ?, ?, ?) ON CONFLICT(scope) DO UPDATE SET agent=excluded.agent, ttl_until=excluded.ttl_until, created_at=excluded.created_at"
      match db.prepare(sql) {
        None => Err("rsv_set prepare failed")
        Some(stmt) => {
          ignore(
            stmt.bind(1, @sqlite.SqlValue::Text(@encoding.encode(UTF8, scope))),
          )
          ignore(
            stmt.bind(2, @sqlite.SqlValue::Text(@encoding.encode(UTF8, agent))),
          )
          ignore(
            stmt.bind(
              3,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, ttl_until)),
            ),
          )
          ignore(
            stmt.bind(
              4,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, created_at)),
            ),
          )
          let ok = stmt.execute()
          stmt.finalize()
          if ok {
            Ok("reserved")
          } else {
            Err("rsv_set execute failed")
          }
        }
      }
    }
  }
}

///|
/// SQLite 后端：按裁决写预订——**抢不到就是 0 行，不是异常**（BUG-136）。
/// 与旧 `rsv_set`（无条件 `ON CONFLICT DO UPDATE SET`）的区别在 `WHERE`：
/// 只有「本来就是我的」或「现持有者的 TTL 已过期」才覆盖，二者都由**数据库**判，
/// 不由调用方写前那次读判（`excluded.created_at` 就是本次请求的服务端盖章时刻）。
/// 纯 `INSERT` 不带 conflict 子句这条路不能用：约束冲突会撞上面那个抛异常形态，
/// 把一次正常冲突变成 server 崩溃。结论一律取**写后回读**，与内存后端同构。
pub fn SqliteStore::rsv_try_set(
  self : SqliteStore,
  scope~ : String,
  agent~ : String,
  ttl_until~ : String,
  created_at~ : String,
) -> Result[RsvOutcome, String] {
  let prev = self.rsv_get(scope)
  // 标签取自写前快照，只用于**播报动作名**；结论一律由下面那条语句 + 写后回读定。
  // 刻意不留「写前已见活体持有者就不发这笔写」的短路：那等于把裁决权交回调用侧那次旧读
  // （缺陷本体），而且 SQL 的 WHERE 永远不会被执行——实测摘掉 WHERE 后单测仍全绿，就是这条短路把判据架空了。
  let (_, action) = rsv_action(prev, agent, created_at)
  let prev_agent = match prev {
    Some((o, _, _)) if action == "taken_over" => o
    _ => ""
  }
  let sql = "INSERT INTO reservations (scope, agent, ttl_until, created_at) VALUES (?, ?, ?, ?) ON CONFLICT(scope) DO UPDATE SET agent=excluded.agent, ttl_until=excluded.ttl_until, created_at=excluded.created_at WHERE reservations.agent = excluded.agent OR reservations.ttl_until < excluded.created_at"
  match self.db {
    None => Err("sqlite store 未打开")
    Some(db) =>
      match db.prepare(sql) {
        None => Err("rsv_try_set prepare failed")
        Some(stmt) => {
          ignore(
            stmt.bind(1, @sqlite.SqlValue::Text(@encoding.encode(UTF8, scope))),
          )
          ignore(
            stmt.bind(2, @sqlite.SqlValue::Text(@encoding.encode(UTF8, agent))),
          )
          ignore(
            stmt.bind(
              3,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, ttl_until)),
            ),
          )
          ignore(
            stmt.bind(
              4,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, created_at)),
            ),
          )
          ignore(stmt.execute())
          stmt.finalize()
          Ok(self.rsv_outcome_after_write(scope, action, prev_agent, agent~))
        }
      }
  }
}

///|
/// 写后回读收口：库里现在是谁，回执就是谁（结论不许由请求反推）。
/// `None`（表读空）只可能来自库不可用/坏针，此时如实报 conflict 且 held_by 为空串——
/// 工具面把它报出去，比伪造一次 reserved 诚实。
fn SqliteStore::rsv_outcome_after_write(
  self : SqliteStore,
  scope : String,
  action : String,
  prev_agent : String,
  agent~ : String,
) -> RsvOutcome {
  match self.rsv_get(scope) {
    Some((owner, ttl, _)) if owner == agent =>
      RsvOutcome::{ reserved: true, action, prev_agent, agent, ttl_until: ttl, }
    Some((owner, ttl, _)) =>
      RsvOutcome::{
        reserved: false,
        action: "conflict",
        prev_agent: "",
        agent: owner,
        ttl_until: ttl,
      }
    None =>
      RsvOutcome::{
        reserved: false,
        action: "conflict",
        prev_agent: "",
        agent: "",
        ttl_until: "",
      }
  }
}

///|
/// SQLite 后端：查询某作用域预订。
pub fn SqliteStore::rsv_get(
  self : SqliteStore,
  scope : String,
) -> (String, String, String)? {
  match self.db {
    None => None
    Some(db) => {
      let sql = "SELECT agent, ttl_until, created_at FROM reservations WHERE scope = ?"
      match db.prepare(sql) {
        None => None
        Some(stmt) => {
          ignore(
            stmt.bind(1, @sqlite.SqlValue::Text(@encoding.encode(UTF8, scope))),
          )
          let r : (String, String, String)? = if stmt.step() {
            Some(
              (
                str_from_bytes(stmt.column_text(0)),
                str_from_bytes(stmt.column_text(1)),
                str_from_bytes(stmt.column_text(2)),
              ),
            )
          } else {
            None
          }
          stmt.finalize()
          r
        }
      }
    }
  }
}

///|
/// SQLite 后端：释放预订（仅持有者）。
/// BUG-79：`Statement::execute -> Bool` 只表示「语句没报错」——绑定层（mizchi/sqlite 的
/// js 与 native 两版签名都是 execute -> Bool）根本不给 changes()，删 0 行同样返回 true。
/// 于是非持有者调 reserve_release 会被告知「已释放」而预订仍在，两个 agent 同改一份作用域，
/// 正是这个原语要防的多 agent 撞车；内存后端校持有者，所以它的单测永远绿、抓不到。
/// 修法：删前先按 scope 读回持有者比对，不匹配即 false（与内存后端同语义）。
pub fn SqliteStore::rsv_release(
  self : SqliteStore,
  scope : String,
  agent : String,
) -> Bool {
  match self.db {
    None => false
    Some(db) =>
      match self.rsv_get(scope) {
        Some((owner, _, _)) if owner == agent => {
          let sql = "DELETE FROM reservations WHERE scope = ? AND agent = ?"
          match db.prepare(sql) {
            None => false
            Some(stmt) => {
              ignore(
                stmt.bind(
                  1,
                  @sqlite.SqlValue::Text(@encoding.encode(UTF8, scope)),
                ),
              )
              ignore(
                stmt.bind(
                  2,
                  @sqlite.SqlValue::Text(@encoding.encode(UTF8, agent)),
                ),
              )
              let ok = stmt.execute()
              stmt.finalize()
              ok
            }
          }
        }
        _ => false
      }
  }
}

///|
/// SQLite 后端：列出全部预订。
pub fn SqliteStore::rsv_list(
  self : SqliteStore,
) -> Array[(String, String, String)] {
  let out : Array[(String, String, String)] = []
  match self.db {
    None => out
    Some(db) => {
      let sql = "SELECT agent, ttl_until, created_at FROM reservations ORDER BY created_at"
      match db.prepare(sql) {
        None => out
        Some(stmt) => {
          while stmt.step() {
            out.push(
              (
                str_from_bytes(stmt.column_text(0)),
                str_from_bytes(stmt.column_text(1)),
                str_from_bytes(stmt.column_text(2)),
              ),
            )
          }
          stmt.finalize()
          out
        }
      }
    }
  }
}

///|
/// 提升声明：允许通过具体类型直接调用 trait 方法。
pub extend SqliteStore with Store::{
  create_task,
  get_task,
  update_task,
  list_tasks,
  delete_task,
  clear,
}

// —— executors 表（执行者能力注册，Marketplace 雏形的跨进程持久化，R31）——

///|
/// SQLite 后端：写入/覆盖一个执行者的能力注册。（幂等：同 name 覆盖）
pub fn SqliteStore::executor_save(
  self : SqliteStore,
  name~ : String,
  abilities_json~ : String,
  created_at~ : String,
) -> Result[String, String] {
  match self.db {
    None => Err("db not available")
    Some(db) => {
      let sql = "INSERT INTO executors (name, abilities_json, created_at) VALUES (?, ?, ?) ON CONFLICT(name) DO UPDATE SET abilities_json=excluded.abilities_json, created_at=excluded.created_at"
      match db.prepare(sql) {
        None => Err("executor_save prepare failed")
        Some(stmt) => {
          ignore(
            stmt.bind(1, @sqlite.SqlValue::Text(@encoding.encode(UTF8, name))),
          )
          ignore(
            stmt.bind(
              2,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, abilities_json)),
            ),
          )
          ignore(
            stmt.bind(
              3,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, created_at)),
            ),
          )
          let ok = stmt.execute()
          stmt.finalize()
          if ok {
            Ok("saved")
          } else {
            Err("executor_save execute failed")
          }
        }
      }
    }
  }
}

///|
/// SQLite 后端：列出全部执行者 (name, abilities_json, created_at)。
pub fn SqliteStore::executor_list(
  self : SqliteStore,
) -> Array[(String, String, String)] {
  let out : Array[(String, String, String)] = []
  match self.db {
    None => out
    Some(db) => {
      let sql = "SELECT name, abilities_json, created_at FROM executors ORDER BY name"
      match db.prepare(sql) {
        None => out
        Some(stmt) => {
          while stmt.step() {
            out.push(
              (
                str_from_bytes(stmt.column_text(0)),
                str_from_bytes(stmt.column_text(1)),
                str_from_bytes(stmt.column_text(2)),
              ),
            )
          }
          stmt.finalize()
          out
        }
      }
    }
  }
}

///|
/// SQLite 后端：清空全部执行者能力注册（Marketplace 重置/整洁）。
pub fn SqliteStore::executor_clear(self : SqliteStore) -> Bool {
  match self.db {
    None => ()
    Some(db) => ignore(db.exec("DELETE FROM executors"))
  }
  true
}

// —— 分布式文件锁（SQLite 后端）——

///|
/// SQLite 后端：upsert 一把锁（按 scope 主键；旧锁 active 且非本人且未过期 → 记违例）。
pub fn SqliteStore::locks_upsert(self : SqliteStore, lock : FileLock) -> Unit {
  match self.db {
    None => ()
    Some(db) => {
      ignore(db.exec("BEGIN IMMEDIATE"))
      let v_sql = "INSERT INTO lock_violations (ts, agent, scope, reason, lock_id) SELECT ?, ?, ?, 'lock_taken_over', ? FROM file_locks WHERE scope = ? AND status = 'active' AND agent != ? AND ttl_until >= ?"
      match db.prepare(v_sql) {
        None => ()
        Some(stmt) => {
          ignore(
            stmt.bind(
              1,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, lock.ts)),
            ),
          )
          ignore(
            stmt.bind(
              2,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, lock.agent)),
            ),
          )
          ignore(
            stmt.bind(
              3,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, lock.scope)),
            ),
          )
          ignore(
            stmt.bind(
              4,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, lock.lock_id)),
            ),
          )
          ignore(
            stmt.bind(
              5,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, lock.scope)),
            ),
          )
          ignore(
            stmt.bind(
              6,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, lock.agent)),
            ),
          )
          ignore(
            stmt.bind(
              7,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, lock.ts)),
            ),
          )
          ignore(stmt.execute())
          stmt.finalize()
        }
      }
      let sql = "INSERT INTO file_locks (scope, lock_id, batch_id, agent, status, ts, ttl_until, meta) VALUES (?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(scope) DO UPDATE SET lock_id=excluded.lock_id, batch_id=excluded.batch_id, agent=excluded.agent, status=excluded.status, ts=excluded.ts, ttl_until=excluded.ttl_until, meta=excluded.meta WHERE file_locks.status != 'active' OR file_locks.agent = excluded.agent OR file_locks.ttl_until < excluded.ts"
      match db.prepare(sql) {
        None => ()
        Some(stmt) => {
          ignore(
            stmt.bind(
              1,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, lock.scope)),
            ),
          )
          ignore(
            stmt.bind(
              2,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, lock.lock_id)),
            ),
          )
          ignore(
            stmt.bind(
              3,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, lock.batch_id)),
            ),
          )
          ignore(
            stmt.bind(
              4,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, lock.agent)),
            ),
          )
          ignore(
            stmt.bind(
              5,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, lock.status)),
            ),
          )
          ignore(
            stmt.bind(
              6,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, lock.ts)),
            ),
          )
          ignore(
            stmt.bind(
              7,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, lock.ttl_until)),
            ),
          )
          ignore(
            stmt.bind(
              8,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, lock.meta)),
            ),
          )
          ignore(stmt.execute())
          stmt.finalize()
        }
      }
      ignore(db.exec("COMMIT"))
    }
  }
}

///|
/// SQLite 后端：落一条锁违例（`lock_violations` 的唯一写入形状，供本文件内复用）。
fn SqliteStore::lock_violation_insert(
  self : SqliteStore,
  ts : String,
  agent : String,
  scope : String,
  reason : String,
  lock_id : String,
) -> Unit {
  match self.db {
    None => ()
    Some(db) => {
      let sql = "INSERT INTO lock_violations (ts, agent, scope, reason, lock_id) VALUES (?, ?, ?, ?, ?)"
      match db.prepare(sql) {
        None => ()
        Some(stmt) => {
          ignore(
            stmt.bind(1, @sqlite.SqlValue::Text(@encoding.encode(UTF8, ts))),
          )
          ignore(
            stmt.bind(2, @sqlite.SqlValue::Text(@encoding.encode(UTF8, agent))),
          )
          ignore(
            stmt.bind(3, @sqlite.SqlValue::Text(@encoding.encode(UTF8, scope))),
          )
          ignore(
            stmt.bind(4, @sqlite.SqlValue::Text(@encoding.encode(UTF8, reason))),
          )
          ignore(
            stmt.bind(
              5,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, lock_id)),
            ),
          )
          ignore(stmt.execute())
          stmt.finalize()
        }
      }
    }
  }
}

///|
/// SQLite 后端：按裁决抢锁（BUG-145）——**抢不到就是 0 行，不是覆盖**（BUG-136 同形）。
/// 与 `rsv_try_set` 同一形状，三处要点逐字对齐：
///   1. 互斥由**数据库**在 `ON CONFLICT ... WHERE` 里判，不由调用方写前那次读判
///      （「先读后写」的竞态窗口正是缺陷本体：两进程都读到空闲、都以为拿到了锁）；
///   2. 刻意**不留**「写前已见活体持有者就不发这笔写」的短路——那等于把裁决权交回
///      调用侧那次旧读，而且 SQL 的 WHERE 永远不会被执行（照 BUG-136 的同族教训）；
///   3. 结论一律取**写后回读**：库里现在是谁，回执就是谁。
/// `WHERE` 编码的是 `lock_acquire_action`→`rsv_action` 同一条规则：
///   `agent = excluded.agent`（同持有者续，排在过期之前）
///   `OR status <> 'active'`（复用一条已释放/已扫出的行——预订表没有这一维，锁表有）
///   `OR ttl_until < excluded.ts`（旧主 TTL 已过，可让渡）
pub fn SqliteStore::locks_try_acquire(
  self : SqliteStore,
  lock : FileLock,
) -> LockAcquireOutcome {
  let prev = self.locks_get(lock.scope)
  // 标签取自写前快照，只用于**播报动作名**；结论一律由下面那条语句 + 写后回读定。
  let (may_write, action) = lock_acquire_action(prev, lock.agent, lock.ts)
  let prev_agent = match prev {
    Some(o) if action == "taken_over" => o.agent
    _ => ""
  }
  let sql = "INSERT INTO file_locks (scope, lock_id, batch_id, agent, status, ts, ttl_until, meta) VALUES (?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(scope) DO UPDATE SET lock_id=excluded.lock_id, batch_id=excluded.batch_id, agent=excluded.agent, status=excluded.status, ts=excluded.ts, ttl_until=excluded.ttl_until, meta=excluded.meta WHERE file_locks.agent = excluded.agent OR file_locks.status <> 'active' OR file_locks.ttl_until < excluded.ts"
  ignore(may_write) // 与 rsv_try_set 同一纪律：本地裁决不决定发不发这笔写，只决定动作名
  match self.db {
    None =>
      LockAcquireOutcome::{
        granted: false,
        action: "conflict",
        prev_agent: "",
        agent: "",
        ttl_until: "",
        violation_logged: false,
      }
    Some(db) =>
      match db.prepare(sql) {
        None =>
          // prepare 失败＝尺子那头的库不可用，如实报未授予，绝不冒认一次 granted
          LockAcquireOutcome::{
            granted: false,
            action: "conflict",
            prev_agent: "",
            agent: "",
            ttl_until: "",
            violation_logged: false,
          }
        Some(stmt) => {
          ignore(
            stmt.bind(
              1,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, lock.scope)),
            ),
          )
          ignore(
            stmt.bind(
              2,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, lock.lock_id)),
            ),
          )
          ignore(
            stmt.bind(
              3,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, lock.batch_id)),
            ),
          )
          ignore(
            stmt.bind(
              4,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, lock.agent)),
            ),
          )
          ignore(
            stmt.bind(
              5,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, lock.status)),
            ),
          )
          ignore(
            stmt.bind(
              6,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, lock.ts)),
            ),
          )
          ignore(
            stmt.bind(
              7,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, lock.ttl_until)),
            ),
          )
          ignore(
            stmt.bind(
              8,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, lock.meta)),
            ),
          )
          ignore(stmt.execute())
          stmt.finalize()
          self.lock_outcome_after_write(lock.scope, action, prev_agent, lock~)
        }
      }
  }
}

///|
/// 写后回读收口（与 `rsv_outcome_after_write` 同一条纪律：结论不许由请求反推）。
/// 库里现在是自己 → granted + 播报写前算出的动作名；是别人 → conflict 并落一条
/// `lock_denied` 违例（拒夺审计），锁行没被改动，现持有者原样保住。
fn SqliteStore::lock_outcome_after_write(
  self : SqliteStore,
  scope : String,
  action : String,
  prev_agent : String,
  lock~ : FileLock,
) -> LockAcquireOutcome {
  match self.locks_get(scope) {
    Some(l) if l.agent == lock.agent =>
      LockAcquireOutcome::{
        granted: true,
        action,
        prev_agent,
        agent: lock.agent,
        ttl_until: l.ttl_until,
        violation_logged: false,
      }
    Some(l) => {
      self.lock_violation_insert(
        lock.ts,
        lock.agent,
        scope,
        "lock_denied",
        lock.lock_id,
      )
      LockAcquireOutcome::{
        granted: false,
        action: "conflict",
        prev_agent: "",
        agent: l.agent,
        ttl_until: l.ttl_until,
        violation_logged: true,
      }
    }
    None =>
      // 表读空只可能来自库不可用/坏针——如实报未授予，比伪造一次 granted 诚实
      LockAcquireOutcome::{
        granted: false,
        action: "conflict",
        prev_agent: "",
        agent: "",
        ttl_until: "",
        violation_logged: false,
      }
  }
}

///|
/// SQLite 后端：查询某 scope 的锁（不存在返回 None）。
pub fn SqliteStore::locks_get(self : SqliteStore, scope : String) -> FileLock? {
  match self.db {
    None => None
    Some(db) => {
      let sql = "SELECT lock_id, batch_id, scope, agent, status, ts, ttl_until, meta FROM file_locks WHERE scope = ?"
      match db.prepare(sql) {
        None => None
        Some(stmt) => {
          ignore(
            stmt.bind(1, @sqlite.SqlValue::Text(@encoding.encode(UTF8, scope))),
          )
          let r : FileLock? = if stmt.step() {
            Some(FileLock::{
              lock_id: str_from_bytes(stmt.column_text(0)),
              batch_id: str_from_bytes(stmt.column_text(1)),
              scope: str_from_bytes(stmt.column_text(2)),
              agent: str_from_bytes(stmt.column_text(3)),
              status: str_from_bytes(stmt.column_text(4)),
              ts: str_from_bytes(stmt.column_text(5)),
              ttl_until: str_from_bytes(stmt.column_text(6)),
              meta: str_from_bytes(stmt.column_text(7)),
            })
          } else {
            None
          }
          stmt.finalize()
          r
        }
      }
    }
  }
}

///|
/// SQLite 后端：列出全部锁。
pub fn SqliteStore::locks_list(self : SqliteStore) -> Array[FileLock] {
  let out : Array[FileLock] = []
  match self.db {
    None => out
    Some(db) => {
      let sql = "SELECT lock_id, batch_id, scope, agent, status, ts, ttl_until, meta FROM file_locks ORDER BY ts"
      match db.prepare(sql) {
        None => out
        Some(stmt) => {
          while stmt.step() {
            out.push(FileLock::{
              lock_id: str_from_bytes(stmt.column_text(0)),
              batch_id: str_from_bytes(stmt.column_text(1)),
              scope: str_from_bytes(stmt.column_text(2)),
              agent: str_from_bytes(stmt.column_text(3)),
              status: str_from_bytes(stmt.column_text(4)),
              ts: str_from_bytes(stmt.column_text(5)),
              ttl_until: str_from_bytes(stmt.column_text(6)),
              meta: str_from_bytes(stmt.column_text(7)),
            })
          }
          stmt.finalize()
          out
        }
      }
    }
  }
}

///|
/// SQLite 后端：释放某 scope 的锁（仅持有者可释放）。
pub fn SqliteStore::locks_release(
  self : SqliteStore,
  scope : String,
  agent : String,
) -> Bool {
  match self.db {
    None => false
    Some(db) => {
      let sql = "UPDATE file_locks SET status='released' WHERE scope = ? AND agent = ?"
      match db.prepare(sql) {
        None => false
        Some(stmt) => {
          ignore(
            stmt.bind(1, @sqlite.SqlValue::Text(@encoding.encode(UTF8, scope))),
          )
          ignore(
            stmt.bind(2, @sqlite.SqlValue::Text(@encoding.encode(UTF8, agent))),
          )
          ignore(stmt.execute())
          stmt.finalize()
          // SQLite changes() via prepare is not directly exposed; use a follow-up check
          match self.locks_get(scope) {
            Some(l) if l.status == "released" && l.agent == agent => true
            _ => false
          }
        }
      }
    }
  }
}

///|
/// SQLite 后端：清理过期锁（active 且 ttl_until < now → expired + 记违例）。
pub fn SqliteStore::locks_sweep(self : SqliteStore, now : String) -> Int32 {
  match self.db {
    None => 0
    Some(db) => {
      ignore(db.exec("BEGIN IMMEDIATE"))
      let v_sql = "INSERT INTO lock_violations (ts, agent, scope, reason, lock_id) SELECT ?, agent, scope, 'lock_expired', lock_id FROM file_locks WHERE status = 'active' AND ttl_until < ?"
      match db.prepare(v_sql) {
        None => ()
        Some(stmt) => {
          ignore(
            stmt.bind(1, @sqlite.SqlValue::Text(@encoding.encode(UTF8, now))),
          )
          ignore(
            stmt.bind(2, @sqlite.SqlValue::Text(@encoding.encode(UTF8, now))),
          )
          ignore(stmt.execute())
          stmt.finalize()
        }
      }
      let upd_sql = "UPDATE file_locks SET status='expired' WHERE status = 'active' AND ttl_until < ?"
      match db.prepare(upd_sql) {
        None => ()
        Some(stmt) => {
          ignore(
            stmt.bind(1, @sqlite.SqlValue::Text(@encoding.encode(UTF8, now))),
          )
          ignore(stmt.execute())
          stmt.finalize()
        }
      }
      let count_sql = "SELECT changes()"
      let mut count = 0
      match db.prepare(count_sql) {
        None => ()
        Some(stmt) => {
          if stmt.step() {
            count = stmt.column_int(0)
          }
          stmt.finalize()
        }
      }
      ignore(db.exec("COMMIT"))
      count
    }
  }
}

///|
/// SQLite 后端：追加一条违例记录。
pub fn SqliteStore::lock_violations_push(
  self : SqliteStore,
  v : LockViolation,
) -> Unit {
  match self.db {
    None => ()
    Some(db) => {
      let sql = "INSERT INTO lock_violations (ts, agent, scope, reason, lock_id) VALUES (?, ?, ?, ?, ?)"
      match db.prepare(sql) {
        None => ()
        Some(stmt) => {
          ignore(
            stmt.bind(1, @sqlite.SqlValue::Text(@encoding.encode(UTF8, v.ts))),
          )
          ignore(
            stmt.bind(
              2,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, v.agent)),
            ),
          )
          ignore(
            stmt.bind(
              3,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, v.scope)),
            ),
          )
          ignore(
            stmt.bind(
              4,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, v.reason)),
            ),
          )
          ignore(
            stmt.bind(
              5,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, v.lock_id)),
            ),
          )
          ignore(stmt.execute())
          stmt.finalize()
        }
      }
    }
  }
}

///|
/// SQLite 后端：列出违例记录。
pub fn SqliteStore::lock_violations_list(
  self : SqliteStore,
) -> Array[LockViolation] {
  let out : Array[LockViolation] = []
  match self.db {
    None => out
    Some(db) => {
      let sql = "SELECT ts, agent, scope, reason, lock_id FROM lock_violations ORDER BY ts"
      match db.prepare(sql) {
        None => out
        Some(stmt) => {
          while stmt.step() {
            out.push(LockViolation::{
              ts: str_from_bytes(stmt.column_text(0)),
              agent: str_from_bytes(stmt.column_text(1)),
              scope: str_from_bytes(stmt.column_text(2)),
              reason: str_from_bytes(stmt.column_text(3)),
              lock_id: str_from_bytes(stmt.column_text(4)),
            })
          }
          stmt.finalize()
          out
        }
      }
    }
  }
}

// —— 项目助理登记（SQLite 后端，multi-agent-lock v3 阶段2 精简版）——

///|
/// SQLite 后端：写入/覆盖一个助理登记（幂等）。
pub fn SqliteStore::assistant_upsert(
  self : SqliteStore,
  reg : AssistantReg,
) -> Unit {
  match self.db {
    None => ()
    Some(db) => {
      ignore(db.exec("BEGIN IMMEDIATE"))
      // BUG-157 修复：单主不变量——如果当前 agent 抢主 (is_primary=1)，
      // 先把所有其他 agent 的 is_primary 清零，再 upsert 当前行。
      // SQLite 的 INSERT...ON CONFLICT(agent) 只表达"同一行幂等"，
      // 无法保证"全局只许一个 is_primary=1"，必须显式抢占。
      // 事务包裹保证 clear + insert 原子性，防止并发抢主时双写 is_primary=1。
      if reg.is_primary {
        let clear_sql = "UPDATE assistant_reg SET is_primary=0 WHERE is_primary=1 AND agent != ?"
        match db.prepare(clear_sql) {
          None => ()
          Some(clear_stmt) => {
            ignore(
              clear_stmt.bind(
                1,
                @sqlite.SqlValue::Text(@encoding.encode(UTF8, reg.agent)),
              ),
            )
            ignore(clear_stmt.execute())
            clear_stmt.finalize()
          }
        }
      }

      let sql = "INSERT INTO assistant_reg (agent, mode, is_primary, registered_at, heartbeat_at, status) VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(agent) DO UPDATE SET mode=excluded.mode, is_primary=excluded.is_primary, registered_at=excluded.registered_at, heartbeat_at=excluded.heartbeat_at, status=excluded.status"
      match db.prepare(sql) {
        None => ()
        Some(stmt) => {
          ignore(
            stmt.bind(
              1,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, reg.agent)),
            ),
          )
          ignore(
            stmt.bind(
              2,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, reg.mode)),
            ),
          )
          ignore(
            stmt.bind(
              3,
              @sqlite.SqlValue::Int(if reg.is_primary { 1 } else { 0 }),
            ),
          )
          ignore(
            stmt.bind(
              4,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, reg.registered_at)),
            ),
          )
          ignore(
            stmt.bind(
              5,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, reg.heartbeat_at)),
            ),
          )
          ignore(
            stmt.bind(
              6,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, reg.status)),
            ),
          )
          ignore(stmt.execute())
          stmt.finalize()
        }
      }
      ignore(db.exec("COMMIT"))
    }
  }
}

///|
/// SQLite 后端：查询某 agent 的助理登记（不存在返回 None）。
pub fn SqliteStore::assistant_get(
  self : SqliteStore,
  agent : String,
) -> AssistantReg? {
  match self.db {
    None => None
    Some(db) => {
      let sql = "SELECT agent, mode, is_primary, registered_at, heartbeat_at, status FROM assistant_reg WHERE agent = ?"
      match db.prepare(sql) {
        None => None
        Some(stmt) => {
          ignore(
            stmt.bind(1, @sqlite.SqlValue::Text(@encoding.encode(UTF8, agent))),
          )
          let out : AssistantReg? = if stmt.step() {
            self.assistant_from_row(stmt)
          } else {
            None
          }
          stmt.finalize()
          out
        }
      }
    }
  }
}

///|
/// SQLite 后端：列出全部助理登记。
pub fn SqliteStore::assistant_list(self : SqliteStore) -> Array[AssistantReg] {
  let out : Array[AssistantReg] = []
  match self.db {
    None => out
    Some(db) => {
      let sql = "SELECT agent, mode, is_primary, registered_at, heartbeat_at, status FROM assistant_reg ORDER BY registered_at"
      match db.prepare(sql) {
        None => out
        Some(stmt) => {
          while stmt.step() {
            match self.assistant_from_row(stmt) {
              Some(r) => out.push(r)
              None => ()
            }
          }
          stmt.finalize()
          out
        }
      }
    }
  }
}

///|
/// SQLite 后端：改某 agent 登记的 status（不存在返回 false）。
pub fn SqliteStore::assistant_set_status(
  self : SqliteStore,
  agent : String,
  status : String,
) -> Bool {
  match self.db {
    None => false
    Some(db) => {
      let sql = "UPDATE assistant_reg SET status = ? WHERE agent = ?"
      match db.prepare(sql) {
        None => false
        Some(stmt) => {
          ignore(
            stmt.bind(1, @sqlite.SqlValue::Text(@encoding.encode(UTF8, status))),
          )
          ignore(
            stmt.bind(2, @sqlite.SqlValue::Text(@encoding.encode(UTF8, agent))),
          )
          let changed = stmt.execute()
          stmt.finalize()
          let _ = changed
          match self.assistant_get(agent) {
            Some(r) => r.status == status
            None => false
          }
        }
      }
    }
  }
}

///|
/// 行 -> AssistantReg（列序与上面 SELECT 一致）。取值函数全为全函数，坏行只会读出空串，
/// 不会打死调用方；None 由调用方的 prepare/step 守卫产生。
fn SqliteStore::assistant_from_row(
  self : SqliteStore,
  stmt : @sqlite.Statement,
) -> AssistantReg? {
  let _ = self
  Some(AssistantReg::{
    agent: str_from_bytes(stmt.column_text(0)),
    mode: str_from_bytes(stmt.column_text(1)),
    is_primary: stmt.column_int(2) == 1,
    registered_at: str_from_bytes(stmt.column_text(3)),
    heartbeat_at: str_from_bytes(stmt.column_text(4)),
    status: str_from_bytes(stmt.column_text(5)),
  })
}

// —— executions 表（执行元数据，供成本统计使用）——

///|
/// 确保 executions 表存在（首次写入时调用）。
fn SqliteStore::ensure_executions_table(self : SqliteStore) -> Bool {
  match self.db {
    None => false
    Some(db) => db.exec(executions_table_sql())
  }
}

///|
/// 写入执行记录（供 execute 工具调用）。
pub fn SqliteStore::record_execution(
  self : SqliteStore,
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
  match self.db {
    None => Err("sqlite store 未打开")
    Some(db) => {
      if !self.ensure_executions_table() {
        return Err("无法创建 executions 表")
      }
      let rec = ExecutionRecord::{
        id: task_id + "_" + created_at,
        task_id,
        executor,
        model,
        tokens_in,
        tokens_out,
        cost,
        duration_ms,
        rate_limited,
        failure_reason,
        created_at,
      }
      match insert_execution(db, rec) {
        Ok(_) => Ok(())
        Err(e) => Err(e)
      }
    }
  }
}

// —— archive 快照（Phase 2/5 预置 API，不改变 Store trait）——

///|
/// 将已归档任务写入 archive 表快照。
pub fn SqliteStore::archive_task(
  self : SqliteStore,
  t : @core.Task,
  archived_at~ : String,
) -> Result[Unit, String] {
  match self.db {
    None => Err("sqlite store 未打开")
    Some(db) => {
      let sql = "INSERT OR REPLACE INTO archive (id, task_json, archived_at) VALUES (?, ?, ?)"
      match db.prepare(sql) {
        None => Err("sqlite prepare 失败: archive_task")
        Some(stmt) => {
          ignore(
            stmt.bind(
              1,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.get_id())),
            ),
          )
          ignore(
            stmt.bind(
              2,
              @sqlite.SqlValue::Text(
                @encoding.encode(UTF8, t.to_json().stringify()),
              ),
            ),
          )
          ignore(
            stmt.bind(
              3,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, archived_at)),
            ),
          )
          let exec_ok = stmt.execute()
          stmt.finalize()
          if exec_ok {
            Ok(())
          } else {
            Err("sqlite 归档写入失败: \{t.get_id()}")
          }
        }
      }
    }
  }
}

///|
/// 列出全部归档快照（id -> 原 task_json）。
pub fn SqliteStore::list_archived(
  self : SqliteStore,
) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  match self.db {
    None => out
    Some(db) =>
      match
        db.prepare("SELECT id, task_json FROM archive ORDER BY archived_at") {
        None => out
        Some(stmt) => {
          while stmt.step() {
            out.push(
              (
                str_from_bytes(stmt.column_text(0)),
                str_from_bytes(stmt.column_text(1)),
              ),
            )
          }
          stmt.finalize()
          out
        }
      }
  }
}

///|
/// 写入心跳记录（UPSERT：存在则更新 last_seen / status，不存在则插入）。
pub fn SqliteStore::write_heartbeat(
  self : SqliteStore,
  agent_id~ : String,
  task_id~ : String,
  last_seen~ : String,
  status~ : String,
) -> Result[Unit, String] {
  match self.db {
    None => Err("sqlite store 未打开")
    Some(db) => {
      let sql = "INSERT INTO heartbeats (agent_id, task_id, last_seen, status) VALUES (?, ?, ?, ?) ON CONFLICT(agent_id, task_id) DO UPDATE SET last_seen=excluded.last_seen, status=excluded.status"
      match db.prepare(sql) {
        None => Err("sqlite prepare 失败: write_heartbeat")
        Some(stmt) => {
          ignore(
            stmt.bind(
              1,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, agent_id)),
            ),
          )
          ignore(
            stmt.bind(
              2,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, task_id)),
            ),
          )
          ignore(
            stmt.bind(
              3,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, last_seen)),
            ),
          )
          ignore(
            stmt.bind(4, @sqlite.SqlValue::Text(@encoding.encode(UTF8, status))),
          )
          let exec_ok = stmt.execute()
          stmt.finalize()
          if exec_ok {
            Ok(())
          } else {
            Err("sqlite 写入心跳失败: \{agent_id}/\{task_id}")
          }
        }
      }
    }
  }
}

///|
/// 读取指定任务的心跳记录。
pub fn SqliteStore::read_heartbeat(
  self : SqliteStore,
  task_id : String,
) -> (String, String, String) {
  match self.db {
    None => ("", "", "")
    Some(db) => {
      let sql = "SELECT agent_id, last_seen, status FROM heartbeats WHERE task_id = ?"
      match db.prepare(sql) {
        None => ("", "", "")
        Some(stmt) => {
          ignore(
            stmt.bind(
              1,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, task_id)),
            ),
          )
          let result = if stmt.step() {
            let agent = str_from_bytes(stmt.column_text(0))
            let last = str_from_bytes(stmt.column_text(1))
            let status = str_from_bytes(stmt.column_text(2))
            (agent, last, status)
          } else {
            ("", "", "")
          }
          stmt.finalize()
          result
        }
      }
    }
  }
}

///|
/// 删除心跳记录。
pub fn SqliteStore::delete_heartbeat(
  self : SqliteStore,
  task_id : String,
) -> Result[Unit, String] {
  match self.db {
    None => Err("sqlite store 未打开")
    Some(db) => {
      let sql = "DELETE FROM heartbeats WHERE task_id = ?"
      match db.prepare(sql) {
        None => Err("sqlite prepare 失败: delete_heartbeat")
        Some(stmt) => {
          ignore(
            stmt.bind(
              1,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, task_id)),
            ),
          )
          let exec_ok = stmt.execute()
          stmt.finalize()
          if exec_ok {
            Ok(())
          } else {
            Err("sqlite 删除心跳失败: \{task_id}")
          }
        }
      }
    }
  }
}

///|
/// 列出全部心跳记录（供启动时加载）。
pub fn SqliteStore::list_all_heartbeats(
  self : SqliteStore,
) -> Array[(String, String, String, String)] {
  let out : Array[(String, String, String, String)] = []
  match self.db {
    None => out
    Some(db) => {
      let sql = "SELECT agent_id, task_id, last_seen, status FROM heartbeats"
      match db.prepare(sql) {
        None => out
        Some(stmt) => {
          while stmt.step() {
            out.push(
              (
                str_from_bytes(stmt.column_text(0)),
                str_from_bytes(stmt.column_text(1)),
                str_from_bytes(stmt.column_text(2)),
                str_from_bytes(stmt.column_text(3)),
              ),
            )
          }
          stmt.finalize()
          out
        }
      }
    }
  }
}

///|
/// 追加一条心跳间隔历史（R90，Phi Accrual 判活的数据源）；同一任务保留最近 1000 条。
pub fn SqliteStore::write_heartbeat_interval(
  self : SqliteStore,
  task_id~ : String,
  interval_sec~ : Int32,
  ts~ : String,
) -> Result[Unit, String] {
  match self.db {
    None => Err("sqlite store 未打开")
    Some(db) => {
      let sql = "INSERT INTO heartbeat_history (task_id, interval_sec, ts) VALUES (?, ?, ?)"
      match db.prepare(sql) {
        None => Err("sqlite prepare 失败: write_heartbeat_interval")
        Some(stmt) => {
          ignore(
            stmt.bind(
              1,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, task_id)),
            ),
          )
          ignore(stmt.bind(2, @sqlite.SqlValue::Int(interval_sec)))
          ignore(
            stmt.bind(3, @sqlite.SqlValue::Text(@encoding.encode(UTF8, ts))),
          )
          let exec_ok = stmt.execute()
          stmt.finalize()
          if exec_ok {
            // 裁剪：每任务只留最近 1000 条（防无限增长）
            let prune_sql = "DELETE FROM heartbeat_history WHERE task_id = ? AND id NOT IN (SELECT id FROM heartbeat_history WHERE task_id = ? ORDER BY id DESC LIMIT 1000)"
            match db.prepare(prune_sql) {
              None => ()
              Some(prune_stmt) => {
                ignore(
                  prune_stmt.bind(
                    1,
                    @sqlite.SqlValue::Text(@encoding.encode(UTF8, task_id)),
                  ),
                )
                ignore(
                  prune_stmt.bind(
                    2,
                    @sqlite.SqlValue::Text(@encoding.encode(UTF8, task_id)),
                  ),
                )
                ignore(prune_stmt.execute())
                prune_stmt.finalize()
              }
            }
            Ok(())
          } else {
            Err("sqlite 写入心跳间隔失败: \{task_id}")
          }
        }
      }
    }
  }
}

///|
/// 读取指定任务的心跳间隔历史（时间序：旧→新；最多 limit 条，默认 100）。
pub fn SqliteStore::list_heartbeat_intervals(
  self : SqliteStore,
  task_id : String,
  limit~ : Int32 = 100,
) -> Array[Int32] {
  let out : Array[Int32] = []
  match self.db {
    None => out
    Some(db) => {
      let sql = "SELECT interval_sec FROM heartbeat_history WHERE task_id = ? ORDER BY id DESC LIMIT ?"
      match db.prepare(sql) {
        None => out
        Some(stmt) => {
          ignore(
            stmt.bind(
              1,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, task_id)),
            ),
          )
          ignore(stmt.bind(2, @sqlite.SqlValue::Int(limit)))
          let rows : Array[Int32] = []
          while stmt.step() {
            rows.push(stmt.column_int(0))
          }
          stmt.finalize()
          // 逆序翻转 → 时间序（旧→新）
          for i = rows.length() - 1; i >= 0; i = i - 1 {
            out.push(rows[i])
          }
          out
        }
      }
    }
  }
}

// —— 调用日志（call_log 表）：与 write_heartbeat 同一持久化模式 ——

///|
/// 登记一条 Saga 补偿步骤（R92，durable action log）：同一 (ns, root_task_id, step)
/// 幂等覆盖——重登记会把 status 重置为 pending（重试安全），created_at 刷新。
pub fn SqliteStore::write_saga_action(
  self : SqliteStore,
  ns~ : String = "default",
  root_task_id~ : String,
  step~ : String,
  task_id~ : String = "",
  compensation~ : String,
  created_at~ : String,
) -> Result[Unit, String] {
  match self.db {
    None => Err("sqlite store 未打开")
    Some(db) => {
      let sql = "INSERT INTO saga_log (ns, root_task_id, step, task_id, compensation, status, created_at) VALUES (?, ?, ?, ?, ?, 'pending', ?) ON CONFLICT(ns, root_task_id, step) DO UPDATE SET task_id=excluded.task_id, compensation=excluded.compensation, status='pending', created_at=excluded.created_at"
      match db.prepare(sql) {
        None => Err("sqlite prepare 失败: write_saga_action")
        Some(stmt) => {
          ignore(
            stmt.bind(1, @sqlite.SqlValue::Text(@encoding.encode(UTF8, ns))),
          )
          ignore(
            stmt.bind(
              2,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, root_task_id)),
            ),
          )
          ignore(
            stmt.bind(3, @sqlite.SqlValue::Text(@encoding.encode(UTF8, step))),
          )
          ignore(
            stmt.bind(
              4,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, task_id)),
            ),
          )
          ignore(
            stmt.bind(
              5,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, compensation)),
            ),
          )
          ignore(
            stmt.bind(
              6,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, created_at)),
            ),
          )
          let exec_ok = stmt.execute()
          stmt.finalize()
          if exec_ok {
            Ok(())
          } else {
            Err("sqlite 写入 Saga 补偿失败: \{step}")
          }
        }
      }
    }
  }
}

///|
/// 列出某根任务已登记的 Saga 补偿步骤（前向顺序 id ASC：登记顺序）。
/// 返回 (id, step, task_id, compensation, status) 五元组数组。
pub fn SqliteStore::list_saga_actions(
  self : SqliteStore,
  ns : String,
  root_task_id : String,
) -> Array[(Int32, String, String, String, String)] {
  let out : Array[(Int32, String, String, String, String)] = []
  match self.db {
    None => out
    Some(db) => {
      let sql = "SELECT id, step, task_id, compensation, status FROM saga_log WHERE ns = ? AND root_task_id = ? ORDER BY id ASC"
      match db.prepare(sql) {
        None => out
        Some(stmt) => {
          ignore(
            stmt.bind(1, @sqlite.SqlValue::Text(@encoding.encode(UTF8, ns))),
          )
          ignore(
            stmt.bind(
              2,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, root_task_id)),
            ),
          )
          while stmt.step() {
            out.push(
              (
                stmt.column_int(0),
                str_from_bytes(stmt.column_text(1)),
                str_from_bytes(stmt.column_text(2)),
                str_from_bytes(stmt.column_text(3)),
                str_from_bytes(stmt.column_text(4)),
              ),
            )
          }
          stmt.finalize()
          out
        }
      }
    }
  }
}

///|
/// 把指定 Saga 补偿步骤标记为 done（已补偿/已消费），幂等。
pub fn SqliteStore::mark_saga_actions_done(
  self : SqliteStore,
  ns~ : String = "default",
  root_task_id~ : String,
  ids~ : Array[Int32],
) -> Result[Unit, String] {
  if ids.is_empty() {
    return Ok(())
  }
  match self.db {
    None => Err("sqlite store 未打开")
    Some(db) => {
      let placeholders = ids.map(fn(_) { "?" }).join(",")
      let sql = "UPDATE saga_log SET status='done' WHERE ns = ? AND root_task_id = ? AND id IN (\{placeholders})"
      match db.prepare(sql) {
        None => Err("sqlite prepare 失败: mark_saga_actions_done")
        Some(stmt) => {
          ignore(
            stmt.bind(1, @sqlite.SqlValue::Text(@encoding.encode(UTF8, ns))),
          )
          ignore(
            stmt.bind(
              2,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, root_task_id)),
            ),
          )
          let mut i = 3
          for id in ids {
            ignore(stmt.bind(i, @sqlite.SqlValue::Int(id)))
            i = i + 1
          }
          let exec_ok = stmt.execute()
          stmt.finalize()
          if exec_ok {
            Ok(())
          } else {
            Err("sqlite 标记 Saga 补偿失败")
          }
        }
      }
    }
  }
}

///|
/// 读取某熔断器记录（R104）：(state, failures, window_secs, threshold, recovery_secs, opened_at, last_fail_ts)。
pub fn SqliteStore::cb_get(
  self : SqliteStore,
  ns : String,
  circuit : String,
) -> (String, Int32, Int32, Int32, Int32, Int32, Int32)? {
  match self.db {
    None => None
    Some(db) => {
      let sql = "SELECT state, failures, window_secs, threshold, recovery_secs, opened_at, last_fail_ts FROM circuit_breakers WHERE ns = ? AND circuit = ?"
      match db.prepare(sql) {
        None => None
        Some(stmt) => {
          ignore(
            stmt.bind(1, @sqlite.SqlValue::Text(@encoding.encode(UTF8, ns))),
          )
          ignore(
            stmt.bind(
              2,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, circuit)),
            ),
          )
          let mut row : (String, Int32, Int32, Int32, Int32, Int32, Int32)? = None
          if stmt.step() {
            row = Some(
              (
                str_from_bytes(stmt.column_text(0)),
                stmt.column_int(1),
                stmt.column_int(2),
                stmt.column_int(3),
                stmt.column_int(4),
                stmt.column_int(5),
                stmt.column_int(6),
              ),
            )
          }
          stmt.finalize()
          row
        }
      }
    }
  }
}

///|
/// 写入/覆盖熔断器记录（R104，ON CONFLICT DO UPDATE 幂等）。
pub fn SqliteStore::cb_save(
  self : SqliteStore,
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
  match self.db {
    None => Err("sqlite store 未打开")
    Some(db) => {
      let sql = "INSERT INTO circuit_breakers (ns, circuit, state, failures, window_secs, threshold, recovery_secs, opened_at, last_fail_ts, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(ns, circuit) DO UPDATE SET state=excluded.state, failures=excluded.failures, window_secs=excluded.window_secs, threshold=excluded.threshold, recovery_secs=excluded.recovery_secs, opened_at=excluded.opened_at, last_fail_ts=excluded.last_fail_ts, updated_at=excluded.updated_at"
      match db.prepare(sql) {
        None => Err("sqlite prepare 失败: cb_save")
        Some(stmt) => {
          ignore(
            stmt.bind(1, @sqlite.SqlValue::Text(@encoding.encode(UTF8, ns))),
          )
          ignore(
            stmt.bind(
              2,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, circuit)),
            ),
          )
          ignore(
            stmt.bind(3, @sqlite.SqlValue::Text(@encoding.encode(UTF8, state))),
          )
          ignore(stmt.bind(4, @sqlite.SqlValue::Int(failures)))
          ignore(stmt.bind(5, @sqlite.SqlValue::Int(window_secs)))
          ignore(stmt.bind(6, @sqlite.SqlValue::Int(threshold)))
          ignore(stmt.bind(7, @sqlite.SqlValue::Int(recovery_secs)))
          ignore(stmt.bind(8, @sqlite.SqlValue::Int(opened_at)))
          ignore(stmt.bind(9, @sqlite.SqlValue::Int(last_fail_ts)))
          ignore(
            stmt.bind(
              10,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, updated_at)),
            ),
          )
          let exec_ok = stmt.execute()
          stmt.finalize()
          if exec_ok {
            Ok(())
          } else {
            Err("sqlite 写入熔断器失败")
          }
        }
      }
    }
  }
}

///|
/// 写入一条调用日志到 call_log 表。best-effort：失败返回 Err（调用方应忽略）。
pub fn SqliteStore::write_call_log(
  self : SqliteStore,
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
  match self.db {
    None => Err("sqlite store 未打开")
    Some(db) => {
      let sql = "INSERT INTO call_log (seq, ts, tool, caller, ns, params_json, result_json, ok, runtime_ms) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
      match db.prepare(sql) {
        None => Err("sqlite prepare 失败: write_call_log")
        Some(stmt) => {
          ignore(stmt.bind(1, @sqlite.SqlValue::Int(seq)))
          ignore(
            stmt.bind(2, @sqlite.SqlValue::Text(@encoding.encode(UTF8, ts))),
          )
          ignore(
            stmt.bind(3, @sqlite.SqlValue::Text(@encoding.encode(UTF8, tool))),
          )
          ignore(
            stmt.bind(4, @sqlite.SqlValue::Text(@encoding.encode(UTF8, caller))),
          )
          ignore(
            stmt.bind(5, @sqlite.SqlValue::Text(@encoding.encode(UTF8, ns))),
          )
          ignore(
            stmt.bind(
              6,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, params_json)),
            ),
          )
          ignore(
            stmt.bind(
              7,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, result_json)),
            ),
          )
          ignore(stmt.bind(8, @sqlite.SqlValue::Int(if ok { 1 } else { 0 })))
          ignore(stmt.bind(9, @sqlite.SqlValue::Int(runtime_ms)))
          let exec_ok = stmt.execute()
          stmt.finalize()
          if exec_ok {
            Ok(())
          } else {
            Err("sqlite 写入 call_log 失败: tool=\{tool}")
          }
        }
      }
    }
  }
}

///|
/// 读取最近 N 条调用日志（按自增 id DESC，新的在前；seq 仅作同进程单调定位）。
pub fn SqliteStore::recent_call_logs(
  self : SqliteStore,
  limit~ : Int32 = 50,
) -> Array[Json] {
  let out : Array[Json] = []
  match self.db {
    None => out
    Some(db) => {
      let sql = "SELECT seq, ts, tool, caller, ns, params_json, result_json, ok, runtime_ms FROM call_log ORDER BY id DESC LIMIT ?"
      match db.prepare(sql) {
        None => out
        Some(stmt) => {
          ignore(stmt.bind(1, @sqlite.SqlValue::Int(limit)))
          while stmt.step() {
            let m : Map[String, Json] = Map([])
            m.set("seq", Json::number(stmt.column_int(0).to_double()))
            m.set("ts", Json::string(str_from_bytes(stmt.column_text(1))))
            m.set("tool", Json::string(str_from_bytes(stmt.column_text(2))))
            m.set("caller", Json::string(str_from_bytes(stmt.column_text(3))))
            m.set("ns", Json::string(str_from_bytes(stmt.column_text(4))))
            m.set("params", Json::string(str_from_bytes(stmt.column_text(5))))
            m.set("result", Json::string(str_from_bytes(stmt.column_text(6))))
            m.set("ok", Json::boolean(stmt.column_int(7) != 0))
            m.set("runtime_ms", Json::number(stmt.column_int(8).to_double()))
            out.push(Json::object(m))
          }
          stmt.finalize()
          out
        }
      }
    }
  }
}

///|
/// AgentRecord —— `agents` 表的一行（进程级身份；`agent_id` 即指纹哈希，跨进程持久）。
/// `pid` 是进程实例标记（本仓不暴露 OS-PID，由 server 层以启动毫秒推导的实例 token 注入），
/// 同一指纹换 `pid` 视为"同一身份换进程"——身份不变、活体续期；`pid` 与上次不同即判旧实例已死。
pub struct AgentRecord {
  agent_id : String
  agent_type : String
  role : String
  soldier : String
  pid : Int32
  pubkey_fp : String
  first_seen : String
  last_seen : String
  status : String
}

///|
/// 注册 agent（指纹即身份）。首次出现则 INSERT，已存在则仅刷新
/// `pid`/`last_seen`/`status`（身份不变，进程实例换新）。
///
/// **职责边界（BUG-404）**：本函数**只写 `agents` 表，不落默认 ACL**——
/// 原注释称「并落一条 fail-closed 的默认 ACL」，实际 body 无任何 `agent_acl` INSERT。
/// 默认 ACL 的真源在 **server 层**的 `agents_acl_ensure`（`src/server/server.mbt`，
/// `agent_touch_first_seen` 调用链保证），不在 store 层。
/// **后果**：任何绕过 server 层 `agents_acl_ensure` 的直连 store 调用
/// （现成的就是 `agents_heartbeat`）会留下「有 agent 身份、无 ACL 行」的中间态；
/// `agents_acl_check` 对此返回 `Err("ACL 无记录（fail-closed）")`——仍 fail-closed，
/// 不是安全洞，但「注释承诺的默认 ACL 自动落」在这条路径上从不发生。
/// 需要「注册即落 ACL」语义时，调用方必须先过 server 层 `agents_acl_ensure`。
pub fn SqliteStore::agents_register(
  self : SqliteStore,
  agent_id~ : String,
  agent_type~ : String,
  role~ : String,
  soldier~ : String,
  pubkey_fp~ : String,
  pid~ : Int32,
  now~ : String,
) -> Result[Unit, String] {
  match self.db {
    None => Err("sqlite store 未打开")
    Some(db) => {
      // BUG-423：`ON CONFLICT` 必须**防降级**。
      //
      // 原实现只刷 `pid`/`last_seen`/`status`、**完全不碰 `role`** —— 本意是
      // 「防低权路径改高权角色」，但副作用是「**第一次出现的 role 终生有效**」，
      // 而第一次出现往往来自低权路径（claim/execute 的 `agent_touch_first_seen`
      // 对任意 assignee 写 `role="Executor"`）。
      //
      // ⇒ 一旦有人以 `human_steward` 作为 assignee 认领过任务，那个身份就被永久
      // 固定为 Executor；而 BUG-418 的修法让角色判定**优先读 `agents.role`**
      // ⇒ **合法统帅本人订自己的独占面会被拒**（`src/store/store_sqlite.mbt`）。
      //
      // 修法：`role` 取「库里现值 vs 本次值」中**不低于 Executor 的那一个** ——
      //   · 库里是 HumanSteward/Leader ⇒ **不被 Executor 覆盖**（防降级）
      //   · 库里是 Executor ⇒ 可被显式注册抬高为 HumanSteward/Leader（正道可行）
      // 用 CASE 而不是无条件 `role=excluded.role`，是因为后者会让低权路径
      // （claim 传 Executor）把高角色打回去 —— 那正是本条 bug 的原始形状。
      let sql = "INSERT INTO agents (agent_id, agent_type, role, soldier, pid, pubkey_fp, first_seen, last_seen, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'active') ON CONFLICT(agent_id) DO UPDATE SET pid=excluded.pid, last_seen=excluded.last_seen, status='active', role=CASE WHEN agents.role != 'Executor' THEN agents.role ELSE excluded.role END"
      match db.prepare(sql) {
        None => Err("sqlite prepare 失败: agents_register")
        Some(stmt) => {
          ignore(
            stmt.bind(
              1,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, agent_id)),
            ),
          )
          ignore(
            stmt.bind(
              2,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, agent_type)),
            ),
          )
          ignore(
            stmt.bind(3, @sqlite.SqlValue::Text(@encoding.encode(UTF8, role))),
          )
          ignore(
            stmt.bind(
              4,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, soldier)),
            ),
          )
          ignore(stmt.bind(5, @sqlite.SqlValue::Int(pid)))
          ignore(
            stmt.bind(
              6,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, pubkey_fp)),
            ),
          )
          ignore(
            stmt.bind(7, @sqlite.SqlValue::Text(@encoding.encode(UTF8, now))),
          )
          ignore(
            stmt.bind(8, @sqlite.SqlValue::Text(@encoding.encode(UTF8, now))),
          )
          let exec_ok = stmt.execute()
          stmt.finalize()
          if exec_ok {
            Ok(())
          } else {
            Err("sqlite 注册 agent 失败: \{agent_id}")
          }
        }
      }
    }
  }
}

///|
/// 进程级心跳：刷新 `pid`/`last_seen` 并置回 active。`agent_id` 未注册则先注册（agent_type 取调用方给出值）。
pub fn SqliteStore::agents_heartbeat(
  self : SqliteStore,
  agent_id~ : String,
  agent_type~ : String,
  role~ : String,
  soldier~ : String,
  pid~ : Int32,
  now~ : String,
) -> Result[Unit, String] {
  self.agents_register(
    agent_id~,
    agent_type~,
    role~,
    soldier~,
    pubkey_fp="",
    pid~,
    now~,
  )
}

///|
/// 读单个 agent 的持久化身份（无记录返回 None）。
pub fn SqliteStore::agents_get(
  self : SqliteStore,
  agent_id : String,
) -> AgentRecord? {
  match self.db {
    None => None
    Some(db) => {
      let sql = "SELECT agent_id, agent_type, role, soldier, pid, pubkey_fp, first_seen, last_seen, status FROM agents WHERE agent_id = ?"
      match db.prepare(sql) {
        None => None
        Some(stmt) => {
          ignore(
            stmt.bind(
              1,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, agent_id)),
            ),
          )
          let rec = if stmt.step() {
            Some(AgentRecord::{
              agent_id: str_from_bytes(stmt.column_text(0)),
              agent_type: str_from_bytes(stmt.column_text(1)),
              role: str_from_bytes(stmt.column_text(2)),
              soldier: str_from_bytes(stmt.column_text(3)),
              pid: stmt.column_int(4),
              pubkey_fp: str_from_bytes(stmt.column_text(5)),
              first_seen: str_from_bytes(stmt.column_text(6)),
              last_seen: str_from_bytes(stmt.column_text(7)),
              status: str_from_bytes(stmt.column_text(8)),
            })
          } else {
            None
          }
          stmt.finalize()
          rec
        }
      }
    }
  }
}

///|
/// 换绑进程实例（server 启动时调用）：仅刷新 `pid`，不动 `first_seen`/`last_seen`。
pub fn SqliteStore::agents_set_pid(
  self : SqliteStore,
  agent_id~ : String,
  pid~ : Int32,
) -> Result[Unit, String] {
  match self.db {
    None => Err("sqlite store 未打开")
    Some(db) => {
      let sql = "UPDATE agents SET pid = ? WHERE agent_id = ?"
      match db.prepare(sql) {
        None => Err("sqlite prepare 失败: agents_set_pid")
        Some(stmt) => {
          ignore(stmt.bind(1, @sqlite.SqlValue::Int(pid)))
          ignore(
            stmt.bind(
              2,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, agent_id)),
            ),
          )
          let exec_ok = stmt.execute()
          stmt.finalize()
          if exec_ok {
            Ok(())
          } else {
            Err("sqlite 换绑 pid 失败: \{agent_id}")
          }
        }
      }
    }
  }
}

///|
/// 确保一条默认 ACL（can_read=1, can_write=0, pid_bound=0）——fail-closed 底线。
/// 已存在则不动（授权变更只经 `agents_acl_grant`）。
pub fn SqliteStore::agents_acl_ensure(
  self : SqliteStore,
  agent_id~ : String,
  ns~ : String,
  now~ : String,
) -> Result[Unit, String] {
  // `now` 是公开契约的一部分（与 agents_acl_grant 同形，调用方统一传时刻），
  // 但 agent_acl 表没有 created_at 列 —— 默认 ACL 只断言"存在即 fail-closed"，
  // 首次写入时刻不是判据面。保留参数不破坏调用面，此处显式消费掉。
  ignore(now)
  match self.db {
    None => Err("sqlite store 未打开")
    Some(db) => {
      let sql = "INSERT OR IGNORE INTO agent_acl (agent_id, ns, can_read, can_write, pid_bound, revoked_at, revoked_by) VALUES (?, ?, 1, 0, 0, '', '')"
      match db.prepare(sql) {
        None => Err("sqlite prepare 失败: agents_acl_ensure")
        Some(stmt) => {
          ignore(
            stmt.bind(
              1,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, agent_id)),
            ),
          )
          ignore(
            stmt.bind(2, @sqlite.SqlValue::Text(@encoding.encode(UTF8, ns))),
          )
          let exec_ok = stmt.execute()
          stmt.finalize()
          if exec_ok {
            Ok(())
          } else {
            Err("sqlite 默认 ACL 落库失败: \{agent_id}/\{ns}")
          }
        }
      }
    }
  }
}

///|
/// ACL 检查（调用前先 `agents_acl_ensure`）。`write=true` 且 `can_write=0` 即 Err；
/// `write=false` 且 `can_read=0` 即 Err。`pid_bound=1` 且 `agents.pid` 与当前 pid 不同视为换实例 → Err。
pub fn SqliteStore::agents_acl_check(
  self : SqliteStore,
  agent_id~ : String,
  ns~ : String,
  write~ : Bool,
  current_pid~ : Int32,
) -> Result[Unit, String] {
  match self.db {
    None => Err("sqlite store 未打开")
    Some(db) => {
      let sql = "SELECT a.can_read, a.can_write, a.pid_bound, g.pid FROM agent_acl a LEFT JOIN agents g ON g.agent_id = a.agent_id WHERE a.agent_id = ? AND a.ns = ?"
      match db.prepare(sql) {
        None => Err("sqlite prepare 失败: agents_acl_check")
        Some(stmt) => {
          ignore(
            stmt.bind(
              1,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, agent_id)),
            ),
          )
          ignore(
            stmt.bind(2, @sqlite.SqlValue::Text(@encoding.encode(UTF8, ns))),
          )
          let verdict = if stmt.step() {
            let can_read = stmt.column_int(0)
            let can_write = stmt.column_int(1)
            let pid_bound = stmt.column_int(2)
            let bound_pid = stmt.column_int(3)
            stmt.finalize()
            if pid_bound != 0 && bound_pid != current_pid {
              Err(
                "ACL 绑定旧进程实例（pid_bound=1 且 pid 已换），需重新授权: \{agent_id}/\{ns}",
              )
            } else if write && can_write == 0 {
              // BUG-408：原文案只说 can_write=0，调用方无法自救（不知道谁能授予、怎么授予），
              // 也看不出「publish 成功而 claim 被拒」是两道门（角色矩阵 vs ns ACL）结论不同所致。
              // 这里附足三条出路，让错误本身可行动。
              Err(
                "ACL 默认拒绝写（can_write=0）: \{agent_id}/\{ns}。出路：① 由 human_steward 执行 agents_acl_grant(agent_id=\"{agent_id}\", ns=\"{ns}\", can_write=true) 授予写权；② 若这是首次接入该 ns，先 store_open(ns=\"{ns}\") 建立会话再重试；③ 注意 audit_permission 只反映角色矩阵、不反映 ns ACL（两道独立门，见 BUG-408）——角色矩阵 allowed 不代表本 ns 可写",
              )
            } else if !write && can_read == 0 {
              Err("ACL 拒绝读（can_read=0）: \{agent_id}/\{ns}")
            } else {
              Ok(())
            }
          } else {
            stmt.finalize()
            Err("ACL 无记录（fail-closed）: \{agent_id}/\{ns}")
          }
          verdict
        }
      }
    }
  }
}

///|
/// 统计某命名空间下 `can_write=1` 的 agent 数（BUG-411）。
///
/// **为什么需要它**：`publish` / `publish_parallel` / `dag_publish` 走 human_steward
/// 特权路径、**不看 ns ACL**，而 `claim` 走 `agent_write_gate` 的 ns ACL ——
/// 两道门结论可以相反（同一 ns 内 publish 成功、claim 被拒）。调用方在
/// 「发布成功」与「认领被拒」之间没有任何预警，排查成本高（BUG-411 实测）。
///
/// 本函数只回答一个问题：**这个 ns 现在有没有任何一个 agent 能写**。
/// publish 成功时若为 0，回执就该当场预警「你之后 claim 会被拒 + 出路」。
///
/// 口径与 `agents_acl_check` 保持一致：只看 `can_write`，不看 `revoked_at`
/// （吊销在 `agents_acl_grant` 里就是 `can_write=0`，两处同源）。
/// 内存 stub 返回 0（无持久化 ACL 面，与 `agent_write_gate` 的放行口径不同——
/// 那是写门，这是诊断读数，0 会让调用方看到「无持久化 ACL」这个事实）。
pub fn SqliteStore::agents_acl_count_writable(
  self : SqliteStore,
  ns~ : String,
) -> Int32 {
  match self.db {
    None => 0
    Some(db) => {
      let sql = "SELECT COUNT(*) FROM agent_acl WHERE ns = ? AND can_write = 1"
      match db.prepare(sql) {
        None => 0
        Some(stmt) => {
          ignore(
            stmt.bind(1, @sqlite.SqlValue::Text(@encoding.encode(UTF8, ns))),
          )
          let n = if stmt.step() { stmt.column_int(0) } else { 0 }
          stmt.finalize()
          n
        }
      }
    }
  }
}

///|
/// 授权/收权（UPSERT）：`can_read`/`can_write` 直接覆盖；`pid_bound=1` 时绑定当前 `agents.pid`，
/// 之后换进程实例即失效。`now` 写入 revoked_at/revoked_by 仅用于吊销记录（can_write=0 且 pid_bound=0）。
pub fn SqliteStore::agents_acl_grant(
  self : SqliteStore,
  agent_id~ : String,
  ns~ : String,
  can_read~ : Bool,
  can_write~ : Bool,
  pid_bound~ : Bool,
  now~ : String,
  by~ : String,
) -> Result[Unit, String] {
  match self.db {
    None => Err("sqlite store 未打开")
    Some(db) => {
      // 先取该 agent 当前 pid（供 pid_bound=1 绑定）
      let bound_pid = match
        db.prepare("SELECT pid FROM agents WHERE agent_id = ?") {
        None => 0
        Some(s2) => {
          ignore(
            s2.bind(1, @sqlite.SqlValue::Text(@encoding.encode(UTF8, agent_id))),
          )
          let p = if s2.step() { s2.column_int(0) } else { 0 }
          s2.finalize()
          p
        }
      }
      let revoke = if !can_write && !pid_bound { now } else { "" }
      let revoke_by = if !can_write && !pid_bound { by } else { "" }
      let sql = "INSERT INTO agent_acl (agent_id, ns, can_read, can_write, pid_bound, revoked_at, revoked_by) VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT(agent_id, ns) DO UPDATE SET can_read=excluded.can_read, can_write=excluded.can_write, pid_bound=excluded.pid_bound, revoked_at=excluded.revoked_at, revoked_by=excluded.revoked_by"
      match db.prepare(sql) {
        None => Err("sqlite prepare 失败: agents_acl_grant")
        Some(stmt) => {
          ignore(
            stmt.bind(
              1,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, agent_id)),
            ),
          )
          ignore(
            stmt.bind(2, @sqlite.SqlValue::Text(@encoding.encode(UTF8, ns))),
          )
          ignore(
            stmt.bind(3, @sqlite.SqlValue::Int(if can_read { 1 } else { 0 })),
          )
          ignore(
            stmt.bind(4, @sqlite.SqlValue::Int(if can_write { 1 } else { 0 })),
          )
          ignore(
            stmt.bind(
              5,
              @sqlite.SqlValue::Int(if pid_bound { bound_pid } else { 0 }),
            ),
          )
          ignore(
            stmt.bind(6, @sqlite.SqlValue::Text(@encoding.encode(UTF8, revoke))),
          )
          ignore(
            stmt.bind(
              7,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, revoke_by)),
            ),
          )
          let exec_ok = stmt.execute()
          stmt.finalize()
          if exec_ok {
            Ok(())
          } else {
            Err("sqlite 授权失败: \{agent_id}/\{ns}")
          }
        }
      }
    }
  }
}

///|
/// 陈旧 agent 扫描：返回 `last_seen` 早于 `cutoff`（或从未心跳）的 agent 列表。
/// `cutoff` 与 `last_seen` 同为 `YYYY-MM-DDTHH:MM:SSZ`，字典序比较成立。
pub fn SqliteStore::agents_stale_check(
  self : SqliteStore,
  cutoff : String,
) -> Array[AgentRecord] {
  let out : Array[AgentRecord] = []
  match self.db {
    None => out
    Some(db) => {
      let sql = "SELECT agent_id, agent_type, role, soldier, pid, pubkey_fp, first_seen, last_seen, status FROM agents WHERE status = 'active' AND (last_seen = '' OR last_seen < ?)"
      match db.prepare(sql) {
        None => out
        Some(stmt) => {
          ignore(
            stmt.bind(1, @sqlite.SqlValue::Text(@encoding.encode(UTF8, cutoff))),
          )
          while stmt.step() {
            out.push(AgentRecord::{
              agent_id: str_from_bytes(stmt.column_text(0)),
              agent_type: str_from_bytes(stmt.column_text(1)),
              role: str_from_bytes(stmt.column_text(2)),
              soldier: str_from_bytes(stmt.column_text(3)),
              pid: stmt.column_int(4),
              pubkey_fp: str_from_bytes(stmt.column_text(5)),
              first_seen: str_from_bytes(stmt.column_text(6)),
              last_seen: str_from_bytes(stmt.column_text(7)),
              status: str_from_bytes(stmt.column_text(8)),
            })
          }
          stmt.finalize()
          out
        }
      }
    }
  }
}
