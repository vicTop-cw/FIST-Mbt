/// mcp_config_scaffold_wbtest.mbt —— `mcp_config_scaffold` 的白盒回归锁（cl4）。
///
/// 为什么必须有：这个工具是方向一 P0-b 的核心，把目标项目的「MCP 设置偏好」form
/// 校验成可落盘的 `fist.mcp.json` 正文。它自称的硬门（凭据形状整笔拒绝）如果只写在
/// 描述里，等于没有——负路径必须真的跑过才会红。本文件正/负各若干，直接调纯函数
/// `mcp_config_scaffold_impl`（工具注册只做参数抽取，无 IO 可测）。

///|
fn mcs_test_must(cond : Bool, msg : String) -> Unit {
  if cond {
    ()
  } else {
    abort(msg)
  }
}

///|
/// 调纯函数并断言 Ok；失败时把 Err 原因带进 abort 消息。
fn mcs_run(
  form_json : String,
  project_dir : String,
  unknown_keys : Array[String],
) -> Json {
  match mcp_config_scaffold_impl(form_json, project_dir, unknown_keys) {
    Ok(j) => j
    Err(e) => abort("应当 Ok 但拿到 Err: " + e)
  }
}

///|
/// 调纯函数并断言 Err（含关键词匹配）。
fn mcs_run_err(
  form_json : String,
  project_dir : String,
  unknown_keys : Array[String],
  keyword : String,
) -> Unit {
  match mcp_config_scaffold_impl(form_json, project_dir, unknown_keys) {
    Ok(_) =>
      abort(
        "应当整笔拒绝但拿到 Ok（负路径漏了：要求含「" +
        keyword +
        "」）",
      )
    Err(e) =>
      mcs_test_must(
        e.contains(keyword),
        "拒绝原因应含「" + keyword + "」，实际：" + e,
      )
  }
}

///|
fn mcs_str(j : Json, key : String) -> String {
  match j.value(key) {
    Some(Json::String(s)) => s
    _ => "<缺 String 字段 " + key + ">"
  }
}

///|
fn mcs_arr(j : Json, key : String) -> Array[Json] {
  match j.value(key) {
    Some(Json::Array(arr)) => arr
    _ => []
  }
}

///|
/// 从返回体的 `json` 字段里取 mcpServers.<name> 的某字段，返回紧凑 stringify（便于 contains 断言）。
fn mcs_server_field(text : String, name : String, key : String) -> String {
  let j = @json.parse(text) catch { _ => Json::object({}) }
  match j.value("mcpServers") {
    Some(Json::Object(servers)) =>
      match servers.get(name) {
        Some(Json::Object(conf)) =>
          match conf.get(key) {
            Some(v) => v.stringify()
            _ => "<缺 " + key + ">"
          }
        _ => "<缺 server " + name + ">"
      }
    _ => "<缺 mcpServers>"
  }
}

///|
/// 正：空 form 拿默认值（全默认 + FIST_PROJECT_DIR="."）
test "mcs-正-空form拿默认值" {
  let j = mcs_run("{}", "proj-x", [])
  mcs_test_must(mcs_str(j, "project_dir") == "proj-x", "project_dir 应回显")
  mcs_test_must(
    mcs_str(j, "target_file") == "fist.mcp.json",
    "target_file 应为 fist.mcp.json",
  )
  let body = mcs_str(j, "json")
  mcs_test_must(body.contains("\"mcpServers\""), "正文应含 mcpServers")
  mcs_test_must(
    mcs_server_field(body, "fist-mbt", "command") == "\"fist-mbt\"",
    "默认 command 应为 fist-mbt",
  )
  mcs_test_must(
    mcs_server_field(body, "fist-mbt", "args") == "[]",
    "默认 args 应为空数组",
  )
  mcs_test_must(
    mcs_server_field(body, "fist-mbt", "toolCallTimeoutMs") == "30000",
    "默认 toolCallTimeoutMs 应为 30000",
  )
  mcs_test_must(
    mcs_server_field(body, "fist-mbt", "failOnStartupError") == "false",
    "默认 failOnStartupError 应为 false",
  )
  // 漂亮打印：正文必须带换行与 2 空格缩进（不能是紧凑单行）
  mcs_test_must(
    body.contains("\n  "),
    "正文应为 2 空格缩进的漂亮打印",
  )
  mcs_test_must(!body.contains("\\n"), "正文不应是紧凑 stringify")
}

///|
/// 正：显式填 serverName / command / cwd / env，reconnect 与 args 走显式值
test "mcs-正-填serverName与command与cwd与env" {
  let form = "{\"serverName\":\"my-mcp\",\"command\":\"fist-mbt\",\"cwd\":\"C:/proj\",\"args\":[\"serve\"],\"toolCallTimeoutMs\":60000,\"failOnStartupError\":true,\"reconnect\":{\"intervalMs\":1000,\"maxRetries\":5,\"delayMs\":70000},\"env\":{\"FIST_PROJECT_DIR\":\".\",\"FIST_GITHUB_REPO\":\"vicTop-cw/fist-mbt\",\"FIST_MODEL_API_KEY\":\"$FIST_MODEL_API_KEY\"}}"
  let j = mcs_run(form, "proj-y", [])
  let body = mcs_str(j, "json")
  mcs_test_must(
    mcs_server_field(body, "my-mcp", "cwd") == "\"C:/proj\"",
    "cwd 应回显",
  )
  mcs_test_must(
    mcs_server_field(body, "my-mcp", "args") == "[\"serve\"]",
    "args 应为 [serve]",
  )
  mcs_test_must(
    mcs_server_field(body, "my-mcp", "failOnStartupError") == "true",
    "failOnStartupError 应为 true",
  )
  mcs_test_must(
    mcs_server_field(body, "my-mcp", "toolCallTimeoutMs") == "60000",
    "toolCallTimeoutMs 应为 60000",
  )
  let env_field = mcs_server_field(body, "my-mcp", "env")
  mcs_test_must(
    env_field.contains("FIST_PROJECT_DIR"),
    "env 应含 FIST_PROJECT_DIR",
  )
  mcs_test_must(
    env_field.contains("$FIST_MODEL_API_KEY"),
    "env 应含 $FIST_MODEL_API_KEY 占位",
  )
  // FIST_PROJECT_DIR 已显式给 "."，不得再覆盖为 "."（此处同值，仅断言键存在）
  let rc = mcs_server_field(body, "my-mcp", "reconnect")
  mcs_test_must(
    rc.contains("\"intervalMs\":1000"),
    "reconnect.intervalMs 应为 1000",
  )
  mcs_test_must(
    rc.contains("\"maxRetries\":5"),
    "reconnect.maxRetries 应为 5",
  )
  mcs_test_must(
    rc.contains("\"delayMs\":70000"),
    "reconnect.delayMs 应为 70000",
  )
}

///|
/// 正：args 显式空数组 + FIST_PROJECT_DIR 走 env（不显式给 env 时默认补 "."）
test "mcs-正-args空数组与默认FIST_PROJECT_DIR" {
  let form = "{\"serverName\":\"fist-mbt\",\"args\":[]}"
  let j = mcs_run(form, "proj-z", [])
  let body = mcs_str(j, "json")
  mcs_test_must(
    mcs_server_field(body, "fist-mbt", "args") == "[]",
    "args 显式空数组应保持空数组",
  )
  let env_field = mcs_server_field(body, "fist-mbt", "env")
  mcs_test_must(
    env_field.contains("\"FIST_PROJECT_DIR\":\".\""),
    "默认 env 应补 FIST_PROJECT_DIR=.",
  )
}

///|
/// 负：serverName 含非法字符（. / 空格 / /）→ 拒
test "mcs-负-serverName含非法字符" {
  mcs_run_err("{\"serverName\":\"fist.mbt\"}", "", [], "serverName")
  mcs_run_err("{\"serverName\":\"fist mbt\"}", "", [], "serverName")
  mcs_run_err("{\"serverName\":\"fist/mbt\"}", "", [], "serverName")
  mcs_run_err(
    "{\"serverName\":\"abc123456789012345678901234567890abc\"}",
    "",
    [],
    "serverName",
  )
}

///|
/// 负：toolCallTimeoutMs 非整数 / 越界 → 拒
test "mcs-负-toolCallTimeoutMs非法" {
  mcs_run_err("{\"toolCallTimeoutMs\":0}", "", [], "toolCallTimeoutMs")
  mcs_run_err("{\"toolCallTimeoutMs\":700000}", "", [], "toolCallTimeoutMs")
  mcs_run_err("{\"toolCallTimeoutMs\":30000.5}", "", [], "toolCallTimeoutMs")
  mcs_run_err("{\"toolCallTimeoutMs\":\"30000\"}", "", [], "toolCallTimeoutMs")
}

///|
/// 负（硬门）：含凭据**键名**（在 env 之外，例如顶层/args）→ 整笔拒绝。
/// 注意：env **内部**的 `*_API_KEY` / `*_TOKEN` 是环境变量名，不做键名判据——
/// 真值只走 server 进程环境变量（见「mcs-正-env内API_KEY名字放行」）。
test "mcs-负-凭据键必拒" {
  // ① 键名 api_key（顶层，不是 env 内）
  mcs_run_err("{\"api_key\":\"x\"}", "", [], "凭据形状")
  // ② 键名 token（顶层）
  mcs_run_err("{\"token\":\"x\"}", "", [], "凭据形状")
  // ③ 键名 password（顶层）
  mcs_run_err("{\"password\":\"hunter2\"}", "", [], "凭据形状")
  // ④ 键名 secret（大小写变体，顶层）
  mcs_run_err("{\"SecretKey\":\"x\"}", "", [], "凭据形状")
  // ⑤ env 内的 **嵌套对象**里的凭据键仍要拒（env 判据①只对 env 的直接键名跳过）
  mcs_run_err(
    "{\"env\":{\"creds\":{\"api_key\":\"sk-123\"}}}",
    "",
    [],
    "凭据形状",
  )
}

///|
/// 负（硬门）：含凭据值形状（sk- 前缀 / Bearer 前缀 / ghp_ / glpat- / AIza）→ 整笔拒绝
test "mcs-负-凭据值必拒" {
  // ① sk- 前缀
  mcs_run_err(
    "{\"env\":{\"MY_API_KEY_REF\":\"sk-abcdef123456\"}}",
    "",
    [],
    "凭据形状",
  )
  // ② Bearer 前缀
  mcs_run_err(
    "{\"env\":{\"X_AUTH\":\"Bearer yyy.zzz\"}}",
    "",
    [],
    "凭据形状",
  )
  // ③ ghp_ 前缀（GitHub PAT）
  mcs_run_err(
    "{\"env\":{\"GITHUB_CRED\":\"ghp_abcdef0123456789\"}}",
    "",
    [],
    "凭据形状",
  )
  // ④ glpat- 前缀（GitLab PAT）
  mcs_run_err(
    "{\"env\":{\"GITLAB_CRED\":\"glpat-abcdef012345\"}}",
    "",
    [],
    "凭据形状",
  )
  // ⑤ AIza 前缀（Google API key）
  mcs_run_err(
    "{\"env\":{\"GOOGLE_KEY\":\"AIzaSyABCDEF0123456789\"}}",
    "",
    [],
    "凭据形状",
  )
}

///|
/// 负（硬门）：字面键 `"token":` 出现在 args / 顶层 → 拒（覆盖字面键判据）
test "mcs-负-字面token键" {
  mcs_run_err("{\"args\":[\"token\"],\"env\":{}}", "", [], "凭据形状")
}

///|
/// 负：form_json 非法 JSON / 空字符串 / 顶层非对象 → 拒
test "mcs-负-非法JSON与空字符串" {
  mcs_run_err("{not json}", "", [], "不是合法 JSON")
  mcs_run_err("", "", [], "不能为空")
  mcs_run_err("   ", "", [], "不能为空")
  mcs_run_err("[1,2,3]", "", [], "顶层必须是 JSON 对象")
}

///|
/// 未知字段：忽略不崩，回显 unknown_keys
test "mcs-未知字段回显不崩" {
  let form = "{\"serverName\":\"fist-mbt\",\"mysteryField\":\"hello\",\"another\":1}"
  let keys = mcs_collect_unknown_keys(
    @json.parse(form) catch {
      _ => Json::object({})
    },
  )
  mcs_test_must(
    keys.length() == 2,
    "应收集到 2 个未知键，实际 " + keys.length().to_string(),
  )
  let j = mcs_run(form, "proj-w", keys)
  let uk = mcs_arr(j, "unknown_keys")
  mcs_test_must(uk.length() == 2, "unknown_keys 应回显 2 项")
  // 主体仍然正常生成
  let body = mcs_str(j, "json")
  mcs_test_must(
    body.contains("\"mcpServers\""),
    "含未知键时仍应产出正文",
  )
}

///|
/// env 里的非白名单键：忽略 + notes 提示（不是硬拒——它不是凭据形状，只是未知键）
test "mcs-env非白名单键忽略并提示" {
  let form = "{\"env\":{\"FIST_PROJECT_DIR\":\".\",\"MY_CUSTOM_VAR\":\"1\"}}"
  let j = mcs_run(form, "proj-v", [])
  let body = mcs_str(j, "json")
  let env_field = mcs_server_field(body, "fist-mbt", "env")
  mcs_test_must(
    env_field.contains("FIST_PROJECT_DIR"),
    "env 应含白名单键",
  )
  mcs_test_must(
    !env_field.contains("MY_CUSTOM_VAR"),
    "env 不应含非白名单键",
  )
  let notes = mcs_str(j, "notes").to_string()
  // notes 是数组，用 stringify 后的全文判读
  let full = j.stringify()
  mcs_test_must(
    full.contains("非白名单键"),
    "notes 应点名非白名单键",
  )
  let _ = notes
}

///|
/// project_dir 走 env（工具层抽取逻辑的等价面：缺省回退 "."，FIST_PROJECT_DIR 为空也回退 "."）
test "mcs-project_dir缺省回退" {
  // impl 层直接回显传入的 project_dir；工具层才做 env 回退（在 server.mbt 注册处）。
  // 这里锁的是「空 project_dir 也不崩，正文正常产出」。
  let j = mcs_run("{}", "", [])
  mcs_test_must(
    mcs_str(j, "project_dir") == "",
    "impl 层应回显原值（env 回退在工具层）",
  )
  let body = mcs_str(j, "json")
  mcs_test_must(
    body.contains("\"mcpServers\""),
    "空 project_dir 也应产出正文",
  )
}

///|
/// 正（缺陷 2 回归锁）：env **内**的 `*_API_KEY` 是环境变量**名字**，不是凭据——
/// 键名判据①在 env 内跳过，值必须是 `$NAME` 占位；两项都必须出现在生成的 json 里。
test "mcs-正-env内API_KEY名字放行" {
  let form = "{\"env\":{\"ANTHROPIC_API_KEY\":\"$ANTHROPIC_API_KEY\",\"OPENAI_API_KEY\":\"$OPENAI_API_KEY\"}}"
  let j = mcs_run(form, "proj-a", [])
  let body = mcs_str(j, "json")
  let env_field = mcs_server_field(body, "fist-mbt", "env")
  mcs_test_must(
    env_field.contains("ANTHROPIC_API_KEY"),
    "env 应含 ANTHROPIC_API_KEY 名字",
  )
  mcs_test_must(
    env_field.contains("OPENAI_API_KEY"),
    "env 应含 OPENAI_API_KEY 名字",
  )
  mcs_test_must(
    env_field.contains("$ANTHROPIC_API_KEY"),
    "值应为 $NAME 占位（不许回显真值）",
  )
  mcs_test_must(!env_field.contains("sk-"), "env 值不得含 sk- 形状")
}

///|
/// 负（缺陷 2 值硬门不放松）：env 内**值**出现 sk-/ghp_ 长令牌形状仍整笔拒。
test "mcs-负-env值长令牌仍拒" {
  mcs_run_err(
    "{\"env\":{\"ANTHROPIC_API_KEY\":\"sk-ant-api03-abcdef123456\"}}",
    "",
    [],
    "凭据形状",
  )
  mcs_run_err(
    "{\"env\":{\"FIST_GITHUB_TOKEN\":\"ghp_abcdef0123456789\"}}",
    "",
    [],
    "凭据形状",
  )
}
