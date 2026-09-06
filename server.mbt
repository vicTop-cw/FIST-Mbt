/// FIST-Mbt MCP server: 暴露 10 tools + 2 resources + 2 prompts。
/// 接入 colmugx/mcp@0.17.4（2026-07-28 协议，Stdio/HTTP 双传输）。

/// —— 引擎（进程内共享的可变状态）——
/// 运行时优先接入 SQLite 内建数据库（本项目根目录 fist-mbt.db 持久化）；
/// 打开失败（如缺 libsqlite3）自动回退内存版，保证 server 总能启动。
fn make_engine() -> FistEngine {
  match SqliteStore::new() {
    Some(s) => FistEngine::new(store = StoreBackend::Sql(s))
    None => FistEngine::new()
  }
}

/// 使用模块级 var，handler 闭包内直接引用（全局变量无需显式捕获）。
let engine : FistEngine = make_engine()

/// 默认时间戳（无系统时钟依赖，保证 demo 可重现）
fn now_default() -> String { "2026-09-05T00:00:00Z" }

/// —— JSON schema 辅助 ——
fn string_prop(desc : String) -> Json {
  Json::object({
    "type": Json::string("string"),
    "description": Json::string(desc),
  })
}

fn int_prop(desc : String) -> Json {
  Json::object({
    "type": Json::string("integer"),
    "description": Json::string(desc),
  })
}

fn schema(props : Map[String, Json], required : Array[String]) -> Json {
  Json::object({
    "type": Json::string("object"),
    "properties": Json::object(props),
    "required": Json::array(required.map(fn(s) { Json::string(s) })),
  })
}

/// 从 JSON 参数中读取字符串，缺省回退默认值
fn get_str(args : Json, key : String, default~ : String = "") -> String {
  match args {
    Object(map) =>
      match map.get(key) {
        Some(String(s)) => s
        _ => default
      }
    _ => default
  }
}

/// 从 JSON 参数中读取整数，缺省回退默认值
fn get_int(args : Json, key : String, default~ : Int = 3) -> Int {
  match args {
    Object(map) =>
      match map.get(key) {
        Some(Number(n, ..)) => n.to_int()
        _ => default
      }
    _ => default
  }
}

/// —— 结果转换辅助 ——
fn to_result(r : Result[Task, String]) -> Result[@mcp.ToolResult, @mcp.MCPError] {
  match r {
    Ok(t) => Ok(@mcp.ToolResult::text(t.to_json().stringify()))
    Err(e) => Err(@mcp_types.ToolError(e))
  }
}

fn to_ids_result(
  r : Result[Array[String], String],
) -> Result[@mcp.ToolResult, @mcp.MCPError] {
  match r {
    Ok(ids) => Ok(@mcp.ToolResult::text(Json::array(
      ids.map(fn(s) { Json::string(s) }),
    ).stringify()))
    Err(e) => Err(@mcp_types.ToolError(e))
  }
}

fn to_unit_result(r : Result[Unit, String]) -> Result[@mcp.ToolResult, @mcp.MCPError] {
  match r {
    Ok(_) => Ok(@mcp.ToolResult::text("ok"))
    Err(e) => Err(@mcp_types.ToolError(e))
  }
}

/// —— overview 资源：任务统计概览 ——
fn overview_json() -> Json {
  let tasks = engine.list_all()
  let m : Map[String, Json] = Map([
    ("product", Json::string("FIST-Mbt")),
    ("version", Json::string("0.1.0")),
    ("principles", Json::number(7.0)),
    ("statuses", Json::string("待领取/已领取/拆分中/执行中/待验收/已完成/已归档")),
  ])
  let counts : Map[String, Json] = Map([])
  let status_names = [
    "待领取", "已领取", "拆分中", "执行中", "待验收", "已完成", "已归档",
  ]
  for s in status_names {
    counts.set(s, Json::number(
      tasks.filter(fn(t) { t.status_to_string() == s }).length().to_double(),
    ))
  }
  m.set("tasks_total", Json::number(tasks.length().to_double()))
  m.set("tasks_by_status", Json::object(counts))
  Json::object(m)
}

/// —— MCP server 构建与运行 ——
pub async fn run_server() -> Unit {
  let now = now_default()

  let s0 = @mcp.MCPServer::MCPServer("fist-mbt", "0.1.0")

  let s1 = s0
    // ---- tools ----
    .tool(
      "publish",
      "发布根任务（仅限人类指挥官）。参数：project_dir 项目目录、description 任务描述、created_by 创建者身份(默认 human_steward)。",
      schema(
        {
          "project_dir": string_prop("项目目录（必填）"),
          "description": string_prop("任务描述（必填）"),
          "created_by": string_prop("创建者身份(默认 human_steward)"),
          "now": string_prop("时间戳(可选，默认内置)"),
        },
        ["project_dir", "description"],
      ),
      async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
        let project_dir = get_str(args, "project_dir")
        let description = get_str(args, "description")
        let created_by = get_str(args, "created_by", default="human_steward")
        let ts = get_str(args, "now", default=now)
        let r = engine.publish(
          project_dir~,
          description~,
          created_by~,
          now=ts,
        )
        match r {
          Ok(id) => Ok(@mcp.ToolResult::text(
            Json::object({
              "task_id": Json::string(id),
              "message": Json::string("已发布根任务"),
            }).stringify(),
          ))
          Err(e) => Err(@mcp_types.ToolError(e))
        }
      },
    )
    .tool(
      "plan",
      "对指定任务拆分生成一层子任务（非原子任务才可拆）。参数：task_id 任务id、split_n 拆分数量(默认3)、by 执行者。",
      schema(
        {
          "task_id": string_prop("父任务 id（必填）"),
          "split_n": int_prop("拆分数量(默认3)"),
          "by": string_prop("执行拆分的人"),
          "now": string_prop("时间戳(可选)"),
        },
        ["task_id"],
      ),
      async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
        let task_id = get_str(args, "task_id")
        let split_n = get_int(args, "split_n", default=3)
        let by = get_str(args, "by", default="human_steward")
        let ts = get_str(args, "now", default=now)
        to_ids_result(engine.plan(
          task_id~,
          split_n~,
          by~,
          now=ts,
        ))
      },
    )
    .tool(
      "claim",
      "认领任务（待领取 -> 已领取；随后 execute 进入执行中）。参数：task_id、assignee 认领人。",
      schema(
        {
          "task_id": string_prop("任务 id（必填）"),
          "assignee": string_prop("认领人（必填）"),
          "now": string_prop("时间戳(可选)"),
        },
        ["task_id", "assignee"],
      ),
      async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
        let task_id = get_str(args, "task_id")
        let assignee = get_str(args, "assignee")
        let ts = get_str(args, "now", default=now)
        to_result(engine.claim(task_id~, assignee~, now=ts))
      },
    )
    .tool(
      "execute",
      "记录执行交付物。参数：task_id、deliverable 交付物描述。",
      schema(
        {
          "task_id": string_prop("任务 id（必填）"),
          "deliverable": string_prop("交付物描述（必填）"),
          "now": string_prop("时间戳(可选)"),
        },
        ["task_id", "deliverable"],
      ),
      async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
        let task_id = get_str(args, "task_id")
        let deliverable = get_str(args, "deliverable")
        let ts = get_str(args, "now", default=now)
        to_result(engine.execute(task_id~, deliverable~, now=ts))
      },
    )
    .tool(
      "submit",
      "提交验收（执行中 -> 待验收）。参数：task_id。",
      schema(
        {
          "task_id": string_prop("任务 id（必填）"),
          "now": string_prop("时间戳(可选)"),
        },
        ["task_id"],
      ),
      async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
        let task_id = get_str(args, "task_id")
        let ts = get_str(args, "now", default=now)
        to_result(engine.submit(task_id~, now=ts))
      },
    )
    .tool(
      "verify",
      "验收通过（待验收 -> 已完成，父任务自动上卷）。参数：task_id、verifier 验收人。",
      schema(
        {
          "task_id": string_prop("任务 id（必填）"),
          "verifier": string_prop("验收人（必填）"),
          "now": string_prop("时间戳(可选)"),
        },
        ["task_id", "verifier"],
      ),
      async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
        let task_id = get_str(args, "task_id")
        let verifier = get_str(args, "verifier")
        let ts = get_str(args, "now", default=now)
        to_result(engine.verify(task_id~, verifier~, now=ts))
      },
    )
    .tool(
      "archive",
      "归档任务（仅限人类指挥官）。参数：task_id、by 操作者。",
      schema(
        {
          "task_id": string_prop("任务 id（必填）"),
          "by": string_prop("操作者(默认 human_steward)"),
          "now": string_prop("时间戳(可选)"),
        },
        ["task_id"],
      ),
      async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
        let task_id = get_str(args, "task_id")
        let by = get_str(args, "by", default="human_steward")
        let ts = get_str(args, "now", default=now)
        to_result(engine.archive(task_id~, by~, now=ts))
      },
    )
    .tool(
      "list",
      "列出全部任务，可按状态过滤。参数：status(可选，中文状态名)。",
      schema(
        {
          "status": string_prop("按状态过滤(可选)：待领取/已领取/执行中/待验收/已完成/已归档"),
        },
        [],
      ),
      async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
        let status_str = get_str(args, "status")
        let tasks = if status_str == "" {
          engine.list_all()
        } else {
          match TaskStatus::from_string(status_str) {
            Some(st) => engine.list_by_status(st)
            None => return Err(@mcp_types.ToolError(
              "未知状态: \{status_str}",
            ))
          }
        }
        Ok(@mcp.ToolResult::text(Json::array(
          tasks.map(fn(t) { t.to_json() }),
        ).stringify()))
      },
    )
    .tool(
      "get",
      "查询单个任务详情。参数：task_id。",
      schema(
        {
          "task_id": string_prop("任务 id（必填）"),
        },
        ["task_id"],
      ),
      async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
        let task_id = get_str(args, "task_id")
        match engine.get_task(task_id) {
          Some(t) => Ok(@mcp.ToolResult::text(t.to_json().stringify()))
          None => Err(@mcp_types.ToolError("task not found: \{task_id}"))
        }
      },
    )
    .tool(
      "delete",
      "删除已归档任务。参数：task_id。",
      schema(
        {
          "task_id": string_prop("任务 id（必填，仅已归档可删）"),
        },
        ["task_id"],
      ),
      async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
        let task_id = get_str(args, "task_id")
        to_unit_result(engine.delete_task(task_id))
      },
    )

    // ---- resources ----
    .resource(
      "fist://principles",
      "FIST 七条金条",
      "FIST-Mbt 的七条不可动摇原则（机器可读 JSON）",
      "application/json",
      async fn() -> Result[@mcp_resource.ResourceReadResult, @mcp.MCPError] {
        Ok({
          uri: "fist://principles",
          content: @mcp_resource.ResourceContent::Text(
            principles_json().stringify(),
          ),
        })
      },
    )
    .resource(
      "fist://overview",
      "任务概览",
      "当前任务总数与各状态统计",
      "application/json",
      async fn() -> Result[@mcp_resource.ResourceReadResult, @mcp.MCPError] {
        Ok({
          uri: "fist://overview",
          content: @mcp_resource.ResourceContent::Text(
            overview_json().stringify(),
          ),
        })
      },
    )

    // ---- prompts ----
    .prompt(
      "fist:check_in",
      "任务打卡引导：认领/开工前的检查清单",
      [
        {
          name: "task_id",
          description: Some("要认领/开工的任务 id"),
          required: Some(true),
        },
      ],
      async fn(args : Json) -> Result[@mcp_types.GetPromptResult, @mcp.MCPError] {
        let task_id = get_str(args, "task_id")
        Ok({
          description: Some("FIST 任务打卡检查清单"),
          messages: [
            {
              role: "user",
              content: @mcp_types.ContentItem::Text(
                "请为任务 \{task_id} 打卡。检查：1) 我已确认任务描述与交付标准；2) 我使用 claim 认领、execute 记录交付物；3) 完成后用 submit 提交验收。",
              ),
            },
          ],
        })
      },
    )
    .prompt(
      "fist:verify",
      "验收引导：提交后的验收清单",
      [
        {
          name: "task_id",
          description: Some("要验收的任务 id"),
          required: Some(true),
        },
      ],
      async fn(args : Json) -> Result[@mcp_types.GetPromptResult, @mcp.MCPError] {
        let task_id = get_str(args, "task_id")
        Ok({
          description: Some("FIST 任务验收清单"),
          messages: [
            {
              role: "user",
              content: @mcp_types.ContentItem::Text(
                "请验收任务 \{task_id}。检查：1) 交付物是否满足描述标准；2) 使用 verify 通过；3) 通过后可用 archive 归档。",
              ),
            },
          ],
        })
      },
    )

  // run_stdio 内部 raise TransportError，入口捕获后退出
  s1.run_stdio() catch {
    e => println("fist-mbt server error: \{e}")
  }
}
