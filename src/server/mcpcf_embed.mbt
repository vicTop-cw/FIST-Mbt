///
/// mcpconftest 嵌入层内置版（vendored from vicTop-cw/mcpconftest@e474d8c src/lib/fist_ops.mbt）。
/// serve 模式暴露 mcpcf.* 内部工具，复用本进程 FIST 引擎 API（@engine/@core）。
/// 七工具：ops_init / run_batch / verify / watchdog / report / circuit / review。
/// 数据隔离：默认 %LOCALAPPDATA%\mcpconftest\data\mcpconftest-ops.db，
/// 可用环境变量 MCPCONFTEST_DATA_DIR 覆盖（与 fist-mbt 主引擎库互不干扰）。

///|
/// 引擎持有者：内部可变性模式（MoonBit 顶层仅允许 let，可变状态放入 struct mut 字段）。
priv struct EngineHolder {
  mut engine : @engine.FistEngine?
}

///|
/// 模块级引擎（进程内共享的可变状态；handler 闭包直接引用）。
let holder : EngineHolder = { engine: None, }

///|
fn set_engine(e : @engine.FistEngine) -> Unit {
  holder.engine = Some(e)
}

///|
fn get_engine() -> @engine.FistEngine? {
  holder.engine
}

///|
/// 解析运行时数据目录：优先 MCPCONFTEST_DATA_DIR，其次 LOCALAPPDATA，最后 cwd。
fn ops_data_dir() -> String {
  match @env.get_env_var("MCPCONFTEST_DATA_DIR") {
    Some(d) => d
    None =>
      match @env.get_env_var("LOCALAPPDATA") {
        Some(base) => base + "\\mcpconftest\\data"
        None => "./mcpconftest-data"
      }
  }
}

///|
/// 确保引擎已初始化：优先 SQLite（mcpconftest-ops.db），失败回退内存版。
fn ensure_engine() -> @engine.FistEngine {
  match get_engine() {
    Some(e) => e
    None => {
      let dir = ops_data_dir()
      let db_path = dir + "\\mcpconftest-ops.db"
      // 数据目录不存在时先创建（幂等，失败不影响后续打开尝试）
      @fs.create_dir(dir) catch {
        _ => ()
      }
      let e = match @engine.FistEngine::open_sqlite(db_path) {
        Some(x) => x
        None => @engine.FistEngine::new()
      }
      set_engine(e)
      e
    }
  }
}

///|
/// 重置引擎（ops_init 强制重开 / 测试隔离用）。
fn reset_engine() -> Unit {
  holder.engine = None
}

///|
/// 当前 UTC 时间戳（YYYY-MM-DDTHH:MM:SSZ），供 publish/verify 等 now~ 参数使用。
fn now_utc() -> String {
  let ms = @env.now().reinterpret_as_int64()
  let total_sec = ms / 1000L
  let sec = (total_sec % 60L).to_int()
  let min = (total_sec / 60L % 60L).to_int()
  let hour = (total_sec / 3600L % 24L).to_int()
  let days = (total_sec / 86400L).to_int()
  let (y, m, d) = fist_civil_from_days(days)
  "\{y}-\{fist_pad2(m)}-\{fist_pad2(d)}T\{fist_pad2(hour)}:\{fist_pad2(min)}:\{fist_pad2(sec)}Z"
}

///|
fn fist_pad2(n : Int32) -> String {
  let s = n.to_string()
  if s.length() == 1 {
    "0" + s
  } else {
    s
  }
}

///|
fn fist_civil_from_days(z : Int32) -> (Int32, Int32, Int32) {
  let z0 = z + 719468
  let era = z0 / 146097
  let doe = z0 - era * 146097
  let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  let y = yoe + era * 400
  let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
  let mp = (5 * doy + 2) / 153
  let d = doy - (153 * mp + 2) / 5 + 1
  let m = if mp < 10 { mp + 3 } else { mp - 9 }
  (if m <= 2 { y + 1 } else { y }, m, d)
}

///|
/// 工具参数读取：字符串字段。
fn arg_str(args : Json, key : String, default : String) -> String {
  match args {
    Object(m) =>
      match m.get(key) {
        Some(String(s)) => s
        _ => default
      }
    _ => default
  }
}

///|
/// 工具参数读取：可空字符串字段（None 表示未传）。
fn arg_str_opt(args : Json, key : String) -> String? {
  match args {
    Object(m) =>
      match m.get(key) {
        Some(String(s)) => Some(s)
        _ => None
      }
    _ => None
  }
}

///|
/// 工具参数读取：布尔字段。
fn arg_bool(args : Json, key : String, default : Bool) -> Bool {
  match args {
    Object(m) =>
      match m.get(key) {
        Some(True) => true
        Some(False) => false
        _ => default
      }
    _ => default
  }
}

///|
/// 构造成功 JSON 文本结果。
fn ok_text(m : Map[String, Json]) -> @mcp.ToolResult {
  @mcp.ToolResult::text(Json::object(m).stringify())
}

///|
/// 构造失败文本结果。
fn err_text(msg : String) -> @mcp.ToolResult {
  @mcp.ToolResult::text(Json::string("ERROR: " + msg).stringify())
}

///|
/// 任务列表转 JSON 数组（精简字段）。
fn tasks_json(tasks : Array[@core.Task]) -> Json {
  let arr = tasks.map(fn(t) {
    let m : Map[String, Json] = Map([])
    m.set("id", Json::string(t.get_id()))
    m.set("status", Json::string(t.get_status().to_string()))
    m.set("description", Json::string(t.get_description()))
    m.set("depth", Json::number(t.get_depth().to_double()))
    m.set("updated_at", Json::string(t.get_updated_at()))
    Json::object(m)
  })
  Json::array(arr)
}

///|
/// 初始化 FIST 引擎（SQLite 优先，内存回退）。参数：data_dir（可选，覆盖默认数据目录）。
fn tool_ops_init(args : Json) -> @mcp.ToolResult {
  let data_dir_opt = arg_str_opt(args, "data_dir")
  match data_dir_opt {
    Some(d) => {
      // 显式数据目录：重置并注入环境变量语义（通过局部覆盖）
      reset_engine()
      let db_path = d + "\\mcpconftest-ops.db"
      @fs.create_dir(d) catch {
        _ => ()
      }
      let e = match @engine.FistEngine::open_sqlite(db_path) {
        Some(x) => x
        None => @engine.FistEngine::new()
      }
      set_engine(e)
      let m : Map[String, Json] = Map([])
      m.set("ok", Json::boolean(true))
      m.set("backend", Json::string(e.heartbeat_backend()))
      m.set("db", Json::string(db_path))
      ok_text(m)
    }
    None => {
      let e = ensure_engine()
      let m : Map[String, Json] = Map([])
      m.set("ok", Json::boolean(true))
      m.set("backend", Json::string(e.heartbeat_backend()))
      m.set("db", Json::string(ops_data_dir() + "\\mcpconftest-ops.db"))
      ok_text(m)
    }
  }
}

///|
/// 发布根任务（一次巡检批次）。参数：project_dir / description / created_by / ns（可选）。
fn tool_run_batch(args : Json) -> @mcp.ToolResult {
  let e = ensure_engine()
  let project_dir = arg_str(args, "project_dir", "")
  let description = arg_str(args, "description", "")
  let created_by = arg_str(args, "created_by", "human_steward")
  let ns = arg_str(args, "ns", "default")
  if project_dir.is_empty() || description.is_empty() {
    return err_text("run_batch requires project_dir and description")
  }
  match e.publish(project_dir~, description~, created_by~, now=now_utc(), ns~) {
    Ok(id) => {
      let m : Map[String, Json] = Map([])
      m.set("ok", Json::boolean(true))
      m.set("task_id", Json::string(id))
      m.set("ns", Json::string(ns))
      ok_text(m)
    }
    Err(err) => err_text(err)
  }
}

///|
/// 验收任务。参数：task_id / verifier / docs_check（可选）。
fn tool_verify(args : Json) -> @mcp.ToolResult {
  let e = ensure_engine()
  let task_id = arg_str(args, "task_id", "")
  let verifier = arg_str(args, "verifier", "mcpconftest")
  if task_id.is_empty() {
    return err_text("verify requires task_id")
  }
  match
    e.verify(
      task_id~,
      verifier~,
      now=now_utc(),
      docs_check=arg_bool(args, "docs_check", false),
    ) {
    Ok(t) => {
      let m : Map[String, Json] = Map([])
      m.set("ok", Json::boolean(true))
      m.set("task_id", Json::string(t.get_id()))
      m.set("status", Json::string(t.get_status().to_string()))
      ok_text(m)
    }
    Err(err) => err_text(err)
  }
}

///|
/// 熔断状态查询/操作。参数：circuit / action(status|fail|succeed) / ns（可选）。
fn tool_circuit(args : Json) -> @mcp.ToolResult {
  let e = ensure_engine()
  let circuit = arg_str(args, "circuit", "")
  if circuit.is_empty() {
    return err_text("circuit requires circuit name")
  }
  let ns = arg_str(args, "ns", "default")
  let action = arg_str(args, "action", "status")
  let now_secs = (@env.now().reinterpret_as_int64() / 1000L).to_int()
  let json = if action == "fail" {
    e.circuit_fail(ns~, circuit~, now_secs~)
  } else if action == "succeed" {
    e.circuit_succeed(ns~, circuit~, now_secs~)
  } else {
    e.circuit_status(ns~, circuit~, now_secs~)
  }
  @mcp.ToolResult::text(json.stringify())
}

///|
/// 生成巡检任务报告。参数：ns（可选，默认 default）。
fn tool_report(args : Json) -> @mcp.ToolResult {
  let e = ensure_engine()
  let ns = arg_str(args, "ns", "default")
  let tasks = e.list_in_ns(ns)
  let counts : Map[String, Int32] = Map([])
  for t in tasks {
    let st = t.get_status().to_string()
    let cur = match counts.get(st) {
      Some(x) => x
      None => 0
    }
    counts.set(st, cur + 1)
  }
  let summary : Map[String, Json] = Map([])
  for (st, cnt) in counts {
    summary.set(st, Json::number(cnt.to_double()))
  }
  let m : Map[String, Json] = Map([])
  m.set("ok", Json::boolean(true))
  m.set("ns", Json::string(ns))
  m.set("total", Json::number(tasks.length().to_double()))
  m.set("by_status", Json::object(summary))
  m.set("tasks", tasks_json(tasks))
  ok_text(m)
}

///|
/// 审查任务。参数：task_id（可选；不传则按 status 过滤或全量）。
fn tool_review(args : Json) -> @mcp.ToolResult {
  let e = ensure_engine()
  match arg_str_opt(args, "task_id") {
    Some(tid) =>
      match e.get_task(tid) {
        Some(t) => {
          let m : Map[String, Json] = Map([])
          m.set("ok", Json::boolean(true))
          m.set(
            "task",
            Json::object({
              "id": Json::string(t.get_id()),
              "status": Json::string(t.get_status().to_string()),
              "description": Json::string(t.get_description()),
              "depth": Json::number(t.get_depth().to_double()),
              "updated_at": Json::string(t.get_updated_at()),
            }),
          )
          ok_text(m)
        }
        None => err_text("task not found: " + tid)
      }
    None => {
      let status = arg_str(args, "status", "")
      let tasks = if status.is_empty() {
        e.list_all()
      } else {
        match @core.TaskStatus::from_string(status) {
          Some(st) => e.list_by_status(st)
          None => return err_text("unknown status: " + status)
        }
      }
      let m : Map[String, Json] = Map([])
      m.set("ok", Json::boolean(true))
      m.set("count", Json::number(tasks.length().to_double()))
      m.set("tasks", tasks_json(tasks))
      ok_text(m)
    }
  }
}

///|
/// 看护检查：引擎后端 + 心跳 + 熔断快照。参数：circuit（可选，同时查熔断）。
fn tool_watchdog(args : Json) -> @mcp.ToolResult {
  let e = ensure_engine()
  let m : Map[String, Json] = Map([])
  m.set("ok", Json::boolean(true))
  m.set("backend", Json::string(e.heartbeat_backend()))
  m.set("task_count", Json::number(e.list_all().length().to_double()))
  match arg_str_opt(args, "circuit") {
    Some(c) => {
      let ns = arg_str(args, "ns", "default")
      let now_secs = (@env.now().reinterpret_as_int64() / 1000L).to_int()
      m.set("circuit", e.circuit_status(ns~, circuit=c, now_secs~))
    }
    None => ()
  }
  ok_text(m)
}

///|
/// 注册 mcpcf.* 内部工具到现有 server（链式调用，返回扩展后的 server）。
pub fn embed_mcpcf_tools(s : @mcp.MCPServer) -> @mcp.MCPServer {
  let s1 = s.tool(
    "mcpcf.ops_init",
    "Initialize the embedded FIST engine (SQLite preferred, memory fallback). Parameters: data_dir (optional, overrides MCPCONFTEST_DATA_DIR). Returns backend and db path.",
    Json::object({
      "type": Json::string("object"),
      "properties": Json::object({
        "data_dir": Json::object({
          "type": Json::string("string"),
          "description": Json::string(
            "Optional data directory; defaults to MCPCONFTEST_DATA_DIR or %LOCALAPPDATA%\\mcpconftest\\data",
          ),
        }),
      }),
    }),
    fn(args : Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError] {
      Ok(tool_ops_init(args))
    },
  )
  let s2 = s1.tool(
    "mcpcf.run_batch",
    "Publish a root inspection batch task to the embedded FIST engine. Parameters: project_dir, description, created_by (default human_steward), ns (default default). Returns the new task id.",
    Json::object({
      "type": Json::string("object"),
      "properties": Json::object({
        "project_dir": Json::object({
          "type": Json::string("string"),
          "description": Json::string("Project directory for this batch"),
        }),
        "description": Json::object({
          "type": Json::string("string"),
          "description": Json::string("Batch description"),
        }),
        "created_by": Json::object({
          "type": Json::string("string"),
          "description": Json::string(
            "Creator role; must be human_steward or human",
          ),
        }),
        "ns": Json::object({
          "type": Json::string("string"),
          "description": Json::string("Namespace (default default)"),
        }),
      }),
    }),
    fn(args : Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError] {
      Ok(tool_run_batch(args))
    },
  )
  let s3 = s2.tool(
    "mcpcf.verify",
    "Verify (accept) a task in the embedded FIST engine. Parameters: task_id, verifier (default mcpconftest), docs_check (optional boolean).",
    Json::object({
      "type": Json::string("object"),
      "properties": Json::object({
        "task_id": Json::object({
          "type": Json::string("string"),
          "description": Json::string("Task id to verify"),
        }),
        "verifier": Json::object({
          "type": Json::string("string"),
          "description": Json::string("Verifier name"),
        }),
        "docs_check": Json::object({
          "type": Json::string("boolean"),
          "description": Json::string("Run docs gate during verification"),
        }),
      }),
    }),
    fn(args : Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError] {
      Ok(tool_verify(args))
    },
  )
  let s4 = s3.tool(
    "mcpcf.circuit",
    "Query or operate a circuit breaker in the embedded FIST engine. Parameters: circuit, action (status|fail|succeed), ns (default default).",
    Json::object({
      "type": Json::string("object"),
      "properties": Json::object({
        "circuit": Json::object({
          "type": Json::string("string"),
          "description": Json::string("Circuit name"),
        }),
        "action": Json::object({
          "type": Json::string("string"),
          "description": Json::string("status (default), fail, or succeed"),
        }),
        "ns": Json::object({
          "type": Json::string("string"),
          "description": Json::string("Namespace (default default)"),
        }),
      }),
    }),
    fn(args : Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError] {
      Ok(tool_circuit(args))
    },
  )
  let s5 = s4.tool(
    "mcpcf.report",
    "Generate an inspection task report from the embedded FIST engine. Parameters: ns (default default). Returns per-status counts and task list.",
    Json::object({
      "type": Json::string("object"),
      "properties": Json::object({
        "ns": Json::object({
          "type": Json::string("string"),
          "description": Json::string("Namespace (default default)"),
        }),
      }),
    }),
    fn(args : Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError] {
      Ok(tool_report(args))
    },
  )
  let s6 = s5.tool(
    "mcpcf.review",
    "Review tasks in the embedded FIST engine. Parameters: task_id (optional), status (optional; list tasks by status), or omit both to list all tasks.",
    Json::object({
      "type": Json::string("object"),
      "properties": Json::object({
        "task_id": Json::object({
          "type": Json::string("string"),
          "description": Json::string("Specific task id to inspect"),
        }),
        "status": Json::object({
          "type": Json::string("string"),
          "description": Json::string(
            "Filter by status, e.g. 待领取/执行中/已完成",
          ),
        }),
      }),
    }),
    fn(args : Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError] {
      Ok(tool_review(args))
    },
  )
  let s7 = s6.tool(
    "mcpcf.watchdog",
    "Watchdog health check of the embedded FIST engine. Parameters: circuit (optional, include circuit status), ns (default default). Returns backend, task count, optional circuit state.",
    Json::object({
      "type": Json::string("object"),
      "properties": Json::object({
        "circuit": Json::object({
          "type": Json::string("string"),
          "description": Json::string("Optional circuit name to report"),
        }),
        "ns": Json::object({
          "type": Json::string("string"),
          "description": Json::string("Namespace (default default)"),
        }),
      }),
    }),
    fn(args : Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError] {
      Ok(tool_watchdog(args))
    },
  )
  s7
}
