/// github_sync.mbt —— FIST-Mbt 外部 bug → GitHub issue 同步（R116）
///
/// 纯 MoonBit 核心层：零网络、零 token、零外部依赖。
/// 队列格式：JSONL（每行一条），落 memory/bugs_pending_github.json。
/// GitHub API 调用由外部注入层执行（JS target / gh CLI / 用户脚本）。

///|
fn gq_path(project_dir : String) -> String {
  mem_join(mem_dir(project_dir), "bugs_pending_github.json")
}

///|
/// 从 Result[Json, String] 安全取出 Json 数组；任何失败回退空数组。
fn extract_arr(r : Result[Json, String]) -> Array[Json] {
  match r {
    Ok(j) =>
      match j {
        Array(a) => a
        _ => []
      }
    Err(_) => []
  }
}

///|
pub fn github_queue_read(project_dir : String) -> Result[Json, String] {
  if !bug_project_dir_ok(project_dir) {
    return Err("github_queue_read: 非法 project_dir")
  }
  let text = match mem_read(gq_path(project_dir)) {
    None => ""
    Some(s) => s
  }
  let entries : Array[Json] = []
  for raw in text.split("\n") {
    let line = raw.trim().to_owned()
    if line.length() == 0 {
      continue
    }
    let j = @json.parse(line) catch { _ => Json::null() }
    entries.push(j)
  }
  Ok(Json::array(entries))
}

///|
pub fn github_queue_append(
  project_dir : String,
  bug_id : String,
  summary : String,
  detail : String,
  severity : String,
  ts : String,
  github_repo : String,
  github_labels : Array[String],
) -> Result[Json, String] {
  if !bug_project_dir_ok(project_dir) {
    return Err("github_queue_append: 非法 project_dir")
  }
  if bug_id.is_empty() {
    return Err("github_queue_append: bug_id 不能为空")
  }
  if summary.is_empty() {
    return Err("github_queue_append: summary 不能为空")
  }
  if github_repo.is_empty() {
    return Err(
      "github_queue_append: github_repo 不能为空（格式 owner/repo）",
    )
  }
  let existing = extract_arr(github_queue_read(project_dir))
  for entry in existing {
    match entry {
      Object(m) => {
        let eid = match m.get("bug_id") {
          Some(String(s)) => s
          _ => ""
        }
        if eid == bug_id {
          let mm : Map[String, Json] = Map([])
          mm.set("bug_id", Json::string(bug_id))
          mm.set("exists", Json::boolean(true))
          return Ok(Json::object(mm))
        }
      }
      _ => ()
    }
  }
  let labels_json : Array[Json] = []
  for lb in github_labels {
    labels_json.push(Json::string(lb))
  }
  let nm : Map[String, Json] = Map([])
  nm.set("bug_id", Json::string(bug_id))
  nm.set("summary", Json::string(summary))
  nm.set("detail", Json::string(detail))
  nm.set("severity", Json::string(severity))
  nm.set("ts", Json::string(ts))
  nm.set("github_repo", Json::string(github_repo))
  nm.set("github_labels", Json::array(labels_json))
  nm.set("sent_at", Json::null())
  nm.set("github_issue_number", Json::null())
  let entry_json = Json::object(nm)

  let old = match mem_read(gq_path(project_dir)) {
    None => ""
    Some(s) => s
  }
  mem_ensure_dir(mem_dir(project_dir))
  let _ = mem_write(gq_path(project_dir), old + entry_json.stringify() + "\n")

  let mm : Map[String, Json] = Map([])
  mm.set("bug_id", Json::string(bug_id))
  mm.set("exists", Json::boolean(false))
  Ok(Json::object(mm))
}

///|
pub fn github_queue_status(project_dir : String) -> Result[Json, String] {
  if !bug_project_dir_ok(project_dir) {
    return Err("github_queue_status: 非法 project_dir")
  }
  let entries = extract_arr(github_queue_read(project_dir))
  let mut sent_count = 0
  let mut oldest_ts = ""
  let by_sev : Map[String, Int] = Map([])
  let pending_entries : Array[Json] = []

  for entry in entries {
    match entry {
      Object(m) => {
        let sent = match m.get("sent_at") {
          Some(String(s)) => !s.is_empty()
          _ => false
        }
        let sev = match m.get("severity") {
          Some(String(s)) => s
          _ => "open"
        }
        let ts = match m.get("ts") {
          Some(String(s)) => s
          _ => ""
        }
        if sent {
          sent_count = sent_count + 1
        } else {
          let cur = match by_sev.get(sev) {
            Some(n) => n
            _ => 0
          }
          by_sev.set(sev, cur + 1)
          if oldest_ts.is_empty() || (!ts.is_empty() && ts < oldest_ts) {
            oldest_ts = ts
          }
          pending_entries.push(entry)
        }
      }
      _ => ()
    }
  }

  let sev_obj : Map[String, Json] = Map([])
  for (k, v) in by_sev {
    sev_obj.set(k, Json::number(v.to_double()))
  }

  let slim : Array[Json] = []
  for p in pending_entries {
    match p {
      Object(m) => {
        let sm : Map[String, Json] = Map([])
        sm.set("bug_id", m.get("bug_id").unwrap_or(Json::string("")))
        sm.set("summary", m.get("summary").unwrap_or(Json::string("")))
        sm.set("severity", m.get("severity").unwrap_or(Json::string("")))
        sm.set("ts", m.get("ts").unwrap_or(Json::string("")))
        sm.set("github_repo", m.get("github_repo").unwrap_or(Json::string("")))
        slim.push(Json::object(sm))
      }
      _ => ()
    }
  }

  let mm : Map[String, Json] = Map([])
  mm.set("total", Json::number(entries.length().to_double()))
  mm.set("pending", Json::number(pending_entries.length().to_double()))
  mm.set("sent", Json::number(sent_count.to_double()))
  mm.set("oldest_pending_ts", Json::string(oldest_ts))
  mm.set("by_severity", Json::object(sev_obj))
  mm.set("pending_list", Json::array(slim))
  mm.set("path", Json::string(gq_path(project_dir)))
  Ok(Json::object(mm))
}

///|
pub fn github_flush_plan(
  project_dir : String,
  limit : Int,
) -> Result[Json, String] {
  if !bug_project_dir_ok(project_dir) {
    return Err("github_flush_plan: 非法 project_dir")
  }
  let entries = extract_arr(github_queue_read(project_dir))
  let plan : Array[Json] = []
  let cap = if limit > 0 { limit } else { 20 }

  for entry in entries {
    if plan.length() >= cap {
      break
    }
    match entry {
      Object(m) => {
        let sent = match m.get("sent_at") {
          Some(String(s)) => !s.is_empty()
          _ => false
        }
        if sent {
          continue
        }

        let bug_id = match m.get("bug_id") {
          Some(String(s)) => s
          _ => ""
        }
        let summary = match m.get("summary") {
          Some(String(s)) => s
          _ => ""
        }
        let detail = match m.get("detail") {
          Some(String(s)) => s
          _ => ""
        }
        let sev = match m.get("severity") {
          Some(String(s)) => s
          _ => "open"
        }
        let repo = match m.get("github_repo") {
          Some(String(s)) => s
          _ => ""
        }

        let labels2 : Array[String] = if sev == "critical" {
          ["bug", "priority-critical"]
        } else if sev == "high" {
          ["bug", "priority-high"]
        } else if sev == "medium" {
          ["bug", "priority-medium"]
        } else if sev == "low" {
          ["bug", "priority-low"]
        } else {
          ["bug"]
        }

        let body = build_issue_body(bug_id, summary, detail, sev)
        let labels_json = labels2
          .map(fn(l : String) { "\"" + l + "\"" })
          .join(",")
        let payload = "{\"title\":" +
          shell_quote(summary) +
          ",\"body\":" +
          shell_quote(body) +
          ",\"labels\":[" +
          labels_json +
          "]}"
        let curl_cmd = "curl -sS -X POST \"https://api.github.com/repos/" +
          repo +
          "/issues\" -H \"Authorization: Bearer ${FIST_GITHUB_TOKEN}\" " +
          "-H \"Accept: application/vnd.github+json\" " +
          "-H \"Content-Type: application/json\" " +
          "--data " +
          shell_quote(payload)

        let pm : Map[String, Json] = Map([])
        pm.set("bug_id", Json::string(bug_id))
        pm.set("repo", Json::string(repo))
        pm.set("title", Json::string(summary))
        pm.set("severity", Json::string(sev))
        pm.set("curl_command", Json::string(curl_cmd))
        plan.push(Json::object(pm))
      }
      _ => ()
    }
  }

  let mm : Map[String, Json] = Map([])
  mm.set("plan", Json::array(plan))
  mm.set("generated", Json::number(plan.length().to_double()))
  mm.set(
    "hint",
    Json::string(
      "执行 curl 后从返回 JSON 提取 issue.number，调 github_queue_mark_sent 标记",
    ),
  )
  Ok(Json::object(mm))
}

///|
pub fn github_queue_mark_sent(
  project_dir : String,
  bug_ids : Array[String],
  sent_at : String,
  issue_numbers : Map[String, Int],
) -> Result[Json, String] {
  if !bug_project_dir_ok(project_dir) {
    return Err("github_queue_mark_sent: 非法 project_dir")
  }
  let entries = extract_arr(github_queue_read(project_dir))
  let target_ids : Map[String, Bool] = Map([])
  for id in bug_ids {
    target_ids.set(id, true)
  }

  let updated : Array[Json] = []
  let mut marked = 0
  for entry in entries {
    match entry {
      Object(m) => {
        let bid = match m.get("bug_id") {
          Some(String(s)) => s
          _ => ""
        }
        let want = match target_ids.get(bid) {
          Some(true) => true
          _ => false
        }
        if want {
          m.set("sent_at", Json::string(sent_at))
          let issue_num = match issue_numbers.get(bid) {
            Some(n) => Json::number(n.to_double())
            None => Json::null()
          }
          m.set("github_issue_number", issue_num)
          marked = marked + 1
        }
        updated.push(Json::object(m))
      }
      _ => updated.push(entry)
    }
  }
  let lines = updated.map(fn(j : Json) { j.stringify() })
  let _ = mem_write(gq_path(project_dir), lines.join("\n") + "\n")

  let mm : Map[String, Json] = Map([])
  mm.set("marked", Json::number(marked.to_double()))
  mm.set("total", Json::number(updated.length().to_double()))
  Ok(Json::object(mm))
}

///|
fn build_issue_body(
  bug_id : String,
  summary : String,
  detail : String,
  severity : String,
) -> String {
  let body : Array[String] = [
    "<!-- FIST-Mbt 自动上报 bug · " + bug_id + " -->",
    "",
    "## 摘要",
    "",
    summary,
    "",
    "## 详细描述",
    "",
    if detail.is_empty() {
      "_无额外细节_"
    } else {
      "```" + detail + "```"
    },
    "",
    "## 元信息",
    "",
    "| 字段 | 值 |",
    "|---|---|",
    "| Bug ID | `" + bug_id + "` |",
    "| 严重度 | **" + severity + "** |",
    "",
    "> 由 FIST-Mbt report_bug 自动生成，同步至 GitHub issue",
  ]
  body.join("\n")
}

///|
/// Shell 单引号转义：内部单引号替换为双引号。
fn shell_quote(s : String) -> String {
  let replaced = s.replace(old="'", new="\"")
  "'" + replaced + "'"
}

// ===== Part A 新增：pending 提取 + close/comment 计划构建 + webhook 解析 =====

///|
/// 从 JSONL 队列提取所有 sent_at 为空的 pending 条目。
/// 返回的每条是简化版 JSON：{ bug_id, summary, repo, labels_json }。
/// 纯计算：零网络、零 token、零外部依赖。
pub fn github_queue_pending(
  project_dir : String,
) -> Result[Array[Json], String] {
  if !bug_project_dir_ok(project_dir) {
    return Err("github_queue_pending: 非法 project_dir")
  }
  let entries = extract_arr(github_queue_read(project_dir))
  let pending : Array[Json] = []
  for entry in entries {
    match entry {
      Object(m) => {
        let sent = match m.get("sent_at") {
          Some(String(s)) => !s.is_empty()
          _ => false
        }
        if sent {
          continue
        }
        let bug_id = match m.get("bug_id") {
          Some(String(s)) => s
          _ => ""
        }
        let summary = match m.get("summary") {
          Some(String(s)) => s
          _ => ""
        }
        let repo = match m.get("github_repo") {
          Some(String(s)) => s
          _ => ""
        }
        let labels_json = match m.get("github_labels") {
          Some(a) => a.stringify()
          _ => "[]"
        }
        let sm : Map[String, Json] = Map([])
        sm.set("bug_id", Json::string(bug_id))
        sm.set("summary", Json::string(summary))
        sm.set("repo", Json::string(repo))
        sm.set("labels_json", Json::string(labels_json))
        pending.push(Json::object(sm))
      }
      _ => ()
    }
  }
  Ok(pending)
}

///|
/// 从 JSONL 队列查找指定 bug_id 对应的 github_issue_number + github_repo。
/// 返回 (issue_number, repo)；找不到时 issue_number=-1, repo=""。
fn find_issue_and_repo(project_dir : String, bug_id : String) -> (Int, String) {
  let entries = extract_arr(github_queue_read(project_dir))
  for entry in entries {
    match entry {
      Object(m) => {
        let bid = match m.get("bug_id") {
          Some(String(s)) => s
          _ => ""
        }
        if bid != bug_id {
          continue
        }
        let issue_num = match m.get("github_issue_number") {
          Some(Number(n, ..)) => n.to_int()
          _ => -1
        }
        let repo = match m.get("github_repo") {
          Some(String(s)) => s
          _ => ""
        }
        return (issue_num, repo)
      }
      _ => ()
    }
  }
  (-1, "")
}

///|
/// 为一批 issue number 构建 close 计划：按 repo 分组 → 每组生成一条 curl 命令
/// (PUT /repos/{owner}/{repo}/issues/{n} body=`{"state":"closed"}`)。
/// issue_numbers key=bug_id, value=issue_number（来自 curl 执行后回写的映射）。
/// 找不到 repo 的条目静默跳过。返回 { plan: [...], generated: N }。
/// 纯计算：零网络、零 token、零外部依赖。
pub fn github_build_close_plan(
  project_dir : String,
  issue_numbers : Map[String, Int],
) -> Result[Json, String] {
  if !bug_project_dir_ok(project_dir) {
    return Err("github_build_close_plan: 非法 project_dir")
  }
  let plan : Array[Json] = []
  for (bug_id, issue_number) in issue_numbers {
    if issue_number <= 0 {
      continue
    }
    let (num_found, repo) = find_issue_and_repo(project_dir, bug_id)
    let real_num = if num_found > 0 { num_found } else { issue_number }
    if repo.is_empty() {
      continue
    }
    let payload = "{\"state\":\"closed\"}"
    let curl_cmd = "curl -sS -X PUT \"https://api.github.com/repos/" +
      repo +
      "/issues/" +
      real_num.to_string() +
      "\" -H \"Authorization: Bearer ${FIST_GITHUB_TOKEN}\" " +
      "-H \"Accept: application/vnd.github+json\" " +
      "-H \"Content-Type: application/json\" " +
      "--data " +
      shell_quote(payload)
    let pm : Map[String, Json] = Map([])
    pm.set("bug_id", Json::string(bug_id))
    pm.set("repo", Json::string(repo))
    pm.set("issue_number", Json::number(real_num.to_double()))
    pm.set("curl_command", Json::string(curl_cmd))
    plan.push(Json::object(pm))
  }
  let mm : Map[String, Json] = Map([])
  mm.set("plan", Json::array(plan))
  mm.set("generated", Json::number(plan.length().to_double()))
  Ok(Json::object(mm))
}

///|
/// 为指定 bug_id 构建 comment curl 命令。
/// 从队列找到对应的 github_issue_number + repo → 构造
/// POST /repos/{owner}/{repo}/issues/{n}/comments body=`{"body":"..."}`。
/// 找不到 issue_number 时返回 Err。
/// 纯计算：零网络、零 token、零外部依赖。
pub fn github_build_comment_plan(
  project_dir : String,
  bug_id : String,
  comment_body : String,
) -> Result[Json, String] {
  if !bug_project_dir_ok(project_dir) {
    return Err("github_build_comment_plan: 非法 project_dir")
  }
  if bug_id.is_empty() {
    return Err("github_build_comment_plan: bug_id 不能为空")
  }
  if comment_body.is_empty() {
    return Err("github_build_comment_plan: comment_body 不能为空")
  }
  let (issue_num, repo) = find_issue_and_repo(project_dir, bug_id)
  if issue_num <= 0 {
    return Err(
      "github_build_comment_plan: bug_id 未同步过（无 github_issue_number）——先 flush 再 comment",
    )
  }
  if repo.is_empty() {
    return Err("github_build_comment_plan: bug_id 无 github_repo 配置")
  }
  let payload = "{\"body\":" + shell_quote(comment_body) + "}"
  let curl_cmd = "curl -sS -X POST \"https://api.github.com/repos/" +
    repo +
    "/issues/" +
    issue_num.to_string() +
    "/comments\" -H \"Authorization: Bearer ${FIST_GITHUB_TOKEN}\" " +
    "-H \"Accept: application/vnd.github+json\" " +
    "-H \"Content-Type: application/json\" " +
    "--data " +
    shell_quote(payload)
  let mm : Map[String, Json] = Map([])
  mm.set("bug_id", Json::string(bug_id))
  mm.set("repo", Json::string(repo))
  mm.set("issue_number", Json::number(issue_num.to_double()))
  mm.set("curl_command", Json::string(curl_cmd))
  Ok(Json::object(mm))
}

///|
/// 从 JSONL 队列查找所有已 sent 的条目，返回 { bug_id, github_issue_number, repo } 数组。
/// 供 flush_execute 执行后自动 mark_sent 时回填 issue number 映射。
pub fn github_find_sent_entries(
  project_dir : String,
  bug_ids : Array[String],
) -> Result[Json, String] {
  if !bug_project_dir_ok(project_dir) {
    return Err("github_find_sent_entries: 非法 project_dir")
  }
  let id_set : Map[String, Bool] = Map([])
  for id in bug_ids {
    id_set.set(id, true)
  }
  let out : Array[Json] = []
  let entries = extract_arr(github_queue_read(project_dir))
  for entry in entries {
    match entry {
      Object(m) => {
        let bug_id = match m.get("bug_id") {
          Some(String(s)) => s
          _ => ""
        }
        let want = match id_set.get(bug_id) {
          Some(true) => true
          _ => false
        }
        if !want {
          continue
        }
        let issue_num = match m.get("github_issue_number") {
          Some(Number(n, ..)) => n.to_int()
          _ => -1
        }
        let repo = match m.get("github_repo") {
          Some(String(s)) => s
          _ => ""
        }
        let om : Map[String, Json] = Map([])
        om.set("bug_id", Json::string(bug_id))
        om.set("repo", Json::string(repo))
        om.set("issue_number", Json::number(issue_num.to_double()))
        out.push(Json::object(om))
      }
      _ => ()
    }
  }
  Ok(Json::array(out))
}

///|
/// 解析 GitHub issue comment webhook payload，提取 @fist-bot 指令。
/// 纯计算正则匹配，零 LLM、零网络。
/// 支持的指令集：
///   "@fist-bot reopen <task_id>"  → { action: "reopen",  task_id, raw }
///   "@fist-bot challenge"         → { action: "challenge", raw }
///   "@fist-bot close"             → { action: "close",    raw }
///   "@fist-bot blocked <reason>"  → { action: "blocked",  reason, raw }
///   未命中                        → { action: "none" }
pub fn github_webhook_parse(payload : String) -> Result[Json, String] {
  if payload.is_empty() {
    return Err("github_webhook_parse: payload 不能为空")
  }
  let j = @json.parse(payload) catch {
    _ => return Err("github_webhook_parse: payload 不是合法 JSON")
  }
  let body = match j {
    Object(m) =>
      match m.get("comment") {
        Some(Object(cm)) =>
          match cm.get("body") {
            Some(String(s)) => s
            _ => ""
          }
        _ => ""
      }
    _ => ""
  }
  let trimmed = body.trim().to_owned()
  let mm : Map[String, Json] = Map([])
  if trimmed.starts_with("@fist-bot reopen ") {
    let rest = trimmed.substring(start=17)
    let task_id = rest.trim().to_owned()
    mm.set("action", Json::string("reopen"))
    mm.set("task_id", Json::string(task_id))
    mm.set("raw", Json::string(trimmed))
  } else if trimmed.starts_with("@fist-bot challenge") {
    mm.set("action", Json::string("challenge"))
    mm.set("raw", Json::string(trimmed))
  } else if trimmed.starts_with("@fist-bot close") {
    mm.set("action", Json::string("close"))
    mm.set("raw", Json::string(trimmed))
  } else if trimmed.starts_with("@fist-bot blocked ") {
    let rest = trimmed.substring(start=18)
    let reason = rest.trim().to_owned()
    mm.set("action", Json::string("blocked"))
    mm.set("reason", Json::string(reason))
    mm.set("raw", Json::string(trimmed))
  } else {
    mm.set("action", Json::string("none"))
    mm.set("raw", Json::string(trimmed))
  }
  Ok(Json::object(mm))
}
