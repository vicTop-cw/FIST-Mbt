/// FIST-Mbt MCP server: 暴露 129 tools + 3 resources + 2 prompts。
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
/// BUG-119：跨进程心跳回读。旧实现是模块级 `let _init_hb : Unit = init_heartbeats()`——
/// MoonBit 不保留未被引用的非 `pub` 顶层绑定，那行"启动时回灌"根本没进产物
/// （实测产物里 `init__heartbeats` 出现 0 次），新进程的内存心跳表因此恒为空。
/// 现在不在启动时预热：**持久化心跳表是唯一真相**，`heal` 走 store 版判活，
/// `heartbeat` 需要上一次心跳时按需回读单行。内存表只当本进程的写缓冲。
fn hb_last_seen_of(task_id : String) -> String {
  let mem = heartbeats.last_seen_of(task_id)
  if mem != "" {
    mem
  } else {
    engine.store_read_heartbeat_last_seen(task_id)
  }
}

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
/// 执行者能力注册表（进程内，Marketplace/Dynamic 范式雏形，R30）。
/// 供 `executor_register`（登记能力标签）与 `executor_route`（按能力+负载路由）。
let exec_reg : @executor.ExecutorRegistry = @executor.ExecutorRegistry::new()

///|
/// Phase 6 组合环进程内注册表。loop_create 注册、loop_tick 推进、loop_status 查询。
/// 模仿 AuditLog/ExecutorRegistry 的内部可变性模式。
let loop_reg : @ops.LoopRegistry = @ops.LoopRegistry::new()

///|
/// 统计各执行者（assignee）当前的活跃负载：其名下"非终态"（未完成/未归档）任务数。
/// 供 executor_route 做负载均衡。
fn executor_loads(e : @engine.FistEngine) -> Map[String, Int] {
  let m : Map[String, Int] = Map([])
  for t in e.list_all() {
    let st = t.get_status()
    let active = not(st.is_pending()) &&
      not(st.is_completed()) &&
      not(st.is_archived())
    if active {
      match t.get_assignee() {
        Some(a) => {
          let cur = match m.get(a) {
            Some(n) => n
            None => 0
          }
          ignore(m.set(a, cur + 1))
        }
        None => ()
      }
    }
  }
  m
}

///|
/// 把 Json 数组 [{Int}] 转成 Array[Int]（用于 intervals 解析）。
fn intlist(j : Array[Json]) -> Array[Int] {
  let out : Array[Int] = []
  for x in j {
    match x {
      Json::Number(n, ..) => out.push(n.to_int())
      _ => ()
    }
  }
  out
}

///|
/// 把 Json 数组 [{String}] 转成 Array[String]（用于 abilities 解析）。
fn strlist(j : Array[Json]) -> Array[String] {
  let out : Array[String] = []
  for x in j {
    match x {
      Json::String(s) => out.push(s)
      _ => ()
    }
  }
  out
}

///|
/// 把能力标签数组序列化成 JSON 数组串（用于落库）。
fn ab_to_json(ab : Array[String]) -> String {
  Json::array(ab.map(fn(s) { Json::string(s) })).stringify()
}

///|
/// 从 JSON 数组串反解析能力标签（落库读出）。
fn ab_from_jsonstr(s : String) -> Array[String] {
  let j = @json.parse(s) catch { _ => Json::null() }
  match j {
    Json::Array(a) => strlist(a)
    _ => []
  }
}

///|
/// 把 store 里已持久化的执行者能力注册"回灌"进进程内注册表（幂等，跨进程可复现）。
fn sync_db_executors() -> Unit {
  for (name, ab, _ca) in engine.executor_list() {
    if not(exec_reg.has(name)) {
      ignore(exec_reg.add_ability(name, ab_from_jsonstr(ab)))
    }
  }
}

///|
/// 从参数解析可选出价表 {执行者: 0..1 置信度}（可选参数，缺省返回空表=按覆盖率自动出价）。
fn json_bid_map(args : Json, key : String) -> Map[String, Double] {
  let m : Map[String, Double] = Map([])
  match args.value(key) {
    Some(Json::Object(o)) =>
      for (k, v) in o {
        match v {
          Json::Number(n, ..) => ignore(m.set(k, n))
          _ => ()
        }
      }
    _ => ()
  }
  m
}

///|
/// 读 Json 对象的字符串字段（复用式，等价 executor 包内私有 num/str）。
fn jstr(j : Json, key : String) -> String {
  match j.value(key) {
    Some(Json::String(s)) => s
    _ => ""
  }
}

///|
/// 读 Json 对象的数值字段。
fn jnum(j : Json, key : String) -> Double {
  match j.value(key) {
    Some(Json::Number(n, ..)) => n
    _ => 0.0
  }
}

///|
/// 任务→所需能力自动抽取（R33）：扫任务描述里出现的「已注册执行者能力标签」，
/// 取最长命中的那个作 need（最具体）。没命中返回空串（调用方回退 agent / 空 want）。
fn auto_need(desc : String) -> String {
  let mut best = ""
  for name in exec_reg.list() {
    for a in exec_reg.abilities_of(name) {
      if a != "" && desc.contains(a) && a.length() > best.length() {
        best = a
      }
    }
  }
  best
}

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
/// BUG-3（Round 2 收口）：audit_log 的返回体构造（抽成纯函数，好让契约可被回归测试钉住）。
/// 病灶：@ops.AuditLog 是**进程内**实现、不落库（见 src/ops/audit.mbt 头注），而每次 MCP
/// 调用是新起进程 → 裸数组 [] 与「从来没有发生过任何治理动作」不可区分，这是审计面最坏的
/// 失败（假阴性证据）。本轮只做「让空结果可区分且自我说明」，不改落库（那是新架构，另单）：
/// 恒返回 { scope:"process", entries:[...], note:"仅本进程…；跨进程请用 call_log" }。
fn audit_log_payload(entries : Array[@ops.AuditEntry]) -> Json {
  let arr = entries.map(fn(e) {
    let m : Map[String, Json] = Map([])
    m.set("ts", Json::string(e.ts))
    m.set("action", Json::string(e.action))
    m.set("actor", Json::string(e.actor))
    m.set("task_id", Json::string(e.task_id))
    m.set("detail", Json::string(e.detail))
    Json::object(m)
  })
  Json::object({
    "scope": Json::string("process"),
    "entries": Json::array(arr),
    "count": Json::number(arr.length().to_double()),
    "note": Json::string(
      "仅本进程生命周期内的审计记录（AuditLog 不落库）；空 entries **不等于**没有治理动作——跨进程请用 call_log（服务端盖章、持久）",
    ),
  })
}

///|
/// BUG-4（Round 2）：run_check 拒绝一次宿主命令尝试时的统一出口。
/// 拒绝必须**可审**：① 立刻写进程内 audit_log（audit_log 当场能查到 scope=process 的这条）；
/// ② 错误文案原样返回，由 _instrument 落进 call_log（跨进程持久痕迹，含完整入参）。
/// 旧版 workdir 判定（bugreport_resolve.mbt 的 run_check_workdir_ok）已被
/// run_check_guard.mbt 的子树判定 + cmd 白名单取代，那里只留一个兼容别名。
fn run_check_deny(
  task_id : String,
  actor : String,
  reason : String,
) -> Result[@mcp.ToolResult, @mcp_types.MCPError] {
  ignore(
    audit.record(
      action="run_check_denied",
      actor~,
      task_id~,
      detail=reason,
      now=now_default(),
    ),
  )
  Err(
    @mcp_types.ToolError(
      reason +
      "。本次尝试已落审计：audit_log(本进程) 与 call_log(跨进程, tool=run_check, ok=false) 均可查",
    ),
  )
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
/// config_json 一类的"文本型 JSON 参数"取值（BUG-63）：
/// schema 声明是字符串，但真实 MCP 客户端经常直接给 JSON 对象/数组。
/// `get_str` 对非字符串一律回退默认值 ⇒ 自定义配置被静默当成"没传"，
/// 用默认池跑完还回 ok=true、warnings 里一条配置告警都没有（BUG-55 的失效模式
/// 在类型边界复活）。这里两种形态都收：字符串照旧，对象/数组先取其文本，
/// 再走**同一条** JSON 校验 —— 合法就用、非法就显式报错，绝不静默回落。
fn get_json_text(args : Json, key : String) -> String {
  match args {
    Json::Object(m) =>
      match m.get(key) {
        None => ""
        Some(Json::Null) => ""
        Some(Json::String(s)) => s
        Some(v) => v.stringify()
      }
    _ => ""
  }
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
/// BUG-18（Round 2 修复）：Laya sidecar 的**延迟预算对齐**。
///
/// 病灶（活证据 temp/r2_laya_before.json + .err）：本机 `laya_decide` 一次真实调用
/// 阻塞 **278.77s**（rc=0），因为 ① 每次调用都无条件重跑 `--probe`（旧预算 15000ms），
/// ② sidecar 决策调用给了 300000ms（5 分钟）预算。而 `.mcp.json` 里 server 的
/// `timeout_ms` 只有 **30000**：客户端在 30s 就先超时，看到的是「无响应」，
/// 正好是 BUG-14 承诺「绝不阻断现网」的反面。
///
/// 现在的不变式（三者关系必须一起看，改任何一个都要重算）：
///   laya_probe_budget_ms + laya_sidecar_budget_ms (=25s) < 客户端 laya_client_budget_ms(30s)
/// 即**服务端一定先于客户端出结论**，最坏情况也回一个降级 decision 而不是让调用方干等；
/// 留 5s 余量给 node/python 进程 spawn 与 MCP 往返。要真用满 Laya 侧车（本机实测 ~270s），
/// 必须**同时**上调 `.mcp.json` 的 timeout_ms 和下面两个常量，否则客户端仍先断。
/// `.mcp.json` 的 timeout_ms 是真源，这里只是镜像常量（没有构建期单一真源＝BUG-16 遗留）。
let laya_client_budget_ms : Int = 30000

///|
let laya_probe_budget_ms : Int = 5000

///|
let laya_sidecar_budget_ms : Int = 20000

///|
/// probe 结果的进程内缓存（BUG-18）：`--probe` 会真的 `import laya`，是每次调用的固定
/// 成本；同一台机器上可用性不会毫秒级变化，所以缓存 TTL 内的答案。
/// 键固定 "probe"，值 {available, at_ms}。**运维语义**：装上/卸掉 Laya 后最迟
/// laya_probe_ttl_ms 生效，要立刻生效就重启 server（本缓存只在进程内，不落库）。
let laya_probe_cache : Map[String, Json] = Map([])

///|
let laya_probe_ttl_ms : Int64 = 300000L

///|
/// TTL 判定（纯函数，便于回归测试）：缓存条目是否仍然新鲜。
/// at_ms<=0 视为"从没探过"（不新鲜），命中窗口内才算新鲜。
fn laya_probe_cache_fresh(now_ms : Int64, at_ms : Int64) -> Bool {
  at_ms > 0L && now_ms - at_ms < laya_probe_ttl_ms
}

///|
/// 带 TTL 缓存的 Laya 探测：TTL 内复用上次答案，否则真探一次并回灌缓存。
/// 语义与 laya_probe_available 一致（Err=探测失败=不可用），只是不再每次付费。
async fn laya_probe_cached(
  cmd : String,
  args : Array[String],
  workdir : String,
  timeout_ms : Int,
) -> Result[Bool, String] {
  let now_ms = @env.now().to_int64()
  let cached : Json = match laya_probe_cache.get("probe") {
    Some(j) => j
    None => Json::null()
  }
  let at_ms = get_int(cached, "at_ms", default=-1).to_int64()
  if laya_probe_cache_fresh(now_ms, at_ms) {
    // 命中：不再 spawn（at_ms 供调用方自证用的是哪一次探测）
    return Ok(get_bool(cached, "available", default=false))
  }
  let r = laya_probe_available(cmd, args, workdir, timeout_ms)
  let avail = match r {
    Ok(a) => a
    Err(_) => false
  }
  ignore(
    laya_probe_cache.set(
      "probe",
      Json::object({
        "available": Json::boolean(avail),
        "at_ms": Json::number(now_ms.to_double()),
      }),
    ),
  )
  r
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
/// 契约守卫（BUG-14 修复）：`laya_decide` 的工具描述承诺顶层恒含 `decision`，但
///   1) sidecar（scripts/laya_decide.py）只输出 answers/auto_decide/escalate，从不产出 decision；
///   2) src/server/laya_js.mbt 在退出码非 0 时把 available 覆写为 false 后**仍返回 Ok(...)**，
///      于是 handler 的 `not(avail)` 回退分支（唯一调 route_decision 的分支）不会触发，
///      `Ok(res) => res.stringify()` 原样透传 → 调用方按文档取 decision.feature_route 拿到 undefined。
/// 这里把 decision 补齐为**恒在**：res 自带 decision 就原样保留（前向兼容 sidecar 未来产出），
/// 否则合并 route_decision(context, split_n_hint)（本工具 decision 结构的唯一真源）。
/// 不改动 available 的原判定、不改工具签名、不引入依赖。
fn laya_ensure_decision(
  res : Json,
  context : String,
  split_n_hint : Int,
) -> Json {
  let obj = match res {
    Object(m) => m
    _ => Map([])
  }
  match obj.get("decision") {
    Some(_) => res
    None => {
      obj.set("decision", route_decision(context, split_n_hint))
      obj.set(
        "decision_note",
        Json::string(
          "decision 由内建规则式分支 laya_route 补齐（Laya sidecar 只输出 answers，不产出 feature_route/split_n）；本工具保证 decision 恒在，调用方无需按 available 自行分支",
        ),
      )
      Json::object(obj)
    }
  }
}

///|
/// 项目自述版本（BUG-16 修复：对外版本单一真源）。
/// 此前 status_summary / project_health / fist://overview 三处各写一遍上一版版本号字面量，
/// 升版时漏改 → 对外自述落后一整版（违反规范 r1「文档即实现」/ r2「一源四态·单真源优先」；
/// 漂移过程与活证据见 memory/bugs.md 的 BUG-16 条目）。现收敛到本常量；回归测试
/// （src/server/fist-mbt_wbtest.mbt）逐字比对它与 moon.mod 里 version 的声明值，并断言本文件
/// 不再残留任何硬编码版本字面量——所以这段说明本身也不写旧版本号，否则会被回归锁误伤。
let project_version : String = "0.3.6"

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
        "MCP 层工具注册面（逐个清单看同资源的 `tool_groups` 与各宿主 SKILL.md，注册表真源在本文件）+ 3 resources + 2 prompts + call_log 注入",
      ),
      "decompose": Json::string("递归拆解规格"),
      "executor": Json::string("执行器"),
    }),
    "tool_groups": Json::object({
      "生命周期": Json::string(
        "publish/publish_parallel/plan/claim/execute/submit/verify/reject/retry/pause/resume/reopen_task/archive/delete",
      ),
      "查询": Json::string("list/get"),
      "运维": Json::string(
        "task_plan_deep/conflicts_check/heartbeat/heal/watchdog_tick/task_cleanup/phi_accrual/saga_register/saga_rollback/saga_repair/circuit_fail/succeed/status/tx_contract",
      ),
      "运维·日志/缺陷/成本/调度": Json::string(
        "call_log/bug_list/report_bug/eval_feedback/run_check/schedule/pipeline_tick/cost_stats/cost_budget_check/cost_budget_split/progress_gate/laya_decide/loop_create/loop_tick/loop_status",
      ),
      "看板/脉冲/预订/推荐+DAG": Json::string(
        "dag_critical_path/parallelism/ascii/check/ready/sort/depend/publish/slack/schedule/cost_route/mc/plan_revise/goal_drift_check + board_ascii + status_summary + project_health/health_check + reserve_scope/check/release + task_triage",
      ),
      "自驱": Json::string(
        "selfdrive_init/append/get/export_tasks/review_tick/review_ready/publish_next/parse_next_tasks + selfdrive_pick_next + selfdrive_dispatch",
      ),
      "记忆与自进化": Json::string(
        "memory_consolidate/gc/link + evolve_submit/sample/snapshot/distill/lesson/critic/asset_register + task_challenge",
      ),
      "Marketplace·能力路由": Json::string(
        "executor_register/auction/route/clear + selfdrive_dispatch（能力登记/置信度拍卖/专长+负载路由/重置/自动派单，R30-R33/R87）",
      ),
      "审计权限": Json::string("audit_permission/log"),
      "多租户": Json::string("store_open/list/close"),
      "强验证": Json::string(
        "omega_spec_create/review/result_verify/status/verify/verify_fix",
      ),
      "衍生·ATGC-old": Json::string("atgc_old_compile/run/talk"),
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
    ("version", Json::string(project_version)),
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
/// caller 的优先级（纯函数，便于白盒判据——与 `SqliteStore::db_path_from_env` 同形状）：
/// 进程环境 `FIST_CALLER` > 调用方自述 `created_by` > 空串。
/// BUG-137：过去只有第二档，而 `created_by` 是**调用方自己填的**，且绝大多数工具没这个入参
/// ⇒ 根库 call_log 的 caller 实测最近 800 行全为空串。仲裁类工具（预订/冲突检测）的身份是承重件，
/// 认不出是谁，锁就只是自报家门。环境变量只由运维侧注入，调用面传参不许自我扩权。
fn caller_from_env(env_value : String?, created_by : String) -> String {
  match env_value {
    Some(c) => if c.is_empty() { created_by } else { c }
    None => created_by
  }
}

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
  // BUG-137：caller 过去只从 `args.created_by` 取——那是**调用方自报**，而绝大多数工具没有这个
  // 入参，于是根库 call_log 最近 800 行的 caller 全为空串（实测读数见账本）。
  // 身份在仲裁类工具（预订/冲突检测）里是承重件：认不出是谁，锁就只是自报家门。
  // 改成服务端盖章，优先级逐字照 `FIST_DB_PATH`/`FIST_RUN_CHECK_ALLOW` 那一族的做法：
  // 进程环境 > 调用方自述 > 空串。环境变量只由运维侧注入，调用面传参不能自我扩权。
  let caller = caller_from_env(
    @env.get_env_var("FIST_CALLER"),
    get_str(args, "created_by", default=""),
  )
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
/// schema 声明的 required 参数名（BUG-19 用；解析不到就返回空数组=不新增约束）。
fn schema_required(input_schema : Json) -> Array[String] {
  let out : Array[String] = []
  match input_schema.value("required") {
    Some(Json::Array(arr)) =>
      for j in arr {
        match j {
          Json::String(s) => if s != "" { out.push(s) }
          _ => ()
        }
      }
    _ => ()
  }
  out
}

///|
/// schema 声明的参数名（inputSchema.properties 的键）。解析不到返回空数组=不做未知键判定。
fn schema_properties(input_schema : Json) -> Array[String] {
  let out : Array[String] = []
  match input_schema.value("properties") {
    Some(Object(map)) =>
      for (k, _) in map {
        if k != "" {
          out.push(k)
        }
      }
    _ => ()
  }
  out
}

///|
/// 实测调用面出现过的缩写错名 → 正名（BUG-23 判定口径 ①）。
/// 为什么必须有这张表：**缩写不是子串**——"ns" 在 "namespace" 里并不连续，
/// 只用子串规则抓不到它；本轮第一版就栽在这个前提上（回归锁打红才发现）。
/// 表里的正名只有在「该工具确实声明了它」时才生效（见 misnamed_args），
/// 所以多列几个候选不会误伤别的工具。
fn known_arg_aliases(k : String) -> String {
  if k == "ns" {
    "namespace"
  } else if k == "task" {
    "task_id"
  } else if k == "desc" {
    "description"
  } else if k == "root" {
    "root_task_id"
  } else if k == "proj" || k == "project" {
    "project_dir"
  } else {
    ""
  }
}

///|
/// 传了「某已声明参数的错名」的那些键（BUG-23）。判定口径两条，任一命中即算错名：
/// ① 缩写表 known_arg_aliases（`ns`↔`namespace`）且该正名确实被这个工具声明；
/// ② 互为子串且长度≥2（`desc`↔`description`、`task`↔`task_id`、`dir`↔`project_dir`），
///    长度下限挡住单字符键——"a" 会子串命中一堆声明，那是噪声不是同根。
///
/// 静默忽略这类键等于把「任务落到哪个 ns」从写侧挪到下游读侧去查：实测本仓的 CLI
/// `publish --ns r1` 就这样整颗落进 default，随后按 --ns 读回一律 insufficient。
///
/// 对**完全对不上任何声明**的键（历史调用里的 now）保持忽略——
/// temp/phaseC/audit_unknown_args.py 对 5890 行 call_log 的实测是 4310 行带 schema 外键，
/// 一律拒绝会当场打断 73% 的既有调用面。`now` 那一类是文案在广告没人读的参数，归 BUG-80。
fn misnamed_args(args : Json, props : Array[String]) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  if props.is_empty() {
    return out
  }
  match args {
    Object(map) =>
      for (k, _) in map {
        if not(props.any(fn(p) { p == k })) {
          let mut suggest = ""
          // ① 缩写表：命中的正名必须真的被这个工具声明
          let alias = known_arg_aliases(k)
          if alias != "" && props.any(fn(p) { p == alias }) {
            suggest = alias
          }
          // ② 同根子串：取最短的那个已声明键作建议（短的更可能是同一参数）
          if suggest.is_empty() && k.length() >= 2 {
            for p in props {
              if p.contains(k) || k.contains(p) {
                if suggest.is_empty() || p.length() < suggest.length() {
                  suggest = p
                }
              }
            }
          }
          if not(suggest.is_empty()) {
            out.push((k, suggest))
          }
        }
      }
    _ => ()
  }
  out
}

///|
/// 缺失的必填参数名。口径与 handler 一致：不给 / Null / 空串都算缺——
/// `get_str(args, k)` 对这三种形态一律返回 ""，下游会把它当成「不存在的任务」或静默用默认值。
fn missing_required(args : Json, required : Array[String]) -> Array[String] {
  let out : Array[String] = []
  for name in required {
    let blank = match args.value(name) {
      None => true
      Some(Json::Null) => true
      Some(Json::String(s)) => s.trim() == ""
      _ => false
    }
    if blank {
      out.push(name)
    }
  }
  out
}

///|
/// 逗号连接（不依赖跨版本不稳的 join 语义）。
fn rq_join(items : Array[String]) -> String {
  let mut out = ""
  for i = 0; i < items.length(); i = i + 1 {
    if i > 0 {
      out = out + ", "
    }
    out = out + items[i]
  }
  out
}

///|
/// 包装一个工具 handler：度量耗时、捕获入参/结果、best-effort 记日志，原样返回结果。
/// Ok 路径结果文本在外部不可读（ToolResult 字段私有），故以 "ok" 占位；
/// Err 路径记录真实错误信息（MCPError::message()）。
fn _instrument(
  tool : String,
  input_schema : Json,
  handler : async (Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError],
) -> async (Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError] {
  // BUG-19：`schema(props, required)` 过去**只声明不校验**——缺必填参数会落到 handler 的
  // `get_str(args, "x")` 拿到 ""，再被下游当成「任务不存在」或直接返回假成功。契约在这里补齐：
  // 缺 required 一律拒，并写清缺哪几个（调用方看 tools/list 的 inputSchema 即可自证）。
  let required = schema_required(input_schema)
  let props = schema_properties(input_schema)
  async fn(args : Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError] {
    let t0 = @env.now().to_int64()
    let params_json = args.stringify()
    let miss = missing_required(args, required)
    if miss.length() > 0 {
      let msg = tool +
        ": 缺必填参数 " +
        rq_join(miss) +
        "（schema.required 已声明，BUG-19 硬门）。全部可用参数见 tools/list 的 inputSchema.properties"
      let e = @mcp_types.ToolError(msg)
      // 被拒的调用同样记账：否则"入口被硬门挡住"在跨进程审计里等于没发生
      _log_call(engine, tool, args, params_json, e.message(), false, 0)
      return Err(e)
    }
    // BUG-23：错名参数（与已声明参数互为前缀）过去被静默忽略——publish --ns 就这样整颗
    // 落进 default ns，而返回体只有 task_id，调用面看不出任何异常。当场点名两个键名。
    let bad = misnamed_args(args, props)
    if bad.length() > 0 {
      let mut hint = ""
      for (k, p) in bad {
        if hint != "" {
          hint = hint + "；"
        }
        hint = hint + "「" + k + "」应为「" + p + "」"
      }
      let msg = tool +
        ": 参数名不被接受 " +
        hint +
        "（该工具声明的参数：" +
        rq_join(props) +
        "）。BUG-23：这类键过去被静默忽略，任务会落进默认命名空间而返回体看不出来。"
      let e = @mcp_types.ToolError(msg)
      _log_call(engine, tool, args, params_json, e.message(), false, 0)
      return Err(e)
    }
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
  s.tool(
    name,
    description,
    input_schema,
    _instrument(name, input_schema, handler),
  )
}

///|
/// —— MCP server 构建与运行 ——
pub async fn run_server() -> Unit {
  // BUG-21：握手版本曾是硬编码 "0.1.0"，与 moon.mod / project_version / 文档三处口径分裂——
  // 客户端 tools/list 之外的唯一自报身份就是它，必须与单一真源一致。
  let mut s1 = @mcp.MCPServer::MCPServer("fist-mbt", project_version)

  // ---- tools ----
  s1 = instrumented_tool(
    s1,
    "publish",
    "发布根任务（仅限人类指挥官）。参数：project_dir 项目目录、description 任务描述、namespace 命名空间(默认 default)、created_by 创建者身份(默认 human_steward)。返回 {task_id, namespace, message}，其中 namespace 是任务**实际落在**的 ns（BUG-23：过去只回 task_id，把键名写成 ns 会静默落进 default 而无从发现）。参数名逐字对 inputSchema：与本工具已声明参数同根（互为子串）的错名（ns/desc/project 这类）直接拒绝，不做静默忽略。",
    schema(
      {
        "project_dir": string_prop("项目目录（必填）"),
        "description": string_prop("任务描述（必填）"),
        "namespace": string_prop("命名空间(默认 default)"),
        "created_by": string_prop("创建者身份(默认 human_steward)"),
      },
      ["project_dir", "description"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let project_dir = get_str(args, "project_dir")
      let description = get_str(args, "description")
      let ns = get_str(args, "namespace", default="default")
      let created_by = get_str(args, "created_by", default="human_steward")
      let ts = now_default()
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
                // BUG-23：回显任务**实际落在**哪个 ns，落错当场看得见
                "namespace": Json::string(ns),
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
    "并行追加独立根任务（不要求命名空间为空、不续轮不归档）：在已有任务的命名空间追加新的独立根任务，供自驱/定时命名空间连续发布多根使用。参数：project_dir、description(必填)、namespace(必填，非 default)、created_by(默认 selfdrive)。",
    schema(
      {
        "project_dir": string_prop("项目目录（必填）"),
        "description": string_prop("任务描述（必填）"),
        "namespace": string_prop("命名空间（必填，不得为 default）"),
        "created_by": string_prop("创建者身份(默认 selfdrive)"),
      },
      ["project_dir", "description", "namespace"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let project_dir = get_str(args, "project_dir")
      let description = get_str(args, "description")
      let ns = get_str(args, "namespace")
      let created_by = get_str(args, "created_by", default="selfdrive")
      let ts = now_default()
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
                // BUG-23：同 publish —— 回显实际落点 ns
                "namespace": Json::string(ns),
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
      },
      ["task_id"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let task_id = get_str(args, "task_id")
      let split_n = get_int(args, "split_n", default=3)
      let by = get_str(args, "by", default="human_steward")
      let ts = now_default()
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
      },
      ["task_id", "assignee"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let task_id = get_str(args, "task_id")
      let assignee = get_str(args, "assignee")
      let ts = now_default()
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
    "记录执行交付物（向后兼容）。合法前态：拆分中/已领取/**执行中**→执行中（BUG-2 收口：执行中重复 execute = 追加/覆盖交付物，因此 reject→retry（→执行中）后可以直接原地更新交付物，无需 pause→resume 绕行；被拒时错误文案会给出当前状态的可用出路）。必填：task_id、deliverable；可选：executor(默认manual)、model、tokens_in、tokens_out、cost、duration_ms、rate_limited、failure_reason。",
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
      },
      ["task_id", "deliverable"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let task_id = get_str(args, "task_id")
      let deliverable = get_str(args, "deliverable")
      let ts = now_default()
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
    schema({ "task_id": string_prop("任务 id（必填）") }, ["task_id"]),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let task_id = get_str(args, "task_id")
      let ts = now_default()
      to_result(engine.submit(task_id~, now=ts))
    },
  )
  s1 = instrumented_tool(
    s1,
    "run_check",
    "外部判据检查（**宿主命令执行能力**：服务端真实 spawn 进程，防自写自测恒绿；请勿暴露给不可信客户端）。自 Round 2 起执行面**默认收紧**（BUG-4 收口，判定在 src/server/run_check_guard.mbt）：① cmd 必须在白名单内——默认只放项目脚本解释器 moon/node/python/python3/py/bash/sh/zsh/powershell/pwsh（集合来源=call_log 实测调用面）或**项目内的**相对判据脚本（如 `scripts/check.sh`）；② workdir 必须在任务 project_dir 子树内（默认即 project_dir 本身；**相对 workdir 按任务 project_dir 相对解析，`.` 就是该任务的项目目录本身**，与 project_dir 是绝对还是相对无关 —— BUG-51 统一口径，实际 spawn 的 cwd 用归一后的绝对形态）。注意这条口径与 `report_bug`/`bug_list` 的 `project_dir` **相反**：那个参数是 bug 账的落盘根，只接受相对 store 根的路径（拒绝绝对路径/盘符/`..`）。越界（`..` 上跳、跨盘、脱离子树、绝对 workdir 配相对 project_dir）直接拒绝。要扩展白名单只有两条路：把判据脚本写进项目目录按相对路径调用，或由**运维侧**设环境变量 FIST_RUN_CHECK_ALLOW=git,cargo（调用方传参不能给自己扩权）。被拒的尝试一律落审计（audit_log 本进程 + call_log 跨进程）。参数：task_id 任务id、cmd 可执行命令、args 参数数组(可选)、workdir 工作目录(默认任务 project_dir；相对路径按任务 project_dir 解析，绝对路径须在项目子树内)、timeout_ms 超时毫秒(默认120000)（注：时间戳由服务端盖章，不接受调用方注入 now）。真实 spawn 子进程运行 cmd，退出码 0 记为 passed、否则 failed，结果 JSON（含 stdout/stderr）落库 specs 表（spec_type=check）；[gate:required] 任务的 verify 依赖本记录且校验新鲜度。返回 {ok, check_id, task_id, round, status, stdout_tail, stderr_tail, output_truncated, note}：**顶层的 ok 只表示「判据已跑完并落库」**（spawn 成功即 true，与判据通过与否无关），**判据通过与否只看 status**（passed/failed，服务端由子进程退出码推导，调用方声称的 passed 无效）。别拿 ok 当结论：BUG-83 实测有驱动以顶层 ok 汇总出『判据 11/11 通过』，而同一份回执里 status=failed 的那条就躺在旁边。stdout/stderr 各带**末 2000 字符**（判据的关键信息在结尾；BUG-75 前只回退出码，failed 时举不出红在哪、只能本地重跑同一条命令，等于退回本工具要防的自述路径），完整输出仍存 specs.content 供库内复核。",
    schema(
      {
        "task_id": string_prop("任务 id（必填）"),
        "cmd": string_prop(
          "要执行的外部命令（必填，受 BUG-4 白名单约束）：默认允许 moon/node/python/python3/py/bash/sh/zsh/powershell/pwsh，或项目内相对判据脚本（scripts/xxx.sh）；扩展靠运维侧环境变量 FIST_RUN_CHECK_ALLOW",
        ),
        "args": array_prop("命令参数数组（可选）"),
        "workdir": string_prop(
          "工作目录（可选，默认任务 project_dir；**相对路径按任务 project_dir 相对解析，`.` 即该项目目录本身**，绝对路径必须落在该子树内；拒绝 .. 上跳/跨盘/脱离子树/绝对 workdir 配相对 project_dir。BUG-51 统一口径）",
        ),
        "timeout_ms": int_prop("超时毫秒（可选，默认 120000）"),
      },
      ["task_id", "cmd"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let task_id = get_str(args, "task_id")
      let cmd = get_str(args, "cmd")
      let now = now_default()
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
      // BUG-4（Round 2）：先过 cmd 白名单（allow_extra 恒为空数组——只有运维侧环境变量
      // FIST_RUN_CHECK_ALLOW 能扩权，调用方无处自授），再定位任务。两条分支
      // （任务存在/不存在）共用同一判定，防「任务不存在」变成绕过白名单的后门。
      match run_check_cmd_denied(cmd, []) {
        Some(reason) => return run_check_deny(task_id, "unknown", reason)
        None => ()
      }
      // 定位任务（取项目目录作默认 workdir；任务不存在也允许执行，仅不落库）
      match engine.get_task(task_id) {
        Some(t) => {
          let workdir = get_str(args, "workdir", default=t.project_dir)
          // BUG-4 fix（Round 2）：workdir 必须落在任务 project_dir 子树内。
          // 绝对 project_dir 本身**是**合法值（实测调用面 38/51 就是这种形态）。
          match run_check_workdir_denied(workdir, t.project_dir) {
            Some(reason) =>
              return run_check_deny(
                task_id,
                match t.get_assignee() {
                  Some(a) if a != "" => a
                  _ => "unassigned"
                },
                reason,
              )
            None => ()
          }
          let r = run_check_external(
            cmd,
            args_arr,
            run_check_effective_workdir(workdir, t.project_dir),
            timeout_ms,
          )
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
          // 任务不存在：仍执行命令并返回结果，但不落库（无任务可挂）。
          // BUG-4（Round 2）：这条分支同样过白名单（上面已判），workdir 则**钉死在 server
          // cwd 子树**（等价于 project_dir="."），越界照旧拒绝并落审计——不因为
          // 「没有任务」就放开执行面。
          let workdir = get_str(args, "workdir", default=".")
          match run_check_workdir_denied(workdir, ".") {
            Some(reason) => {
              let hint = "（任务 \{task_id} 不存在，workdir 只允许 server cwd 子树内的相对路径，如 `.`）"
              return run_check_deny(task_id, "unknown", reason + hint)
            }
            None => ()
          }
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
    "验收通过（待验收 -> 已完成，父任务自动上卷）。[gate:required] 任务须先有新鲜通过的 run_check 记录；可选 docs_check 开启「文档即实现」门禁（校验 README/CHANGELOG/reports 存在性与交付物回传五段式，不达标打回）。参数：task_id、verifier、docs_check。",
    schema(
      {
        "task_id": string_prop("任务 id（必填）"),
        "verifier": string_prop("验收人（必填）"),
        "docs_check": bool_prop(
          "是否开启文档一致性门禁(默认 false，不传即现状)：开启后校验项目结构 README.md/CHANGELOG.md/reports 与交付物回传五段式，缺项打回",
        ),
      },
      ["task_id", "verifier"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let task_id = get_str(args, "task_id")
      let verifier = get_str(args, "verifier")
      let ts = now_default()
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
      },
      ["task_id"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let task_id = get_str(args, "task_id")
      let reason = get_str(args, "reason", default="")
      let by = get_str(args, "by", default="human_steward")
      let ts = now_default()
      to_result(engine.reject_task(task_id~, reason~, by~, now=ts))
    },
  )
  s1 = instrumented_tool(
    s1,
    "retry",
    "打回后重试（已打回 -> 执行中）。参数：task_id。",
    schema({ "task_id": string_prop("任务 id（必填）") }, ["task_id"]),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let task_id = get_str(args, "task_id")
      let ts = now_default()
      to_result(engine.retry_task(task_id~, now=ts))
    },
  )
  s1 = instrumented_tool(
    s1,
    "reopen_task",
    "重开/重派任务：任意非归档任务回滚为已领取（M4 heal/运维重派用）。参数：task_id。",
    schema({ "task_id": string_prop("任务 id（必填）") }, ["task_id"]),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let task_id = get_str(args, "task_id")
      let ts = now_default()
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
    schema({ "task_id": string_prop("任务 id（必填）") }, ["task_id"]),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let task_id = get_str(args, "task_id")
      let ts = now_default()
      to_result(engine.pause_task(task_id~, now=ts))
    },
  )
  s1 = instrumented_tool(
    s1,
    "resume",
    "恢复任务（已暂停 -> 已领取）。参数：task_id。",
    schema({ "task_id": string_prop("任务 id（必填）") }, ["task_id"]),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let task_id = get_str(args, "task_id")
      let ts = now_default()
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
      },
      ["task_id"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let task_id = get_str(args, "task_id")
      let by = get_str(args, "by", default="human_steward")
      let ts = now_default()
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
    "AO 式递归拆解：对指定任务拆出整棵多层子任务树并写库。参数：task_id 任务id、split_n 每层默认拆分数(默认3)、by 拆解拳长、spec 可选 omega spec JSON(laws 作切割依据、fingerprint 作验收基准)、omega_strong_verify 是否开启 Omega 强验证(默认 false，不传即现状)、gradient 是否开启难度梯度标注(默认 false，开启后每个拆出的子任务描述附带『难度梯度 序号/总数:难易档』+『更简单变体』提示，使递归拆解呈由易到难、可验证最小片的梯度)（注：时间戳一律由服务端盖章，不接受调用方注入 now）。开启强验证后每层子任务多出『语料创建者建语料 -> 验证者审语料 -> 执行者执行 -> 验证者复验成果』环节。返回 {root, by, split_n, tree, exec_order}：**子任务在 tree.children 里逐层递归**，tree = {task_id, created, children:[{id, depth, leaf, spec_hash, depends_on, children[…]}]}，exec_order = {task_id, count, order:[…]}。两个坑点名（BUG-74，实测撞过）：① 顶层没有 subtasks/tasks/created，按这些键取必得空，会误判『拆解失败』而重复发布（造孤儿树）；② tree.created 是**整数计数**不是数组，拿它当列表遍历会直接崩。取叶子请递归 tree.children，或事后调 list(namespace=) 复核真实数量。",
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
        "gradient_dag": bool_prop(
          "是否把 LADDER『更简单变体→先易后逆推』落成真实 DAG 前置依赖(默认 false，须 gradient=true 才生效)：开启后每个非首切片会对前一兄弟切片建 depends_on，这样后续更难切片必须等它更简单的前驱切片完成后才可认领——由提示文本升级为真实可领取门禁，经 dag_ready/dag_ascii/topo_sort 可见。默认关闭零回归。",
        ),
        "reinject_context": bool_prop(
          "是否把『父计划 + 剩余兄弟』回注进每条子任务描述(默认 false 零回归，ReCAP 借鉴/R63)：开启后每个拆出的子任务描述携带它归属于哪个父计划摘要 + 还剩几个兄弟，让原子片知其所以然，防上下文漂移，整棵树递归下钻均继承。",
        ),
        "boundary_probe": bool_prop(
          "是否为『spec 没写的域外行为』补一个 owner(默认 false 零回归，atgc-merge 归因报告机理 1/2)：开启后本层切片末尾追加一条『边界审视叶』(全局输入域 owner，须对空输入/极值/非法输入/资源极限逐项给用例或声明不适用)，并给其余每条叶挂『边界四问』提示，整棵树递归下钻均继承。用于治『验收锚定+弱语料』：语料只断言做了没时，执行体会理性地停在判据边界上。",
        ),
        "laya_auto": bool_prop(
          "是否开启 Laya 自动选档(默认 false)。开启后探测 Laya，可用则按 difficulty.score 自动定 split_n（递归层数交给 Laya 推断）并附决策；不可用回退 split_n 默认值。⚠ 本机若 laya 可 import 但 predict 慢/卡（无内部超时），开启会拉长每次拆解耗时，故默认关闭按需开启。显式传 decide_split_n 则忽略 Laya(躬身自决优先)",
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
      },
      ["task_id"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let task_id = get_str(args, "task_id")
      let mut split_n = get_int(args, "split_n", default=3)
      let by = get_str(args, "by", default="leader")
      let spec_raw = get_str(args, "spec")
      let ts = now_default()
      let spec : Json? = if spec_raw == "" {
        None
      } else {
        Some(@json.parse(spec_raw)) catch {
          _ => return Err(@mcp_types.ToolError("spec 不是合法 JSON"))
        }
      }
      let omega_strong = get_bool(args, "omega_strong_verify", default=false)
      let gradient = get_bool(args, "gradient", default=false)
      let gradient_dag = get_bool(args, "gradient_dag", default=false)
      let reinject_context = get_bool(args, "reinject_context", default=false)
      let boundary_probe = get_bool(args, "boundary_probe", default=false)
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
        // BUG-18：探测走 TTL 缓存、预算与 .mcp.json 的 30s 客户端超时对齐
        let avail = match
          laya_probe_cached(
            "python",
            ["scripts/laya_decide.py", "--probe"],
            ".",
            laya_probe_budget_ms,
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
                  laya_sidecar_budget_ms,
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
          gradient_dag~,
          reinject_context~,
          boundary_probe~,
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
          // 「执行计划」视图：拆解后给出一张按 DAG 拓扑序、附难度/依赖/深度的
          // 扁平执行清单，agent 拿到即可照单执行（纯读，无副作用）。
          m.set("exec_order", engine.plan_exec_order(task_id))
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
    "自进化·Challenger 进阶变体（SAGE 四专家环另一半，与 R12 梯度/R13 Critic 互补）：对一条【已完成/已归档】任务按策略发布上一档『更难变体』—新根任务带 [challenge] 标记 + from 溯源 + 重要度升一档，构成『由易到难』自推进序列，让复杂能力持续上探而非停在完成点。可选 critic（缺省关闭零回归）：开启后对生成的挑战题先做 Critic 防漂移评审（与 evolve_critic 同一单一真源，防课程漂移/同质坍缩），当前策略漂移自动降档、全部漂移则拒发。参数：task_id 源任务(必填，须已完成/已归档)、by 触发者(默认 auto)、factor 扩规模倍数(默认2，仅 scale 策略生效)、strat 进阶策略(默认 scale，可选 generalize/unhint/constrain/scale)、critic 是否开启防漂移门禁(默认 false)。返回 {new_id,source,factor,strat,importance,critic,critic_status}。",
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
      },
      ["task_id"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let task_id = get_str(args, "task_id")
      let by = get_str(args, "by", default="auto")
      let factor = get_int(args, "factor", default=2)
      let strat = get_str(args, "strat", default="scale")
      let ts = now_default()
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
    "Omega 强验证·语料创建者：为已开启强验证的任务创建本轮语料，并真正持久化写入 specs 表。参数：task_id、author 语料创建者(默认 spec_author)、content 语料内容(必填)、max_rounds 打回上限(默认3，最大10)。",
    schema(
      {
        "task_id": string_prop("任务 id（必填）"),
        "author": string_prop("语料创建者身份(默认 spec_author)"),
        "content": string_prop("语料内容（必填）"),
        "max_rounds": int_prop("打回上限(默认3，最大10)"),
      },
      ["task_id", "content"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let task_id = get_str(args, "task_id")
      let author = get_str(args, "author", default="spec_author")
      let content = get_str(args, "content")
      let max_rounds = get_int(args, "max_rounds", default=3)
      let ts = now_default()
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
    "Omega 强验证·验证者审语料：审核本轮语料。verdict=approve 通过（放行执行），其它值视为打回重做；打回次数超过 max_rounds 自动升级人工裁决，禁止死循环。参数：task_id、reviewer 验证者(默认 verifier)、verdict、reason 审核意见、max_rounds。",
    schema(
      {
        "task_id": string_prop("任务 id（必填）"),
        "reviewer": string_prop("验证者身份(默认 verifier)"),
        "verdict": string_prop("approve 通过 / 其它值打回（必填）"),
        "reason": string_prop("审核意见(可选)"),
        "max_rounds": int_prop("打回上限(默认3，最大10)"),
      },
      ["task_id", "verdict"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let task_id = get_str(args, "task_id")
      let reviewer = get_str(args, "reviewer", default="verifier")
      let verdict = get_str(args, "verdict")
      let reason = get_str(args, "reason")
      let max_rounds = get_int(args, "max_rounds", default=3)
      let ts = now_default()
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
    "Omega 强验证·验证者复验成果：执行者完成后，复验成果与语料是否达标。verdict=pass 达标（可提交验收），其它值打回重做；超过 max_rounds 自动升级人工裁决。参数：task_id、reviewer、verdict、reason、max_rounds。",
    schema(
      {
        "task_id": string_prop("任务 id（必填）"),
        "reviewer": string_prop("验证者身份(默认 verifier)"),
        "verdict": string_prop("pass 达标 / 其它值打回（必填）"),
        "reason": string_prop("复验意见(可选)"),
        "max_rounds": int_prop("打回上限(默认3，最大10)"),
      },
      ["task_id", "verdict"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let task_id = get_str(args, "task_id")
      let reviewer = get_str(args, "reviewer", default="verifier")
      let verdict = get_str(args, "verdict")
      let reason = get_str(args, "reason")
      let max_rounds = get_int(args, "max_rounds", default=3)
      let ts = now_default()
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
    "tx_contract",
    "迁移契约检查（R109，Design by Contract 蒸馏：Bertrand Meyer Eiffel 1986/1997 precondition/invariant/postcondition 三件套 + PMAT ch59 work-item 契约先例）：对 (task, action) 做只读预检——precondition（前置状态合法，复用 Task 迁移语义）/ invariant（领域不变量在迁移后成立：IN-1 id 非空 / IN-2 K 值 depth≥1 / IN-3 split_n≥1 / IN-4 身份保持 id/project_dir/ns / IN-5 assignee 纪律，claim/reopen 除外）/ postcondition（目标态=文档化目标态）。任一失败 → verdict=rejected 整笔拒绝、状态 A 回稳（不落库）；全部通过 → verdict=allowed。纯计算只读不写库（决策建议，执行权在调用方）。参数：task_id、action（claim/split/execute/submit/reject/retry/pause/resume/reopen/complete/archive/mark_decomposing）、assignee(可选默认 agent，claim 用)、completed_by(可选默认 human_steward，complete 用)。返回 { ok, task_id, action, phase, verdict, reasons, target_state, state_stable, note }。",
    schema(
      {
        "task_id": string_prop("任务 id（必填）"),
        "action": string_prop(
          "迁移动作（必填）：claim/split/execute/submit/reject/retry/pause/resume/reopen/complete/archive/mark_decomposing",
        ),
        "assignee": string_prop(
          "拟认领人(可选，claim 用，默认 agent)",
        ),
        "completed_by": string_prop(
          "验收身份(可选，complete 用，默认 human_steward)",
        ),
      },
      ["task_id", "action"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let task_id = get_str(args, "task_id")
      let action = get_str(args, "action")
      let assignee = get_str(args, "assignee", default="agent")
      let completed_by = get_str(args, "completed_by", default="human_steward")
      Ok(
        @mcp.ToolResult::text(
          engine
          .transition_contract(task_id, action, assignee~, completed_by~)
          .stringify(),
        ),
      )
    },
  )
  s1 = instrumented_tool(
    s1,
    "heartbeat",
    "活动信号上报（AO ActivityState）：任务执行前/执行中周期性上报，超时静默将触发 heal 回滚。参数：task_id、signal(可选默认 active)。",
    schema(
      {
        "task_id": string_prop("任务 id（必填）"),
        "signal": string_prop(
          "信号(可选)：pre-execution/active/submit，默认 active",
        ),
      },
      ["task_id"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let task_id = get_str(args, "task_id")
      let signal = get_str(args, "signal", default="active")
      let ts = now_default()
      match engine.get_task(task_id) {
        None => Err(@mcp_types.ToolError("task not found: \{task_id}"))
        Some(_) => {
          // 计算本次心跳间隔（R90：Phi Accrual 判活数据源），上次心跳存在且可解析才记
          // BUG-119：上次心跳以持久化表为准，别的进程上报的也算数
          let prev = hb_last_seen_of(task_id)
          if prev != "" && prev != ts {
            let now_s = @ops.iso_to_secs(ts)
            let prev_s = @ops.iso_to_secs(prev)
            if now_s >= 0 && prev_s >= 0 && now_s > prev_s {
              ignore(
                engine.store_write_heartbeat_interval(
                  task_id~,
                  interval_sec=now_s - prev_s,
                  ts~,
                ),
              )
            }
          }
          // 内存心跳表
          heartbeats.beat(task_id, signal~, now=ts)
          // SQLite 持久化：落库失败不阻塞主流程，但必须如实回执（BUG-119）——
          // 内存后端下 write_heartbeat 也返回 Ok，所以"是否落库"只能看后端自述
          let store_ok = match
            engine.store_write_heartbeat(
              agent_id="fist-mbt",
              task_id~,
              last_seen=ts,
              status=signal,
            ) {
            Ok(_) => true
            Err(_) => false
          }
          let hb_backend = engine.heartbeat_backend()
          Ok(
            @mcp.ToolResult::text(
              Json::object({
                "task_id": Json::string(task_id),
                "signal": Json::string(signal),
                "last_seen": Json::string(heartbeats.last_seen_of(task_id)),
                "backend": Json::string(hb_backend),
                "persisted": Json::boolean(store_ok && hb_backend == "sqlite"),
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
    "no_signal 看护（AO watchdog）：心跳超时静默的活跃任务（执行中/已领取/拆分中）回滚为已领取待重派。参数：timeout_sec(可选默认600)、namespace(可选)。**namespace 不传时扫全库所有命名空间**（BUG-81：多 ns 共用同一个 fist-mbt.db，一次不带 ns 的 heal 会把别的轮次的在途任务一并 reopen，而 reopen 不署名 ⇒ 枝干 assignee 被清空）；只想看护自己这一批就显式传 ns。返回 { healed, count, scope, namespace, backend, heartbeat_source, message }，scope 明说这次是全库还是单 ns（时间戳一律服务端盖章，不接受调用方注入 now）。**判活以持久化心跳表为准**（BUG-119）：没有心跳行不等于「已静默」，此时退到任务行的 `updated_at`（claim/execute/reopen 都会盖章它）——距最后一次活动超过 timeout_sec 才回滚，进程重启后的第一拍不再把在途任务一律打死。",
    schema(
      {
        "timeout_sec": int_prop("超时秒数(可选默认600)"),
        "namespace": string_prop(
          "作用域命名空间(可选)：只回滚该 ns 的在途任务；不传=全库（旧行为）",
        ),
      },
      [],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let ts = now_default()
      let timeout_sec = get_int(args, "timeout_sec", default=600)
      let heal_ns = get_str(args, "namespace")
      let skipped : Array[String] = []
      match
        @ops.heal_stale_tasks_from_store(
          engine,
          ts,
          timeout_sec~,
          ns=heal_ns,
          skipped_ids=skipped,
        ) {
        Ok(healed) =>
          Ok(
            @mcp.ToolResult::text(
              Json::object({
                "healed": Json::array(healed.map(fn(s) { Json::string(s) })),
                "count": Json::number(healed.length().to_double()),
                // BUG-81：作用域必须在调用面自证，不能让"回滚了 5 条"看起来总是本批次那 5 条
                "scope": Json::string(
                  if heal_ns.is_empty() {
                    "all-namespaces"
                  } else {
                    "namespace"
                  },
                ),
                "namespace": Json::string(heal_ns),
                // BUG-119：判活读的是持久化心跳表，后端身份必须写在回执里
                // （memory 后端时心跳只活在本进程，看护结论不可跨进程复现）
                "backend": Json::string(engine.heartbeat_backend()),
                "heartbeat_source": Json::string("sqlite-heartbeats"),
                // 判死但回滚不了的条目（如「已领取」不可 reopen）必须点名，不能只让 healed 变少
                "skipped": Json::array(skipped.map(fn(s) { Json::string(s) })),
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
    "定时任务看门狗编排单入口（推荐仅用于定时任务/无人值守场景，不用于人工指挥流程）：扫描活跃任务，心跳超时则回滚重派；检测到上一轮根任务已完成且提供了 next_description（或可由 meta_prompt_path 读取元提示词）时自动发布下一轮。参数：timeout_sec(可选默认600)、namespace(可选，未传则不自动续轮)、next_description(可选)、next_created_by(可选默认watchdog)、meta_prompt_path(可选)、cold_start(可选默认false，冷启动时设为true以发布首个任务)、project_dir(可选，冷启动时用于指定项目目录)、omega_strong_verify(可选默认false，开启后自动拆分并启用Omega强验证)、omega_split_n(可选默认3)、omega_spec(可选JSON)。",
    schema(
      {
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
        "autodispatch": bool_prop(
          "自治派单(可选默认false零回归，R57)：显式 namespace 无人值守且无活跃任务时，自动把顶部待领取任务按能力/负载认领给最佳执行者，结果并入 detail.autodispatch",
        ),
        "autodispatch_want": string_prop(
          "自治派单所需能力标签(可选，autodispatch=true 时按此路由；缺省自动从任务描述抽取)",
        ),
        "phi_gate": bool_prop(
          "Phi Accrual 概率式判活(可选默认false零回归)：true 时心跳超时判定改用概率怀疑度 φ（读持久化间隔历史），φ≥phi_threshold 判 suspect 才回滚——心跳节奏越快、越久没来才值得怀疑",
        ),
        "phi_threshold": int_prop(
          "phi_gate 怀疑阈值(可选默认8，原论文口径)",
        ),
        "mode": string_prop(
          "开发模式(可选默认 advance)：advance | polish | verify | bugfind | fix_and_merge | tidy | explore。非 advance 时 templates/pipeline_mode_<mode>.md **覆盖**显式 meta_prompt_path（不是反过来！BUG-77：旧描述写的是『显式优先』，代码走的是 mode 优先）；要让显式路径生效就别传 mode 或传 advance。回执里 meta_prompt_resolved 才是真被读的那份，meta_prompt_path 只是你传进来的那个。非法值立即返回 Err。",
        ),
        "flush_bug_queue": bool_prop(
          "是否自动 flush bug 队列到 GitHub/GitCode（可选默认false）——定时唤醒时顺便 flush，GitHub 失败自动切 GitCode",
        ),
      },
      [],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let ts = now_default()
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
      let phi_gate = get_bool(args, "phi_gate", default=false)
      let phi_threshold = get_int(args, "phi_threshold", default=8)
      let mode = get_str(args, "mode")
      let flush_bug_queue = get_bool(args, "flush_bug_queue", default=false)
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
          autodispatch=get_bool(args, "autodispatch", default=false),
          autodispatch_want=get_str(args, "autodispatch_want"),
          phi_gate~,
          phi_threshold~,
          mode~,
          flush_bug_queue~,
        ) {
        Ok(j) => {
          // —— flush_bug_queue 追加段（append-only，不改上面任何代码）——
          let auto_flush = get_bool(args, "flush_bug_queue", default=false)
          let mut gh_ok = false
          let flush_result : Map[String, Json] = Map([])
          if auto_flush {
            let pd = get_str(args, "project_dir")
            let actual_dir = if pd.is_empty() { "." } else { pd }
            // 1. GitHub env check
            match github_env_check() {
              Ok(ge) => {
                let gh_ready = match ge {
                  Object(m) =>
                    match m.get("ready") {
                      Some(True) => true
                      _ => false
                    }
                  _ => false
                }
                if gh_ready {
                  match github_flush_plan(actual_dir, 10) {
                    Ok(_plan) => {
                      flush_result.set("github_attempted", Json::boolean(true))
                      gh_ok = true
                    }
                    Err(e) => flush_result.set("github_error", Json::string(e))
                  }
                } else {
                  flush_result.set(
                    "github_skipped",
                    Json::string("env not ready"),
                  )
                }
              }
              Err(e) => flush_result.set("github_error", Json::string(e))
            }

            // 2. 如果 GitHub 没成功，试 GitCode
            let mut gc_ok = false
            if !gh_ok {
              match gitcode_env_check() {
                Ok(gce) => {
                  let gc_ready = match gce {
                    Object(m) =>
                      match m.get("ready") {
                        Some(True) => true
                        _ => false
                      }
                    _ => false
                  }
                  if gc_ready {
                    let pid = match gce {
                      Object(m) =>
                        match m.get("project_id") {
                          Some(String(s)) => s
                          _ => ""
                        }
                      _ => ""
                    }
                    if !pid.is_empty() {
                      match gitcode_flush_plan(actual_dir, pid, 10) {
                        Ok(_plan) => {
                          flush_result.set(
                            "gitcode_attempted",
                            Json::boolean(true),
                          )
                          flush_result.set(
                            "fallback_used",
                            Json::string("gitcode"),
                          )
                          gc_ok = true
                        }
                        Err(e) =>
                          flush_result.set("gitcode_error", Json::string(e))
                      }
                    } else {
                      flush_result.set(
                        "gitcode_skipped",
                        Json::string("project_id empty"),
                      )
                    }
                  } else {
                    flush_result.set(
                      "gitcode_skipped",
                      Json::string("env not ready"),
                    )
                  }
                }
                Err(e) => flush_result.set("gitcode_error", Json::string(e))
              }
            }

            flush_result.set("any_success", Json::boolean(gh_ok || gc_ok))
          }

          // 只在 auto_flush=true 时才合并 flush_result，保证默认路径字节级一致
          let final_json = if auto_flush {
            match j {
              Object(m) => {
                m.set("flush_bug_queue", Json::object(flush_result))
                Json::object(m)
              }
              _ => {
                let mm : Map[String, Json] = Map([])
                mm.set("flush_bug_queue", Json::object(flush_result))
                mm.set("original", j)
                Json::object(mm)
              }
            }
          } else {
            j
          }
          Ok(@mcp.ToolResult::text(final_json.stringify()))
        }
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "pipeline_tick",
    "提示词流水线状态机单入口（仅用于定时任务/无人值守命名空间，不用于人工指挥流程）：以 project_dir/currentState.txt 为唯一状态源，按四分支推进——空闲(Creating/Closed)生成新提示词、提示词已落盘(Pending)发布根任务、执行中(Running)缺报告且超时则要求补报告、报告落盘后校验收口。全程报告先行、不空转、不写脏数据。参数：project_dir(必填)、namespace(可选默认cron-auto)、phase(可选auto/prompt_ready/report_ready)、prompt_name(可选)、timeout_sec(可选默认2400)。",
    schema(
      {
        "project_dir": string_prop(
          "项目目录(必填)：其下 currentState.txt 为状态源，Gen_Prompts 为提示词目录",
        ),
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
        "mode": string_prop(
          "开发模式(可选默认 advance)：advance | polish | verify | bugfind | fix_and_merge | tidy | explore。BUG-76：本工具的 mode **只作为标签写进台账**，不读模式模板（接线只在 watchdog_tick 上做了）；要按模式取 templates/pipeline_mode_<mode>.md 请用 watchdog_tick(mode=) 或自己把路径传给 meta_prompt_path。",
        ),
      },
      [],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let ts = now_default()
      let project_dir = get_str(args, "project_dir")
      let ns = get_str(args, "namespace", default="cron-auto")
      let phase = get_str(args, "phase", default="auto")
      let prompt_name = get_str(args, "prompt_name")
      let timeout_sec = get_int(args, "timeout_sec", default=2400)
      let mode = get_str(args, "mode")
      match
        @ops.pipeline_tick(
          engine,
          project_dir,
          ts,
          ns~,
          timeout_sec~,
          phase~,
          prompt_name~,
          mode~,
        ) {
        Ok(j) => Ok(@mcp.ToolResult::text(j.stringify()))
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )
  // -------------------------------------------------------------------------
  // Phase 6 组合环 MCP 工具：loop_create / loop_tick / loop_status
  // -------------------------------------------------------------------------
  s1 = instrumented_tool(
    s1,
    "loop_create",
    "创建组合环（Phase 6 组合环编排层）：给定环名 + steps 数组或预设名（fix-iterate/build-verify/full-iterate），创建并注册到进程内 LoopRegistry。",
    schema(
      {
        "name": string_prop("组合环唯一名称(必填)"),
        "steps": Json::object({
          "type": Json::string("array"),
          "description": Json::string(
            "step mode 数组，7 种合法 mode 之一：advance/polish/verify/bugfind/fix_and_merge/tidy/explore",
          ),
          "items": string_prop("单个 step mode"),
        }),
        "preset": string_prop(
          "预设环名(可选)：fix-iterate | build-verify | full-iterate。若提供则覆盖 steps",
        ),
        "max_rounds": int_prop("硬上限(可选默认5)"),
        "stop_on_goal": bool_prop(
          "健康度 healthy+零blocked 即停(可选默认true)",
        ),
        "stop_on_exceeded": bool_prop(
          "test↑10% 或 open_bug↓50% 即停(可选默认true)",
        ),
        "baseline_test_count": int_prop("baseline 测试数(可选默认0)"),
        "baseline_open_bug_count": int_prop(
          "baseline 未关闭 bug 数(可选默认0)",
        ),
      },
      ["name"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let name = get_str(args, "name")
      if name == "" {
        return Err(@mcp_types.ToolError("name is required"))
      }
      match loop_reg.get(name) {
        Some(_) =>
          return Err(@mcp_types.ToolError("loop already exists: " + name))
        None => ()
      }
      let preset = get_str(args, "preset")
      let steps : Array[String] = if preset != "" {
        match @ops.preset_loop(preset) {
          Ok((s, _)) => s
          Err(e) => return Err(@mcp_types.ToolError(e))
        }
      } else {
        let raw = get_array(args, "steps")
        if raw.length() == 0 {
          return Err(@mcp_types.ToolError("either steps or preset is required"))
        }
        raw.map(fn(j) {
          match j {
            String(s) => s
            _ => j.stringify()
          }
        })
      }
      match @ops.validate_loop_steps(steps) {
        Some(e) => return Err(@mcp_types.ToolError(e))
        None => ()
      }
      let now = get_str(args, "now", default=now_default())
      // max_rounds 默认 5（get_int 默认 3，不能直接用）
      let max_rounds = match args {
        Object(m) =>
          match m.get("max_rounds") {
            Some(Number(n, ..)) => n.to_int()
            _ => 5
          }
        _ => 5
      }
      // stop_on_goal / stop_on_exceeded 默认 true（get_bool 默认 false）
      let stop_on_goal = match args {
        Object(m) =>
          match m.get("stop_on_goal") {
            None => true
            Some(True) => true
            Some(False) => false
            _ => true
          }
        _ => true
      }
      let stop_on_exceeded = match args {
        Object(m) =>
          match m.get("stop_on_exceeded") {
            None => true
            Some(True) => true
            Some(False) => false
            _ => true
          }
        _ => true
      }
      let baseline_test_count = match args {
        Object(m) =>
          match m.get("baseline_test_count") {
            Some(Number(n, ..)) => n.to_int()
            _ => 0
          }
        _ => 0
      }
      let baseline_open_bug_count = match args {
        Object(m) =>
          match m.get("baseline_open_bug_count") {
            Some(Number(n, ..)) => n.to_int()
            _ => 0
          }
        _ => 0
      }
      let lp = @ops.loop_create(
        name,
        steps,
        now,
        max_rounds~,
        stop_on_goal~,
        stop_on_exceeded~,
        baseline_test_count~,
        baseline_open_bug_count~,
      )
      loop_reg.set(name, lp)
      Ok(@mcp.ToolResult::text(@ops.loop_to_json(lp).stringify()))
    },
  )
  s1 = instrumented_tool(
    s1,
    "loop_tick",
    "推进一环（Phase 6）：从 LoopRegistry 取出当前 PipelineLoop，调 loop_tick 纯函数推进，更新 registry，返回 LoopTickResult JSON（含 next_mode / should_stop / stop_reason / loop_after）。",
    schema(
      {
        "name": string_prop("已注册环名称(必填)"),
        "project_health_grade": string_prop(
          "当前项目健康度等级(可选)：healthy/attention/stalled",
        ),
        "blocked_tasks": int_prop("当前 blocked_tasks 数(可选默认0)"),
        "current_test_count": int_prop("当前测试数(可选默认0)"),
        "current_open_bug_count": int_prop(
          "当前未关闭 bug 数(可选默认0)",
        ),
      },
      ["name"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let name = get_str(args, "name")
      match loop_reg.get(name) {
        None => return Err(@mcp_types.ToolError("loop not found: " + name))
        Some(lp) => {
          let now = now_default()
          let project_health_grade = get_str(args, "project_health_grade")
          let blocked_tasks = get_int(args, "blocked_tasks", default=0)
          let current_test_count = get_int(
            args,
            "current_test_count",
            default=0,
          )
          let current_open_bug_count = get_int(
            args,
            "current_open_bug_count",
            default=0,
          )
          let result = @ops.loop_tick(
            lp,
            now,
            current_test_count~,
            current_open_bug_count~,
            project_health_grade~,
            blocked_tasks~,
          )
          loop_reg.set(name, result.loop_after)
          let json = Json::object(
            Map([
              ("next_mode", Json::string(result.next_mode)),
              ("next_step_idx", Json::number(result.next_step_idx.to_double())),
              ("next_round", Json::number(result.next_round.to_double())),
              ("should_stop", Json::boolean(result.should_stop)),
              ("stop_reason", Json::string(result.stop_reason)),
              ("history", result.history_json),
              ("loop_after", @ops.loop_to_json(result.loop_after)),
            ]),
          )
          Ok(@mcp.ToolResult::text(json.stringify()))
        }
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "loop_status",
    "查询组合环状态（Phase 6）。无 name 参数时列出所有已注册环的摘要；有 name 参数时返回单个环完整 JSON。",
    schema(
      {
        "name": string_prop(
          "查询特定环的 name(可选)，缺省列出所有",
        ),
      },
      [],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let name = get_str(args, "name")
      if name != "" {
        match loop_reg.get(name) {
          None => Err(@mcp_types.ToolError("loop not found: " + name))
          Some(lp) =>
            Ok(@mcp.ToolResult::text(@ops.loop_to_json(lp).stringify()))
        }
      } else {
        let names = loop_reg.list_names()
        let arr = names.map(fn(n) {
          match loop_reg.get(n) {
            Some(lp) => @ops.loop_to_json(lp)
            None => Json::object(Map([]))
          }
        })
        Ok(@mcp.ToolResult::text(Json::array(arr).stringify()))
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
    "自驱式编程·追加/更新 memory 条目。参数：project_dir(必填)、kind(必填 thinking/product/target/task)、content(必填)、namespace。thinking 为 append-only 流水带时间戳；其余覆盖写。",
    schema(
      {
        "project_dir": string_prop("项目目录（必填）"),
        "kind": string_prop(
          "条目类型（必填）：thinking/product/target/task",
        ),
        "content": string_prop("内容（必填）"),
        "namespace": string_prop("命名空间(可选默认 default)"),
      },
      ["project_dir", "kind", "content"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let project_dir = get_str(args, "project_dir")
      let kind = get_str(args, "kind")
      let content = get_str(args, "content")
      let ns = get_str(args, "namespace", default="default")
      let ts = now_default()
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
      // BUG-82：时间戳服务端盖章（不接受调用方注入 now，见 BUG-33 政策）
      match
        @ops.selfdrive_export_tasks(engine, project_dir, ns, now=now_default()) {
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
    "自驱式编程·解析最新审视报告 `## Next Tasks` 段并将待办任务并行发布为同命名空间下独立根任务（幂等，description 内嵌 [review:<file>:<idx>] 标记防重）。参数：project_dir(必填)、namespace(可选默认 default)、max_tasks(可选默认10)。",
    schema(
      {
        "project_dir": string_prop("项目目录（必填）"),
        "namespace": string_prop("命名空间(可选默认 default)"),
        "max_tasks": int_prop("最多发布任务数(可选默认10)"),
        "mode": string_prop(
          "开发模式(可选默认 advance)：advance | polish | verify | bugfind | fix_and_merge | tidy | explore。",
        ),
      },
      ["project_dir"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let project_dir = get_str(args, "project_dir")
      let ns = get_str(args, "namespace", default="default")
      let max_tasks = get_int(args, "max_tasks", default=10)
      let ts = now_default()
      let mode = get_str(args, "mode")
      match
        @ops.selfdrive_publish_next(
          engine,
          project_dir,
          ns~,
          max_tasks~,
          now=ts,
          mode~,
        ) {
        Ok(j) => Ok(@mcp.ToolResult::text(j.stringify()))
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "mode_list",
    "返回 7 种自驱编程开发模式的完整信息（mode / name / description / constraints / template_path / forbidden_tools）。纯计算只读，供 AI 选择模式。其中 `explore`（探索模式）不直接开发：它先给目标复杂度打分（0..5，复用难度单一抽取来源），再据此**自选**一个单模式去跑；只有在候选模式申报的文件作用域两两不相交（`reserve_scope` 预订成功 + 认领前 `conflicts_check` 可认领）时才允许并行多模式，否则退回单模式串行。",
    schema({}, []),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError] {
      let modes = @ops.all_modes()
      Ok(@mcp.ToolResult::text(Json::array(modes).stringify()))
    },
  )
  s1 = instrumented_tool(
    s1,
    "mode_templates",
    "检查 templates/pipeline_mode_*.md 全部存在性，返回 {templates:{advance:true,...}, missing:[...]}。mode 参数预检用。名单从模式注册表 all_modes() 反解，不硬编码——注册表加模式而这里漏检查就是『模板缺席没人报』（BUG-118 同族：判据看不见样本就等于没判）。",
    schema({}, []),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      // 名单从模式注册表反解：注册表加模式而这里漏名单 ⇒ 模板缺席永远没人报
      let names = @ops.all_modes().map(fn(j) { get_str(j, "mode") })
      let exists : Map[String, Json] = Map([])
      let missing : Array[Json] = []
      for n in names {
        let p = @ops.mode_template_path(n)
        let ok = @fs.path_exists(p)
        exists.set(n, Json::boolean(ok))
        if !ok {
          missing.push(Json::string(n))
        }
      }
      let m : Map[String, Json] = Map([])
      m.set("templates", Json::object(exists))
      m.set("missing", Json::array(missing))
      Ok(@mcp.ToolResult::text(Json::object(m).stringify()))
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
    "自我记忆·收敛写回：verify 通过后把交付物/结论收敛写回 memory/{kind}.md（kind 缺省 target；thinking 为 append-only 带时间戳，其余覆盖写）。参数：project_dir(必填)、task_id(必填)、kind(可选默认 target)、content(必填)。返回 {consolidated, kind, chars, note}。",
    schema(
      {
        "project_dir": string_prop("项目目录（必填）"),
        "task_id": string_prop("任务 id（必填，用于 tags 注入）"),
        "kind": string_prop(
          "条目类型(可选)：thinking/product/target/task，默认 target",
        ),
        "content": string_prop("收敛内容（必填）"),
      },
      ["project_dir", "task_id", "content"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let project_dir = get_str(args, "project_dir")
      let task_id = get_str(args, "task_id")
      let kind = get_str(args, "kind", default="target")
      let content = get_str(args, "content")
      let ts = now_default()
      match memory_consolidate(project_dir, task_id, kind, content, ts) {
        Ok(j) => Ok(@mcp.ToolResult::text(j.stringify()))
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "memory_gc",
    "自我记忆·上限+软降权归档（不硬删）：超 max_chars 时把 memory/{kind}.md 末尾（老人）条目移入 memory/archive/ 归档保留，正文只保留最新 max_chars 个字符。kind 缺省对四件套全部处理。参数：project_dir(必填)、kind(可选)、max_chars(可选默认2000)。",
    schema(
      {
        "project_dir": string_prop("项目目录（必填）"),
        "kind": string_prop(
          "条目类型(可选)：thinking/product/target/task；缺省处理全部四件套",
        ),
        "max_chars": int_prop("正文上限(可选默认2000)"),
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
    "自我记忆·A-Mem 式关联：在 memory/links.md 追加一条 `from -> to  note` 关联记录（不存在则创建），供 plan/claim 前检索注入。参数：project_dir(必填)、from(必填)、to(必填)、note(可选)。返回 {linked, from, to}。",
    schema(
      {
        "project_dir": string_prop("项目目录（必填）"),
        "from": string_prop("来源概念/任务（必填）"),
        "to": string_prop("目标概念/任务（必填）"),
        "note": string_prop("关联说明(可选)"),
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
    "DGM 演化·自进化蒸馏（EvolveR 最小级）：把一次 verify 通过的任务交付物蒸馏成一条 principle 写入 DGM（goal 前加 [principle] 前缀标识，code 写蒸馏内容，复用既有 evolve_upsert 落库 + Archive 查重语义）。参数：task_id(必填)、goal(必填)、note(必填)、score(可选默认1.0)。返回 {distilled, artifact_id}。",
    schema(
      {
        "task_id": string_prop("任务 id（必填）"),
        "goal": string_prop("蒸馏出的原则/目标（必填）"),
        "note": string_prop(
          "原则说明/设计意图（必填，同时写入 code）",
        ),
        "score": number_prop("可计算评分(默认1.0)"),
      },
      ["task_id", "goal", "note"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let goal = get_str(args, "goal")
      let note = get_str(args, "note")
      let score = get_double(args, "score", default=1.0)
      let ts = now_default()
      let j = do_evolve_distill(evolve_arc, evolve_store, goal, note, score, ts)
      Ok(@mcp.ToolResult::text(j.stringify()))
    },
  )
  s1 = instrumented_tool(
    s1,
    "evolve_submit",
    "DGM 演化·归档一个产物（Artifact）：把本轮设计/代码/目标加入档案库，自动递增父代子代数。参数：id、goal、note、code、score、parent_id(可选)、parts(可选 JSON 对象)。",
    schema(
      {
        "id": string_prop("产物 id（必填，唯一）"),
        "goal": string_prop("目标/本轮想解决的问题（必填）"),
        "note": string_prop("设计意图（必填，查重/新颖性用）"),
        "code": string_prop("实现内容（必填）"),
        "score": number_prop("可计算评分(默认0)"),
        "parent_id": string_prop("父产物 id（可选）"),
        "parts": string_prop("评分分项 JSON(可选)"),
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
      let ts = now_default()
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
    "自进化·失败回流学习（learn-from-reject）：把一次被打回/失败的原因归档成一条 [lesson]<类目> 资产入 DGM，让建档库能「学教训」——note 存失败原因、code 存纠偏提示，plan/claim 的 inject 可按类目命中「踩过的坑」。参数：cat 类目(必填，检索 tag)、reason 失败原因(必填)、fix 纠偏提示(可选)、score(可选默认0.5)。返回 {learned, artifact_id}。",
    schema(
      {
        "cat": string_prop(
          "教训类目（必填，检索 tag，自动拼成 goal=[lesson]<cat>）",
        ),
        "reason": string_prop("失败/被打回的原因（必填）"),
        "fix": string_prop("纠偏提示/来源（可选，无则用 reason）"),
        "score": number_prop("可计算评分(默认0.5)"),
      },
      ["cat", "reason"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let cat = get_str(args, "cat")
      let reason = get_str(args, "reason")
      let fix = get_str(args, "fix")
      let score = get_double(args, "score", default=0.5)
      let ts = now_default()
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
    "自进化·Critic 防漂移门禁（SAGE 论文落地，杜绝课程漂移）：把一条「拟入库的 principle/lesson/资产」的 note 交给 Critic 评审，复用 Archive::novelty + scoring 纯计算，返回是否放行 {admit} 与理由——与档案库最相似资产重合 ≥70% 判「疑似课程漂移/重复」直接建议拒绝；综合分(0.5*score+0.5*新颖度)低于阈值判「稳健性不足」暂缓入库。只评审不写库，供入库前决策。参数：note 候选资产意图/原因(必填)、score 可计算评分(默认0.5)、threshold 放行阈值(默认0.85)。返回含 top_hit 最相似资产。",
    schema(
      {
        "note": string_prop(
          "候选资产的意图/原因（必填，用于新颖度/查重）",
        ),
        "score": number_prop("可计算评分(默认0.5)"),
        "threshold": number_prop("放行阈值(默认0.85)"),
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
      },
      ["source", "note", "code"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let source = get_str(args, "source")
      let note = get_str(args, "note")
      let code = get_str(args, "code")
      let score = get_double(args, "score", default=0.0)
      let ts = now_default()
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
    "Laya 决策工具（自动探测 + 确定性回退）：用 Laya（Python ML 决策模型）对任务/文本快速分类并给出「该用哪些功能机制 + 建议拆分数」决策；**机器无 Laya 或探测失败时，自动降级到内建规则式决策分支**（laya_route 纯计算：按任务描述关键词对机制族打分选最匹配 feature_route + 按复杂度启发式给 split_n），绝不阻断现网。参数：context(必填)、split_n_hint(可选整数，建议拆分数基线默认3)、questions(可选 JSON)、model(可选默认 english)、**no_sidecar(可选默认 false；true=跳过探测与 sidecar，直取规则式分支——无人值守流水线在延迟预算内显式选降级的逃生门)**。⏱ **延迟预算（BUG-18）**：本工具的服务端预算与 `.mcp.json` 的 `timeout_ms=30000` 显式对齐——探测 ≤5s（结果进程内缓存 TTL 5min，不再每次 `import laya`）+ sidecar ≤20s = 25s < 30s，服务端一定先于客户端出结论；若你的机器 Laya 更慢（本机实测 sidecar 单跑约 279s），要么接受降级 decision，要么同时上调 `.mcp.json` 与 src/server/server.mbt 的三个 laya_*_budget 常量。超时/失败**不报错**，回 available=false + 可用 decision。返回 { available, decision:{source/feature_route/split_n/splits_per_family/reasons} }；**decision 恒在**（BUG-14 修复：sidecar 只产出 answers，其 feature_route/split_n 由 laya_route 规则式分支补齐；sidecar 若自带 decision 则原样保留），available=false 表示 Laya 不可用（或被本预算截断）、此时 decision.source=fallback，available=true 时 answers 为 Laya 原始分类结果、decision 为可执行基线。",
    schema(
      {
        "context": string_prop("待决策的任务/文本描述（必填）"),
        "split_n_hint": int_prop("拆分数基线(可选，默认3)"),
        "questions": string_prop(
          "决策问题 schema JSON（可选；缺省用 Laya 内置 default questions）",
        ),
        "model": string_prop("Laya 模型(可选默认 english)"),
        "no_sidecar": bool_prop(
          "跳过 Laya 探测与 sidecar、直接走内建规则式分支(可选，默认 false=现状零回归)。用于在 30s 客户端超时预算内拿确定性决策（BUG-18）",
        ),
      },
      ["context"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let context = get_str(args, "context")
      if context == "" {
        return Err(@mcp_types.ToolError("context 不能为空"))
      }
      let split_n_hint = get_int(args, "split_n_hint", default=3)
      let questions_raw = get_str(args, "questions", default="")
      let model = get_str(args, "model", default="english")
      // 0) BUG-18 逃生门：显式不要 sidecar → 0 次 spawn，直接规则式决策。
      //    默认 false，既有调用（不传本参数）行为逐字不变。
      if get_bool(args, "no_sidecar", default=false) {
        return Ok(
          @mcp.ToolResult::text(
            Json::object({
              "available": Json::boolean(false),
              "sidecar": Json::string("skipped"),
              "decision": route_decision(context, split_n_hint),
              "note": Json::string(
                "调用方显式 no_sidecar=true：跳过 Laya 探测与 sidecar（BUG-18 延迟预算逃生门），直取内建规则式决策分支 laya_route；确定性、零延迟、可复现",
              ),
            }).stringify(),
          ),
        )
      }
      // 1) 探测（BUG-18：改走进程内 TTL 缓存 + 与客户端超时对齐的小预算；
      //    旧版每次无条件 15s 探测是 4 分钟阻塞的一半成因）
      let probe : Result[Bool, String] = laya_probe_cached(
        "python",
        ["scripts/laya_decide.py", "--probe"],
        ".",
        laya_probe_budget_ms,
      )
      let avail = match probe {
        Ok(a) => a
        Err(_) => false
      }
      if not(avail) {
        // 无 Laya（或探测失败/超时）→ 确定性回退分支（本自驱改造核心：不再是空降级，而给出可用决策）
        return Ok(
          @mcp.ToolResult::text(
            Json::object({
              "available": Json::boolean(false),
              "decision": route_decision(context, split_n_hint),
              "note": Json::string(
                "机器上未探测到 Laya（或探测失败/超出 \{laya_probe_budget_ms}ms 预算），已降级到内建规则式决策分支（laya_route）",
              ),
            }).stringify(),
          ),
        )
      }
      // 2) 可用 → 调 sidecar 决策（BUG-18：预算 ≤20s，与 probe 合计仍小于 .mcp.json 的 30s）
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
          laya_sidecar_budget_ms,
        ) {
        Ok(res) =>
          // BUG-14：sidecar 退出码 0（available 真假皆然）也必须带 decision，
          // 否则描述承诺的 decision.feature_route/split_n 在这条主路径上是 undefined。
          Ok(
            @mcp.ToolResult::text(
              laya_ensure_decision(res, context, split_n_hint).stringify(),
            ),
          )
        Err(e) =>
          // 调度失败也降级（不报错）；降级同样必须给可执行的 decision
          Ok(
            @mcp.ToolResult::text(
              Json::object({
                "available": Json::boolean(false),
                "fallback": Json::string("use existing schedule / LLM"),
                "reason": Json::string("laya sidecar 调用失败: \{e}"),
                "decision": route_decision(context, split_n_hint),
              }).stringify(),
            ),
          )
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "task_cleanup",
    "归档清理：删除超过保留期的已归档任务。参数：retention_days(可选默认30)。",
    schema(
      { "retention_days": int_prop("归档保留天数(可选默认30)") },
      [],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let ts = now_default()
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
    "发布带依赖关系的根任务。参数：project_dir、description、depends_on(依赖任务 id JSON 数组)、namespace、created_by。",
    schema(
      {
        "project_dir": string_prop("项目目录（必填）"),
        "description": string_prop("任务描述（必填）"),
        "depends_on": string_prop("依赖任务 id 列表 JSON 数组(可选)"),
        "namespace": string_prop("命名空间(默认 default)"),
        "created_by": string_prop("创建者身份(默认 human_steward)"),
      },
      ["project_dir", "description"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let project_dir = get_str(args, "project_dir")
      let description = get_str(args, "description")
      let depends_on_raw = get_str(args, "depends_on", default="[]")
      let ns = get_str(args, "namespace", default="default")
      let created_by = get_str(args, "created_by", default="human_steward")
      let ts = now_default()
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
    "给任务追加一条前置依赖（显式构建 DAG 依赖边，不只靠 plan_deep 隐式父子；供 dag_check/ready/critical_path/ascii 使用）。参数：task_id 任务(必经)、dep_id 前置依赖任务 id(必经)。幂等去重；校验两任务存在且非自身。返回追加后的任务 JSON。",
    schema(
      {
        "task_id": string_prop("任务 id（必填）"),
        "dep_id": string_prop("前置依赖任务 id（必填）"),
      },
      ["task_id", "dep_id"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let task_id = get_str(args, "task_id")
      let dep_id = get_str(args, "dep_id")
      let ts = now_default()
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
    "dag_slack",
    "瓶颈与松弛分析（PERT/CPM 硬核调度，R71）：对每个任务算 earliest/latest/slack（0=关键路径，>0=可灵活并行安排），返回 { makespan, critical:[关键任务], slack_map:{id:{earliest,latest,slack}}, cycle:[成环任务] }——找出【谁在关键路径上、谁有松弛可并行】，直接支撑排程优化。无参数。",
    schema({}, []),
    async fn(_args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      Ok(@mcp.ToolResult::text(engine.dag_slack_analysis().stringify()))
    },
  )
  s1 = instrumented_tool(
    s1,
    "dag_schedule",
    "排程视图（R75 负载感知，基于 dag_slack 落成可执行排程）：返回 { critical_batch:[{task_id,earliest,slack,assignee}](关键路径瓶颈,须串行盯紧), flexible_batch:[...](slack>0,按最早开始排序可并行,未认领项附 suggest=活跃负载最低的已注册执行者), basis, note }——谁在瓶颈、谁可并行派单、建议派给谁，一目了然。无参数。",
    schema({}, []),
    async fn(_args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      Ok(@mcp.ToolResult::text(engine.dag_schedule().stringify()))
    },
  )
  s1 = instrumented_tool(
    s1,
    "dag_cost_route",
    "依赖图成本路由（R77，STAR 式蒸馏）：对 flexible(slack>0) 未认领任务按拓扑序贪心给建议执行者——执行成本(难度档易/中/难→1/2/3)+切换税(依赖执行者不同则+1，上下文切换成本)，能力约束过滤(描述命中的已注册能力标签)。返回 { cost_route:[{task_id,assignee,est_cost,switch_cost,total}], total_est_cost, basis, note }——排程优化闭环：critical_path→slack→schedule→cost_route。纯读不 claim。无参数。",
    schema({}, []),
    async fn(_args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      Ok(@mcp.ToolResult::text(engine.dag_cost_route().stringify()))
    },
  )
  s1 = instrumented_tool(
    s1,
    "dag_mc",
    "Monte Carlo 概率式完工预测（R94，Van Slyke 1963 首倡 MCS 求网络完工分布）：对作用域内每个任务按难度档([难度梯度 X]→易/中/难)采样三点三角分布时长，整网模拟 samples 次，得完工时间分布(min/mean/p50/p90/max)+按期概率 P(完工≤deadline)+关键度排行(任务出现在最长路径的频率，含近关键路径)——克服 PERT 单关键路径/merge bias，回答【能不能按期、风险在哪】。seed 固定则结果可复现；纯读无副作用。参数：namespace(可选默认 default)、root_task_id(可选，取该根子树)、deadline(可选，>0 时算 P(≤deadline))、samples(可选默认 1000，<10 钳到 10)、seed(可选默认 42)。返回 { scope, samples, deadline, p_on_time, makespan:{min,mean,p50,p90,max}, criticality:[{task_id,critical_freq}], note }；空作用域返回 insufficient。",
    schema(
      {
        "namespace": string_prop("命名空间（可选默认 default）"),
        "root_task_id": string_prop("根任务 id（可选，取该子树）"),
        "deadline": int_prop("完工期限（可选，>0 时算按期概率）"),
        "samples": int_prop(
          "模拟次数（可选默认 1000，<10 钳到 10）",
        ),
        "seed": int_prop("随机种子（可选默认 42，固定可复现）"),
      },
      [],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let ns = get_str(args, "namespace", default="default")
      let root = get_str(args, "root_task_id", default="")
      let deadline = get_int(args, "deadline", default=0)
      let samples = get_int(args, "samples", default=1000)
      let seed = get_int(args, "seed", default=42)
      Ok(
        @mcp.ToolResult::text(
          engine
          .dag_mc(ns~, root_task_id=root, deadline~, samples~, seed~)
          .stringify(),
        ),
      )
    },
  )
  s1 = instrumented_tool(
    s1,
    "plan_revise",
    "反馈驱动的计划修订（R98，ReAct arXiv 2210.03629 / CoPAL arXiv 2310.07263 蒸馏）：把「拆完即弃」升级为「执行中持续修订」——给定根任务及子任务执行反馈，计算计划三分：keep（已证有效、承诺保留）/ rework（失败或其依赖链受牵连，需返工，控级联不涟漪）/ ready（依赖全部有效且未执行，下一步可做）。feedback 缺省读真实状态（已完成/已归档=ok；已打回/已暂停=否；其余=未证）；传 [{task_id, ok}] 可显式覆盖。纯计算、只读不写库（决策建议，执行权在 agent/指挥官，与 saga 返回补偿序列同一抽象层）。参数：root_task_id 根任务（必填）、feedback 执行反馈数组（可选，[{task_id, ok}]）、namespace（可选默认 default）。返回 { ok, root_task_id, basis: status|feedback, keep_count, rework_count, ready_count, keep, rework, ready, note }。",
    schema(
      {
        "root_task_id": string_prop("根任务 id（必填）"),
        "feedback": array_prop(
          "执行反馈数组（可选，[{task_id, ok}]，缺省读真实状态）",
        ),
        "namespace": string_prop("命名空间（可选默认 default）"),
      },
      ["root_task_id"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let ns = get_str(args, "namespace", default="default")
      let root = get_str(args, "root_task_id")
      let feedback = get_array(args, "feedback")
      Ok(
        @mcp.ToolResult::text(
          engine.plan_revise(root, feedback~, ns~).stringify(),
        ),
      )
    },
  )
  s1 = instrumented_tool(
    s1,
    "goal_drift_check",
    "全局目标校验（R100，goal drift arXiv 2505.02709 / Repetitiveness Rate 2603.12710 / IntentCUA 2602.17049 / HiMAP ICML2026 蒸馏）：**advisory 判据，不是打回硬门**（BUG-25 标定，hard_gate=false）。词法相似度纯计算（复用 @evolve.tokens/jaccard/coverage 单真源，零 LLM 自评）：similarity=max(jaccard, coverage)，coverage=|根∩子|/|根| 是非对称量（子任务多写模板不被长度稀释）；drift=1-similarity >0.7 记 drift_suspect 并附 re_anchor 提示，与任一兄弟 jaccard ≥0.7 记 redundant_suspect，任一侧词数 <min_tokens(6) 记 insufficient（不判漂移——恒阳性正是本工具的原始缺陷形状）。标定实测（python scripts/calibrate_goal_drift.py，语料=本机 fist-mbt.db）：全量父子对 1262 条假阳性 1.9% vs 随机错配 400 条 81.3%（分离成立），但**改写型**父子对 39 条假阳性 59%、3 个可测家族上绝对阈值命中 15/15 ⇒ 合法拆解与真漂移在词面上不可分，verdict 一律带 advisory=true，按它自动打回会把正常子任务反复打回。subtask_id 缺省校验根下全部后代。纯计算、只读不写库。参数：root_task_id 根任务（必填）、subtask_id 单个子任务（可选，缺省校验全部）、namespace（可选默认 default）。返回 { ok, root_task_id, basis, hard_gate, threshold:{drift, redundancy, min_tokens}, calibration:{corpus, real_pairs_suspect, reworded_pairs_suspect, random_control_suspect, conclusion}, counts:{aligned, drift_suspect, redundant_suspect, insufficient}, checks:[{subtask_id, drift_score, redundancy_score, verdict, advisory, re_anchor}], note }。",
    schema(
      {
        "root_task_id": string_prop("根任务 id（必填）"),
        "subtask_id": string_prop(
          "单个子任务 id（可选，缺省校验全部后代）",
        ),
        "namespace": string_prop("命名空间（可选默认 default）"),
      },
      ["root_task_id"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let ns = get_str(args, "namespace", default="default")
      let root = get_str(args, "root_task_id")
      let subtask = get_str(args, "subtask_id", default="")
      Ok(
        @mcp.ToolResult::text(
          engine.goal_drift_check(root, subtask_id=subtask, ns~).stringify(),
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
    "返回当前命名空间的实时任务看板 ASCII：按状态分组 + 深度缩进，一眼看全貌（哪些任务、什么状态、在树哪层）。已完成一档在合计行里标出「(无交付物N)」——「已完成」不自动等于有成果（BUG-29 的探针/绕验收残留）。参数：namespace(可选，空=全部命名空间)。返回 { counts:{状态:数量}, done_no_artifact, ascii }。",
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
    "项目脉冲摘要：返回 { version, total_tasks, by_status:{状态:数量}, done_no_artifact, by_difficulty:{易/中/难/无:数量}, active_namespaces }。by_difficulty 统计待领取任务的难度结构（复用难度单一抽取来源）。done_no_artifact=已完成但交付物为空的条数（BUG-29：这一档不为 0 时，「已完成」不等于成果）。参数：namespace(可选，只统计该 ns；空=全部)。",
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
      let j = render_status_summary(tasks, mstore.ns_list(), project_version)
      Ok(@mcp.ToolResult::text(j.stringify()))
    },
  )
  s1 = instrumented_tool(
    s1,
    "project_health",
    "项目健康卡（单次调用看全项目健康）：返回 { version, grade:empty/attention/stalled/healthy, total_tasks, in_flight(执行中+已领取+拆分中), ready(待领取), done(已完成), done_no_artifact, done_no_artifact_baseline, residue_over_baseline, blocked(已暂停+已打回), reviewing(待验收), archived, blocked_tasks:[阻塞任务id] }。grade 判定：有阻塞**或残留高出基线**→attention；无任务→empty；无进行无就绪→stalled；否则→healthy。done_no_artifact=已完成但无交付物（BUG-29 探针/绕验收残留），基线=账本点名作废的条数（只许降不许升，新高即压等级）。参数：namespace(可选，只统计该 ns；空=全部)。",
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
      let j = render_project_health(tasks, project_version)
      Ok(@mcp.ToolResult::text(j.stringify()))
    },
  )
  s1 = instrumented_tool(
    s1,
    "health_check",
    "四金信号健康巡检（R102，Google SRE Book 2016「Monitoring Distributed Systems」蒸馏）：project_health 从「一个等级」升级为「四个信号」——latency（最近已完成任务完成周期 created_at→updated_at 秒，p50/p90 百分位，<3 条 insufficient）、traffic（活跃需求 in_flight+ready）、errors（失败率 已打回+已暂停/总数 >0.3 attention）、saturation（积压率 待领取/总数——SRE 先行指标：系统先积压后坏，>0.5 attention 预警）。grade=最差信号（healthy/attention/idle）。纯计算只读不写库。参数：namespace(可选，只统计该 ns；空=全部)。返回 { ok, namespace, total_tasks, signals:{latency,traffic,errors,saturation}, grade, basis }。",
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
      let j = render_health_check(tasks, if ns == "" { "all" } else { ns })
      Ok(@mcp.ToolResult::text(j.stringify()))
    },
  )
  s1 = instrumented_tool(
    s1,
    "circuit_fail",
    "熔断器·上报失败（R104，Nygard Release It! 2007 / Fowler / Azure 蒸馏）：外部调用失败后上报并推进三态状态机——Closed 窗口内失败计数达阈值 → Open（fail-fast 拒绝）；Half-Open 探测失败 → 回 Open 重启恢复定时器。参数：circuit 熔断器名（必填）（注：时间戳一律由服务端盖章，不接受调用方注入 now）、window_secs 失败窗口秒（可选默认 60）、threshold 失败阈值（可选默认 3）、recovery_secs 恢复秒（可选默认 30）、namespace（可选默认 default）。返回 { circuit, state, failures, probes_granted, probe_limit, window_secs, threshold, recovery_secs, opened_at, allow_call, note }——allow_call=false 即调用方应立即快速失败。",
    schema(
      {
        "circuit": string_prop(
          "熔断器名（必填，如 external-http / laya）",
        ),
        "window_secs": int_prop("失败窗口秒（可选默认 60）"),
        "threshold": int_prop("失败阈值（可选默认 3）"),
        "recovery_secs": int_prop("恢复秒（可选默认 30）"),
        "namespace": string_prop("命名空间（可选默认 default）"),
      },
      ["circuit"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let ns = get_str(args, "namespace", default="default")
      let circuit = get_str(args, "circuit")
      let now = now_default()
      let secs = @ops.iso_to_secs(now)
      let w = get_int(args, "window_secs", default=60)
      let thr = get_int(args, "threshold", default=3)
      let rec = get_int(args, "recovery_secs", default=30)
      Ok(
        @mcp.ToolResult::text(
          engine
          .circuit_fail(
            ns~,
            circuit~,
            now_secs=secs,
            window_secs=w,
            threshold=thr,
            recovery_secs=rec,
          )
          .stringify(),
        ),
      )
    },
  )
  s1 = instrumented_tool(
    s1,
    "circuit_succeed",
    "熔断器·上报成功（R104）：外部调用成功后回灌——Closed 复位计数；Half-Open 探测成功 → Closed（恢复，节流配额随之解除）。参数：circuit 熔断器名（必填）（注：时间戳一律由服务端盖章，不接受调用方注入 now）、namespace（可选默认 default）。返回 { circuit, state, failures, probes_granted, probe_limit, window_secs, threshold, recovery_secs, opened_at, allow_call, note }。",
    schema(
      {
        "circuit": string_prop("熔断器名（必填）"),
        "namespace": string_prop("命名空间（可选默认 default）"),
      },
      ["circuit"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let ns = get_str(args, "namespace", default="default")
      let circuit = get_str(args, "circuit")
      let now = now_default()
      let secs = @ops.iso_to_secs(now)
      Ok(
        @mcp.ToolResult::text(
          engine.circuit_succeed(ns~, circuit~, now_secs=secs).stringify(),
        ),
      )
    },
  )
  s1 = instrumented_tool(
    s1,
    "circuit_status",
    "熔断器·查询状态（R104）：查三态并做 Half-Open 到期判定——Open 且 elapsed≥recovery_secs → 转 Half-Open（**只放行 probe_limit 次探测，默认 1**，配额用尽即 allow_call=false 继续快速失败；BUG-34：旧实现全量透传，与本句承诺相反）。探测结果由 circuit_succeed/circuit_fail 上报；拿到配额却长时间不上报时，超过一个 recovery 窗自动重置配额（否则一次被吞掉的探测会把半开态永久锁死）。参数：circuit 熔断器名（必填）（注：时间戳一律由服务端盖章，不接受调用方注入 now）、namespace（可选默认 default）、probe_limit 半开探测配额（可选默认 1，<=0 视为不节流）。返回 { circuit, state, failures, probes_granted, probe_limit, window_secs, threshold, recovery_secs, opened_at, allow_call, note }。半开态下 failures 即 probes_granted（已放行探测数），不要按失败数解释。",
    schema(
      {
        "circuit": string_prop("熔断器名（必填）"),
        "namespace": string_prop("命名空间（可选默认 default）"),
        "probe_limit": int_prop(
          "半开态放行探测的配额（可选默认 1）；<=0 表示不节流",
        ),
      },
      ["circuit"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let ns = get_str(args, "namespace", default="default")
      let circuit = get_str(args, "circuit")
      let now = now_default()
      let secs = @ops.iso_to_secs(now)
      let probe_limit = get_int(args, "probe_limit", default=1)
      Ok(
        @mcp.ToolResult::text(
          engine
          .circuit_status(ns~, circuit~, now_secs=secs, probe_limit~)
          .stringify(),
        ),
      )
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
    "自驱·按推荐自动取下一单：对指定命名空间取 task_triage 的顶部推荐并认领给 agent（待领取→已领取；能力匹配 want 优先），让无人值守可按能力推荐自推进。复用 triage 排行 + claim，只动一条推荐任务、不动看门狗主流程（零回归）。参数：namespace(可选)、agent(认领者,默认 self)、want 能力关键词(可选)。返回 { picked, remaining, claimed, ns, want, task?, note|error? }。",
    schema(
      {
        "namespace": string_prop("命名空间(可选，空=全部)"),
        "agent": string_prop("认领者身份(默认 self)"),
        "want": string_prop(
          "能力关键词(可选)：命中者可领取任务优先被取单",
        ),
      },
      [],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let ns = get_str(args, "namespace")
      let agent = get_str(args, "agent", default="self")
      let want = get_str(args, "want")
      let ts = now_default()
      let j = engine.pick_next(ns, agent, want, ts)
      Ok(@mcp.ToolResult::text(j.stringify()))
    },
  )
  s1 = instrumented_tool(
    s1,
    "executor_register",
    "Marketplace·执行者能力注册（Dynamic/Marketplace 雏形，R30）：为执行者登记能力标签集合（如 [编排,json]），供 executor_route 按任务所需能力做专长路由。参数：name 执行者标识(必)、abilities 能力标签数组(可选)。返回 {name, abilities, executors}。",
    schema(
      {
        "name": string_prop("执行者标识（如 executor-A，必填）"),
        "abilities": array_prop(
          "能力标签数组（如 [\"编排\",\"json\"]）",
        ),
      },
      ["name"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let name = get_str(args, "name")
      let abs = strlist(get_array(args, "abilities"))
      // 先把持久化的既有注册回灌进进程内注册表，再登记（跨进程可复现）
      sync_db_executors()
      ignore(exec_reg.add_ability(name, abs))
      // 持久化：与 store executors 表对齐（跨 server 重启仍可被 executor_route 读到）
      let ts = now_default()
      ignore(
        engine.executor_save(
          name~,
          abilities_json=ab_to_json(abs),
          created_at=ts,
        ),
      )
      Ok(
        @mcp.ToolResult::text(
          Json::object({
            "name": Json::string(name),
            "abilities": Json::array(abs.map(fn(s) { Json::string(s) })),
            "executors": Json::number(exec_reg.list().length().to_double()),
            "persisted": Json::boolean(true),
            "ok": Json::boolean(true),
          }).stringify(),
        ),
      )
    },
  )
  s1 = instrumented_tool(
    s1,
    "executor_route",
    "Marketplace·能力路由推荐（Dynamic/Marketplace 雏形，R30；R80 历史信任轴）：给定任务所需能力 need，从已注册执行者中按 { 能力覆盖率 desc → 历史信任(名下已完成/名下总数，验收通过率，无历史 0.5 中性) desc → 负载(名下活跃任务数) asc } 排序，返回候选 + 最佳执行者 + basis——按专长+信任+负载分配（防只认领不交付）。参数：need 所需能力标签（逗号/顿号/空格分隔，如“编排,json”）。返回 {need, parsed, count, candidates, best, basis}。",
    schema(
      {
        "need": string_prop(
          "所需能力标签（如“编排,json”，必填）",
        ),
      },
      ["need"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let need = get_str(args, "need")
      sync_db_executors()
      let load = executor_loads(engine)
      let trust = engine.executor_trust()
      let j = exec_reg.route_pick_with_trust(need, load, trust)
      Ok(@mcp.ToolResult::text(j.stringify()))
    },
  )
  s1 = instrumented_tool(
    s1,
    "executor_auction",
    "Marketplace·置信度校准拍卖（Agora arXiv 2607.09600 蒸馏，R87）：把执行者分派从排序推荐升级为按出价竞拍——每个已注册执行者对任务所需能力 need 出价（显式 bid，缺省按能力覆盖率自动出价），经校准系数 1-|出价-历史验收通过率| 折扣防胜者诅咒（过度自信而兑现差的执行者被惩罚），再乘负载折扣 1/(1+负载) 得拍卖分；能力覆盖>0 方可竞拍。参数：need 所需能力标签（必填，逗号/顿号/空格分隔），bid 可选出价表 {执行者: 0..1 置信度}。返回 {need, parsed, count, bids, winner, basis, note}。",
    schema(
      {
        "need": string_prop(
          "所需能力标签（如“编排,json”，必填）",
        ),
        "bid": Json::object({
          "type": Json::string("object"),
          "description": Json::string(
            "出价表 {执行者: 0..1 置信度}（可选，缺省按能力覆盖率自动出价）",
          ),
        }),
      },
      ["need"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let need = get_str(args, "need")
      let bid = json_bid_map(args, "bid")
      sync_db_executors()
      let load = executor_loads(engine)
      let trust = engine.executor_trust()
      let j = exec_reg.auction_pick(need, load, trust, bid)
      Ok(@mcp.ToolResult::text(j.stringify()))
    },
  )
  s1 = instrumented_tool(
    s1,
    "executor_clear",
    "Marketplace·清空全部执行者能力注册（重置/整洁，R31）：清空 store executors 表（进程内注册表以 store 为空为基准重建）。无参数。返回 {persisted}。",
    schema({}, []),
    async fn(_args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let did_persist = engine.executor_clear()
      Ok(
        @mcp.ToolResult::text(
          Json::object({ "persisted": Json::boolean(did_persist) }).stringify(),
        ),
      )
    },
  )
  s1 = instrumented_tool(
    s1,
    "selfdrive_dispatch",
    "Marketplace·能力路由自动派单（R32/R33，把 R30/R31 的'路由推荐'落到动作）：先 `task_triage` 取顶部可领取任务，确定所需能力——显式 `want` 优先，否则**从任务描述自动抽取**已注册执行者的能力标签（R33 免手传）——经 `executor_route` 找最佳执行者（能力覆盖率 desc → 负载 asc），并把该任务**直接认领给该执行者**（待领取→已领取）。无匹配执行者时回退认领给 `agent`。让'按专长+负载分配'不再只是建议，而是系统自动派单。参数：namespace(可选)、agent(默认 self，回退认领者)、want 所需能力关键词(可选)。返回 {dispatched, task_id, assignee, want, need_auto, route?}。",
    schema(
      {
        "namespace": string_prop("命名空间(可选，空=全部)"),
        "agent": string_prop("认领者/回退身份(默认 self)"),
        "want": string_prop(
          "任务所需能力关键词(可选，供能力路由)",
        ),
      },
      [],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let ns = get_str(args, "namespace")
      let agent = get_str(args, "agent", default="self")
      let want = get_str(args, "want")
      let ts = now_default()
      sync_db_executors()
      // 1. 取顶部可领取任务
      let tr = engine.triage(ns, agent, want)
      let sug = match tr.value("suggestion") {
        Some(Json::Object(o)) => o
        _ => Map([])
      }
      let task_id = match sug.get("task_id") {
        Some(Json::String(id)) => id
        _ => ""
      }
      if task_id == "" {
        return Ok(
          @mcp.ToolResult::text(
            Json::object({
              "dispatched": Json::boolean(false),
              "task_id": Json::string(""),
              "assignee": Json::string(agent),
              "want": Json::string(want),
              "note": Json::string(
                "无可领取的推荐任务（待领取且依赖已满足集合为空）",
              ),
            }).stringify(),
          ),
        )
      }
      // 2. 能力决定派给谁：显式 want 优先，否则从任务描述自动抽取所需能力（R33 免手传）
      let desc = match engine.get_task(task_id) {
        Some(t) => t.get_description()
        None => ""
      }
      let need = if want != "" { want } else { auto_need(desc) }
      let load = executor_loads(engine)
      let route = exec_reg.route_pick(need, load)
      let best = match route.value("best") {
        Some(Json::Object(o)) => o
        _ => Map([])
      }
      let cov = jnum(Json::object(best), "coverage")
      let best_name = jstr(Json::object(best), "name")
      let assignee = if cov > 0.0 && best_name != "" {
        best_name
      } else {
        agent
      }
      // 3. 认领（0 状态迁移：待领取→已领取）
      match engine.claim(task_id~, assignee~, now=ts) {
        Err(e) =>
          Ok(
            @mcp.ToolResult::text(
              Json::object({
                "dispatched": Json::boolean(false),
                "task_id": Json::string(task_id),
                "assignee": Json::string(assignee),
                "want": Json::string(need),
                "note": Json::string("认领失败: " + e),
              }).stringify(),
            ),
          )
        Ok(_) =>
          Ok(
            @mcp.ToolResult::text(
              Json::object({
                "dispatched": Json::boolean(true),
                "task_id": Json::string(task_id),
                "assignee": Json::string(assignee),
                "want": Json::string(need),
                "need_auto": Json::boolean(want == "" && need != ""),
                "routed": Json::boolean(assignee != agent),
                "route": Json::object({
                  "best": Json::string(best_name),
                  "coverage": Json::number(cov),
                }),
              }).stringify(),
            ),
          )
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "reserve_scope",
    "预订一个工作作用域（文件/目录/资源）防多 agent 并发编辑冲突。若作用域空闲（未被他人活体预订）则由本 agent 占据，否则返回持有者。TTL 由 ttl_until(ISO-8601 未来时间戳串)给定；到时自动视为可让渡。参数：scope、agent、ttl_until(必)。",
    schema(
      {
        "scope": string_prop(
          "作用域（如 src/foo.mbt 或模块名，必填）",
        ),
        "agent": string_prop("预订者（如 exec_1，必填）"),
        "ttl_until": string_prop("TTL 截止时间戳（ISO-8601，必填）"),
      },
      ["scope", "agent", "ttl_until"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let scope = get_str(args, "scope")
      let agent = get_str(args, "agent")
      let ttl_until = get_str(args, "ttl_until")
      let now = now_default()
      // BUG-136：这里过去是「先 rsv_get 判空闲、再无条件 rsv_set」——两个进程都读到空闲
      // 就都写成功，两边都拿到 reserved=true 而表里只剩最后一笔。裁决交回后端，工具面只渲染结论。
      match engine.rsv_try_set(scope~, agent~, ttl_until~, created_at=now) {
        Err(e) => Err(@mcp_types.ToolError(e))
        Ok(o) =>
          Ok(
            @mcp.ToolResult::text(
              Json::object({
                "scope": Json::string(scope),
                "agent": Json::string(if o.reserved { agent } else { o.agent }),
                "ttl_until": Json::string(o.ttl_until),
                "reserved": Json::boolean(o.reserved),
                "action": Json::string(o.action),
                "prev_agent": Json::string(o.prev_agent),
                "held_by": Json::string(if o.reserved { "" } else { o.agent }),
                "reason": Json::string(
                  if o.reserved {
                    ""
                  } else {
                    "该作用域已被其他 agent 活体预订"
                  },
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
    "查询某工作作用域是否可编辑（空闲可用）。参数：scope。",
    schema({ "scope": string_prop("作用域（必填）") }, ["scope"]),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let scope = get_str(args, "scope")
      let now = now_default()
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
  s1 = instrumented_tool(
    s1,
    "cost_budget_split",
    "预算按依赖图阶段切分（R81，ZEBRA 背包水填充蒸馏简化版）：给定总预算，按任务 DAG 阶段(slack 分析 earliest 层级)切分——每阶段份额=阶段难度权重(难3/中2/易1)占总量比例×总预算(余数补最大权重阶段)。返回 { verdict: ok|rejected|insufficient, stages:[{level,tasks,difficulty_sum,share}], total_budget, makespan, scope:{root_task_id,namespace,scoped_task_count,scope_kind}, note }——瓶颈阶段(关键路径层)占额可见，超支先预警。参数：budget(总预算，必填，**必须为正**：负数/0 直接 rejected，过去 -50 会切出 -42/-5/-2 的负份额)、task_id(可选：只按该任务子树切分)、namespace(可选：不给 task_id 时按该 ns 切分)。BUG-20：这两个作用域参数过去**传了也不生效**、恒扫全库（某轮 7 个任务的子树被报成 tasks=1152＝全库数）；现在真的参与取数，且切了哪些任务写在 scope 里自证。两个都不传＝全库（旧行为，scope_kind=whole-store）。",
    schema(
      {
        "budget": number_prop("总预算（必填，正整数）"),
        "task_id": string_prop(
          "作用域根任务(可选)：只对该任务的子树切分；与 namespace 同时给时以子树为准",
        ),
        "namespace": string_prop(
          "作用域命名空间(可选)：不给 task_id 时按该 ns 切分；都不给＝全库",
        ),
      },
      ["budget"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let budget = jnum(args, "budget").to_int()
      let root = get_str(args, "task_id")
      let ns = get_str(args, "namespace")
      Ok(
        @mcp.ToolResult::text(
          engine.budget_split_by_dag(budget, root~, ns~).stringify(),
        ),
      )
    },
  )
  s1 = instrumented_tool(
    s1,
    "progress_gate",
    "进度预算路由门控（R88，PROGROUTER arXiv 2608.25992 蒸馏）：对任务子树按已消耗预算(难度权重 易/中/难→1/2/3，自动估算或手动注入 spent) 与 完成进度(已完成+已归档/子树任务数) 做双路径剩余成本预测——线性=燃尽率×剩余工作量、保守=1.2×线性，元门控给决策 OK(预算充足继续) / CAUTION(线性可行但缓冲不足，建议降档缩范围) / ESCALATE(线性已超支，建议追加预算或暂停)——计划性增强：预算×进度在线体检，先预警后决策。参数：task_id(必)、budget(总预算，必)、spent(可选手动注入已消耗，缺省按难度权重自动估算)。返回 {ok, task_id, budget, spent, remaining, progress, burn_rate, projection:{linear, conservative}, verdict, action, basis}。",
    schema(
      {
        "task_id": string_prop(
          "任务 id（必填，以其为根的子树参与进度/预算统计）",
        ),
        "budget": number_prop("总预算（必填，正整数）"),
        "spent": number_prop(
          "已消耗（可选，手动注入；缺省按子树非待领取任务难度权重 易/中/难→1/2/3 自动估算）",
        ),
      },
      ["task_id", "budget"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let task_id = get_str(args, "task_id")
      let budget = jnum(args, "budget").to_int()
      let spent = jnum(args, "spent").to_int()
      Ok(
        @mcp.ToolResult::text(
          engine.progress_gate(task_id, budget, spent).stringify(),
        ),
      )
    },
  )
  s1 = instrumented_tool(
    s1,
    "phi_accrual",
    "Phi Accrual 概率式故障检测（R89，Hayashibara 2004 经典算法）：按心跳间隔历史分布算怀疑度 φ=-log10(P(心跳晚于 elapsed 到达))，替代固定 timeout——窗口内间隔均值 μ + 标准差 σ 建模（σ≈0 回退指数分布；|z|≥3 用尾部渐近展开保精度），φ≥threshold（默认 8，原论文口径）判 suspect 否则 healthy；无间隔历史返回 insufficient；**取值域外返回 rejected 且不出结论**（BUG-26：elapsed<0、间隔≤0、非整数或越出 Int 域的值过去会被静默饱和/截断后照样回一个 healthy，看护据此不 heal，任务就永久卡着）。升级 watchdog/heal 看护语义：心跳节奏越快、越久没来才值得怀疑，而非固定超时。参数：intervals 心跳间隔历史（秒数组，必填）、elapsed 自上次心跳起的秒数（必填）、threshold 怀疑阈值（可选默认 8）。返回 { verdict: insufficient|rejected|healthy|suspect, phi, mean, stddev, window, threshold, note, basis }；rejected 时只有 verdict/phi/window/threshold/note/basis，没有 mean/stddev（没有可信均值，不伪造）。",
    schema(
      {
        "intervals": array_prop(
          "心跳间隔历史（秒，整数数组，必填；元素须为 1..2147483647 的整数）",
        ),
        "elapsed": number_prop(
          "自上次心跳起的秒数（必填，0..2147483647 的整数）",
        ),
        "threshold": number_prop(
          "怀疑阈值（可选，默认 8，原论文口径）",
        ),
      },
      ["intervals", "elapsed"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      // BUG-26：这里原先用 intlist(...) / jnum(...).to_int()，两者都会**静默**把
      // 1e300 饱和成 2147483647、把 1.5 截断成 1、把非数字元素整个丢掉。
      // φ 的建模输入失真后输出仍是格式完好的判定，所以改成逐个严格转换并按原值报错。
      let raw = get_array(args, "intervals")
      let intervals : Array[Int] = []
      let offs : Array[String] = []
      let mut idx = 0
      for item in raw {
        match item {
          Json::Number(n, ..) =>
            match @engine.phi_coerce_seconds(n) {
              Some(v) => intervals.push(v)
              None =>
                offs.push("intervals[" + idx.to_string() + "]=" + n.to_string())
            }
          _ =>
            offs.push(
              "intervals[" +
              idx.to_string() +
              "] 不是数字（过去会被直接丢掉＝少一个观测）",
            )
        }
        idx = idx + 1
      }
      let el = match args.value("elapsed") {
        Some(Json::Number(n, ..)) => @engine.phi_coerce_seconds(n)
        _ => None
      }
      let bad = offs
      if el == None {
        let shown = match args.value("elapsed") {
          Some(j) => j.stringify()
          None => "缺失"
        }
        bad.push("elapsed=" + shown + "（须为 0..2147483647 的整数）")
      }
      if not(bad.is_empty()) {
        return Err(
          @mcp_types.ToolError(
            "phi_accrual: 取值域外 " +
            rq_join(bad) +
            "。BUG-26：这类输入过去会被静默饱和后照常输出 healthy，看护据此不 heal。",
          ),
        )
      }
      let elapsed = match el {
        Some(v) => v
        None => 0
      }
      let threshold = match args.value("threshold") {
        None => 8
        Some(Json::Null) => 8
        Some(Json::Number(n, ..)) =>
          match @engine.phi_coerce_seconds(n) {
            Some(v) => v
            None => -1
          }
        _ => 8
      }
      if threshold == -1 {
        return Err(
          @mcp_types.ToolError(
            "phi_accrual: threshold 越出 Int 域或带小数，取值域是 1..2147483647 的整数（BUG-26）",
          ),
        )
      }
      let j = if threshold > 0 {
        @engine.phi_accrual(intervals, elapsed, threshold~)
      } else {
        @engine.phi_accrual(intervals, elapsed)
      }
      Ok(@mcp.ToolResult::text(j.stringify()))
    },
  )

  // ---- Saga 补偿事务（R92，Garcia-Molina & Salem 1987 蒸馏） ----
  s1 = instrumented_tool(
    s1,
    "saga_register",
    "Saga 补偿登记（R92，durable action log）：多步骤任务链的每个前向步骤成功后，登记其「可补偿动作」（业务逆转描述）——失败时按 LIFO 优雅收尾，而非卡死/整树重来。幂等：同 (namespace, root_task_id, step) 重登记会重置为 pending 并刷新 compensation（重试安全）。参数：root_task_id 根任务（必填）、step 步骤名（必填）、compensation 补偿动作描述（必填，业务逆转而非逆向操作）、task_id 执行该步骤的任务（可选）、namespace 命名空间（可选默认 default）（注：时间戳一律由服务端盖章，不接受调用方注入 now）。返回 { root_task_id, step, task_id, compensation, status: pending, registered }。",
    schema(
      {
        "root_task_id": string_prop("根任务 id（saga 作用域，必填）"),
        "step": string_prop("前向步骤名（必填）"),
        "compensation": string_prop(
          "补偿动作描述（必填，业务逆转动作）",
        ),
        "task_id": string_prop("执行该步骤的任务 id（可选）"),
        "namespace": string_prop("命名空间（可选默认 default）"),
      },
      ["root_task_id", "step", "compensation"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let ns = get_str(args, "namespace", default="default")
      let root_task_id = get_str(args, "root_task_id")
      let step = get_str(args, "step")
      let task_id = get_str(args, "task_id", default="")
      let compensation = get_str(args, "compensation")
      let now = now_default()
      match
        engine.saga_register(
          ns~,
          root_task_id~,
          step~,
          task_id~,
          compensation~,
          now~,
        ) {
        Err(m) => Err(@mcp_types.ToolError(m))
        Ok(j) => Ok(@mcp.ToolResult::text(j.stringify()))
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "saga_rollback",
    "Saga 补偿序列（R92）：按 LIFO（严格倒序，后登记先补偿）返回某根任务待补偿步骤序列。mark=true（默认）返回后即标记 done（幂等：重复调用已补偿步骤不再出现，防重复回滚）；mark=false 仅预览不消费。补偿是业务逆转动作，由调用方（指挥官/agent）按 pending 顺序执行真实补偿。参数：root_task_id 根任务（必填）、mark 是否消费（可选默认 true）、namespace（可选默认 default）。返回 { root_task_id, lifo, pending_count, pending: [{id, step, task_id, compensation, status}], marked_done, note }。",
    schema(
      {
        "root_task_id": string_prop("根任务 id（saga 作用域，必填）"),
        "mark": bool_prop(
          "返回后即标记 done（可选默认 true，幂等）",
        ),
        "namespace": string_prop("命名空间（可选默认 default）"),
      },
      ["root_task_id"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let ns = get_str(args, "namespace", default="default")
      let root_task_id = get_str(args, "root_task_id")
      let mark = get_bool(args, "mark", default=true)
      match engine.saga_rollback(ns~, root_task_id, mark~) {
        Err(m) => Err(@mcp_types.ToolError(m))
        Ok(j) => Ok(@mcp.ToolResult::text(j.stringify()))
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "saga_repair",
    "Saga 局部补偿（R96，Plan Commitment / scope-aware repair 蒸馏）：给定失败步骤，计算最小补偿切片——失败步骤 + 其依赖下游（任务 depends_on 传递闭包中仍 pending 的步骤，无 task_id 时按注册序保守兜底）——只补偿切片（LIFO），切片外步骤保留承诺不补偿（keep，控级联不涟漪撤销），与 saga_rollback 全局 LIFO 整链收尾互补。mark=true（默认）返回后即把切片标记 done（幂等），keep 步骤保持 pending 供后续按需补偿。参数：root_task_id 根任务（必填）、failed_step 失败步骤名（必填）、mark 是否消费切片（可选默认 true）、namespace（可选默认 default）。返回 { root_task_id, failed_step, basis: depends_on|order, compensate_count, keep_count, compensate: [{id, step, task_id, compensation, status}], keep: [...], marked_done, note }。",
    schema(
      {
        "root_task_id": string_prop("根任务 id（saga 作用域，必填）"),
        "failed_step": string_prop("失败的前向步骤名（必填）"),
        "mark": bool_prop(
          "返回后即标记切片 done（可选默认 true，幂等）",
        ),
        "namespace": string_prop("命名空间（可选默认 default）"),
      },
      ["root_task_id", "failed_step"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let ns = get_str(args, "namespace", default="default")
      let root_task_id = get_str(args, "root_task_id")
      let failed_step = get_str(args, "failed_step")
      let mark = get_bool(args, "mark", default=true)
      match engine.saga_repair(ns~, root_task_id, failed_step~, mark~) {
        Err(m) => Err(@mcp_types.ToolError(m))
        Ok(j) => Ok(@mcp.ToolResult::text(j.stringify()))
      }
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
    "查看追加式审计日志。**注意：** audit_log 仅返回**本进程生命周期**内的内存记录（AuditLog 不落库，见 src/ops/audit.mbt 设计注）；跨进程查询请改用 call_log。返回体恒为 {scope:'process', entries, count, note}，**空 entries 不代表没发生过治理动作**。可选 filter_actor、filter_task_id。",
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
      // BUG-3 fix: 恒返回带 scope/note 的对象（构造集中在 audit_log_payload，契约可测）。
      Ok(@mcp.ToolResult::text(audit_log_payload(entries).stringify()))
    },
  )
  // ---- multi-store 命名空间工具 ----
  s1 = instrumented_tool(
    s1,
    "store_open",
    "打开（或复用）一个命名空间。参数：namespace、data_dir(可选，默认当前目录；**只接受相对 server 进程 cwd 的相对路径**——含 .. / 前导分隔符 / 盘符一律拒。BUG-78：过去 data_dir 原样拼接，指到哪就往哪建 .db，『命名空间物理隔离』形同虚设)、scratch(可选，true 时库落 temp/ 临时区，不污染仓库根)。返回 {namespace, opened, data_dir, path}；失败原因分列（非法 ns 与非法 data_dir 不合并成一句『打开失败』，否则调用方不知道该改哪个参数）。",
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
      // BUG-78：原因分列再动手——把非法 ns 和非法 data_dir 合并成一句"打开失败"，
      // 调用方就只能猜该改哪个参数（本项目对拒绝文案的一贯要求：自带出路）
      if @store.MultiStore::safe_ns(ns) is None {
        return Err(
          @mcp_types.ToolError(
            "store_open: 非法 namespace=\{ns}（只允许字母/数字/_/-，拒分隔符与穿越）",
          ),
        )
      }
      if not(@store.MultiStore::data_dir_ok(dir)) {
        return Err(
          @mcp_types.ToolError(
            "store_open: 非法 data_dir=\{dir}（只接受相对 server 进程 cwd 的相对路径，拒 .. 、前导分隔符、盘符）。两条出路：① 传相对目录（如 temp/ns-probe）；② 直接给 scratch=true 落 temp/",
          ),
        )
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
    "上报一个运行时 bug：追加到 {project_dir}/memory/bugs.md（OPEN 状态账本）。**注意：** project_dir 必须是**相对 server 进程 cwd** 的相对路径（拒绝绝对路径/盘符/..）。返回值含 resolved_path（**绝对** + normalize 后的落点）与 server_cwd（server 进程自己的工作目录，同样规范化成正斜杠）——BUG-134：这一句从前是真的悬空（实现回显的是相对 server cwd 的规范化路径，账写进哪本台账从回执本身判不出来），现在两者同批回显，一比就知道有没有写错轨；server_cwd 为空串表示宿主取不到 cwd，此时 resolved_path 退回相对形态，别当绝对落点读。参数：project_dir(必填)、summary(必填)、detail(可选)、severity(可选 open/critical/high/medium/low)、ref_call_id(可选，指向 call_log 的 seq)、reported_by(可选)、publish_task(可选默认false)：为 true 时同时把'修复 bug: <summary>'发布为独立根任务，供自驱/定时流水线认领修复，形成上报→修复闭环；task_ns(可选，缺省 bugs)：修复单落到哪个命名空间——想与本批次任务树同库对账就显式传它，否则默认落在 ns `bugs`（那是另一棵树，按批次 ns 查会查不到，BUG-8）；auto_push(可选默认false)：上报后立即尝试推送到远端 issue 系统——GitHub 优先，失败自动切 GitCode fallback；remote_fallback(可选默认 '[\"github\",\"gitcode\"]')：远端 fallback 顺序 JSON 数组字符串，auto_push=true 时生效。返回 {bug_id, id, status, path, resolved_path, server_cwd, project_dir, task_namespace, task_id?, auto_push?}：**bug_id 与 id 是同一个编号的两个键**（BUG-11：写侧只发 bug_id、读侧 bug_list 只发 id，按任一侧字段名对账的另一侧会静默拿到 null）；task_namespace 回显修复单实际落在哪个 ns（未发单时是空串，不是 'bugs'）。**账本状态**（OPEN/FIXED/DUPLICATE/FALSE_POSITIVE）写在条目抬头，改它走 `bug_fix`（标修好，同一笔落 ### FIXED 小记）或 `bug_mark_status`（改判 OPEN/DUPLICATE/FALSE_POSITIVE）——BUG-9 之前这里写着「本模块不提供关闭 API」，账本因此只写不销；对外那句「X 条待修 / Y 条已修」只从抬头状态反解，不是数小记条数。",
    schema(
      {
        "project_dir": string_prop(
          "项目目录（必填，**相对 server 进程 cwd**，拒绝绝对路径/盘符/..）",
        ),
        "summary": string_prop("bug 摘要（必填）"),
        "detail": string_prop("详细描述(可选)"),
        "severity": string_prop(
          "严重度(可选)：critical/high/medium/low（缺省 medium；闭集与账本抬头文法逐字对齐，BUG-88）",
        ),
        "ref_call_id": string_prop("关联 call_log seq(可选)"),
        "reported_by": string_prop("上报者(可选)"),
        "publish_task": bool_prop(
          "是否发布修复根任务(可选默认false)",
        ),
        "task_ns": string_prop(
          "修复单落到的命名空间(可选，缺省 bugs)；publish_task=false 时无效果",
        ),
        "auto_push": bool_prop(
          "上报后立即尝试推送到远端 issue 系统(可选默认false)——GitHub 优先，失败自动切 GitCode",
        ),
        "remote_fallback": string_prop(
          "远端 fallback 顺序 JSON 数组字符串(可选默认 '[\"github\",\"gitcode\"]')——auto_push=true 时生效",
        ),
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
      let task_ns = get_str(args, "task_ns")
      let auto_push = get_bool(args, "auto_push", default=false)
      let remote_fallback_raw = get_str(args, "remote_fallback")
      let ts = now_default()
      let bug_result = match
        report_bug(
          project_dir,
          summary,
          detail~,
          severity~,
          ref_call_id~,
          reported_by~,
          publish_task~,
          task_ns~,
          engine,
          now=ts,
        ) {
        Ok(j) => j
        Err(e) => return Err(@mcp_types.ToolError(e))
      }
      // 从 report_bug 返回提取 bug_id
      let bug_id = match bug_result {
        Object(m) =>
          match m.get("bug_id") {
            Some(String(s)) => s
            _ => ""
          }
        _ => ""
      }
      // 构造 fallback 顺序数组
      let fallback : Array[String] = if remote_fallback_raw.is_empty() {
        ["github", "gitcode"]
      } else {
        let arr = @json.parse(remote_fallback_raw) catch {
          _ => Json::array([])
        }
        match arr {
          Array(a) =>
            a
            .map(fn(v) { v.as_string().unwrap_or("") })
            .filter(fn(s) { !s.is_empty() })
          _ => ["github", "gitcode"]
        }
      }

      if !auto_push {
        // 零回归路径：auto_push=false 时行为与当前字节级一致
        return Ok(@mcp.ToolResult::text(bug_result.stringify()))
      }

      // ===== auto_push=true：立即 flush fallback 逻辑 =====
      let remote_push : Map[String, Json] = Map([])
      let mut github_ok = false

      if fallback.contains("github") {
        // 先检查 github 环境
        let gh_check_res = github_env_check()
        let gh_check = match gh_check_res {
          Ok(j) => j
          Err(e) => {
            let mm : Map[String, Json] = Map([])
            mm.set("ok", Json::boolean(false))
            mm.set("error", Json::string("github_env_check: " + e))
            remote_push.set("github", Json::object(mm))
            Json::object(Map([]))
          }
        }
        let gh_ready = match gh_check {
          Object(m) =>
            match m.get("ready") {
              Some(True) => true
              _ => false
            }
          _ => false
        }
        if !gh_ready {
          let mm : Map[String, Json] = Map([])
          mm.set("ok", Json::boolean(false))
          mm.set(
            "error",
            Json::string("github_env_check: ready=false，跳过 GitHub"),
          )
          remote_push.set("github", Json::object(mm))
        } else {
          let repo = match gh_check {
            Object(m) =>
              match m.get("repo") {
                Some(String(s)) => s
                _ => ""
              }
            _ => ""
          }
          // 入队 GitHub 条目
          let labels : Array[String] = if severity == "critical" {
            ["bug", "priority-critical"]
          } else if severity == "high" {
            ["bug", "priority-high"]
          } else if severity == "medium" {
            ["bug", "priority-medium"]
          } else if severity == "low" {
            ["bug", "priority-low"]
          } else {
            ["bug"]
          }
          let eff_sev = if severity.is_empty() { "medium" } else { severity }
          let append_res = github_queue_append(
            project_dir, bug_id, summary, detail, eff_sev, ts, repo, labels,
          )
          match append_res {
            Err(e) => {
              let mm : Map[String, Json] = Map([])
              mm.set("ok", Json::boolean(false))
              mm.set("error", Json::string("入队失败: " + e))
              remote_push.set("github", Json::object(mm))
            }
            Ok(_) => {
              // 生成 flush_plan
              let plan_res = github_flush_plan(project_dir, 1)
              let curl_cmd = match plan_res {
                Ok(pj) =>
                  match pj {
                    Object(pm) =>
                      match pm.get("plan") {
                        Some(Array(pa)) =>
                          if pa.length() > 0 {
                            match pa[0] {
                              Object(oe) =>
                                match oe.get("curl_command") {
                                  Some(String(s)) => s
                                  _ => ""
                                }
                              _ => ""
                            }
                          } else {
                            ""
                          }
                        _ => ""
                      }
                    _ => ""
                  }
                Err(_) => ""
              }
              if curl_cmd.is_empty() {
                let mm : Map[String, Json] = Map([])
                mm.set("ok", Json::boolean(false))
                mm.set(
                  "error",
                  Json::string("flush_plan 未生成 curl 命令"),
                )
                remote_push.set("github", Json::object(mm))
              } else {
                // 执行 curl（JS target 下，native 返回明确 Err）
                let exec_res = github_execute_single(
                  curl_cmd, project_dir, 15000,
                )
                match exec_res {
                  Ok(exec_json) =>
                    match exec_json {
                      Object(em) => {
                        let ok = match em.get("ok") {
                          Some(True) => true
                          _ => false
                        }
                        if ok {
                          let issue_number = match em.get("issue_number") {
                            Some(Number(n, ..)) => n.to_int()
                            _ => -1
                          }
                          if issue_number > 0 {
                            let _ = github_queue_mark_sent(
                              project_dir,
                              [bug_id],
                              Map([(bug_id, issue_number)]),
                              sent_at=ts,
                            )
                          }
                          github_ok = true
                          let mm : Map[String, Json] = Map([])
                          mm.set("ok", Json::boolean(true))
                          if issue_number > 0 {
                            mm.set(
                              "issue_url",
                              Json::string(
                                "https://github.com/" +
                                repo +
                                "/issues/" +
                                issue_number.to_string(),
                              ),
                            )
                            mm.set(
                              "issue_number",
                              Json::number(issue_number.to_double()),
                            )
                          }
                          remote_push.set("github", Json::object(mm))
                        } else {
                          let mm : Map[String, Json] = Map([])
                          mm.set("ok", Json::boolean(false))
                          let err_msg = match em.get("error") {
                            Some(String(s)) => s
                            _ => "execution failed"
                          }
                          mm.set("error", Json::string(err_msg))
                          remote_push.set("github", Json::object(mm))
                        }
                      }
                      _ => {
                        let mm : Map[String, Json] = Map([])
                        mm.set("ok", Json::boolean(false))
                        mm.set(
                          "error",
                          Json::string("unexpected response shape"),
                        )
                        remote_push.set("github", Json::object(mm))
                      }
                    }
                  Err(e) => {
                    let mm : Map[String, Json] = Map([])
                    mm.set("ok", Json::boolean(false))
                    mm.set("error", Json::string("execute: " + e))
                    remote_push.set("github", Json::object(mm))
                  }
                }
              }
            }
          }
        }
      }

      if !github_ok && fallback.contains("gitcode") {
        let gc_check_res = gitcode_env_check()
        let gc_check = match gc_check_res {
          Ok(j) => j
          Err(e) => {
            let mm : Map[String, Json] = Map([])
            mm.set("ok", Json::boolean(false))
            mm.set("error", Json::string("env_check: " + e))
            remote_push.set("gitcode", Json::object(mm))
            Json::object(Map([]))
          }
        }
        let gc_ready = match gc_check {
          Object(m) =>
            match m.get("ready") {
              Some(True) => true
              _ => false
            }
          _ => false
        }
        if !gc_ready {
          let mm : Map[String, Json] = Map([])
          mm.set("ok", Json::boolean(false))
          mm.set(
            "error",
            Json::string("gitcode_env_check: ready=false，跳过 GitCode"),
          )
          mm.set("fallback_used", Json::boolean(false))
          remote_push.set("gitcode", Json::object(mm))
        } else {
          let pid = match gc_check {
            Object(m) =>
              match m.get("project_id") {
                Some(String(s)) => s
                _ => ""
              }
            _ => ""
          }
          let labels : Array[String] = if severity == "critical" {
            ["bug", "priority-critical"]
          } else if severity == "high" {
            ["bug", "priority-high"]
          } else if severity == "medium" {
            ["bug", "priority-medium"]
          } else if severity == "low" {
            ["bug", "priority-low"]
          } else {
            ["bug"]
          }
          let eff_sev = if severity.is_empty() { "medium" } else { severity }
          let append_res = gitcode_queue_append(
            project_dir, bug_id, summary, detail, eff_sev, ts, pid, labels,
          )
          match append_res {
            Err(e) => {
              let mm : Map[String, Json] = Map([])
              mm.set("ok", Json::boolean(false))
              mm.set("error", Json::string("入队失败: " + e))
              remote_push.set("gitcode", Json::object(mm))
            }
            Ok(_) => {
              let plan_res = gitcode_flush_plan(project_dir, pid, 1)
              let curl_cmd = match plan_res {
                Ok(pj) =>
                  match pj {
                    Object(pm) =>
                      match pm.get("plan") {
                        Some(Array(pa)) =>
                          if pa.length() > 0 {
                            match pa[0] {
                              Object(oe) =>
                                match oe.get("curl_command") {
                                  Some(String(s)) => s
                                  _ => ""
                                }
                              _ => ""
                            }
                          } else {
                            ""
                          }
                        _ => ""
                      }
                    _ => ""
                  }
                Err(_) => ""
              }
              if curl_cmd.is_empty() {
                let mm : Map[String, Json] = Map([])
                mm.set("ok", Json::boolean(false))
                mm.set(
                  "error",
                  Json::string("gitcode_flush_plan 未生成 curl 命令"),
                )
                remote_push.set("gitcode", Json::object(mm))
              } else {
                // 执行 GitCode curl（复用 github_execute_single 的 JS 壳）
                let exec_res = github_execute_single(
                  curl_cmd, project_dir, 15000,
                )
                match exec_res {
                  Ok(exec_json) =>
                    match exec_json {
                      Object(em) => {
                        let ok = match em.get("ok") {
                          Some(True) => true
                          _ => false
                        }
                        if ok {
                          // 解析 GitCode iid
                          let stdout_str = match em.get("stdout") {
                            Some(String(s)) => s
                            _ => ""
                          }
                          let inner = @json.parse(stdout_str.trim().to_owned()) catch {
                            _ => Json::null()
                          }
                          let iid = match inner {
                            Object(im) =>
                              match im.get("iid") {
                                Some(Number(n, ..)) => n.to_int().to_string()
                                _ => ""
                              }
                            _ => ""
                          }
                          if !iid.is_empty() {
                            let _ = gitcode_queue_mark_sent_batch(
                              project_dir,
                              [bug_id],
                              Map([(bug_id, iid)]),
                              sent_at=ts,
                            )
                          }
                          let mm : Map[String, Json] = Map([])
                          mm.set("ok", Json::boolean(true))
                          mm.set("fallback_used", Json::string("gitcode"))
                          if !iid.is_empty() {
                            mm.set(
                              "issue_url",
                              Json::string(
                                "https://gitcode.com/" + pid + "/issues/" + iid,
                              ),
                            )
                            mm.set("issue_iid", Json::string(iid))
                          }
                          remote_push.set("gitcode", Json::object(mm))
                        } else {
                          let mm : Map[String, Json] = Map([])
                          mm.set("ok", Json::boolean(false))
                          let err_msg = match em.get("error") {
                            Some(String(s)) => s
                            _ => "execution failed"
                          }
                          mm.set("error", Json::string(err_msg))
                          mm.set("fallback_used", Json::boolean(false))
                          remote_push.set("gitcode", Json::object(mm))
                        }
                      }
                      _ => {
                        let mm : Map[String, Json] = Map([])
                        mm.set("ok", Json::boolean(false))
                        mm.set(
                          "error",
                          Json::string("unexpected response shape"),
                        )
                        mm.set("fallback_used", Json::boolean(false))
                        remote_push.set("gitcode", Json::object(mm))
                      }
                    }
                  Err(e) => {
                    let mm : Map[String, Json] = Map([])
                    mm.set("ok", Json::boolean(false))
                    mm.set("error", Json::string("execute: " + e))
                    mm.set("fallback_used", Json::boolean(false))
                    remote_push.set("gitcode", Json::object(mm))
                  }
                }
              }
            }
          }
        }
      }

      // 合并 remote_push 到 report_bug 返回
      match bug_result {
        Object(m) => {
          m.set("auto_push", Json::object(remote_push))
          Ok(@mcp.ToolResult::text(Json::object(m).stringify()))
        }
        _ => Ok(@mcp.ToolResult::text(bug_result.stringify()))
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "eval_feedback",
    "反馈收敛（R111，Evaluator-Optimizer schema 蒸馏：Anthropic E/O 模式 + Self-Refine arXiv 2303.17651 + Reflexion arXiv 2303.11366 + zubi.ai 四段式）：把自由文本反馈归一为 Defects/Evidence/Fix/Acceptance 四段式契约 + 确定性 verdict——无缺陷且 acceptance 非空 → pass（optimizer 可收敛）；否则 fail + flags（evidence_missing / fix_missing / section_missing:...）。纯计算只读不写库（决策建议，执行权在调用方；与 plan_revise 反馈修订互补：反馈从叙事升级为可计算契约）。参数：feedback(必填，含 ## Defects / ## Evidence / ## Fix / ## Acceptance 段，各段 - 列表项)、task_id(可选)。返回 { ok, task_id, schema:{defects,evidence,fix,acceptance}, counts, verdict, flags, note }。",
    schema(
      {
        "feedback": string_prop(
          "反馈文本（必填，含 ## Defects / ## Evidence / ## Fix / ## Acceptance 段，各段 - 列表项）",
        ),
        "task_id": string_prop("关联任务 id(可选)"),
      },
      ["feedback"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
      let feedback = get_str(args, "feedback")
      let task_id = get_str(args, "task_id", default="")
      Ok(
        @mcp.ToolResult::text(
          engine.eval_feedback(feedback, task_id~).stringify(),
        ),
      )
    },
  )
  s1 = instrumented_tool(
    s1,
    "bug_list",
    "列出 {project_dir}/memory/bugs.md 里的 bug 条目。**返回是对象不是裸数组**：{bugs:[{id,bug_id,ts,severity,status,summary,detail,task_id?,linked_task_id?,linked_task_status?}], count, path, project_dir, resolved_path, server_cwd, open_with_linked_done, note}（BUG-9：linked_task_status 取自任务库实时状态，open_with_linked_done>0 就是「账本说没修、任务库说修完了」两份账互相矛盾，一次调用即可看见；抬头状态位用 bug_fix（标修好）/ bug_mark_status（改判）改，判据与闭集见 memory/bugs.md「记账规则」）（BUG-74 同族：按 `bl if isinstance(bl,list)` 取会恒得空，看起来像『账本没 bug』）。用于自驱流水线扫描待修复 bug 并认领。**注意：** project_dir 必须是**相对 server 进程 cwd** 的相对路径（拒绝绝对路径/盘符/..）。返回值含 resolved_path（**绝对** + normalize 后的落点）与 server_cwd（server 进程自己的工作目录，同样规范化成正斜杠）——BUG-134：这一句从前是真的悬空（实现回显的是相对 server cwd 的规范化路径，账写进哪本台账从回执本身判不出来），现在两者同批回显，一比就知道有没有写错轨；server_cwd 为空串表示宿主取不到 cwd，此时 resolved_path 退回相对形态，别当绝对落点读。参数：project_dir(必填)。",
    schema(
      {
        "project_dir": string_prop(
          "项目目录（必填，**相对 server 进程 cwd**，拒绝绝对路径/盘符/..）",
        ),
      },
      ["project_dir"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError] {
      let project_dir = get_str(args, "project_dir")
      // BUG-9：读侧把每条 bug 的关联修复单实时状态一并带回（纯逻辑在 bugreport.mbt）
      match
        bug_list_with_links(project_dir, fn(tid) {
          match engine.get_task(tid) {
            Some(t) => t.status_to_string()
            None => ""
          }
        }) {
        Ok(j) => Ok(@mcp.ToolResult::text(j.stringify()))
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "bug_fix",
    "批量把缺陷抬头标成 FIXED，并**同一笔**追加一条点名整批的 `### FIXED(<盖章时间> / BUG-a, BUG-b)` 小记（BUG-9 的控制面正身：账本此前只写不销，「还剩几条没修」只能人肉数）。为什么是一笔而不是两步：memory/bugs.md 的记账规则把「标 FIXED」与「有小记点名」做成互锁（gen_plugins 生成前硬门①②），分两次调用中间就是一本生成器拒绝产出的红账本。返回 {bug_ids, heading_changed, already_fixed, note_written, note_header, path}：**heading_changed=本次真正改抬头的条数、already_fixed=本就 FIXED 只补小记的条数、note_written=false 表示同抬头小记已存在（幂等重跑，不重复写）**；evidence 必填非空——「说修好了但没人写改在哪」正是历史上假 GREEN 的来源；终态之间不互跳（DUPLICATE/FALSE_POSITIVE 要先用 bug_mark_status 回 OPEN）；编号不存在整笔拒绝，不许静默少写一条。时间戳由服务端盖章，调用面没有 ts/now 参数（BUG-33 政策）。project_dir 必须是**相对 server 进程 cwd** 的相对路径（拒绝绝对路径/盘符/..）。参数：project_dir(必填)、bug_ids(必填，编号数组，`9` 与 `BUG-9` 两种写法都收)、evidence(必填非空)。",
    schema(
      {
        "project_dir": string_prop(
          "项目目录（必填，**相对 server 进程 cwd**，拒绝绝对路径/盘符/..）",
        ),
        "bug_ids": array_prop(
          "要标修好的编号数组（必填，如 [\"BUG-9\",\"BUG-30\"]）",
        ),
        "evidence": string_prop(
          "改了哪个真源、哪条锁钉住（必填非空，写进小记正文）",
        ),
      },
      ["project_dir", "bug_ids"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError] {
      let project_dir = get_str(args, "project_dir")
      let bug_ids = get_array(args, "bug_ids").map(fn(v) {
        v.as_string().unwrap_or("")
      })
      let evidence = get_str(args, "evidence")
      match bug_fix(project_dir, bug_ids, evidence~, ts=now_default()) {
        Ok(j) => Ok(@mcp.ToolResult::text(j.stringify()))
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "bug_mark_status",
    "就地改**一条**缺陷的抬头状态（BUG-9 控制面的另一半：改判，不是销账）。返回 {bug_id, id, status, from_status, changed, duplicate_of?, path}：**changed=false 表示目标状态与主编号都没变（幂等 no-op，一个字节都不写）、from_status 是改之前的状态**。状态闭集 = OPEN/FIXED/DUPLICATE/FALSE_POSITIVE（真源 memory/bugs.md「记账规则」，与 gen_plugins 的闭集判据同源）。**FIXED 在这里一律被拒**：只改抬头会绕过「标 FIXED 必须有小记点名」那道硬门，产出 gen_plugins 拒绝生成的红账本，标修好请走 bug_fix。DUPLICATE 必须带 dup_of 且主编号要存在、不是自己、自身不再是 DUPLICATE（链条禁止）；FALSE_POSITIVE 传非空 evidence 时在条目正文追加一行 `- false_positive(<盖章时间>): …` 立据（只追加、不改既有叙述）。写盘面只有一行抬头，叙述面（正文/小记/reports/轮次日志）一律只追加——改掉旧状态不销毁历史。时间戳由服务端盖章，调用面没有 ts/now 参数（BUG-33 政策）。参数：project_dir(必填，相对 cwd)、bug_id(必填)、status(必填，FIXED 会被拒)、dup_of(仅 DUPLICATE 必填)、evidence(仅 FALSE_POSITIVE 可选)。",
    schema(
      {
        "project_dir": string_prop(
          "项目目录（必填，**相对 server 进程 cwd**，拒绝绝对路径/盘符/..）",
        ),
        "bug_id": string_prop(
          "缺陷编号（必填，`9` 与 `BUG-9` 都收）",
        ),
        "status": string_prop(
          "目标状态(必填)：OPEN/FIXED/DUPLICATE/FALSE_POSITIVE；FIXED 一律拒",
        ),
        "dup_of": string_prop(
          "并入的主编号（仅 DUPLICATE 必填，如 BUG-7）",
        ),
        "evidence": string_prop(
          "误报复核依据（仅 FALSE_POSITIVE 可选，非空则追加一行立据）",
        ),
      },
      ["project_dir", "bug_id", "status"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError] {
      let project_dir = get_str(args, "project_dir")
      let bug_id = get_str(args, "bug_id")
      let status = get_str(args, "status")
      let dup_of = get_str(args, "dup_of")
      let evidence = get_str(args, "evidence")
      match
        bug_mark_status(
          project_dir,
          bug_id,
          status,
          dup_of~,
          evidence~,
          ts=now_default(),
        ) {
        Ok(j) => Ok(@mcp.ToolResult::text(j.stringify()))
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "issue_scan",
    "规则驱动源码扫描（打磨收尾引入的自驱能力）：递归收集 {dir} 下 .mbt 文件，用内建 10 条 MoonBit 高危规则逐行匹配（除零/空数组下标/无保护 unwrap/unsafe_get/无保护整除/substring 越界/ignore 丢错/字符串下标/潜在溢出/空集合单例），产出 findings（rule/severity/file/line/code）。降噪（BUG-15）：**整行注释（trim 后以 /// 或 // 起始）不参与匹配**，doc 注释里的散文不再被当成代码命中；**规则表所在文件（issue_scan.mbt 且含 `fn scan_rules(`）整体跳过**，pattern/hint 字面量不再自命中（scanned_files 仍如实计数）。返回 {scanned_files,total_findings,include_tests,by_severity,by_rule,findings}；命中可直接喂给 report_bug（summary='[rule:id] file:line code'）形成扫描→上报→修复闭环；命中仍只是候选，须由调用方读上下文/实跑复核后才是 bug。参数：dir(必填，相对项目子目录如 src)、rules_file(可选，预留外部规则 JSON，当前忽略)、max_findings(可选默认 100，输出上限)、include_tests(可选默认 false：是否扫描 _test/_wbtest 测试文件——默认跳过以降噪、聚焦产品代码)。",
    schema(
      {
        "dir": string_prop(
          "扫描目录（必填，相对路径如 src，拒绝绝对路径/穿越）",
        ),
        "rules_file": string_prop("外部规则 JSON 路径(可选，预留)"),
        "max_findings": int_prop("findings 输出上限(可选，默认 100)"),
        "include_tests": bool_prop(
          "是否扫描测试文件 _test/_wbtest(可选，默认 false 跳过)",
        ),
      },
      ["dir"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError] {
      let dir = get_str(args, "dir")
      let rules_file = get_str(args, "rules_file")
      let max_findings = get_int(args, "max_findings", default=100)
      let include_tests = get_bool(args, "include_tests", default=false)
      match issue_scan(dir, rules_file, max_findings, include_tests~) {
        Ok(j) => Ok(@mcp.ToolResult::text(j.stringify()))
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "output_validate",
    "产出物验证（Did it work? 证据梯 L4 硬门）：按 artifacts 描述的交付产物做确定性验证——文件存在？非空？invariant 成立？外部 run_check 结果 ok？报告不是证据，只有交付产物的实际状态才能证明工作发生了。任一 artifact 失败即 verdict=fail。enforce 闭环：verdict=fail 时调用方可直接 report_bug(publish_task=true) 或 reject 打回。参数：task_id(可选, 用于取 project_dir)、project_dir(可选, 相对 CWD 路径如 .)、artifacts(必填, 数组：{path, contains?, not_contains?, min_chars?} 或 {check_key})、external_results(可选 Json, 外部 run_check 结果字典)、evidence(可选, agent 报告)、require_evidence(可选默认 false, 硬门全过时是否要求 evidence 非空)。",
    schema(
      {
        "task_id": string_prop("任务 id（可选, 用于取项目目录）"),
        "project_dir": string_prop(
          "项目目录（可选, 相对路径如 ., 不传则依 task_id 或 CWD）",
        ),
        "artifacts": array_prop(
          "要验证的交付产物数组（必填）。每项：{path, contains?, not_contains?, min_chars?} 检查文件；或 {check_key} 引用 external_results 中的外部 run_check 结果",
        ),
        "evidence": string_prop(
          "agent 报告字符串（示意层弱证据；硬门全过时可选参考）",
        ),
        "require_evidence": bool_prop(
          "是否要求 evidence 非空（默认 false）。硬门全过但 evidence 空且此为 true → verdict=fail",
        ),
      },
      ["artifacts"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError] {
      let task_id = get_str(args, "task_id")
      let project_dir = get_str(args, "project_dir")
      let artifacts = get_array(args, "artifacts")
      let external_results = match args {
        Object(m) =>
          match m.get("external_results") {
            Some(obj) => obj
            _ => Json::object({})
          }
        _ => Json::object({})
      }
      let evidence = get_str(args, "evidence")
      let require_evidence = get_bool(args, "require_evidence", default=false)
      // project_dir 优先级：显式传 > task_id 拿 > "."
      let workdir = if !project_dir.is_empty() {
        project_dir
      } else if !task_id.is_empty() {
        match engine.get_task(task_id) {
          Some(t) => t.project_dir
          None => "."
        }
      } else {
        "."
      }
      match
        output_validate(
          workdir,
          artifacts,
          external_results,
          evidence,
          require_evidence~,
        ) {
        Ok(j) => Ok(@mcp.ToolResult::text(j.stringify()))
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )

  // ===== project_standards：AI 项目开发规范（默认内置 + FIST 专项）=====
  s1 = instrumented_tool(
    s1,
    "project_standards",
    "AI 项目开发规范（默认内置 5 条 + FIST 专项 5 条）。纯计算、零依赖，只**下发清单**、不扫描文件也不修改文档（要扫描请用 issue_scan / check_doc_surface.py）。规范性正文真源 = AI-DEVELOPMENT-STANDARD.md，本工具是它的机器投影。基线：文档即实现、一源四态、确定性优先、增量零回归、自我迭代；加上 FIST 强制：用自身能力迭代（call_log/report_bug/laya/Omega 四开关可量化）/四态必须对齐/证据梯至少 L4/重任务先拆 DAG/工具命名即文档。附四态验收 checklist 7 项（cl1-mcp-exists 到 cl7-plugin-forms-sync），可直接喂 output_validate 当验收门禁。参数：project_type（可选默认 moontbit_mcp，给针对性上下文）、include_checklist（可选默认 true，是否附带验收 checklist）。",
    schema(
      {
        "project_type": string_prop(
          "项目类型标签（可选，默认 moontbit_mcp）。用于给规范清单打上下文标注",
        ),
        "include_checklist": bool_prop(
          "是否附带四态验收 checklist 7 项（默认 true，cl1→cl7）。是新功能上线的硬门",
        ),
      },
      [],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError] {
      let ptype = get_str(args, "project_type")
      let icl = get_bool(args, "include_checklist", default=true)
      let ptype2 = if ptype.is_empty() { "moontbit_mcp" } else { ptype }
      Ok(@mcp.ToolResult::text(project_standards(ptype2, icl).stringify()))
    },
  )

  // ===== 模型路由 + 外部执行器（合并自兄弟项目 fist-model-router 与 FIST 的 aider/atomcode 执行器）=====
  s1 = instrumented_tool(
    s1,
    "model_route",
    "模型路由决策（免费优先 + 达阈值切付费 + 每模型 5h 滚动窗口）。纯决策来自 src/router（确定性、可单测），用量状态落盘 {project_dir}/memory/model-router-{ns}.json 跨进程复现。**时间戳由服务端盖章，不接受调用方注入 now**（BUG-33 政策）；两池皆耗尽时显式 ok=false，绝不静默改用别的模型。**只问不消耗（不给 record_model）＝零副作用**：不记账、不推进轮询游标、不给模型盖窗口起点，返回 persisted=false 与 mode=query-only（BUG-62：旧实现连查询也落盘，两次相同查询会换模型、5h 窗口没人使用就开始倒计时）。唯一例外是**只播种定义不播种用量**：显式给了 config_json 的池定义时，在决策之前把池形状写进状态文件（否则 executor_run 自动记账那一笔不带 config，只能拿默认池，自定义模型名走「未在任何池中配置」，配额形同虚设）。namespace 只允许字母/数字/_/-（空=default）：写不进盘的 ns 会被显式拒绝，不再静默失去配额约束（BUG-64）。参数：project_dir(必填，相对路径)、namespace(可选默认 default)、record_model(可选：给模型名则先记账再决策，用于执行器真实用完一次)、config_json(可选：RouterConfig 的 JSON **文本或对象均可**（BUG-63：给对象时按其文本走同一条校验，不再被静默当成没传），覆盖池定义；同名模型的已用配额保留；**非法 JSON 直接报错，不静默回落默认池**)（注：本工具不含任何密钥，凭据只来自 server 进程环境变量）。",
    schema(
      {
        "project_dir": string_prop(
          "项目目录（必填，相对 server 进程 cwd，拒绝绝对路径/盘符/..）",
        ),
        "namespace": string_prop(
          "命名空间（可选，默认 default）——每个 ns 一份独立配额账",
        ),
        "record_model": string_prop(
          "可选：要记账的模型名（须已在池内）。给了才 used+1、才落盘（persisted=true）；留空=只问不消耗，一个字节都不动状态文件（BUG-62 成对锁 mo_9 逐字节自证）",
        ),
        "config_json": string_prop(
          "RouterConfig 的 JSON（文本或对象均可，BUG-63），如 {\"window_seconds\":18000,\"threshold_pct\":95,\"free_pool\":[{\"name\":\"x\",\"limit\":10}],\"paid_pool\":[]}；非法字段回落默认并写进 warnings",
        ),
      },
      ["project_dir"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError] {
      let pd = get_str(args, "project_dir")
      let ns = get_str(args, "namespace")
      let rec = get_str(args, "record_model")
      let cj = get_json_text(args, "config_json")
      let cfgj = match mr_parse_config(cj) {
        Err(e) => return Err(@mcp_types.ToolError(e))
        Ok(j) => j
      }
      let ns2 = if ns.is_empty() { "default" } else { ns }
      match model_route_impl(pd, ns=ns2, record_model=rec, config=cfgj) {
        Ok(j) => Ok(@mcp.ToolResult::text(j.stringify()))
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "model_router_status",
    "查当前模型路由状态（每模型 used/limit/占比/是否超阈值 + 当前档位 + 切换次数 + 状态文件路径与是否存在）。只读：不改配额不落盘。参数：project_dir(必填)、namespace(可选默认 default)。",
    schema(
      {
        "project_dir": string_prop(
          "项目目录（必填，相对 server 进程 cwd）",
        ),
        "namespace": string_prop("命名空间（可选，默认 default）"),
      },
      ["project_dir"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError] {
      let pd = get_str(args, "project_dir")
      let ns = get_str(args, "namespace")
      let ns2 = if ns.is_empty() { "default" } else { ns }
      match model_router_status_impl(pd, ns=ns2) {
        Ok(j) => Ok(@mcp.ToolResult::text(j.stringify()))
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "model_router_reset",
    "清模型路由窗口：把所有模型的 used 与 window_start 归零（等价于'这 5 小时重新开始'）。hard=true 时连当前档位/轮询游标/切换计数一起复位。参数：project_dir(必填)、namespace(可选)、hard(可选默认 false)。",
    schema(
      {
        "project_dir": string_prop(
          "项目目录（必填，相对 server 进程 cwd）",
        ),
        "namespace": string_prop("命名空间（可选，默认 default）"),
        "hard": bool_prop(
          "可选：true 时连同档位/游标/切换计数一起复位（默认只清窗口）",
        ),
      },
      ["project_dir"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError] {
      let pd = get_str(args, "project_dir")
      let ns = get_str(args, "namespace")
      let hard = get_bool(args, "hard", default=false)
      let ns2 = if ns.is_empty() { "default" } else { ns }
      match model_router_reset_impl(pd, ns=ns2, hard~) {
        Ok(j) => Ok(@mcp.ToolResult::text(j.stringify()))
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "executor_run",
    "把任务交给外部编码执行器真跑（宿主命令能力，默认收紧）：执行器名**只能**是已登记集合 aider | atomcode，argv 形状由 src/executor/cli_argv.mbt 固定（不经过 shell，提示词里的 ; $() 反引号都只是字面量），可执行文件名由登记表推导——调用方无法借本工具注入任意命令。model 留空时先向 model_route 要一个模型并记账（路由↔执行器接线点）；无可用模型直接失败不猜模型。结果 ok=false 时附可诊断 error/hint，绝不静默成功。参数：project_dir(必填)、executor(必填 aider|atomcode)、prompt(必填，非空且不含 NUL)、model(可选，留空则路由决定)、namespace(可选)、timeout_ms(可选默认 180000)、dry_run(可选默认 false：只回显将执行的 argv、一个进程都不起，先审后跑)（注：时间戳由服务端盖章）。执行需 js/node 运行时；native 构建返回明确拒绝。",
    schema(
      {
        "project_dir": string_prop(
          "项目目录（必填，相对 server 进程 cwd；作为执行器工作目录）",
        ),
        "executor": string_prop(
          "执行器名（必填，只接受 aider | atomcode）",
        ),
        "prompt": string_prop(
          "任务描述（必填，作为 --message/-p 的字面量参数）",
        ),
        "model": string_prop(
          "可选：指定模型；留空则由模型路由器决定并记账",
        ),
        "namespace": string_prop(
          "命名空间（可选，默认 default）——路由配额按 ns 记",
        ),
        "timeout_ms": int_prop(
          "可选：子进程超时毫秒（默认 180000）",
        ),
        "dry_run": bool_prop(
          "可选（默认 false）：true 时只回显将执行的 argv，不启动任何外部进程——先审后跑",
        ),
      },
      ["project_dir", "executor", "prompt"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError] {
      let pd = get_str(args, "project_dir")
      let ex = get_str(args, "executor")
      let prompt = get_str(args, "prompt")
      let model = get_str(args, "model")
      let ns = get_str(args, "namespace")
      let ns2 = if ns.is_empty() { "default" } else { ns }
      let tm = match args {
        Json::Object(m) =>
          match m.get("timeout_ms") {
            Some(Json::Number(n, ..)) => {
              let v = n.to_int()
              if v > 0 {
                v
              } else {
                180000
              }
            }
            _ => 180000
          }
        _ => 180000
      }
      let j = executor_run_impl(
        pd,
        ns=ns2,
        executor=ex,
        prompt~,
        model~,
        timeout_ms=tm,
        dry_run=get_bool(args, "dry_run", default=false),
      )
      Ok(@mcp.ToolResult::text(j.stringify()))
    },
  )

  // ===== github_sync 三件套 =====
  s1 = instrumented_tool(
    s1,
    "github_queue_status",
    "查看待同步 GitHub issue 队列状态。返回 {total, pending, sent, oldest_pending_ts, by_severity, pending_list, path}。纯计算读 JSONL 队列，不碰网络。**两栏不许混读**（BUG-74 同族，实测撞过）：total=0 只说明队列文件为空——`github_env_check` 的 enabled=false 时压根不会有入队记录，此时『没有待同步』读起来像『没有 bug 待上报』，是两回事；判断『能不能自动上报』请看 github_env_check 的 enabled/repo_set/token_present/ready 四元组。参数：project_dir(必填)。",
    schema({ "project_dir": string_prop("项目目录（必填）") }, [
      "project_dir",
    ]),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError] {
      let project_dir = get_str(args, "project_dir")
      match github_queue_status(project_dir) {
        Ok(j) => Ok(@mcp.ToolResult::text(j.stringify()))
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "github_flush_plan",
    "生成 GitHub issue 同步计划——为每条 pending bug 生成一条 curl 命令（含 FIST_GITHUB_TOKEN 占位符）。不执行任何网络调用，外部拿到后手动/脚本执行 curl，成功后调 github_queue_mark_sent 标记。参数：project_dir(必填)、limit(可选默认20)。",
    schema(
      {
        "project_dir": string_prop("项目目录（必填）"),
        "limit": int_prop("输出上限(可选默认20)"),
      },
      ["project_dir"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError] {
      let project_dir = get_str(args, "project_dir")
      let limit = get_int(args, "limit", default=20)
      match github_flush_plan(project_dir, limit) {
        Ok(j) => Ok(@mcp.ToolResult::text(j.stringify()))
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "github_queue_mark_sent",
    "标记一批 bug_id 已同步至 GitHub issue（写入 sent_at + github_issue_number）。curl 执行成功后调此工具回写队列，幂等安全。参数：project_dir(必填)、bug_ids(必填数组)、sent_at(可选，缺省自动回退)、issue_numbers(可选 JSON 对象)。",
    schema(
      {
        "project_dir": string_prop("项目目录（必填）"),
        "bug_ids": array_prop("已同步的 bug_id 数组（必填）"),
        "sent_at": string_prop("同步时间戳 ISO 格式（可选）"),
        "issue_numbers": string_prop(
          "bug_id->issue_number 映射 JSON 对象（可选）",
        ),
      },
      ["project_dir", "bug_ids"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError] {
      let project_dir = get_str(args, "project_dir")
      let sent_at = get_str(args, "sent_at", default="")
      let ids_arr = get_array(args, "bug_ids")
      let bug_ids = ids_arr.map(fn(v) { v.as_string().unwrap_or("") })
      let issue_nums_raw = get_str(args, "issue_numbers")
      let issue_numbers = if issue_nums_raw.is_empty() {
        Map([])
      } else {
        let m = Map([])
        let j = @json.parse(issue_nums_raw) catch { _ => Json::object(Map([])) }
        match j {
          Object(om) => {
            for (k, v) in om {
              match v {
                Number(n, ..) => m.set(k, n.to_int())
                _ => ()
              }
            }
            m
          }
          _ => Map([])
        }
      }
      match
        github_queue_mark_sent(project_dir, bug_ids, issue_numbers, sent_at~) {
        Ok(j) => Ok(@mcp.ToolResult::text(j.stringify()))
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "github_env_check",
    "检查 GitHub issue 同步的环境变量配置状态——读 FIST_GITHUB_ENABLED / FIST_GITHUB_REPO / FIST_GITHUB_TOKEN，返回 enabled/repo/token_present/ready 四元组。纯计算只读环境变量，不碰网络。外部 AI 开发前先查此工具，确认能否自动上报 bug。",
    schema({}, []),
    async fn(_args : Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError] {
      let enabled = match @env.get_env_var("FIST_GITHUB_ENABLED") {
        Some(v) => v == "true" || v == "1" || v == "yes"
        None => false
      }
      let repo = match @env.get_env_var("FIST_GITHUB_REPO") {
        Some(v) => v
        None => ""
      }
      let token_present = match @env.get_env_var("FIST_GITHUB_TOKEN") {
        Some(v) => !v.is_empty()
        None => false
      }
      let ready = enabled && !repo.is_empty() && token_present
      let mm : Map[String, Json] = Map([])
      mm.set("enabled", Json::boolean(enabled))
      mm.set("repo", Json::string(repo))
      mm.set("repo_set", Json::boolean(!repo.is_empty()))
      mm.set("token_present", Json::boolean(token_present))
      mm.set("ready", Json::boolean(ready))
      let hints : Array[String] = []
      if !enabled {
        hints.push("set FIST_GITHUB_ENABLED=true to enable auto-sync")
      }
      if repo.is_empty() {
        hints.push("set FIST_GITHUB_REPO=owner/repo")
      }
      if !token_present {
        hints.push("set FIST_GITHUB_TOKEN=ghp_xxx for curl execution")
      }
      let hints_json = hints.map(fn(s) { Json::string(s) })
      mm.set("hints", Json::array(hints_json))
      Ok(@mcp.ToolResult::text(Json::object(mm).stringify()))
    },
  )

  // ===== github_sync 执行层：4 个新工具 =====
  s1 = instrumented_tool(
    s1,
    "github_flush_execute",
    "一键执行 github_flush_plan 生成的 curl 命令，直接在队列上发 GitHub issue。硬门控——force 必须显式为 true 才执行，防误操作。JS target 下真实执行 curl；native target 返回跳过提示。成功后自动回写 github_queue_mark_sent（从 curl 返回解析 issue.number）。参数：project_dir(必填)、force(必填=true 才执行)、limit(可选默认 10)、timeout_ms(可选默认 15000)。",
    schema(
      {
        "project_dir": string_prop("项目目录（必填）"),
        "force": bool_prop(
          "硬门控——必须 true 才执行 curl，防误操作（必填）",
        ),
        "limit": int_prop(
          "每次最多执行几条 pending（可选，默认 10）",
        ),
        "timeout_ms": int_prop(
          "单条 curl 超时 ms（可选，默认 15000）",
        ),
      },
      ["project_dir", "force"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError] {
      let project_dir = get_str(args, "project_dir")
      let force = get_bool(args, "force", default=false)
      let limit = get_int(args, "limit", default=10)
      let timeout_ms = get_int(args, "timeout_ms", default=15000)
      if !force {
        return Err(
          @mcp_types.ToolError(
            "github_flush_execute 需要显式 force=true 才执行（硬门控，防误操作）",
          ),
        )
      }
      let plan_res = github_flush_plan(project_dir, limit)
      let plan_json = match plan_res {
        Ok(j) => j
        Err(e) => return Err(@mcp_types.ToolError(e))
      }
      let plan_obj = match plan_json {
        Object(m) => m
        _ => return Err(@mcp_types.ToolError("flush_plan 返回非对象"))
      }
      let plan_arr = match plan_obj.get("plan") {
        Some(Array(a)) => a
        _ => []
      }
      if plan_arr.length() == 0 {
        let mm : Map[String, Json] = Map([])
        mm.set("executed", Json::boolean(false))
        mm.set(
          "message",
          Json::string("队列里没有 pending 的 bug——无需 flush"),
        )
        return Ok(@mcp.ToolResult::text(Json::object(mm).stringify()))
      }
      let bug_ids : Array[String] = []
      let curl_cmds : Array[String] = []
      for entry in plan_arr {
        match entry {
          Object(m) => {
            let bid = match m.get("bug_id") {
              Some(String(s)) => s
              _ => ""
            }
            let cmd = match m.get("curl_command") {
              Some(String(s)) => s
              _ => ""
            }
            if !bid.is_empty() && !cmd.is_empty() {
              bug_ids.push(bid)
              curl_cmds.push(cmd)
            }
          }
          _ => ()
        }
      }
      let batch_res = github_execute_batch(curl_cmds, project_dir, timeout_ms)
      let batch_json = match batch_res {
        Ok(j) => j
        Err(e) => {
          let mm : Map[String, Json] = Map([])
          mm.set("executed", Json::boolean(false))
          mm.set("message", Json::string(e))
          mm.set(
            "hint",
            Json::string(
              "native target 没有 node child_process 能力，请在 js target 运行 server",
            ),
          )
          return Ok(@mcp.ToolResult::text(Json::object(mm).stringify()))
        }
      }
      let batch_obj = match batch_json {
        Object(m) => m
        _ => return Err(@mcp_types.ToolError("batch 返回非对象"))
      }
      let total = match batch_obj.get("total") {
        Some(Number(n, ..)) => n.to_int()
        _ => 0
      }
      let succeeded = match batch_obj.get("succeeded") {
        Some(Number(n, ..)) => n.to_int()
        _ => 0
      }
      let results_arr = match batch_obj.get("results") {
        Some(Array(a)) => a
        _ => []
      }
      // 为每条成功的 curl 解析 issue number
      let issue_numbers : Map[String, Int] = Map([])
      let sent_at_list : Array[String] = []
      let sent_at_now = "flushed-by-github_flush_execute"
      let mut i1 = 0
      while i1 < plan_arr.length() {
        if i1 < results_arr.length() {
          let res_json = results_arr[i1]
          let bug_id = bug_ids[i1]
          let ok_bool = match res_json {
            Object(m) =>
              match m.get("ok") {
                Some(True) => true
                _ => false
              }
            _ => false
          }
          if ok_bool {
            let stdout_str = match res_json {
              Object(m) =>
                match m.get("stdout") {
                  Some(String(s)) => s
                  _ => ""
                }
              _ => ""
            }
            let inner = @json.parse(stdout_str.trim().to_owned()) catch {
              _ => Json::null()
            }
            let num = match inner {
              Object(im) =>
                match im.get("number") {
                  Some(Number(n, ..)) => n.to_int()
                  _ => -1
                }
              _ => -1
            }
            if num > 0 {
              issue_numbers.set(bug_id, num)
            }
            sent_at_list.push(bug_id)
          }
        }
        i1 = i1 + 1
      }
      let mark_res = github_queue_mark_sent(
        project_dir,
        sent_at_list,
        issue_numbers,
        sent_at=sent_at_now,
      )
      let mark_json = match mark_res {
        Ok(j) => j
        Err(_) => Json::object(Map([]))
      }
      // 组装返回
      let result_obj : Array[Json] = []
      let mut i2 = 0
      while i2 < plan_arr.length() {
        let pm : Map[String, Json] = Map([])
        let bid2 = bug_ids[i2]
        pm.set("bug_id", Json::string(bid2))
        match issue_numbers.get(bid2) {
          Some(n) => pm.set("issue_number", Json::number(n.to_double()))
          None => ()
        }
        let res_json2 = if i2 < results_arr.length() {
          results_arr[i2]
        } else {
          Json::object(Map([]))
        }
        match res_json2 {
          Object(rm) => {
            match rm.get("ok") {
              Some(True) => pm.set("ok", Json::boolean(true))
              Some(False) => pm.set("ok", Json::boolean(false))
              _ => pm.set("ok", Json::boolean(false))
            }
            match rm.get("error") {
              Some(String(s)) => pm.set("error", Json::string(s))
              _ => ()
            }
          }
          _ => pm.set("ok", Json::boolean(false))
        }
        result_obj.push(Json::object(pm))
        i2 = i2 + 1
      }
      let mm : Map[String, Json] = Map([])
      mm.set("executed", Json::boolean(true))
      mm.set("total", Json::number(total.to_double()))
      mm.set("succeeded", Json::number(succeeded.to_double()))
      mm.set("failed", Json::number((total - succeeded).to_double()))
      mm.set("marked_sent", mark_json)
      mm.set("results", Json::array(result_obj))
      Ok(@mcp.ToolResult::text(Json::object(mm).stringify()))
    },
  )
  s1 = instrumented_tool(
    s1,
    "github_issue_close",
    "根据 bug_id -> issue_number 映射，批量关闭 GitHub issue（PUT state=closed）。硬门控——force 必须为 true。通常在 FIST 任务归档/完成后触发。参数：project_dir(必填)、force(必填=true)、issue_numbers_json(必填 bug_id->issue_number 的 JSON 对象)、timeout_ms(可选默认 15000)。",
    schema(
      {
        "project_dir": string_prop("项目目录（必填）"),
        "force": bool_prop(
          "硬门控——必须 true 才执行 close（必填）",
        ),
        "issue_numbers_json": string_prop(
          "bug_id->issue_number 映射的 JSON 对象字符串（必填）",
        ),
        "timeout_ms": int_prop(
          "单条 curl 超时 ms（可选，默认 15000）",
        ),
      },
      ["project_dir", "force", "issue_numbers_json"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError] {
      let project_dir = get_str(args, "project_dir")
      let force = get_bool(args, "force", default=false)
      let timeout_ms = get_int(args, "timeout_ms", default=15000)
      let issue_nums_raw = get_str(args, "issue_numbers_json")
      if !force {
        return Err(
          @mcp_types.ToolError(
            "github_issue_close 需要显式 force=true 才执行",
          ),
        )
      }
      let issue_numbers : Map[String, Int] = Map([])
      let j = @json.parse(issue_nums_raw) catch { _ => Json::object(Map([])) }
      match j {
        Object(om) =>
          for (k, v) in om {
            match v {
              Number(n, ..) => issue_numbers.set(k, n.to_int())
              _ => ()
            }
          }
        _ => ()
      }
      if issue_numbers.length() == 0 {
        return Err(
          @mcp_types.ToolError("issue_numbers_json 为空或格式错误"),
        )
      }
      let plan_res = github_build_close_plan(project_dir, issue_numbers)
      let plan_json = match plan_res {
        Ok(j) => j
        Err(e) => return Err(@mcp_types.ToolError(e))
      }
      let plan_obj = match plan_json {
        Object(m) => m
        _ => return Err(@mcp_types.ToolError("close plan 返回非对象"))
      }
      let plan_arr = match plan_obj.get("plan") {
        Some(Array(a)) => a
        _ => []
      }
      if plan_arr.length() == 0 {
        let mm : Map[String, Json] = Map([])
        mm.set("executed", Json::boolean(false))
        mm.set(
          "message",
          Json::string(
            "没有可以 close 的 issue（repo 缺失或 issue_number 无效）",
          ),
        )
        return Ok(@mcp.ToolResult::text(Json::object(mm).stringify()))
      }
      let curl_cmds : Array[String] = []
      for entry in plan_arr {
        match entry {
          Object(m) => {
            let cmd = match m.get("curl_command") {
              Some(String(s)) => s
              _ => ""
            }
            if !cmd.is_empty() {
              curl_cmds.push(cmd)
            }
          }
          _ => ()
        }
      }
      let batch_res = github_execute_batch(curl_cmds, project_dir, timeout_ms)
      let mm : Map[String, Json] = Map([])
      mm.set("executed", Json::boolean(true))
      match batch_res {
        Err(e) => {
          mm.set("executed", Json::boolean(false))
          mm.set("message", Json::string(e))
        }
        Ok(br) => {
          let total = match br {
            Object(m) =>
              match m.get("total") {
                Some(Number(n, ..)) => n.to_int()
                _ => 0
              }
            _ => 0
          }
          let succeeded = match br {
            Object(m) =>
              match m.get("succeeded") {
                Some(Number(n, ..)) => n.to_int()
                _ => 0
              }
            _ => 0
          }
          mm.set("total", Json::number(total.to_double()))
          mm.set("succeeded", Json::number(succeeded.to_double()))
          mm.set("failed", Json::number((total - succeeded).to_double()))
        }
      }
      Ok(@mcp.ToolResult::text(Json::object(mm).stringify()))
    },
  )
  s1 = instrumented_tool(
    s1,
    "github_issue_comment",
    "给指定 bug_id 对应的 GitHub issue 追加评论（POST comments API）。硬门控——force 必须为 true。先从队列找到 bug_id 对应的 github_issue_number（bug 必须已经 flush 成功过），再执行 comment curl。参数：project_dir(必填)、force(必填=true)、bug_id(必填)、comment_body(必填)、timeout_ms(可选默认 15000)。",
    schema(
      {
        "project_dir": string_prop("项目目录（必填）"),
        "force": bool_prop("硬门控——必须 true 才执行（必填）"),
        "bug_id": string_prop(
          "bug_id（必填，队列里必须已 flush 过）",
        ),
        "comment_body": string_prop("评论正文（必填）"),
        "timeout_ms": int_prop("curl 超时 ms（可选，默认 15000）"),
      },
      ["project_dir", "force", "bug_id", "comment_body"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError] {
      let project_dir = get_str(args, "project_dir")
      let force = get_bool(args, "force", default=false)
      let bug_id = get_str(args, "bug_id")
      let comment_body = get_str(args, "comment_body")
      let timeout_ms = get_int(args, "timeout_ms", default=15000)
      if !force {
        return Err(
          @mcp_types.ToolError(
            "github_issue_comment 需要显式 force=true 才执行",
          ),
        )
      }
      let plan_res = github_build_comment_plan(
        project_dir, bug_id, comment_body,
      )
      let plan_json = match plan_res {
        Ok(j) => j
        Err(e) => return Err(@mcp_types.ToolError(e))
      }
      let curl_cmd = match plan_json {
        Object(m) =>
          match m.get("curl_command") {
            Some(String(s)) => s
            _ => ""
          }
        _ => ""
      }
      if curl_cmd.is_empty() {
        return Err(@mcp_types.ToolError("comment plan 未生成 curl 命令"))
      }
      let exec_res = github_execute_single(curl_cmd, project_dir, timeout_ms)
      let mm : Map[String, Json] = Map([])
      mm.set("executed", Json::boolean(true))
      mm.set("bug_id", Json::string(bug_id))
      match plan_json {
        Object(m) =>
          match m.get("issue_number") {
            Some(Number(n, ..)) => mm.set("issue_number", Json::number(n))
            _ => mm.set("issue_number", Json::number(-1.0))
          }
        _ => mm.set("issue_number", Json::number(-1.0))
      }
      match exec_res {
        Ok(j) => mm.set("execution", j)
        Err(e) => mm.set("execution_error", Json::string(e))
      }
      Ok(@mcp.ToolResult::text(Json::object(mm).stringify()))
    },
  )
  s1 = instrumented_tool(
    s1,
    "github_issue_webhook_parse",
    "解析 GitHub issue comment webhook payload，提取 @fist-bot 指令。纯计算正则匹配，零 LLM、零网络。支持指令：'@fist-bot reopen <task_id>' / '@fist-bot challenge' / '@fist-bot close' / '@fist-bot blocked <reason>'。返回结构化 action 供 FIST 闭环消费。参数：payload(必填 webhook 原始 JSON 字符串)。",
    schema(
      {
        "payload": string_prop(
          "GitHub issue comment webhook 原始 JSON 字符串（必填）",
        ),
      },
      ["payload"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError] {
      let payload = get_str(args, "payload")
      match github_webhook_parse(payload) {
        Ok(j) => Ok(@mcp.ToolResult::text(j.stringify()))
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )

  // ===== gitcode 四件套：GitCode issue 同步（fallback 通道）=====
  s1 = instrumented_tool(
    s1,
    "gitcode_queue_status",
    "查看待同步 GitCode issue 队列状态。返回 {total, pending, sent, oldest_pending_ts, by_severity, pending_list, path}。纯计算读 JSONL 队列，不碰网络。**两栏不许混读**（同 github_queue_status 的 BUG-74 口径：total=0 ≠ 没有 bug 待上报——GitCode 是 GitHub 的 fallback，入队需显式带 gitcode_project_id）。可选 gitcode_project_id：非空时只统计该 project_id 的条目。参数：project_dir(必填)、gitcode_project_id(可选数字字符串)。",
    schema(
      {
        "project_dir": string_prop("项目目录（必填）"),
        "gitcode_project_id": string_prop(
          "GitCode 项目 ID（可选，非空时只统计该项目）",
        ),
      },
      ["project_dir"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError] {
      let project_dir = get_str(args, "project_dir")
      let pid = get_str(args, "gitcode_project_id")
      match gitcode_queue_status(project_dir, pid) {
        Ok(j) => Ok(@mcp.ToolResult::text(j.stringify()))
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "gitcode_flush_plan",
    "生成 GitCode issue 同步计划——为每条 pending bug 生成一条 curl 命令（PRIVATE-TOKEN: ${FIST_GITCODE_TOKEN}，URL: https://gitcode.com/api/v4/projects/{id}/issues）。不执行任何网络调用，外部拿到后手动/脚本执行 curl，成功后调 gitcode_queue_mark_sent 标记。参数：project_dir(必填)、gitcode_project_id(必填数字字符串)、limit(可选默认20)。",
    schema(
      {
        "project_dir": string_prop("项目目录（必填）"),
        "gitcode_project_id": string_prop(
          "GitCode 项目 ID（必填，格式如 12345）",
        ),
        "limit": int_prop("输出上限(可选默认20)"),
      },
      ["project_dir", "gitcode_project_id"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError] {
      let project_dir = get_str(args, "project_dir")
      let pid = get_str(args, "gitcode_project_id")
      let limit = get_int(args, "limit", default=20)
      match gitcode_flush_plan(project_dir, pid, limit) {
        Ok(j) => Ok(@mcp.ToolResult::text(j.stringify()))
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "gitcode_queue_mark_sent",
    "标记一批 bug_id 已同步至 GitCode issue（写入 sent_at + gitcode_issue_iid）。curl 执行成功后调此工具回写队列，幂等安全。参数：project_dir(必填)、bug_ids(必填数组)、sent_at(可选，缺省自动回退)、gitcode_issue_iids(可选 JSON 对象：bug_id → iid 映射)。",
    schema(
      {
        "project_dir": string_prop("项目目录（必填）"),
        "bug_ids": array_prop("已同步的 bug_id 数组（必填）"),
        "sent_at": string_prop("同步时间戳 ISO 格式（可选）"),
        "gitcode_issue_iids": string_prop(
          "bug_id→gitcode_issue_iid 映射 JSON 对象（可选）",
        ),
      },
      ["project_dir", "bug_ids"],
    ),
    async fn(args : Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError] {
      let project_dir = get_str(args, "project_dir")
      let sent_at = get_str(args, "sent_at", default="")
      let ids_arr = get_array(args, "bug_ids")
      let bug_ids = ids_arr.map(fn(v) { v.as_string().unwrap_or("") })
      let iids_raw = get_str(args, "gitcode_issue_iids")
      let iids_map = if iids_raw.is_empty() {
        Map([])
      } else {
        let m : Map[String, String] = Map([])
        let j = @json.parse(iids_raw) catch { _ => Json::object(Map([])) }
        match j {
          Object(om) => {
            for (k, v) in om {
              match v {
                String(s) => m.set(k, s)
                Number(n, ..) => m.set(k, n.to_int().to_string())
                _ => ()
              }
            }
            m
          }
          _ => Map([])
        }
      }
      match
        gitcode_queue_mark_sent_batch(project_dir, bug_ids, iids_map, sent_at~) {
        Ok(j) => Ok(@mcp.ToolResult::text(j.stringify()))
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )
  s1 = instrumented_tool(
    s1,
    "gitcode_env_check",
    "检查 GitCode issue 同步的环境变量配置状态——读 FIST_GITCODE_ENABLED / FIST_GITCODE_PROJECT_ID / FIST_GITCODE_TOKEN，返回 enabled/project_id_set/token_present/ready/hints 五元组。纯计算只读环境变量，不碰网络。外部 AI 开发前先查此工具，确认能否自动上报 bug（GitCode 是 GitHub 的 fallback 通道）。",
    schema({}, []),
    async fn(_args : Json) -> Result[@mcp.ToolResult, @mcp_types.MCPError] {
      match gitcode_env_check() {
        Ok(j) => Ok(@mcp.ToolResult::text(j.stringify()))
        Err(e) => Err(@mcp_types.ToolError(e))
      }
    },
  )

  // 默认 stdio 传输（MCP 标准模式）。
  run_stdio_target(s1)
}

///|
/// 暴露单一真源 project_version（cli/外部模块只读版本号入口）。
/// 不直接暴露 pub let 是因为 MoonBit 包内 let 默认私有；
/// BUG-16 回归测试仍锁 src/server/server.mbt L560 的字面量，不改它。
pub fn get_version() -> String {
  project_version
}
