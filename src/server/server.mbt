/// FIST-Mbt MCP server: 暴露 16 tools + 2 resources + 2 prompts。
/// 接入 colmugx/mcp@0.17.4（2026-07-28 协议，Stdio/HTTP 双传输）。

///|
/// —— 引擎（进程内共享的可变状态）——
/// 运行时优先接入 SQLite 内建数据库（本项目根目录 fist-mbt.db 持久化）；
/// 打开失败（如缺 libsqlite3）自动回退内存版，保证 server 总能启动。
fn make_engine() -> @engine.FistEngine {
  match @store.SqliteStore::new() {
    Some(s) => @engine.FistEngine::new(store=@store.StoreBackend::sqlite(s))
    None => @engine.FistEngine::new()
  }
}

///|
/// 使用模块级 var，handler 闭包内直接引用（全局变量无需显式捕获）。
let engine : @engine.FistEngine = make_engine()

///|
/// 模块级心跳登记表（M4 运维：ActivityState / no_signal watchdog）。
let heartbeats : @ops.Heartbeat = @ops.Heartbeat::new()

///|
fn init_heartbeats() -> Unit {
  let rows = engine.store_list_heartbeats()
  for row in rows {
    let (_agent_id, task_id, last_seen, status) = row
    if task_id != "" {
      heartbeats.beat(task_id, signal=status, now=last_seen)
    }
  }
}

///|
let _init_hb : Unit = init_heartbeats()

///|
/// 模块级追加式审计日志（M5 治理：人类主权 + 追加式审计）。
let audit : @ops.AuditLog = @ops.AuditLog::new()

///|
/// 模块级多库管理器（M5 多租户：namespace 隔离的持久化，内部可变性模式）。
let mstore : @store.MultiStore = @store.MultiStore::new(data_dir=".")

///|
/// DGM 档案库（进程内 Archive，演化/自驱机制状态容器）。
/// SQLite 持久化能力已在 store 层（evolve_artifacts 表 + evolve_upsert/list）就绪；
/// 本进程 Archive 用于 MCP 工具的实时采样/查重/新颖性/谱系演示与编排。
let evolve_arc : @evolve.Archive = @evolve.Archive::new("mem-evolve")

///|
/// DGM 档案库的 SQLite 持久化句柄（供 evolve_distill 复用 evolve_upsert 落库）。
/// 打开失败（缺 sqlite）时为 None，蒸馏仅写进程内 Archive，语义仍成立。
let evolve_store : @store.SqliteStore? = @store.SqliteStore::new()

///|
/// 把毫秒级 Unix 时间转换为 UTC 时刻两项补齐
fn _pad2(n : Int) -> String {
  let s = n.to_string()
  if s.length() == 1 {
    "0" + s
  } else {
    s
  }
}

///|
/// 从 Unix 日起算天数反推公历 (年, 月, 日)（Howard Hinnant 的 civil_from_days，
/// 纯整数算术、适用于 z >= 0 即 1970 年起的日期）。
fn _civil_from_days(z : Int) -> (Int, Int, Int) {
  let z0 = z + 719468
  let era = z0 / 146097
  let doe = z0 - era * 146097
  let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  let y = yoe + era * 400
  let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
  let mp = (5 * doy + 2) / 153
  let d = doy - (153 * mp + 2) / 5 + 1
  let m = if mp < 10 { mp + 3 } else { mp - 9 }
  let y2 = if m <= 2 { y + 1 } else { y }
  (y2, m, d)
}

///|
/// 默认时间戳：取真实墙钟时间（UTC，毫秒级），格式化为
/// `YYYY-MM-DDTHH:MM:SSZ`。避免省略 now 参数时共享一个冻结时钟，
/// 使心跳/陈旧检测/清理/审计与真实时间对齐（不再硬编码 2026-09-05）。
fn now_default() -> String {
  // @env.now() 返回 UInt64 毫秒；直接用 Int64 做整数运算，避免 .to_int()
  // 对 UInt64 的 32 位截断（1790 亿级别毫秒被截成负值，导致 1969 时间戳）。
  let ms = @env.now().to_int64()
  let total_sec = ms / 1000L
  let sec = (total_sec % 60L).to_int()
  let min = (total_sec / 60L % 60L).to_int()
  let hour = (total_sec / 3600L % 24L).to_int()
  let days = (total_sec / 86400L).to_int()
  let (y, m, d) = _civil_from_days(days)
  "\{y}-\{_pad2(m)}-\{_pad2(d)}T\{_pad2(hour)}:\{_pad2(min)}:\{_pad2(sec)}Z"
}

///|
/// —— JSON schema 辅助 ——
fn string_prop(desc : String) -> Json {
  Json::object({
    "type": Json::string("string"),
    "description": Json::string(desc),
  })
}

///|
fn int_prop(desc : String) -> Json {
  Json::object({
    "type": Json::string("integer"),
    "description": Json::string(desc),
  })
}

///|
fn array_prop(desc : String) -> Json {
  Json::object({
    "type": Json::string("array"),
    "description": Json::string(desc),
  })
}

///|
fn number_prop(desc : String) -> Json {
  Json::object({
    "type": Json::string("number"),
    "description": Json::string(desc),
  })
}

///|
fn bool_prop(desc : String) -> Json {
  Json::object({
    "type": Json::string("boolean"),
    "description": Json::string(desc),
  })
}

///|
fn schema(props : Map[String, Json], required : Array[String]) -> Json {
  Json::object({
    "type": Json::string("object"),
    "properties": Json::object(props),
    "required": Json::array(required.map(fn(s) { Json::string(s) })),
  })
}

///|
/// 从 JSON 参数中读取字符串，缺省回退默认值
fn get_str(args : Json, key : String, default? : String = "") -> String {
  match args {
    Object(map) =>
      match map.get(key) {
        Some(String(s)) => s
        _ => default
      }
    _ => default
  }
}

///|
/// 从 JSON 参数中读取整数，缺省回退默认值
fn get_int(args : Json, key : String, default? : Int = 3) -> Int {
  match args {
    Object(map) =>
      match map.get(key) {
        Some(Number(n, ..)) => n.to_int()
        _ => default
      }
    _ => default
  }
}

///|
/// 从 JSON 参数中读取数组
fn get_array(args : Json, key : String) -> Array[Json] {
  match args {
    Object(map) =>
      match map.get(key) {
        Some(Array(a)) => a
        _ => []
      }
    _ => []
  }
}

///|
fn get_double(args : Json, key : String, default? : Double = 0.0) -> Double {
  match args {
    Object(map) =>
      match map.get(key) {
        Some(Number(n, ..)) => n
        _ => default
      }
    _ => default
  }
}

///|
fn get_bool(args : Json, key : String, default? : Bool = false) -> Bool {
  match args {
    Object(map) =>
      match map.get(key) {
        Some(True) => true
        Some(False) => false
        _ => default
      }
    _ => default
  }
}

///|
/// 从 laya_decide 返回的 Json 取 `answers.difficulty.score`，缺省回退 2.0。
/// 供 task_plan_deep 的 laya_auto 自动选档使用（纯解析，各 target 均可用）。
fn laya_difficulty_score(j : Json) -> Double {
  match j {
    Object(m) =>
      match m.get("answers") {
        Some(Object(a)) =>
          match a.get("difficulty") {
            Some(Object(d)) =>
              match d.get("score") {
                Some(Number(n, ..)) => n
                _ => 2.0
              }
            _ => 2.0
          }
        _ => 2.0
      }
    _ => 2.0
  }
}

///|
/// —— 结果转换辅助 ——
fn to_result(
  r : Result[@core.Task, String],
) -> Result[@mcp.ToolResult, @mcp.MCPError] {
  match r {
    Ok(t) => Ok(@mcp.ToolResult::text(t.to_json().stringify()))
    Err(e) => Err(@mcp_types.ToolError(e))
  }
}

///|
/// 检索档案库资产：按逗号分隔的 keywords，对每个 Artifact 的 goal 做子串匹配，
/// 返回命中项的 {goal, note, code}，供 plan/claim 前注入。检索不到命中项时返回空数组。
pub fn lookup_injected_assets_in(
  arc : @evolve.Archive,
  inject : String,
) -> Json {
  let hits : Array[Json] = []
  let ksq : Array[String] = []
  for k in inject.split(",") {
    let s = k.trim().to_string()
    if s != "" {
      ksq.push(s)
    }
  }
  if ksq.is_empty() {
    return Json::array(hits)
  }
  for art in @evolve.Archive::all(arc) {
    for k in ksq {
      if art.goal.contains(k) || art.note.contains(k) {
        hits.push(
          Json::object({
            "id": Json::string(art.id),
            "goal": Json::string(art.goal),
            "note": Json::string(art.note),
            "code": Json::string(art.code),
          }),
        )
        break
      }
    }
  }
  Json::array(hits)
}

///|
/// 检索全局档案库资产（工具调用入口）：先把 DB 中的 [lesson] 教训同步进内存档案库，
/// 再委托给带 arc 参数的纯函数（这样 Omega 打回自动落库的教训在 plan/claim 的
/// inject 中可见，而不仅是落库）。
fn lookup_injected_assets(inject : String) -> Json {
  ignore(sync_db_lessons(evolve_arc, evolve_store))
  lookup_injected_assets_in(evolve_arc, inject)
}

///|
fn to_ids_result(
  r : Result[Array[String], String],
) -> Result[@mcp.ToolResult, @mcp.MCPError] {
  match r {
    Ok(ids) =>
      Ok(
        @mcp.ToolResult::text(
          Json::array(ids.map(fn(s) { Json::string(s) })).stringify(),
        ),
      )
    Err(e) => Err(@mcp_types.ToolError(e))
  }
}

///|
fn to_unit_result(
  r : Result[Unit, String],
) -> Result[@mcp.ToolResult, @mcp.MCPError] {
  match r {
    Ok(_) => Ok(@mcp.ToolResult::text("ok"))
    Err(e) => Err(@mcp_types.ToolError(e))
  }
}

///|
/// 项目地图（Repo Map）：src/ 子包职责 + MCP 工具分组 + 入口引导。
/// 供 AI agent 通过 fist://map 首读定位，避免全项目盲目探索。
fn map_json() -> Json {
  Json::object({
    "product": Json::string("FIST-Mbt"),
    "orientation": Json::string(
      "纯 MoonBit 实现的 MCP Server：AI 指挥官式任务编排（发布→拆解→认领→执行→提交→验收→归档）+ DGM 自进化 + Omega 强验证",
    ),
    "build_test": Json::string("moon check && moon test --target js"),
    "run_server": Json::string(
      "moon build --target js cmd/main && python scripts/patch_esm_main.py && node _build/js/debug/build/cmd/main/main.js",
    ),
    "packages": Json::object({
      "core": Json::string("领域模型 Task/TaskStatus + 七条金条"),
      "store": Json::string(
        "持久化 Memory/SQLite 双后端 + call_log/heartbeats/specs/evolve_artifacts",
      ),
      "engine": Json::string(
        "业务核心 publish/claim/plan_deep/execute/verify/archive + DAG + Omega/docs 门禁",
      ),
      "evolve": Json::string(
        "DGM 自进化档案库 Archive/Artifact/采样/查重/谱系",
      ),
      "omega": Json::string("Ω-check 项目结构/回传五段式校验"),
      "ops": Json::string("运维：心跳/看门狗/heal/清理"),
      "server": Json::string(
        "MCP 层 79 工具 + 3 resources + 2 prompts + call_log 注入",
      ),
      "decompose": Json::string("递归拆解规格"),
      "executor": Json::string("执行器"),
    }),
    "tool_groups": Json::object({
      "生命周期": Json::string(
        "publish/plan/claim/execute/submit/verify/reject/retry/pause/resume/archive/delete",
      ),
      "查询": Json::string("list/get"),
      "运维": Json::string(
        "task_plan_deep/conflicts_check/heartbeat/heal/watchdog_tick/task_cleanup",
      ),
      "DAG": Json::string(
        "dag_critical_path/parallelism/ascii/check/ready/sort/depend/publish",
      ),
      "自驱": Json::string(
        "selfdrive_init/append/get/export_tasks/review_tick/review_ready/publish_next/parse_next_tasks",
      ),
      "记忆与自进化": Json::string(
        "memory_consolidate/gc/link + evolve_submit/sample/snapshot/distill/asset_register",
      ),
      "审计权限": Json::string("audit_permission/log"),
      "多租户": Json::string("store_open/list/close"),
      "强验证": Json::string("omega_spec_create/review/result_verify/status"),
    }),
    "entry": Json::string(
      "先读 README.md + ARCHITECTURE.md + docs/agent-map.md 定位；加/改工具到 src/server/server.mbt；动存储到 src/store/store_sqlite.mbt",
    ),
  })
}

///|
/// —— overview 资源：任务统计概览 ——
fn overview_json() -> Json {
  let tasks = engine.list_all()
  let m : Map[String, Json] = Map([
    ("product", Json::string("FIST-Mbt")),
    ("version", Json::string("0.2.4")),
    ("principles", Json::number(7.0)),
    (
      "statuses",
      Json::string(
        "待领取/已领取/拆分中/执行中/待验收/已打回/已完成/已暂停/已归档",
      ),
    ),
  ])
  let counts : Map[String, Json] = Map([])
  let status_names = [
    "待领取", "已领取", "拆分中", "执行中", "待验收", "已打回",
    "已完成", "已暂停", "已归档",
  ]
  for s in status_names {
    counts.set(
      s,
      Json::number(
        tasks.filter(fn(t) { t.status_to_string() == s }).length().to_double(),
      ),
    )
  }
  m.set("tasks_total", Json::number(tasks.length().to_double()))
  m.set("tasks_by_status", Json::object(counts))
  Json::object(m)
}

///|
/// —— 自动调用日志（call_log）包装 ——
/// colmugx/mcp 的 `.tool(name, desc, schema, handler)` 接受
/// `async (Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError]` 的 handler。
/// 我们 `extend` 一个 `instrumented_tool`：在内部用 `_instrument` 包一层 handler，
/// 调前记录 args、调后记录结果/耗时，并 best-effort 写 call_log，绝不改动原结果。

///|
/// 进程内注入全局 handler 的自动日志（best-effort，任何失败均被吞掉，不影响工具调用）。
/// seq 用单调递增计数器（跨全部工具严格递增，供回放定位/排序，非主键）。
/// 规避 @env.now().to_int() 对 UInt64 毫秒做 32 位截断产生的负值/1970 错乱排序。
let _call_log_seq : Ref[Int] = { val: 0, }

///|
fn _log_call(
  eng : @engine.FistEngine,
  tool : String,
  args : Json,
  params_json : String,
  result_json : String,
  ok : Bool,
  runtime_ms : Int,
) -> Unit {
  let caller = get_str(args, "created_by", default="")
  // ns 缺失时回退 project_dir，实现多项目（兄弟项目）可追溯分组
  let mut ns = get_str(
    args,
    "namespace",
    default=get_str(args, "ns", default=""),
  )
  if ns.is_empty() {
    ns = get_str(args, "project_dir", default="")
  }
  let ts = now_default()
  _call_log_seq.val = _call_log_seq.val + 1
  let seq = _call_log_seq.val
  // 忽略写入失败：调用日志是"尽力而为"，绝不能反过来破坏业务调用
  ignore(
    eng.store_write_call_log(
      ts~,
      tool~,
      caller~,
      ns~,
      params_json~,
      result_json~,
      ok~,
      runtime_ms~,
      seq~,
    ),
  )
}

///|
/// 包装一个工具 handler：度量耗时、捕获入参/结果、best-effort 记日志，原样返回结果。
/// Ok 路径结果文本在外部不可读（ToolResult 字段私有），故以 "ok" 占位；
/// Err 路径记录真实错误信息（MCPError::message()）。
fn _instrument(
  tool : String,
  handler : async (Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError],
) -> async (Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError] {
  async fn(args : Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError] {
    let t0 = @env.now().to_int64()
    let params_json = args.stringify()
    let r = handler(args)
    let runtime_ms = (@env.now().to_int64() - t0).to_int()
    let (result_json, ok) = match r {
      Err(e) => (e.message(), false)
      Ok(_tr) => ("ok", true)
    }
    _log_call(engine, tool, args, params_json, result_json, ok, runtime_ms)
    r
  }
}

///|
/// 注册一个带自动 call_log 的工具（等价于 `.tool`，但 handler 经 `_instrument` 包装）。
/// 由于 MoonBit 不能为外部类型 MCPServer 新增方法，这里用自由函数 + 显式回传 server。
pub fn instrumented_tool(
  s : @mcp.MCPServer,
  name : String,
  description : String,
  input_schema : Json,
  handler : async (Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError],
) -> @mcp.MCPServer {
  s.tool(name, description, input_schema, _instrument(name, handler))
}

///|
/// —— MCP server 构建与运行 ——
pub async fn run_server() -> Unit {
  let mut s1 = @mcp.MCPServer::MCPServer("fist-mbt", "0.1.0")

  // ---- tools ----
  s1 = instrumented_tool(
    s1,
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
      let ts = get_str(args, "now", default=now_default())
      let r = engine.publish(
        project_dir~,
        description~,
        created_by~,
        now=ts,
        ns~,
      )
      match r {
        Ok(id) =>
          Ok(
            @mcp.ToolResult::text(
              Json::object({
                "task_id": Json::string(id),
                "message": Json::string("已发布根任务"),
              }).stringify(),
            ),
          )
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "publish_parallel",
    "并行追加独立根任务（不要求命名空间为空、不续轮不归档）：在已有任务的命名空间追加新的独立根任务，供自驱/定时命名空间连续发布多根使用。参数：project_dir、description(必填)、namespace(必填，非 default)、created_by(默认 selfdrive)、now。",
    schema(
      {
        "project_dir": string_prop("项目目录（必填）"),
        "description": string_prop("任务描述（必填）"),
        "namespace": string_prop("命名空间（必填，不得为 default）"),
        "created_by": string_prop("创建者身份(默认 selfdrive)"),
        "now": string_prop("时间戳(可选)"),
      },
      ["project_dir", "description", "namespace"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let project_dir = get_str(args, "project_dir")
      let description = get_str(args, "description")
      let ns = get_str(args, "namespace")
      let created_by = get_str(args, "created_by", default="selfdrive")
      let ts = get_str(args, "now", default=now_default())
      match
        engine.publish_parallel(
          ns~,
          description~,
          created_by~,
          project_dir~,
          now=ts,
        ) {
        Ok(id) =>
          Ok(
            @mcp.ToolResult::text(
              Json::object({
                "task_id": Json::string(id),
                "message": Json::string("已并行追加独立根任务"),
              }).stringify(),
            ),
          )
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "plan",
    "对指定任务拆分生成一层子任务（非原子任务才可拆）。参数：task_id 任务id、split_n 拆分数量(默认3)、by 执行者、inject 可选逗号分隔的档案资产关键词(命中则把资产 code/note 追加到返回 injected_assets)。",
    schema(
      {
        "task_id": string_prop("父任务 id（必填）"),
        "split_n": int_prop("拆分数量(默认3)"),
        "by": string_prop("执行拆分的人"),
        "inject": string_prop(
          "可选：逗号分隔的档案库资产 keywords（如 code-review,superpowers），按 goal 子串检索命中资产并追加到返回",
        ),
        "now": string_prop("时间戳(可选)"),
      },
      ["task_id"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let task_id = get_str(args, "task_id")
      let split_n = get_int(args, "split_n", default=3)
      let by = get_str(args, "by", default="human_steward")
      let ts = get_str(args, "now", default=now_default())
      let inject = get_str(args, "inject")
      // 先执行拆解拿 ids
      let ids = match engine.plan(task_id~, split_n~, by~, now=ts) {
        Ok(a) => a
        Err(e) => return Err(@mcp_types.ToolError(e))
      }
      // inject 非空：检索档案资产并转成对象返回；否则保持现有数组格式
      if inject == "" {
        return Ok(
          @mcp.ToolResult::text(
            Json::array(ids.map(fn(s) { Json::string(s) })).stringify(),
          ),
        )
      }
      let injected = lookup_injected_assets(inject)
      let m : Map[String, Json] = Map([])
      m.set("task_ids", Json::array(ids.map(fn(s) { Json::string(s) })))
      m.set("injected_assets", injected)
      Ok(@mcp.ToolResult::text(Json::object(m).stringify()))
    },
  )
  s1 = instrumented_tool(
    s1,
    "claim",
    "认领任务（待领取 -> 已领取；随后 execute 进入执行中）。参数：task_id、assignee 认领人、inject 可选逗号分隔档案资产关键词(命中则把 code/note 追加到返回 injected_assets)。",
    schema(
      {
        "task_id": string_prop("任务 id（必填）"),
        "assignee": string_prop("认领人（必填）"),
        "inject": string_prop(
          "可选：逗号分隔的档案库资产 keywords，按 goal 子串检索命中资产并追加到返回",
        ),
        "now": string_prop("时间戳(可选)"),
      },
      ["task_id", "assignee"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let task_id = get_str(args, "task_id")
      let assignee = get_str(args, "assignee")
      let ts = get_str(args, "now", default=now_default())
      let inject = get_str(args, "inject")
      match engine.claim(task_id~, assignee~, now=ts) {
        Err(e) => Err(@mcp_types.ToolError(e))
        Ok(t) => {
          if inject == "" {
            return Ok(@mcp.ToolResult::text(t.to_json().stringify()))
          }
          let injected = lookup_injected_assets(inject)
          let m : Map[String, Json] = Map([])
          m.set("task", t.to_json())
          m.set("injected_assets", injected)
          Ok(@mcp.ToolResult::text(Json::object(m).stringify()))
        }
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "execute",
    "记录执行交付物（向后兼容）。必填：task_id、deliverable；可选：executor(默认manual)、model、tokens_in、tokens_out、cost、duration_ms、rate_limited、failure_reason、now。",
    schema(
      {
        "task_id": string_prop("任务 id（必填）"),
        "deliverable": string_prop("交付物描述（必填）"),
        "executor": string_prop("执行器名称(默认 manual)"),
        "model": string_prop("模型名称(可选)"),
        "tokens_in": int_prop("输入 token 数(可选默认0)"),
        "tokens_out": int_prop("输出 token 数(可选默认0)"),
        "cost": number_prop("执行成本(可选默认0)"),
        "duration_ms": int_prop("执行耗时毫秒(可选默认0)"),
        "rate_limited": bool_prop("是否被限流(可选默认false)"),
        "failure_reason": string_prop("失败原因(可选)"),
        "now": string_prop("时间戳(可选)"),
      },
      ["task_id", "deliverable"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let task_id = get_str(args, "task_id")
      let deliverable = get_str(args, "deliverable")
      let ts = get_str(args, "now", default=now_default())
      // 提取可选执行元数据（向后兼容：无元数据时行为同旧版 execute）
      let executor = get_str(args, "executor", default="manual")
      let model = get_str(args, "model", default="")
      let tokens_in = get_int(args, "tokens_in", default=0)
      let tokens_out = get_int(args, "tokens_out", default=0)
      let cost = get_double(args, "cost", default=0.0)
      let duration_ms = get_int(args, "duration_ms", default=0)
      let rate_limited = get_bool(args, "rate_limited", default=false)
      let failure_reason = get_str(args, "failure_reason", default="")
      // 调用 execute_with_meta：同时写入 executions 表 + 流转任务状态
      to_result(
        engine.execute_with_meta(
          task_id~,
          deliverable~,
          now=ts,
          executor~,
          model~,
          tokens_in~,
          tokens_out~,
          cost~,
          duration_ms~,
          rate_limited~,
          failure_reason~,
        ),
      )
    },
  )
  s1 = instrumented_tool(
    s1,
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
      let ts = get_str(args, "now", default=now_default())
      to_result(engine.submit(task_id~, now=ts))
    },
  )
  s1 = instrumented_tool(
    s1,
    "run_check",
    "外部判据检查（服务端真实执行命令，防自写自测恒绿）。参数：task_id 任务id、cmd 可执行命令、args 参数数组(可选)、workdir 工作目录(默认项目目录)、timeout_ms 超时毫秒(默认120000)、now 时间戳(可选)。真实 spawn 子进程运行 cmd，退出码 0 记为 passed、否则 failed，结果 JSON（含 stdout/stderr）落库 specs 表（spec_type=check）；[gate:required] 任务的 verify 依赖本记录且校验新鲜度。",
    schema(
      {
        "task_id": string_prop("任务 id（必填）"),
        "cmd": string_prop(
          "要执行的外部命令（必填），如 bash / sh / node / cargo",
        ),
        "args": array_prop("命令参数数组（可选）"),
        "workdir": string_prop(
          "工作目录（可选，默认任务所在项目目录）",
        ),
        "timeout_ms": int_prop("超时毫秒（可选，默认 120000）"),
        "now": string_prop("时间戳(可选)"),
      },
      ["task_id", "cmd"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let task_id = get_str(args, "task_id")
      let cmd = get_str(args, "cmd")
      let now = get_str(args, "now", default=now_default())
      if task_id == "" || cmd == "" {
        return Err(@mcp_types.ToolError("run_check: task_id 与 cmd 必填"))
      }
      let args_arr = get_array(args, "args").map(fn(j) {
        match j {
          String(s) => s
          _ => j.stringify()
        }
      })
      let timeout_ms = get_int(args, "timeout_ms", default=120000)
      // 定位任务（取项目目录作默认 workdir；任务不存在也允许执行，仅不落库）
      match engine.get_task(task_id) {
        Some(t) => {
          let workdir = get_str(args, "workdir", default=t.project_dir)
          let r = run_check_external(cmd, args_arr, workdir, timeout_ms)
          match r {
            Ok(res) => {
              let status = match res {
                Object(m) =>
                  if m.get("ok") is Some(True) {
                    "passed"
                  } else {
                    "failed"
                  }
                _ => "failed"
              }
              match
                engine.gate_check_record(task_id, res.stringify(), status, now) {
                Ok(rec) => Ok(@mcp.ToolResult::text(rec.stringify()))
                Err(e) => Err(@mcp_types.ToolError(e))
              }
            }
            Err(e) => Err(@mcp_types.ToolError(e))
          }
        }
        None => {
          // 任务不存在：仍执行命令并返回结果，但不落库（无任务可挂）
          let workdir = get_str(args, "workdir", default=".")
          let r = run_check_external(cmd, args_arr, workdir, timeout_ms)
          match r {
            Ok(res) =>
              Err(
                @mcp_types.ToolError(
                  "任务不存在: \{task_id}（命令已执行，结果: \{res.stringify()}，未落库）",
                ),
              )
            Err(e) => Err(@mcp_types.ToolError(e))
          }
        }
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "verify",
    "验收通过（待验收 -> 已完成，父任务自动上卷）。[gate:required] 任务须先有新鲜通过的 run_check 记录；可选 docs_check 开启「文档即实现」门禁（校验 README/CHANGELOG/reports 存在性与交付物回传五段式，不达标打回）。参数：task_id、verifier、docs_check、now。",
    schema(
      {
        "task_id": string_prop("任务 id（必填）"),
        "verifier": string_prop("验收人（必填）"),
        "docs_check": bool_prop(
          "是否开启文档一致性门禁(默认 false，不传即现状)：开启后校验项目结构 README.md/CHANGELOG.md/reports 与交付物回传五段式，缺项打回",
        ),
        "now": string_prop("时间戳(可选)"),
      },
      ["task_id", "verifier"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let task_id = get_str(args, "task_id")
      let verifier = get_str(args, "verifier")
      let ts = get_str(args, "now", default=now_default())
      let docs_check = get_bool(args, "docs_check", default=false)
      to_result(engine.verify(task_id~, verifier~, now=ts, docs_check~))
    },
  )
  s1 = instrumented_tool(
    s1,
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
      let ts = get_str(args, "now", default=now_default())
      to_result(engine.reject_task(task_id~, reason~, by~, now=ts))
    },
  )
  s1 = instrumented_tool(
    s1,
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
      let ts = get_str(args, "now", default=now_default())
      to_result(engine.retry_task(task_id~, now=ts))
    },
  )
  s1 = instrumented_tool(
    s1,
    "reopen_task",
    "重开/重派任务：任意非归档任务回滚为已领取（M4 heal/运维重派用）。参数：task_id、now。",
    schema(
      {
        "task_id": string_prop("任务 id（必填）"),
        "now": string_prop("时间戳(可选)"),
      },
      ["task_id"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let task_id = get_str(args, "task_id")
      let ts = get_str(args, "now", default=now_default())
      match engine.reopen_task(task_id, ts) {
        Ok(t) => Ok(@mcp.ToolResult::text(t.to_json().stringify()))
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )
  s1 = instrumented_tool(
    s1,
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
      let ts = get_str(args, "now", default=now_default())
      to_result(engine.pause_task(task_id~, now=ts))
    },
  )
  s1 = instrumented_tool(
    s1,
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
      let ts = get_str(args, "now", default=now_default())
      to_result(engine.resume_task(task_id~, now=ts))
    },
  )
  s1 = instrumented_tool(
    s1,
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
      let ts = get_str(args, "now", default=now_default())
      to_result(engine.archive(task_id~, by~, now=ts))
    },
  )
  s1 = instrumented_tool(
    s1,
    "list",
    "列出任务，可按状态与命名空间过滤。参数：status(可选，中文状态名)、namespace(可选，按命名空间过滤；不传则列出全库所有命名空间)。",
    schema(
      {
        "status": string_prop(
          "按状态过滤(可选)：待领取/已领取/执行中/待验收/已完成/已归档",
        ),
        "namespace": string_prop(
          "按命名空间过滤(可选)：如 default/cron-auto/cron-cypy/fist-iter；不传则列出全部命名空间",
        ),
      },
      [],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let status_str = get_str(args, "status")
      let ns_str = get_str(args, "namespace")
      let mut tasks = if status_str == "" {
        engine.list_all()
      } else {
        match @core.TaskStatus::from_string(status_str) {
          Some(st) => engine.list_by_status(st)
          None =>
            return Err(@mcp_types.ToolError("未知状态: \{status_str}"))
        }
      }
      if ns_str != "" {
        tasks = tasks.filter(fn(t) { t.ns == ns_str })
      }
      Ok(
        @mcp.ToolResult::text(
          Json::array(tasks.map(fn(t) { t.to_json() })).stringify(),
        ),
      )
    },
  )
  s1 = instrumented_tool(
    s1,
    "get",
    "查询单个任务详情。参数：task_id。",
    schema({ "task_id": string_prop("任务 id（必填）") }, ["task_id"]),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let task_id = get_str(args, "task_id")
      match engine.get_task(task_id) {
        Some(t) => Ok(@mcp.ToolResult::text(t.to_json().stringify()))
        None => Err(@mcp_types.ToolError("task not found: \{task_id}"))
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "delete",
    "删除已归档任务。参数：task_id。",
    schema(
      { "task_id": string_prop("任务 id（必填，仅已归档可删）") },
      ["task_id"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let task_id = get_str(args, "task_id")
      to_unit_result(engine.delete_task(task_id))
    },
  )
  s1 = instrumented_tool(
    s1,
    "task_plan_deep",
    "AO 式递归拆解：对指定任务拆出整棵多层子任务树并写库。参数：task_id 任务id、split_n 每层默认拆分数(默认3)、by 拆解拳长、spec 可选 omega spec JSON(laws 作切割依据、fingerprint 作验收基准)、omega_strong_verify 是否开启 Omega 强验证(默认 false，不传即现状)、gradient 是否开启难度梯度标注(默认 false，开启后每个拆出的子任务描述附带『难度梯度 序号/总数:难易档』+『更简单变体』提示，使递归拆解呈由易到难、可验证最小片的梯度)、now 时间戳。开启强验证后每层子任务多出『语料创建者建语料 -> 验证者审语料 -> 执行者执行 -> 验证者复验成果』环节。",
    schema(
      {
        "task_id": string_prop("父任务 id（必填，非原子任务）"),
        "split_n": int_prop(
          "每层默认拆分数(默认3，有 spec.laws 时以 laws 为准)",
        ),
        "by": string_prop("执行拆解的拳长身份(默认 leader)"),
        "spec": string_prop("可选 omega spec JSON 字符串"),
        "omega_strong_verify": bool_prop(
          "是否开启 Omega 强验证(默认 false，不传即现状；开启后每轮需语料审核与成果复验)",
        ),
        "gradient": bool_prop(
          "是否开启难度梯度标注(默认 false，不传即现状；开启后每个拆出的子任务描述附带『难度梯度 序号/总数:易/中/难』+『更简单变体』提示，使递归拆解呈由易到难、可验证最小片的梯度)",
        ),
        "calibrate": array_prop(
          "可选难度校准：按切片给真实/投影难度数组(0..5，长度须与每层切片数一致才生效)；缺省回退按位置的易/中/难(零回归)。开启 gradient 时生效。",
        ),
        "laya_auto": bool_prop(
          "是否开启 Laya 自动选档(默认 false)：开启后探测 Laya，可用则按 difficulty.score 自动定 split_n 并把决策附到返回；不可用则回退 split_n 默认值。若同时传 decide_split_n，则忽略 Laya(躬身自决优先)",
        ),
        "decide_split_n": int_prop(
          "躬身自决拆分数(可选)：显式传入即以 agent 自决为准，跳过 Laya sidecar；缺省沿用 split_n/laya_auto 逻辑",
        ),
        "decide_difficulty": number_prop(
          "躬身自估困难度(可选，0..5)：随 plan_decision 返回做可审计依据，不强制校验",
        ),
        "decide_reason": string_prop(
          "躬身选档理由(可选，可审计)：说明为何定此拆分数",
        ),
        "decide_by": string_prop("躬身选档身份(默认 leader)"),
        "now": string_prop("时间戳(可选)"),
      },
      ["task_id"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let task_id = get_str(args, "task_id")
      let mut split_n = get_int(args, "split_n", default=3)
      let by = get_str(args, "by", default="leader")
      let spec_raw = get_str(args, "spec")
      let ts = get_str(args, "now", default=now_default())
      let spec : Json? = if spec_raw == "" {
        None
      } else {
        Some(@json.parse(spec_raw)) catch {
          _ => return Err(@mcp_types.ToolError("spec 不是合法 JSON"))
        }
      }
      let omega_strong = get_bool(args, "omega_strong_verify", default=false)
      let gradient = get_bool(args, "gradient", default=false)
      // 可选难度校准数组：把 JSON 数字数组转成 Double 数组（缺省 None = 位置档）
      let calibrate : Array[Double]? = {
        let arr = get_array(args, "calibrate")
        if arr.is_empty() {
          None
        } else {
          Some(
            arr.map(fn(j) {
              match j {
                Number(n, ..) => n
                _ => 0.0
              }
            }),
          )
        }
      }
      let laya_auto = get_bool(args, "laya_auto", default=false)
      // —— 躬身入局选档（decide_*）—— 决策由 agent/调用方显式自决，可审计，优先于 Laya。
      let decide_split_n = get_int(args, "decide_split_n", default=0)
      let decide_difficulty = get_double(args, "decide_difficulty", default=0.0)
      let decide_reason = get_str(args, "decide_reason")
      let decide_by = get_str(args, "decide_by", default="leader")
      // 躬身自决拆分数（>0 视为有效）优先；无自决时才走 Laya 冷启动/默认。
      let mut decided : Bool = false
      if decide_split_n > 0 {
        split_n = decide_split_n
        decided = true
      }
      // Laya 自动选档（仅在无躬身自决、且显式开启 laya_auto 时探测）：
      let mut laya_info : Json = Json::null()
      if laya_auto && not(decided) {
        let avail = match
          laya_probe_available(
            "python",
            ["scripts/laya_decide.py", "--probe"],
            ".",
            15000,
          ) {
          Ok(a) => a
          Err(_) => false
        }
        if avail {
          match engine.get_task(task_id) {
            Some(parent) =>
              match
                laya_decide_external(
                  "python",
                  ["scripts/laya_decide.py"],
                  ".",
                  Json::object({
                    "context": Json::string(parent.description),
                    "questions": Json::null(),
                    "model": Json::string("english"),
                  }).stringify(),
                  300000,
                ) {
                Ok(res) => {
                  let raw_n = laya_difficulty_score(res).round().to_int() + 2
                  let n = if raw_n < 2 {
                    2
                  } else if raw_n > 6 {
                    6
                  } else {
                    raw_n
                  }
                  split_n = n
                  let obj = match res {
                    Object(m) => m
                    _ => Map([])
                  }
                  obj.set("auto_split_n", Json::number(split_n.to_double()))
                  obj.set("context", Json::string(parent.description))
                  laya_info = Json::object(obj)
                }
                Err(_) => ()
              }
            None => ()
          }
        }
      }
      let base = match
        engine.plan_deep(
          task_id~,
          split_n~,
          by~,
          spec~,
          now=ts,
          omega_strong_verify=omega_strong,
          gradient~,
          calibrate~,
        ) {
        Ok(j) => j
        Err(e) => return Err(@mcp_types.ToolError(e))
      }
      // 组装返回：躬身自决 → 附 plan_decision；查明 laya_auto → 附 laya；否则与现状一致。
      let out = match base {
        Object(m) => {
          if decided {
            let dm : Map[String, Json] = Map([
              ("source", Json::string("self")),
              ("split_n", Json::number(split_n.to_double())),
              ("difficulty", Json::number(decide_difficulty)),
              ("reason", Json::string(decide_reason)),
              ("by", Json::string(decide_by)),
              ("decided_at", Json::string(now_default())),
            ])
            m.set("plan_decision", Json::object(dm))
          }
          if laya_auto && not(decided) {
            m.set("laya", laya_info)
          }
          Json::object(m)
        }
        _ => base
      }
      Ok(@mcp.ToolResult::text(out.stringify()))
    },
  )
  s1 = instrumented_tool(
    s1,
    "task_challenge",
    "自进化·Challenger 进阶变体（SAGE 四专家环另一半，与 R12 梯度/R13 Critic 互补）：对一条【已完成/已归档】任务按策略发布上一档『更难变体』—新根任务带 [challenge] 标记 + from 溯源 + 重要度升一档，构成『由易到难』自推进序列，让复杂能力持续上探而非停在完成点。可选 critic（缺省关闭零回归）：开启后对生成的挑战题先做 Critic 防漂移评审（与 evolve_critic 同一单一真源，防课程漂移/同质坍缩），当前策略漂移自动降档、全部漂移则拒发。参数：task_id 源任务(必填，须已完成/已归档)、by 触发者(默认 auto)、factor 扩规模倍数(默认2，仅 scale 策略生效)、strat 进阶策略(默认 scale，可选 generalize/unhint/constrain/scale)、critic 是否开启防漂移门禁(默认 false)、now。返回 {new_id,source,factor,strat,importance,critic,critic_status}。",
    schema(
      {
        "task_id": string_prop(
          "源任务 id（必填，须为已完成/已归档）",
        ),
        "by": string_prop("触发者身份(默认 auto)"),
        "factor": int_prop("扩规模倍数(默认2，仅 scale 策略生效)"),
        "strat": string_prop(
          "进阶策略(默认 scale；generalize/unhint/constrain/scale)",
        ),
        "critic": bool_prop(
          "是否开启防漂移门禁(默认 false；true 时挑战题过 Critic 评审，漂移自动降档/拒发)",
        ),
        "now": string_prop("时间戳(可选，默认内置)"),
      },
      ["task_id"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let task_id = get_str(args, "task_id")
      let by = get_str(args, "by", default="auto")
      let factor = get_int(args, "factor", default=2)
      let strat = get_str(args, "strat", default="scale")
      let ts = get_str(args, "now", default=now_default())
      let critic_on = get_bool(args, "critic", default=false)
      // 开启门禁时，先把 DB 已沉淀 [lesson] 同步进内存档案库，再作评判（查全量判漂移，与 evolve_critic 一致）
      if critic_on {
        ignore(sync_db_lessons(evolve_arc, evolve_store))
      }
      let gated = if critic_on { Some(evolve_arc) } else { None }
      match
        engine.challenge(task_id~, by~, factor~, strat~, now=ts, critic=gated) {
        Ok(j) => Ok(@mcp.ToolResult::text(j.stringify()))
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "omega_spec_create",
    "Omega 强验证·语料创建者：为已开启强验证的任务创建本轮语料，并真正持久化写入 specs 表。参数：task_id、author 语料创建者(默认 spec_author)、content 语料内容(必填)、max_rounds 打回上限(默认3，最大10)、now。",
    schema(
      {
        "task_id": string_prop("任务 id（必填）"),
        "author": string_prop("语料创建者身份(默认 spec_author)"),
        "content": string_prop("语料内容（必填）"),
        "max_rounds": int_prop("打回上限(默认3，最大10)"),
        "now": string_prop("时间戳(可选)"),
      },
      ["task_id", "content"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let task_id = get_str(args, "task_id")
      let author = get_str(args, "author", default="spec_author")
      let content = get_str(args, "content")
      let max_rounds = get_int(args, "max_rounds", default=3)
      let ts = get_str(args, "now", default=now_default())
      match
        engine.omega_spec_create(
          task_id~,
          author~,
          content~,
          now=ts,
          max_rounds~,
        ) {
        Ok(j) => Ok(@mcp.ToolResult::text(j.stringify()))
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "omega_spec_review",
    "Omega 强验证·验证者审语料：审核本轮语料。verdict=approve 通过（放行执行），其它值视为打回重做；打回次数超过 max_rounds 自动升级人工裁决，禁止死循环。参数：task_id、reviewer 验证者(默认 verifier)、verdict、reason 审核意见、max_rounds、now。",
    schema(
      {
        "task_id": string_prop("任务 id（必填）"),
        "reviewer": string_prop("验证者身份(默认 verifier)"),
        "verdict": string_prop("approve 通过 / 其它值打回（必填）"),
        "reason": string_prop("审核意见(可选)"),
        "max_rounds": int_prop("打回上限(默认3，最大10)"),
        "now": string_prop("时间戳(可选)"),
      },
      ["task_id", "verdict"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let task_id = get_str(args, "task_id")
      let reviewer = get_str(args, "reviewer", default="verifier")
      let verdict = get_str(args, "verdict")
      let reason = get_str(args, "reason")
      let max_rounds = get_int(args, "max_rounds", default=3)
      let ts = get_str(args, "now", default=now_default())
      match
        engine.omega_spec_review(
          task_id~,
          reviewer~,
          verdict~,
          reason~,
          now=ts,
          max_rounds~,
        ) {
        Ok(j) => Ok(@mcp.ToolResult::text(j.stringify()))
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "omega_result_verify",
    "Omega 强验证·验证者复验成果：执行者完成后，复验成果与语料是否达标。verdict=pass 达标（可提交验收），其它值打回重做；超过 max_rounds 自动升级人工裁决。参数：task_id、reviewer、verdict、reason、max_rounds、now。",
    schema(
      {
        "task_id": string_prop("任务 id（必填）"),
        "reviewer": string_prop("验证者身份(默认 verifier)"),
        "verdict": string_prop("pass 达标 / 其它值打回（必填）"),
        "reason": string_prop("复验意见(可选)"),
        "max_rounds": int_prop("打回上限(默认3，最大10)"),
        "now": string_prop("时间戳(可选)"),
      },
      ["task_id", "verdict"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let task_id = get_str(args, "task_id")
      let reviewer = get_str(args, "reviewer", default="verifier")
      let verdict = get_str(args, "verdict")
      let reason = get_str(args, "reason")
      let max_rounds = get_int(args, "max_rounds", default=3)
      let ts = get_str(args, "now", default=now_default())
      match
        engine.omega_result_verify(
          task_id~,
          reviewer~,
          verdict~,
          reason~,
          now=ts,
          max_rounds~,
        ) {
        Ok(j) => Ok(@mcp.ToolResult::text(j.stringify()))
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "omega_status",
    "Omega 强验证状态查询：返回该任务是否开启强验证、语料/复验轮次、打回次数、是否已升级人工。参数：task_id。",
    schema({ "task_id": string_prop("任务 id（必填）") }, ["task_id"]),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let task_id = get_str(args, "task_id")
      match engine.omega_status(task_id) {
        Ok(j) => Ok(@mcp.ToolResult::text(j.stringify()))
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )
  s1 = instrumented_tool(
    s1,
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
        Ok(_) =>
          Ok(
            @mcp.ToolResult::text(
              Json::object({
                "task_id": Json::string(task_id),
                "assignee": Json::string(assignee),
                "ok": Json::boolean(true),
                "message": Json::string("可安全认领（待领取）"),
              }).stringify(),
            ),
          )
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "heartbeat",
    "活动信号上报（AO ActivityState）：任务执行前/执行中周期性上报，超时静默将触发 heal 回滚。参数：task_id、signal(可选默认 active)、now。",
    schema(
      {
        "task_id": string_prop("任务 id（必填）"),
        "signal": string_prop(
          "信号(可选)：pre-execution/active/submit，默认 active",
        ),
        "now": string_prop("时间戳(可选，默认内置)"),
      },
      ["task_id"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let task_id = get_str(args, "task_id")
      let signal = get_str(args, "signal", default="active")
      let ts = get_str(args, "now", default=now_default())
      match engine.get_task(task_id) {
        None => Err(@mcp_types.ToolError("task not found: \{task_id}"))
        Some(_) => {
          // 内存心跳表
          heartbeats.beat(task_id, signal~, now=ts)
          // SQLite 持久化（落库失败仅忽略，不阻塞主流程）
          ignore(
            engine.store_write_heartbeat(
              agent_id="fist-mbt",
              task_id~,
              last_seen=ts,
              status=signal,
            ),
          )
          Ok(
            @mcp.ToolResult::text(
              Json::object({
                "task_id": Json::string(task_id),
                "signal": Json::string(signal),
                "last_seen": Json::string(heartbeats.last_seen_of(task_id)),
              }).stringify(),
            ),
          )
        }
      }
    },
  )
  s1 = instrumented_tool(
    s1,
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
      let ts = get_str(args, "now", default=now_default())
      let timeout_sec = get_int(args, "timeout_sec", default=600)
      match @ops.heal_stale_tasks(engine, heartbeats, ts, timeout_sec~) {
        Ok(healed) =>
          Ok(
            @mcp.ToolResult::text(
              Json::object({
                "healed": Json::array(healed.map(fn(s) { Json::string(s) })),
                "count": Json::number(healed.length().to_double()),
                "message": Json::string("超时静默任务已回滚待重派"),
              }).stringify(),
            ),
          )
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "watchdog_tick",
    "定时任务看门狗编排单入口（推荐仅用于定时任务/无人值守场景，不用于人工指挥流程）：扫描活跃任务，心跳超时则回滚重派；检测到上一轮根任务已完成且提供了 next_description（或可由 meta_prompt_path 读取元提示词）时自动发布下一轮。参数：now、timeout_sec(可选默认600)、namespace(可选，未传则不自动续轮)、next_description(可选)、next_created_by(可选默认watchdog)、meta_prompt_path(可选)、cold_start(可选默认false，冷启动时设为true以发布首个任务)、project_dir(可选，冷启动时用于指定项目目录)、omega_strong_verify(可选默认false，开启后自动拆分并启用Omega强验证)、omega_split_n(可选默认3)、omega_spec(可选JSON)。",
    schema(
      {
        "now": string_prop("当前时间戳(默认内置)"),
        "timeout_sec": int_prop("心跳超时秒数(可选默认600)"),
        "namespace": string_prop(
          "作用域命名空间(可选)：自动续轮/自动 heal 只作用于该 ns，未传则不自动续轮",
        ),
        "next_description": string_prop(
          "下一轮任务描述(可选，缺省则不自动续轮)",
        ),
        "next_created_by": string_prop(
          "下一轮任务创建者(可选默认watchdog)",
        ),
        "meta_prompt_path": string_prop(
          "元提示词文档路径(可选)：单个文档或目录，目录内按 yyyyMMdd.HH.mm.ss.md 取最新一份",
        ),
        "cold_start": bool_prop(
          "冷启动模式(可选默认false)：设为true时，若命名空间无已完成根任务，则发布首个任务",
        ),
        "project_dir": string_prop(
          "项目目录(可选)：冷启动时用于指定项目路径",
        ),
        "omega_strong_verify": bool_prop(
          "Omega 强验证开关(可选默认false)：开启后新根任务自动拆分并打 [omega:required] 标记",
        ),
        "omega_split_n": int_prop(
          "Omega 强验证拆分数(可选默认3)：每层子任务数",
        ),
        "omega_spec": string_prop(
          "可选 Omega spec JSON(可选)：laws 作切割依据，fingerprint 作验收基准",
        ),
        "selfdrive_project_dir": string_prop(
          "自驱式编程整合(可选)：提供时会探测该项目的记忆审视轮，结果挂到 detail.selfdrive（报告先行）",
        ),
        "selfdrive_review_every": int_prop(
          "自驱审视频率(可选默认3)：每满 N 份 Reports 报告触发一轮审视",
        ),
      },
      [],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let ts = get_str(args, "now", default=now_default())
      let timeout_sec = get_int(args, "timeout_sec", default=600)
      let ns = get_str(args, "namespace")
      let next_description = get_str(args, "next_description")
      let next_created_by = get_str(args, "next_created_by", default="watchdog")
      let meta_prompt_path = get_str(args, "meta_prompt_path")
      let cold_start = get_bool(args, "cold_start", default=false)
      let project_dir = get_str(args, "project_dir")
      let omega_strong_verify = get_bool(
        args,
        "omega_strong_verify",
        default=false,
      )
      let omega_split_n = get_int(args, "omega_split_n", default=3)
      let omega_spec_str = get_str(args, "omega_spec")
      let selfdrive_project_dir = get_str(args, "selfdrive_project_dir")
      let selfdrive_review_every = get_int(
        args,
        "selfdrive_review_every",
        default=3,
      )
      let omega_spec = if omega_spec_str == "" {
        None
      } else {
        match @omega.parse_spec(omega_spec_str) {
          Ok(j) => Some(j)
          Err(_) => None
        }
      }
      match
        @ops.watchdog_tick(
          engine,
          ts,
          timeout_sec~,
          ns~,
          next_description~,
          next_created_by~,
          meta_prompt_path~,
          cold_start~,
          project_dir~,
          omega_strong_verify~,
          omega_split_n~,
          omega_spec~,
          selfdrive_project_dir~,
          selfdrive_review_every~,
        ) {
        Ok(j) => Ok(@mcp.ToolResult::text(j.stringify()))
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "pipeline_tick",
    "提示词流水线状态机单入口（仅用于定时任务/无人值守命名空间，不用于人工指挥流程）：以 project_dir/currentState.txt 为唯一状态源，按四分支推进——空闲(Creating/Closed)生成新提示词、提示词已落盘(Pending)发布根任务、执行中(Running)缺报告且超时则要求补报告、报告落盘后校验收口。全程报告先行、不空转、不写脏数据。参数：project_dir(必填)、now(可选)、namespace(可选默认cron-auto)、phase(可选auto/prompt_ready/report_ready)、prompt_name(可选)、timeout_sec(可选默认2400)。",
    schema(
      {
        "project_dir": string_prop(
          "项目目录(必填)：其下 currentState.txt 为状态源，Gen_Prompts 为提示词目录",
        ),
        "now": string_prop("当前时间戳(可选，默认内置)"),
        "namespace": string_prop(
          "作用域命名空间(可选默认 cron-auto)：不得为 default",
        ),
        "phase": string_prop(
          "阶段(可选默认 auto)：auto 自动推进 / prompt_ready 提示词已落盘 / report_ready 报告已落盘",
        ),
        "prompt_name": string_prop(
          "指定提示词文件名(可选，缺省取目录内最新一份)",
        ),
        "timeout_sec": int_prop("执行超时秒数(可选默认2400)"),
      },
      [],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let ts = get_str(args, "now", default=now_default())
      let project_dir = get_str(args, "project_dir")
      let ns = get_str(args, "namespace", default="cron-auto")
      let phase = get_str(args, "phase", default="auto")
      let prompt_name = get_str(args, "prompt_name")
      let timeout_sec = get_int(args, "timeout_sec", default=2400)
      match
        @ops.pipeline_tick(
          engine,
          project_dir,
          ts,
          ns~,
          timeout_sec~,
          phase~,
          prompt_name~,
        ) {
        Ok(j) => Ok(@mcp.ToolResult::text(j.stringify()))
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "selfdrive_init",
    "自驱式编程·初始化 memory 四件套（product/target/task/thinking + reviews 目录），幂等不覆盖。参数：project_dir(必填)、namespace(可选默认 default)。",
    schema(
      {
        "project_dir": string_prop(
          "项目目录（必填）：其下生成 memory/ 四件套",
        ),
        "namespace": string_prop("命名空间(可选默认 default)"),
      },
      ["project_dir"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let project_dir = get_str(args, "project_dir")
      let ns = get_str(args, "namespace", default="default")
      match @ops.selfdrive_memory_init(project_dir, ns~) {
        Ok(j) => Ok(@mcp.ToolResult::text(j.stringify()))
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "selfdrive_append",
    "自驱式编程·追加/更新 memory 条目。参数：project_dir(必填)、kind(必填 thinking/product/target/task)、content(必填)、namespace、now(可选)。thinking 为 append-only 流水带时间戳；其余覆盖写。",
    schema(
      {
        "project_dir": string_prop("项目目录（必填）"),
        "kind": string_prop(
          "条目类型（必填）：thinking/product/target/task",
        ),
        "content": string_prop("内容（必填）"),
        "namespace": string_prop("命名空间(可选默认 default)"),
        "now": string_prop("时间戳(可选，默认内置)"),
      },
      ["project_dir", "kind", "content"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let project_dir = get_str(args, "project_dir")
      let kind = get_str(args, "kind")
      let content = get_str(args, "content")
      let ns = get_str(args, "namespace", default="default")
      let ts = get_str(args, "now", default=now_default())
      match
        @ops.selfdrive_memory_append(project_dir, ns~, kind~, content~, now=ts) {
        Ok(j) => Ok(@mcp.ToolResult::text(j.stringify()))
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "selfdrive_get",
    "自驱式编程·读取指定 memory 文件。参数：project_dir(必填)、kind(必填 thinking/product/target/task)、namespace。返回 {exists, content}。",
    schema(
      {
        "project_dir": string_prop("项目目录（必填）"),
        "kind": string_prop(
          "条目类型（必填）：thinking/product/target/task",
        ),
        "namespace": string_prop("命名空间(可选默认 default)"),
      },
      ["project_dir", "kind"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let project_dir = get_str(args, "project_dir")
      let kind = get_str(args, "kind")
      let ns = get_str(args, "namespace", default="default")
      match @ops.selfdrive_memory_get(project_dir, ns~, kind~) {
        Ok(j) => Ok(@mcp.ToolResult::text(j.stringify()))
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "selfdrive_export_tasks",
    "自驱式编程·从任务库导出任务清单到 task.md（视图覆盖写）。参数：project_dir(必填)、namespace(可选默认 default)。",
    schema(
      {
        "project_dir": string_prop("项目目录（必填）"),
        "namespace": string_prop("命名空间(可选默认 default)"),
      },
      ["project_dir"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let project_dir = get_str(args, "project_dir")
      let ns = get_str(args, "namespace", default="default")
      match @ops.selfdrive_export_tasks(engine, project_dir, ns) {
        Ok(j) => Ok(@mcp.ToolResult::text(j.stringify()))
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "selfdrive_review_tick",
    "自驱式编程·审视轮判定：Reports/ 报告数 - 已审视轮次 >= review_every 触发审视返回 action=review（附最近报告+memory 摘要），否则返回 idle/no_memory/safe_exit。参数：project_dir(必填)、review_every(可选默认3)、namespace。",
    schema(
      {
        "project_dir": string_prop("项目目录（必填）"),
        "review_every": int_prop(
          "审视频率(可选默认3)：每满 N 份报告触发一轮",
        ),
        "namespace": string_prop("命名空间(可选默认 default)"),
      },
      ["project_dir"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let project_dir = get_str(args, "project_dir")
      let review_every = get_int(args, "review_every", default=3)
      let ns = get_str(args, "namespace", default="default")
      match @ops.selfdrive_review_tick(project_dir, ns~, review_every~) {
        Ok(j) => Ok(@mcp.ToolResult::text(j.stringify()))
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "selfdrive_review_ready",
    "自驱式编程·审视收口：确认 memory/reviews/ 最新审视报告已落盘并推进已审视轮次（报告先行，无报告拒绝推进）。参数：project_dir(必填)、namespace。",
    schema(
      {
        "project_dir": string_prop("项目目录（必填）"),
        "namespace": string_prop("命名空间(可选默认 default)"),
      },
      ["project_dir"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let project_dir = get_str(args, "project_dir")
      let ns = get_str(args, "namespace", default="default")
      match @ops.selfdrive_review_ready(project_dir, ns~) {
        Ok(j) => Ok(@mcp.ToolResult::text(j.stringify()))
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "selfdrive_publish_next",
    "自驱式编程·解析最新审视报告 `## Next Tasks` 段并将待办任务并行发布为同命名空间下独立根任务（幂等，description 内嵌 [review:<file>:<idx>] 标记防重）。参数：project_dir(必填)、namespace(可选默认 default)、max_tasks(可选默认10)、now(可选)。",
    schema(
      {
        "project_dir": string_prop("项目目录（必填）"),
        "namespace": string_prop("命名空间(可选默认 default)"),
        "max_tasks": int_prop("最多发布任务数(可选默认10)"),
        "now": string_prop("时间戳(可选，默认内置)"),
      },
      ["project_dir"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let project_dir = get_str(args, "project_dir")
      let ns = get_str(args, "namespace", default="default")
      let max_tasks = get_int(args, "max_tasks", default=10)
      let ts = get_str(args, "now", default=now_default())
      match
        @ops.selfdrive_publish_next(
          engine,
          project_dir,
          ns~,
          max_tasks~,
          now=ts,
        ) {
        Ok(j) => Ok(@mcp.ToolResult::text(j.stringify()))
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "selfdrive_parse_next_tasks",
    "自驱式编程·纯解析审视报告文本中的 `## Next Tasks` 段（调试/校验用）。参数：content(必填)、max_tasks(可选默认10)。",
    schema(
      {
        "content": string_prop("审视报告全文（必填）"),
        "max_tasks": int_prop("最多返回任务数(可选默认10)"),
      },
      ["content"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let content = get_str(args, "content")
      let max_tasks = get_int(args, "max_tasks", default=10)
      let tasks = @ops.selfdrive_parse_next_tasks(content, max_tasks~)
      Ok(
        @mcp.ToolResult::text(
          Json::object({
            "tasks": Json::array(tasks.map(fn(t) { Json::string(t) })),
            "count": Json::number(tasks.length().to_double()),
          }).stringify(),
        ),
      )
    },
  )
  s1 = instrumented_tool(
    s1,
    "memory_consolidate",
    "自我记忆·收敛写回：verify 通过后把交付物/结论收敛写回 memory/{kind}.md（kind 缺省 target；thinking 为 append-only 带时间戳，其余覆盖写）。参数：project_dir(必填)、task_id(必填)、kind(可选默认 target)、content(必填)、now(可选)。返回 {consolidated, kind, chars, note}。",
    schema(
      {
        "project_dir": string_prop("项目目录（必填）"),
        "task_id": string_prop("任务 id（必填，用于 tags 注入）"),
        "kind": string_prop(
          "条目类型(可选)：thinking/product/target/task，默认 target",
        ),
        "content": string_prop("收敛内容（必填）"),
        "now": string_prop("时间戳(可选，默认内置)"),
      },
      ["project_dir", "task_id", "content"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let project_dir = get_str(args, "project_dir")
      let task_id = get_str(args, "task_id")
      let kind = get_str(args, "kind", default="target")
      let content = get_str(args, "content")
      let ts = get_str(args, "now", default=now_default())
      match memory_consolidate(project_dir, task_id, kind, content, ts) {
        Ok(j) => Ok(@mcp.ToolResult::text(j.stringify()))
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "memory_gc",
    "自我记忆·上限+软降权归档（不硬删）：超 max_chars 时把 memory/{kind}.md 末尾（老人）条目移入 memory/archive/ 归档保留，正文只保留最新 max_chars 个字符。kind 缺省对四件套全部处理。参数：project_dir(必填)、kind(可选)、max_chars(可选默认2000)、now(可选)。",
    schema(
      {
        "project_dir": string_prop("项目目录（必填）"),
        "kind": string_prop(
          "条目类型(可选)：thinking/product/target/task；缺省处理全部四件套",
        ),
        "max_chars": int_prop("正文上限(可选默认2000)"),
        "now": string_prop("时间戳(可选，默认内置)"),
      },
      ["project_dir"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let project_dir = get_str(args, "project_dir")
      let kind = get_str(args, "kind")
      let max_chars = get_int(args, "max_chars", default=2000)
      let j = if kind == "" {
        memory_gc_all(project_dir, max_chars)
      } else {
        memory_gc_one(project_dir, kind, max_chars)
      }
      Ok(@mcp.ToolResult::text(j.stringify()))
    },
  )
  s1 = instrumented_tool(
    s1,
    "memory_link",
    "自我记忆·A-Mem 式关联：在 memory/links.md 追加一条 `from -> to  note` 关联记录（不存在则创建），供 plan/claim 前检索注入。参数：project_dir(必填)、from(必填)、to(必填)、note(可选)、now(可选)。返回 {linked, from, to}。",
    schema(
      {
        "project_dir": string_prop("项目目录（必填）"),
        "from": string_prop("来源概念/任务（必填）"),
        "to": string_prop("目标概念/任务（必填）"),
        "note": string_prop("关联说明(可选)"),
        "now": string_prop("时间戳(可选，默认内置)"),
      },
      ["project_dir", "from", "to"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let project_dir = get_str(args, "project_dir")
      let from = get_str(args, "from")
      let to = get_str(args, "to")
      let note = get_str(args, "note")
      match memory_link(project_dir, from, to, note) {
        Ok(j) => Ok(@mcp.ToolResult::text(j.stringify()))
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "evolve_distill",
    "DGM 演化·自进化蒸馏（EvolveR 最小级）：把一次 verify 通过的任务交付物蒸馏成一条 principle 写入 DGM（goal 前加 [principle] 前缀标识，code 写蒸馏内容，复用既有 evolve_upsert 落库 + Archive 查重语义）。参数：task_id(必填)、goal(必填)、note(必填)、score(可选默认1.0)、now(可选)。返回 {distilled, artifact_id}。",
    schema(
      {
        "task_id": string_prop("任务 id（必填）"),
        "goal": string_prop("蒸馏出的原则/目标（必填）"),
        "note": string_prop(
          "原则说明/设计意图（必填，同时写入 code）",
        ),
        "score": number_prop("可计算评分(默认1.0)"),
        "now": string_prop("时间戳(可选，默认内置)"),
      },
      ["task_id", "goal", "note"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let goal = get_str(args, "goal")
      let note = get_str(args, "note")
      let score = get_double(args, "score", default=1.0)
      let ts = get_str(args, "now", default=now_default())
      let j = do_evolve_distill(evolve_arc, evolve_store, goal, note, score, ts)
      Ok(@mcp.ToolResult::text(j.stringify()))
    },
  )
  s1 = instrumented_tool(
    s1,
    "evolve_submit",
    "DGM 演化·归档一个产物（Artifact）：把本轮设计/代码/目标加入档案库，自动递增父代子代数。参数：id、goal、note、code、score、parent_id(可选)、parts(可选 JSON 对象)、now(可选)。",
    schema(
      {
        "id": string_prop("产物 id（必填，唯一）"),
        "goal": string_prop("目标/本轮想解决的问题（必填）"),
        "note": string_prop("设计意图（必填，查重/新颖性用）"),
        "code": string_prop("实现内容（必填）"),
        "score": number_prop("可计算评分(默认0)"),
        "parent_id": string_prop("父产物 id（可选）"),
        "parts": string_prop("评分分项 JSON(可选)"),
        "now": string_prop("时间戳(可选，默认内置)"),
      },
      ["id", "goal", "note", "code"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let id = get_str(args, "id")
      let goal = get_str(args, "goal")
      let note = get_str(args, "note")
      let code = get_str(args, "code")
      let score = get_double(args, "score", default=0.0)
      let parent_id = get_str(args, "parent_id", default="")
      let parts_raw = get_str(args, "parts", default="{}")
      let ts = get_str(args, "now", default=now_default())
      let parts : Map[String, Double] = Map([])
      let parsed = @json.parse(parts_raw) catch { _ => Json::object(Map([])) }
      match parsed {
        Object(pm) =>
          for (k, v) in pm {
            match v {
              Number(n, ..) => parts.set(k, n)
              _ => ()
            }
          }
        _ => ()
      }
      let art = @evolve.Artifact::create(
        id~,
        parent_id=if parent_id == "" { None } else { Some(parent_id) },
        goal~,
        note~,
        code~,
        score~,
        parts~,
        created_at=ts,
      )
      // 查重：重复目标丢弃（DGM/Voyager 必修），除非阈值宽松
      if @evolve.Archive::is_duplicate(evolve_arc, goal, threshold=0.88) {
        return Ok(
          @mcp.ToolResult::text(
            Json::object({
              "rejected": Json::boolean(true),
              "reason": Json::string(
                "目标与档案库中已有产物高度相似，丢弃",
              ),
            }).stringify(),
          ),
        )
      }
      @evolve.Archive::add(evolve_arc, art)
      Ok(@mcp.ToolResult::text(art.to_json().stringify()))
    },
  )
  s1 = instrumented_tool(
    s1,
    "evolve_lesson",
    "自进化·失败回流学习（learn-from-reject）：把一次被打回/失败的原因归档成一条 [lesson]<类目> 资产入 DGM，让建档库能「学教训」——note 存失败原因、code 存纠偏提示，plan/claim 的 inject 可按类目命中「踩过的坑」。参数：cat 类目(必填，检索 tag)、reason 失败原因(必填)、fix 纠偏提示(可选)、score(可选默认0.5)、now。返回 {learned, artifact_id}。",
    schema(
      {
        "cat": string_prop(
          "教训类目（必填，检索 tag，自动拼成 goal=[lesson]<cat>）",
        ),
        "reason": string_prop("失败/被打回的原因（必填）"),
        "fix": string_prop("纠偏提示/来源（可选，无则用 reason）"),
        "score": number_prop("可计算评分(默认0.5)"),
        "now": string_prop("时间戳(可选，默认内置)"),
      },
      ["cat", "reason"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let cat = get_str(args, "cat")
      let reason = get_str(args, "reason")
      let fix = get_str(args, "fix")
      let score = get_double(args, "score", default=0.5)
      let ts = get_str(args, "now", default=now_default())
      if cat == "" || reason == "" {
        return Err(@mcp_types.ToolError("cat/reason 均为必填"))
      }
      let j = do_evolve_lesson(evolve_arc, evolve_store, cat, reason, fix, ts)
      Ok(@mcp.ToolResult::text(j.stringify()))
    },
  )
  s1 = instrumented_tool(
    s1,
    "evolve_critic",
    "自进化·Critic 防漂移门禁（SAGE 论文落地，杜绝课程漂移）：把一条「拟入库的 principle/lesson/资产」的 note 交给 Critic 评审，复用 Archive::novelty + scoring 纯计算，返回是否放行 {admit} 与理由——与档案库最相似资产重合 ≥70% 判「疑似课程漂移/重复」直接建议拒绝；综合分(0.5*score+0.5*新颖度)低于阈值判「稳健性不足」暂缓入库。只评审不写库，供入库前决策。参数：note 候选资产意图/原因(必填)、score 可计算评分(默认0.5)、threshold 放行阈值(默认0.85)、now。返回含 top_hit 最相似资产。",
    schema(
      {
        "note": string_prop(
          "候选资产的意图/原因（必填，用于新颖度/查重）",
        ),
        "score": number_prop("可计算评分(默认0.5)"),
        "threshold": number_prop("放行阈值(默认0.85)"),
        "now": string_prop("时间戳(可选，默认内置)"),
      },
      ["note"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let note = get_str(args, "note")
      let score = get_double(args, "score", default=0.5)
      let threshold = get_double(args, "threshold", default=0.85)
      // 先把 DB 中已沉淀的 [lesson] 教训同步进内存档案库，使 Critic 能对"全量"判漂移
      ignore(sync_db_lessons(evolve_arc, evolve_store))
      let j = @evolve.critic_review(evolve_arc, note, score, threshold~)
      Ok(@mcp.ToolResult::text(j.stringify()))
    },
  )
  s1 = instrumented_tool(
    s1,
    "evolve_asset_register",
    "DGM 演化·注册一个可选外部资产（如 code-review / superpowers 类 skill 库）：作为 Artifact 归档进档案库，goal 用 [asset]<来源名> 便于 plan/claim 的 inject 按关键词检索，note 放可注入提示词、code 放来源路径/URL。返回产物 JSON；asset_id 可省略（自动生成，避免与既有产物 id 冲突）。",
    schema(
      {
        "source": string_prop(
          "资产来源名/关键词（必填，如 code-review）；检索用，自动拼成 goal=[asset]<source>",
        ),
        "note": string_prop("可注入提示词（必填）"),
        "code": string_prop("来源路径或 URL（必填）"),
        "score": number_prop("可计算评分(默认0)"),
        "now": string_prop("时间戳(可选，默认内置)"),
      },
      ["source", "note", "code"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let source = get_str(args, "source")
      let note = get_str(args, "note")
      let code = get_str(args, "code")
      let score = get_double(args, "score", default=0.0)
      let ts = get_str(args, "now", default=now_default())
      if source == "" || note == "" || code == "" {
        return Err(@mcp_types.ToolError("source/note/code 均为必填"))
      }
      let goal = "[asset]\{source}"
      let asset_id = "asset-\{source}-\{ts}"
      let art = @evolve.Artifact::create(
        id=asset_id,
        parent_id=None,
        goal~,
        note~,
        code~,
        score~,
        parts=Map([]),
        created_at=ts,
      )
      @evolve.Archive::add(evolve_arc, art)
      Ok(@mcp.ToolResult::text(art.to_json().stringify()))
    },
  )
  s1 = instrumented_tool(
    s1,
    "evolve_snapshot",
    "DGM 演化·查看档案库快照（含 best/lineage/summaries/dead_ends）。参数：无。",
    schema({}, []),
    async fn(_args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      // 先同步 DB 中已沉淀的 [lesson]（含 Omega 打回自动落库的）进内存档案库，
      // 使 dead_ends 能如实反映"踩过的坑（此路不通）"。
      ignore(sync_db_lessons(evolve_arc, evolve_store))
      let best = match @evolve.Archive::best(evolve_arc) {
        Some(a) => a.to_json()
        None => Json::null()
      }
      let summaries = Json::array(
        @evolve.Archive::summaries(evolve_arc, limit=12).map(fn(s) {
          Json::string(s)
        }),
      )
      let dead = Json::array(
        @evolve.Archive::dead_ends(evolve_arc, limit=8).map(fn(s) {
          Json::string(s)
        }),
      )
      let lineage = match @evolve.Archive::best(evolve_arc) {
        Some(b) =>
          Json::array(
            @evolve.Archive::lineage(evolve_arc, b.id, depth=12).map(fn(l) {
              let (lid, lscore, lgoal) = l
              Json::string("[\{lid} score=\{lscore} ] \{lgoal}")
            }),
          )
        None => Json::array([])
      }
      Ok(
        @mcp.ToolResult::text(
          Json::object({
            "count": Json::number(@evolve.Archive::len(evolve_arc).to_double()),
            "best": best,
            "summaries": summaries,
            "dead_ends": dead,
            "lineage_of_best": lineage,
          }).stringify(),
        ),
      )
    },
  )
  s1 = instrumented_tool(
    s1,
    "evolve_sample",
    "DGM 演化·按 p∝s·h 多样性加权采样父代产物（子代越少/性能越高越可能被选）。参数：rand(可选)。",
    schema({ "rand": number_prop("伪随机种子(可选，[0,1))") }, []),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let r = get_double(args, "rand", default=0.5)
      let picked = @evolve.Archive::sample_parent(evolve_arc, rand=fn() { r })
      match picked {
        Some(a) =>
          Ok(
            @mcp.ToolResult::text(
              Json::object({ "picked": a.to_json() }).stringify(),
            ),
          )
        None =>
          Ok(
            @mcp.ToolResult::text(
              Json::object({
                "picked": Json::null(),
                "note": Json::string(
                  "档案库为空，先 evolve_submit 添加产物",
                ),
              }).stringify(),
            ),
          )
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "laya_decide",
    "Laya 可选决策工具（自动探测）：用 Laya（Python ML 决策模型）对任务/文本快速分类。命中时返回结构化 answers（task_type/urgency/needs_review 等）；机器无 laya 或探测失败则返回 available:false，调用方照旧走 schedule/LLM，不影响现网。参数：context(必填)、questions(可选 JSON)、model(可选默认 english)。",
    schema(
      {
        "context": string_prop("待决策的任务/文本描述（必填）"),
        "questions": string_prop(
          "决策问题 schema JSON（可选；缺省用 Laya 内置 default questions）",
        ),
        "model": string_prop("Laya 模型(可选默认 english)"),
      },
      ["context"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let context = get_str(args, "context")
      if context == "" {
        return Err(@mcp_types.ToolError("context 不能为空"))
      }
      let questions_raw = get_str(args, "questions", default="")
      let model = get_str(args, "model", default="english")
      // 1) 探测（--probe 仅 import laya，较快；每次调用探测以保证实时准确性）
      let probe : Result[Bool, String] = laya_probe_available(
        "python",
        ["scripts/laya_decide.py", "--probe"],
        ".",
        15000,
      )
      let avail = match probe {
        Ok(a) => a
        Err(_) => false
      }
      if not(avail) {
        return Ok(
          @mcp.ToolResult::text(
            Json::object({
              "available": Json::boolean(false),
              "fallback": Json::string("use existing schedule / LLM"),
              "reason": Json::string(
                "机器上未探测到 Laya（python-sidecar 不可用），已降级",
              ),
            }).stringify(),
          ),
        )
      }
      // 2) 可用 → 调 sidecar 决策
      let questions_json : Json = if questions_raw == "" {
        Json::null()
      } else {
        @json.parse(questions_raw) catch {
          _ => Json::null()
        }
      }
      let input_json = Json::object({
        "context": Json::string(context),
        "questions": questions_json,
        "model": Json::string(model),
      }).stringify()
      match
        laya_decide_external(
          "python",
          ["scripts/laya_decide.py"],
          ".",
          input_json,
          300000,
        ) {
        Ok(res) => Ok(@mcp.ToolResult::text(res.stringify()))
        Err(e) =>
          // 调度失败也降级（不报错）
          Ok(
            @mcp.ToolResult::text(
              Json::object({
                "available": Json::boolean(false),
                "fallback": Json::string("use existing schedule / LLM"),
                "reason": Json::string("laya sidecar 调用失败: \{e}"),
              }).stringify(),
            ),
          )
      }
    },
  )
  s1 = instrumented_tool(
    s1,
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
      let ts = get_str(args, "now", default=now_default())
      let retention_days = get_int(args, "retention_days", default=30)
      match @ops.cleanup_archived(engine, ts, retention_days~) {
        Ok(removed) =>
          Ok(
            @mcp.ToolResult::text(
              Json::object({
                "removed": Json::array(removed.map(fn(s) { Json::string(s) })),
                "count": Json::number(removed.length().to_double()),
                "message": Json::string("已清理过期归档任务"),
              }).stringify(),
            ),
          )
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )

  // ---- ATGC 双链虚拟机（嵌入式子项目，纯 MoonBit）----
  s1 = instrumented_tool(
    s1,
    "atgc_old_compile",
    "ATGC 双链虚拟机(全量参照 atgc-old)·编译：把 DNA 序列转录成 mRNA 并翻译成操作列表。参数：seq(必填) DNA 序列（仅允许 A/T/G/C/U 与空白/`;;` 注释，大小写不敏感）。返回 {transcription, ops, mode, antisense, rollback} JSON。",
    schema(
      {
        "seq": string_prop(
          "DNA 序列（必填）：仅允许 [ATGCU] 碱基与空白/注释",
        ),
      },
      ["seq"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let seq = get_str(args, "seq")
      match @atgc_old.atgc_compile(seq) {
        Ok(j) => Ok(@mcp.ToolResult::text(j))
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "atgc_old_run",
    "ATGC 双链虚拟机(全量参照 atgc-old)·运行：执行 DNA 程序（含快照回滚）。参数：seq(必填)。返回 {output, stack_history, final_stack, result, rolled_back} JSON。",
    schema(
      {
        "seq": string_prop(
          "DNA 序列（必填）：仅允许 [ATGCU] 碱基与空白/注释",
        ),
      },
      ["seq"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let seq = get_str(args, "seq")
      match @atgc_old.atgc_run(seq) {
        Ok(j) => Ok(@mcp.ToolResult::text(j))
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "atgc_old_talk",
    "ATGC 双链虚拟机(全量参照 atgc-old)·叙事对话：把 DNA 程序讲成生物故事（转录→mRNA→翻译→酶执行）并输出最终数值；可选择性回答自由问题；无 seq 时返回双链虚拟机简介。参数：seq(可选)、question(可选)。",
    schema(
      {
        "seq": string_prop(
          "DNA 序列（可选）：无则返回双链虚拟机简介",
        ),
        "question": string_prop(
          "自由问题（可选）：以叙事方式回答",
        ),
      },
      [],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let seq = get_str(args, "seq")
      let question = get_str(args, "question")
      Ok(@mcp.ToolResult::text(@atgc_old.atgc_talk(seq, question)))
    },
  )

  // ---- resources ----
  s1 = s1.resource(
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
  s1 = s1.resource(
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

  s1 = s1.resource(
    "fist://map",
    "项目地图",
    "fist-mbt 结构地图（Repo Map）：src/ 各子包职责、MCP 工具分组、入口引导，供 AI agent 首读定位，避免全项目盲目探索",
    "application/json",
    async fn() -> Result[@mcp_resource.ResourceReadResult, @mcp.MCPError] {
      Ok({
        uri: "fist://map",
        content: @mcp_resource.ResourceContent::Text(map_json().stringify()),
      })
    },
  )

  // ---- prompts ----
  s1 = s1.prompt(
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
  s1 = s1.prompt(
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
  s1 = instrumented_tool(
    s1,
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
      let ts = get_str(args, "now", default=now_default())
      let depends_on : Array[String] = try {
        match @json.parse(depends_on_raw) {
          Json::Array(a) => a.map(fn(v) { v.as_string().unwrap_or("") })
          _ => []
        }
      } catch {
        _ => []
      }
      let id = match
        engine.publish_with_deps(
          project_dir~,
          description~,
          depends_on~,
          created_by~,
          now=ts,
          ns~,
        ) {
        Ok(id) => id
        Err(e) => return Err(@mcp_types.ToolError(e))
      }
      Ok(
        @mcp.ToolResult::text(
          Json::object({
            "task_id": Json::string(id),
            "message": Json::string("已发布根任务（带依赖）"),
          }).stringify(),
        ),
      )
    },
  )
  s1 = instrumented_tool(
    s1,
    "dag_depend",
    "给任务追加一条前置依赖（显式构建 DAG 依赖边，不只靠 plan_deep 隐式父子；供 dag_check/ready/critical_path/ascii 使用）。参数：task_id 任务(必经)、dep_id 前置依赖任务 id(必经)、now。幂等去重；校验两任务存在且非自身。返回追加后的任务 JSON。",
    schema(
      {
        "task_id": string_prop("任务 id（必填）"),
        "dep_id": string_prop("前置依赖任务 id（必填）"),
        "now": string_prop("时间戳(可选)"),
      },
      ["task_id", "dep_id"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let task_id = get_str(args, "task_id")
      let dep_id = get_str(args, "dep_id")
      let ts = get_str(args, "now", default=now_default())
      to_result(engine.dag_depend(task_id~, dep_id~, now=ts))
    },
  )
  s1 = instrumented_tool(
    s1,
    "dag_critical_path",
    "返回当前最长依赖链（关键路径）。无参数。",
    schema({}, []),
    async fn(_args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let path = engine.critical_path()
      Ok(
        @mcp.ToolResult::text(
          Json::object({
            "critical_path": Json::array(path.map(fn(id) { Json::string(id) })),
            "length": Json::number(path.length().to_double()),
          }).stringify(),
        ),
      )
    },
  )
  s1 = instrumented_tool(
    s1,
    "dag_parallelism",
    "返回当前可并行执行的任务数（待领取且依赖已满足）。无参数。",
    schema({}, []),
    async fn(_args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let n = engine.parallelism()
      Ok(
        @mcp.ToolResult::text(
          Json::object({ "parallelism": Json::number(n.to_double()) }).stringify(),
        ),
      )
    },
  )
  s1 = instrumented_tool(
    s1,
    "dag_ascii",
    "返回当前命名空间任务的 ASCII 依赖结构图。参数：namespace(可选，默认 default)。",
    schema({ "namespace": string_prop("命名空间(默认 default)") }, []),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let ns = get_str(args, "namespace", default="default")
      let ascii = engine.dag_ascii(ns~)
      Ok(
        @mcp.ToolResult::text(
          Json::object({
            "namespace": Json::string(if ns == "" { "default" } else { ns }),
            "ascii": Json::string(ascii),
          }).stringify(),
        ),
      )
    },
  )
  s1 = instrumented_tool(
    s1,
    "board_ascii",
    "返回当前命名空间的实时任务看板 ASCII：按状态分组 + 深度缩进，一眼看全貌（哪些任务、什么状态、在树哪层）。参数：namespace(可选，空=全部命名空间)。",
    schema({ "namespace": string_prop("命名空间(默认全部)") }, []),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let ns = get_str(args, "namespace")
      let board = render_board_ascii(engine.list_all(), ns)
      Ok(@mcp.ToolResult::text(board.stringify()))
    },
  )
  s1 = instrumented_tool(
    s1,
    "status_summary",
    "项目脉冲摘要：返回 { version, total_tasks, by_status:{状态:数量}, active_namespaces }。参数：namespace(可选，只统计该 ns；空=全部)。",
    schema(
      { "namespace": string_prop("命名空间(可选，只统计该 ns)") },
      [],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let ns = get_str(args, "namespace")
      let tasks = if ns == "" {
        engine.list_all()
      } else {
        engine.list_all().filter(fn(t) { t.ns == ns })
      }
      let j = render_status_summary(tasks, mstore.ns_list(), "0.2.4")
      Ok(@mcp.ToolResult::text(j.stringify()))
    },
  )
  s1 = instrumented_tool(
    s1,
    "task_triage",
    "下一步该做啥（推荐式挑选 + 能力偏好路由）：对指定命名空间（namespace 缺省全量）把『待领取且依赖已满足』的任务按 能力匹配(want)→优先级(高>中>低)→重要度(高>中>低)→深度(叶可执行单元优先)→id 排出序，并给出一条 suggestion（此刻建议先领哪条及理由），供 agent 无需全量扫描。难度标签直接复用拆解时的『难度梯度 …:易/中/难』标记。参数：namespace(可选)、agent(调用方身份，可审计)、want 能力关键词(可选，命中者排头部，Marketplookup 雏形)。返回 { count, ns, agent, want, tasks:[...], suggestion? }。",
    schema(
      {
        "namespace": string_prop(
          "命名空间(可选，只统计该 ns；空=全部)",
        ),
        "agent": string_prop(
          "调用方身份(默认 self)，用于 suggestion/审计",
        ),
        "want": string_prop(
          "能力关键词(可选)：命中该关键词的可领取任务排头部(按能力路由)",
        ),
      },
      [],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let ns = get_str(args, "namespace")
      let agent = get_str(args, "agent", default="self")
      let want = get_str(args, "want")
      let j = engine.triage(ns, agent, want)
      Ok(@mcp.ToolResult::text(j.stringify()))
    },
  )
  s1 = instrumented_tool(
    s1,
    "selfdrive_pick_next",
    "自驱·按推荐自动取下一单：对指定命名空间取 task_triage 的顶部推荐并认领给 agent（待领取→已领取；能力匹配 want 优先），让无人值守可按能力推荐自推进。复用 triage 排行 + claim，只动一条推荐任务、不动看门狗主流程（零回归）。参数：namespace(可选)、agent(认领者,默认 self)、want 能力关键词(可选)、now。返回 { picked, remaining, claimed, ns, want, task?, note|error? }。",
    schema(
      {
        "namespace": string_prop("命名空间(可选，空=全部)"),
        "agent": string_prop("认领者身份(默认 self)"),
        "want": string_prop(
          "能力关键词(可选)：命中者可领取任务优先被取单",
        ),
        "now": string_prop("时间戳(可选，默认内置)"),
      },
      [],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let ns = get_str(args, "namespace")
      let agent = get_str(args, "agent", default="self")
      let want = get_str(args, "want")
      let ts = get_str(args, "now", default=now_default())
      let j = engine.pick_next(ns, agent, want, ts)
      Ok(@mcp.ToolResult::text(j.stringify()))
    },
  )
  s1 = instrumented_tool(
    s1,
    "reserve_scope",
    "预订一个工作作用域（文件/目录/资源）防多 agent 并发编辑冲突。若作用域空闲（未被他人活体预订）则由本 agent 占据，否则返回持有者。TTL 由 ttl_until(ISO-8601 未来时间戳串)给定；到时自动视为可让渡。参数：scope、agent、ttl_until(必)、now(时间戳)。",
    schema(
      {
        "scope": string_prop(
          "作用域（如 src/foo.mbt 或模块名，必填）",
        ),
        "agent": string_prop("预订者（如 exec_1，必填）"),
        "ttl_until": string_prop("TTL 截止时间戳（ISO-8601，必填）"),
        "now": string_prop("当前时间戳(可选，默认内置)"),
      },
      ["scope", "agent", "ttl_until"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let scope = get_str(args, "scope")
      let agent = get_str(args, "agent")
      let ttl_until = get_str(args, "ttl_until")
      let now = get_str(args, "now", default=now_default())
      match engine.rsv_get(scope) {
        // 空闲（无预订，或原预订已过期）→ 抢占
        None => {
          let r = engine.rsv_set(scope~, agent~, ttl_until~, created_at=now)
          match r {
            Ok(_) =>
              Ok(
                @mcp.ToolResult::text(
                  Json::object({
                    "scope": Json::string(scope),
                    "agent": Json::string(agent),
                    "ttl_until": Json::string(ttl_until),
                    "reserved": Json::boolean(true),
                    "action": Json::string("reserved"),
                  }).stringify(),
                ),
              )
            Err(e) => Err(@mcp_types.ToolError(e))
          }
        }
        Some((owner, ot, _)) if owner == agent || ot < now => {
          // 同 agent 续期，或原持有者已超时 → 让渡/续期
          let r = engine.rsv_set(scope~, agent~, ttl_until~, created_at=now)
          match r {
            Ok(_) =>
              Ok(
                @mcp.ToolResult::text(
                  Json::object({
                    "scope": Json::string(scope),
                    "agent": Json::string(agent),
                    "ttl_until": Json::string(ttl_until),
                    "reserved": Json::boolean(true),
                    "action": Json::string(
                      if owner == agent {
                        "renewed"
                      } else {
                        "taken_over"
                      },
                    ),
                    "prev_agent": Json::string(owner),
                  }).stringify(),
                ),
              )
            Err(e) => Err(@mcp_types.ToolError(e))
          }
        }
        Some((owner, ot, _)) =>
          Ok(
            @mcp.ToolResult::text(
              Json::object({
                "scope": Json::string(scope),
                "reserved": Json::boolean(false),
                "held_by": Json::string(owner),
                "ttl_until": Json::string(ot),
                "reason": Json::string(
                  "该作用域已被其他 agent 活体预订",
                ),
              }).stringify(),
            ),
          )
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "reserve_check",
    "查询某工作作用域是否可编辑（空闲可用）。参数：scope、now(时间戳)。",
    schema(
      {
        "scope": string_prop("作用域（必填）"),
        "now": string_prop("当前时间戳(可选)"),
      },
      ["scope"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let scope = get_str(args, "scope")
      let now = get_str(args, "now", default=now_default())
      match engine.rsv_get(scope) {
        None =>
          Ok(
            @mcp.ToolResult::text(
              Json::object({
                "scope": Json::string(scope),
                "free": Json::boolean(true),
                "agent": Json::string(""),
              }).stringify(),
            ),
          )
        Some((agent, ttl_until, _)) if ttl_until < now =>
          Ok(
            @mcp.ToolResult::text(
              Json::object({
                "scope": Json::string(scope),
                "free": Json::boolean(true),
                "agent": Json::string(agent),
                "expired_ttl_until": Json::string(ttl_until),
              }).stringify(),
            ),
          )
        Some((agent, ttl_until, _)) =>
          Ok(
            @mcp.ToolResult::text(
              Json::object({
                "scope": Json::string(scope),
                "free": Json::boolean(false),
                "agent": Json::string(agent),
                "ttl_until": Json::string(ttl_until),
              }).stringify(),
            ),
          )
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "reserve_release",
    "释放自己的工作作用域（仅持有者有效）。参数：scope、agent。",
    schema(
      {
        "scope": string_prop("作用域（必填）"),
        "agent": string_prop("持有者（必填）"),
      },
      ["scope", "agent"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let scope = get_str(args, "scope")
      let agent = get_str(args, "agent")
      let ok = engine.rsv_release(scope, agent)
      Ok(
        @mcp.ToolResult::text(
          Json::object({
            "scope": Json::string(scope),
            "released": Json::boolean(ok),
          }).stringify(),
        ),
      )
    },
  )
  s1 = instrumented_tool(
    s1,
    "dag_check",
    "检查某任务的依赖是否全部完成。参数：task_id。",
    schema({ "task_id": string_prop("任务 id（必填）") }, ["task_id"]),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let task_id = get_str(args, "task_id")
      let ok = engine.deps_satisfied(task_id)
      Ok(
        @mcp.ToolResult::text(
          Json::object({
            "task_id": Json::string(task_id),
            "deps_satisfied": Json::boolean(ok),
          }).stringify(),
        ),
      )
    },
  )
  s1 = instrumented_tool(
    s1,
    "dag_ready",
    "列出所有依赖满足、可领取的任务。参数：namespace(可选)。",
    schema({ "namespace": string_prop("命名空间(默认 default)") }, []),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let ns = get_str(args, "namespace", default="default")
      let ready = engine.ready_tasks(ns_filter=ns)
      Ok(
        @mcp.ToolResult::text(
          Json::array(ready.map(fn(t) { t.to_json() })).stringify(),
        ),
      )
    },
  )
  s1 = instrumented_tool(
    s1,
    "dag_sort",
    "对任务列表按依赖深度拓扑排序。参数：task_ids(JSON 数组)。",
    schema(
      { "task_ids": string_prop("任务 id 列表 JSON 数组（必填）") },
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
      Ok(
        @mcp.ToolResult::text(
          Json::object({
            "sorted": Json::array(sorted.map(fn(id) { Json::string(id) })),
          }).stringify(),
        ),
      )
    },
  )

  // ---- Omega 验证工具（金条八：一票否决 + verify_fix）----
  s1 = instrumented_tool(
    s1,
    "omega_verify",
    "批量验证 spec JSON：schema + fingerprint 校验，accuracy < 100% 一票否决。参数：specs(JSON数组，每项 {file_name, content})。",
    schema(
      {
        "specs": array_prop(
          "spec 数组，每项 {file_name: String, content: String}",
        ),
      },
      [],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let specs_raw = get_array(args, "specs")
      let spec_files : Array[(String, String)] = []
      for item in specs_raw {
        match item.value("file_name") {
          Some(String(fname)) => {
            let content = match item.value("content") {
              Some(String(s)) => s
              _ => ""
            }
            if content != "" {
              spec_files.push((fname, content))
            }
          }
          _ => ()
        }
      }
      let result = @omega.batch_verify(spec_files)
      Ok(@mcp.ToolResult::text(result.stringify()))
    },
  )
  s1 = instrumented_tool(
    s1,
    "omega_verify_fix",
    "对失败 spec 做根因分类 → 定向修复 → 回归验证（3 轮循环）。参数：specs(JSON数组，每项 {file_name, content})、max_rounds(可选默认3)。",
    schema(
      {
        "specs": array_prop(
          "spec 数组，每项 {file_name: String, content: String}",
        ),
        "max_rounds": int_prop("最大修复轮次(可选默认3)"),
      },
      [],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let specs_raw = get_array(args, "specs")
      let max_rounds = get_int(args, "max_rounds", default=3)
      let all_spec_contents : Array[(String, String)] = []
      for item in specs_raw {
        match item.value("file_name") {
          Some(String(fname)) => {
            let content = match item.value("content") {
              Some(String(s)) => s
              _ => ""
            }
            if content != "" {
              all_spec_contents.push((fname, content))
            }
          }
          _ => ()
        }
      }
      // 第一轮：批量验证获取失败项
      let verify_result = @omega.batch_verify(all_spec_contents)
      let failed_results : Array[Json] = []
      match verify_result.value("failed_details") {
        Some(Array(fd)) =>
          for fr in fd {
            failed_results.push(fr)
          }
        _ => ()
      }
      // 修复循环
      let fix_result = @omega.batch_verify_fix(failed_results, max_rounds~)
      Ok(@mcp.ToolResult::text(fix_result.stringify()))
    },
  )

  // ---- 成本统计工具 ----
  s1 = instrumented_tool(
    s1,
    "cost_stats",
    "执行成本聚合统计。参数：无。返回：total_records/total_cost/total_tokens_in/total_tokens_out/by_executor。",
    schema({}, []),
    async fn(_args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      Ok(@mcp.ToolResult::text(engine.cost_stats().stringify()))
    },
  )
  s1 = instrumented_tool(
    s1,
    "cost_budget_check",
    "预算超限告警。参数：limit(预算上限)、current(当前消耗)。返回：{exceeded, remaining, action}。",
    schema(
      {
        "limit": number_prop("预算上限（必填）"),
        "current": number_prop("当前消耗（必填）"),
      },
      ["limit", "current"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let result = @engine.budget_check_json(args)
      Ok(@mcp.ToolResult::text(result.stringify()))
    },
  )

  // ---- 调度预览工具 ----
  s1 = instrumented_tool(
    s1,
    "schedule",
    "调度预览：根据任务描述自适应计算分级/拆分/成本档/执行器（不落库）。参数：description(必填)、n_files(可选默认1)。",
    schema(
      {
        "description": string_prop("任务描述（必填）"),
        "n_files": int_prop("涉及文件数(可选默认1)"),
      },
      ["description"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let desc = get_str(args, "description")
      if desc == "" {
        return Err(@mcp_types.ToolError("description 不能为空"))
      }
      let n_files = get_int(args, "n_files", default=1)
      let result = @engine.schedule_json(
        Json::object({
          "description": Json::string(desc),
          "n_files": Json::number(n_files.to_double()),
        }),
      )
      Ok(@mcp.ToolResult::text(result.stringify()))
    },
  )

  // ---- 审计工具 ----
  s1 = instrumented_tool(
    s1,
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
        None =>
          Err(
            @mcp_types.ToolError(
              "未知角色: \{role_s}，合法值：human_steward / leader / agent",
            ),
          )
        Some(role) =>
          match @ops.enforce(action~, role~) {
            Ok(_) =>
              Ok(
                @mcp.ToolResult::text(
                  Json::object({
                    "role": Json::string(role_s),
                    "action": Json::string(action),
                    "allowed": Json::boolean(true),
                  }).stringify(),
                ),
              )
            Err(msg) =>
              Ok(
                @mcp.ToolResult::text(
                  Json::object({
                    "role": Json::string(role_s),
                    "action": Json::string(action),
                    "allowed": Json::boolean(false),
                    "message": Json::string(msg),
                  }).stringify(),
                ),
              )
          }
      }
    },
  )
  s1 = instrumented_tool(
    s1,
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
  s1 = instrumented_tool(
    s1,
    "store_open",
    "打开（或复用）一个命名空间。参数：namespace、data_dir(可选，默认当前目录)、scratch(可选，true 时库落 temp/ 临时区，不污染仓库根)。",
    schema(
      {
        "namespace": string_prop("命名空间（必填）"),
        "data_dir": string_prop(
          "库文件根目录(可选，默认当前目录)",
        ),
        "scratch": bool_prop(
          "临时命名空间开关(可选，默认 false)：true 时强制 data_dir=temp/（gitignore），避免根目录堆 .db",
        ),
      },
      ["namespace"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let ns = get_str(args, "namespace")
      let mut dir = get_str(args, "data_dir", default=".")
      let scratch = get_bool(args, "scratch", default=false)
      // 临时命名空间：强制落到 temp/（gitignore），不污染仓库根
      if scratch {
        @fs.create_dir("temp") catch {
          _ => ()
        }
        dir = "temp"
      }
      match mstore.open(ns~, data_dir=dir) {
        false => Err(@mcp_types.ToolError("打开命名空间失败: \{ns}"))
        true =>
          Ok(
            @mcp.ToolResult::text(
              Json::object({
                "namespace": Json::string(ns),
                "opened": Json::boolean(true),
                "data_dir": Json::string(dir),
                "scratch": Json::boolean(scratch),
                "active_namespaces": Json::array(
                  mstore.ns_list().map(fn(s) { Json::string(s) }),
                ),
              }).stringify(),
            ),
          )
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "store_list",
    "列出当前已打开的命名空间及任务数。无参数。",
    schema({}, []),
    async fn(_args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let list = mstore.ns_list()
      let stats = mstore.ns_stats()
      Ok(
        @mcp.ToolResult::text(
          Json::object({
            "active_namespaces": Json::array(
              list.map(fn(s) { Json::string(s) }),
            ),
            "stats": stats,
          }).stringify(),
        ),
      )
    },
  )
  s1 = instrumented_tool(
    s1,
    "store_close",
    "关闭指定命名空间（不删除物理库文件）。参数：namespace。",
    schema({ "namespace": string_prop("命名空间（必填）") }, [
      "namespace",
    ]),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let ns = get_str(args, "namespace")
      mstore.close(ns)
      Ok(
        @mcp.ToolResult::text(
          Json::object({
            "namespace": Json::string(ns),
            "closed": Json::boolean(true),
            "active_namespaces": Json::array(
              mstore.ns_list().map(fn(s) { Json::string(s) }),
            ),
          }).stringify(),
        ),
      )
    },
  )

  s1 = instrumented_tool(
    s1,
    "call_log",
    "查询最近的调用日志（call_log 表）。参数：limit(可选，默认50)。返回最近工具调用记录（seq/ts/tool/caller/ns/params/result/ok/runtime_ms，新的在前）。用于复盘'是哪次调用+入参+结果产生了 bug'。",
    schema({ "limit": int_prop("返回条数(可选默认50)") }, []),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError] {
      let limit = get_int(args, "limit", default=50)
      Ok(
        @mcp.ToolResult::text(
          Json::object({
            "count": Json::number(
              engine.store_recent_call_logs(limit~).length().to_double(),
            ),
            "calls": Json::array(engine.store_recent_call_logs(limit~)),
          }).stringify(),
        ),
      )
    },
  )
  s1 = instrumented_tool(
    s1,
    "report_bug",
    "上报一个运行时 bug：追加到 {project_dir}/memory/bugs.md（OPEN 状态账本）。参数：project_dir(必填)、summary(必填)、detail(可选)、severity(可选 open/critical/high/medium/low)、ref_call_id(可选，指向 call_log 的 seq)、reported_by(可选)、publish_task(可选默认false)：为 true 时同时把'修复 bug: <summary>'发布为 bugs 命名空间下的独立根任务，供自驱/定时流水线认领修复，形成上报→修复闭环。",
    schema(
      {
        "project_dir": string_prop("项目目录（必填）"),
        "summary": string_prop("bug 摘要（必填）"),
        "detail": string_prop("详细描述(可选)"),
        "severity": string_prop(
          "严重度(可选)：open/critical/high/medium/low",
        ),
        "ref_call_id": string_prop("关联 call_log seq(可选)"),
        "reported_by": string_prop("上报者(可选)"),
        "publish_task": bool_prop(
          "是否发布修复根任务(可选默认false)",
        ),
        "now": string_prop("时间戳(可选，默认内置)"),
      },
      ["project_dir", "summary"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError] {
      let project_dir = get_str(args, "project_dir")
      let summary = get_str(args, "summary")
      let detail = get_str(args, "detail")
      let severity = get_str(args, "severity")
      let ref_call_id = get_str(args, "ref_call_id")
      let reported_by = get_str(args, "reported_by")
      let publish_task = get_bool(args, "publish_task", default=false)
      let ts = get_str(args, "now", default=now_default())
      match
        report_bug(
          project_dir,
          summary,
          detail~,
          severity~,
          ref_call_id~,
          reported_by~,
          publish_task~,
          engine,
          now=ts,
        ) {
        Ok(j) => Ok(@mcp.ToolResult::text(j.stringify()))
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "bug_list",
    "列出 {project_dir}/memory/bugs.md 里的 bug 条目（{id,ts,severity,status,summary}）。用于自驱流水线扫描待修复 bug 并认领。参数：project_dir(必填)。",
    schema({ "project_dir": string_prop("项目目录（必填）") }, [
      "project_dir",
    ]),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError] {
      let project_dir = get_str(args, "project_dir")
      match bug_list(project_dir) {
        Ok(j) => Ok(@mcp.ToolResult::text(j.stringify()))
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )

  // 默认 stdio 传输（MCP 标准模式）。
  run_stdio_target(s1)
}
