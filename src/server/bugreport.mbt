/// bugreport.mbt —— bug 上报 + 清单（"上报 → 修复"闭环）工具实现
///
/// 提供两个 MCP 工具背后的纯逻辑：
///   - report_bug：把一次运行时失败追加写入 {project_dir}/memory/bugs.md
///     （OPEN 状态账本）；publish_task=true 时同时把"修复 bug: <summary>"
///     并行发布为命名空间 bugs 下的独立根任务，供系统自驱认领修复。
///   - bug_list：解析 memory/bugs.md 为 {id, ts, severity, status, summary}。
///
/// 关闭（status → CLOSED）由修复方 agent 直接编辑该条目完成，本模块不提供
/// 独立 bug_ack（保持最小足迹）。路径一律相对拼接（mem_join），跨平台可移植。

///|
/// 允许的 severity 取值（默认 open）。
fn bug_severities() -> Array[String] {
  ["open", "critical", "high", "medium", "low"]
}

///|
/// severity 是否合法（防枚举外值注入）。
fn bug_severity_ok(sev : String) -> Bool {
  bug_severities().any(fn(s : String) { s == sev })
}

///|
/// 校验项目目录：拒绝空串 / 绝对路径 / 路径穿越（".."、盘符、前导分隔符）。
fn bug_project_dir_ok(dir : String) -> Bool {
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
  // 拒绝盘符（如 C:）
  if dir.length() >= 2 && dir[1] == ':' {
    return false
  }
  true
}

///|
/// bugs.md 路径。
fn bug_file_path(project_dir : String) -> String {
  mem_join(mem_dir(project_dir), "bugs.md")
}

///|
/// 在字符串中自 `from` 起找字符，返回下标或 -1。
fn bug_char_index(s : String, ch : Char, from : Int) -> Int {
  let mut i = from
  while i < s.length() {
    if s[i].to_int() == ch.to_int() {
      return i
    }
    i = i + 1
  }
  -1
}

///|
/// 是否 bug 条目头行（`## BUG-<n> [...]`）。
fn bug_is_header(line : String) -> Bool {
  line.has_prefix("## BUG-")
}

///|
/// 取首个 `[...]` 括号内容；无则返回空串。
fn bug_next_bracket(rest : String) -> String {
  let li = bug_char_index(rest, '[', 0)
  if li < 0 {
    return ""
  }
  let ri = bug_char_index(rest, ']', li)
  if ri < 0 {
    return ""
  }
  rest[li + 1:ri].to_string()
}

///|
/// 返回首个 `[...]` 之后的内容（不含括号本身）。
fn bug_after_bracket(rest : String) -> String {
  let li = bug_char_index(rest, '[', 0)
  if li < 0 {
    return rest
  }
  let ri = bug_char_index(rest, ']', li)
  if ri < 0 {
    return rest
  }
  rest[ri + 1:rest.length()].to_string()
}

///|
/// 从头部行解析出 (id, ts, severity, status)。
fn bug_parse_header(line : String) -> (String, String, String, String) {
  let raw = line.trim().to_string()
  // 去掉 "## " 前缀后再定位 id
  let body = if raw.has_prefix("## ") {
    raw[3:raw.length()].to_string()
  } else {
    raw
  }
  let sp = bug_char_index(body, ' ', 0)
  let id = if sp < 0 { body } else { body[0:sp].to_string() }
  let tail = if sp < 0 { "" } else { body[sp + 1:body.length()].to_string() }
  let ts = bug_next_bracket(tail)
  let after_ts = bug_after_bracket(tail)
  let sev = bug_next_bracket(after_ts)
  let status = bug_after_bracket(after_ts).trim().to_string()
  let sure_status = if status.is_empty() { "OPEN" } else { status }
  (id, ts, sev, sure_status)
}

///|
/// 提取 `- key: value` 行的值（key 名匹配则回 Some(value)）。
fn bug_field_value(line : String, key : String) -> String? {
  let t = line.trim().to_string()
  if not(t.has_prefix("- ")) {
    return None
  }
  let body = t[2:t.length()].to_string()
  let colon = bug_char_index(body, ':', 0)
  if colon < 0 {
    return None
  }
  let k = body[0:colon].trim().to_string()
  if k != key {
    return None
  }
  Some(body[colon + 1:body.length()].trim().to_string())
}

///|
/// 把 bugs.md 全文解析为条目 Json 数组。
fn bug_parse(text : String) -> Array[Json] {
  let out : Array[Json] = []
  let mut cur : Map[String, Json] = Map([])
  let mut active : Bool = false
  for raw in text.split("\n") {
    let t = raw.trim().to_string()
    if bug_is_header(t) {
      // 收拢上一条
      if active {
        out.push(Json::object(cur))
      }
      let (id, ts, sev, status) = bug_parse_header(t)
      cur = Map([
        ("id", Json::string(id)),
        ("ts", Json::string(ts)),
        ("severity", Json::string(sev)),
        ("status", Json::string(status)),
        ("summary", Json::string("")),
      ])
      active = true
    } else if active {
      let fields = [
        ("summary", "summary"),
        ("detail", "detail"),
        ("ref_call", "ref_call"),
        ("reported_by", "reported_by"),
        ("task_id", "task_id"),
      ]
      for (jkey, mkey) in fields {
        match bug_field_value(t, mkey) {
          Some(v) => if v != "" { cur.set(jkey, Json::string(v)) }
          None => ()
        }
      }
    }
  }
  if active {
    out.push(Json::object(cur))
  }
  out
}

///|
/// 解析非负整数（bug 序号用；解析失败返回 0）。
fn bug_parse_int(s : String) -> Int {
  let mut acc : Int = 0
  for c in s {
    let ci = c.to_int()
    if ci >= 48 && ci <= 57 {
      acc = acc * 10 + ci - 48
    } else {
      break
    }
  }
  acc
}

///|
/// 计算下一个 bug 序号（解析既有条目的最大 BUG-n，+1；无则从 1 起）。
fn bug_next_seq(text : String) -> Int {
  let mut max_n : Int = 0
  for raw in text.split("\n") {
    let t = raw.trim().to_string()
    if bug_is_header(t) {
      let body = t[3:t.length()].to_string()
      let sp = bug_char_index(body, ' ', 0)
      let id = if sp < 0 { body } else { body[0:sp].to_string() }
      // id = "BUG-n"
      if id.has_prefix("BUG-") {
        let n = bug_parse_int(id[4:id.length()].to_string())
        if n > max_n {
          max_n = n
        }
      }
    }
  }
  max_n + 1
}

///|
/// 上报一个 bug：追加到 memory/bugs.md（OPEN 状态）；publish_task=true 时
/// 把"修复 bug: <summary>"并行发布为 bugs 命名空间下的独立根任务。
pub fn report_bug(
  project_dir : String,
  summary : String,
  detail~ : String,
  severity~ : String,
  ref_call_id~ : String,
  reported_by~ : String,
  publish_task~ : Bool,
  eng : @engine.FistEngine,
  now~ : String,
) -> Result[Json, String] {
  if not(bug_project_dir_ok(project_dir)) {
    return Err(
      "report_bug: 非法 project_dir（拒绝绝对路径/穿越/盘符）",
    )
  }
  if summary.is_empty() {
    return Err("report_bug: summary 不能为空")
  }
  let sev = if severity.is_empty() { "open" } else { severity }
  if not(bug_severity_ok(sev)) {
    return Err(
      "report_bug: 非法 severity=" +
      sev +
      "（合法值：open/critical/high/medium/low）",
    )
  }
  mem_ensure_dir(mem_dir(project_dir))
  let path = bug_file_path(project_dir)
  let old = match mem_read(path) {
    None => ""
    Some(s) => s
  }
  let seq = bug_next_seq(old)
  let bug_id = "BUG-" + seq.to_string()

  // 可选：发布修复根任务（best-effort；失败不阻断落账，仅在返回里体现）
  let mut task_id : String = ""
  if publish_task {
    match
      eng.publish_parallel(
        ns="bugs",
        description="修复 bug: " + summary,
        created_by=if reported_by.is_empty() {
          "bug_reporter"
        } else {
          reported_by
        },
        project_dir~,
        now~,
      ) {
      Ok(id) => task_id = id
      Err(_) => ()
    }
  }

  let lines : Array[String] = []
  lines.push("## " + bug_id + " [" + now + "] [" + sev + "] OPEN\n")
  lines.push("- summary: " + summary + "\n")
  if not(detail.is_empty()) {
    lines.push("- detail: " + detail + "\n")
  }
  if not(ref_call_id.is_empty()) {
    lines.push("- ref_call: " + ref_call_id + "\n")
  }
  if not(reported_by.is_empty()) {
    lines.push("- reported_by: " + reported_by + "\n")
  }
  if not(task_id.is_empty()) {
    lines.push("- task_id: " + task_id + "\n")
  }
  lines.push("\n")
  let entry = lines.fold_left(init="", fn(acc, l) { acc + l })
  if not(mem_write(path, old + entry)) {
    return Err("report_bug: 写入 bugs.md 失败: " + path)
  }
  let m : Map[String, Json] = Map([])
  m.set("bug_id", Json::string(bug_id))
  m.set("status", Json::string("OPEN"))
  m.set("path", Json::string(path))
  if not(task_id.is_empty()) {
    m.set("task_id", Json::string(task_id))
  }
  Ok(Json::object(m))
}

///|
/// 列出 {project_dir}/memory/bugs.md 里的 bug 条目（含 status 的均返回）。
pub fn bug_list(project_dir : String) -> Result[Json, String] {
  if not(bug_project_dir_ok(project_dir)) {
    return Err(
      "bug_list: 非法 project_dir（拒绝绝对路径/穿越/盘符）",
    )
  }
  let path = bug_file_path(project_dir)
  let text = match mem_read(path) {
    None => ""
    Some(s) => s
  }
  let entries = bug_parse(text)
  Ok(
    Json::object({
      "path": Json::string(path),
      "count": Json::number(entries.length().to_double()),
      "bugs": Json::array(entries),
    }),
  )
}
