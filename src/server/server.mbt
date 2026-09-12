/// FIST-Mbt MCP server: 暴露 14 tools + 2 resources + 2 prompts。
/// 接入 colmugx/mcp@0.17.4（2026-07-28 协议，Stdio/HTTP 双传输）。

/// —— 引擎（进程内共享的可变状态）——
/// 运行时优先接入 SQLite 内建数据库（本项目根目录 fist-mbt.db 持久化）；
/// 打开失败（如缺 libsqlite3）自动回退内存版，保证 server 总能启动。
fn make_engine() -> @engine.FistEngine {
  match @store.SqliteStore::new() {
    Some(s) => @engine.FistEngine::new(store = @store.StoreBackend::sqlite(s))
    None => @engine.FistEngine::new()
  }
}

/// 使用模块级 var，handler 闭包内直接引用（全局变量无需显式捕获）。
let engine : @engine.FistEngine = make_engine()

/// 模块级心跳登记表（M4 运维：ActivityState / no_signal watchdog）。
let heartbeats : @ops.Heartbeat = @ops.Heartbeat::new()

/// 模块级追加式审计日志（M5 治理：人类主权 + 追加式审计）。
let audit : @ops.AuditLog = @ops.AuditLog::new()

/// 模块级多库管理器（M5 多租户：namespace 隔离的持久化，内部可变性模式）。
let mstore : @store.MultiStore = @store.MultiStore::new(data_dir=".")

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
fn to_result(r : Result[@core.Task, String]) -> Result[@mcp.ToolResult, @mcp.MCPError] {
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
      "发布根任务（仅限人类指挥官）。参数：project_dir 项目目录、description 任务描述、namespace 命名空间(默认 default)、created_by 创建者身份(默认 human_steward)。",
      schema(
        {
          "project_dir": string_prop("项目目录（必填）"),
          "description": string_prop("任务描述（必填）"),
          "namespace": string_prop("命名空间(默认 default)"),
          "created_by": string_prop("创建者身份(默认 human_steward)"),
          "now": string_prop("时间戳(可选，默认内置)"),
        },
        ["project_dir", "description"],
      ),
      async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
        let project_dir = get_str(args, "project_dir")
        let description = get_str(args, "description")
        let ns = get_str(args, "namespace", default="default")
        let created_by = get_str(args, "created_by", default="human_steward")
        let ts = get_str(args, "now", default=now)
        let r = engine.publish(
          project_dir~,
          description~,
          created_by~,
          now=ts,
          ns=ns,
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
      "reject",
      "验收拒绝（待验收 -> 已打回）。参数：task_id、reason 打回原因、by 操作者。",
      schema(
        {
          "task_id": string_prop("任务 id（必填）"),
          "reason": string_prop("打回原因（可选）"),
          "by": string_prop("操作者(默认 human_steward)"),
          "now": string_prop("时间戳(可选)"),
        },
        ["task_id"],
      ),
      async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
        let task_id = get_str(args, "task_id")
        let reason = get_str(args, "reason", default="")
        let by = get_str(args, "by", default="human_steward")
        let ts = get_str(args, "now", default=now)
        to_result(engine.reject_task(task_id~, reason=reason, by=by, now=ts))
      },
    )
    .tool(
      "retry",
      "打回后重试（已打回 -> 执行中）。参数：task_id。",
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
        to_result(engine.retry_task(task_id~, now=ts))
      },
    )
    .tool(
      "pause",
      "暂停任务（任意活跃状态 -> 已暂停）。参数：task_id。",
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
        to_result(engine.pause_task(task_id~, now=ts))
      },
    )
    .tool(
      "resume",
      "恢复任务（已暂停 -> 已领取）。参数：task_id。",
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
        to_result(engine.resume_task(task_id~, now=ts))
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
          match @core.TaskStatus::from_string(status_str) {
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
    .tool(
      "task_plan_deep",
      "AO 式递归拆解：对指定任务拆出整棵多层子任务树并写库。参数：task_id 任务id、split_n 每层默认拆分数(默认3)、by 拆解拳长、spec 可选 omega spec JSON(laws 作切割依据、fingerprint 作验收基准)、now 时间戳。",
      schema(
        {
          "task_id": string_prop("父任务 id（必填，非原子任务）"),
          "split_n": int_prop("每层默认拆分数(默认3，有 spec.laws 时以 laws 为准)"),
          "by": string_prop("执行拆解的拳长身份(默认 leader)"),
          "spec": string_prop("可选 omega spec JSON 字符串"),
          "now": string_prop("时间戳(可选)"),
        },
        ["task_id"],
      ),
      async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
        let task_id = get_str(args, "task_id")
        let split_n = get_int(args, "split_n", default=3)
        let by = get_str(args, "by", default="leader")
        let spec_raw = get_str(args, "spec")
        let ts = get_str(args, "now", default=now)
        let spec : Json? = if spec_raw == "" {
          None
        } else {
          try {
            Some(@json.parse(spec_raw))
          } catch {
            _ => return Err(@mcp_types.ToolError("spec 不是合法 JSON"))
          }
        }
        match engine.plan_deep(
          task_id~,
          split_n~,
          by~,
          spec=spec,
          now=ts,
        ) {
          Ok(j) => Ok(@mcp.ToolResult::text(j.stringify()))
          Err(e) => Err(@mcp_types.ToolError(e))
        }
      },
    )
    .tool(
      "conflicts_check",
      "claim 冲突检测（AO --no-takeover）：认领前检查任务是否已被他人/本人持有。参数：task_id、assignee。",
      schema(
        {
          "task_id": string_prop("任务 id（必填）"),
          "assignee": string_prop("拟认领人（必填）"),
        },
        ["task_id", "assignee"],
      ),
      async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
        let task_id = get_str(args, "task_id")
        let assignee = get_str(args, "assignee")
        match @ops.check_claim(engine, task_id, assignee) {
          Ok(_) => Ok(@mcp.ToolResult::text(Json::object({
            "task_id": Json::string(task_id),
            "assignee": Json::string(assignee),
            "ok": Json::boolean(true),
            "message": Json::string("可安全认领（待领取）"),
          }).stringify()))
          Err(e) => Err(@mcp_types.ToolError(e))
        }
      },
    )
    .tool(
      "heartbeat",
      "活动信号上报（AO ActivityState）：任务执行前/执行中周期性上报，超时静默将触发 heal 回滚。参数：task_id、signal(可选默认 active)、now。",
      schema(
        {
          "task_id": string_prop("任务 id（必填）"),
          "signal": string_prop("信号(可选)：pre-execution/active/submit，默认 active"),
          "now": string_prop("时间戳(可选，默认内置)"),
        },
        ["task_id"],
      ),
      async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
        let task_id = get_str(args, "task_id")
        let signal = get_str(args, "signal", default="active")
        let ts = get_str(args, "now", default=now)
        match engine.get_task(task_id) {
          None => Err(@mcp_types.ToolError("task not found: \{task_id}"))
          Some(_) => {
            heartbeats.beat(task_id, signal~, now=ts)
            Ok(@mcp.ToolResult::text(Json::object({
              "task_id": Json::string(task_id),
              "signal": Json::string(signal),
              "last_seen": Json::string(heartbeats.last_seen_of(task_id)),
            }).stringify()))
          }
        }
      },
    )
    .tool(
      "heal",
      "no_signal 看护（AO watchdog）：心跳超时静默的活跃任务（执行中/已领取/拆分中）回滚为已领取待重派。参数：now、timeout_sec(可选默认600)。",
      schema(
        {
          "now": string_prop("当前时间戳(默认内置)"),
          "timeout_sec": int_prop("超时秒数(可选默认600)"),
        },
        [],
      ),
      async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
        let ts = get_str(args, "now", default=now)
        let timeout_sec = get_int(args, "timeout_sec", default=600)
        match @ops.heal_stale_tasks(engine, heartbeats, ts, timeout_sec=timeout_sec) {
          Ok(healed) => Ok(@mcp.ToolResult::text(Json::object({
            "healed": Json::array(healed.map(fn(s) { Json::string(s) })),
            "count": Json::number(healed.length().to_double()),
            "message": Json::string("超时静默任务已回滚待重派"),
          }).stringify()))
          Err(e) => Err(@mcp_types.ToolError(e))
        }
      },
    )
    .tool(
      "task_cleanup",
      "归档清理：删除超过保留期的已归档任务。参数：now、retention_days(可选默认30)。",
      schema(
        {
          "now": string_prop("当前时间戳(默认内置)"),
          "retention_days": int_prop("归档保留天数(可选默认30)"),
        },
        [],
      ),
      async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
        let ts = get_str(args, "now", default=now)
        let retention_days = get_int(args, "retention_days", default=30)
        match @ops.cleanup_archived(engine, ts, retention_days=retention_days) {
          Ok(removed) => Ok(@mcp.ToolResult::text(Json::object({
            "removed": Json::array(removed.map(fn(s) { Json::string(s) })),
            "count": Json::number(removed.length().to_double()),
            "message": Json::string("已清理过期归档任务"),
          }).stringify()))
          Err(e) => Err(@mcp_types.ToolError(e))
        }
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
            @core.principles_json().stringify(),
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
    .tool(
      "dag_publish",
      "发布带依赖关系的根任务。参数：project_dir、description、depends_on(依赖任务 id JSON 数组)、namespace、created_by、now。",
      schema(
        {
          "project_dir": string_prop("项目目录（必填）"),
          "description": string_prop("任务描述（必填）"),
          "depends_on": string_prop("依赖任务 id 列表 JSON 数组(可选)"),
          "namespace": string_prop("命名空间(默认 default)"),
          "created_by": string_prop("创建者身份(默认 human_steward)"),
          "now": string_prop("时间戳(可选)"),
        },
        ["project_dir", "description"],
      ),
      async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
        let project_dir = get_str(args, "project_dir")
        let description = get_str(args, "description")
        let depends_on_raw = get_str(args, "depends_on", default="[]")
        let ns = get_str(args, "namespace", default="default")
        let created_by = get_str(args, "created_by", default="human_steward")
        let ts = get_str(args, "now", default=now)
        let depends_on : Array[String] = try {
          match @json.parse(depends_on_raw) {
            Json::Array(a) => a.map(fn(v) { v.as_string().unwrap_or("") })
            _ => []
          }
        } catch {
          _ => []
        }
        let id = match engine.publish_with_deps(project_dir~, description~, depends_on~, created_by~, now=ts, ns=ns) {
          Ok(id) => id
          Err(e) => return Err(@mcp_types.ToolError(e))
        }
        Ok(@mcp.ToolResult::text(Json::object({
          "task_id": Json::string(id),
          "message": Json::string("已发布根任务（带依赖）"),
        }).stringify()))
      },
    )
    .tool(
      "dag_critical_path",
      "返回当前最长依赖链（关键路径）。无参数。",
      schema({}, []),
      async fn(_args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
        let path = engine.critical_path()
        Ok(@mcp.ToolResult::text(Json::object({
          "critical_path": Json::array(path.map(fn(id) { Json::string(id) })),
          "length": Json::number(path.length().to_double()),
        }).stringify()))
      },
    )
    .tool(
      "dag_parallelism",
      "返回当前可并行执行的任务数（待领取且依赖已满足）。无参数。",
      schema({}, []),
      async fn(_args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
        let n = engine.parallelism()
        Ok(@mcp.ToolResult::text(Json::object({
          "parallelism": Json::number(n.to_double()),
        }).stringify()))
      },
    )
    .tool(
      "dag_ascii",
      "返回当前命名空间任务的 ASCII 依赖结构图。参数：namespace(可选，默认 default)。",
      schema(
        {
          "namespace": string_prop("命名空间(默认 default)"),
        },
        [],
      ),
      async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
        let ns = get_str(args, "namespace", default="default")
        let ascii = engine.dag_ascii(ns~)
        Ok(@mcp.ToolResult::text(Json::object({
          "namespace": Json::string(if ns == "" { "default" } else { ns }),
          "ascii": Json::string(ascii),
        }).stringify()))
      },
    )
    .tool(
      "dag_check",
      "检查某任务的依赖是否全部完成。参数：task_id。",
      schema(
        {
          "task_id": string_prop("任务 id（必填）"),
        },
        ["task_id"],
      ),
      async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
        let task_id = get_str(args, "task_id")
        let ok = engine.deps_satisfied(task_id)
        Ok(@mcp.ToolResult::text(Json::object({
          "task_id": Json::string(task_id),
          "deps_satisfied": Json::boolean(ok),
        }).stringify()))
      },
    )
    .tool(
      "dag_ready",
      "列出所有依赖满足、可领取的任务。参数：namespace(可选)。",
      schema(
        {
          "namespace": string_prop("命名空间(默认 default)"),
        },
        [],
      ),
      async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
        let ns = get_str(args, "namespace", default="default")
        let ready = engine.ready_tasks(ns_filter=ns)
        Ok(@mcp.ToolResult::text(Json::array(
          ready.map(fn(t) { t.to_json() }),
        ).stringify()))
      },
    )
    .tool(
      "dag_sort",
      "对任务列表按依赖深度拓扑排序。参数：task_ids(JSON 数组)。",
      schema(
        {
          "task_ids": string_prop("任务 id 列表 JSON 数组（必填）"),
        },
        ["task_ids"],
      ),
      async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
        let raw = get_str(args, "task_ids")
        let task_ids : Array[String] = try {
          match @json.parse(raw) {
            Json::Array(a) => a.map(fn(v) { v.as_string().unwrap_or("") })
            _ => []
          }
        } catch {
          _ => []
        }
        let sorted = engine.topo_sort(task_ids)
        Ok(@mcp.ToolResult::text(Json::object({
          "sorted": Json::array(sorted.map(fn(id) { Json::string(id) })),
        }).stringify()))
      },
    )

  // ---- 审计工具 ----
  .tool(
    "audit_permission",
    "查询某角色是否可执行指定操作。参数：role(human_steward/leader/agent)、操作名(publish/archive/delete/claim)。",
    schema(
      {
        "role": string_prop("角色名（必填）"),
        "action": string_prop("操作名（必填）"),
      },
      ["role", "action"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let role_s = get_str(args, "role")
      let action = get_str(args, "action")
      match @ops.Role::from_string(role_s) {
        None => Err(@mcp_types.ToolError("未知角色: \{role_s}，合法值：human_steward / leader / agent"))
        Some(role) => {
          match @ops.enforce(action~, role~) {
            Ok(_) => Ok(@mcp.ToolResult::text(Json::object({
              "role": Json::string(role_s),
              "action": Json::string(action),
              "allowed": Json::boolean(true),
            }).stringify()))
            Err(msg) => Ok(@mcp.ToolResult::text(Json::object({
              "role": Json::string(role_s),
              "action": Json::string(action),
              "allowed": Json::boolean(false),
              "message": Json::string(msg),
            }).stringify()))
          }
        }
      }
    },
  )
  .tool(
    "audit_log",
    "查看追加式审计日志。可选 filter_actor、filter_task_id；now 仅用于兼容忽略。",
    schema(
      {
        "filter_actor": string_prop("按操作者过滤(可选)"),
        "filter_task_id": string_prop("按任务 id 过滤(可选)"),
      },
      [],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let fa = get_str(args, "filter_actor", default="")
      let ft = get_str(args, "filter_task_id", default="")
      let entries = if fa != "" {
        audit.by_actor(fa)
      } else if ft != "" {
        audit.by_task(ft)
      } else {
        audit.entries()
      }
      Ok(@mcp.ToolResult::text(audit.to_json().stringify()))
    },
  )
  // ---- multi-store 命名空间工具 ----
  .tool(
    "store_open",
    "打开（或复用）一个命名空间。参数：namespace、data_dir(可选，默认当前目录)。",
    schema(
      {
        "namespace": string_prop("命名空间（必填）"),
        "data_dir": string_prop("库文件根目录(可选，默认当前目录)"),
      },
      ["namespace"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let ns = get_str(args, "namespace")
      let dir = get_str(args, "data_dir", default=".")
      match mstore.open(ns~, data_dir=dir) {
        false => Err(@mcp_types.ToolError("打开命名空间失败: \{ns}"))
        true => {
          Ok(@mcp.ToolResult::text(Json::object({
            "namespace": Json::string(ns),
            "opened": Json::boolean(true),
            "active_namespaces": Json::array(mstore.ns_list().map(fn(s) { Json::string(s) })),
          }).stringify()))
        }
      }
    },
  )
  .tool(
    "store_list",
    "列出当前已打开的命名空间及任务数。无参数。",
    schema({}, []),
    async fn(_args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let list = mstore.ns_list()
      let stats = mstore.ns_stats()
      Ok(@mcp.ToolResult::text(Json::object({
        "active_namespaces": Json::array(list.map(fn(s) { Json::string(s) })),
        "stats": stats,
      }).stringify()))
    },
  )
  .tool(
    "store_close",
    "关闭指定命名空间（不删除物理库文件）。参数：namespace。",
    schema(
      {
        "namespace": string_prop("命名空间（必填）"),
      },
      ["namespace"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let ns = get_str(args, "namespace")
      mstore.close(ns)
      Ok(@mcp.ToolResult::text(Json::object({
        "namespace": Json::string(ns),
        "closed": Json::boolean(true),
        "active_namespaces": Json::array(mstore.ns_list().map(fn(s) { Json::string(s) })),
      }).stringify()))
    },
  )

  // 默认 stdio 传输（MCP 标准模式）。
  run_stdio_target(s1)
}