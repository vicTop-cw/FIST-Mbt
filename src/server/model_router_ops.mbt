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
  let now = now_default()
  let (r, warns) = @router.router_restore(mr_read(project_dir, ns), config~)
  let dec = if record_model.is_empty() {
    r.pick(now~)
  } else {
    r.record_call(model=record_model, now~)
  }
  let save_res = mr_save(r, project_dir, ns)
  let persisted = match save_res {
    Ok(_) => true
    Err(_) => false
  }
  let mut items : Array[(String, Json)] = [
    ("ok", Json::boolean(dec.available)),
    ("stamped_at", Json::string(now)),
    ("decision", dec.to_json()),
    ("usage", r.usage_report()),
    ("warnings", mr_warn_arr(warns)),
    ("persisted", Json::boolean(persisted)),
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
/// 用路由结果跑外部执行器（工具 `executor_run` 的实现体）。
/// 没显式给 model 时，先向路由器要一个模型并记账 —— 路由↔执行器的接线点。
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
          }
          _ =>
            return fail(
              "路由返回体不是对象（内部异常），未启动执行器",
              [],
            )
        }
    }
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
