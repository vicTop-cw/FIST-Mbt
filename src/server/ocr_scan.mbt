///|
/// ocr_scan.mbt —— ocr-local OCR CLI 集成（MCP 工具 ocr_scan）
///
/// 与 issue_scan 形成"内建规则 + OCR LLM review"双轨。封装 open-code-review CLI
/// （@alibaba-group/ocr-win32-x64 的 opencodereview.exe，命令名 ocr）的
/// scan / delegate / rules 子命令，让 bugfind 的 require_ocr 约束键从空头支票变默认可达的真实能力。
///
/// 平台约束：OCR 二进制是宿主依赖（windows-x64 only），不随本仓发布；native 构建经
/// run_check_external 的 native 桩自然返回 unsupported_target 形状的 Err。不可用时
/// 显式降级为"只用 issue_scan"，回执含 ocr_available=false，绝不静默成功。
///
/// 安全边界：argv 不经 shell（复用 run_check_external 的 spawn(cmd, args) 固定模式），
/// project_dir 过 ocr_dir_ok（拒绝对称/穿越/盘符）；二进制只由 env FIST_OCR_BIN 或
/// 固定相邻模式给出，调用方不能借本工具注入任意命令。

///|
/// 子命令白名单（与 open-code-review CLI 实测子命令对齐）
pub fn ocr_subcmds() -> Array[String] {
  ["scan", "files", "delegate", "rules"]
}

///|
/// 校验 subcmd 是否在白名单内
pub fn is_ocr_subcmd(s : String) -> Bool {
  ocr_subcmds().contains(s)
}

///|
/// OCR 二进制不可用时的可诊断提示（不得静默成功）
pub fn ocr_missing_hint() -> String {
  "OCR 二进制（opencodereview.exe，@alibaba-group/ocr-win32-x64）不可用。请安装 ocr-local 并把它放在 " +
  ocr_join("..", "ocr-local") +
  "（或设 env FIST_OCR_BIN 指向 opencodereview.exe 绝对路径）。本工具不会替你安装依赖，也不会静默返回成功。"
}

///|
/// 简单路径拼接（目录 + 名字，避免双斜杠；"." 与空串视为当前目录）
fn ocr_join(dir : String, name : String) -> String {
  if dir.is_empty() || dir == "." {
    return name
  }
  let last = dir[dir.length() - 1]
  if last == '/' || last == '\\' {
    return dir + name
  }
  dir + "/" + name
}

///|
/// 校验 project_dir：拒绝空串 / 绝对路径 / 路径穿越（与 issue_scan 同款防御）
fn ocr_dir_ok(dir : String) -> Bool {
  if dir.is_empty() {
    return false
  }
  if dir.contains("..") {
    return false
  }
  let c0 = dir[0]
  if c0 == '/' || c0 == '\\' {
    return false
  }
  if dir.length() >= 2 && dir[1] == ':' {
    return false
  }
  true
}

///|
/// 在给定 pnpm 目录下 glob 探测 opencodereview.exe
/// （.pnpm 下形如 @alibaba-group+ocr-win32-x64@<ver> 的目录）。
fn ocr_glob_binary(root : String) -> String? {
  let names = @fs.read_dir(root) catch { _ => return None }
  for name in names {
    if name.has_prefix("@alibaba-group+ocr-win32-x64") {
      let p = root +
        "/" +
        name +
        "/node_modules/@alibaba-group/ocr-win32-x64/bin/opencodereview.exe"
      if @fs.path_exists(p) {
        return Some(p)
      }
    }
  }
  None
}

///|
/// OCR 二进制路径探测（优先级）：
///   1) env FIST_OCR_BIN（非空且存在）
///   2) {project_dir}/../ocr-local/node_modules/.pnpm（glob）
///   3) {project_dir}/ocr-local/node_modules/.pnpm（glob）
/// 返回 None 表示不可用（调用方降级并标注 ocr_available=false）。
/// 探测路径是固定相邻模式，不经 ocr_dir_ok（那是 project_dir 的防御，不是探测的）。
pub fn ocr_probe_binary(project_dir : String) -> String? {
  let env_bin = match @env.get_env_var("FIST_OCR_BIN") {
    Some(b) => b
    None => ""
  }
  if env_bin.trim().length() > 0 && @fs.path_exists(env_bin) {
    return Some(env_bin)
  }
  let roots = [
    // ocr-local 与 FIST-Mbt 同处 AI 根下（FIST-Mbt 的上一级），相对 server 进程 cwd（FIST-Mbt 根）
    // 走 ".." 一级即可命中；不拼 project_dir（project_dir 是仓库内子目录，会少一级）。
    ocr_join("..", "ocr-local/node_modules/.pnpm"),
    ocr_join(project_dir, "ocr-local/node_modules/.pnpm"),
  ]
  for root in roots {
    let found = ocr_glob_binary(root)
    if found.is_some() {
      return found
    }
  }
  None
}

///|
/// argv 构造（纯计算，不经过 shell）：返回 Result，非法输入显式 Err（不猜测、不降级）。
/// 子命令形状与 open-code-review CLI 实测对齐：
///   scan/files : ocr scan --repo <repo> --preview --format json [--path <path>] [--rule <rules>]
///   delegate   : ocr delegate rule --repo <repo> [--rule <rules>] <path...>
///   rules      : ocr rules check <path>
pub fn ocr_build_args(
  project_dir~ : String,
  subcmd~ : String,
  path? : String = "",
  rules_file? : String = "",
) -> Result[Array[String], String] {
  if not(is_ocr_subcmd(subcmd)) {
    return Err(
      "ocr_scan: 未知子命令 '" +
      subcmd +
      "'，可用：" +
      ocr_subcmds().join(", "),
    )
  }
  let mut args : Array[String] = []
  match subcmd {
    "scan" | "files" => {
      args = ["scan", "--repo", project_dir, "--preview", "--format", "json"]
      if path.trim().length() > 0 {
        args = args + ["--path", path]
      }
      if rules_file.trim().length() > 0 {
        args = args + ["--rule", rules_file]
      }
    }
    "delegate" => {
      if path.trim().length() == 0 {
        return Err(
          "ocr_scan: delegate 子命令需要 path（逗号分隔的文件列表）",
        )
      }
      args = ["delegate", "rule", "--repo", project_dir]
      if rules_file.trim().length() > 0 {
        args = args + ["--rule", rules_file]
      }
      for p in path.split(",") {
        let t = p.trim().to_string()
        if t.length() > 0 {
          args = args + [t]
        }
      }
    }
    "rules" => {
      if path.trim().length() == 0 {
        return Err(
          "ocr_scan: rules 子命令需要 path（单个文件，repo 相对）",
        )
      }
      args = ["rules", "check", path]
    }
    _ => return Err("ocr_scan: 未知子命令（内部异常）")
  }
  Ok(args)
}

///|
/// 从 OCR scan 的 stdout JSON 里提取 files[].path 列表（解析失败返回空数组，不报错）
fn ocr_extract_files(stdout : String) -> Array[String] {
  let j = @json.parse(stdout) catch { _ => return [] }
  match j {
    Json::Object(m) =>
      match m.get("files") {
        Some(Json::Array(a)) => {
          let out : Array[String] = []
          for item in a {
            match item {
              Json::Object(f) =>
                match f.get("path") {
                  Some(Json::String(p)) => out.push(p)
                  _ => ()
                }
              _ => ()
            }
          }
          out
        }
        _ => []
      }
    _ => []
  }
}

///|
/// 统一构造回执 JSON（键顺序稳定，便于测试断言）
fn ocr_obj(pairs : Array[(String, Json)]) -> Json {
  let m : Map[String, Json] = Map([])
  for p in pairs {
    m.set(p.0, p.1)
  }
  Json::object(m)
}

///|
/// 失败回执（ocr_available=false，含 hint）
fn ocr_fail(
  subcmd : String,
  msg : String,
  hint : String,
  extra : Array[(String, Json)],
) -> Json {
  ocr_obj(
    [
      ("ok", Json::boolean(false)),
      ("ocr_available", Json::boolean(false)),
      ("subcmd", Json::string(subcmd)),
      ("error", Json::string(msg)),
      ("hint", Json::string(hint)),
    ] +
    extra,
  )
}

///|
/// ocr_plan —— 校验 + argv 构造 + dry_run 回显 + 二进制探测（sync，纯逻辑，不 spawn）。
/// 返回三种回执：
///   1) 终态失败（非法入参 / 二进制不可用）→ ok=false, ocr_available=false
///   2) dry_run 回显 → ok=true, dry_run=true, args=[...]
///   3) 待 spawn → ok=true, dry_run=false, binary="...", args=[...], subcmd="..."
pub fn ocr_plan(
  project_dir : String,
  subcmd~ : String,
  path? : String = "",
  rules_file? : String = "",
  dry_run? : Bool = false,
) -> Json {
  if not(ocr_dir_ok(project_dir)) {
    return ocr_fail(
      subcmd,
      "ocr_scan: 非法 project_dir（拒绝绝对路径/穿越/盘符）",
      "project_dir 必须是仓库相对路径（如 . 或 src）",
      [],
    )
  }
  if not(is_ocr_subcmd(subcmd)) {
    return ocr_fail(
      subcmd,
      "ocr_scan: 未知子命令 '" + subcmd + "'",
      "可用子命令：" + ocr_subcmds().join(", "),
      [],
    )
  }
  let args = match ocr_build_args(project_dir~, subcmd~, path~, rules_file~) {
    Err(e) => return ocr_fail(subcmd, e, "修正参数后重试", [])
    Ok(a) => a
  }
  let args_json = Json::array(args.map(fn(a) { Json::string(a) }))
  if dry_run {
    // 只回显"将要执行的 argv"，一个进程都不起：宿主命令能力默认收紧，
    // 让运维能在真跑之前逐字审命令。
    let bin_hint = match ocr_probe_binary(project_dir) {
      Some(b) => b
      None => ""
    }
    return ocr_obj([
      ("ok", Json::boolean(true)),
      ("ocr_available", Json::boolean(true)),
      ("dry_run", Json::boolean(true)),
      ("executed", Json::boolean(false)),
      ("subcmd", Json::string(subcmd)),
      ("stdout", Json::string("")),
      ("stderr", Json::string("")),
      ("exit_code", Json::number(0.0)),
      ("args", args_json),
      ("binary", Json::string(bin_hint)),
      (
        "hint",
        Json::string(
          "dry_run 未启动任何进程；去掉 dry_run 才会真跑 opencodereview.exe（argv 只作为参数，不经 shell）",
        ),
      ),
    ])
  }
  let bin = match ocr_probe_binary(project_dir) {
    Some(b) => b
    None =>
      return ocr_fail(
        subcmd,
        "ocr_scan: OCR 二进制不可用",
        ocr_missing_hint(),
        [("args", args_json)],
      )
  }
  ocr_obj([
    ("ok", Json::boolean(true)),
    ("dry_run", Json::boolean(false)),
    ("ocr_available", Json::boolean(true)),
    ("subcmd", Json::string(subcmd)),
    ("binary", Json::string(bin)),
    ("args", args_json),
  ])
}

///|
/// ocr_scan 主入口（async）：先走 ocr_plan（校验/argv/探测），再 spawn 真实进程。
/// dry_run=true 或校验失败时直接把 plan 回执返回，一个进程都不起。
pub async fn ocr_scan_impl(
  project_dir : String,
  subcmd~ : String,
  path? : String = "",
  rules_file? : String = "",
  timeout_ms? : Int = 180000,
  dry_run? : Bool = false,
) -> Json {
  let plan = ocr_plan(project_dir, subcmd~, path~, rules_file~, dry_run~)
  let pm : Map[String, Json] = match plan {
    Json::Object(mm) => mm
    _ => return plan
  }
  let okk = match pm.get("ok") {
    Some(Json::True) => true
    _ => false
  }
  let is_dry = match pm.get("dry_run") {
    Some(Json::True) => true
    _ => false
  }
  if not(okk) || is_dry {
    return plan
  }
  let bin = match pm.get("binary") {
    Some(Json::String(s)) => s
    _ => return plan
  }
  let args = match pm.get("args") {
    Some(Json::Array(a)) =>
      a.map(fn(v) {
        match v {
          Json::String(s) => s
          _ => ""
        }
      })
    _ => return plan
  }
  let args_json = Json::array(args.map(fn(a) { Json::string(a) }))
  let res = run_check_external(bin, args, ".", timeout_ms)
  match res {
    Err(e) =>
      ocr_fail(
        subcmd,
        "ocr_scan: OCR CLI 调度失败：" + e,
        "native 构建不支持 spawn；请在 node 运行时下启动 fist-mbt server",
        [("binary", Json::string(bin)), ("args", args_json)],
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
      let stdout = match jm.get("stdout") {
        Some(Json::String(s)) => s
        _ => ""
      }
      let stderr = match jm.get("stderr") {
        Some(Json::String(s)) => s
        _ => ""
      }
      let errtxt = match jm.get("error") {
        Some(Json::String(s)) => s
        _ => ""
      }
      let files = if subcmd == "files" && okk {
        ocr_extract_files(stdout)
      } else {
        []
      }
      ocr_obj(
        [
          ("ok", Json::boolean(okk)),
          ("ocr_available", Json::boolean(true)),
          ("subcmd", Json::string(subcmd)),
          ("binary", Json::string(bin)),
          ("exit_code", Json::number(code.to_double())),
          ("stdout", Json::string(stdout)),
          ("stderr", Json::string(stderr)),
          ("error", Json::string(errtxt)),
          ("args", args_json),
        ] +
        [("files", Json::array(files.map(fn(f) { Json::string(f) })))],
      )
    }
  }
}
