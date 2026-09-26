/// ops_selfdrive.mbt —— 自驱式编程（Self-Driving）模块
///
/// 落地《AI 自驱式编程实验》方法论的 memory 四件套 + 审视轮闭环：
///   <project_dir>/memory/product.md    产品目标（为什么做、给谁用、成功标准）
///   <project_dir>/memory/target.md     当前阶段目标（本轮聚焦什么）
///   <project_dir>/memory/task.md       任务清单（可由任务库导出）
///   <project_dir>/memory/thinking.md   逐轮思考流水（append-only，带时间戳标题）
///   <project_dir>/memory/reviews/      审视报告目录（yyyyMMdd.HH.mm.ss.md）
///   <project_dir>/memory/_review.count 已审视轮次（下划线前缀，辅助文件）
///
/// 与 pipeline_tick 的分工：
///   pipeline_tick 负责「提示词 → 任务 → 报告 → 状态」的常规流水线闭环；
///   本模块负责「沉淀 → 审视 → 自我派活」的自驱增强闭环，二者互相独立。
/// 审视触发：Reports/ 报告数 - 已审视轮次 >= review_every 时，返回 action=review，
///   由外部 agent 依据模板写出审视报告（含 ## Next Tasks 段）落盘到 memory/reviews/，
///   随后 phase=review_ready 推进已审视计数；发布时用 [review:<file>:<idx>] 幂等标记防重。
///
/// action 取值：init / no_memory / idle / review / reviewed / safe_exit /
///              published / wait / parse_failed

// ---------------------------------------------------------------------------
// 路径与文件工具（复用同包 join_path / safe_read_text / latest_meta_prompt_in_dir）
// ---------------------------------------------------------------------------

///|
/// memory 根目录。
fn sd_memory_dir(project_dir : String) -> String {
  join_path(project_dir, "memory")
}

///|
/// memory 四件套路径。
fn sd_kind_path(project_dir : String, kind : String) -> String {
  join_path(sd_memory_dir(project_dir), kind + ".md")
}

///|
/// 审视报告目录。
fn sd_reviews_dir(project_dir : String) -> String {
  join_path(sd_memory_dir(project_dir), "reviews")
}

///|
/// 已审视轮次计数文件。
fn sd_count_path(project_dir : String) -> String {
  join_path(sd_memory_dir(project_dir), "_review.count")
}

///|
/// 确保目录存在（已存在或创建失败均不抛错）。
fn sd_ensure_dir(path : String) -> Unit {
  if @fs.path_exists(path) {
    return
  }
  @fs.create_dir(path) catch {
    _ => ()
  }
}

///|
/// 安全写入文本文件（失败返回 false，不抛错）。
fn sd_write(path : String, content : String) -> Bool {
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
fn sd_read(path : String) -> String? {
  safe_read_text(path)
}

///|
/// 组装返回 JSON。
fn sd_json(
  action : String,
  note : String,
  ns : String,
  extras : Array[(String, Json)],
) -> Json {
  let m : Map[String, Json] = Map([])
  m.set("schema", Json::string("fist.selfdrive/1"))
  m.set("action", Json::string(action))
  m.set("namespace", Json::string(ns))
  m.set("note", Json::string(note))
  for (k, v) in extras {
    m.set(k, v)
  }
  Json::object(m)
}

///|
/// 统计已闭环轮次数：Reports/（兼容 reports/）内合法 yyyyMMdd.HH.mm.ss.md 报告数。
/// 两目录若同时存在，优先 Reports/（协议约定），避免重复计数。
fn sd_round_count(project_dir : String) -> Int {
  let upper = join_path(project_dir, "Reports")
  let lower = join_path(project_dir, "reports")
  let dir = if @fs.path_exists(upper) && safe_is_dir(upper) {
    upper
  } else if @fs.path_exists(lower) && safe_is_dir(lower) {
    lower
  } else {
    return 0
  }
  let names = @fs.read_dir(dir) catch { _ => return 0 }
  let mut n = 0
  for name in names {
    if is_meta_prompt_name(name) {
      n = n + 1
    }
  }
  n
}

///|
/// 取 Reports/（兼容 reports/）内字典序最大的 k 份报告完整路径。
fn sd_recent_reports(project_dir : String, k : Int) -> Array[String] {
  let upper = join_path(project_dir, "Reports")
  let lower = join_path(project_dir, "reports")
  let dir = if @fs.path_exists(upper) && safe_is_dir(upper) {
    upper
  } else if @fs.path_exists(lower) && safe_is_dir(lower) {
    lower
  } else {
    return []
  }
  let names = @fs.read_dir(dir) catch { _ => return [] }
  let valid : Array[String] = []
  for name in names {
    if is_meta_prompt_name(name) {
      valid.push(name)
    }
  }
  valid.sort()
  let n = valid.length()
  let out : Array[String] = []
  let take = if n < k { n } else { k }
  for i = 0; i < take; i = i + 1 {
    out.push(join_path(dir, valid[n - take + i]))
  }
  out
}

///|
/// 简单解析十进制整数（非负，可含前后空白；解析失败返回 None）。
fn sd_parse_int(raw : String) -> Int? {
  let s = raw.trim().to_string()
  if s.is_empty() {
    return None
  }
  let mut v = 0
  for c in s {
    if c < '0' || c > '9' {
      return None
    }
    v = v * 10 + (c.to_int() - '0'.to_int())
  }
  Some(v)
}

///|
/// 读取已审视轮次（缺失视为 0；解析失败视为 0）。
fn sd_reviewed_count(project_dir : String) -> Int {
  match sd_read(sd_count_path(project_dir)) {
    None => 0
    Some(raw) =>
      match sd_parse_int(raw) {
        Some(v) => if v < 0 { 0 } else { v }
        None => 0
      }
  }
}

///|
/// 写已审视轮次（失败返回 false）。
fn sd_write_reviewed(project_dir : String, n : Int) -> Bool {
  sd_write(sd_count_path(project_dir), n.to_string() + "\n")
}

///|
/// 取 memory/reviews/ 内最新一份审视报告（无则 None）。
fn sd_latest_review(project_dir : String) -> String? {
  latest_meta_prompt_in_dir(sd_reviews_dir(project_dir))
}

// ---------------------------------------------------------------------------
// memory 四件套：init / append / get / export_tasks
// ---------------------------------------------------------------------------

///|
/// 初始化 memory 四件套骨架（幂等：已存在的文件不覆盖）。
/// product/target 给出引导模板；task.md 初始为空清单；thinking.md 初始为空流水。
pub fn selfdrive_memory_init(
  project_dir : String,
  ns~ : String,
) -> Result[Json, String] {
  let mem = sd_memory_dir(project_dir)
  sd_ensure_dir(mem)
  sd_ensure_dir(sd_reviews_dir(project_dir))
  let created : Array[String] = []
  let skipped : Array[String] = []
  let files = [
    (
      "product.md", "# 产品目标（Product）\n\n- 为什么做：\n- 给谁用：\n- 成功标准：\n",
    ),
    (
      "target.md", "# 当前阶段目标（Target）\n\n- 本轮聚焦：\n- 验收条件：\n",
    ),
    (
      "task.md", "# 任务清单（Task）\n\n（可由任务库导出，或人工维护）\n",
    ),
    ("thinking.md", "# 思考流水（Thinking）\n\n"),
  ]
  for (name, tpl) in files {
    let p = join_path(mem, name)
    if @fs.path_exists(p) {
      skipped.push(name)
    } else if sd_write(p, tpl) {
      created.push(name)
    }
  }
  Ok(
    sd_json(
      "init",
      "memory 四件套已就绪（已存在项跳过，不覆盖）",
      ns,
      [
        ("created", Json::array(created.map(fn(s) { Json::string(s) }))),
        ("skipped", Json::array(skipped.map(fn(s) { Json::string(s) }))),
      ],
    ),
  )
}

///|
/// 追加/更新 memory 条目。
/// kind ∈ product / target / task / thinking：
///   - thinking 为 append-only 流水，自动附加「## <now>」时间戳标题；
///   - product / target / task 为覆盖写（当前状态视图）。
pub fn selfdrive_memory_append(
  project_dir : String,
  ns~ : String,
  kind~ : String,
  content~ : String,
  now~ : String,
) -> Result[Json, String] {
  let p = sd_kind_path(project_dir, kind)
  if kind == "thinking" {
    let old = match sd_read(p) {
      None => ""
      Some(s) => s
    }
    let entry = "\n## " + now + "\n\n" + content + "\n"
    if sd_write(p, old + entry) {
      Ok(
        sd_json(
          "append",
          "已追加思考流水（时间戳：" + now + "）",
          ns,
          [("kind", Json::string(kind))],
        ),
      )
    } else {
      Err("写入 memory 失败: " + p)
    }
  } else if kind == "product" || kind == "target" || kind == "task" {
    if sd_write(p, content) {
      Ok(
        sd_json("append", "已更新 " + kind + ".md", ns, [
          ("kind", Json::string(kind)),
        ]),
      )
    } else {
      Err("写入 memory 失败: " + p)
    }
  } else {
    Err(
      "未知 memory kind: " +
      kind +
      "（仅支持 product/target/task/thinking）",
    )
  }
}

///|
/// 读取指定 memory 文件。
/// kind ∈ product / target / task / thinking；返回 {exists, content}。
pub fn selfdrive_memory_get(
  project_dir : String,
  ns~ : String,
  kind~ : String,
) -> Result[Json, String] {
  let p = sd_kind_path(project_dir, kind)
  match sd_read(p) {
    None =>
      Ok(
        sd_json(
          "get",
          "memory 文件不存在: " +
          kind +
          ".md（可先 selfdrive_init 初始化）",
          ns,
          [("kind", Json::string(kind)), ("exists", Json::boolean(false))],
        ),
      )
    Some(c) =>
      Ok(
        sd_json("get", "已读取 " + kind + ".md", ns, [
          ("kind", Json::string(kind)),
          ("exists", Json::boolean(true)),
          ("content", Json::string(c)),
        ]),
      )
  }
}

///|
/// 从任务库导出任务清单到 task.md（视图覆盖写）。
/// 输出 markdown 任务树：id + 状态 + 描述（截断至 200 字符）。
pub fn selfdrive_export_tasks(
  engine : @engine.FistEngine,
  project_dir : String,
  ns : String,
) -> Result[Json, String] {
  let tasks = engine.list_in_ns(ns)
  let lines : Array[String] = []
  lines.push("# 任务清单（Task）\n")
  lines.push(
    "（导出时间：" +
    "now" +
    "，共 " +
    tasks.length().to_string() +
    " 条）\n",
  )
  for t in tasks {
    let desc = t.description
    let short = if desc.length() > 200 {
      desc.substring(start=0, end=200) + "..."
    } else {
      desc
    }
    lines.push(
      "- " +
      t.get_id() +
      " [" +
      t.get_status().to_string() +
      "] " +
      short +
      "\n",
    )
  }
  let p = sd_kind_path(project_dir, "task")
  if sd_write(p, lines.fold_left(init="", fn(acc, l) { acc + l })) {
    Ok(
      sd_json(
        "export_tasks",
        "已导出任务清单到 task.md（" +
        tasks.length().to_string() +
        " 条）",
        ns,
        [("count", Json::number(tasks.length().to_double()))],
      ),
    )
  } else {
    Err("写入 task.md 失败: " + p)
  }
}

// ---------------------------------------------------------------------------
// 审视轮状态机
// ---------------------------------------------------------------------------

///|
/// 判断是否到达审视轮次。
/// 规则：Reports/ 报告数 - 已审视轮次 >= review_every → action=review。
/// 触发时返回最近 review_every 份报告路径 + memory 四件套存在性摘要，
/// 供外部 agent 撰写审视报告（模板 templates/review_meta_prompt.md）。
pub fn selfdrive_review_tick(
  project_dir : String,
  ns~ : String,
  review_every~ : Int,
) -> Result[Json, String] {
  let mem = sd_memory_dir(project_dir)
  if !@fs.path_exists(join_path(mem, "product.md")) {
    return Ok(
      sd_json(
        "no_memory",
        "memory 四件套未初始化，请先调用 selfdrive_init 初始化四件套",
        ns,
        [],
      ),
    )
  }
  let rounds = sd_round_count(project_dir)
  let reviewed = sd_reviewed_count(project_dir)
  let pending = rounds - reviewed
  if pending < 0 {
    // 计数异常（例如人工删除报告），仅报不改，绝不写脏数据
    return Ok(
      sd_json(
        "safe_exit",
        "已审视轮次大于报告数（count=" +
        reviewed.to_string() +
        " > rounds=" +
        rounds.to_string() +
        "），拒绝推进，请人工核对",
        ns,
        [
          ("rounds", Json::string(rounds.to_string())),
          ("reviewed", Json::string(reviewed.to_string())),
          ("pending", Json::string(pending.to_string())),
        ],
      ),
    )
  }
  if pending < review_every {
    return Ok(
      sd_json(
        "idle",
        "未到审视轮次（还需 " +
        (review_every - pending).to_string() +
        " 份报告）",
        ns,
        [
          ("rounds", Json::string(rounds.to_string())),
          ("reviewed", Json::string(reviewed.to_string())),
          ("pending", Json::string(pending.to_string())),
          ("review_every", Json::string(review_every.to_string())),
        ],
      ),
    )
  }
  // 触发审视：附最近报告 + memory 四件套摘要
  let recent = sd_recent_reports(project_dir, review_every)
  let kinds = ["product", "target", "task", "thinking"]
  let mem_summary : Array[Json] = []
  for k in kinds {
    let p = sd_kind_path(project_dir, k)
    let exists = @fs.path_exists(p)
    mem_summary.push(
      Json::object({ "kind": Json::string(k), "exists": Json::boolean(exists) }),
    )
  }
  Ok(
    sd_json(
      "review",
      "已到达审视轮次，请按 templates/review_meta_prompt.md 撰写审视报告，落盘到 memory/reviews/yyyyMMdd.HH.mm.ss.md 后调用 phase=review_ready",
      ns,
      [
        ("rounds", Json::string(rounds.to_string())),
        ("reviewed", Json::string(reviewed.to_string())),
        ("pending", Json::string(pending.to_string())),
        ("review_every", Json::string(review_every.to_string())),
        ("recent_reports", Json::array(recent.map(fn(s) { Json::string(s) }))),
        ("memory", Json::array(mem_summary)),
      ],
    ),
  )
}

///|
/// 审视报告落盘后的收口：最新审视报告存在才推进已审视轮次（报告先行）。
/// 推进值 = 当前报告总数（含本次审视覆盖到的轮次）。
pub fn selfdrive_review_ready(
  project_dir : String,
  ns~ : String,
) -> Result[Json, String] {
  let mem = sd_memory_dir(project_dir)
  if !@fs.path_exists(join_path(mem, "product.md")) {
    return Ok(
      sd_json(
        "no_memory",
        "memory 四件套未初始化，请先调用 selfdrive_init 初始化四件套",
        ns,
        [],
      ),
    )
  }
  let latest = sd_latest_review(project_dir)
  match latest {
    None =>
      Ok(
        sd_json(
          "safe_exit",
          "memory/reviews/ 下无审视报告，拒绝推进（报告先行）",
          ns,
          [],
        ),
      )
    Some(f) => {
      let rounds = sd_round_count(project_dir)
      if sd_write_reviewed(project_dir, rounds) {
        Ok(
          sd_json(
            "reviewed",
            "审视报告 " +
            f +
            " 已确认，已审视轮次推进至 " +
            rounds.to_string(),
            ns,
            [
              ("review_file", Json::string(f)),
              ("reviewed", Json::string(rounds.to_string())),
            ],
          ),
        )
      } else {
        Err("写入 _review.count 失败")
      }
    }
  }
}

// ---------------------------------------------------------------------------
// 审视 → 自我派活闭环
// ---------------------------------------------------------------------------

///|
/// 解析审视报告中的 `## Next Tasks` 段。
/// 段内每行格式 `- [任务描述]`；跳过 `- [x]` / `- [X]` 已完成标记。
/// 最多返回 max_tasks 条。
pub fn selfdrive_parse_next_tasks(
  content : String,
  max_tasks~ : Int,
) -> Array[String] {
  let mut in_section = false
  let out : Array[String] = []
  for line in content.split("\n") {
    let l = line.trim()
    if l.starts_with("## ") {
      in_section = l.contains("Next Tasks") || l.contains("Next Task")
      continue
    }
    if !in_section {
      continue
    }
    if l.starts_with("- [x]") || l.starts_with("- [X]") {
      continue
    }
    if l.starts_with("- [") {
      let ls = l.to_string()
      match ls.find("]") {
        Some(end) =>
          if end > 3 {
            let desc = ls.substring(start=3, end~).trim().to_string()
            if desc != "" && out.length() < max_tasks {
              out.push(desc)
            }
          }
        None => ()
      }
    }
  }
  out
}

///|
/// 发布最新审视报告中的 Next Tasks（幂等：description 内嵌 [review:<file>:<idx>] 标记防重）。
/// 发布方式：ns 空 → cold_publish；ns 非空 → publish_next_round（prev 取 ns 内最后一个已完成根任务）。
pub fn selfdrive_publish_next(
  engine : @engine.FistEngine,
  project_dir : String,
  ns~ : String,
  now~ : String,
  max_tasks~ : Int,
) -> Result[Json, String] {
  let latest = match sd_latest_review(project_dir) {
    None =>
      return Ok(
        sd_json(
          "wait",
          "memory/reviews/ 下无审视报告，无可发布任务",
          ns,
          [],
        ),
      )
    Some(f) => f
  }
  let content = match sd_read(join_path(sd_reviews_dir(project_dir), latest)) {
    None =>
      return Ok(
        sd_json("parse_failed", "审视报告读取失败: " + latest, ns, []),
      )
    Some(c) => c
  }
  let tasks = selfdrive_parse_next_tasks(content, max_tasks~)
  if tasks.is_empty() {
    return Ok(
      sd_json(
        "parse_failed",
        "审视报告未解析到 ## Next Tasks 段（或已全部为完成态）: " +
        latest,
        ns,
        [("review_file", Json::string(latest))],
      ),
    )
  }
  // 幂等：扫描 ns 内已发布过的 [review:<file>:<idx>] 标记
  let existing : Map[String, Bool] = Map([])
  for t in engine.list_in_ns(ns) {
    for i = 0; i < tasks.length(); i = i + 1 {
      let marker = "[review:" + latest + ":" + i.to_string() + "]"
      if t.description.contains(marker) {
        existing.set(marker, true)
      }
    }
  }
  let published : Array[String] = []
  let skipped : Array[String] = []
  for i = 0; i < tasks.length(); i = i + 1 {
    let marker = "[review:" + latest + ":" + i.to_string() + "]"
    if existing.contains(marker) {
      skipped.push(tasks[i])
      continue
    }
    let desc = tasks[i] +
      "\n\n<!-- " +
      marker +
      " -->\n\n" +
      sd_agent_contract(tasks[i])
    let new_id = try_publish_one(engine, ns, desc, now, project_dir)
    match new_id {
      Some(id) => {
        published.push(tasks[i])
        existing.set(marker, true)
        ignore(id)
      }
      None => {
        skipped.push(tasks[i])
        break
      }
    }
  }
  let action = if published.is_empty() { "wait" } else { "published" }
  Ok(
    sd_json(
      action,
      "审视任务发布完成（发布 " +
      published.length().to_string() +
      " / 跳过 " +
      skipped.length().to_string() +
      "）",
      ns,
      [
        ("review_file", Json::string(latest)),
        ("published", Json::array(published.map(fn(s) { Json::string(s) }))),
        ("skipped", Json::array(skipped.map(fn(s) { Json::string(s) }))),
      ],
    ),
  )
}

///|
/// 单条发布：追加为同命名空间下的独立并行根任务（审视报告的 Next Tasks 互不依赖）。
/// 复用 publish_parallel：ns 首条与后续多条均以唯一 id 落地，不续轮、不归档、不等前轮完成。
fn try_publish_one(
  engine : @engine.FistEngine,
  ns : String,
  desc : String,
  now : String,
  project_dir : String,
) -> String? {
  match
    engine.publish_parallel(
      ns~,
      description=desc,
      created_by="selfdrive",
      project_dir~,
      now~,
    ) {
    Ok(id) => Some(id)
    Err(_) => None
  }
}

///|
/// Agent Contract 7 字段（five-directions §一 P1 蒸馏）：给自驱发布的任务注入执行纪律，
/// 使每个根任务自带 Objective/Constraints/Tool policy/Stop conditions/Escalation/
/// State discipline/Evidence 七段契约，强化「会自我迭代的 AI 项目管理工具」的执行闭环。
/// 纯函数确定性生成，不改生命周期语义；执行者/验收方可据契约判定「是否按要求做、做对」。
pub fn sd_agent_contract(task : String) -> String {
  "## 执行契约（自驱注入 · Agent Contract）\n- Objective: " +
  task +
  "\n- Constraints: 只完成任务目标与边界内动作；不越权、不改无关文件、不臆造工具或参数\n" +
  "- Tool policy: 用已有的自包含工具（issue_scan 等先查潜问题）；以 `moon test`/`moon check` 真实验证；不调用未列出的工具\n" +
  "- Stop conditions: 完成标准达成即停；失败如实上报原始报错，不以「已完成」糊弄\n" +
  "- Escalation: 无法自决或遇外部阻塞→上报指挥官；不暴力重试\n" +
  "- State discipline: 严守 认领→执行→提交→验收→归档 生命周期；不跳状态\n" +
  "- Evidence: 交付物附可复现验证（文件/命令/测试输出）"
}
