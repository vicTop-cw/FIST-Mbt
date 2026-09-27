/// github_gitcode.mbt —— FIST-Mbt 外部 bug → GitCode issue 同步（fallback 通道）
///
/// 纯 MoonBit 核心层：零网络、零 token、零外部依赖。
/// 队列格式：JSONL（每行一条），复用 memory/bugs_pending_github.json ——
/// GitCode 是 GitHub 的 fallback，两个通道读同一个队列文件，
/// 只是各自过滤属于自己的条目（GitCode 条目带 gitcode_project_id 字段）。
/// GitCode API 调用由外部注入层执行（JS target / curl / 用户脚本）。

///|
/// GitCode token 占位符。必须拆开写 `$` + `{FIST_GITCODE_TOKEN}` ——
/// 写成字面量 `${FIST_GITCODE_TOKEN}` 会被 MoonBit 当成字符串插值，
/// JS target 运行时 ReferenceError（同 github_sync.mbt 的 token_placeholder BUG-87 口径）。
fn gitcode_token_placeholder() -> String {
  "$" + "{FIST_GITCODE_TOKEN}"
}

///|
/// 从队列条目的 json 字段里判断：这条是不是 GitCode 通道的条目。
/// 判据：对象含有非空 gitcode_project_id 字符串。
fn is_gitcode_entry(entry : Json) -> Bool {
  match entry {
    Object(m) =>
      match m.get("gitcode_project_id") {
        Some(String(s)) => !s.is_empty()
        _ => false
      }
    _ => false
  }
}

///|
/// 读整个 JSONL 队列（与 github_queue_read 同路径）。
pub fn gitcode_queue_read(project_dir : String) -> Result[Json, String] {
  github_queue_read(project_dir)
}

///|
/// 队列状态（过滤 GitCode 条目）。
/// 返回 {total, pending, sent, by_severity, pending_list, path}。
/// 可选参数 gitcode_project_id：非空时只统计该 project_id 的条目。
pub fn gitcode_queue_status(
  project_dir : String,
  gitcode_project_id : String,
) -> Result[Json, String] {
  if !bug_project_dir_ok(project_dir) {
    return Err("gitcode_queue_status: 非法 project_dir")
  }
  let all_entries = extract_arr(github_queue_read(project_dir))
  let mut total = 0
  let mut sent_count = 0
  let mut oldest_ts = ""
  let by_sev : Map[String, Int] = Map([])
  let pending_entries : Array[Json] = []

  for entry in all_entries {
    if !is_gitcode_entry(entry) {
      continue
    }
    // 如果指定了 project_id，过滤掉不匹配的
    if !gitcode_project_id.is_empty() {
      match entry {
        Object(m) => {
          let pid = match m.get("gitcode_project_id") {
            Some(String(s)) => s
            _ => ""
          }
          if pid != gitcode_project_id {
            continue
          }
        }
        _ => continue
      }
    }

    total = total + 1
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
        sm.set(
          "gitcode_project_id",
          m.get("gitcode_project_id").unwrap_or(Json::string("")),
        )
        slim.push(Json::object(sm))
      }
      _ => ()
    }
  }

  let mm : Map[String, Json] = Map([])
  mm.set("total", Json::number(total.to_double()))
  mm.set("pending", Json::number(pending_entries.length().to_double()))
  mm.set("sent", Json::number(sent_count.to_double()))
  mm.set("oldest_pending_ts", Json::string(oldest_ts))
  mm.set("by_severity", Json::object(sev_obj))
  mm.set("pending_list", Json::array(slim))
  mm.set("path", Json::string(gq_path(project_dir)))
  Ok(Json::object(mm))
}

///|
/// 生成 GitCode curl 命令列表。
/// URL：POST https://gitcode.com/api/v4/projects/{project_id}/issues
/// 鉴权：PRIVATE-TOKEN（不是 GitHub 的 Bearer）。
/// limit <= 0 时默认 20。
pub fn gitcode_flush_plan(
  project_dir : String,
  gitcode_project_id : String,
  limit : Int,
) -> Result[Json, String] {
  if !bug_project_dir_ok(project_dir) {
    return Err("gitcode_flush_plan: 非法 project_dir")
  }
  if gitcode_project_id.is_empty() {
    return Err("gitcode_flush_plan: gitcode_project_id 不能为空")
  }
  let all_entries = extract_arr(github_queue_read(project_dir))
  let plan : Array[Json] = []
  let cap = if limit > 0 { limit } else { 20 }

  for entry in all_entries {
    if plan.length() >= cap {
      break
    }
    if !is_gitcode_entry(entry) {
      continue
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

        let pid = match m.get("gitcode_project_id") {
          Some(String(s)) => s
          _ => ""
        }
        // 只处理指定 project_id 的条目
        if pid != gitcode_project_id {
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
        let payload = Json::object({
          "title": Json::string(summary),
          "description": Json::string(body),
          "labels": Json::array(labels2.map(fn(l : String) { Json::string(l) })),
        }).stringify()

        let curl_cmd = "curl -sS -X POST \"https://gitcode.com/api/v4/projects/" +
          gitcode_project_id +
          "/issues\" -H \"PRIVATE-TOKEN: " +
          gitcode_token_placeholder() +
          "\" " +
          "-H \"Content-Type: application/json\" " +
          "--data " +
          shell_quote(payload)

        let pm : Map[String, Json] = Map([])
        pm.set("bug_id", Json::string(bug_id))
        pm.set("gitcode_project_id", Json::string(gitcode_project_id))
        pm.set("title", Json::string(summary))
        pm.set("severity", Json::string(sev))
        pm.set("curl_command", Json::string(curl_cmd))
        pm.set("payload_json", Json::string(payload))
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
      "执行 curl 后从返回 JSON 提取 issue.iid，调 gitcode_queue_mark_sent 标记",
    ),
  )
  Ok(Json::object(mm))
}

///|
/// 标记某条 bug 已发送到 GitCode。
/// 在现有条目上追加 gitcode_issue_iid + 更新 sent_at。
pub fn gitcode_queue_mark_sent(
  project_dir : String,
  bug_id : String,
  gitcode_issue_iid : String,
) -> Result[Json, String] {
  if !bug_project_dir_ok(project_dir) {
    return Err("gitcode_queue_mark_sent: 非法 project_dir")
  }
  if bug_id.is_empty() {
    return Err("gitcode_queue_mark_sent: bug_id 不能为空")
  }
  if gitcode_issue_iid.is_empty() {
    return Err("gitcode_queue_mark_sent: gitcode_issue_iid 不能为空")
  }
  let all_entries = extract_arr(github_queue_read(project_dir))

  let updated : Array[Json] = []
  let mut marked = 0
  for entry in all_entries {
    match entry {
      Object(m) => {
        let bid = match m.get("bug_id") {
          Some(String(s)) => s
          _ => ""
        }
        let is_git = is_gitcode_entry(entry)
        if bid == bug_id && is_git {
          m.set("sent_at", Json::string("gitcode"))
          m.set("gitcode_issue_iid", Json::string(gitcode_issue_iid))
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
/// 提取所有 GitCode 通道的 pending 条目（sent_at 为空的 GitCode 条目）。
/// 返回 Json 数组。
pub fn gitcode_queue_pending(project_dir : String) -> Result[Json, String] {
  if !bug_project_dir_ok(project_dir) {
    return Err("gitcode_queue_pending: 非法 project_dir")
  }
  let all_entries = extract_arr(github_queue_read(project_dir))
  let pending : Array[Json] = []
  for entry in all_entries {
    if !is_gitcode_entry(entry) {
      continue
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
        let pid = match m.get("gitcode_project_id") {
          Some(String(s)) => s
          _ => ""
        }
        let sev = match m.get("severity") {
          Some(String(s)) => s
          _ => "open"
        }
        let sm : Map[String, Json] = Map([])
        sm.set("bug_id", Json::string(bug_id))
        sm.set("summary", Json::string(summary))
        sm.set("gitcode_project_id", Json::string(pid))
        sm.set("severity", Json::string(sev))
        pending.push(Json::object(sm))
      }
      _ => ()
    }
  }
  Ok(Json::array(pending))
}
