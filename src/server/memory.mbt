/// memory.mbt —— 自我记忆（Hermes 式）工具实现
///
/// 提供三个 MCP 工具背后的纯逻辑 + 文件操作，逻辑与文件系统解耦以便测试：
///   - memory_consolidate：verify 通过后把交付物/结论收敛写回 memory/{kind}.md
///     （kind 缺省 target；thinking 为 append-only 带时间戳，其余覆盖写）
///   - memory_gc：对 memory/{kind}.md 做「上限 + 软降权归档、不硬删」：
///     超 max_chars 时把文件末尾（老人）条目移入 memory/archive/ 归档保留，
///     正文只保留最新 max_chars 个字符；kind 缺省对四件套全部处理。
///   - memory_link：在 memory/links.md 追加 A-Mem 式关联记录，供检索注入。
///
/// 路径一律用相对路径拼接（join_path），不含盘符，跨 Windows/Linux 可移植。

///|
/// 拼接目录与文件名（沿用目录既有分隔符）。无盘符 / 绝对路径假设。
fn mem_join(dir : String, name : String) -> String {
  if dir.has_suffix("\\") || dir.has_suffix("/") {
    dir + name
  } else if dir.contains("/") || dir.contains("\\") {
    if dir.contains("/") {
      dir + "/" + name
    } else {
      dir + "\\" + name
    }
  } else {
    // 无分隔符时默认用跨平台安全的 "/"（Windows/Linux 均作为目录分隔符接受）
    dir + "/" + name
  }
}

///|
/// memory 根目录。
fn mem_dir(project_dir : String) -> String {
  mem_join(project_dir, "memory")
}

///|
/// memory 归档目录。
fn mem_archive_dir(project_dir : String) -> String {
  mem_join(mem_dir(project_dir), "archive")
}

///|
/// 指定 kind 的记忆正文文件路径。
fn mem_kind_path(project_dir : String, kind : String) -> String {
  mem_join(mem_dir(project_dir), kind + ".md")
}

///|
/// 指定 kind 的归档文件路径（正文外的老人条目落此）。
fn mem_kind_archive_path(project_dir : String, kind : String) -> String {
  mem_join(mem_archive_dir(project_dir), kind + ".archive.md")
}

///|
/// links 关联文件路径。
fn mem_links_path(project_dir : String) -> String {
  mem_join(mem_dir(project_dir), "links.md")
}

///|
/// 确保目录存在（已存在或创建失败均不抛错）。
fn mem_ensure_dir(path : String) -> Unit {
  if @fs.path_exists(path) {
    return
  }
  @fs.create_dir(path) catch {
    _ => ()
  }
}

///|
/// 安全写入文本文件（失败返回 false，不抛错）。
fn mem_write(path : String, content : String) -> Bool {
  let r : Unit? = Some(@fs.write_string_to_file(path, content, encoding="utf8")) catch {
    _ => None
  }
  match r {
    Some(_) => true
    None => false
  }
}

///|
/// 读取文本（缺失/失败返回 None）。
fn mem_read(path : String) -> String? {
  Some(@fs.read_file_to_string(path, encoding="utf8")) catch {
    _ => None
  }
}

///|
/// 记忆正文可用的 kind 集合（thinking 为 append-only，其余覆盖写）。
fn mem_kinds() -> Array[String] {
  ["thinking", "product", "target", "task"]
}

///|
/// kind 是否属于合法集合（防路径遍历：仅允许白名单内 kind）。
fn mem_kinds_contain(kind : String) -> Bool {
  mem_kinds().any(fn(k : String) { k == kind })
}

// ---------------------------------------------------------------------------
// memory_consolidate
// ---------------------------------------------------------------------------

///|
/// 收敛写回记忆正文并返回写后状态。
/// kind 缺省 target；thinking 为 append-only（自动附加 `## <now>` 时间戳标题），
/// 其余覆盖写。返回 {consolidated, kind, chars, note}。
pub fn memory_consolidate(
  project_dir : String,
  task_id : String,
  kind : String,
  content : String,
  now : String,
) -> Result[Json, String] {
  if content.is_empty() {
    return Err("memory_consolidate: content 为空，无可收敛内容")
  }
  if not(mem_kinds_contain(kind)) {
    return Err("memory_consolidate: 非法 kind: \{kind}")
  }
  mem_ensure_dir(mem_dir(project_dir))
  let p = mem_kind_path(project_dir, kind)
  let body = if kind == "thinking" {
    let old = match mem_read(p) {
      None => ""
      Some(s) => s
    }
    old + "\n## " + now + "\n\n" + content + "\n"
  } else {
    content
  }
  if not(mem_write(p, body)) {
    return Err("memory_consolidate: 写入失败 " + p)
  }
  Ok(
    Json::object({
      "consolidated": Json::boolean(true),
      "kind": Json::string(kind),
      "tags": Json::array(["task:" + task_id].map(fn(s) { Json::string(s) })),
      "chars": Json::number(body.length().to_double()),
      "note": Json::string("已写入 memory/" + kind + ".md"),
    }),
  )
}

// ---------------------------------------------------------------------------
// memory_gc —— 上限 + 软降权归档（纯逻辑抽自 memory_gc_apply）
// ---------------------------------------------------------------------------

///|
/// GC 纯逻辑（不含文件系统）：当 content 长度超过 max_chars 时，
/// 把「末尾（老人）」内容切分为归档段，正文只保留最新 max_chars 个字符。
/// 返回 (kept 正文, archived 老人)。未超限时 archived 为空串。
/// 中文安全：按字符（而非字节）截断。
pub fn memory_gc_logic(content : String, max_chars : Int) -> (String, String) {
  let n = content.length()
  if n <= max_chars {
    (content, "")
  } else {
    let cut = if max_chars < 0 { 0 } else { max_chars }
    (
      content.substring(start=n - cut, end=n),
      content.substring(start=0, end=n - cut),
    )
  }
}

///|
/// 对单个 kind 执行 GC（上限 + 软降权归档、不硬删）。
/// 文件不存在返回 {gc:false, kind, exists:false}。
pub fn memory_gc_one(
  project_dir : String,
  kind : String,
  max_chars : Int,
) -> Json {
  // 非法 kind 回退到默认 target，防止路径遍历落到文件系统
  let kind = if mem_kinds_contain(kind) { kind } else { "target" }
  let p = mem_kind_path(project_dir, kind)
  let content = match mem_read(p) {
    None =>
      return Json::object({
        "gc": Json::boolean(false),
        "kind": Json::string(kind),
        "exists": Json::boolean(false),
      })
    Some(c) => c
  }
  let (kept, archived) = memory_gc_logic(content, max_chars)
  if archived.is_empty() {
    return Json::object({
      "gc": Json::boolean(true),
      "kind": Json::string(kind),
      "before_chars": Json::number(content.length().to_double()),
      "after_chars": Json::number(content.length().to_double()),
      "archived_to": Json::string(""),
    })
  }
  // 归档：追加到对应归档文件保留（不硬删）
  mem_ensure_dir(mem_archive_dir(project_dir))
  let arch_path = mem_kind_archive_path(project_dir, kind)
  let arch_old = match mem_read(arch_path) {
    None => ""
    Some(s) => s
  }
  let arch_new = if arch_old.is_empty() {
    archived + "\n"
  } else {
    // 追加一段分隔线，避免与历史归档连成一行
    let sep = if arch_old.has_suffix("\n") { "" } else { "\n" }
    arch_old + sep + archived + "\n"
  }
  if not(mem_write(arch_path, arch_new)) {
    return Json::object({
      "gc": Json::boolean(false),
      "kind": Json::string(kind),
      "note": Json::string("归档写入失败: " + arch_path),
    })
  }
  // 正文只保留最新 max_chars
  if not(mem_write(p, kept)) {
    return Json::object({
      "gc": Json::boolean(false),
      "kind": Json::string(kind),
      "note": Json::string("正文写入失败: " + p),
    })
  }
  Json::object({
    "gc": Json::boolean(true),
    "kind": Json::string(kind),
    "before_chars": Json::number(content.length().to_double()),
    "after_chars": Json::number(kept.length().to_double()),
    "archived_to": Json::string(arch_path),
  })
}

///|
/// 对 memory 四件套逐件执行 GC，返回汇总。
pub fn memory_gc_all(project_dir : String, max_chars : Int) -> Json {
  let results : Array[Json] = []
  for k in mem_kinds() {
    results.push(memory_gc_one(project_dir, k, max_chars))
  }
  Json::object({ "gc": Json::boolean(true), "kinds": Json::array(results) })
}

// ---------------------------------------------------------------------------
// memory_link —— A-Mem 式关联
// ---------------------------------------------------------------------------

///|
/// 追加一条关联记录到 memory/links.md（不存在则创建）。
/// 记录格式：`from -> to  note`。
pub fn memory_link(
  project_dir : String,
  from : String,
  to : String,
  note : String,
) -> Result[Json, String] {
  if from.is_empty() || to.is_empty() {
    return Err("memory_link: from 与 to 均必填")
  }
  mem_ensure_dir(mem_dir(project_dir))
  let p = mem_links_path(project_dir)
  let old = match mem_read(p) {
    None => ""
    Some(s) => s
  }
  let line = from +
    " -> " +
    to +
    (if note.is_empty() { "" } else { "  " + note })
  let body = if old.is_empty() {
    line + "\n"
  } else {
    let sep = if old.has_suffix("\n") { "" } else { "\n" }
    old + sep + line + "\n"
  }
  if not(mem_write(p, body)) {
    return Err("memory_link: 写入失败 " + p)
  }
  Ok(
    Json::object({
      "linked": Json::boolean(true),
      "from": Json::string(from),
      "to": Json::string(to),
    }),
  )
}
