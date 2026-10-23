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
  mut seq : Int32
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
/// 点名寻址：ns → 该 ns 的**物理库**引擎（`default`/空 = 进程默认引擎）。
/// 打不开返回 None，绝不静默回落默认库——`engine_for_ns` 的 None 分支就是那条
/// 静默回落（非法 ns 会被当成默认库读写），管家面先把这条自证掉（R114）。
fn supervisor_ns_engine(ns : String) -> @engine.FistEngine? {
  if ns == "" || ns == "default" {
    Some(engine)
  } else {
    match mstore.get(ns) {
      Some(s) =>
        Some(@engine.FistEngine::new(store=@store.StoreBackend::sqlite(s)))
      None => None
    }
  }
}

///|
/// 点名 ns 却打不开库时的发红文案（可寻址 ⇒ 空串）。
fn supervisor_ns_unavailable(ns : String) -> String {
  if supervisor_ns_engine(ns) is Some(_) {
    ""
  } else {
    "命名空间不可用: \{ns}（未打开或名称非法）—— 超级管家不静默回落默认库，请先用 store_open 打开该 ns"
  }
}

///|
/// 管家族的搜索范围：点名 ns ⇒ 只查该 ns；ns 为空 ⇒ default 先、再其余已打开的 ns。
/// 为什么寻址必须落在 IO 层：ns 既是 `Task.ns` 列、又是物理库路由，引擎侧单库
/// 纯计算看不见别的库——过去五支 supervisor_* 全打默认引擎，非 default 命名空间
/// 里的任务对管家是盲区，而 supervisor_status 的文案早已承诺「不传=全库」（R114 实测）。
fn supervisor_ns_candidates(ns : String) -> Array[(String, @engine.FistEngine)] {
  if ns != "" {
    match supervisor_ns_engine(ns) {
      Some(e) => [(ns, e)]
      None => []
    }
  } else {
    let out : Array[(String, @engine.FistEngine)] = [("default", engine)]
    for one in mstore.ns_list() {
      // default 不进 ns_list 兜底：引擎的 default 走进程默认库，ns_list 里的同名键
      // 是另一只句柄，两条都收会把同一个库数两遍。
      if one != "" && one != "default" {
        match supervisor_ns_engine(one) {
          Some(e) => out.push((one, e))
          None => ()
        }
      }
    }
    out
  }
}

///|
/// 跨候选范围找出任务所在的**全部**库（命中列表，不是第一个）。
/// 为什么不返回「第一个命中」：根任务 id 是每库各自从 T0 起算的（publish 只在单库内
/// 顺延 T0r2），两个 ns 都有 `T0` 是常态——按搜索顺序取第一个会把 tree/kill 落到
/// 别人的任务上，而 kill 是不可逆动作的门面，歧义必须显式拒绝（R114 探针实测的歧义形）。
fn supervisor_find_task_hits(
  task_id : String,
  ns : String,
) -> Array[(String, @engine.FistEngine)] {
  let hits : Array[(String, @engine.FistEngine)] = []
  for (name, eng) in supervisor_ns_candidates(ns) {
    if eng.get_task(task_id) is Some(_) {
      hits.push((name, eng))
    }
  }
  hits
}

///|
/// 命中歧义时的发红文案（调用方已确认 hits 多于一个）。
fn supervisor_ambiguous_msg(
  task_id : String,
  hits : Array[(String, @engine.FistEngine)],
) -> String {
  "task_id \{task_id} 在多个命名空间同时存在: [\{supervisor_scanned_names(hits)}] —— 请点名 namespace，超级管家不按顺序猜库"
}

///|
/// Json 值取数值（非数值 ⇒ 0）。
fn json_num_of(v : Json) -> Double {
  match v {
    Json::Number(n, ..) => n
    _ => 0.0
  }
}

///|
/// Json 对象取数值键（缺失 ⇒ 0）。
fn json_field_num(j : Json, key : String) -> Double {
  match j {
    Json::Object(m) =>
      match m.get(key) {
        Some(v) => json_num_of(v)
        _ => 0.0
      }
    _ => 0.0
  }
}

///|
/// Json 对象取子对象键（缺失/非对象 ⇒ 空表）。供 by_status/by_namespace 合并。
fn json_field_obj(j : Json, key : String) -> Map[String, Json] {
  match j {
    Json::Object(m) =>
      match m.get(key) {
        Some(Json::Object(sub)) => sub
        _ => Map([])
      }
    _ => Map([])
  }
}

///|
/// Json 对象取数组键（缺失/非数组 ⇒ 空表）。供 active/reminders 拼接。
fn json_field_arr(j : Json, key : String) -> Array[Json] {
  match j {
    Json::Object(m) =>
      match m.get(key) {
        Some(Json::Array(arr)) => arr
        _ => []
      }
    _ => []
  }
}

///|
/// 在既有读数上追加/覆盖键，非对象原样返回。用于盖 scope / namespace 这类寻址元数据。
fn supervisor_stamp(j : Json, extra : Map[String, Json]) -> Json {
  match j {
    Json::Object(m) => {
      let out : Map[String, Json] = Map([])
      m.each(fn(k, v) { out.set(k, v) })
      extra.each(fn(k, v) { out.set(k, v) })
      Json::object(out)
    }
    _ => j
  }
}

///|
/// 多库 supervisor_status 读数折成一份全景（纯 IO 层聚合，引擎侧单库口径不动）。
///
/// - `by_namespace` 按**物理库**计数（该库任务行数），不是 `Task.ns` 列值：
///   列值可以是假的（历史上 task_upsert 把 ghostA 的行写进默认库），
///   管家要能顺着这条读数把任务取回来，寻址必须与物理落点一致。
/// - `by_status` 按列值口径逐库相加（沿用引擎既有语义，零回归）。
/// - `progress_pct` 由合并后的「已完成+已归档 / total」重算——百分比不能取平均，
///   两个库任务数悬殊时均值会把全景进度带偏。
/// - `active` 每条盖 `namespace`，指明取回它该点名哪个 ns。
fn supervisor_status_fold(parts : Array[(String, Json)]) -> Json {
  let mut total = 0.0
  let mut done = 0.0
  let by_status : Map[String, Double] = Map([])
  let by_ns : Map[String, Double] = Map([])
  let active : Array[Json] = []
  fn bump(m : Map[String, Double], key : String, v : Double) -> Unit {
    m.set(key, m.get(key).unwrap_or(0.0) + v)
  }
  for (name, j) in parts {
    let t = json_field_num(j, "total")
    total = total + t
    by_ns.set(name, by_ns.get(name).unwrap_or(0.0) + t)
    json_field_obj(j, "by_status").each(fn(k, v) {
      let c = json_num_of(v)
      bump(by_status, k, c)
      if k == "已完成" || k == "已归档" {
        done = done + c
      }
    })
    for a in json_field_arr(j, "active") {
      active.push(supervisor_stamp(a, { "namespace": Json::string(name) }))
    }
  }
  let status_obj : Map[String, Json] = Map([])
  by_status.each(fn(k, v) { status_obj.set(k, Json::number(v)) })
  let ns_obj : Map[String, Json] = Map([])
  by_ns.each(fn(k, v) { ns_obj.set(k, Json::number(v)) })
  let progress = if total == 0.0 { 0.0 } else { done * 100.0 / total }
  Json::object({
    "total": Json::number(total),
    "by_status": Json::object(status_obj),
    "by_namespace": Json::object(ns_obj),
    "progress_pct": Json::number(progress),
    "active_count": Json::number(active.length().to_double()),
    "active": Json::array(active),
  })
}

///|
/// 候选范围里的 ns 名（供「未命中」文案点名搜过哪些库）。
fn supervisor_scanned_names(
  cands : Array[(String, @engine.FistEngine)],
) -> String {
  let names = cands.map(fn(x) { x.0 })
  if names.is_empty() {
    "（无）"
  } else {
    names.join(", ")
  }
}

///|
/// kill 方案的 G2 门是否因「目标不存在」发红——跨库寻址后这条必须点名搜过哪些 ns。
fn supervisor_kill_g2_missing(plan : Json) -> Bool {
  let mut missing = false
  for g in json_field_arr(plan, "gates") {
    if json_field_str(g, "gate") == "G2_exists" && !json_field_bool(g, "passed") {
      missing = true
    }
  }
  missing
}

///|
/// 多库提醒读数折成一份：reminders 逐库拼接并盖 namespace，reminder_count 累加；
/// ts/stale_hours/pending_hours 这类阈值回显取第一库的（同一轮询同一基准，不重复数）。
fn supervisor_reminder_fold(parts : Array[(String, Json)]) -> Json {
  let reminders : Array[Json] = []
  let mut count = 0
  for (name, j) in parts {
    count = count + json_field_arr(j, "reminders").length()
    for r in json_field_arr(j, "reminders") {
      reminders.push(supervisor_stamp(r, { "namespace": Json::string(name) }))
    }
  }
  let out : Map[String, Json] = Map([])
  match parts.get(0) {
    Some((_, j0)) =>
      match j0 {
        Json::Object(m) =>
          m.each(fn(k, v) {
            if k != "reminder_count" && k != "reminders" {
              out.set(k, v)
            }
          })
        _ => ()
      }
    None => ()
  }
  out.set("reminder_count", Json::number(count.to_double()))
  out.set("reminders", Json::array(reminders))
  Json::object(out)
}

///|
/// 注册超级管家专属工具（在 server.mbt 里调用一次）。
pub fn register_supervisor_tools(s1 : @mcp.MCPServer) -> @mcp.MCPServer {
  // —— 1. supervisor_status：查看项目状态 ——
  let s1 = instrumented_tool(
    s1,
    "supervisor_status",
    "超级管家·查看项目状态：全库/指定命名空间的任务全景（by_status/by_namespace/进度/活跃任务列表）。纯读。参数：namespace(可选；不传=真·跨库全库聚合，遍历 default + 所有已打开 ns；传了=只查该 ns 的物理库，打不开则发红不静默回落)、detail(可选默认 false；true=active 每条任务返回完整 description，false=description 截断到 200 字节——task_plan_deep 开满 gradient/reinject_context/boundary_probe 后描述会递归膨胀到数 KB，默认截断控 MCP 返回体积)。返回：total/by_status/by_namespace/progress_pct/active_count/active，另附 scope(all-namespaces|namespace) 与 namespaces_scanned；active 每条带 namespace（取回它要点名哪个 ns）。",
    schema(
      {
        "namespace": string_prop("命名空间(可选，不传=全库聚合)"),
        "detail": bool_prop(
          "返回完整任务描述(可选默认 false；false 时 description 截断到 200 字节)",
        ),
      },
      [],
    ),
    fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let ns = get_str(args, "namespace")
      let detail = get_bool(args, "detail")
      let cands = supervisor_ns_candidates(ns)
      let ns_err = supervisor_ns_unavailable(ns)
      if ns_err != "" {
        return Err(@mcp_types.ToolError(ns_err))
      }
      let parts : Array[(String, Json)] = []
      let scanned : Array[String] = []
      for (name, eng) in cands {
        // 每库取全量：库本身就是 ns，再按 Task.ns 列过滤会把「列值写错但落点对」的行漏掉
        parts.push((name, eng.supervisor_status(ns_filter="", detail~)))
        scanned.push(name)
      }
      Ok(
        @mcp.ToolResult::text(
          supervisor_stamp(supervisor_status_fold(parts), {
            "scope": Json::string(
              if ns == "" {
                "all-namespaces"
              } else {
                "namespace"
              },
            ),
            "namespaces_scanned": Json::array(
              scanned.map(fn(s) { Json::string(s) }),
            ),
          }).stringify(),
        ),
      )
    },
  )
  // —— 2. supervisor_task_tree：任务树状态与进度 ——
  let s1 = instrumented_tool(
    s1,
    "supervisor_task_tree",
    "超级管家·任务树状态与进度：从 root_id 递归聚合子树，每节点带 subtree_done/subtree_total 完成度与 summary 所需字段。纯读。参数：root_id(必填)、namespace(可选；不传=按 default→其余已打开 ns 寻址，传了=只查该 ns)、detail(可选默认 false；true=各节点 task 返回完整 description，false=截断到 200 字节控体积)。返回：root_id/tree，另附 namespace(命中库)；未命中时错误点名已搜索的 ns，不与「任务不存在」混成一条；同 id 在多个 ns 都存在时拒绝猜库、要求点名 namespace。",
    schema(
      {
        "root_id": string_prop("根任务 id（必填）"),
        "namespace": string_prop("命名空间(可选，不传=跨 ns 寻址)"),
        "detail": bool_prop("返回完整任务描述(可选默认 false)"),
      },
      ["root_id"],
    ),
    fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let root_id = get_str(args, "root_id")
      let ns = get_str(args, "namespace")
      let detail = get_bool(args, "detail")
      let ns_err = supervisor_ns_unavailable(ns)
      if ns_err != "" {
        return Err(@mcp_types.ToolError(ns_err))
      }
      let cands = supervisor_ns_candidates(ns)
      let hits = supervisor_find_task_hits(root_id, ns)
      if hits.is_empty() {
        return Err(
          @mcp_types.ToolError(
            "task not found: \{root_id}（已搜索命名空间 \{supervisor_scanned_names(cands)}）",
          ),
        )
      }
      if hits.length() > 1 {
        return Err(
          @mcp_types.ToolError(supervisor_ambiguous_msg(root_id, hits)),
        )
      }
      let (found_ns, eng) = hits[0]
      match eng.supervisor_task_tree(root_id, detail~) {
        Ok(j) =>
          Ok(
            @mcp.ToolResult::text(
              supervisor_stamp(j, { "namespace": Json::string(found_ns) }).stringify(),
            ),
          )
        Err(e) =>
          Err(@mcp_types.ToolError("\{e}（命名空间 [\{found_ns}]）"))
      }
    },
  )
  // —— 3. supervisor_kill_plan：终止方案（只出方案不执行）——
  let s1 = instrumented_tool(
    s1,
    "supervisor_kill_plan",
    "超级管家·终止任务方案（kill 硬门链评估，只出方案不执行——金条四）：G1 身份门(主助理/human_steward)、G2 存在、G3 根任务不可杀、G4 终态拒杀、G5 force+reason；给出 verdict=allowed/only_plan/blocked + steps + saga 补偿建议。参数：task_id(必填)、by(必填)、reason(必填)、force(可选)、apply_pause(可选默认 false；true 时执行可逆的 pause)、namespace(可选；不传=按 default→其余已打开 ns 寻址，传了=只查该 ns)。返回：task_id/verdict/gates/steps/note，另附 namespace(命中或评估所在库) 与 namespaces_scanned；G2 未命中时 namespaces_scanned 点名搜过哪些库，不与「任务不存在」混成一条；同 id 在多个 ns 都存在时直接发红（撞号先于评估，apply_pause 不会打到别的 ns）。",
    schema(
      {
        "task_id": string_prop("目标任务 id（必填）"),
        "by": string_prop("操作者身份（必填）"),
        "reason": string_prop("终止理由（必填）"),
        "force": bool_prop("是否强制（可选，默认 false）"),
        "apply_pause": bool_prop(
          "是否同时执行可逆暂停（可选，默认 false；kill 本体永不自动执行）",
        ),
        "namespace": string_prop("命名空间(可选，不传=跨 ns 寻址)"),
      },
      ["task_id", "by", "reason"],
    ),
    fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let task_id = get_str(args, "task_id")
      let by = get_str(args, "by")
      let reason = get_str(args, "reason")
      let force = get_bool(args, "force")
      let apply_pause = get_bool(args, "apply_pause")
      let ns = get_str(args, "namespace")
      let ns_err = supervisor_ns_unavailable(ns)
      if ns_err != "" {
        return Err(@mcp_types.ToolError(ns_err))
      }
      let cands = supervisor_ns_candidates(ns)
      let hits = supervisor_find_task_hits(task_id, ns)
      // 撞号先于评估：apply_pause=true 时这里若猜库，pause 会打到另一个 ns 的同名任务上
      if hits.length() > 1 {
        return Err(
          @mcp_types.ToolError(supervisor_ambiguous_msg(task_id, hits)),
        )
      }
      // 命中哪库就在哪库评估（pause 这个唯一可逆动作必须落在任务真正所在的库）；
      // 未命中时仍在点名/默认库跑一遍，保持门链形状，再由下面补上「搜过哪些 ns」。
      let (plan_ns, plan_eng) = if hits.is_empty() { cands[0] } else { hits[0] }
      let plan = plan_eng.supervisor_kill_plan(
        task_id~,
        by~,
        reason~,
        force~,
        apply_pause~,
        now=now_default(),
      )
      let scanned = cands.map(fn(x) { x.0 })
      let extra : Map[String, Json] = {
        "namespace": Json::string(plan_ns),
        "namespaces_scanned": Json::array(
          scanned.map(fn(s) { Json::string(s) }),
        ),
      }
      if supervisor_kill_g2_missing(plan) {
        extra.set(
          "ns_hint",
          Json::string(
            "目标在 [\{supervisor_scanned_names(cands)}] 里都不存在：多租户下「找不到」可能是看错了库，点名 namespace 重试",
          ),
        )
      }
      Ok(@mcp.ToolResult::text(supervisor_stamp(plan, extra).stringify()))
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
        "include_consumed": bool_prop(
          "是否包含已消费(可选，默认 false)",
        ),
      },
      [],
    ),
    fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let target = get_str(args, "target")
      let include_consumed = get_bool(args, "include_consumed")
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
    "超级管家·更新目标项目任务列表：items 数组逐条处理——无 task_id=追加新根任务（publish，仅 human_steward）；有 task_id=更新描述/优先级/追加依赖（终态任务拒改）。逐条独立成败。参数：project_dir(必填)、by(必填)、items(必填数组：{task_id?, description, priority?, depends_on?[]})、namespace(可选默认 default；写入落在**该 ns 的物理库**，与 publish/list 同口径)。返回：project_dir/total/ok_count/results 逐条回执{ok,task_id|error,action}，另附 namespace(实际写入库)；ns 打不开直接发红，不会把行写进默认库再盖上别处的 ns。",
    schema(
      {
        "project_dir": string_prop("目标项目目录（必填）"),
        "by": string_prop(
          "操作者身份（必填，追加须为 human_steward）",
        ),
        "items": array_prop(
          "任务列表，每项 {task_id?, description, priority?, depends_on?[]}",
        ),
        "namespace": string_prop(
          "命名空间(可选，默认 default；决定物理落库位置)",
        ),
      },
      ["project_dir", "by", "items"],
    ),
    fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let project_dir = get_str(args, "project_dir")
      let by = get_str(args, "by")
      let ns = get_str(args, "namespace", default="default")
      let items = get_array(args, "items")
      let ns_err = supervisor_ns_unavailable(ns)
      if ns_err != "" {
        return Err(@mcp_types.ToolError(ns_err))
      }
      if project_dir == "" {
        return Err(@mcp_types.ToolError("project_dir 不能为空"))
      }
      if items.is_empty() {
        return Err(@mcp_types.ToolError("items 不能为空"))
      }
      // 过去这里打的是模块默认引擎，却把 ns~ 当列值盖进行里：ghostA 的行躺在
      // 默认库里，publish/list 按 ns 路由看不见它、supervisor_status 又按列值数到它
      // ——库级寻址与列值盖章分家（R114 实测的脑裂）。写入必须与 ns 同库。
      let eng = supervisor_ns_engine(ns).unwrap_or(engine)
      Ok(
        @mcp.ToolResult::text(
          supervisor_stamp(
            eng.supervisor_task_upsert(
              project_dir~,
              by~,
              items,
              now=now_default(),
              ns~,
            ),
            { "namespace": Json::string(if ns == "" { "default" } else { ns }) },
          ).stringify(),
        ),
      )
    },
  )
  // —— 8. supervisor_reminder_tick：提醒者轮询 ——
  let s1 = instrumented_tool(
    s1,
    "supervisor_reminder_tick",
    "超级管家·提醒者轮询：一次全库提醒检查——R1 未消费引导 + R2 停滞任务(活跃超 stale_hours 未更新) + R3 待处理超时(pending 超 pending_hours 未被接管)，产出提醒清单。只读，不注入不修改。参数：now(可选)、stale_hours(可选默认24)、pending_hours(可选默认48)、include_consumed(可选默认false，布尔；true 时另出 guidance_consumed_count/guidance_consumed，已消费引导不参与 total_reminders)、namespace(可选；不传=遍历 default + 所有已打开 ns，传了=只查该 ns)。返回：reminder_count/reminders、guidance_unconsumed_count/guidance_unconsumed、total_reminders，另附 scope/namespaces_scanned；reminders 每条带 namespace。",
    schema(
      {
        "now": string_prop("检查基准时间(可选，默认当前时间)"),
        "stale_hours": string_prop("停滞阈值小时数(可选，默认24)"),
        "pending_hours": string_prop(
          "待处理超时小时数(可选，默认48)",
        ),
        "include_consumed": bool_prop(
          "是否同时列出已消费引导(可选，默认false)",
        ),
        "namespace": string_prop("命名空间(可选，不传=全库轮询)"),
      },
      [],
    ),
    fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let now = get_str(args, "now", default=now_default())
      let stale_h = str_to_int(get_str(args, "stale_hours"), 24)
      let pending_h = str_to_int(get_str(args, "pending_hours"), 48)
      let include_consumed = get_bool(args, "include_consumed")
      let ns = get_str(args, "namespace")
      let ns_err = supervisor_ns_unavailable(ns)
      if ns_err != "" {
        return Err(@mcp_types.ToolError(ns_err))
      }
      // 「一次全库提醒检查」是这支工具自己的文案，过去只打默认引擎：
      // 别的 ns 里停了几天的任务，提醒者永远不响（R114 实测）。
      let parts : Array[(String, Json)] = []
      let scanned : Array[String] = []
      for (name, eng) in supervisor_ns_candidates(ns) {
        parts.push(
          (
            name,
            eng.supervisor_reminder_tick(
              now~,
              stale_hours=stale_h,
              pending_hours=pending_h,
            ),
          ),
        )
        scanned.push(name)
      }
      let tick = supervisor_stamp(supervisor_reminder_fold(parts), {
        "scope": Json::string(
          if ns == "" {
            "all-namespaces"
          } else {
            "namespace"
          },
        ),
        "namespaces_scanned": Json::array(
          scanned.map(fn(s) { Json::string(s) }),
        ),
      })
      let guidance = supervisor_guidance_list(target="", include_consumed~)
      let unconsumed = guidance.filter(fn(g) { !g.consumed })
      let consumed = guidance.filter(fn(g) { g.consumed })
      let base_count = json_field_arr(tick, "reminders").length()
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
      // include_consumed=true 时把已消费引导一并交出：过去先取回、再被上面那道
      // filter 丢掉，参数在 schema 与文案里都 advertised，读数却恒为空（幻影参数）。
      // total_reminders 口径不动（仍 = base + 未消费），已消费另键报告，零回归。
      if include_consumed {
        out.set(
          "guidance_consumed_count",
          Json::number(consumed.length().to_double()),
        )
        out.set(
          "guidance_consumed",
          Json::array(consumed.map(guidance_to_json)),
        )
      }
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
  target~ : String = "",
  include_consumed~ : Bool = false,
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
fn str_to_int(s : String, dft : Int32) -> Int32 {
  if s == "" {
    return dft
  }
  // BUG-187：同族 4 个解析器（sd_parse_int / ov_parse_int / bugreport.mbt:204 /
  // store_sqlite_executions.mbt:202）都用 int_safe 上界守卫，本函数是漏网。
  // 长数字串（如 stale_hours=99999999999999999999）在 `v = v*10 + d` 上溢出 Int
  // （JS target 静默精度丢失、native panic），这里复用同一上界并回退默认值。
  let int_safe : Int32 = 200_000_000
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
