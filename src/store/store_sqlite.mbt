/// FIST-Mbt store: SQLite 持久化后端（M1 内建数据库）。
/// 依赖 mizchi/sqlite（native+js 双端）。五表骨架单调落盘，其中 tasks 完整接入 Store trait；
/// specs / runs / heartbeats / archive 先建表供 Phase 2(Omega) / Phase 5(scheduler) 使用。
/// 列约定：parent_id / assignee / completed_by 等可空字段用空串 "" 表示 None。

///|
/// SQLite 后端：持有打开的 Database（Option 以承载 open 失败场景）。
pub struct SqliteStore {
  db : @sqlite.Database?
}

///|
/// 打开数据库并初始化五表 schema。失败返回 None（调用方决定是否 abort / 回退内存）。
pub fn SqliteStore::open(db_path : String) -> SqliteStore? {
  match @sqlite.Database::open(db_path) {
    None => None
    Some(db) => {
      let s = { db: Some(db), }
      if s.create_schema() {
        // 启用 WAL 模式提升并发读写性能
        s.exec_if_ok("PRAGMA journal_mode=WAL")
        s.exec_if_ok("PRAGMA synchronous=NORMAL")
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
/// 以默认路径（fist-mbt.db，随运行目录）打开的便捷构造。
pub fn SqliteStore::new() -> SqliteStore? {
  SqliteStore::open("fist-mbt.db")
}

///|
/// 初始化 schema：tasks 为完整任务表，specs/runs/heartbeats/archive 为后续阶段预置骨架。
fn SqliteStore::create_schema(self : SqliteStore) -> Bool {
  let sqls : Array[String] = [
    "CREATE TABLE IF NOT EXISTS tasks (id TEXT PRIMARY KEY, parent_id TEXT DEFAULT '', project_dir TEXT NOT NULL DEFAULT '', ns TEXT NOT NULL DEFAULT 'default', priority TEXT NOT NULL DEFAULT '中', importance TEXT NOT NULL DEFAULT '中', depth INTEGER NOT NULL DEFAULT 3, split_n INTEGER NOT NULL DEFAULT 3, status TEXT NOT NULL DEFAULT '待领取', assignee TEXT DEFAULT '', description TEXT NOT NULL DEFAULT '', deliverable TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL DEFAULT '', updated_at TEXT NOT NULL DEFAULT '', completed_by TEXT DEFAULT '', cleanup_mode TEXT NOT NULL DEFAULT 'deferred', depends_on TEXT NOT NULL DEFAULT '[]')",
    "CREATE TABLE IF NOT EXISTS specs (id TEXT PRIMARY KEY, task_id TEXT NOT NULL DEFAULT '', spec_type TEXT NOT NULL DEFAULT 'spec', content TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'pending', created_at TEXT NOT NULL DEFAULT '', updated_at TEXT NOT NULL DEFAULT '')",
    "CREATE TABLE IF NOT EXISTS runs (id TEXT PRIMARY KEY, task_id TEXT NOT NULL DEFAULT '', run_type TEXT NOT NULL DEFAULT 'verify', status TEXT NOT NULL DEFAULT 'running', detail TEXT NOT NULL DEFAULT '', started_at TEXT NOT NULL DEFAULT '', finished_at TEXT DEFAULT '')",
    "CREATE TABLE IF NOT EXISTS heartbeats (agent_id TEXT NOT NULL, task_id TEXT NOT NULL, last_seen TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'active', PRIMARY KEY (agent_id, task_id))",
    "CREATE TABLE IF NOT EXISTS archive (id TEXT PRIMARY KEY, task_json TEXT NOT NULL DEFAULT '', archived_at TEXT NOT NULL DEFAULT '')",
    "CREATE TABLE IF NOT EXISTS evolve_artifacts (id TEXT PRIMARY KEY, parent_id TEXT DEFAULT '', goal TEXT NOT NULL DEFAULT '', note TEXT NOT NULL DEFAULT '', code TEXT NOT NULL DEFAULT '', score TEXT NOT NULL DEFAULT '0', parts_json TEXT NOT NULL DEFAULT '{}', children INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL DEFAULT '')",
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

// —— 行 <-> Task 序列化辅助 ——

///|
fn SqliteStore::task_columns() -> String {
  "id, parent_id, project_dir, ns, priority, importance, depth, split_n, status, assignee, description, deliverable, created_at, updated_at, completed_by, cleanup_mode, depends_on"
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
  ignore(
    stmt.bind(
      9,
      @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.status.to_string())),
    ),
  )
  ignore(
    stmt.bind(
      10,
      @sqlite.SqlValue::Text(@encoding.encode(UTF8, _opt_str(t.get_assignee()))),
    ),
  )
  ignore(
    stmt.bind(11, @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.description))),
  )
  ignore(
    stmt.bind(12, @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.deliverable))),
  )
  ignore(
    stmt.bind(13, @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.created_at))),
  )
  ignore(
    stmt.bind(14, @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.updated_at))),
  )
  ignore(
    stmt.bind(
      15,
      @sqlite.SqlValue::Text(@encoding.encode(UTF8, _opt_str(t.completed_by))),
    ),
  )
  ignore(
    stmt.bind(
      16,
      @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.cleanup_mode)),
    ),
  )
  ignore(
    stmt.bind(
      17,
      @sqlite.SqlValue::Text(
        @encoding.encode(UTF8, _array_to_json(t.depends_on)),
      ),
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
}

///|
fn str_from_bytes(b : Bytes) -> String {
  let sb = StringBuilder::new()
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
  let trimmed = json.trim()
  if trimmed == "" || trimmed == "[]" {
    return []
  }
  let inner = trimmed[1:trimmed.length() - 1]
  if inner == "" {
    return []
  }
  let parts = inner.split(",")
  let out : Array[String] = []
  for p in parts {
    let raw = p.trim()
    let stripped = if raw.length() >= 2 { raw[1:raw.length() - 1] } else { raw }
    if stripped != "" {
      out.push(stripped.to_string())
    }
  }
  out
}

///|
fn row_to_task(stmt : @sqlite.Statement) -> @core.Task {
  let parent_raw = str_from_bytes(stmt.column_text(1))
  let assignee_raw = str_from_bytes(stmt.column_text(9))
  let completed_raw = str_from_bytes(stmt.column_text(14))
  let depends_raw = str_from_bytes(stmt.column_text(16))
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
    str_from_bytes(stmt.column_text(8)),
    if assignee_raw == "" {
      None
    } else {
      Some(assignee_raw)
    },
    str_from_bytes(stmt.column_text(10)),
    str_from_bytes(stmt.column_text(11)),
    str_from_bytes(stmt.column_text(12)),
    str_from_bytes(stmt.column_text(13)),
    if completed_raw == "" {
      None
    } else {
      Some(completed_raw)
    },
    str_from_bytes(stmt.column_text(15)),
    _json_to_array(depends_raw),
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
      let sql = "INSERT INTO tasks (\{SqliteStore::task_columns()}) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)"
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
      let sql = "UPDATE tasks SET parent_id = ?, project_dir = ?, ns = ?, priority = ?, importance = ?, depth = ?, split_n = ?, status = ?, assignee = ?, description = ?, deliverable = ?, created_at = ?, updated_at = ?, completed_by = ?, cleanup_mode = ?, depends_on = ? WHERE id = ?"
      match db.prepare(sql) {
        None => Err("sqlite prepare 失败: update_task")
        Some(stmt) => {
          SqliteStore::bind_task_update_values(stmt, task)
          ignore(
            stmt.bind(
              17,
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
/// 列出指定命名空间的任务
pub fn SqliteStore::list_tasks_in(
  self : SqliteStore,
  ns_filter : String,
) -> Array[@core.Task] {
  let out : Array[@core.Task] = []
  match self.db {
    None => out
    Some(db) => {
      let sql = "SELECT \{SqliteStore::task_columns()} FROM tasks WHERE ns = ?"
      match db.prepare(sql) {
        None => out
        Some(stmt) => {
          ignore(
            stmt.bind(
              1,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, ns_filter)),
            ),
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
fn evolve_col_text(stmt : @sqlite.Statement, i : Int) -> String {
  str_from_bytes(stmt.column_text(i))
}

///|
/// 解析 evolve_artifacts 的 score 文本为 Double（复用同包 executions 的解析器）。
fn evolve_parse_double(raw : String) -> Double {
  parse_simple_double(raw)
}

///|
/// 取 evolve_artifacts 某列 int。
fn evolve_col_int(stmt : @sqlite.Statement, i : Int) -> Int {
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
      ignore(db.exec("DELETE FROM tasks"))
      ignore(db.exec("DELETE FROM archive"))
      // 与 MemoryStore 语义对齐：清空时同时清空语料 / 复验 / 升级账本
      ignore(self.ensure_specs_table())
      ignore(db.exec("DELETE FROM specs"))
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
  tokens_in~ : Int,
  tokens_out~ : Int,
  cost~ : Double,
  duration_ms~ : Int,
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
