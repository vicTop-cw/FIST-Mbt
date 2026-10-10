/// mcp_config_scaffold.mbt —— `mcp_config_scaffold` 的纯校验 + 生成逻辑（cl1）。
///
/// 设计原则（与 `project_standards.mbt` 同族：工具注册只做参数抽取与 IO，
/// 校验/生成全部下沉到可单测的纯函数）：
///   · `mcp_config_scaffold_impl` 是纯函数：给 `form_json` + `project_dir` + 未知键，
///     返回 `Err(reason)`（整笔拒绝）或 `Ok(返回体 JSON)`。白盒测试直接调它。
///   · 工具本身**不写目标项目文件**——HTML 写不了文件，落盘由调用方（agent / 安装器）做，
///     本工具只产出**可落盘的 `fist.mcp.json` 正文**。
///   · 硬门（负路径必须拒）：`form_json` 里任何键值出现**凭据形状**就整笔拒绝。
///     正确姿势是只写环境变量名占位（如 `{"FIST_MODEL_API_KEY":"$FIST_MODEL_API_KEY"}`），
///     真值走 server 进程环境变量（同 `executor_run` 的密钥纪律：不读 `.env`、不回显 key）。

///|
/// 环境变量白名单：配置里只允许出现这些名字（值一律是 `$NAME` 占位或 `"."` 这类路径，
/// 不许放真值）。`FIST_*_TOKEN` 等名字看着像凭据，但它们是**环境变量名**，
/// 值走进程环境——这与 `FIST_PROJECT_DIR` / `FIST_DB_PATH` 是同一类通道。
pub let mcp_env_whitelist : Array[String] = [
  "FIST_PROJECT_DIR",
  "FIST_DB_PATH",
  "FIST_GITHUB_ENABLED",
  "FIST_GITHUB_REPO",
  "FIST_GITHUB_TOKEN",
  "FIST_GITCODE_TOKEN",
  "FIST_GITCODE_PROJECT_ID",
  "FIST_MODEL_API_BASE",
  "FIST_MODEL_API_KEY",
  "FIST_RUN_CHECK_ALLOW",
  "FIST_SELF_OPENAI_BASE",
  "FIST_SELF_OPENAI_KEY",
  "ANTHROPIC_API_KEY",
  "OPENAI_API_KEY",
  "OPENAI_BASE_URL",
]

///|
/// 目标项目 MCP 配置表单字段白名单（HTML 配置页只会产出这些；其它键忽略并回显）。
pub let mcp_form_field_whitelist : Array[String] = [
  "serverName",
  "command",
  "args",
  "cwd",
  "toolCallTimeoutMs",
  "failOnStartupError",
  "reconnect",
  "env",
]

///|
/// 凭据形状判据（键名）：键名归一为小写后含下列子串即命中。
/// 覆盖 `api_key` / `apiKey` / `API_KEY` / `token` / `secret` / `authorization` /
/// `bearer` / `password` 等形态。
pub let mcp_cred_key_hits : Array[String] = [
  "api_key",
  "apikey",
  "token",
  "secret",
  "authorization",
  "bearer",
  "password",
]

///|
/// 凭据形状判据（值前缀 / 长令牌形状）：命中即视为真值泄漏。
pub let mcp_cred_value_hits : Array[String] = [
  "sk-", // OpenAI/Anthropic 风格 API key
  "bearer ", // "Bearer yyy"
  "ghp_", // GitHub personal access token
  "github_pat_", // GitHub fine-grained PAT
  "glpat-", // GitLab PAT
  "aiza", // Google API key（AIza...）
  "ya29.", // Google OAuth
  "xoxb-", // Slack bot token
  "xoxp-", // Slack user token
  "pk_live_", // Stripe live
  "rk_live_", // Stripe restricted
]

///|
///|
/// 2 空格缩进的漂亮打印（`Json::stringify()` 是紧凑形态；MCP 配置要人可读，
/// 但不引入额外依赖，故内联一个最小实现）。对象键按插入序输出，
/// 保证输出确定、可快照。
pub fn mcs_pretty(j : Json) -> String {
  mcs_pretty_at(j, 0)
}

///|
fn mcs_pretty_at(j : Json, depth : Int) -> String {
  let pad = "  ".repeat(depth)
  let child_pad = "  ".repeat(depth + 1)
  match j {
    Json::Object(map) =>
      if map.is_empty() {
        "{}"
      } else {
        let parts : Array[String] = []
        for (k, v) in map {
          parts.push(
            child_pad + mcs_quote(k) + ": " + mcs_pretty_at(v, depth + 1),
          )
        }
        "{\n" + parts.join(",\n") + "\n" + pad + "}"
      }
    Json::Array(arr) =>
      if arr.is_empty() {
        "[]"
      } else {
        let parts : Array[String] = []
        for v in arr {
          parts.push(child_pad + mcs_pretty_at(v, depth + 1))
        }
        "[\n" + parts.join(",\n") + "\n" + pad + "]"
      }
    Json::String(s) => mcs_quote(s)
    Json::Number(n, ..) => n.to_string()
    Json::True => "true"
    Json::False => "false"
    Json::Null => "null"
  }
}

///|
/// JSON 字符串转义（引号 / 反斜杠 / 控制符）。按字符处理，非 ASCII 原样保留。
fn mcs_escape_body(s : String) -> String {
  let mut out = ""
  for c in s {
    match c {
      '"' => out = out + "\\\""
      '\\' => out = out + "\\\\"
      '\n' => out = out + "\\n"
      '\r' => out = out + "\\r"
      '\t' => out = out + "\\t"
      '\b' => out = out + "\\b"
      '\u{0c}' => out = out + "\\f"
      _ =>
        if c.to_int() < 0x20 {
          out = out + "\\u" + mcs_hex4(c.to_int())
        } else {
          out = out + c.to_string()
        }
    }
  }
  out
}

///|
/// 4 位十六进制（补前导 0），用于 `\uXXXX` 控制符转义。
fn mcs_hex4(n : Int) -> String {
  let hex = "0123456789abcdef"
  let mut rem = n
  let mut out = ""
  while rem > 0 {
    let d = rem % 16
    out = hex.substring(start=d, end=d+1) + out
    rem = rem / 16
  }
  if out.length() >= 4 { out } else { "0".repeat(4 - out.length()) + out }
}

///|
/// ASCII 小写（MoonBit core 未提供 String::lowercase / Char::from_int；
/// 只做 A-Z → a-z，其余原样）。
fn mcs_lower(s : String) -> String {
  let upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  let lower = "abcdefghijklmnopqrstuvwxyz"
  let mut out = ""
  for c in s {
    let cs = c.to_string()
    let mut replaced = false
    for i in 0..<26 {
      if upper.substring(start=i, end=i+1) == cs {
        out = out + lower.substring(start=i, end=i+1)
        replaced = true
        break
      }
    }
    if !replaced {
      out = out + cs
    }
  }
  out
}

///|
/// 取字符串前 n 个字符（不足 n 则全取），用于脱敏回显。
fn mcs_head(s : String, n : Int) -> String {
  let mut i = 0
  let mut out = ""
  for c in s {
    if i >= n {
      break
    }
    out = out + c.to_string()
    i = i + 1
  }
  out
}

///|
/// 字符串带引号输出。
fn mcs_quote(s : String) -> String {
  "\"" + mcs_escape_body(s) + "\""
}

///|
/// 从 form JSON 的 Object 里取字符串值（无则返回 default）。
fn mcs_get_str(form : Json, key : String, default : String) -> String {
  match form {
    Json::Object(map) =>
      match map.get(key) {
        Some(Json::String(s)) => s
        _ => default
      }
    _ => default
  }
}

///|
/// 从 form JSON 的 Object 里取 Bool（无则返回 default）。
fn mcs_get_bool(form : Json, key : String, default : Bool) -> Bool {
  match form {
    Json::Object(map) =>
      match map.get(key) {
        Some(Json::True) => true
        Some(Json::False) => false
        _ => default
      }
    _ => default
  }
}

///|
/// 从 form JSON 的 Object 里取 toolCallTimeoutMs（非整数或不在 1..600000 → Err）。
fn mcs_get_timeout(form : Json, key : String) -> Result[Int, String] {
  match form {
    Json::Object(map) =>
      match map.get(key) {
        None => Ok(30000)
        Some(Json::Number(n, ..)) =>
          {
            let v = n.to_int()
            if n != v.to_double() {
              Err("toolCallTimeoutMs 必须是整数（收到 " + n.to_string() + "）")
            } else if v < 1 || v > 600000 {
              Err(
                "toolCallTimeoutMs 必须在 1..600000 之间（收到 " +
                v.to_string() +
                "）",
              )
            } else {
              Ok(v)
            }
          }
        Some(_) => Err("toolCallTimeoutMs 必须是整数")
      }
    _ => Ok(30000)
  }
}

///|
/// 从 form JSON 的 Object 里取 args 数组（非数组或未给 → 空数组）。
fn mcs_get_args(form : Json, key : String) -> Array[String] {
  match form {
    Json::Object(map) =>
      match map.get(key) {
        Some(Json::Array(arr)) =>
          arr.map(fn(v) {
            match v {
              Json::String(s) => s
              _ => ""
            }
          })
        _ => []
      }
    _ => []
  }
}

///|
/// serverName 白名单：`^[A-Za-z0-9_-]{1,32}$`（MoonBit 无内置正则，逐字符判定）。
pub fn mcs_valid_server_name(s : String) -> Bool {
  if s.is_empty() || s.length() > 32 {
    return false
  }
  for c in s {
    let ok = (c >= 'A' && c <= 'Z') ||
      (c >= 'a' && c <= 'z') ||
      (c >= '0' && c <= '9') ||
      c == '_' ||
      c == '-'
    if !ok {
      return false
    }
  }
  true
}

///|
/// 遍历整棵 JSON，命中凭据形状立即返回第一条原因（键名 / 值前缀 / 字面键三判据都走这里）。
/// 返回 Err(原因) 或 Ok("")。
/// `in_env=true` 表示当前处在 `form.env` 对象内部：此时**跳过键名判据①**——
/// env 里的 `ANTHROPIC_API_KEY` / `FIST_GITHUB_TOKEN` 是环境变量**名字**不是凭据，
/// 真值只走 server 进程环境变量；值判据②仍然生效（防真值误入）。
pub fn mcs_scan_credentials(j : Json) -> Result[String, String] {
  mcs_scan_credentials_ex(j, false)
}

/// 带 `in_env` 标记的递归主体（外部只调 `mcs_scan_credentials`）。
fn mcs_scan_credentials_ex(j : Json, in_env : Bool) -> Result[String, String] {
  match j {
    Json::Object(map) =>
      for (k, v) in map {
        // env 对象：键名是环境变量名，不做键名判据；进入后其值为「叶子/再下一层」
        let child_in_env = in_env || k == "env"
        // 判据 ① 键名（env 内跳过）
        if !in_env {
          let kl = mcs_lower(k)
          for hit in mcp_cred_key_hits {
            if kl.contains(hit) {
              return Err(
                "form 里出现凭据形状键「" +
                k +
                "」：配置里只写环境变量名占位，真值走 server 进程环境变量",
              )
            }
          }
        }
        // 判据 ② 值形状（先扫叶子再递归，避免漏掉对象里的字符串值）
        match mcs_scan_credentials_ex(v, child_in_env) {
          Err(e) => return Err(e)
          Ok(_) => ()
        }
      }
    Json::Array(arr) =>
      for v in arr {
        // 数组元素若是字符串，也要做「字面凭据键」判据（如 `args: ["token"]`）——
        // 数组不是 env，键名判据不能跳过（env 内数组仍走 in_env 传递）
        match v {
          Json::String(s) => {
            let sl = mcs_lower(s)
            for hit in mcp_cred_key_hits {
              if sl.contains(hit) {
                return Err(
                  "form 里出现凭据形状字面量「" +
                  s +
                  "」：配置里只写环境变量名占位，真值走 server 进程环境变量",
                )
              }
            }
          }
          _ => ()
        }
        match mcs_scan_credentials_ex(v, in_env) {
          Err(e) => return Err(e)
          Ok(_) => ()
        }
      }
    Json::String(s) =>
      for hit in mcp_cred_value_hits {
        if mcs_lower(s).contains(hit) {
          return Err(
            "form 里出现凭据形状值「" +
            mcs_redact(s) +
            "」：真值不要进配置，改为环境变量名占位（如 $FIST_GITHUB_TOKEN）",
          )
        }
      }
    _ => ()
  }
  Ok("")
}

///|
/// 凭据值回显时脱敏（只保留前 4 个字符，后接 …）。
fn mcs_redact(s : String) -> String {
  if s.length() <= 4 {
    "****"
  } else {
    mcs_head(s, 4) + "…"
  }
}

///|
/// 收集 form 里的未知键（不在白名单内的顶层键；`unknown_keys` 只回显给 HTML 页调试用）。
pub fn mcs_collect_unknown_keys(form : Json) -> Array[String] {
  match form {
    Json::Object(map) =>
      {
        let out : Array[String] = []
        for (k, _v) in map {
          let mut known = false
          for w in mcp_form_field_whitelist {
            if k == w {
              known = true
            }
          }
          if !known {
            out.push(k)
          }
        }
        out
      }
    _ => []
  }
}

///|
/// 环境变量对象的键白名单过滤：非白名单键收集进 `unknown_env_keys`。
pub fn mcs_filter_env(form : Json, unknown_env_keys : Array[String]) -> Result[
  Map[String, String],
  String,
] {
  let out : Map[String, String] = Map([])
  match form {
    Json::Object(map) =>
      for (k, v) in map {
        let mut whitelisted = false
        for w in mcp_env_whitelist {
          if k == w {
            whitelisted = true
          }
        }
        if !whitelisted {
          unknown_env_keys.push(k)
          continue
        }
        let val = match v {
          Json::String(s) => s
          _ => ""
        }
        out.set(k, val)
      }
    _ => ()
  }
  Ok(out)
}

///|
/// 从 form 的 reconnect 对象取整数子字段（缺省回退 default，非法值钳到 default）。
fn mcs_get_reconnect_int(form : Json, key : String, default : Int) -> Int {
  match form {
    Json::Object(map) =>
      match map.get(key) {
        Some(Json::Number(n, ..)) =>
          {
            let v = n.to_int()
            if v <= 0 { default } else { v }
          }
        _ => default
      }
    _ => default
  }
}

///|
/// 纯校验 + 生成（白盒测试直接调这里；工具注册只做参数抽取）。
///   form_json：HTML 配置页产出的偏好 JSON 文本
///   project_dir：目标项目目录（空则回退 "."）
///   unknown_keys：调用方先 `mcs_collect_unknown_keys` 收集的顶层未知键（回显用）
/// 返回 `Err(reason)`（整笔拒绝，含硬门）或 `Ok(返回体 Json)`。
pub fn mcp_config_scaffold_impl(
  form_json : String,
  project_dir : String,
  unknown_keys : Array[String],
) -> Result[Json, String] {
  // 空字符串直接拒（不静默用默认值跑出一个"看起来正常"的配置）
  if form_json.trim().is_empty() {
    return Err("form_json 不能为空（至少传 {}）")
  }

  // 非法 JSON 直接拒
  let form = @json.parse(form_json) catch {
    _ =>
      return Err("form_json 不是合法 JSON：请检查引号/逗号配平（可用 JSON.parse 先验一遍）")
  }

  // 顶层必须是对象
  match form {
    Json::Object(_) => ()
    _ => return Err("form_json 顶层必须是 JSON 对象")
  }

  // —— 硬门：凭据形状（键名 / 值前缀 / 字面键；整笔拒绝）——
  match mcs_scan_credentials(form) {
    Err(reason) => return Err(reason)
    Ok(_) => ()
  }

  // —— serverName ——
  let server_name = mcs_get_str(form, "serverName", "fist-mbt")
  if !mcs_valid_server_name(server_name) {
    return Err(
      "serverName「" +
      server_name +
      "」不合法：只允许 [A-Za-z0-9_-]，长度 1..32（含 . / 空格 / / 都拒）",
    )
  }

  // —— toolCallTimeoutMs（整数，1..600000，否则拒）——
  let timeout = match mcs_get_timeout(form, "toolCallTimeoutMs") {
    Err(e) => return Err(e)
    Ok(v) => v
  }

  // —— env（只允许白名单环境变量名，值留占位）——
  let unknown_env : Array[String] = []
  let env = match mcs_filter_env(mcs_field(form, "env"), unknown_env) {
    Err(e) => return Err(e)
    Ok(m) => m
  }
  if env.get("FIST_PROJECT_DIR") is None {
    env.set("FIST_PROJECT_DIR", ".")
  }

  // env（Map[String,String]）转 Map[String,Json]，交给 Json::object
  let env_json : Map[String, Json] = Map([])
  for (k, v) in env {
    let shown = if v.is_empty() { "." } else { v }
    env_json.set(k, Json::string(shown))
  }

  // —— 组装 server 配置 ——
  let server_conf = Json::object({
    "command": Json::string(mcs_get_str(form, "command", "fist-mbt")),
    "args": Json::array(
      mcs_get_args(form, "args").map(fn(s) { Json::string(s) }),
    ),
    "cwd": Json::string(mcs_get_str(form, "cwd", ".")),
    "toolCallTimeoutMs": Json::number(timeout.to_double()),
    "failOnStartupError": Json::boolean(
      mcs_get_bool(form, "failOnStartupError", false),
    ),
    "reconnect": Json::object({
      "intervalMs": Json::number(mcs_get_reconnect_int(mcs_field(form, "reconnect"), "intervalMs", 500).to_double()),
      "maxRetries": Json::number(mcs_get_reconnect_int(mcs_field(form, "reconnect"), "maxRetries", 30).to_double()),
      "delayMs": Json::number(mcs_get_reconnect_int(mcs_field(form, "reconnect"), "delayMs", 30000).to_double()),
    }),
    "env": Json::object(env_json),
  })

  let servers : Map[String, Json] = Map([])
  servers.set(server_name, server_conf)
  let root = Json::object({
    "mcpServers": Json::object(servers),
  })

  // —— 返回体（json 是可直接落盘的漂亮打印正文，密钥值不回显）——
  let notes : Array[String] = [
    "配置里只写环境变量名占位（如 $FIST_GITHUB_TOKEN），真值走 server 进程环境变量",
    "未知字段已忽略并回显到 unknown_keys（供 HTML 页调试）",
  ]
  if unknown_env.length() > 0 {
    notes.push(
      "env 里出现非白名单键（已忽略）：" + unknown_env.join(", "),
    )
  }

  let out = Json::object({
    "project_dir": Json::string(project_dir),
    "target_file": Json::string("fist.mcp.json"),
    "json": Json::string(mcs_pretty(root)),
    "unknown_keys": Json::array(
      unknown_keys.map(fn(s) { Json::string(s) }),
    ),
    "notes": Json::array(notes.map(fn(s) { Json::string(s) })),
  })
  Ok(out)
}

///|
/// 取 form 顶层对象的某个字段（非对象或缺失 → 空对象 Json，便于下游匹配）。
fn mcs_field(form : Json, key : String) -> Json {
  match form {
    Json::Object(map) =>
      match map.get(key) {
        Some(v) => v
        None => Json::object({})
      }
    _ => Json::object({})
  }
}