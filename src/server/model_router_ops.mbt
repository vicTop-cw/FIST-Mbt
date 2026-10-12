/// model_router_ops.mbt —— 模型路由的服务端编排（只做 IO：落盘 + 时钟盖章 + spawn 执行器）
///
/// 分层理由（一源四态 r2/r3）：纯决策与状态 schema 都在 `src/router`（可单测、零 IO），
/// argv 构造在 `src/executor`（可审、零 IO），本文件只做三件必须 IO 的事：
///   1. 状态落盘 `{project_dir}/memory/model-router-{ns}.json`（跨进程可复现，不靠内存）
///   2. 时间戳由服务端 `now_default()` 盖章（BUG-33：不接受调用方注入 now）
///   3. spawn 外部执行器（复用 run_check_external 的 js 原语；native 明确拒绝）
///
/// 密钥：本文件不读 .env、不打印任何 key；aider/atomcode 的凭据只来自 server 进程环境变量。

///|
/// 命名空间校验（BUG-64）：复用仓库唯一真源 `MultiStore::safe_ns`。
/// 旧实现直接把 ns 拼进文件名 ⇒ `a/b` 这类 ns 写不进盘（`persisted=false`）却仍回 `ok=true`，
/// 配额上限形同虚设；大小写不敏感文件系统上两个 ns 还会共用一本账。
/// 空 ns 按既有约定视为 `default`（零回归），其余非法一律显式拒绝。
fn mr_check_ns(ns : String) -> String? {
  let eff = if ns.is_empty() { "default" } else { ns }
  match @store.MultiStore::safe_ns(eff) {
    Some(_) => None
    None =>
      Some(
        "非法 namespace '\{ns}'：只允许字母/数字/_/-（含 / \\ . 空格 都会造成静默丢账或大小写串账，已拒绝）",
      )
  }
}

///|
/// 状态文件路径（project_dir 必须相对且不含穿越；沿用 bugreport 的同一条校验）
fn mr_state_path(project_dir : String, ns : String) -> String {
  let safe_ns = if ns.is_empty() { "default" } else { ns }
  project_dir + "/memory/model-router-" + safe_ns + ".json"
}

///|
/// 读状态；文件不存在/读失败/非法 JSON 一律回 Json::null()（由 router_restore 留 warning，
/// 并**保留旧文件不删**——坏状态是证据，不能读一次就抹掉）
fn mr_read(project_dir : String, ns : String) -> Json {
  let raw = @fs.read_file_to_string(
    mr_state_path(project_dir, ns),
    encoding="utf8",
  ) catch {
    _ => ""
  }
  if raw.is_empty() {
    Json::null()
  } else {
    @json.parse(raw) catch {
      _ => Json::null()
    }
  }
}

///|
/// 写状态（建 memory/ 目录；失败返回 Err，绝不静默）
fn mr_save(
  r : @router.ModelRouter,
  project_dir : String,
  ns : String,
) -> Result[Unit, String] {
  // 逐层建目录（@fs.create_dir 不递归）：project_dir 本身也可能还不存在
  @fs.create_dir(project_dir) catch {
    _ => ()
  }
  @fs.create_dir(project_dir + "/memory") catch {
    _ => ()
  }
  let path = mr_state_path(project_dir, ns)
  @fs.write_string_to_file(path, r.to_state().stringify(), encoding="utf8") catch {
    _ =>
      return Err(
        "写入路由状态失败：" +
        path +
        "（权限/磁盘/路径越界都可能，未静默）",
      )
  }
  Ok(())
}

///|
fn mr_obj(items : Array[(String, Json)]) -> Json {
  Json::object(Map(items))
}

///|
fn mr_warn_arr(warns : Array[String]) -> Json {
  Json::array(warns.map(fn(x) { Json::string(x) }))
}

///|
/// config_json 文本 → Json。空串=不覆盖（`Json::null()`）；非法 JSON 一律 Err。
/// 这里绝不"解析失败就当没传"：调用方以为覆盖了池定义、实际却用默认池跑，
/// 是最难查的一类静默降级（与 BUG-31/33/43 同族）。
fn mr_parse_config(text : String) -> Result[Json, String] {
  if text.is_empty() {
    return Ok(Json::null())
  }
  let j = @json.parse(text) catch {
    _ =>
      return Err(
        "model_route: config_json 不是合法 JSON，已拒绝（不静默回落默认池定义）",
      )
  }
  Ok(j)
}

///|
/// config_json 里是否**显式给了池定义**。只给 window_seconds/threshold_pct 不算——
/// 不该为一次纯参数微调就替调用方建一个状态文件。
fn mr_config_gives_pools(config : Json) -> Bool {
  match config {
    Json::Object(m) => m.contains("free_pool") || m.contains("paid_pool")
    _ => false
  }
}

///|
/// 读环境变量（Star 门配置源）。不存在一律回空串，由 `star_gate_policy` 判定语义
/// （空公钥 = 门未启用；空 attestation = 启用但 fail-closed）。本文件只读，不打印值。
fn mr_env(name : String) -> String {
  match @env.get_env_var(name) {
    Some(v) => v
    None => ""
  }
}

///|
/// 决策 + 可选记账 + 落盘（工具 `model_route` 的实现体）。时间戳服务端盖章。
fn model_route_impl(
  project_dir : String,
  ns~ : String,
  record_model? : String = "",
  config? : Json = Json::null(),
) -> Result[Json, String] {
  if !bug_project_dir_ok(project_dir) {
    return Err(
      "model_route: 非法 project_dir（拒绝绝对路径/穿越/盘符）",
    )
  }
  match mr_check_ns(ns) {
    Some(msg) => return Err("model_route: " + msg)
    None => ()
  }
  let now = now_default()
  let (r, warns) = @router.router_restore(mr_read(project_dir, ns), config~)
  // Star 门（D1=A 完整接入）：从 env 读钉死公钥 / attestation / login，交给纯策略函数判定。
  //   未配置公钥 → 门未启用（保持现状不设门），状态见回执的 `star_gate` 字段（note 即告警，
  //     不进 `warnings`——既有 mo_2 锁定了默认路径 warnings==0，零回归）；
  //   启用但未放行 → 下方硬门短路（不 pick、不记账、不推进轮询游标）。
  // env 读取是本 IO 层唯一做的事；判定逻辑零 IO 在 src/router（star_gate_wbtest 可单测）。
  let gate = @router.star_gate_policy(
    mr_env("FIST_STAR_GATE_PUBKEY_HEX"),
    mr_env("FIST_STAR_GATE_ATTESTATION_JSON"),
    mr_env("FIST_STAR_GATE_USER_LOGIN"),
    @env.now().to_int64() / 1000L,
  )
  if gate.gate_enabled && not(gate.free_pool_unlocked) {
    return Ok(
      mr_obj([
        ("ok", Json::boolean(false)),
        ("stamped_at", Json::string(now)),
        ("decision", Json::null()),
        (
          "mode",
          Json::string(
            "query-only（Star 门拦截：未验签通过，未进行 pick）",
          ),
        ),
        ("warnings", mr_warn_arr(warns)),
        ("star_gate", gate.to_json()),
        ("state_path", Json::string(mr_state_path(project_dir, ns))),
      ]),
    )
  }
  // BUG-61/62：只有**真消耗**（调用方给了 record_model）才推进账本并落盘。
  // 旧实现连"只问不消耗"的查询也 mr_save ⇒ pick 推进过的轮询游标、以及 pick 顺手盖上的
  // window_start（5h 窗口没人使用就开始倒计时）都被写进了账，两次相同查询还会换模型。
  let consuming = !record_model.is_empty()
  // 唯一的例外：**播种定义，不播种用量**。调用方显式给了池定义时，必须在 pick 之前把
  // 池形状落盘——否则后续不带 config_json 的记账（executor_run 自动记的那一笔就是）只能
  // 拿默认池，自定义模型名走"未在任何池中配置"分支，配额形同虚设（本文件反复拦的静默降级族）。
  let seeds_pools = !consuming && mr_config_gives_pools(config)
  let seed_res = if seeds_pools { mr_save(r, project_dir, ns) } else { Ok(()) }
  let dec = if consuming {
    r.record_call(model=record_model, now~)
  } else {
    r.pick(now~)
  }
  let save_res = if consuming { mr_save(r, project_dir, ns) } else { seed_res }
  let persisted = match save_res {
    Ok(_) => consuming
    Err(_) => false
  }
  let mut items : Array[(String, Json)] = [
    ("ok", Json::boolean(dec.available)),
    ("stamped_at", Json::string(now)),
    ("decision", dec.to_json()),
    ("usage", r.usage_report()),
    ("warnings", mr_warn_arr(warns)),
    ("star_gate", gate.to_json()),
    ("persisted", Json::boolean(persisted)),
    (
      "mode",
      Json::string(
        if consuming {
          "consume（record_model 已给：记账 + 落盘）"
        } else if seeds_pools {
          "query-only（不记账、不推进轮询游标；已按 config_json 播种池定义，用量为零）"
        } else {
          "query-only（未给 record_model：不记账、不落盘、不推进轮询游标）"
        },
      ),
    ),
    ("state_path", Json::string(mr_state_path(project_dir, ns))),
  ]
  if !dec.available {
    items = items +
      [
        (
          "note",
          Json::string(
            "无可用模型（两池皆耗尽或未配置）。这是显式失败，不会静默改用别的模型。",
          ),
        ),
      ]
  }
  match save_res {
    Ok(_) => ()
    Err(e) => items = items + [("persist_error", Json::string(e))]
  }
  Ok(mr_obj(items))
}

///|
/// 只记账不做决策（BUG-61 的接线点：执行器真跑完，把这次用量记到路由账上）。
/// 复用 model_route_impl 的"给了 record_model 才落盘"语义，避免两处各写一遍存盘逻辑。
fn mr_record_only(
  project_dir : String,
  ns~ : String,
  model : String,
) -> Result[Unit, String] {
  match model_route_impl(project_dir, ns~, record_model=model) {
    Err(e) => Err(e)
    Ok(j) =>
      match j {
        Json::Object(m) =>
          match m.get("persisted") {
            Some(Json::True) => Ok(())
            _ => Err("记账未落盘（persisted=false）")
          }
        _ => Err("记账返回体不是对象")
      }
  }
}

///|
/// 只读状态查询（不改配额、不落盘）
fn model_router_status_impl(
  project_dir : String,
  ns~ : String,
) -> Result[Json, String] {
  if !bug_project_dir_ok(project_dir) {
    return Err(
      "model_router_status: 非法 project_dir（拒绝绝对路径/穿越/盘符）",
    )
  }
  match mr_check_ns(ns) {
    Some(msg) => return Err("model_router_status: " + msg)
    None => ()
  }
  let path = mr_state_path(project_dir, ns)
  let (r, warns) = @router.router_restore(mr_read(project_dir, ns))
  Ok(
    Json::object({
      "status": r.usage_report(),
      "state_path": Json::string(path),
      "exists": Json::boolean(@fs.path_exists(path)),
      "stamped_at": Json::string(now_default()),
      "warnings": mr_warn_arr(warns),
    }),
  )
}

///|
/// Star 门验签 verdict → 小写下划线串（契约要求 String）。用 `to_string()` 做映射，
/// 避免 server 包跨包 match 枚举变体；未知值原样回传（不静默吞）。
fn mr_verdict_str(v : @router.StarVerdict?) -> String {
  match v {
    None => ""
    Some(x) =>
      match x.to_string() {
        "Valid" => "valid"
        "Stale" => "stale"
        "BadSignature" => "bad_signature"
        "BadFormat" => "bad_format"
        "Unreadable" => "unreadable"
        "NoSuchUser" => "no_such_user"
        _ => x.to_string()
      }
  }
}

///|
/// 从 attestation JSON 里读一个 Int64 字段（ttl_seconds / issued_at）。
/// 读不到/解析失败一律回 0L，**不许崩溃**（`model_auth_status` 是只读查询，坏 attestation
/// 由 `star_gate_policy` 判定为 unreadable/bad_format，这里只负责"能读到多少是多少"）。
fn mr_att_int64(attestation : String, key : String) -> Int64 {
  if attestation.is_empty() {
    return 0L
  }
  let j : Json = @json.parse(attestation) catch { _ => return 0L }
  match j.value(key) {
    Some(Number(n, ..)) => n.to_int64()
    _ => 0L
  }
}

///|
/// 认证/Star 门状态（纯计算、零 IO）：调用方已把 env 值读好并传入，便于白盒测试
/// 用合成值直接钉住默认态 / fail-closed / 坏 attestation 三档，不污染真实 env。
/// `gate` 是返回契约里的那一块；`pools` 由 impl 另调 `model_router_status_impl` 拼上。
fn mr_auth_gate(
  pinned_key : String,
  attestation : String,
  user_login : String,
  now : Int64,
) -> Json {
  let gate = @router.star_gate_policy(pinned_key, attestation, user_login, now)
  let ttl = mr_att_int64(attestation, "ttl_seconds")
  let issued = mr_att_int64(attestation, "issued_at")
  // 读不到 issued_at 时 age 给 0（不给一个"now - 0"的伪读数）；now 早于签发（时钟回拨）也夹到 0
  let age = if issued <= 0L {
    0L
  } else {
    let d = now - issued
    if d < 0L {
      0L
    } else {
      d
    }
  }
  mr_obj([
    ("gate_enabled", Json::boolean(gate.gate_enabled)),
    ("free_pool_unlocked", Json::boolean(gate.free_pool_unlocked)),
    ("verdict", Json::string(mr_verdict_str(gate.verdict))),
    ("note", Json::string(gate.note)),
    // env 只回显"配没配"，**绝不回显密钥本体**（与 mr_env 的注释同一条纪律）
    ("pinned_key_configured", Json::boolean(!pinned_key.is_empty())),
    ("attestation_present", Json::boolean(!attestation.is_empty())),
    ("user_login_configured", Json::boolean(!user_login.is_empty())),
    ("ttl_seconds", Json::number(ttl.to_double())),
    ("attestation_age_seconds", Json::number(age.to_double())),
  ])
}

///|
/// 只读查询：模型路由的认证/Star 门当前状态（工具 `model_auth_status` 的实现体）。
/// **零副作用**：不改配额、不落盘、不推进轮询游标、不做任何模型 pick（也不调 `model_route_impl`）。
/// `pools` 直接复用 `model_router_status_impl` 的返回 JSON 原样嵌入；它 Err 时 pools 给
/// `{"error": e}` 但**整体仍 Ok**——排障场景里"gate 能不能看到"比"池状态读没读到"更重要。
/// Star 门完全未配置（默认态）时 gate_enabled=false / free_pool_unlocked=true，零回归。
pub fn model_auth_status_impl(
  project_dir : String,
  ns~ : String,
) -> Result[Json, String] {
  if !bug_project_dir_ok(project_dir) {
    return Err(
      "model_auth_status: 非法 project_dir（拒绝绝对路径/穿越/盘符）",
    )
  }
  match mr_check_ns(ns) {
    Some(msg) => return Err("model_auth_status: " + msg)
    None => ()
  }
  let now = @env.now().to_int64() / 1000L
  let gate = mr_auth_gate(
    mr_env("FIST_STAR_GATE_PUBKEY_HEX"),
    mr_env("FIST_STAR_GATE_ATTESTATION_JSON"),
    mr_env("FIST_STAR_GATE_USER_LOGIN"),
    now,
  )
  let pools = match model_router_status_impl(project_dir, ns~) {
    Ok(j) => j
    Err(e) => Json::object({ "error": Json::string(e) })
  }
  Ok(mr_obj([("ok", Json::boolean(true)), ("gate", gate), ("pools", pools)]))
}

///|
/// 清窗口（配额与窗口起点归零）。hard=true 连档位/游标/切换计数一起复位。
fn model_router_reset_impl(
  project_dir : String,
  ns~ : String,
  hard? : Bool = false,
) -> Result[Json, String] {
  if !bug_project_dir_ok(project_dir) {
    return Err(
      "model_router_reset: 非法 project_dir（拒绝绝对路径/穿越/盘符）",
    )
  }
  match mr_check_ns(ns) {
    Some(msg) => return Err("model_router_reset: " + msg)
    None => ()
  }
  let now = now_default()
  let (r, _) = @router.router_restore(mr_read(project_dir, ns))
  if hard {
    r.hard_reset()
  } else {
    r.reset_windows()
  }
  match mr_save(r, project_dir, ns) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  Ok(
    Json::object({
      "reset": Json::string(if hard { "hard" } else { "window" }),
      "stamped_at": Json::string(now),
      "usage": r.usage_report(),
    }),
  )
}

///|
/// OFM 通道：真实 POST `{ofm_endpoint}/chat/completions`（CLI spawn 保留，本通道**并存**）。
/// `executor=="ofm"` 时由 `executor_run_impl` 分流到此，不经 `build_command`。
/// 端点 env 优先、config 兜底（复用 `resolve_ofm_endpoint`）；密钥只在 server 进程环境变量里，
/// 本层读进 fetch 头、**不回显**；`dry_run=true` 只回显将发送的请求体，一个网络请求都不发。
/// 失败走 `classify_ofm_failure` 归因（status<=0 → NetworkError，401 → InvalidCredential，
/// 5xx → UpstreamDown），不猜、不降级、不静默成功。
async fn ofm_execute_http(
  project_dir : String,
  ns~ : String,
  prompt~ : String,
  model~ : String,
  timeout_ms : Int,
  dry_run : Bool,
  route_json : Json,
  routed_by_pool : Bool,
) -> Json {
  let fail = fn(msg : String, extra : Array[(String, Json)]) -> Json {
    mr_obj(
      [
        ("ok", Json::boolean(false)),
        ("executor", Json::string("ofm")),
        ("error", Json::string(msg)),
      ] +
      extra,
    )
  }
  let head : Array[(String, Json)] = [
    ("executor", Json::string("ofm")),
    ("model", Json::string(model)),
    ("route", route_json),
  ]
  let (r, _warns) = @router.router_restore(
    mr_read(project_dir, ns),
    config=Json::null(),
  )
  let endpoint = @router.resolve_ofm_endpoint(
    r.config.ofm_endpoint,
    mr_env("FIST_OFM_ENDPOINT"),
  )
  if endpoint.is_empty() {
    return fail(
      "ofm: OFM 端点未配置（设 FIST_OFM_ENDPOINT 或 config.ofm_endpoint，均空则拒绝）",
      head,
    )
  }
  let body = match @router.build_ofm_chat_request_json_simple(model, prompt) {
    Err(e) =>
      return fail("ofm: 请求体构建失败（fail-closed）：" + e, head)
    Ok(b) => b
  }
  let url = ofm_chat_url(endpoint)
  if dry_run {
    return mr_obj(
      [("ok", Json::boolean(true))] +
      head +
      [
        ("executed", Json::boolean(false)),
        ("dry_run", Json::boolean(true)),
        ("quota_touched", Json::boolean(false)),
        ("url", Json::string(url)),
        ("request_body", Json::string(body)),
        (
          "hint",
          Json::string(
            "dry_run 未发任何网络请求；密钥只从 server 进程环境变量读，不在此回显",
          ),
        ),
      ],
    )
  }
  let call_res = ofm_chat_http(url, body, timeout_ms)
  let (http_status, raw_body, net_error) = match call_res {
    Err(e) => (0, "", e)
    Ok(j) =>
      match j {
        Json::Object(m) =>
          (
            mr_json_int(m, "status"),
            mr_json_str(m, "body"),
            mr_json_str(m, "error"),
          )
        _ => (0, "", "ofm_chat_http 返回体非对象")
      }
  }
  // status==0 且带网络错误文本：没拿到 HTTP 响应（网络/超时/DNS），解析它归因
  let to_parse = if http_status == 0 && net_error.length() > 0 {
    net_error
  } else {
    raw_body
  }
  let resp = @router.parse_ofm_chat_response(to_parse, http_status)
  let fail_kind = @router.classify_ofm_failure(http_status, resp.error_type)
  let quota_note = if routed_by_pool {
    match mr_record_only(project_dir, ns~, model) {
      Ok(_) => "recorded(\{model})"
      Err(e) => "record_failed: \{e}"
    }
  } else {
    "not_routed(调用方显式指定 model，不代记账)"
  }
  if resp.is_error {
    return mr_obj(
      [("ok", Json::boolean(false))] +
      head +
      [
        ("executed", Json::boolean(true)),
        ("quota", Json::string(quota_note)),
        ("http_status", Json::number(http_status.to_double())),
        ("error_type", Json::string(resp.error_type)),
        ("error", Json::string(resp.error_message)),
        ("failure_kind", Json::string(fail_kind.label())),
        (
          "hint",
          Json::string(
            "OFM 通道未拿到成功正文（上游/网络/凭据）。故障面见 failure_kind；" +
            "key 只在 server 进程环境变量里，本回执不回显。",
          ),
        ),
      ],
    )
  }
  mr_obj(
    [("ok", Json::boolean(true))] +
    head +
    [
      ("executed", Json::boolean(true)),
      ("quota", Json::string(quota_note)),
      ("http_status", Json::number(http_status.to_double())),
      ("content", Json::string(resp.content)),
      (
        "hint",
        Json::string(
          "OFM 通道返回成功正文；仍是外部模型输出，按证据梯 L4 用 output_validate 到文件系统验证",
        ),
      ),
    ],
  )
}

///|
/// 把端点规范化成 `{endpoint}/chat/completions`（端点已带该后缀则不重复拼接）。
fn ofm_chat_url(endpoint : String) -> String {
  let ep = endpoint.trim().to_owned()
  if ep.ends_with("/chat/completions") {
    return ep
  }
  if ep.ends_with("/") {
    return ep + "chat/completions"
  }
  ep + "/chat/completions"
}

///|
/// 读 Json 对象的 Int 字段。
fn mr_json_int(m : Map[String, Json], key : String) -> Int {
  match m.get(key) {
    Some(Json::Number(n, ..)) => n.to_int()
    _ => 0
  }
}

///|
/// 读 Json 对象的 String 字段。
fn mr_json_str(m : Map[String, Json], key : String) -> String {
  match m.get(key) {
    Some(Json::String(s)) => s
    _ => ""
  }
}

///|
/// 用路由结果跑外部执行器（工具 `executor_run` 的实现体）。
/// 没显式给 model 时，先向路由器要一个模型并记账 —— 路由↔执行器的接线点。
/// `executor=="ofm"` 走并存 HTTP 通道（见 `ofm_execute_http`），其余走 CLI spawn。
/// 可执行文件名由 src/executor 的登记表推导（调用方无法注入任意命令）。
/// dry_run=true 只回显"将执行的 argv"、一个进程都不起 —— 宿主命令能力默认收紧，
/// 先可审后执行；真跑的开关留在调用方显式去掉 dry_run。
async fn executor_run_impl(
  project_dir : String,
  ns~ : String,
  executor~ : String,
  prompt~ : String,
  model? : String = "",
  timeout_ms? : Int = 180000,
  dry_run? : Bool = false,
) -> Json {
  let fail = fn(msg : String, extra : Array[(String, Json)]) -> Json {
    mr_obj(
      [
        ("ok", Json::boolean(false)),
        ("executor", Json::string(executor)),
        ("error", Json::string(msg)),
      ] +
      extra,
    )
  }
  if !bug_project_dir_ok(project_dir) {
    return fail(
      "executor_run: 非法 project_dir（拒绝绝对路径/穿越/盘符）",
      [],
    )
  }
  match mr_check_ns(ns) {
    Some(msg) => return fail("executor_run: " + msg, [])
    None => ()
  }
  if !@executor.is_external_executor(executor) {
    return fail(
      "未知执行器 '" +
      executor +
      "'，可用：" +
      @executor.external_executors().join(", "),
      [],
    )
  }
  let mut chosen = model
  let mut route_json = Json::null()
  // 只有"模型是路由器给的"才需要在真跑后记账；调用方显式指定 model 属越池覆盖，
  // 由调用方自己负责，不替它动配额账。
  let mut routed_by_pool = false
  if chosen.is_empty() {
    match model_route_impl(project_dir, ns~) {
      Err(e) => return fail(e, [])
      Ok(j) =>
        match j {
          Json::Object(m) => {
            let avail = match m.get("ok") {
              Some(Json::True) => true
              _ => false
            }
            if !avail {
              return fail(
                "路由无可用模型，未启动执行器（不猜测模型名）",
                [("route", j)],
              )
            }
            let name = match m.get("decision") {
              Some(Json::Object(d)) =>
                match d.get("model") {
                  Some(Json::String(s)) => s
                  _ => ""
                }
              _ => ""
            }
            if name.is_empty() {
              return fail(
                "路由返回的模型名为空，未启动执行器",
                [("route", j)],
              )
            }
            chosen = name
            route_json = j
            routed_by_pool = true
          }
          _ =>
            return fail(
              "路由返回体不是对象（内部异常），未启动执行器",
              [],
            )
        }
    }
  }
  // OFM 走并存 HTTP 通道（不经 build_command / spawn）；CLI spawn（aider/atomcode）保留。
  if executor == "ofm" {
    return ofm_execute_http(
      project_dir,
      ns~,
      prompt~,
      model=chosen,
      timeout_ms,
      dry_run,
      route_json,
      routed_by_pool,
    )
  }
  let (bin, args) = match
    @executor.build_command(
      executor~,
      prompt~,
      model=chosen,
      workdir=project_dir,
    ) {
    Err(e) => return fail(e, [("model", Json::string(chosen))])
    Ok(v) => v
  }
  if dry_run {
    // 只回显"将要执行的 argv"，一个进程都不起：宿主命令能力默认收紧，
    // 让运维能在真跑之前逐字审命令（也用于 CI/无凭据环境下验证接线）。
    return mr_obj(
      [
        ("ok", Json::boolean(true)),
        ("executed", Json::boolean(false)),
        ("dry_run", Json::boolean(true)),
        ("quota_touched", Json::boolean(false)),
        ("argv", Json::array(args.map(fn(a) { Json::string(a) }))),
        ("workdir", Json::string(project_dir)),
        ("timeout_ms", Json::number(timeout_ms.to_double())),
      ] +
      [
        (
          "hint",
          Json::string(
            "dry_run 未启动任何外部进程；去掉 dry_run 才会真跑（提示词只作为 argv 元素，不经 shell）",
          ),
        ),
      ] +
      [
        ("executor", Json::string(executor)),
        ("binary", Json::string(bin)),
        ("model", Json::string(chosen)),
        ("route", route_json),
      ],
    )
  }
  let res = run_check_external(bin, args, project_dir, timeout_ms)
  let head : Array[(String, Json)] = [
    ("executor", Json::string(executor)),
    ("binary", Json::string(bin)),
    ("model", Json::string(chosen)),
    ("route", route_json),
  ]
  match res {
    Err(e) =>
      mr_obj(
        [("ok", Json::boolean(false))] +
        head +
        [
          ("executed", Json::boolean(false)),
          ("exit_code", Json::number(-1.0)),
          ("error", Json::string(e)),
          ("hint", Json::string(@executor.executor_missing_hint(executor))),
        ],
      )
    Ok(j) => {
      // BUG-61：进程真起来的一方才记账（Err 分支是 ENOENT 一类，没起进程就不消耗）。
      // 这正是 AGENTS.md 与工具描述承诺的"model 留空则先要一个模型并记账"。
      let quota_note = if routed_by_pool {
        match mr_record_only(project_dir, ns~, chosen) {
          Ok(_) => "recorded(\{chosen})"
          Err(e) => "record_failed: \{e}"
        }
      } else {
        "not_routed(调用方显式指定 model，不代记账)"
      }
      let jm : Map[String, Json] = match j {
        Json::Object(mm) => mm
        _ => Map([])
      }
      let okk = match jm.get("ok") {
        Some(Json::True) => true
        _ => false
      }
      let code = match jm.get("code") {
        Some(Json::Number(n, ..)) => n.to_int()
        _ => -1
      }
      let errtxt = match jm.get("error") {
        Some(Json::String(s)) => s
        _ => ""
      }
      let stderrtxt = match jm.get("stderr") {
        Some(Json::String(s)) => s
        _ => ""
      }
      let tail = if !errtxt.is_empty() { errtxt } else { stderrtxt }
      let hint = if okk {
        "外部执行器返回 0；成果仍需按证据梯 L4 用 output_validate 到文件系统验证（报告不是证据）"
      } else {
        @executor.executor_missing_hint(executor)
      }
      mr_obj(
        [("ok", Json::boolean(okk))] +
        head +
        [
          ("executed", Json::boolean(true)),
          ("quota", Json::string(quota_note)),
          ("exit_code", Json::number(code.to_double())),
          (
            "cost_estimate",
            Json::number(if executor == "atomcode" { 0.0 } else { -1.0 }),
          ),
          ("error_tail", Json::string(tail)),
          ("hint", Json::string(hint)),
        ],
      )
    }
  }
}
