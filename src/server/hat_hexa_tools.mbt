/// hat_hexa_tools.mbt —— HexaMind 六元自驱决策 · MCP 工具层（R119）
///
/// 把 `src/hat` 的纯计算引擎核心挂到 MCP 面，注册三个工具：
///   · `hat_run`    —— P0 单轮并行：config_json → 每帽任务 + 星核合成 + 辩论对（**不发模型调用**）
///   · `hat_merge`  —— P1 分歧显性化：单元报告 → 分歧清单 + 收敛三态 + 裁决报告
///   · `hat_debate` —— P2 辩论对冲：两元交锋计划
///
/// 三个工具**全部纯计算只读、无进程内会话态、无网络**：真实模型调用由调用方把
/// `hat_run` 返回的每个 `prompt` 喂给 `executor_run`（executor=ofm）执行，再把结果
/// 拼成 `reports_json` 交给 `hat_merge`。引擎不自己发 HTTP，也不替用户裁决。
///
/// 单入口：`embed_hexa_tools(s)` 把三个工具追加到 MCPServer 上；`src/server/server.mbt`
/// 只在 `run_stdio_target(s1)` 之前加一行 `s1 = embed_hexa_tools(s1)` 即可接线
/// （最小侵入，避免大段 diff 撞并发会话）。
///
/// 真源：`src/hat`（六元注册表 / config 解析 / 分歧提取 / 收敛判定 / 报告组装）。

///|
/// 把 HexaMind 三工具注册到 MCPServer 上并返回扩展后的 server。
pub fn embed_hexa_tools(s : @mcp.MCPServer) -> @mcp.MCPServer {
  let mut s1 = s
  s1 = instrumented_tool(
    s1,
    "hat_run",
    "HexaMind 六元派发（P0 单轮并行，纯计算只读）：解析 config_json → 给每个已选六元生成单元任务（角色 prompt + 模型车道 + 采样参数 + 输出契约）+ 星核合成任务 + 黑↔黄 / 红↔绿 辩论对。**本工具不发任何模型调用**：每个任务带 executor_hint=ofm 与 dry_run_shape，把 prompt 喂 executor_run 即可真实执行。参数：config_json(必填，含 topic/hats/hat_policy)、round(可选,默认 1)。返回 plan。",
    schema(
      {
        "config_json": string_prop(
          "HexaMind 配置（必填）：{topic, hats[], hat_policy{max_rounds,converge_threshold,auto_select_hats,debate_enabled}}",
        ),
        "round": number_prop(
          "当前轮次（可选，默认 1，仅标记用）",
        ),
      },
      ["config_json"],
    ),
    fn(args : Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError] {
      match hat_run_impl(args) {
        Ok(j) => Ok(@mcp.ToolResult::text(j.stringify()))
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "hat_merge",
    "HexaMind 分歧提取 + 收敛判定 + 裁决报告（P1，纯计算只读）：对 reports_json 里的单元报告做程序化分歧提取（verdict 对冲 / 置信度落差 / 论据路径 Jaccard）+ 收敛三态（converged/partial/diverged）+ 生成 Markdown 报告。**终态门=user**（本工具只给读数，不代用户裁决）。参数：topic(必填)、reports_json(必填,单元报告数组)、config_json(可选,缺省默认策略)、round(可选,默认 1)。返回 report。",
    schema(
      {
        "topic": string_prop("议题（必填）"),
        "reports_json": string_prop(
          "单元报告数组 JSON（必填）：[{element_id, verdict, confidence, evidence, outcomes[]}]",
        ),
        "config_json": string_prop(
          "HexaMind 配置（可选；缺省用默认策略 max_rounds=2/threshold=0.6）",
        ),
        "round": number_prop("当前轮次（可选，默认 1）"),
      },
      ["topic", "reports_json"],
    ),
    fn(args : Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError] {
      match hat_merge_impl(args) {
        Ok(j) => Ok(@mcp.ToolResult::text(j.stringify()))
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "hat_debate",
    "HexaMind 辩论对冲（P2，纯计算只读）：给定两个不同六元，生成一对辩论计划（交锋议题 + 回合数）+ 建议的论据分歧类型。**本工具不发模型调用**：把议题与左右两元角色 prompt（见 hat_run）喂 executor_run 即可执行辩论。参数：left(必填)、right(必填,须与 left 不同)、issue(可选,缺省按黑↔黄/红↔绿给预设议题)、rounds(可选,默认 1,1..5)。返回 debate。",
    schema(
      {
        "left": string_prop(
          "六元代号 A（必填）：stargazer|pulse|wallbreaker|golddigger|nova|nucleus",
        ),
        "right": string_prop("六元代号 B（必填，须与 A 不同）"),
        "issue": string_prop(
          "交锋议题（可选，缺省按黑↔黄/红↔绿给预设）",
        ),
        "rounds": number_prop("回合数（可选，默认 1，1..5）"),
      },
      ["left", "right"],
    ),
    fn(args : Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError] {
      match hat_debate_impl(args) {
        Ok(j) => Ok(@mcp.ToolResult::text(j.stringify()))
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )
  s1
}

// ---------------------------------------------------------------------------
// 三个 handler（返回 JSON 值；错误走 Err 整笔拒绝，不静默回落）
// ---------------------------------------------------------------------------

///|
/// hat_run：解析 config_json → build_plan → 序列化计划。
fn hat_run_impl(args : Json) -> Result[Json, String] {
  let raw = get_str(args, "config_json")
  if raw.trim().is_empty() {
    return Err("config_json 不能为空（至少含 topic）")
  }
  let config = match @hat.parse_config_json(raw) {
    Ok(c) => c
    Err(e) => return Err(e)
  }
  let plan = @hat.build_plan(config.topic, config)
  let round = get_int(args, "round", default=1)
  let m : Map[String, Json] = Map([])
  m.set("tool", Json::string("hat_run"))
  m.set("topic", Json::string(plan.topic))
  m.set("round", Json::number(round.to_double()))
  m.set("elements", Json::array(plan.config.elements.map(element_json)))
  m.set("tasks", Json::array(plan.tasks.map(task_json)))
  m.set("nucleus", task_json(plan.nucleus))
  m.set("debate_pairs", Json::array(plan.debate_pairs.map(debate_pair_json)))
  m.set("policy", policy_json(plan.config.policy))
  m.set(
    "note",
    Json::string(
      "本工具不发模型调用：把 tasks[].prompt（含 nucleus.prompt）逐条喂 executor_run(executor=ofm, ...) 执行，" +
      "再把各元产出按 {element_id, verdict, confidence, evidence, outcomes[]} 拼成 reports_json 交给 hat_merge。终审门=user。",
    ),
  )
  Ok(Json::object(m))
}

///|
/// hat_merge：单元报告 → 分歧提取 + 收敛判定 + 裁决报告。
fn hat_merge_impl(args : Json) -> Result[Json, String] {
  let topic = get_str(args, "topic")
  if topic.trim().is_empty() {
    return Err("topic 不能为空")
  }
  let reports_raw = get_str(args, "reports_json")
  if reports_raw.trim().is_empty() {
    return Err("reports_json 不能为空（至少一条合法报告）")
  }
  let reports = match parse_reports(reports_raw) {
    Ok(a) => a
    Err(e) => return Err(e)
  }
  if reports.is_empty() {
    return Err(
      "reports_json 里没有合法报告（element_id 须为六元代号、evidence 非空）",
    )
  }
  let config = match parse_optional_config(args, topic) {
    Ok(c) => c
    Err(e) => return Err(e)
  }
  let round = get_int(args, "round", default=1)
  let report = @hat.build_report(topic, config, reports, round)
  let m : Map[String, Json] = Map([])
  m.set("tool", Json::string("hat_merge"))
  m.set("topic", Json::string(report.topic))
  m.set("status", Json::string(report.status))
  m.set("should_iterate", @json.to_json(report.should_iterate))
  m.set("terminal_gate", Json::string(report.terminal_gate))
  m.set("convergence", converge_json(report.convergence))
  m.set("divergences", Json::array(report.divergences.map(divergence_json)))
  m.set("reports", Json::array(report.reports.map(report_json)))
  m.set("markdown", Json::string(report.markdown))
  Ok(Json::object(m))
}

///|
/// hat_debate：两元交锋计划。
fn hat_debate_impl(args : Json) -> Result[Json, String] {
  let left_raw = get_str(args, "left")
  let right_raw = get_str(args, "right")
  let left = match @hat.resolve_element_id(left_raw) {
    Ok(id) => id
    Err(e) => return Err("left: " + e)
  }
  let right = match @hat.resolve_element_id(right_raw) {
    Ok(id) => id
    Err(e) => return Err("right: " + e)
  }
  if left == right {
    return Err("left 与 right 不能相同（自辩不构成对冲）")
  }
  let rounds = get_int(args, "rounds", default=1)
  if rounds < 1 || rounds > 5 {
    return Err("rounds 必须在 1..5（收到 " + rounds.to_string() + "）")
  }
  let issue_raw = get_str(args, "issue")
  let issue = if issue_raw.trim().is_empty() {
    default_issue(left, right)
  } else {
    issue_raw
  }
  let pair = @hat.debate_pair(left, right, issue, rounds)
  let m : Map[String, Json] = Map([])
  m.set("tool", Json::string("hat_debate"))
  m.set("debate", debate_pair_json(pair))
  m.set(
    "note",
    Json::string(
      "本工具不发模型调用：把 debate.issue 与 left/right 两元角色 prompt（hat_run 可查）喂 executor_run 执行；" +
      "辩论结果按单元报告格式回灌 hat_merge。终审门=user。",
    ),
  )
  Ok(Json::object(m))
}

// ---------------------------------------------------------------------------
// 序列化
// ---------------------------------------------------------------------------

///|
fn task_json(t : @hat.ElementTask) -> Json {
  Json::object({
    "element_id": Json::string(t.element_id),
    "lane": Json::string(t.lane),
    "temperature": Json::number(t.temperature),
    "max_tokens": Json::number(t.max_tokens.to_double()),
    "output_schema": Json::array(str_arr(t.output_schema)),
    "prompt": Json::string(t.prompt),
    "executor_hint": Json::string(t.executor_hint),
    "dry_run_shape": Json::string(t.dry_run_shape),
  })
}

///|
fn element_json(e : @hat.HexaElement) -> Json {
  Json::object({
    "element_id": Json::string(e.id),
    "hat_id": Json::string(e.hat_id),
    "name_zh": Json::string(e.name_zh),
    "lane": Json::string(e.lane),
    "temperature": Json::number(e.temperature),
    "max_tokens": Json::number(e.max_tokens.to_double()),
    "output_schema": Json::array(str_arr(e.output_schema)),
    "role": Json::string(e.role),
  })
}

///|
fn debate_pair_json(p : @hat.DebatePair) -> Json {
  Json::object({
    "left": Json::string(p.left),
    "right": Json::string(p.right),
    "issue": Json::string(p.issue),
    "rounds": Json::number(p.rounds.to_double()),
  })
}

///|
fn policy_json(p : @hat.HatPolicy) -> Json {
  Json::object({
    "max_rounds": Json::number(p.max_rounds.to_double()),
    "converge_threshold": Json::number(p.converge_threshold),
    "auto_select_hats": @json.to_json(p.auto_select_hats),
    "debate_enabled": @json.to_json(p.debate_enabled),
  })
}

///|
fn converge_json(c : @hat.ConvergeResult) -> Json {
  Json::object({
    "round": Json::number(c.round.to_double()),
    "max_rounds": Json::number(c.max_rounds.to_double()),
    "agree": Json::number(c.agree.to_double()),
    "total": Json::number(c.total.to_double()),
    "rate": Json::number(c.rate),
    "threshold": Json::number(c.threshold),
    "status": Json::string(c.status),
    "blocking": Json::number(c.blocking.to_double()),
    "blockers": Json::array(str_arr(c.blockers)),
    "should_iterate": @json.to_json(c.should_iterate),
    "terminal_gate": Json::string(c.terminal_gate),
  })
}

///|
fn divergence_json(d : @hat.Divergence) -> Json {
  Json::object({
    "kind": Json::string(d.kind),
    "left": Json::string(d.left),
    "right": Json::string(d.right),
    "detail": Json::string(d.detail),
    "severity": Json::number(d.severity.to_double()),
  })
}

///|
fn report_json(r : @hat.HatReport) -> Json {
  Json::object({
    "element_id": Json::string(r.element_id),
    "verdict": Json::string(r.verdict),
    "confidence": Json::number(r.confidence),
    "evidence": Json::string(r.evidence),
    "outcomes": Json::array(str_arr(r.outcomes)),
  })
}

///|
fn str_arr(items : Array[String]) -> Array[Json] {
  items.map(fn(s) { Json::string(s) })
}

// ---------------------------------------------------------------------------
// 解析 / 默认议题
// ---------------------------------------------------------------------------

///|
/// 解析单元报告数组 JSON → Array[HatReport]；任一非法整笔 Err。
fn parse_reports(s : String) -> Result[Array[@hat.HatReport], String] {
  let j = @json.parse(s) catch {
    _ =>
      return Err(
        "reports_json 不是合法 JSON：请检查引号/逗号配平",
      )
  }
  let arr = match j {
    Json::Array(a) => a
    _ => return Err("reports_json 顶层必须是 JSON 数组")
  }
  let out : Array[@hat.HatReport] = []
  for i = 0; i < arr.length(); i = i + 1 {
    let item = arr[i]
    let element_id = obj_str(item, "element_id", "")
    let verdict = obj_str(item, "verdict", "")
    let confidence = obj_num(item, "confidence", -1.0)
    let evidence = obj_str(item, "evidence", "")
    let outcomes = obj_str_arr(obj_field(item, "outcomes"))
    let r = @hat.hat_report(
      element_id, verdict, confidence, evidence, outcomes, "",
    )
    match @hat.valid_report(r) {
      Ok(_) => out.push(r)
      Err(e) => return Err("reports_json[" + i.to_string() + "]: " + e)
    }
  }
  Ok(out)
}

///|
/// 解析可选 config_json；为空则用默认策略（议题照 topic）。
fn parse_optional_config(
  args : Json,
  topic : String,
) -> Result[@hat.HatConfig, String] {
  let raw = get_str(args, "config_json")
  if raw.trim().is_empty() {
    return Ok(@hat.default_config(topic))
  }
  match @hat.parse_config_json(raw) {
    Ok(c) => Ok(c)
    Err(e) => return Err("config_json: " + e)
  }
}

///|
/// 缺省交锋议题（对齐 build_plan 的 debate_pairs_of）。
fn default_issue(left : String, right : String) -> String {
  if (left == "wallbreaker" && right == "golddigger") ||
    (left == "golddigger" && right == "wallbreaker") {
    return "风险 vs 价值：该议题的致命缺陷与核心价值可否对冲（破壁者先摆坑，掘金者说清价值）"
  }
  if (left == "pulse" && right == "nova") ||
    (left == "nova" && right == "pulse") {
    return "直觉 vs 创意：发散方向是否偏离可行性（脉冲给感觉信号，新星给替代路径）"
  }
  left +
  " 与 " +
  right +
  " 就该议题的核心结论与论据路径正面交锋，把分歧显性化"
}

// ---------------------------------------------------------------------------
// JSON 对象小工具（对齐 server.mbt 的 get_* 约定）
// ---------------------------------------------------------------------------

///|
fn obj_field(j : Json, key : String) -> Json {
  match j {
    Json::Object(map) =>
      match map.get(key) {
        Some(v) => v
        None => Json::null()
      }
    _ => Json::null()
  }
}

///|
fn obj_str(j : Json, key : String, default : String) -> String {
  match j {
    Json::Object(map) =>
      match map.get(key) {
        Some(Json::String(s)) => s
        _ => default
      }
    _ => default
  }
}

///|
fn obj_num(j : Json, key : String, default : Double) -> Double {
  match j {
    Json::Object(map) =>
      match map.get(key) {
        Some(Json::Number(n, ..)) => n
        _ => default
      }
    _ => default
  }
}

///|
fn obj_str_arr(j : Json) -> Array[String] {
  match j {
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
