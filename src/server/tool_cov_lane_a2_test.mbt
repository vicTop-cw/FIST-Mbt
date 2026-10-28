/// tool_cov_lane_a2_test.mbt —— Lane A「纯计算族」工具行为锁（第二批 3 个）。
///
/// 覆盖：`mode_templates` / `github_issue_webhook_parse` / `executor_auction`。
/// 第一批（`staff_label_of` / `text_diff` / `audit_permission`）见
/// `tool_cov_lane_a_test.mbt`。
///
/// ## 与第一批的口径差异（判例-33：测配置这根线，不是测服务本体）
///
/// `mode_templates` 的已知坑是 **BUG-375**：判定基准曾是「server 进程 cwd」，
/// 于是业务项目目录下调用必然 **7/7 missing 误报**。修法是引入基准根
/// `FIST_MODE_TEMPLATES_ROOT`（env 优先、cwd 兜底）+ `template_probe_path` 产出
/// **探测绝对路径**。所以本文件不是「跑一遍看有没有模板」，而是**把环境变量这根线
/// 真的拧一遍**：设 env → 断言 root/probe 跟着变；清 env → 断言回落 cwd。
/// 齐全/缺失两种形状都用**自建临时根**造，不依赖本仓 `templates/` 在不在、cwd 是哪儿。
///
/// ## 诚实边界
///
/// 三个 handler 的 `Json::object({...})` 拼装行仍不可达（handler 体在
/// `run_server()` 内是匿名闭包，见第一批文件头与回传风险①）。
/// 本文件覆盖：`@ops.templates_root / template_probe_path / mode_template_path`、
/// `@server.github_webhook_parse`（该工具实现即 pub 顶层函数，**回执正文就是它的返回值**）、
/// `@executor.ExecutorRegistry::auction_pick`（回执正文即其返回 Json）。

///|
fn a2_must(cond : Bool, msg : String) -> Unit {
  if cond {
    ()
  } else {
    abort(msg)
  }
}

///|
/// 取 Json 对象字段（blackbox 测试用不了包内私有 `jget`）。
fn a2_field(j : Json, key : String) -> Json? {
  match j {
    Json::Object(m) => m.get(key)
    _ => None
  }
}

///|
fn a2_str(j : Json, key : String) -> String {
  match a2_field(j, key) {
    Some(Json::String(s)) => s
    _ => "<缺 String 字段 " + key + ">"
  }
}

///|
fn a2_num(j : Json, key : String) -> Double {
  match a2_field(j, key) {
    Some(Json::Number(n, ..)) => n
    _ => -1.0
  }
}

///|
fn a2_bool(j : Json, key : String) -> Bool {
  match a2_field(j, key) {
    Some(Json::True) => true
    _ => false
  }
}

// ─────────────────────────────────────────────────────────────────────────
// mode_templates（模板存在性预检 + BUG-375 基准根）
// ─────────────────────────────────────────────────────────────────────────

///|
/// 从模式注册表反解 mode 名（handler 用 `all_modes().map(get_str(_, "mode"))`，
/// 这里等价实现一份——blackbox 拿不到包内 get_str）。
fn a2_mode_names() -> Array[String] {
  let out : Array[String] = []
  for j in @ops.all_modes() {
    out.push(a2_str(j, "mode"))
  }
  out
}

///|
/// 【配置线 · 判例-33】基准根由 `FIST_MODE_TEMPLATES_ROOT` 决定，probe 必须挂在它下面。
///
/// ①设 env ⇒ `templates_root()` **逐字等于** env 值；
/// ②probe = root + "/" + `mode_template_path(mode)`（不是 cwd 相对路径，BUG-375 根因）；
/// ③清 env ⇒ 回落 cwd（**不缓存**上次 env，否则同进程后续调用全被污染）。
test "mode_templates：基准线——FIST_MODE_TEMPLATES_ROOT 决定 root 与 probe（BUG-375）" {
  let tmp = "temp/lane-a2-tpl-root"
  @env.set_env_var("FIST_MODE_TEMPLATES_ROOT", tmp)
  let root_under_env = @ops.templates_root()
  let probe_under_env = @ops.template_probe_path("advance")
  let rel = @ops.mode_template_path("advance")
  @env.unset_env_var("FIST_MODE_TEMPLATES_ROOT")
  let root_after_unset = @ops.templates_root()
  // ↑ 断言前已清 env：即便断言炸掉，也不会把 env 泄漏给同进程后续测试
  a2_must(
    root_under_env == tmp,
    "templates_root 应逐字取 env 值，实际 " + root_under_env,
  )
  a2_must(
    probe_under_env == tmp + "/" + rel,
    "probe 应为『基准根 + 注册表路径』，实际 " + probe_under_env,
  )
  a2_must(
    probe_under_env.has_prefix(tmp),
    "probe 必须挂在基准根下；若是 cwd 相对路径即 BUG-375 复发",
  )
  a2_must(
    root_after_unset != tmp,
    "清 env 后必须回落 cwd 基准，实际仍返回 " +
    root_after_unset +
    "（缓存了 env 值 ⇒ 业务目录下会误报 7/7 missing）",
  )
  a2_must(
    rel == "templates/pipeline_mode_advance.md",
    "模板相对路径应稳定，实际 " + rel,
  )
}

///|
/// 【齐全路径】自建临时根 + 写齐全部模板 ⇒ 逐 mode 命中、`missing` 为空。
///
/// 判定口径与 handler 逐字对齐：names 从 `all_modes()` 反解 → 每个 mode 用
/// `template_probe_path` 探测 → 缺失者进 missing。**不硬编码 7 个模式名**，
/// 注册表加模式而漏模板这里就会红。
test "mode_templates：模板齐全——注册表反解出的每个 mode 都命中、missing 为空" {
  let tmp = "temp/lane-a2-tpl-full"
  let names = a2_mode_names()
  @fs.create_dir(tmp) catch {
    _ => ()
  }
  @fs.create_dir(tmp + "/templates") catch {
    _ => ()
  }
  for n in names {
    let p = tmp + "/" + @ops.mode_template_path(n)
    @fs.write_string_to_file(p, "# " + n) catch {
      _ => ()
    }
  }
  @env.set_env_var("FIST_MODE_TEMPLATES_ROOT", tmp)
  let probes : Array[String] = []
  let exists : Array[Bool] = []
  let missing : Array[String] = []
  for n in names {
    let p = @ops.template_probe_path(n)
    let ok = @fs.path_exists(p)
    probes.push(p)
    exists.push(ok)
    if !ok {
      missing.push(n)
    }
  }
  @env.unset_env_var("FIST_MODE_TEMPLATES_ROOT")
  a2_must(
    names.length() == 7,
    "模式注册表应给 7 个 mode，实际 " + names.length().to_string(),
  )
  a2_must(
    missing.length() == 0,
    "模板齐全时 missing 应为空，实际 " +
    missing.length().to_string() +
    " 个: " +
    missing.join(","),
  )
  for i in 0..<names.length() {
    a2_must(
      exists[i],
      "mode " + names[i] + " 的探测路径不存在: " + probes[i],
    )
  }
  // 探测路径必须逐个 mode 不同（同一个路径 = 模板名硬编码漏了 mode）
  a2_must(
    probes[0] != probes[1],
    "两个 mode 的 probe 不应相同，实际都指向 " + probes[0],
  )
}

///|
/// 【缺失形状】空基准根 ⇒ 全部 mode missing，且回执里的 probe 是**可人工核对的绝对路径**。
///
/// 这正是 BUG-375 修复后的回执价值：用户可以照着 probes 去核，而不是盲改。
test "mode_templates：缺失形状——空根下 missing 列全、probes 为基准根下的可核对路径" {
  let tmp = "temp/lane-a2-tpl-empty"
  let names = a2_mode_names()
  @fs.create_dir(tmp) catch {
    _ => ()
  }
  // 反证：该根下确实没有 templates/ 目录（避免上一次跑残留导致本格假红）
  @fs.remove_file(tmp + "/templates/pipeline_mode_advance.md") catch {
    _ => ()
  }
  @env.set_env_var("FIST_MODE_TEMPLATES_ROOT", tmp)
  let probes : Array[String] = []
  let mut ok_count = 0
  let missing : Array[String] = []
  for n in names {
    let p = @ops.template_probe_path(n)
    let ok = @fs.path_exists(p)
    probes.push(p)
    if ok {
      ok_count = ok_count + 1
    } else {
      missing.push(n)
    }
  }
  let root = @ops.templates_root()
  @env.unset_env_var("FIST_MODE_TEMPLATES_ROOT")
  a2_must(
    missing.length() == names.length(),
    "空根下应全部 missing（" +
    names.length().to_string() +
    " 个），实际 " +
    missing.length().to_string(),
  )
  a2_must(
    ok_count == 0,
    "空根下不应有任何命中，实际命中 " + ok_count.to_string(),
  )
  a2_must(
    root == tmp,
    "回执 root 必须是调用时生效的基准根，实际 " + root,
  )
  for p in probes {
    a2_must(
      p.has_prefix(tmp),
      "missing 时回执的 probe 必须是基准根下的路径（供人工核对），实际 " +
      p,
    )
  }
}

// ─────────────────────────────────────────────────────────────────────────
// github_issue_webhook_parse（纯正则/前缀解析，零网络）
// ─────────────────────────────────────────────────────────────────────────

///|
/// 造一个 GitHub issue_comment webhook payload，并调真实现解析。
fn a2_wh(body : String) -> Json {
  let payload = "{\"comment\":{\"body\":\"" + body + "\"}}"
  match @server.github_webhook_parse(payload) {
    Ok(j) => j
    Err(m) =>
      abort("github_issue_webhook_parse 应解析成功，实际 Err: " + m)
  }
}

///|
/// 【正常路径】四类指令各自映射到 action，且带参指令的参数被剥离干净。
///
/// 回执正文**就是** `github_webhook_parse` 的返回值（handler 只做 stringify）。
test "github_issue_webhook_parse：四类指令——reopen/challenge/close/blocked 各归其位" {
  let reopen = a2_wh("@fist-bot reopen T-42")
  a2_must(
    a2_str(reopen, "action") == "reopen",
    "reopen 指令应得 action=reopen，实际 " + a2_str(reopen, "action"),
  )
  a2_must(
    a2_str(reopen, "task_id") == "T-42",
    "reopen 应剥离出 task_id=T-42，实际 " + a2_str(reopen, "task_id"),
  )
  let challenge = a2_wh("@fist-bot challenge")
  a2_must(
    a2_str(challenge, "action") == "challenge",
    "challenge 指令应得 action=challenge，实际 " +
    a2_str(challenge, "action"),
  )
  let close = a2_wh("@fist-bot close")
  a2_must(
    a2_str(close, "action") == "close",
    "close 指令应得 action=close，实际 " + a2_str(close, "action"),
  )
  let blocked = a2_wh("@fist-bot blocked 依赖未就绪")
  a2_must(
    a2_str(blocked, "action") == "blocked",
    "blocked 指令应得 action=blocked，实际 " + a2_str(blocked, "action"),
  )
  a2_must(
    a2_str(blocked, "reason") == "依赖未就绪",
    "blocked 应剥离出 reason，实际 " + a2_str(blocked, "reason"),
  )
}

///|
/// 【负例】无 `@fist-bot` ⇒ 无 action（折成 none，不误报指令）；
/// 空 payload / 非法 JSON ⇒ 显式 Err 且文案点名工具与原因。
test "github_issue_webhook_parse：负例——非指令/空/坏 JSON 都不产生动作" {
  let plain = a2_wh("这个问题我看看")
  a2_must(
    a2_str(plain, "action") == "none",
    "无 @fist-bot 应得 action=none，实际 " + a2_str(plain, "action"),
  )
  a2_must(
    a2_str(plain, "raw") == "这个问题我看看",
    "raw 应回显原评论正文（供排查），实际 " +
    a2_str(plain, "raw"),
  )
  match @server.github_webhook_parse("") {
    Ok(_) =>
      abort("空 payload 必须报错，不能返回 action=none 混过去")
    Err(m) =>
      a2_must(
        m.contains("payload 不能为空"),
        "空 payload 的 Err 文案应点名原因，实际 " + m,
      )
  }
  match @server.github_webhook_parse("{not json") {
    Ok(_) => abort("非法 JSON 必须报错")
    Err(m) =>
      a2_must(
        m.contains("不是合法 JSON"),
        "坏 JSON 的 Err 文案应点名原因，实际 " + m,
      )
  }
  // 合法 JSON 但没有 comment.body（如只带 issue 字段）⇒ 退化为 none，不崩
  let no_body = a2_wh("")
  a2_must(
    a2_str(no_body, "action") == "none",
    "空评论正文应得 action=none，实际 " + a2_str(no_body, "action"),
  )
}

///|
/// 【变体】首尾空白被容忍（`body.trim()`）；但**大小写敏感**、reopen 缺 task_id 不成立。
///
/// 这三条是真实契约，不是猜的：`trimmed.has_prefix("@fist-bot …")` 逐字匹配。
test "github_issue_webhook_parse：变体——空白容忍、大小写敏感、reopen 缺参不成立" {
  let spaced = a2_wh("  @fist-bot close  ")
  a2_must(
    a2_str(spaced, "action") == "close",
    "首尾空白应被 trim 后仍识别为 close，实际 " +
    a2_str(spaced, "action"),
  )
  a2_must(
    a2_str(spaced, "raw") == "@fist-bot close",
    "raw 应为 trim 后的正文，实际 [" + a2_str(spaced, "raw") + "]",
  )
  let upper = a2_wh("@FIST-BOT close")
  a2_must(
    a2_str(upper, "action") == "none",
    "指令前缀大小写敏感 ⇒ @FIST-BOT 不应被识别，实际 " +
    a2_str(upper, "action"),
  )
  let no_id = a2_wh("@fist-bot reopen")
  a2_must(
    a2_str(no_id, "action") == "none",
    "reopen 缺 task_id 时前缀不成立（要求尾部空格+参数）⇒ action=none，实际 " +
    a2_str(no_id, "action"),
  )
}

// ─────────────────────────────────────────────────────────────────────────
// executor_auction（置信度校准拍卖，R87 Agora）
// ─────────────────────────────────────────────────────────────────────────

///|
/// 造负载表。
fn a2_load(pairs : Array[(String, Int32)]) -> Map[String, Int32] {
  let m : Map[String, Int32] = Map([])
  for kv in pairs {
    ignore(m.set(kv.0, kv.1))
  }
  m
}

///|
/// 造信任表（历史验收通过率）。
fn a2_trust(pairs : Array[(String, Double)]) -> Map[String, Double] {
  let m : Map[String, Double] = Map([])
  for kv in pairs {
    ignore(m.set(kv.0, kv.1))
  }
  m
}

///|
/// 造显式出价表。
fn a2_bid(pairs : Array[(String, Double)]) -> Map[String, Double] {
  let m : Map[String, Double] = Map([])
  for kv in pairs {
    ignore(m.set(kv.0, kv.1))
  }
  m
}

///|
fn a2_no_load() -> Map[String, Int32] {
  Map([])
}

///|
/// 【正常路径】两个都覆盖 need，负载轻的胜出；basis/note 给出可核对依据。
test "executor_auction：正常路径——负载折扣决定 winner（重载方落败）" {
  let reg = @executor.ExecutorRegistry::new()
    .add_ability("agent-fast", ["json", "编排"])
    .add_ability("agent-heavy", ["json", "db"])
  let load = a2_load([("agent-fast", 3), ("agent-heavy", 0)])
  let trust = a2_trust([("agent-fast", 0.5), ("agent-heavy", 0.5)])
  let j = reg.auction_pick("json", load, trust, Map([]))
  a2_must(
    a2_num(j, "count") == 2.0,
    "两个执行者都覆盖 json ⇒ count 应为 2，实际 " +
    a2_num(j, "count").to_string(),
  )
  let winner = match a2_field(j, "winner") {
    Some(w) => w
    None => abort("executor_auction 回执缺 winner 字段")
  }
  a2_must(
    a2_str(winner, "name") == "agent-heavy",
    "负载 0 的 agent-heavy 应胜出，实际 " + a2_str(winner, "name"),
  )
  // 默认出价=能力覆盖率=1.0，trust=0.5 ⇒ 校准=1-|1.0-0.5|=0.5，load=0 ⇒ score=0.5
  a2_must(
    a2_num(winner, "load") == 0.0 &&
    a2_num(winner, "score") > 0.49 &&
    a2_num(winner, "score") < 0.51,
    "胜者应为 load=0 且 score=1.0×0.5×1.0=0.5，实际 load=" +
    a2_num(winner, "load").to_string() +
    " score=" +
    a2_num(winner, "score").to_string(),
  )
  a2_must(
    a2_str(j, "basis").contains("1/(1+负载)"),
    "basis 应写明负载折扣口径，实际 " + a2_str(j, "basis"),
  )
}

///|
/// 【边界】无人具备该能力 ⇒ count=0、winner=null、note 说明原因（不是静默给一个赢家）。
test "executor_auction：边界——无人覆盖 need 时 count=0 且 winner 为 null" {
  let reg = @executor.ExecutorRegistry::new().add_ability("agent-fast", ["json"])
  let j = reg.auction_pick("golang", a2_no_load(), Map([]), Map([]))
  a2_must(
    a2_num(j, "count") == 0.0,
    "无人覆盖 golang ⇒ count 应为 0，实际 " +
    a2_num(j, "count").to_string(),
  )
  match a2_field(j, "winner") {
    Some(Json::Null) =>
      a2_must(
        a2_str(j, "note").contains("无能力覆盖"),
        "note 应说明无人可竞拍，实际 " + a2_str(j, "note"),
      )
    Some(_) =>
      abort("无人覆盖时 winner 必须是 null，不能给出一个赢家")
    None => abort("executor_auction 回执缺 winner 字段")
  }
}

///|
/// 【校准 · 防胜者诅咒】同负载下，出价高于历史兑现率者被折扣，诚实者胜出。
///
/// boast：bid=1.0、trust=0.2 ⇒ 校准 0.2、score 0.2；
/// honest：bid=0.5、trust=0.5 ⇒ 校准 1.0、score 0.5 ⇒ honest 胜。
test "executor_auction：校准——过度自信者的折扣直接改变 winner" {
  let reg = @executor.ExecutorRegistry::new()
    .add_ability("boast", ["json"])
    .add_ability("honest", ["json"])
  let trust = a2_trust([("boast", 0.2), ("honest", 0.5)])
  let bid = a2_bid([("boast", 1.0), ("honest", 0.5)])
  let j = reg.auction_pick("json", a2_no_load(), trust, bid)
  let winner = match a2_field(j, "winner") {
    Some(w) => w
    None => abort("executor_auction 回执缺 winner 字段")
  }
  a2_must(
    a2_str(winner, "name") == "honest",
    "同负载下诚实出价者应胜出（校准防胜者诅咒），实际 " +
    a2_str(winner, "name"),
  )
  // 逐条核对 boast 的校准与 overconfident 标记（回执 bids 全表）
  let mut checked_boast = false
  match a2_field(j, "bids") {
    Some(Json::Array(rows)) =>
      for row in rows {
        if a2_str(row, "name") == "boast" {
          checked_boast = true
          a2_must(
            a2_bool(row, "overconfident"),
            "boast 的 overconfident 应为 true",
          )
          a2_must(
            a2_num(row, "calibration") > 0.19 &&
            a2_num(row, "calibration") < 0.21,
            "boast 校准应为 1-|1.0-0.2|=0.2，实际 " +
            a2_num(row, "calibration").to_string(),
          )
        }
      }
    _ => abort("executor_auction 回执 bids 应为数组")
  }
  a2_must(
    checked_boast, "bids 全表里应能看到 boast 这一行（用于核对折扣）",
  )
}
