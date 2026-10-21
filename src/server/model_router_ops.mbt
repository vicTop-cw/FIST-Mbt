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
/// CAF 记忆状态文件路径（与 mr_state_path 同一条命名空间校验口径）。
/// dry_run 预览只读它、绝不创建（文件不存在 = 空记忆，零回归）。
fn mr_caf_state_path(project_dir : String, ns : String) -> String {
  let safe_ns = if ns.is_empty() { "default" } else { ns }
  project_dir + "/memory/model-router-caf-" + safe_ns + ".json"
}

///|
/// 读 CAF 记忆状态；文件不存在/读失败/非法 JSON 一律回 Json::null()，
/// 由 `caf_memory_load` 降级成空记忆 + warning，绝不 panic。
/// 与 `mr_read` 同款"坏状态不删"纪律：坏记忆是证据，留给 `caf_memory_load` 计数告警。
fn mr_caf_read(project_dir : String, ns : String) -> Json {
  let raw = @fs.read_file_to_string(
    mr_caf_state_path(project_dir, ns),
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
/// 把 `@json.parse`（raising 风格）包成 Result，好让调用方能区分「解析成功」与「坏 JSON」。
/// `mr_caf_read` 把两者都塌成 `Json::null()`（读侧只需降级），CAF 写半需要知道根因
/// ——坏 JSON 是证据，不能覆盖/删除。
fn mr_try_parse(raw : String) -> Result[Json, Unit] {
  let v = @json.parse(raw) catch { _ => return Err(()) }
  Ok(v)
}

///|
/// CAF 记忆文件的**可诊断**读取：区分「不存在」/「空」/「坏 JSON」/「合法 JSON」，
/// 供 dry_run 读侧与 push 写侧共用同一套降级口径（`mr_caf_read` 把"不存在/读失败/坏 JSON"
/// 全部塌成 `Json::null()`，读侧能降级但**说不出根因**；本函数把根因显式带出来）。
/// 返回 `(是否存在, 是否坏 JSON, 解析后的 Json 或 Json::null())`。
/// 坏 JSON 是证据：只计数告警，绝不删除/覆盖（与 `mr_read` 同款"坏状态不删"纪律）。
fn mr_caf_read_diag(project_dir : String, ns : String) -> (Bool, Bool, Json) {
  let path = mr_caf_state_path(project_dir, ns)
  if not(@fs.path_exists(path)) {
    return (false, false, Json::null())
  }
  let raw = @fs.read_file_to_string(path, encoding="utf8") catch { _ => "" }
  if raw.trim().is_empty() {
    return (true, false, Json::null())
  }
  // 解析成功即合法 JSON（即使是字面量 `null`/数字——那种由 caf_memory_load 再降级），
  // 解析失败才是坏 JSON。
  match mr_try_parse(raw) {
    Ok(j) => (true, false, j)
    Err(_) => (true, true, Json::null())
  }
}

///|
/// CAF 写半（Slice B）：把一次**真消耗**作为 evidence 追加进 CAF 记忆文件并落盘，
/// 闭合标准 3 的「写半」——否则 CAF 状态文件永为空、dry_run 恒返回空 basis。
///
/// 纪律（与读侧同源）：
///   - 只在 `r.config.use_caf_memory=true` 时由调用方调用；false 一个字节都不碰（零回归）。
///   - 坏 JSON 记忆文件**不覆盖、不删除**，留作证据并计数告警，本次 push 直接跳过。
///   - cost 记为 0.0：路由层不掌握真实成本（CafRecord 契约：0 = 未知/免费）。
///   - ok 由调用方给定：成功执行记 ok=true，失败执行记 ok=false——CAF 同时学成功与失败，
///     不能只学成功（否则"常失败模型"的 CAF 成功率被长期抬高）。
///
/// 返回追加过程的 warnings；Err 仅表示**写盘失败**（调用方必须回执，不得静默吞）。
fn mr_caf_push_evidence(
  project_dir : String,
  ns : String,
  context : String,
  model : String,
  ts : String,
  ok : Bool,
) -> Result[Array[String], String] {
  let path = mr_caf_state_path(project_dir, ns)
  let (_exists, bad_json, caf_json) = mr_caf_read_diag(project_dir, ns)
  if bad_json {
    return Ok([
      "CAF 记忆文件是坏 JSON，已跳过本次回写（不覆盖证据）",
    ])
  }
  let (mem, warns) = @router.caf_memory_load(caf_json)
  mem.push(
    @router.CafRecord::new(
      feature_hash=@router.caf_feature_hash(
        @router.caf_normalize_context(context),
      ),
      model~,
      ok~,
      cost=0.0,
      ts~,
    ),
  )
  @fs.create_dir(project_dir + "/memory") catch {
    _ => ()
  }
  @fs.write_string_to_file(
    path,
    @router.caf_memory_dump(mem).stringify(),
    encoding="utf8",
  ) catch {
    _ => return Err("写入 CAF 记忆文件失败：" + path)
  }
  Ok(warns)
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
/// 非空才出字段：空数组→`[]`（不给回执塞 `"key": []` 噪音）。
fn mr_opt_arr_field(key : String, arr : Array[String]) -> Array[(String, Json)] {
  if arr.is_empty() {
    []
  } else {
    [(key, mr_warn_arr(arr))]
  }
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
/// 从环境变量读取逗号分隔的不健康模型黑名单（如 `FIST_OFM_UNHEALTHY_MODELS`）。
/// 空串 / 不存在 → 空数组（不误伤任何模型）。
fn mr_unhealthy_models() -> Array[String] {
  let raw = mr_env("FIST_OFM_UNHEALTHY_MODELS").trim().to_string()
  if raw.is_empty() {
    return []
  }
  let out : Array[String] = []
  let mut buf = ""
  for i = 0; i < raw.length(); i = i + 1 {
    let c = raw[i]
    if c == ',' {
      let s = buf.trim().to_string()
      if !s.is_empty() {
        out.push(s)
      }
      buf = ""
    } else {
      buf = buf + c.to_string()
    }
  }
  let last = buf.trim().to_string()
  if !last.is_empty() {
    out.push(last)
  }
  out
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
/// P2：laya 软性档位提示（probe → tier 选择 → 解析 answers.tier）。
/// 任一环节失败/超时 → 返回 ""（静默回落，零回归）。返回 "Free" 或 "Paid"（与 laya sidecar 口径）。
async fn mr_laya_tier_hint() -> String {
  let cmd = "python"
  let args = ["scripts/laya_decide.py"]
  let workdir = "."
  let avail = match laya_probe_cached(cmd, args, workdir, 1000) {
    Ok(a) => a
    Err(_) => false
  }
  if !avail {
    return ""
  }
  let questions = Json::object({
    "tier": Json::object({
      "choices": Json::array([Json::string("Free"), Json::string("Paid")]),
      "description": Json::string(
        "建议路由档位：Free=免费池优先，Paid=付费池优先",
      ),
    }),
  })
  let input = Json::object({
    "context": Json::string("model-router 软性档位建议"),
    "questions": questions,
    "model": Json::string("english"),
  }).stringify()
  match laya_decide_external(cmd, args, workdir, input, 3000) {
    Err(_) => ""
    Ok(j) =>
      match j {
        Json::Object(m) =>
          match m.get("answers") {
            Some(Json::Object(am)) =>
              match am.get("tier") {
                Some(Json::String(s)) => {
                  let t = s.trim().to_owned()
                  if t == "Free" || t == "Paid" {
                    t
                  } else {
                    ""
                  }
                }
                Some(_) => ""
                None => ""
              }
            _ => ""
          }
        _ => ""
      }
  }
}

///|
/// 决策 + 可选记账 + 落盘（工具 `model_route` 的实现体）。时间戳服务端盖章。
fn model_route_impl(
  project_dir : String,
  ns~ : String,
  record_model? : String = "",
  config? : Json = Json::null(),
  laya_hint? : String = "",
  soldier? : String = "",
  pool_label? : String = "",
  dry_run? : Bool = false,
  context? : String = "",
  ok? : Bool = true,
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
  if gate.gate_enabled && !gate.free_pool_unlocked {
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
  // CAF dry_run 预览（§2.3 最后一格，验收标准 3）：零副作用 peek，返回建议模型 + 历史依据。
  // 必须在此短路返回——否则 dry_run 会推进 pick 的轮询游标、给模型盖 window_start、
  // 甚至被"播种池定义"路径写一个 model-router-{ns}.json，全部违背"零副作用预览"承诺。
  // config.use_caf_memory=false 时**显式拒绝**（不静默降级回普通查询：调用方以为在看
  // CAF 建议、实际却拿到了非 CAF 决策，是 BUG-31 同族的最难查静默降级）。
  if dry_run {
    if !r.config.use_caf_memory {
      return Err(
        "model_route: dry_run=true 但 config.use_caf_memory=false，CAF 未开启",
      )
    }
    let caf_path = mr_caf_state_path(project_dir, ns)
    let (_caf_exists, caf_bad_json, caf_json) = mr_caf_read_diag(
      project_dir, ns,
    )
    let (mem, caf_warns) = @router.caf_memory_load(caf_json)
    // 坏 JSON 是证据：只计数告警，绝不删除/覆盖（与 mr_read 同款纪律）。caf_memory_load 已
    // 降级成空记忆（顶层非对象），这里再点名根因，让调用方知道"空 basis 是因为记忆坏了"。
    let caf_warns_all = if caf_bad_json {
      caf_warns +
      [
        "CAF 记忆文件是坏 JSON，按空记忆处理（坏状态是证据，未删除）",
      ]
    } else {
      caf_warns
    }
    let dr = r.pick_caf_dry_run(
      now~,
      caf_memory=mem,
      context~,
      k=32,
      unhealthy_ids=mr_unhealthy_models(),
      caf_default_preference=r.config.caf_default_preference,
      caf_min_evidences=r.config.caf_min_evidences,
    )
    return Ok(
      mr_obj([
        ("ok", Json::boolean(true)),
        ("stamped_at", Json::string(now)),
        ("context", Json::string(context)),
        ("persisted", Json::boolean(false)),
        ("decision", @router.caf_dry_run_to_json(dr)),
        ("warnings", mr_warn_arr(warns + caf_warns_all)),
        ("star_gate", gate.to_json()),
        (
          "mode",
          Json::string(
            "caf-dry-run（零副作用：不记账、不推进游标、不写状态文件）",
          ),
        ),
        ("state_path", Json::string(mr_state_path(project_dir, ns))),
        ("caf_state_path", Json::string(caf_path)),
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
  let unhealthy_ids = mr_unhealthy_models()
  // §8.3 路由联动：兵种（display 层 8 兵种）→ 池标签 → pick 的软性档位提示。
  // 给 soldier 没给 pool_label 时，用 display 的 pool_label_of 解析；两者皆空 = 零回归。
  let resolved_soldier = soldier
  let resolved_pool = if pool_label != "" {
    pool_label
  } else if resolved_soldier != "" {
    @display.pool_label_of(resolved_soldier)
  } else {
    ""
  }
  let dec = if consuming {
    r.record_call(model=record_model, now~)
  } else {
    r.pick(
      now~,
      unhealthy_ids~,
      laya_prefer_tier=laya_hint,
      soldier_label=resolved_pool,
    )
  }
  let save_res = if consuming { mr_save(r, project_dir, ns) } else { seed_res }
  let persisted = match save_res {
    Ok(_) => consuming
    Err(_) => false
  }
  // CAF 写半（Slice B）：真消耗后把本次调用作为一条 evidence 回写进 CAF 记忆文件，
  // 闭合标准 3 的「写半」——否则 `memory/model-router-caf-{ns}.json` 永为空、dry_run 恒返回空 basis。
  // 只在 `r.config.use_caf_memory=true` 时发生（false 时一个字节都不碰，零回归红线）；
  // 坏 JSON 记忆文件不覆盖、不删除，由 push helper 留作证据计数告警。
  // 失败不吞：写盘失败进 `warnings`（回执可见），但**不**让 model_route 整体转 Err——
  // 路由决策与记账已成功，CAF 写半是旁路增强，不应把主路径拉黑。
  let mut caf_push_warns : Array[String] = []
  if consuming && r.config.use_caf_memory {
    match
      mr_caf_push_evidence(project_dir, ns, context, record_model, now, ok) {
      Ok(w) => caf_push_warns = w
      Err(e) => caf_push_warns = [e]
    }
  }
  let mut items : Array[(String, Json)] = [
    ("ok", Json::boolean(dec.available)),
    ("stamped_at", Json::string(now)),
    ("decision", dec.to_json()),
    ("usage", r.usage_report()),
    ("soldier", Json::string(resolved_soldier)),
    ("pool_label", Json::string(resolved_pool)),
    (
      "tier_hint",
      Json::string(
        if resolved_pool == "" {
          ""
        } else {
          @router.pool_label_tier_hint(resolved_pool)
        },
      ),
    ),
    ("warnings", mr_warn_arr(warns + caf_push_warns)),
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
/// `ok` 是本次执行的成败：成功 true、失败 false，透传给 CAF 写半（失败也 push，ok=false）。
fn mr_record_only(
  project_dir : String,
  ns~ : String,
  model : String,
  ok? : Bool = true,
) -> Result[Unit, String] {
  match model_route_impl(project_dir, ns~, record_model=model, ok~) {
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
/// P1.1：给某模型标记失败冷却（不消耗配额）。冷却时长从 env `FIST_MODEL_COOLDOWN_SECS`
/// 取（默认 300 秒）。模型不在池中→无操作返回 Ok（防御性，正常路径不会触发）；
/// 落盘失败返回 Err，调用方必须回执，不得静默吞错（BUG-229）。
fn mr_record_failure(
  project_dir : String,
  ns~ : String,
  model : String,
) -> Result[Unit, String] {
  let env_secs = mr_env("FIST_MODEL_COOLDOWN_SECS")
  let mut secs = 300
  if env_secs != "" {
    let parsed = bug_parse_int(env_secs)
    if parsed > 0 {
      secs = parsed
    }
  }
  let now_secs = @router.iso_to_secs(now_default())
  let cool_until = @router.secs_to_iso(now_secs + secs)
  let (r, _warns) = @router.router_restore(mr_read(project_dir, ns))
  let found = r.mark_failure(model, cool_until)
  if !found {
    return Ok(())
  }
  mr_save(r, project_dir, ns)
}

///|
/// BUG-229：把重试分支的记账/冷却 `Result` 归一成回执字符串（Ok→""；Err→"model: err"）。
/// 重试分支不得再用 `let _ =` 丢弃：落盘失败必须留痕。
fn mr_retry_note(model : String, res : Result[Unit, String]) -> String {
  match res {
    Ok(_) => ""
    Err(e) => "\{model}: \{e}"
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
  // 非 JSON 二次重试：回体不可解析时，追加 system 提示后重发一次
  let (http_status, resp) = if @router.should_retry_on_invalid_json(resp) {
    match @router.append_retry_prompt(body) {
      Ok(body2) => {
        let call_res2 = ofm_chat_http(url, body2, timeout_ms)
        let (hs2, rb2, ne2) = match call_res2 {
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
        let tp2 = if hs2 == 0 && ne2.length() > 0 { ne2 } else { rb2 }
        let resp2 = @router.parse_ofm_chat_response(tp2, hs2)
        (hs2, resp2)
      }
      Err(_) => (http_status, resp)
    }
  } else {
    (http_status, resp)
  }
  let fail_kind = @router.classify_ofm_failure(http_status, resp.error_type)
  let quota_note = if routed_by_pool {
    match mr_record_only(project_dir, ns~, model, ok=not(resp.is_error)) {
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
  if ep.has_suffix("/chat/completions") {
    return ep
  }
  if ep.has_suffix("/") {
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
  // 可替换 Executor（验收项）：白名单走 build_command；自定义执行器走受限 CLI 通道
  // （binary=注册名、argv=[prompt]，不经 shell）。放行名单由 server 层 exec_reg 把关
  // （executor_run 工具闭包），本层只负责执行通道，不再硬拒非白名单。
  let custom_cli = !@executor.is_external_executor(executor)
  let mut chosen = model
  let mut route_json = Json::null()
  // 只有"模型是路由器给的"才需要在真跑后记账；调用方显式指定 model 属越池覆盖，
  // 由调用方自己负责，不替它动配额账。
  let mut routed_by_pool = false
  // BUG-238：atomcode 不走 FIST 模型路由。FIST `model_route` 的池名
  // （ling-3.1-flash-free / mimo-v2.6-flash-free 等）是 FIST 自己的命名空间，
  // 与 atomcode provider 命名空间（longcat/deepseek/Kimi，见 ~/.atomcode/config.toml）
  // 两套不通——把 FIST 池名塞进 atomcode 的 `--model` 会让它恒吃
  // `HTTP 400 Unsupported model`。故 model 留空时**跳过路由**、chosen 保持空串，
  // 由 `cli_argv.atomcode_argv` 省略 `--model`，让 atomcode 走自身 config 的
  // default_model。aider 不同（空模型=绕过路由决策，维持拒绝），仍走路由。
  if chosen.is_empty() && executor != "atomcode" && !custom_cli {
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
  // P1.1：从路由回执取备用链 + 最大重试次数（env FIST_MODEL_MAX_RETRIES 默认 1）
  let mut fallback_models : Array[String] = []
  let mut max_retries = 1
  let env_retries = mr_env("FIST_MODEL_MAX_RETRIES")
  if env_retries != "" {
    let parsed = bug_parse_int(env_retries)
    if parsed > 0 {
      max_retries = parsed
    }
  }
  match route_json {
    Json::Object(m) =>
      match m.get("decision") {
        Some(Json::Object(d)) =>
          match d.get("fallback_chain") {
            Some(Json::Array(arr)) =>
              for item in arr {
                match item {
                  Json::String(s) => fallback_models = fallback_models + [s]
                  _ => ()
                }
              }
            _ => ()
          }
        _ => ()
      }
    _ => ()
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
  let (bin, args) : (String, Array[String]) = if custom_cli {
    // 自定义执行器：binary=注册名、argv=[prompt]（受限 CLI 通道，不经 shell，与
    // build_command 同一安全线：提示词只是字面量 argv 元素）
    (executor, [prompt])
  } else {
    match
      @executor.build_command(executor~, prompt~, model=chosen, workdir="") {
      Err(e) => return fail(e, [("model", Json::string(chosen))])
      Ok(v) => v
    }
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
  // P1.1：备用模型自动切换（CLI 通道）。主选失败且备用链还有候选时换模型重试，
  // 最多 `max_retries` 次（env FIST_MODEL_MAX_RETRIES）。每次重试把失败模型记一次配额账。
  let mut attempt_model = chosen
  let mut attempt_idx = -1
  let mut retried : Array[String] = []
  let mut should_retry = true
  // BUG-229：重试分支的记账/冷却 Err 留痕（不得 `let _ =` 静默吞错）
  let mut cooldown_errors : Array[String] = []
  while should_retry {
    should_retry = false
    let (bin, args) = if attempt_idx < 0 {
      (bin, args)
    } else {
      match
        @executor.build_command(
          executor~,
          prompt~,
          model=attempt_model,
          workdir="",
        ) {
        Err(e) => return fail(e, [("model", Json::string(attempt_model))])
        Ok(v) => v
      }
    }
    let res = run_check_external(bin, args, project_dir, timeout_ms)
    let head : Array[(String, Json)] = [
        ("executor", Json::string(executor)),
        ("binary", Json::string(bin)),
        ("model", Json::string(attempt_model)),
        ("route", route_json),
      ] +
      [("retried", Json::array(retried.map(fn(x) { Json::string(x) })))]
    match res {
      Err(e) =>
        // 进程没起来（ENOENT 一类）不消耗配额，所以重试无需记账；
        // 但模型可靠性已受疑 → 标记冷却（P1.1 冷却/自动摘除）
        if attempt_idx + 1 < max_retries &&
          attempt_idx + 1 < fallback_models.length() {
          let note = mr_retry_note(
            attempt_model,
            mr_record_failure(project_dir, ns~, attempt_model),
          )
          if note != "" {
            cooldown_errors = cooldown_errors + [note]
          }
          retried = retried + [attempt_model]
          attempt_idx = attempt_idx + 1
          attempt_model = fallback_models[attempt_idx]
          should_retry = true
        } else {
          return mr_obj(
            [("ok", Json::boolean(false))] +
            head +
            mr_opt_arr_field("cooldown_errors", cooldown_errors) +
            [
              ("executed", Json::boolean(false)),
              ("exit_code", Json::number(-1.0)),
              ("error", Json::string(e)),
              ("hint", Json::string(@executor.executor_missing_hint(executor))),
            ],
          )
        }
      Ok(j) => {
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
        // 进程真起来的一方才记账（BUG-61：Err 分支是 ENOENT，没起进程就不消耗）
        if !okk &&
          attempt_idx + 1 < max_retries &&
          attempt_idx + 1 < fallback_models.length() {
          if routed_by_pool {
            let note = mr_retry_note(
              attempt_model,
              mr_record_only(project_dir, ns~, attempt_model, ok=false),
            )
            if note != "" {
              cooldown_errors = cooldown_errors + [note]
            }
          }
          let note = mr_retry_note(
            attempt_model,
            mr_record_failure(project_dir, ns~, attempt_model),
          )
          if note != "" {
            cooldown_errors = cooldown_errors + [note]
          }
          retried = retried + [attempt_model]
          attempt_idx = attempt_idx + 1
          attempt_model = fallback_models[attempt_idx]
          should_retry = true
        } else {
          // 最终尝试（成功或已用尽重试）：记账并返回
          let quota_note = if routed_by_pool {
            match mr_record_only(project_dir, ns~, attempt_model, ok=okk) {
              Ok(_) => "recorded(\{attempt_model})"
              Err(e) => "record_failed: \{e}"
            }
          } else {
            "not_routed(调用方显式指定 model，不代记账)"
          }
          let hint = if okk {
            "外部执行器返回 0；成果仍需按证据梯 L4 用 output_validate 到文件系统验证（报告不是证据）"
          } else {
            @executor.executor_missing_hint(executor)
          }
          return mr_obj(
            [("ok", Json::boolean(okk))] +
            head +
            mr_opt_arr_field("cooldown_errors", cooldown_errors) +
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
  }
  // 不可达（每个分支要么 return，要么把 should_retry 置 true 继续循环）
  mr_obj([("ok", Json::boolean(false)), ("error", Json::string("unreachable"))])
}
