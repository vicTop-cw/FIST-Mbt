/// executions.mbt — executions 表 schema + CRUD。
///
/// 注意：moonbitlang/sqlite 的 SqlValue 仅支持 Text/Int，
/// 因此 cost 字段以 TEXT 存储（字符串化的浮点数），读回时 parse 为 Double。

///|
/// executions 表 CREATE TABLE SQL（使用 \n 避免跨行字面量）
pub fn executions_table_sql() -> String {
  "CREATE TABLE IF NOT EXISTS executions (\n    id TEXT PRIMARY KEY,\n    task_id TEXT NOT NULL DEFAULT '',\n    executor TEXT NOT NULL DEFAULT 'manual',\n    model TEXT NOT NULL DEFAULT '',\n    tokens_in INTEGER NOT NULL DEFAULT 0,\n    tokens_out INTEGER NOT NULL DEFAULT 0,\n    cost TEXT NOT NULL DEFAULT '0.0',\n    duration_ms INTEGER NOT NULL DEFAULT 0,\n    rate_limited INTEGER NOT NULL DEFAULT 0,\n    failure_reason TEXT NOT NULL DEFAULT '',\n    created_at TEXT NOT NULL DEFAULT ''\n)"
}

///|
/// 执行记录结构体
pub struct ExecutionRecord {
  id : String
  task_id : String
  executor : String
  model : String
  tokens_in : Int
  tokens_out : Int
  cost : Double
  duration_ms : Int
  rate_limited : Bool
  failure_reason : String
  created_at : String
}

///|
/// 初始化 executions 表
pub fn init_executions_table(db : @sqlite.Database) -> Bool {
  db.exec(executions_table_sql())
}

///|
/// 写入执行记录
pub fn insert_execution(
  db : @sqlite.Database,
  rec : ExecutionRecord,
) -> Result[Unit, String] {
  let sql = "INSERT INTO executions (id, task_id, executor, model, tokens_in, tokens_out, cost, duration_ms, rate_limited, failure_reason, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
  match db.prepare(sql) {
    None => Err("sqlite prepare 失败: insert_execution")
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
          @sqlite.SqlValue::Text(@encoding.encode(UTF8, rec.executor)),
        ),
      )
      ignore(
        stmt.bind(4, @sqlite.SqlValue::Text(@encoding.encode(UTF8, rec.model))),
      )
      ignore(stmt.bind(5, @sqlite.SqlValue::Int(rec.tokens_in)))
      ignore(stmt.bind(6, @sqlite.SqlValue::Int(rec.tokens_out)))
      // cost 以 TEXT 存储（SqlValue 不支持 Real）
      ignore(
        stmt.bind(
          7,
          @sqlite.SqlValue::Text(@encoding.encode(UTF8, rec.cost.to_string())),
        ),
      )
      ignore(stmt.bind(8, @sqlite.SqlValue::Int(rec.duration_ms)))
      ignore(
        stmt.bind(
          9,
          @sqlite.SqlValue::Int(if rec.rate_limited { 1 } else { 0 }),
        ),
      )
      ignore(
        stmt.bind(
          10,
          @sqlite.SqlValue::Text(@encoding.encode(UTF8, rec.failure_reason)),
        ),
      )
      ignore(
        stmt.bind(
          11,
          @sqlite.SqlValue::Text(@encoding.encode(UTF8, rec.created_at)),
        ),
      )
      let exec_ok = stmt.execute()
      stmt.finalize()
      if exec_ok {
        Ok(())
      } else {
        Err("sqlite 写入失败: \{rec.id}")
      }
    }
  }
}

///|
/// 列出全部执行记录（按 created_at DESC）
pub fn list_all_executions(db : @sqlite.Database) -> Array[ExecutionRecord] {
  let out : Array[ExecutionRecord] = []
  let sql = "SELECT id, task_id, executor, model, tokens_in, tokens_out, cost, duration_ms, rate_limited, failure_reason, created_at FROM executions ORDER BY created_at DESC"
  match db.prepare(sql) {
    None => out
    Some(stmt) => {
      while stmt.step() {
        out.push(row_to_execution(stmt))
      }
      stmt.finalize()
      out
    }
  }
}

///|
/// 聚合统计：总成本 / 总 token / 执行次数 / 按执行器分组
pub fn aggregate_stats(db : @sqlite.Database) -> Json {
  let records = list_all_executions(db)
  let mut total_cost : Double = 0.0
  let mut total_tokens_in : Int = 0
  let mut total_tokens_out : Int = 0
  let mut total_rate_limited : Int = 0
  let by_executor : Map[String, Json] = Map([])
  for rec in records {
    total_cost = total_cost + rec.cost
    total_tokens_in = total_tokens_in + rec.tokens_in
    total_tokens_out = total_tokens_out + rec.tokens_out
    if rec.rate_limited {
      total_rate_limited = total_rate_limited + 1
    }
    let key = rec.executor
    let existing = match by_executor.get(key) {
      Some(Object(m)) => m
      _ => Map([])
    }
    let count = match existing.get("count") {
      Some(Number(n, ..)) => n.to_int() + 1
      _ => 1
    }
    let cost_sum = match existing.get("cost") {
      Some(Number(n, ..)) => n + rec.cost
      _ => rec.cost
    }
    let new_m : Map[String, Json] = Map([
      ("count", Json::number(count.to_double())),
      ("cost", Json::number(cost_sum)),
    ])
    by_executor.set(key, Json::object(new_m))
  }
  Json::object({
    "total_records": Json::number(records.length().to_double()),
    "total_cost": Json::number(total_cost),
    "total_tokens_in": Json::number(total_tokens_in.to_double()),
    "total_tokens_out": Json::number(total_tokens_out.to_double()),
    "total_rate_limited": Json::number(total_rate_limited.to_double()),
    "by_executor": Json::object(by_executor),
  })
}

///|
fn row_to_execution(stmt : @sqlite.Statement) -> ExecutionRecord {
  let cost_str = str_from_stmt_text(stmt, 6)
  // 简单解析：取第一个 . 分隔的数字部分
  let cost = parse_simple_double(cost_str)
  ExecutionRecord::{
    id: str_from_stmt_text(stmt, 0),
    task_id: str_from_stmt_text(stmt, 1),
    executor: str_from_stmt_text(stmt, 2),
    model: str_from_stmt_text(stmt, 3),
    tokens_in: stmt.column_int(4),
    tokens_out: stmt.column_int(5),
    cost,
    duration_ms: stmt.column_int(7),
    rate_limited: stmt.column_int(8) != 0,
    failure_reason: str_from_stmt_text(stmt, 9),
    created_at: str_from_stmt_text(stmt, 10),
  }
}

///|
fn str_from_stmt_text(stmt : @sqlite.Statement, col : Int) -> String {
  str_from_bytes(stmt.column_text(col))
}

///|
/// 简单解析字符串为 Double（支持 "3.14" 格式）
fn parse_simple_double(s : String) -> Double {
  let mut integer_part : Int = 0
  let mut fractional_part : Int = 0
  let mut fractional_digits : Int = 0
  let mut found_dot : Bool = false
  let mut negative : Bool = false
  let mut i : Int = 0
  // 跳过前导空格
  while i < s.length() {
    let c = s[i]
    if c == ' ' {
      i = i + 1
    } else {
      break
    }
  }
  if i < s.length() && s[i] == '-' {
    negative = true
    i = i + 1
  }
  while i < s.length() {
    let c = s[i]
    if c >= '0' && c <= '9' {
      if found_dot {
        fractional_part = fractional_part * 10 + (c - '0').to_int()
        fractional_digits = fractional_digits + 1
      } else {
        integer_part = integer_part * 10 + (c - '0').to_int()
      }
      i = i + 1
    } else if c == '.' && !found_dot {
      found_dot = true
      i = i + 1
    } else {
      break
    }
  }
  let mut result : Double = integer_part.to_double()
  if fractional_digits > 0 {
    let mut divisor : Double = 1.0
    let mut j : Int = 0
    while j < fractional_digits {
      divisor = divisor * 10.0
      j = j + 1
    }
    result = result + fractional_part.to_double() / divisor
  }
  if negative {
    -result
  } else {
    result
  }
}
