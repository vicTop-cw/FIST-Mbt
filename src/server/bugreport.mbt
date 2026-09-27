/// bugreport.mbt —— bug 上报 + 清单（"上报 → 修复"闭环）工具实现
///
/// 提供两个 MCP 工具背后的纯逻辑：
///   - report_bug：把一次运行时失败追加写入 {project_dir}/memory/bugs.md
///     （OPEN 状态账本）；publish_task=true 时同时把"修复 bug: <summary>"
///     并行发布为命名空间 bugs 下的独立根任务，供系统自驱认领修复。
///   - bug_list：解析 memory/bugs.md 为 {id, ts, severity, status, summary}。
///
/// 关闭与改判由本模块的 bug_fix / bug_mark_status 完成（BUG-9 之前只能人肉编辑），
/// 状态只存在于抬头一行，正文与叙述面保持追加。路径一律相对拼接（mem_join），跨平台可移植。

///|
/// 允许的 severity 取值（缺省 medium；BUG-88：本集合与账本抬头文法逐字相等，由生成器把关）。
fn bug_severities() -> Array[String] {
  // BUG-88：这套集合必须与账本抬头文法（memory/bugs.md 的 `## BUG-n [时间] [严重度] 状态`）
  // **逐字相等**——gen_plugins 生成前会比对两侧，漂移即 FATAL。
  // 旧集里的 `open` 是个状态词冒充严重度：省略 severity 时默认落 [open]，
  // 而判据只认 high|medium|low ⇒ 一条不传 severity 的正常上报就能把账本写成读不到的抬头。
  ["critical", "high", "medium", "low"]
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
      let (id, ts, sev, raw_status) = bug_parse_header(t)
      // 记账规则（memory/bugs.md 顶部）允许 DUPLICATE 抬头带 `→BUG-m` 主编号；
      // 在这里拆成独立字段回给读侧，status 保持单值，别让调用方自己切字符串。
      let arrow = raw_status.split("→").to_array()
      let (status, dup_of) = if arrow.length() == 2 {
        (arrow[0].trim().to_string(), arrow[1].trim().to_string())
      } else {
        (raw_status, "")
      }
      cur = Map([
        ("id", Json::string(id)),
        // BUG-11：与写侧 report_bug 的 `bug_id` 同名对齐，两个键都给 ⇒ 任一读法都对得上账
        ("bug_id", Json::string(id)),
        ("ts", Json::string(ts)),
        ("severity", Json::string(sev)),
        ("status", Json::string(status)),
        ("summary", Json::string("")),
      ])
      if not(dup_of.is_empty()) {
        cur.set("duplicate_of", Json::string(dup_of))
      }
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
  // BUG-8：修复单落哪个 ns 由调用方决定（缺省 "bugs" ⇒ 既有调用零回归）
  task_ns? : String = "bugs",
  github_sync? : Bool = false,
  github_repo? : String = "",
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
  let sev = if severity.is_empty() { "medium" } else { severity }
  if not(bug_severity_ok(sev)) {
    return Err(
      "report_bug: 非法 severity=" +
      sev +
      "（合法值：critical/high/medium/low；缺省 medium。BUG-88：闭集必须等于抬头文法）",
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
  // BUG-8：修复单落到哪个 ns 由调用方决定（缺省仍 "bugs"，零回归）。
  // 过去这里写死 ns="bugs"，与发起轮的 ns 断裂：按批次 ns 查不到修复单，
  // 「子单全部 verify 后父任务自动上卷」这条生命周期对 issue_up 通道永不触发。
  // 无论有没有发单都把生效 ns 回显出去（空 publish_task 时回空串，不是 "bugs"）。
  let eff_task_ns = if task_ns.is_empty() { "bugs" } else { task_ns }
  if publish_task {
    match
      eng.publish_parallel(
        ns=eff_task_ns,
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
  // BUG-11：写侧叫 bug_id、读侧（bug_list 行）叫 id，按写侧字段名对账的读侧静默拿 null。
  // 两侧都发这两个键 ⇒ 任一字段名都对得上；不删旧键 ⇒ 既有调用零回归。
  m.set("id", Json::string(bug_id))
  m.set("status", Json::string("OPEN"))
  m.set("path", Json::string(path))
  // BUG-5 fix: 补 resolved_path（绝对 + normalize），让落点可审
  m.set("resolved_path", Json::string(bug_resolve_path(project_dir)))
  m.set("project_dir", Json::string(project_dir))
  m.set(
    "task_namespace",
    Json::string(if publish_task { eff_task_ns } else { "" }),
  )
  if not(task_id.is_empty()) {
    m.set("task_id", Json::string(task_id))
  }
  Ok(Json::object(m))
}

///|
/// 列出 {project_dir}/memory/bugs.md 里的 bug 条目（含 status 的均返回）。

///|
/// 带**关联修复单当前状态**的 bug 清单（BUG-9 的读侧出路）。
///
/// 写侧按声明的设计不做状态 API（本模块文件头：关闭由修复方直接编辑条目完成），
/// 但读侧此前只能看到抬头写的 OPEN——账本与任务库两份账于是可以互相矛盾而无人发现
/// （原始证据：Cypy 的 bugs.md 八条全 OPEN，同轮八张修复单 verify 回复全「已完成」）。
/// 这里给每条带 task_id 的条目挂 `linked_task_status`，并汇总 `open_with_linked_done`
/// ——"账本说没修、任务库说修完了"变成一次调用就能看见的数，而不是靠人对照。
/// 状态查询由调用方注入（纯函数不碰引擎，便于白盒锁）。
pub fn bug_list_with_links(
  project_dir : String,
  task_status_of : (String) -> String,
) -> Result[Json, String] {
  match bug_list(project_dir) {
    Err(e) => Err(e)
    Ok(j) => {
      let entries = match j.value("bugs") {
        Some(Array(a)) => a
        _ => []
      }
      let enriched : Array[Json] = []
      let mut open_with_linked_done = 0
      for e in entries {
        match e {
          Object(m) => {
            let status = match m.get("status") {
              Some(Json::String(s)) => s
              _ => ""
            }
            let tid = match m.get("task_id") {
              Some(Json::String(s)) => s
              _ => ""
            }
            let linked = if tid == "" { "" } else { task_status_of(tid) }
            if linked != "" {
              m.set("linked_task_id", Json::string(tid))
              m.set("linked_task_status", Json::string(linked))
            }
            // 只对"抬头仍 OPEN 但关联单已完成"这一类计账——那正是两份账矛盾的形状
            if status == "OPEN" && linked == "已完成" {
              open_with_linked_done = open_with_linked_done + 1
            }
            enriched.push(Json::object(m))
          }
          _ => enriched.push(e)
        }
      }
      let top = match j {
        Object(m) => m
        _ => Map([])
      }
      top.set("bugs", Json::array(enriched))
      top.set(
        "open_with_linked_done",
        Json::number(open_with_linked_done.to_double()),
      )
      top.set(
        "note",
        Json::string(
          "open_with_linked_done>0 ⇒ 账本抬头与任务库当前状态互相矛盾：要么该条已修完但抬头没改 FIXED（记账规则允许就地改抬头），要么修复单被误标完成。linked_task_status 取自任务库实时状态，空串=该条目没有关联修复单或任务已不存在。",
        ),
      )
      Ok(Json::object(top))
    }
  }
}

///|
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
      "project_dir": Json::string(project_dir),
      "resolved_path": Json::string(bug_resolve_path(project_dir)),
      "count": Json::number(entries.length().to_double()),
      "bugs": Json::array(entries),
    }),
  )
}

///|
/// 抬头状态闭集（真源 = 本账本顶部「记账规则」段，2026-09-27 立）。
/// 写侧与判据共用这一份，避免"API 收 Fixed、抬头写 FIXED、投影数成第三种"三套话。
fn bug_status_closed() -> Array[String] {
  ["OPEN", "FIXED", "FALSE_POSITIVE", "DUPLICATE"]
}

///|
/// 按行切正文（与 bug_lines_to_text 互为逆运算：写回时统一补 \n）。
fn bug_lines_of(text : String) -> Array[String] {
  let out : Array[String] = []
  for v in text.split("\n") {
    out.push(v.to_string())
  }
  out
}

///|
fn bug_lines_to_text(lines : Array[String]) -> String {
  let mut acc = ""
  for l in lines {
    acc = acc + l + "\n"
  }
  acc
}

///|
/// 用 / 拼闭集，只为了把违例文案写得可复核（不依赖 Array::join 是否存在）。
fn bug_slash_join(items : Array[String]) -> String {
  let mut acc = ""
  for s in items {
    acc = if acc.is_empty() { s } else { acc + "/" + s }
  }
  acc
}

///|
/// 用逗号+空格拼编号列表：小记抬头 `### FIXED(ts / BUG-a, BUG-b)` 的分隔符口径
/// 必须与 gen_plugins 的 RE_FIXED_IDS 一致，别改成中文顿号（判据认半角逗号）。
fn bug_comma_join(items : Array[String]) -> String {
  let mut acc = ""
  for s in items {
    acc = if acc.is_empty() { s } else { acc + ", " + s }
  }
  acc
}

///|
/// 归一缺陷编号：接受 `9` 与 `BUG-9` 两种写法，一律输出后者。
fn bug_norm_id(bug_id : String) -> String {
  if bug_id.has_prefix("BUG-") {
    bug_id
  } else {
    "BUG-" + bug_id
  }
}

///|
/// 某编号抬头所在行（0-based），找不到回 -1。
fn bug_header_line(lines : Array[String], bug_id : String) -> Int {
  let want = bug_norm_id(bug_id)
  let n = lines.length()
  let mut i = 0
  while i < n {
    let t = lines[i].trim().to_string()
    if bug_is_header(t) && bug_parse_header(t).0 == want {
      return i
    }
    i = i + 1
  }
  -1
}

///|
/// 条目正文的结束行 = 下一条抬头（或文件尾）。
/// 小记只能插在这个界内，否则会把邻居条目的正文吞进本条目的证据里。
fn bug_entry_end(lines : Array[String], from : Int) -> Int {
  let n = lines.length()
  let mut j = from + 1
  while j < n {
    if bug_is_header(lines[j].trim().to_string()) {
      return j
    }
    j = j + 1
  }
  j
}

///|
/// 抬头那一行的三段（编号 / 时间戳 / 严重度）+ 裸状态串（可能带 `→BUG-m`）。
fn bug_split_header(line : String) -> (String, String, String, String, String) {
  let (id, ts, sev, raw_status) = bug_parse_header(line.trim().to_string())
  let parts = raw_status.split("→").to_array()
  let status = parts[0].trim().to_string()
  let main = if parts.length() == 2 { parts[1].trim().to_string() } else { "" }
  (id, ts, sev, status, main)
}

///|
/// 读账本正文；文件不存在按空文处理（"编号不存在"由调用方判，这里不猜）。
fn bug_read_text(project_dir : String) -> String {
  match mem_read(bug_file_path(project_dir)) {
    None => ""
    Some(s) => s
  }
}

///|
fn bug_status_result(
  id : String,
  status : String,
  dup_of : String,
  from : String,
  changed : Bool,
  path : String,
) -> Json {
  let m : Map[String, Json] = Map([])
  m.set("bug_id", Json::string(id))
  m.set("id", Json::string(id))
  m.set("status", Json::string(status))
  m.set("from_status", Json::string(from))
  m.set("changed", Json::boolean(changed))
  if not(dup_of.is_empty()) {
    m.set("duplicate_of", Json::string(dup_of))
  }
  m.set("path", Json::string(path))
  Json::object(m)
}

///|
/// 把一条缺陷的抬头状态就地改掉（BUG-9 的控制面缺口：账本此前只写不销，OPEN 集合永远清不掉）。
///
/// 写盘面**只有一行**：`## BUG-n [时间] [严重度] 状态 [→BUG-m]` 的状态字段被替换，其余字节不动。
/// 叙述面（正文、`### FIXED(...)` 小记、reports/、memory/ 轮次段）按记账规则只追加——
/// 改掉旧状态不销毁历史，历史由那些面承载。同状态重复调用是幂等 no-op。
///
/// 刻意**不**允许直接标 FIXED：那条路会绕过「标 FIXED 必须有一条点名本编号的小记」这道硬门
/// （gen_plugins 生成前自检①），把账本写成生成器拒绝产出的红状态。标修好走 `bug_fix`。
pub fn bug_mark_status(
  project_dir : String,
  bug_id : String,
  new_status : String,
  dup_of? : String,
  evidence? : String,
  ts~ : String,
) -> Result[Json, String] {
  if !bug_project_dir_ok(project_dir) {
    return Err("bug_mark_status: 非法 project_dir")
  }
  if ts.trim().is_empty() {
    return Err(
      "bug_mark_status: 需要 ts（时间戳由调用层服务端盖章）",
    )
  }
  let want = bug_norm_id(bug_id)
  let closed = bug_status_closed()
  if !closed.any(fn(s : String) { s == new_status }) {
    return Err(
      "bug_mark_status: 状态 [" +
      new_status +
      "] 不在闭集 [" +
      bug_slash_join(closed) +
      "] 内",
    )
  }
  if new_status == "FIXED" {
    return Err(
      "bug_mark_status: 标 FIXED 必须走 bug_fix——它同一笔落 ### FIXED 小记；" +
      "只改抬头会撞上 gen_plugins 硬门①（标修好却无小记点名）",
    )
  }
  let path = bug_file_path(project_dir)
  let lines = bug_lines_of(bug_read_text(project_dir))
  let idx = bug_header_line(lines, want)
  if idx < 0 {
    return Err("bug_mark_status: 编号不存在 " + want)
  }
  let (id, h_ts, sev, cur_status, cur_main) = bug_split_header(lines[idx])
  let note_text = match evidence {
    None => ""
    Some(s) => s.trim().to_string()
  }
  let add_note = new_status == "FALSE_POSITIVE" && not(note_text.is_empty())

  let mut new_main = ""
  if new_status == "DUPLICATE" {
    let target = match dup_of {
      None => ""
      Some(s) => bug_norm_id(s)
    }
    if target.is_empty() {
      return Err("bug_mark_status: DUPLICATE 必须带 →BUG-m 主编号")
    }
    if target == want {
      return Err("bug_mark_status: 主编号不能指向自己 " + target)
    }
    let t_idx = bug_header_line(lines, target)
    if t_idx < 0 {
      return Err("bug_mark_status: 主编号 " + target + " 不存在")
    }
    let (_, _, _, t_status, _) = bug_split_header(lines[t_idx])
    if t_status == "DUPLICATE" {
      return Err(
        "bug_mark_status: 主编号 " +
        target +
        " 自身也是 DUPLICATE（链条不允许）",
      )
    }
    new_main = target
  }
  // 幂等：目标状态与主编号都没变、又不需要补误报立据 ⇒ 一个字节都不写。
  if cur_status == new_status && new_main == cur_main && !add_note {
    return Ok(
      bug_status_result(id, new_status, new_main, cur_status, false, path),
    )
  }
  let tail = if new_main.is_empty() { "" } else { " →" + new_main }
  lines[idx] = "## " + id + " [" + h_ts + "] [" + sev + "] " + new_status + tail
  if add_note {
    let end = bug_entry_end(lines, idx)
    lines.insert(end, "- false_positive(" + ts + "): " + note_text)
  }
  let wrote = mem_write(path, bug_lines_to_text(lines))
  if !wrote {
    return Err("bug_mark_status: 写入失败 " + path)
  }
  Ok(bug_status_result(id, new_status, new_main, cur_status, true, path))
}

///|
/// 批量标修好（BUG-9 的控制面正身）：一次调用 = 一批编号的抬头改 FIXED，
/// 外加**一条**点名整批的 `### FIXED(<ts> / BUG-a, BUG-b)` 小记（evidence 写清改了哪个真源、
/// 哪条锁钉住）。
///
/// 为什么必须同一笔写两面：记账规则把「标 FIXED」与「有小记点名」做成互锁（生成器硬门①②），
/// 分两次调用的中间态就是一本生成器拒绝产出的红账本。
/// 幂等：已 FIXED 的条目只补小记、不重改抬头；小记抬头已存在则整笔 no-op。
pub fn bug_fix(
  project_dir : String,
  bug_ids : Array[String],
  evidence~ : String,
  ts~ : String,
) -> Result[Json, String] {
  if !bug_project_dir_ok(project_dir) {
    return Err("bug_fix: 非法 project_dir")
  }
  if ts.trim().is_empty() {
    return Err("bug_fix: 需要 ts（时间戳由调用层服务端盖章）")
  }
  let ev = evidence.trim().to_string()
  if ev.is_empty() {
    return Err(
      "bug_fix: 需要 evidence——空口标修好正是历史上假 GREEN 的来源（记账规则硬门①）",
    )
  }
  if bug_ids.is_empty() {
    return Err("bug_fix: bug_ids 不能为空")
  }
  let path = bug_file_path(project_dir)
  let lines = bug_lines_of(bug_read_text(project_dir))
  let named : Array[String] = []
  let mut changed = 0
  let mut already = 0
  let mut insert_at = 0
  for raw_id in bug_ids {
    let want = bug_norm_id(raw_id)
    let idx = bug_header_line(lines, want)
    if idx < 0 {
      return Err("bug_fix: 编号不存在 " + want)
    }
    let (id, h_ts, sev, cur, cur_main) = bug_split_header(lines[idx])
    if cur == "DUPLICATE" || cur == "FALSE_POSITIVE" {
      return Err(
        "bug_fix: " +
        want +
        " 当前是 " +
        cur +
        "，终态之间不互跳（要改判先回 OPEN）",
      )
    }
    if cur != "FIXED" {
      let tail = if cur_main.is_empty() { "" } else { " →" + cur_main }
      lines[idx] = "## " + id + " [" + h_ts + "] [" + sev + "] FIXED" + tail
      changed = changed + 1
    } else {
      already = already + 1
    }
    named.push(want)
    let e = bug_entry_end(lines, idx)
    if e > insert_at {
      insert_at = e
    }
  }
  let header = "### FIXED(" + ts + " / " + bug_comma_join(named) + ")"
  let exists = lines.any(fn(l : String) { l.trim().to_string() == header })
  if !exists {
    lines.insert(insert_at, "- evidence: " + ev)
    lines.insert(insert_at, header)
    lines.insert(insert_at, "")
  }
  let wrote = mem_write(path, bug_lines_to_text(lines))
  if !wrote {
    return Err("bug_fix: 写入失败 " + path)
  }
  let m : Map[String, Json] = Map([])
  m.set("bug_ids", Json::array(named.map(fn(s : String) { Json::string(s) })))
  m.set("heading_changed", Json::number(changed.to_double()))
  m.set("already_fixed", Json::number(already.to_double()))
  m.set("note_written", Json::boolean(!exists))
  m.set("note_header", Json::string(header))
  m.set("path", Json::string(path))
  Ok(Json::object(m))
}
