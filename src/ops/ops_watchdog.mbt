/// ops_watchdog.mbt —— 定时任务看门狗编排（watchdog_tick 单入口）
///
/// ⚠ 适用范围声明（对应 reports/2026-09-17-watchdog-cron-plan.md 第 0 节）：
/// **推荐仅用于「定时任务 / 无人值守自动化」场景，不用于人工指挥官任务分配流程。**
/// 看门狗会在「心跳超时」时自动回滚重派、在「上一轮完成」时自动起下一轮；
/// 这两点在无人值守 cron 中正确且必要，但在人工指挥流程里有害
/// （人类指挥官需自行判断任务是真挂了，还是执行者被暂时阻塞）。
/// 因此：自动续轮只作用于调用方**显式传入的 namespace**；未传 namespace 时
/// 只做心跳回滚与状态汇报，绝不自动起新轮；default 人工命名空间语义保持不变。
///
/// 外循环（不属于本仓库）：外部 cron 每 1 分钟调用一次 watchdog_tick，
/// 按返回 action（waiting / restarted / advanced / idle）分支处理。

///|
/// ASCII 数字判定（'0'=48, '9'=57）。
fn is_ascii_digit(c : Char) -> Bool {
  let v = c.to_int()
  v >= 48 && v <= 57
}

///|
/// ASCII 句点判定（'.'=46）。
fn is_dot(c : Char) -> Bool {
  c.to_int() == 46
}

///|
/// 判断目录项名是否符合元提示词文档命名规则 `yyyyMMdd.HH.mm.ss.md`。
pub fn is_meta_prompt_name(name : String) -> Bool {
  let cs = name.to_array()
  // 8 + 1 + 2 + 1 + 2 + 1 + 2 + 1 + 2 = 20
  if cs.length() != 20 {
    return false
  }
  if !is_dot(cs[8]) || !is_dot(cs[11]) || !is_dot(cs[14]) || !is_dot(cs[17]) {
    return false
  }
  for i = 0; i < 8; i = i + 1 {
    if !is_ascii_digit(cs[i]) {
      return false
    }
  }
  for i = 9; i < 11; i = i + 1 {
    if !is_ascii_digit(cs[i]) {
      return false
    }
  }
  for i = 12; i < 14; i = i + 1 {
    if !is_ascii_digit(cs[i]) {
      return false
    }
  }
  for i = 15; i < 17; i = i + 1 {
    if !is_ascii_digit(cs[i]) {
      return false
    }
  }
  // 后缀 .md（'m'=109, 'd'=100）
  cs[18].to_int() == 109 && cs[19].to_int() == 100
}

///|
/// 拼接目录与文件名（沿用目录既有的分隔符风格）。
fn join_path(dir : String, name : String) -> String {
  if dir.has_suffix("\\") || dir.has_suffix("/") {
    dir + name
  } else if dir.contains("/") {
    dir + "/" + name
  } else {
    dir + "\\" + name
  }
}

///|
/// 安全判定路径是否为目录（不存在/异常均返回 false，不抛错）。
fn safe_is_dir(path : String) -> Bool {
  @fs.is_dir(path) catch {
    _ => false
  }
}

///|
/// 安全读取文本文件（失败返回 None，不抛错）。
fn safe_read_text(path : String) -> String? {
  Some(@fs.read_file_to_string(path, encoding="utf8")) catch {
    _ => None
  }
}

///|
/// 在目录中挑选最新一份元提示词文档：命名规则 `yyyyMMdd.HH.mm.ss.md`，
/// 忽略下划线开头的辅助文件；等宽格式下字典序即时间序。无合法文档返回 None。
pub fn latest_meta_prompt_in_dir(dir : String) -> String? {
  let names = @fs.read_dir(dir) catch { _ => return None }
  let mut best : String? = None
  for n in names {
    if n.has_prefix("_") {
      continue
    }
    if !is_meta_prompt_name(n) {
      continue
    }
    match best {
      None => best = Some(n)
      Some(b) => if n > b { best = Some(n) }
    }
  }
  best
}

///|
/// 读取元提示词文档内容：path 可为单个文档，或一个目录
/// （目录内按 yyyyMMdd.HH.mm.ss.md 命名规则取最新一份、忽略下划线开头的辅助文件）。
/// 路径不存在 / 读取失败 / 内容为空一律返回 None，**绝不 panic**。
pub fn read_meta_prompt(path : String) -> String? {
  if path == "" {
    return None
  }
  if !@fs.path_exists(path) {
    return None
  }
  let target = if safe_is_dir(path) {
    match latest_meta_prompt_in_dir(path) {
      None => return None
      Some(f) => join_path(path, f)
    }
  } else {
    path
  }
  match safe_read_text(target) {
    None => None
    Some(c) => if c == "" { None } else { Some(c) }
  }
}

///|
/// 读持久化心跳表，按 task_id 建 last_seen 索引。
fn heartbeat_index(engine : @engine.FistEngine) -> Map[String, String] {
  let m : Map[String, String] = Map([])
  for row in engine.store_list_heartbeats() {
    let (_agent_id, task_id, last_seen, _status) = row
    if task_id != "" {
      m.set(task_id, last_seen)
    }
  }
  m
}

///|
/// 可选字符串 -> Json（None 输出 null）。
fn opt_str_json(v : String?) -> Json {
  match v {
    Some(s) => Json::string(s)
    None => Json::null()
  }
}

///|
/// 组装 tick 返回 JSON（结构稳定，供外部 cron 分支判断）。
fn tick_json(
  action : String,
  active : Int,
  healed : Array[String],
  new_task_id : String?,
  previous_task_id : String?,
  blocked : Array[String],
  detail : Json,
  omega : Json,
) -> Json {
  Json::object({
    "action": Json::string(action),
    "active": Json::number(active.to_double()),
    "healed": Json::number(healed.length().to_double()),
    "healed_tasks": Json::array(healed.map(fn(s) { Json::string(s) })),
    "new_task_id": opt_str_json(new_task_id),
    "previous_task_id": opt_str_json(previous_task_id),
    "blocked": Json::array(blocked.map(fn(s) { Json::string(s) })),
    "detail": detail,
    "omega": omega,
  })
}

///|
/// 看门狗单次 tick（定时任务单入口，⚠ 推荐仅用于定时任务/无人值守场景）。
///
/// 参数：
///   now               当前时间戳（如 2026-09-17T10:00:00Z）；
///   timeout_sec       心跳超时秒数（默认 600）；
///   ns                作用域命名空间（**可选**：未传则不自动续轮，仅回滚 + 状态汇报）；
///   next_description  下一轮任务描述（未传则本次不续轮，只返回信号）；
///   next_created_by   下一轮任务创建者（默认 watchdog）；
///   meta_prompt_path  元提示词文档路径（可选，支持单文件或目录；目录内按
///                     yyyyMMdd.HH.mm.ss.md 取最新一份、忽略下划线开头的辅助文件）。
///                     当 next_description 未提供时，用该文档内容作为下一轮根任务描述；
///                     路径不存在或读取失败时按「不续轮」处理，不 panic。
///   omega_strong_verify 是否开启 Omega 强验证（默认 false）。开启后：
///                     1) 新根任务 description 追加 [omega:required] 标记；
///                     2) 自动执行 task_plan_deep 拆分并开启强验证子任务；
///                     3) 后续执行/验收受 omega_execute_gate / omega_verify_gate 约束。
///   omega_split_n     Omega 强验证模式下每层拆分数（默认 3）。
///   omega_spec        可选 Omega spec JSON（laws 作切割依据，fingerprint 作验收基准）。
///
/// 返回 JSON：{ action, active, healed, healed_tasks, new_task_id,
///             previous_task_id, blocked, detail, omega }，
///             action ∈ waiting / restarted / advanced / idle。
pub fn watchdog_tick(
  engine : @engine.FistEngine,
  now : String,
  timeout_sec? : Int = 600,
  ns? : String = "",
  next_description? : String = "",
  next_created_by? : String = "watchdog",
  meta_prompt_path? : String = "",
  cold_start? : Bool = false,
  project_dir? : String = "",
  omega_strong_verify? : Bool = false,
  omega_split_n? : Int = 3,
  omega_spec? : Json? = None,
  selfdrive_project_dir? : String = "",
  selfdrive_review_every? : Int = 3,
) -> Result[Json, String] {
  let heal_ns = if ns == "" { "default" } else { ns }
  // ---- 1. 回滚阶段（功能 A：读 SQLite 心跳，跨进程正确） ----
  let healed = match
    heal_stale_tasks_from_store(engine, now, timeout_sec~, ns=heal_ns) {
    Ok(l) => l
    Err(_) => []
  }
  // ---- 2. 扫描作用域内任务，分类活跃 / 阻塞 / 待续轮 ----
  let tasks = engine.list_in_ns(heal_ns)
  let last_seen_map = heartbeat_index(engine)
  let active_ids : Array[String] = []
  let active_detail : Map[String, Json] = Map([])
  let blocked_ids : Array[String] = []
  let mut pending_advance : @core.Task? = None
  for t in tasks {
    let st = t.get_status().to_string()
    if st == "执行中" || st == "已领取" || st == "拆分中" {
      let ls = match last_seen_map.get(t.get_id()) {
        Some(x) => x
        None => ""
      }
      active_ids.push(t.get_id())
      active_detail.set(t.get_id(), Json::string(ls))
    } else if st == "已暂停" || st == "已打回" {
      blocked_ids.push(t.get_id())
    } else if st == "已完成" {
      let is_root = match t.get_parent() {
        Some(_) => false
        None => true
      }
      if is_root && !t.deliverable.has_prefix(@engine.advance_mark_prefix()) {
        pending_advance = Some(t)
      }
    }
  }
  // ---- 3. 解析下一轮描述（显式描述优先，其次读元提示词文档） ----
  let mut next_desc = next_description
  let mut meta_used = false
  if next_desc == "" && meta_prompt_path != "" {
    match read_meta_prompt(meta_prompt_path) {
      Some(c) => {
        next_desc = c
        meta_used = true
      }
      None => ()
    }
  }
  // 自驱整合：启用 selfdrive 时探测审视轮（报告先行），结果附加到 detail.selfdrive。
  // 不改变既有 idle/advanced 语义，仅供通过 watchdog_tick 驱动无人值守时同步推进审视。
  let sd_detail : Json = if selfdrive_project_dir != "" {
    match
      selfdrive_review_tick(
        selfdrive_project_dir,
        ns~,
        review_every=selfdrive_review_every,
      ) {
      Ok(j) => j
      Err(_) => Json::string("selfdrive_review_tick failed")
    }
  } else {
    Json::null()
  }
  let detail = Json::object({
    "namespace": Json::string(heal_ns),
    "scanned": Json::number(tasks.length().to_double()),
    "active_tasks": Json::object(active_detail),
    "blocked_detail": Json::array(blocked_ids.map(fn(s) { Json::string(s) })),
    "meta_prompt_path": Json::string(meta_prompt_path),
    "meta_prompt_used": Json::boolean(meta_used),
    "selfdrive": sd_detail,
  })
  // ---- 4. 心跳超时回滚优先返回 ----
  if !healed.is_empty() {
    return Ok(
      tick_json(
        "restarted",
        active_ids.length(),
        healed,
        None,
        None,
        blocked_ids,
        detail,
        Json::null(),
      ),
    )
  }
  // ---- 5. 完成 -> 自动起下一轮（功能 C，仅当显式指定 ns 且有下一轮描述） ----
  if ns != "" && next_desc != "" {
    if pending_advance.is_some() {
      let prev = pending_advance.unwrap()
      match
        engine.publish_next_round(
          ns~,
          description=next_desc,
          created_by=next_created_by,
          prev_task_id=prev.get_id(),
          now~,
        ) {
        Ok(new_id) => {
          // Omega 强验证：开启后自动拆分并打标记
          let omega_info = if omega_strong_verify {
            match
              engine.plan_deep(
                task_id=new_id,
                split_n=omega_split_n,
                by=next_created_by,
                spec=omega_spec,
                now~,
                omega_strong_verify=true,
              ) {
              Ok(tree) =>
                Json::object({
                  "enabled": Json::boolean(true),
                  "root": Json::string(new_id),
                  "split_n": Json::number(omega_split_n.to_double()),
                  "tree": tree,
                })
              Err(_) =>
                Json::object({
                  "enabled": Json::boolean(false),
                  "error": Json::string("plan_deep failed"),
                })
            }
          } else {
            Json::null()
          }
          return Ok(
            tick_json(
              "advanced",
              active_ids.length(),
              healed,
              Some(new_id),
              Some(prev.get_id()),
              blocked_ids,
              detail,
              omega_info,
            ),
          )
        }
        Err(_) => () // 续轮失败退化为等待/空闲，不 panic
      }
    } else if cold_start {
      // 冷启动：无已完成根任务时，发布首个任务
      let pdir = if project_dir != "" { project_dir } else { "" }
      match
        engine.cold_publish(
          ns~,
          description=next_desc,
          created_by=next_created_by,
          project_dir=pdir,
          now~,
        ) {
        Ok(new_id) => {
          // Omega 强验证：开启后自动拆分并打标记
          let omega_info = if omega_strong_verify {
            match
              engine.plan_deep(
                task_id=new_id,
                split_n=omega_split_n,
                by=next_created_by,
                spec=omega_spec,
                now~,
                omega_strong_verify=true,
              ) {
              Ok(tree) =>
                Json::object({
                  "enabled": Json::boolean(true),
                  "root": Json::string(new_id),
                  "split_n": Json::number(omega_split_n.to_double()),
                  "tree": tree,
                })
              Err(_) =>
                Json::object({
                  "enabled": Json::boolean(false),
                  "error": Json::string("plan_deep failed"),
                })
            }
          } else {
            Json::null()
          }
          return Ok(
            tick_json(
              "advanced",
              active_ids.length(),
              healed,
              Some(new_id),
              None,
              blocked_ids,
              detail,
              omega_info,
            ),
          )
        }
        Err(_) => () // 冷启动失败退化为空闲，不 panic
      }
    }
  }
  // ---- 6. 默认：等待 / 空闲 ---- 
  let action = if !active_ids.is_empty() { "waiting" } else { "idle" }
  Ok(
    tick_json(
      action,
      active_ids.length(),
      healed,
      None,
      None,
      blocked_ids,
      detail,
      Json::null(),
    ),
  )
}
