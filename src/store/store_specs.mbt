/// store/specs.mbt — specs 表 schema + CRUD（Omega 强验证语料账本）。
///
/// 表结构沿用 store_sqlite.mbt create_schema 中的既有定义（Phase 2 预置骨架），
/// 本文件把它升级为真正可读写的语料账本：
///   specs (id TEXT PRIMARY KEY, task_id, spec_type, content, status, created_at, updated_at)
///
/// 约定：
///   spec_type = "spec"       执行前语料（语料创建者编写、验证者审核）
///   spec_type = "result"     成果复验记录（验证者对执行成果的复验）
///   spec_type = "escalation" 打回超限升级记录（转人工）
///   status    ∈ pending / approved / rejected / escalated

///|
/// specs 表 CREATE TABLE SQL（幂等，兼容旧库）。
pub fn specs_table_sql() -> String {
  "CREATE TABLE IF NOT EXISTS specs (id TEXT PRIMARY KEY, task_id TEXT NOT NULL DEFAULT '', spec_type TEXT NOT NULL DEFAULT 'spec', content TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'pending', created_at TEXT NOT NULL DEFAULT '', updated_at TEXT NOT NULL DEFAULT '')"
}

///|
/// 语料 / 复验记录（跨后端统一结构）。
pub struct SpecRecord {
  pub id : String
  pub task_id : String
  pub spec_type : String
  pub content : String
  pub status : String
  pub created_at : String
  pub updated_at : String
} derive(Eq, Debug)

///|
/// 便捷构造（仅 id / task_id 必填，其余带默认值）。
pub fn SpecRecord::new(
  id~ : String,
  task_id~ : String,
  spec_type? : String = "spec",
  content? : String = "",
  status? : String = "pending",
  created_at? : String = "",
  updated_at? : String = "",
) -> SpecRecord {
  { id, task_id, spec_type, content, status, created_at, updated_at, }
}

///|
/// 记录转 JSON（供 MCP 工具输出，content 不展开以免撑爆响应）。
pub fn SpecRecord::to_json(self : SpecRecord) -> Json {
  Json::object({
    "id": Json::string(self.id),
    "task_id": Json::string(self.task_id),
    "spec_type": Json::string(self.spec_type),
    "status": Json::string(self.status),
    "created_at": Json::string(self.created_at),
    "updated_at": Json::string(self.updated_at),
  })
}

// —— SQLite 后端 ——

///|
/// 确保 specs 表存在（幂等；旧库自动补齐）。
pub fn SqliteStore::ensure_specs_table(self : SqliteStore) -> Bool {
  match self.db {
    None => false
    Some(db) => db.exec(specs_table_sql())
  }
}

///|
/// 写入 / 覆盖一条语料记录（UPSERT，主键 id）。
pub fn SqliteStore::upsert_spec(
  self : SqliteStore,
  rec : SpecRecord,
) -> Result[Unit, String] {
  match self.db {
    None => Err("sqlite store 未打开")
    Some(db) => {
      ignore(self.ensure_specs_table())
      let sql = "INSERT INTO specs (id, task_id, spec_type, content, status, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET task_id=excluded.task_id, spec_type=excluded.spec_type, content=excluded.content, status=excluded.status, updated_at=excluded.updated_at"
      match db.prepare(sql) {
        None => Err("sqlite prepare 失败: upsert_spec")
        Some(stmt) => {
          ignore(
            stmt.bind(1, @sqlite.SqlValue::Text(@encoding.encode(UTF8, rec.id))),
          )
          ignore(
            stmt.bind(
              2,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, rec.task_id)),
            ),
          )
          ignore(
            stmt.bind(
              3,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, rec.spec_type)),
            ),
          )
          ignore(
            stmt.bind(
              4,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, rec.content)),
            ),
          )
          ignore(
            stmt.bind(
              5,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, rec.status)),
            ),
          )
          ignore(
            stmt.bind(
              6,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, rec.created_at)),
            ),
          )
          ignore(
            stmt.bind(
              7,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, rec.updated_at)),
            ),
          )
          let exec_ok = stmt.execute()
          stmt.finalize()
          if exec_ok {
            Ok(())
          } else {
            Err("sqlite 写入语料失败: \{rec.id}")
          }
        }
      }
    }
  }
}

///|
/// 按 id 读取单条语料记录。
pub fn SqliteStore::get_spec(self : SqliteStore, id : String) -> SpecRecord? {
  match self.db {
    None => None
    Some(db) => {
      let sql = "SELECT id, task_id, spec_type, content, status, created_at, updated_at FROM specs WHERE id = ?"
      match db.prepare(sql) {
        None => None
        Some(stmt) => {
          ignore(
            stmt.bind(1, @sqlite.SqlValue::Text(@encoding.encode(UTF8, id))),
          )
          let found = if stmt.step() { Some(row_to_spec(stmt)) } else { None }
          stmt.finalize()
          found
        }
      }
    }
  }
}

///|
/// 列出某任务的全部语料 / 复验记录（按 created_at、id 升序）。
pub fn SqliteStore::list_specs_by_task(
  self : SqliteStore,
  task_id : String,
) -> Array[SpecRecord] {
  let out : Array[SpecRecord] = []
  match self.db {
    None => out
    Some(db) => {
      ignore(self.ensure_specs_table())
      let sql = "SELECT id, task_id, spec_type, content, status, created_at, updated_at FROM specs WHERE task_id = ? ORDER BY created_at ASC, id ASC"
      match db.prepare(sql) {
        None => out
        Some(stmt) => {
          ignore(
            stmt.bind(
              1,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, task_id)),
            ),
          )
          while stmt.step() {
            out.push(row_to_spec(stmt))
          }
          stmt.finalize()
          out
        }
      }
    }
  }
}

///|
/// 更新语料状态（可同时更新内容与时间戳）。
pub fn SqliteStore::update_spec_status(
  self : SqliteStore,
  id : String,
  status : String,
  content : String,
  updated_at : String,
) -> Result[Unit, String] {
  match self.db {
    None => Err("sqlite store 未打开")
    Some(db) => {
      let sql = "UPDATE specs SET status = ?, content = ?, updated_at = ? WHERE id = ?"
      match db.prepare(sql) {
        None => Err("sqlite prepare 失败: update_spec_status")
        Some(stmt) => {
          ignore(
            stmt.bind(1, @sqlite.SqlValue::Text(@encoding.encode(UTF8, status))),
          )
          ignore(
            stmt.bind(
              2,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, content)),
            ),
          )
          ignore(
            stmt.bind(
              3,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, updated_at)),
            ),
          )
          ignore(
            stmt.bind(4, @sqlite.SqlValue::Text(@encoding.encode(UTF8, id))),
          )
          let exec_ok = stmt.execute()
          stmt.finalize()
          if exec_ok {
            Ok(())
          } else {
            Err("sqlite 更新语料失败: \{id}")
          }
        }
      }
    }
  }
}

// —— 行反序列化 ——

///|
/// 结果行 -> SpecRecord（列序与 SELECT 语句一致）。
fn row_to_spec(stmt : @sqlite.Statement) -> SpecRecord {
  {
    id: str_from_bytes(stmt.column_text(0)),
    task_id: str_from_bytes(stmt.column_text(1)),
    spec_type: str_from_bytes(stmt.column_text(2)),
    content: str_from_bytes(stmt.column_text(3)),
    status: str_from_bytes(stmt.column_text(4)),
    created_at: str_from_bytes(stmt.column_text(5)),
    updated_at: str_from_bytes(stmt.column_text(6)),
  }
}
