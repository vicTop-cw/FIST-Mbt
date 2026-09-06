/// FIST-Mbt store: SQLite 持久化后端（M1 内建数据库）。
/// 依赖 mizchi/sqlite（native+js 双端）。五表骨架单调落盘，其中 tasks 完整接入 Store trait；
/// specs / runs / heartbeats / archive 先建表供 Phase 2(Omega) / Phase 5(scheduler) 使用。
/// 列约定：parent_id / assignee / completed_by 等可空字段用空串 "" 表示 None。

/// SQLite 后端：持有打开的 Database（Option 以承载 open 失败场景）。
pub struct SqliteStore {
  db : @sqlite.Database?
}

/// 打开数据库并初始化五表 schema。失败返回 None（调用方决定是否 abort / 回退内存）。
pub fn SqliteStore::open(db_path : String) -> Option[SqliteStore] {
  match @sqlite.Database::open(db_path) {
    None => None
    Some(db) => {
      let s = { db: Some(db) }
      if s.create_schema() {
        Some(s)
      } else {
        db.close()
        None
      }
    }
  }
}

/// 以默认路径（fist-mbt.db，随运行目录）打开的便捷构造。
pub fn SqliteStore::new() -> Option[SqliteStore] {
  SqliteStore::open("fist-mbt.db")
}

/// 初始化 schema：tasks 为完整任务表，specs/runs/heartbeats/archive 为后续阶段预置骨架。
fn SqliteStore::create_schema(self : SqliteStore) -> Bool {
  let sqls : Array[String] = [
    "CREATE TABLE IF NOT EXISTS tasks (id TEXT PRIMARY KEY, parent_id TEXT DEFAULT '', project_dir TEXT NOT NULL DEFAULT '', priority TEXT NOT NULL DEFAULT '中', importance TEXT NOT NULL DEFAULT '中', depth INTEGER NOT NULL DEFAULT 3, split_n INTEGER NOT NULL DEFAULT 3, status TEXT NOT NULL DEFAULT '待领取', assignee TEXT DEFAULT '', description TEXT NOT NULL DEFAULT '', deliverable TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL DEFAULT '', updated_at TEXT NOT NULL DEFAULT '', completed_by TEXT DEFAULT '', cleanup_mode TEXT NOT NULL DEFAULT 'deferred')",
    "CREATE TABLE IF NOT EXISTS specs (id TEXT PRIMARY KEY, task_id TEXT NOT NULL DEFAULT '', spec_type TEXT NOT NULL DEFAULT 'spec', content TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'pending', created_at TEXT NOT NULL DEFAULT '', updated_at TEXT NOT NULL DEFAULT '')",
    "CREATE TABLE IF NOT EXISTS runs (id TEXT PRIMARY KEY, task_id TEXT NOT NULL DEFAULT '', run_type TEXT NOT NULL DEFAULT 'verify', status TEXT NOT NULL DEFAULT 'running', detail TEXT NOT NULL DEFAULT '', started_at TEXT NOT NULL DEFAULT '', finished_at TEXT DEFAULT '')",
    "CREATE TABLE IF NOT EXISTS heartbeats (agent_id TEXT NOT NULL, task_id TEXT NOT NULL, last_seen TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'active', PRIMARY KEY (agent_id, task_id))",
    "CREATE TABLE IF NOT EXISTS archive (id TEXT PRIMARY KEY, task_json TEXT NOT NULL DEFAULT '', archived_at TEXT NOT NULL DEFAULT '')",
  ]
  match self.db {
    None => false
    Some(db) => {
      var ok = true
      for s in sqls {
        if !db.exec(s) { ok = false }
      }
      ok
    }
  }
}

// —— 行 <-> Task 序列化辅助 ——

fn SqliteStore::task_columns() -> String {
  "id, parent_id, project_dir, priority, importance, depth, split_n, status, assignee, description, deliverable, created_at, updated_at, completed_by, cleanup_mode"
}

fn SqliteStore::bind_task_values(stmt : @sqlite.Statement, t : Task) -> Unit {
  ignore(stmt.bind(1, @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.get_id()))))
  ignore(stmt.bind(2, @sqlite.SqlValue::Text(@encoding.encode(UTF8, _opt_str(t.get_parent())))))
  ignore(stmt.bind(3, @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.project_dir))))
  ignore(stmt.bind(4, @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.priority))))
  ignore(stmt.bind(5, @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.importance))))
  ignore(stmt.bind(6, @sqlite.SqlValue::Int(t.depth)))
  ignore(stmt.bind(7, @sqlite.SqlValue::Int(t.split_n)))
  ignore(stmt.bind(8, @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.status.to_string()))))
  ignore(stmt.bind(9, @sqlite.SqlValue::Text(@encoding.encode(UTF8, _opt_str(t.get_assignee())))))
  ignore(stmt.bind(10, @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.description))))
  ignore(stmt.bind(11, @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.deliverable))))
  ignore(stmt.bind(12, @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.created_at))))
  ignore(stmt.bind(13, @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.updated_at))))
  ignore(stmt.bind(14, @sqlite.SqlValue::Text(@encoding.encode(UTF8, _opt_str(t.completed_by)))))
  ignore(stmt.bind(15, @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.cleanup_mode))))
}

/// UPDATE 专用绑定：SET 列顺序（parent_id..cleanup_mode）+ WHERE id
fn SqliteStore::bind_task_update_values(stmt : @sqlite.Statement, t : Task) -> Unit {
  ignore(stmt.bind(1, @sqlite.SqlValue::Text(@encoding.encode(UTF8, _opt_str(t.get_parent())))))
  ignore(stmt.bind(2, @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.project_dir))))
  ignore(stmt.bind(3, @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.priority))))
  ignore(stmt.bind(4, @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.importance))))
  ignore(stmt.bind(5, @sqlite.SqlValue::Int(t.depth)))
  ignore(stmt.bind(6, @sqlite.SqlValue::Int(t.split_n)))
  ignore(stmt.bind(7, @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.status.to_string()))))
  ignore(stmt.bind(8, @sqlite.SqlValue::Text(@encoding.encode(UTF8, _opt_str(t.get_assignee())))))
  ignore(stmt.bind(9, @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.description))))
  ignore(stmt.bind(10, @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.deliverable))))
  ignore(stmt.bind(11, @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.created_at))))
  ignore(stmt.bind(12, @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.updated_at))))
  ignore(stmt.bind(13, @sqlite.SqlValue::Text(@encoding.encode(UTF8, _opt_str(t.completed_by)))))
  ignore(stmt.bind(14, @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.cleanup_mode))))
}

fn str_from_bytes(b : Bytes) -> String {
  let sb = StringBuilder::new()
  @encoding.decode_to(b, sb, encoding=UTF8) catch {
    _ => ()
  }
  sb.to_string()
}

fn _opt_str(o : String?) -> String {
  match o {
    Some(s) => s
    None => ""
  }
}

fn row_to_task(stmt : @sqlite.Statement) -> Task {
  let parent_raw = str_from_bytes(stmt.column_text(1))
  let assignee_raw = str_from_bytes(stmt.column_text(8))
  let completed_raw = str_from_bytes(stmt.column_text(13))
  let status_s = str_from_bytes(stmt.column_text(7))
  let status = match TaskStatus::from_string(status_s) {
    Some(s) => s
    None => Pending
  }
  {
    id : str_from_bytes(stmt.column_text(0)),
    parent_id : if parent_raw == "" { None } else { Some(parent_raw) },
    project_dir : str_from_bytes(stmt.column_text(2)),
    priority : str_from_bytes(stmt.column_text(3)),
    importance : str_from_bytes(stmt.column_text(4)),
    depth : stmt.column_int(5),
    split_n : stmt.column_int(6),
    status,
    assignee : if assignee_raw == "" { None } else { Some(assignee_raw) },
    description : str_from_bytes(stmt.column_text(9)),
    deliverable : str_from_bytes(stmt.column_text(10)),
    created_at : str_from_bytes(stmt.column_text(11)),
    updated_at : str_from_bytes(stmt.column_text(12)),
    completed_by : if completed_raw == "" { None } else { Some(completed_raw) },
    cleanup_mode : str_from_bytes(stmt.column_text(14)),
  }
}

// —— Store trait 实现 ——

impl Store for SqliteStore with create_task(self, task) {
  match self.db {
    None => Err("sqlite store 未打开")
    Some(db) => {
      if self.get_task(task.get_id()) is Some(_) {
        return Err("task already exists: \{task.get_id()}")
      }
      let sql = "INSERT INTO tasks (\{SqliteStore::task_columns()}) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)"
      match db.prepare(sql) {
        None => Err("sqlite prepare 失败: create_task")
        Some(stmt) => {
          SqliteStore::bind_task_values(stmt, task)
          let exec_ok = stmt.execute()
          stmt.finalize()
          if exec_ok { Ok(()) } else { Err("sqlite 写入失败: \{task.get_id()}") }
        }
      }
    }
  }
}

impl Store for SqliteStore with get_task(self, id) {
  match self.db {
    None => None
    Some(db) => {
      let sql = "SELECT \{SqliteStore::task_columns()} FROM tasks WHERE id = ?"
      match db.prepare(sql) {
        None => None
        Some(stmt) => {
          ignore(stmt.bind(1, @sqlite.SqlValue::Text(@encoding.encode(UTF8, id))))
          let found = if stmt.step() { Some(row_to_task(stmt)) } else { None }
          stmt.finalize()
          found
        }
      }
    }
  }
}

impl Store for SqliteStore with update_task(self, task) {
  match self.db {
    None => Err("sqlite store 未打开")
    Some(db) => {
      if self.get_task(task.get_id()) is None {
        return Err("task not found: \{task.get_id()}")
      }
      let sql = "UPDATE tasks SET parent_id = ?, project_dir = ?, priority = ?, importance = ?, depth = ?, split_n = ?, status = ?, assignee = ?, description = ?, deliverable = ?, created_at = ?, updated_at = ?, completed_by = ?, cleanup_mode = ? WHERE id = ?"
      match db.prepare(sql) {
        None => Err("sqlite prepare 失败: update_task")
        Some(stmt) => {
          SqliteStore::bind_task_update_values(stmt, task)
          ignore(stmt.bind(15, @sqlite.SqlValue::Text(@encoding.encode(UTF8, task.get_id()))))
          let exec_ok = stmt.execute()
          stmt.finalize()
          if exec_ok { Ok(()) } else { Err("sqlite 更新失败: \{task.get_id()}") }
        }
      }
    }
  }
}

impl Store for SqliteStore with list_tasks(self) {
  let out : Array[Task] = []
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

impl Store for SqliteStore with delete_task(self, id) {
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
          ignore(stmt.bind(1, @sqlite.SqlValue::Text(@encoding.encode(UTF8, id))))
          let exec_ok = stmt.execute()
          stmt.finalize()
          if exec_ok { Ok(()) } else { Err("sqlite 删除失败: \{id}") }
        }
      }
    }
  }
}

impl Store for SqliteStore with clear(self) {
  match self.db {
    None => ()
    Some(db) => {
      ignore(db.exec("DELETE FROM tasks"))
      ignore(db.exec("DELETE FROM archive"))
    }
  }
}

/// 提升声明：允许通过具体类型直接调用 trait 方法。
pub extend SqliteStore with Store::{create_task, get_task, update_task, list_tasks, delete_task, clear}

// —— archive 快照（Phase 2/5 预置 API，不改变 Store trait）——

/// 将已归档任务写入 archive 表快照。
pub fn SqliteStore::archive_task(self : SqliteStore, t : Task, archived_at~ : String) -> Result[Unit, String] {
  match self.db {
    None => Err("sqlite store 未打开")
    Some(db) => {
      let sql = "INSERT OR REPLACE INTO archive (id, task_json, archived_at) VALUES (?, ?, ?)"
      match db.prepare(sql) {
        None => Err("sqlite prepare 失败: archive_task")
        Some(stmt) => {
          ignore(stmt.bind(1, @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.get_id()))))
          ignore(stmt.bind(2, @sqlite.SqlValue::Text(@encoding.encode(UTF8, t.to_json().stringify()))))
          ignore(stmt.bind(3, @sqlite.SqlValue::Text(@encoding.encode(UTF8, archived_at))))
          let exec_ok = stmt.execute()
          stmt.finalize()
          if exec_ok { Ok(()) } else { Err("sqlite 归档写入失败: \{t.get_id()}") }
        }
      }
    }
  }
}

/// 列出全部归档快照（id -> 原 task_json）。
pub fn SqliteStore::list_archived(self : SqliteStore) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  match self.db {
    None => out
    Some(db) => {
      match db.prepare("SELECT id, task_json FROM archive ORDER BY archived_at") {
        None => out
        Some(stmt) => {
          while stmt.step() {
            out.push((str_from_bytes(stmt.column_text(0)), str_from_bytes(stmt.column_text(1))))
          }
          stmt.finalize()
          out
        }
      }
    }
  }
}
