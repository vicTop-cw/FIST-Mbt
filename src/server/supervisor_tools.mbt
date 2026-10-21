/// server/supervisor_tools.mbt —— 超级管家专属工具（supervisor_ 前缀，7 个）
///
/// 对应 docs/2026-10-12-fist-mbt-supervisor-tools-plan.md：
///   supervisor_status / supervisor_task_tree / supervisor_kill_plan /
///   supervisor_prompt_inject / supervisor_prompt_list / supervisor_prompt_consume /
///   supervisor_task_upsert
/// 引擎侧实现在 src/engine/engine_supervisor.mbt；本文件只做 IO/注册/引导队列。

///|
/// 引导提示词条目（提示词引导能力）。
priv struct SupervisorGuidance {
  id : String
  target : String
  prompt : String
  ns : String
  created_at : String
  consumed : Bool
}

///|
/// 引导队列注册表（进程内；跨进程经 call_log 双写回读，见计划文档 §4）。
priv struct SupervisorGuidanceRegistry {
  mut seq : Int
  items : Map[String, SupervisorGuidance]
}

///|
fn SupervisorGuidanceRegistry::new() -> SupervisorGuidanceRegistry {
  { seq: 0, items: Map([]), }
}

///|
/// 进程内引导队列。重启即失的部分由 call_log 回读兜底（best-effort）。
let supervisor_guidance : SupervisorGuidanceRegistry = SupervisorGuidanceRegistry::new()

///|
fn guidance_to_json(g : SupervisorGuidance) -> Json {
  Json::object({
    "id": Json::string(g.id),
    "target": Json::string(g.target),
    "prompt": Json::string(g.prompt),
    "namespace": Json::string(g.ns),
    "created_at": Json::string(g.created_at),
    "consumed": Json::boolean(g.consumed),
  })
}

///|
/// 注册超级管家专属工具（在 server.mbt 里调用一次）。
pub fn register_supervisor_tools(s1 : @mcp.MCPServer) -> @mcp.MCPServer {
  // —— 1. supervisor_status：查看项目状态 ——
  let s1 = instrumented_tool(
    s1,
    "supervisor_status",
    "超级管家·查看项目状态：全库/指定命名空间的任务全景（by_status/by_namespace/进度/活跃任务列表）。纯读。参数：namespace(可选，不传=全库)。",
    schema(
      { "namespace": string_prop("命名空间(可选，默认全部)") },
      [],
    ),
    fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let ns = get_str(args, "namespace")
      Ok(
        @mcp.ToolResult::text(
          engine.supervisor_status(ns_filter=ns).stringify(),
        ),
      )
    },
  )
  // —— 2. supervisor_task_tree：任务树状态与进度 ——
  let s1 = instrumented_tool(
    s1,
    "supervisor_task_tree",
    "超级管家·任务树状态与进度：从 root_id 递归聚合子树，每节点带 subtree_done/subtree_total 完成度与 summary 所需字段。纯读。参数：root_id(必填)。",
    schema({ "root_id": string_prop("根任务 id（必填）") }, ["root_id"]),
    fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let root_id = get_str(args, "root_id")
      match engine.supervisor_task_tree(root_id) {
        Ok(j) => Ok(@mcp.ToolResult::text(j.stringify()))
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )
  // —— 3. supervisor_kill_plan：终止方案（只出方案不执行）——
  let s1 = instrumented_tool(
    s1,
    "supervisor_kill_plan",
    "超级管家·终止任务方案（kill 硬门链评估，只出方案不执行——金条四）：G1 身份门(主助理/human_steward)、G2 存在、G3 根任务不可杀、G4 终态拒杀、G5 force+reason；给出 verdict=allowed/only_plan/blocked + steps + saga 补偿建议。参数：task_id(必填)、by(必填)、reason(必填)、force(可选)、apply_pause(可选默认 false；true 时执行可逆的 pause)。",
    schema(
      {
        "task_id": string_prop("目标任务 id（必填）"),
        "by": string_prop("操作者身份（必填）"),
        "reason": string_prop("终止理由（必填）"),
        "force": string_prop("是否强制（可选，默认 false）"),
        "apply_pause": string_prop(
          "是否同时执行可逆暂停（可选，默认 false；kill 本体永不自动执行）",
        ),
      },
      ["task_id", "by", "reason"],
    ),
    fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let task_id = get_str(args, "task_id")
      let by = get_str(args, "by")
      let reason = get_str(args, "reason")
      let force = get_str(args, "force") == "true"
      let apply_pause = get_str(args, "apply_pause") == "true"
      let plan = engine.supervisor_kill_plan(
        task_id~,
        by~,
        reason~,
        force~,
        apply_pause~,
        now=now_default(),
      )
      Ok(@mcp.ToolResult::text(plan.stringify()))
    },
  )
  // —— 4. supervisor_prompt_inject：注入引导提示词 ——
  let s1 = instrumented_tool(
    s1,
    "supervisor_prompt_inject",
    "超级管家·提示词引导：向目标 agent/项目注入一条引导提示词（入队待投递；双写 call_log 跨进程可回读）。参数：target(必填)、prompt(必填非空)、namespace(可选)。",
    schema(
      {
        "target": string_prop("目标 agent 或项目（必填）"),
        "prompt": string_prop("引导提示词正文（必填非空）"),
        "namespace": string_prop("命名空间(可选，默认 default)"),
      },
      ["target", "prompt"],
    ),
    fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let target = get_str(args, "target")
      let prompt = get_str(args, "prompt")
      let ns = get_str(args, "namespace", default="default")
      if target == "" {
        return Err(@mcp_types.ToolError("target 不能为空"))
      }
      if prompt == "" {
        return Err(@mcp_types.ToolError("prompt 不能为空"))
      }
      let id = supervisor_guidance_inject(target~, prompt~, ns~)
      Ok(
        @mcp.ToolResult::text(
          Json::object({
            "id": Json::string(id),
            "target": Json::string(target),
            "queued": Json::boolean(true),
            "note": Json::string(
              "引导队列进程内保存 + call_log 双写；目标 agent 用 supervisor_prompt_consume 取走",
            ),
          }).stringify(),
        ),
      )
    },
  )
  // —— 5. supervisor_prompt_list：列出引导 ——
  let s1 = instrumented_tool(
    s1,
    "supervisor_prompt_list",
    "超级管家·列出待投递引导提示词（可按 target 过滤，include_consumed=true 时含已消费）。参数：target(可选)、include_consumed(可选)。",
    schema(
      {
        "target": string_prop("按目标过滤(可选)"),
        "include_consumed": string_prop(
          "是否包含已消费(可选，默认 false)",
        ),
      },
      [],
    ),
    fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let target = get_str(args, "target")
      let include_consumed = get_str(args, "include_consumed") == "true"
      let items = supervisor_guidance_list(target~, include_consumed~)
      Ok(
        @mcp.ToolResult::text(
          Json::object({
            "count": Json::number(items.length().to_double()),
            "items": Json::array(items.map(guidance_to_json)),
          }).stringify(),
        ),
      )
    },
  )
  // —— 6. supervisor_prompt_consume：取走一条引导 ——
  let s1 = instrumented_tool(
    s1,
    "supervisor_prompt_consume",
    "超级管家·取走一条引导提示词：按 guidance_id 取 prompt 正文并标记已消费（幂等：重复取仍返回正文）。参数：guidance_id(必填)。",
    schema(
      {
        "guidance_id": string_prop(
          "引导条目 id（必填，来自 supervisor_prompt_inject/list）",
        ),
      },
      ["guidance_id"],
    ),
    fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let id = get_str(args, "guidance_id")
      match supervisor_guidance_consume(id~) {
        None => Err(@mcp_types.ToolError("guidance not found: \{id}"))
        Some(g) => {
          ignore(
            engine.store_write_call_log(
              ts=now_default(),
              tool="supervisor_prompt_consume",
              caller="supervisor",
              ns=g.ns,
              params_json=Json::object({ "guidance_id": Json::string(id) }).stringify(),
              result_json=guidance_to_json(g).stringify(),
              ok=true,
              runtime_ms=0,
              seq=0,
            ),
          )
          Ok(@mcp.ToolResult::text(guidance_to_json(g).stringify()))
        }
      }
    },
  )
  // —— 7. supervisor_task_upsert：更新目标项目任务列表 ——
  let s1 = instrumented_tool(
    s1,
    "supervisor_task_upsert",
    "超级管家·更新目标项目任务列表：items 数组逐条处理——无 task_id=追加新根任务（publish，仅 human_steward）；有 task_id=更新描述/优先级/追加依赖（终态任务拒改）。逐条独立成败。参数：project_dir(必填)、by(必填)、items(必填数组：{task_id?, description, priority?, depends_on?[]})、namespace(可选)。",
    schema(
      {
        "project_dir": string_prop("目标项目目录（必填）"),
        "by": string_prop(
          "操作者身份（必填，追加须为 human_steward）",
        ),
        "items": array_prop(
          "任务列表，每项 {task_id?, description, priority?, depends_on?[]}",
        ),
        "namespace": string_prop("命名空间(可选，默认 default)"),
      },
      ["project_dir", "by", "items"],
    ),
    fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let project_dir = get_str(args, "project_dir")
      let by = get_str(args, "by")
      let ns = get_str(args, "namespace", default="default")
      let items = get_array(args, "items")
      if project_dir == "" {
        return Err(@mcp_types.ToolError("project_dir 不能为空"))
      }
      if items.is_empty() {
        return Err(@mcp_types.ToolError("items 不能为空"))
      }
      Ok(
        @mcp.ToolResult::text(
          engine
          .supervisor_task_upsert(
            project_dir~,
            by~,
            items,
            now=now_default(),
            ns~,
          )
          .stringify(),
        ),
      )
    },
  )
  // —— 8. supervisor_reminder_tick：提醒者轮询 ——
  let s1 = instrumented_tool(
    s1,
    "supervisor_reminder_tick",
    "超级管家·提醒者轮询：一次全库提醒检查——R1 未消费引导 + R2 停滞任务(活跃超 stale_hours 未更新) + R3 待处理超时(pending 超 pending_hours 未被接管)，产出提醒清单。只读，不注入不修改。参数：now(可选)、stale_hours(可选默认24)、pending_hours(可选默认48)、include_consumed(可选默认false，是否列出已消费引导)。",
    schema(
      {
        "now": string_prop("检查基准时间(可选，默认当前时间)"),
        "stale_hours": string_prop("停滞阈值小时数(可选，默认24)"),
        "pending_hours": string_prop(
          "待处理超时小时数(可选，默认48)",
        ),
        "include_consumed": string_prop(
          "是否同时列出已消费引导(可选，默认false)",
        ),
      },
      [],
    ),
    fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let now = get_str(args, "now", default=now_default())
      let stale_h = str_to_int(get_str(args, "stale_hours"), 24)
      let pending_h = str_to_int(get_str(args, "pending_hours"), 48)
      let include_consumed = get_str(args, "include_consumed") == "true"
      let tick = engine.supervisor_reminder_tick(
        now~,
        stale_hours=stale_h,
        pending_hours=pending_h,
      )
      let guidance = supervisor_guidance_list(target="", include_consumed~)
      let unconsumed = guidance.filter(fn(g) { !g.consumed })
      let base_count = match tick {
        Json::Object(m) =>
          match m.get("reminder_count") {
            Some(Json::Number(n, ..)) => n.to_int()
            _ => 0
          }
        _ => 0
      }
      let out : Map[String, Json] = Map([])
      match tick {
        Json::Object(m) => m.each(fn(k, v) { out.set(k, v) })
        _ => ()
      }
      out.set(
        "guidance_unconsumed_count",
        Json::number(unconsumed.length().to_double()),
      )
      out.set(
        "guidance_unconsumed",
        Json::array(unconsumed.map(guidance_to_json)),
      )
      out.set(
        "total_reminders",
        Json::number((base_count + unconsumed.length()).to_double()),
      )
      Ok(@mcp.ToolResult::text(Json::object(out).stringify()))
    },
  )
  s1
}

///|
/// 注入一条引导（分配自增 id，双写 call_log）。
fn supervisor_guidance_inject(
  target~ : String,
  prompt~ : String,
  ns~ : String,
) -> String {
  supervisor_guidance.seq = supervisor_guidance.seq + 1
  let id = "sg-\{supervisor_guidance.seq}"
  let now = now_default()
  let g : SupervisorGuidance = {
    id,
    target,
    prompt,
    ns,
    created_at: now,
    consumed: false,
  }
  supervisor_guidance.items.set(id, g)
  ignore(
    engine.store_write_call_log(
      ts=now,
      tool="supervisor_prompt_inject",
      caller="supervisor",
      ns~,
      params_json=Json::object({
        "target": Json::string(target),
        "namespace": Json::string(ns),
      }).stringify(),
      result_json=guidance_to_json(g).stringify(),
      ok=true,
      runtime_ms=0,
      seq=0,
    ),
  )
  id
}

///|
/// 从 Json 对象安全取字符串字段（缺省 ""）。
fn json_field_str(j : Json, key : String) -> String {
  match j {
    Json::Object(m) =>
      match m.get(key) {
        Some(Json::String(s)) => s
        _ => ""
      }
    _ => ""
  }
}

///|
/// 从 Json 对象安全取布尔字段（缺省 false）。
fn json_field_bool(j : Json, key : String) -> Bool {
  match j {
    Json::Object(m) =>
      match m.get(key) {
        Some(True) => true
        Some(False) => false
        _ => false
      }
    _ => false
  }
}

///|
/// 列出引导（进程内 + call_log 回读去重）。新的在前。
fn supervisor_guidance_list(
  target? : String = "",
  include_consumed? : Bool = false,
) -> Array[SupervisorGuidance] {
  // call_log 回读（best-effort）：把落库但进程内没有的条目回灌
  for log in engine.store_recent_call_logs(limit=200) {
    if json_field_str(log, "tool") == "supervisor_prompt_inject" {
      let raw = json_field_str(log, "result_json")
      if raw != "" {
        let parsed : Json = @json.parse(raw) catch { _ => Json::null() }
        match parsed {
          Json::Null => ()
          gj => {
            let id = json_field_str(gj, "id")
            if id != "" && !supervisor_guidance.items.contains(id) {
              supervisor_guidance.items.set(id, {
                id,
                target: json_field_str(gj, "target"),
                prompt: json_field_str(gj, "prompt"),
                ns: json_field_str(gj, "namespace"),
                created_at: json_field_str(gj, "created_at"),
                consumed: json_field_bool(gj, "consumed"),
              })
            }
          }
        }
      }
    }
  } nobreak {
    ()
  }
  let out : Array[SupervisorGuidance] = []
  supervisor_guidance.items.each(fn(_, g) {
    if (target == "" || g.target == target) && (include_consumed || !g.consumed) {
      out.push(g)
    }
  })
  out.sort_by(fn(a, b) { b.created_at.compare(a.created_at) })
  out
}

///|
/// 取走一条引导：返回正文并标记已消费（幂等，重复取仍返回）。
fn supervisor_guidance_consume(id~ : String) -> SupervisorGuidance? {
  match supervisor_guidance.items.get(id) {
    None => None
    Some(g) => {
      let g2 = { ..g, consumed: true, }
      supervisor_guidance.items.set(id, g2)
      Some(g2)
    }
  }
}

///|
/// 字符串转整数（非法/空返回默认值）。供 supervisor_reminder_tick 解析阈值。
fn str_to_int(s : String, dft : Int) -> Int {
  if s == "" {
    return dft
  }
  // BUG-187：同族 4 个解析器（sd_parse_int / ov_parse_int / bugreport.mbt:204 /
  // store_sqlite_executions.mbt:202）都用 int_safe 上界守卫，本函数是漏网。
  // 长数字串（如 stale_hours=99999999999999999999）在 `v = v*10 + d` 上溢出 Int
  // （JS target 静默精度丢失、native panic），这里复用同一上界并回退默认值。
  let int_safe : Int = 200_000_000
  let mut v = 0
  let mut neg = false
  let mut i = 0
  if s[0] == '-' {
    neg = true
    i = 1
  }
  for j in i..<s.length() {
    let d = s[j].to_int() - 48
    if d < 0 || d > 9 {
      return dft
    }
    if v >= int_safe {
      return dft
    }
    v = v * 10 + d
  }
  if neg {
    -v
  } else {
    v
  }
}
