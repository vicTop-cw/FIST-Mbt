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
    if found is Some(_) {
      return found
    }
  }
  None
}

///|
/// T0r588（P0 诊断结论）：`.mbt` 放行规则的 JSON 正文。
///
/// 为什么不是"认命"：OCR 的扩展名白名单是 `go:embed supported_file_types.json`
/// 内嵌进二进制的（源码 internal/config/allowlist/allowed_ext.go 只读 embed，
/// 运行时**没有** env / 配置文件可改），所以「把 .mbt 加进白名单」这条路不存在。
/// 但 `--rule <json>` 属于**最高优先级**的 custom 层，其 `include` glob 在扩展名
/// 白名单**之前**短路放行——internal/scan/agent.go 的 whyExcluded 顺序是
/// `HasInclude() && IsUserIncluded(path) ⇒ ExcludeNone`，先于
/// `IsAllowedExt(ext) ⇒ ExcludeExtension`。故本仓走"合法放行"而非"接受不可达"。
///
/// `rules: []` 是刻意的：不含任何 per-path 规则 ⇒ composedResolver.Resolve 在第一层
/// 匹配不到 entry，自然落到 system 层，系统评审规则一条都不丢（不会因为注入而静默降质）。
pub fn ocr_mbt_include_rule_json() -> String {
  "{\n  \"rules\": [],\n  \"include\": [\"**/*.mbt\"]\n}\n"
}

///|
/// path（逗号分隔的文件/目录列表）里是否点名了 .mbt 目标。
pub fn ocr_path_has_mbt(path : String) -> Bool {
  for p in path.split(",") {
    if p.trim().has_suffix(".mbt") {
      return true
    }
  }
  false
}

///|
/// 是否需要自动注入 .mbt 放行规则（纯计算，决策与 IO 分离以便白盒锁）：
///   - 显式给了 rules_file ⇒ false：custom 层只有一格，注入会抢掉用户自己的规则文件。
///     此时不假装能审，改由 fake-green 检测 + 兜底提示如实报不可达（fail-closed）。
///   - 目标点名 .mbt ⇒ true
///   - 目标项目是 MoonBit 项目（根有 moon.mod）⇒ true（目录/全仓扫描同样被白名单拦）
pub fn ocr_needs_mbt_include(
  path : String,
  rules_file : String,
  moonbit_project : Bool,
) -> Bool {
  if rules_file.trim().length() > 0 {
    return false
  }
  if ocr_path_has_mbt(path) {
    return true
  }
  moonbit_project
}

///|
/// 系统临时目录（TEMP > TMPDIR > TMP）。都拿不到返回 None——绝不退化成往
/// 工作树里写文件（那会污染用户仓库）。
fn ocr_temp_dir() -> String? {
  for k in ["TEMP", "TMPDIR", "TMP"] {
    match @env.get_env_var(k) {
      Some(v) => {
        let t = v.trim()
        if t.length() > 0 {
          return Some(t.to_owned())
        }
      }
      None => ()
    }
  }
  None
}

///|
/// 幂等落盘 .mbt 放行规则到系统临时目录，返回可传给 `--rule` 的路径；
/// 无临时目录或写盘失败返回 None（调用方据此记 mbt_include_error，并照旧
/// 走 fake-green fail-closed —— 写不进去不等于"审过了"）。
/// 文件名固定 ⇒ 并发重复调用是同一份内容，覆盖写无副作用。
fn ocr_ensure_mbt_include_rule() -> String? {
  let dir = match ocr_temp_dir() {
    Some(d) => d
    None => return None
  }
  // 反斜杠统一成正斜杠：Windows 上两类分隔符都可接受，但混拼进 argv 更难排障。
  // 注意必须用 replace_all——String::replace 只换**第一处**（本仓实测：会留下
  // `C:/Users/<user>\AppData\Local\Temp/...` 这种混拼），replace_all 才是全量。
  let p = ocr_join(
    dir.replace_all(old="\\", new="/"),
    "fist-mbt-ocr-moonbit-include.json",
  )
  let r : Unit? = Some(
    @fs.write_string_to_file(p, ocr_mbt_include_rule_json(), encoding="utf8"),
  ) catch {
    _ => None
  }
  match r {
    Some(_) => if @fs.path_exists(p) { Some(p) } else { None }
    None => None
  }
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
  path~ : String = "",
  rules_file~ : String = "",
) -> Result[Array[String], String] {
  if !is_ocr_subcmd(subcmd) {
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
        let t = p.trim().to_owned()
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
/// 从 OCR stdout JSON 里取一个整数字段；键缺失或解析失败返回 -1（调用方据此
/// 区分「0 份」与「这个版本不给这个键」——证据制判据必须能分辨这两者）。
fn ocr_stdout_int(stdout : String, key : String) -> Int32 {
  if stdout.trim().is_empty() {
    return -1
  }
  let j = @json.parse(stdout) catch { _ => return -1 }
  match j {
    Json::Object(m) =>
      match m.get(key) {
        Some(Json::Number(n, ..)) => n.to_int()
        _ => -1
      }
    _ => -1
  }
}

///|
/// 把 ocr_plan 回执里的 .mbt 放行现场字段原样搬到最终回执（纯搬运，缺则略过）。
fn ocr_plan_mbt_pairs(pm : Map[String, Json]) -> Array[(String, Json)] {
  let out : Array[(String, Json)] = []
  for k in ["mbt_include", "mbt_include_rule", "mbt_include_error"] {
    match pm.get(k) {
      Some(v) => out.push((k, v))
      None => ()
    }
  }
  out
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
  path~ : String = "",
  rules_file~ : String = "",
  dry_run~ : Bool = false,
) -> Json {
  if !ocr_dir_ok(project_dir) {
    return ocr_fail(
      subcmd,
      "ocr_scan: 非法 project_dir（拒绝绝对路径/穿越/盘符）",
      "project_dir 必须是仓库相对路径（如 . 或 src）",
      [],
    )
  }
  if !is_ocr_subcmd(subcmd) {
    return ocr_fail(
      subcmd,
      "ocr_scan: 未知子命令 '" + subcmd + "'",
      "可用子命令：" + ocr_subcmds().join(", "),
      [],
    )
  }
  // T0r588：.mbt 放行——ASCII 白名单改不动，但 --rule 的 include 能短路放行。
  // 条件是"目标涉及 MoonBit 且用户没自己给规则文件"（见 ocr_needs_mbt_include）。
  // `rules` 子命令只 dump 某文件的规则、不做扩展名过滤 ⇒ 不为它落盘放行规则。
  let is_mbt_proj = @fs.path_exists(ocr_join(project_dir, "moon.mod"))
  let needs_inc = subcmd != "rules" &&
    ocr_needs_mbt_include(path, rules_file, is_mbt_proj)
  let mut eff_rules = rules_file
  let mut inc_path = ""
  let mut inc_err = ""
  if needs_inc {
    match ocr_ensure_mbt_include_rule() {
      Some(p) => {
        eff_rules = p
        inc_path = p
      }
      // 写不进放行规则：不静默、也不假装成功，只把原因带进回执，
      // 后续由 fake-green 检测把 ok 强制成 false。
      None =>
        inc_err = "ocr_scan: 无法落盘 .mbt 放行规则（无临时目录或写盘失败）；" +
          "OCR 内嵌扩展名白名单不含 .mbt，本次 LLM review 不会真正执行"
    }
  }
  let args = match
    ocr_build_args(project_dir~, subcmd~, path~, rules_file=eff_rules) {
    Err(e) => return ocr_fail(subcmd, e, "修正参数后重试", [])
    Ok(a) => a
  }
  let args_json = Json::array(args.map(fn(a) { Json::string(a) }))
  let inc_pairs : Array[(String, Json)] = [
      ("mbt_include", Json::boolean(inc_path != "")),
      ("mbt_include_rule", Json::string(inc_path)),
    ] +
    (if inc_err == "" {
      []
    } else {
      [("mbt_include_error", Json::string(inc_err))]
    })
  if dry_run {
    // 只回显"将要执行的 argv"，一个进程都不起：宿主命令能力默认收紧，
    // 让运维能在真跑之前逐字审命令。
    let bin_hint = match ocr_probe_binary(project_dir) {
      Some(b) => b
      None => ""
    }
    return ocr_obj(
      [
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
      ] +
      inc_pairs,
    )
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
  ocr_obj(
    [
      ("ok", Json::boolean(true)),
      ("dry_run", Json::boolean(false)),
      ("ocr_available", Json::boolean(true)),
      ("subcmd", Json::string(subcmd)),
      ("binary", Json::string(bin)),
      ("args", args_json),
    ] +
    inc_pairs,
  )
}

///|
/// 假绿检测（BUG-165）：scan/files 子命令对不在二进制扩展名白名单内的文件
/// （如 .mbt）会返回 exit_code=0 + ok=true 但 `reviewable_count:0`、且每份文件带
/// `exclude_reason:"unsupported_ext"` —— 调用方看回执以为 LLM review 跑过了，
/// 实际 0 份文件被评审。此函数解析 stdout，返回 (是否真有文件被评审, 说明文本)。
/// 解析失败保守返回 (true, "")，不误报。
fn ocr_fake_green_check(stdout : String) -> (Bool, String) {
  if stdout.trim().is_empty() {
    return (true, "")
  }
  let j = @json.parse(stdout) catch { _ => return (true, "") }
  match j {
    Json::Object(m) => {
      let reviewable = match m.get("reviewable_count") {
        Some(Json::Number(n, ..)) => n.to_int()
        _ => -1
      }
      let excluded = match m.get("excluded_count") {
        Some(Json::Number(n, ..)) => n.to_int()
        _ => 0
      }
      if reviewable < 0 {
        // 不是 scan/files 的 JSON 形状（如 delegate/rules 的 markdown），不判定
        return (true, "")
      }
      if reviewable > 0 {
        return (true, "")
      }
      if excluded <= 0 {
        return (true, "")
      }
      // reviewable_count == 0 且 excluded > 0：收集 exclude_reason 计数
      let reason_counts : Map[String, Int32] = Map([])
      match m.get("files") {
        Some(Json::Array(a)) =>
          for item in a {
            match item {
              Json::Object(f) =>
                match f.get("exclude_reason") {
                  Some(Json::String(r)) => {
                    let prev = match reason_counts.get(r) {
                      Some(n) => n
                      None => 0
                    }
                    reason_counts.set(r, prev + 1)
                  }
                  _ => ()
                }
              _ => ()
            }
          }
        _ => ()
      }
      if reason_counts.is_empty() {
        return (true, "")
      }
      let parts : Array[String] = []
      for kv in reason_counts {
        parts.push("\{kv.0}(\{kv.1} 份)")
      }
      let prefix = "scan/files 回执 reviewable_count=0 但 excluded_count="
      let suffix = "：全部文件被二进制扩展名白名单拦下（"
      let tail = "），LLM review 未真正执行"
      (false, prefix + excluded.to_string() + suffix + parts.join("，") + tail)
    }
    _ => (true, "")
  }
}

///|
/// BUG-327：BUG-165 已在假绿时给出 ocr_reviewed=false + notice，但顶层 ok 仍按
/// exit_code 报 true，只看 ok 的调用方（含 bugfind 的 require_ocr 门）会把
/// 「0 份文件被评审」当成 OCR 成功。此处把「假绿 ⇒ ok 必须 false」抽成纯函数，
/// 供白盒锁（bugfind fail-closed 契约）。
pub fn ocr_effective_ok(okk : Bool, reviewed : Bool) -> Bool {
  okk && reviewed
}

///|
/// 单目标复核（T0r588 改为**证据制**，替代「见 .mbt 就恒 false」的旧一刀切）：
///
/// 旧的 BUG-327b 盲区是：单 .mbt 文件目标时 OCR 静默返回 `files:[] /
/// reviewable_count:0 / excluded_count:0`，与「空目录」同形 ⇒ 走空目录豁免
/// 判 reviewed=true（假绿）。但一刀切「目标带 .mbt 就 false」会**挡住已修好的
/// 真审查**（T0r588 注入 include 规则后，单 .mbt 文件真的会被评审）。
///
/// 证据制判据：目标点名 .mbt 时，必须看到回执里 `total_files >= 1`（该文件确实
/// 进了选择面）才算 reviewed；`total_files == 0`（静默丢弃）或 <0（回执无该键，
/// 版本差异）一律 fail-closed —— 宁可报不可达，不可谎报审过。
pub fn ocr_reviewed_final(
  stdout_reviewed : Bool,
  path : String,
  total_files : Int32,
) -> (Bool, String) {
  if !stdout_reviewed {
    return (false, "")
  }
  if !ocr_path_has_mbt(path) {
    return (true, "")
  }
  if total_files >= 1 {
    return (true, "")
  }
  (
    false,
    "目标点名了 .mbt 文件，但 OCR 回执未把它纳入选择面（total_files=" +
    total_files.to_string() +
    "）；LLM review 未真正执行，顶层 ok 已强制 fail-closed",
  )
}

///|
/// .mbt 未真审时的可执行修法提示（追加到 notice，让调用方知道下一步怎么做）。
/// 只在确实没审成时返回非空——审成了就不该再喊修法。
pub fn ocr_mbt_remedy(path : String, reviewed : Bool) -> String {
  if reviewed || !ocr_path_has_mbt(path) {
    return ""
  }
  "；修法：省略 rules_file 让 ocr_scan 自动注入 include 规则，或在你的规则 JSON 顶层加 \"include\": [\"**/*.mbt\"]"
}

///|
/// T0r588 修订：`.mbt` **不再恒不可达**。OCR 内嵌的扩展名白名单确实不含 .mbt
/// （go:embed，运行时改不动），但 `--rule` 的 include glob 优先级更高、能短路放行
/// （见 ocr_mbt_include_rule_json）。因此 MoonBit 目标的 gate 由 degraded 改为
/// satisfied —— 前提是 ocr_scan 会自动注入该规则。
///
/// 但 gate=satisfied 只表示"机制可达"，不表示"这一发真审了"：最终判据仍是单次
/// 回执的 ok / ocr_reviewed（reviewable_count 与 total_files 证据）。
pub fn ocr_gate_state(
  binary_available : Bool,
  moonbit_target : Bool,
) -> (String, String) {
  if !binary_available {
    return (
      "unavailable", "OCR 二进制不可用（windows-x64 only，宿主依赖）；bugfind 显式降级为只用 issue_scan，回执 ocr_available=false",
    )
  }
  if moonbit_target {
    return (
      "satisfied", "OCR 二进制可用；.mbt 不在二进制内嵌扩展名白名单里，但 ocr_scan 会自动注入 --rule 的 include 规则（**/*.mbt）短路放行（T0r588）。require_ocr 的最终判据是本发回执的 ok/ocr_reviewed，不能只看本 gate",
    )
  }
  (
    "satisfied", "OCR 二进制可用且目标非 MoonBit 项目；require_ocr 由 ocr_scan 回执的 ok/reviewed 字段判定",
  )
}

///|
/// bugfind 的 require_ocr 预检回执（IO 薄壳，pipeline_tick / watchdog_tick 共用）：
/// probe 二进制 + 判目标是否 MoonBit 项目（project_dir 根有 moon.mod）。
/// 纯读探测，不 spawn；新增字段对旧调用方是纯增量。
///
/// T0r588：`mbt_reviewable` 由恒 false 改为跟随二进制可用性——放行机制是
/// `--rule` 的 include glob（见 ocr_mbt_include_rule_json），由 ocr_scan 自动注入。
/// 这只是"机制可达"的声明；某一发到底审没审，看该发回执的 ocr_reviewed
/// （reviewable_count / total_files 证据）。本函数仍保持纯读：不写临时文件。
pub fn ocr_capability_json(project_dir : String) -> Json {
  let bin = ocr_probe_binary(project_dir)
  let is_mbt = @fs.path_exists(ocr_join(project_dir, "moon.mod"))
  let avail = bin is Some(_)
  let (gate, note) = ocr_gate_state(avail, is_mbt)
  let m : Map[String, Json] = Map([])
  m.set("available", Json::boolean(avail))
  match bin {
    Some(b) => m.set("binary", Json::string(b))
    None => ()
  }
  m.set("moonbit_target", Json::boolean(is_mbt))
  m.set("mbt_reviewable", Json::boolean(avail))
  m.set(
    "mbt_admission",
    Json::string(if avail { "rule-include" } else { "none" }),
  )
  m.set("gate", Json::string(gate))
  m.set("note", Json::string(note))
  Json::object(m)
}

///|
/// ocr_scan 主入口（async）：先走 ocr_plan（校验/argv/探测），再 spawn 真实进程。
/// dry_run=true 或校验失败时直接把 plan 回执返回，一个进程都不起。
pub async fn ocr_scan_impl(
  project_dir : String,
  subcmd~ : String,
  path~ : String = "",
  rules_file~ : String = "",
  timeout_ms~ : Int32 = 180000,
  dry_run~ : Bool = false,
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
  if !okk || is_dry {
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
      // BUG-165：scan/files 对白名单外扩展名（如 .mbt）会假绿——回执 ok=true 但
      // reviewable_count=0。这里把假绿显式摊到回执上，调用方不再误读为「已审完」。
      let (reviewed, fake_notice) = if subcmd == "scan" || subcmd == "files" {
        ocr_fake_green_check(stdout)
      } else {
        (true, "")
      }
      // T0r588：把证据读数摊到回执上（reviewable_count / total_files），
      // 让「到底几份进了选择面」不必调用方再解析 stdout。
      let reviewable_n = ocr_stdout_int(stdout, "reviewable_count")
      let total_n = ocr_stdout_int(stdout, "total_files")
      // 单 .mbt 目标复核改为证据制：必须看到 total_files>=1（见 ocr_reviewed_final）。
      let (reviewed2, evidence_notice) = ocr_reviewed_final(
        reviewed, path, total_n,
      )
      // BUG-327：假绿 fail-closed——reviewable_count=0 时顶层 ok 强制 false（见 ocr_effective_ok）。
      let ok_eff = ocr_effective_ok(okk, reviewed2)
      // 诊断面：假绿原因优先（它更接近根因），其次是单目标证据不足的原因；
      // 再补一条"下一步怎么修"的动作提示——只报失败不给修法等于半张回执。
      let mut notice = if fake_notice != "" {
        fake_notice
      } else {
        evidence_notice
      }
      let remedy = ocr_mbt_remedy(path, reviewed2)
      if remedy != "" {
        notice = notice + remedy
      }
      ocr_obj(
        [
          ("ok", Json::boolean(ok_eff)),
          ("ocr_available", Json::boolean(true)),
          ("subcmd", Json::string(subcmd)),
          ("binary", Json::string(bin)),
          ("exit_code", Json::number(code.to_double())),
          ("stdout", Json::string(stdout)),
          ("stderr", Json::string(stderr)),
          ("error", Json::string(errtxt)),
          ("args", args_json),
          ("ocr_reviewed", Json::boolean(reviewed2)),
          ("reviewable_count", Json::number(reviewable_n.to_double())),
          ("total_files", Json::number(total_n.to_double())),
        ] +
        (if notice == "" { [] } else { [("notice", Json::string(notice))] }) +
        // T0r588：.mbt 放行机制的现场留痕（注入没注入、注入了哪份规则），
        // 便于一次回执就判「不可达是机制问题还是写盘问题」。
        ocr_plan_mbt_pairs(pm) +
        [("files", Json::array(files.map(fn(f) { Json::string(f) })))],
      )
    }
  }
}
