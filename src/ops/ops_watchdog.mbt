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
  active : Int32,
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
///   autodispatch      是否在显式 ns 无人值守且无活跃任务时，调引擎层 store-backed
///                     dispatch_next 把顶部待领取任务按能力/负载认领给最佳执行者
///                     （默认 false，零回归；结果并入 detail.autodispatch）。
///   autodispatch_want dispatch_next 所需能力标签（autodispatch=true 时按此能力路由执行者）。
///   phi_gate         是否启用 Phi Accrual 概率式判活（R90，默认 false 零回归）：true 时
///                     心跳超时判定改用概率怀疑度 φ（读持久化间隔历史 + elapsed），
///                     φ≥phi_threshold 判 suspect 才回滚——心跳节奏越快、越久没来才值得怀疑；
///                     false 时维持既有固定 timeout_sec 语义。
///   phi_threshold    phi_gate=true 时的怀疑阈值（默认 8，原论文口径）。
///
/// 返回 JSON：{ action, active, healed, healed_tasks, new_task_id,
///             previous_task_id, blocked, detail, omega }，
///             action ∈ waiting / restarted / advanced / idle。

///|
/// BUG-166：判断 ISO 时间戳 b 是否比 a「更新」（更晚完成）。用秒数比较；任一侧
/// 解析失败（空串/非法 ISO）保守返回 false（不覆盖既有选择），保证续轮链不下跳。
fn watchdog_ts_newer(a : String, b : String) -> Bool {
  let sa = iso_to_secs(a)
  let sb = iso_to_secs(b)
  if sa < 0 || sb < 0 {
    return false
  }
  sb > sa
}

///|
/// BUG-166：续轮选 prev_task 时，b 是否比 a「更新」（等价于 `watchdog_ts_newer`）。
fn watchdog_newer_task(a : @core.Task, b : @core.Task) -> Bool {
  watchdog_ts_newer(a.get_updated_at(), b.get_updated_at())
}

///|
pub fn watchdog_tick(
  engine : @engine.FistEngine,
  now : String,
  timeout_sec~ : Int32 = 600,
  ns~ : String = "",
  next_description~ : String = "",
  next_created_by~ : String = "watchdog",
  meta_prompt_path~ : String = "",
  cold_start~ : Bool = false,
  project_dir~ : String = "",
  omega_strong_verify~ : Bool = false,
  omega_split_n~ : Int32 = 3,
  omega_spec~ : Json? = None,
  selfdrive_project_dir~ : String = "",
  selfdrive_review_every~ : Int32 = 3,
  autodispatch~ : Bool = false,
  autodispatch_want~ : String = "",
  phi_gate~ : Bool = false,
  phi_threshold~ : Int32 = 8,
  mode~ : String = "",
) -> Result[Json, String] {
  let heal_ns = if ns == "" { "default" } else { ns }
  // ---- 1. 回滚阶段（功能 A：读 SQLite 心跳，跨进程正确） ----
  // R90：phi_gate=true 时用概率怀疑度 φ 判活（默认关闭零回归），否则既有固定 timeout。
  // BUG-27：φ 分支缺间隔历史时内部回落到同一个 timeout_sec，两条路径的恢复能力可比。
  let phi_no_history : Array[String] = []
  let delete_failed : Array[String] = []
  let mut heal_error : String? = None
  let healed = if phi_gate {
    match
      heal_stale_tasks_by_phi(
        engine,
        now,
        phi_threshold~,
        ns=heal_ns,
        timeout_sec~,
        no_history_ids=phi_no_history,
        delete_failed_ids=delete_failed,
      ) {
      Ok(l) => l
      Err(e) => {
        heal_error = Some(e)
        []
      }
    }
  } else {
    match
      heal_stale_tasks_from_store(
        engine,
        now,
        timeout_sec~,
        ns=heal_ns,
        delete_failed_ids=delete_failed,
      ) {
      Ok(l) => l
      Err(e) => {
        heal_error = Some(e)
        []
      }
    }
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
        // BUG-166：续轮选 prev_task 不能依赖 list_in_ns 的未定义顺序——
        // SqliteStore 无 ORDER BY、MemoryStore 走 Map.each（皆插入序），多个未标记
        // 完成根任务时无条件覆盖会串错续轮链。显式保留「最近完成的一条」。
        let is_newer = match pending_advance {
          Some(prev) => watchdog_newer_task(prev, t)
          None => true
        }
        if is_newer {
          pending_advance = Some(t)
        }
      }
    }
  }
  // ---- 3. 模式模板解析（R117 mode 参数扩展，零回归：不传则走旧路径） ----
  let mode_str = mode.trim().to_owned()
  let effective_meta_path = if mode_str == "" || mode_str == "advance" {
    // mode 为空 或 advance → 走用户显式传的 meta_prompt_path（零回归）
    meta_prompt_path
  } else {
    // 非 advance：先校验 mode 值合法性
    match parse_mode(mode_str) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
    let tp = template_probe_path(mode_str)
    if @fs.path_exists(tp) {
      tp // mode 指定的模板存在 → 覆盖
    } else {
      // BUG-375：判定基准与 mode_list 的 template_path 同一根（env 优先 / cwd 兜底），
      // 并回执**实际探测的绝对路径**——驱动据此人工核对，不再误以为模板全缺而降级空转。
      return Err("mode=" + mode_str + " 模板不存在: " + tp)
    }
  }
  // ---- 4. 解析下一轮描述（显式描述优先，其次读元提示词文档 / mode 模板） ----
  let mut next_desc = next_description
  let mut meta_used = false
  if next_desc == "" && effective_meta_path != "" {
    match read_meta_prompt(effective_meta_path) {
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
  // 无人值守派发预览（R51，纯读零回归）：显式传 ns 时，用 engine.triage 给出"下一单可自动派发"的
  // 候选（不自动认领——完整派发走 server 自驱派单，避免 ops 仓与进程内 exec_reg 耦合）。
  // 只读快照，供外部 cron/agent 一看就知道"此刻可对哪条按能力/难度自动接单"。
  let ready_preview : Json = if ns != "" {
    let tri = engine.triage(heal_ns, "watchdog", "")
    match tri.value("suggestion") {
      Some(Object(sm)) => {
        let tid = match sm.get("task_id") {
          Some(Json::String(s)) => s
          _ => ""
        }
        let reason = match sm.get("reason") {
          Some(Json::String(r)) => r
          _ => ""
        }
        Json::object({
          "task_id": Json::string(tid),
          "note": Json::string(reason),
          "hint": Json::string(
            "可对这条调 selfdrive_dispatch/schedule 做能力路由自治派单",
          ),
        })
      }
      _ =>
        Json::object({
          "task_id": Json::string(""),
          "note": Json::string(
            "无待领取且依赖满足的任务，无需派发",
          ),
        })
    }
  } else {
    Json::null()
  }
  let mut detail = Json::object({
    "namespace": Json::string(heal_ns),
    "scanned": Json::number(tasks.length().to_double()),
    "active_tasks": Json::object(active_detail),
    "blocked_detail": Json::array(blocked_ids.map(fn(s) { Json::string(s) })),
    // BUG-77：调用方给的那份与被读的那份**分栏回**，只回前者＝回执说谎
    "meta_prompt_path": Json::string(meta_prompt_path),
    "meta_prompt_resolved": Json::string(effective_meta_path),
    "meta_prompt_overridden": Json::boolean(
      effective_meta_path != meta_prompt_path,
    ),
    "meta_prompt_used": Json::boolean(meta_used),
    "phi_gate": Json::boolean(phi_gate),
    // BUG-27 建议②：披露哪些活跃任务不是由 φ 建模判活、而是由固定 timeout 兜底判的。
    // 没有这一栏时，phi_gate=true 的恢复行为与 false 差在哪只能靠读源码知道。
    "phi_timeout_fallback_ids": Json::array(
      phi_no_history.map(fn(s) { Json::string(s) }),
    ),
    "phi_judged_by": Json::string(
      if phi_gate {
        "有心跳间隔历史的按 φ；无历史、或 φ 返回 insufficient/rejected 的按 timeout_sec 兜底（本栏列兜底的那些）"
      } else {
        "phi_gate=false：全部按固定 timeout_sec 判活"
      },
    ),
    // BUG-240：回滚成功但清理持久化心跳失败的条目必须点名——残留心跳行会让下一轮
    // from_store 把已回滚任务误判为「仍在执行」，回执不得只报 healed 成功。
    "heartbeat_delete_failed_ids": Json::array(
      delete_failed.map(fn(s) { Json::string(s) }),
    ),
    "selfdrive": sd_detail,
    "ready_dispatch_preview": ready_preview,
    "autodispatch": Json::null(),
    "mode": Json::string(if mode_str == "" { "advance" } else { mode_str }),
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
    match pending_advance {
      Some(prev) =>
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
          Err(e) => {
            let new_m : Map[String, Json] = Map([])
            match detail {
              Object(m) =>
                for k, v in m {
                  new_m.set(k, v)
                }
              _ => ()
            }
            new_m.set("advance_error", Json::string(e))
            detail = Json::object(new_m)
          }
        }
      None =>
        if cold_start {
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
            Err(e) => {
              // BUG-225：冷启动发布失败不能静默吞掉——否则调用方只看到 action="idle"，
              // 无法区分「无任务可发布」与「冷启动失败」（default 命名空间拒绝冷启动、
              // 已有任务拒绝重复发布、或 DB/IO 瞬时错误）。与上方 publish_next_round
              // 失败分支保持一致，把原因并入 detail.cold_start_error 供调用方判别；
              // 仍退化为 idle，保持 D-3/D-4 既有语义零回归。
              let new_m : Map[String, Json] = Map([])
              match detail {
                Object(m) =>
                  for k, v in m {
                    new_m.set(k, v)
                  }
                _ => ()
              }
              new_m.set("cold_start_error", Json::string(e))
              detail = Json::object(new_m)
            }
          }
        }
    }
  }
  // ---- 6. 默认：等待 / 空闲 ---- 
  let action = if !active_ids.is_empty() { "waiting" } else { "idle" }
  // R57 自治派单（默认关闭，零回归）：显式 ns 无人值守且无活跃任务时，
  // 调引擎层 store-backed `dispatch_next` 把顶部可领取任务按能力/负载路由认领给最佳执行者，
  // 结果并入 detail.autodispatch，不改动既有 waiting/idle 语义。
  if autodispatch && ns != "" && active_ids.is_empty() {
    let ad = engine.dispatch_next(
      heal_ns, next_created_by, autodispatch_want, now,
    )
    let detail_new = match detail {
      Object(m) => {
        let new_m : Map[String, Json] = Map([])
        for k, v in m {
          new_m.set(k, v)
        }
        new_m.set("autodispatch", ad)
        Json::object(new_m)
      }
      _ => detail
    }
    detail = detail_new
  }
  match heal_error {
    Some(e) =>
      detail = match detail {
        Object(m) => {
          let new_m : Map[String, Json] = Map([])
          for k, v in m {
            new_m.set(k, v)
          }
          new_m.set("heal_error", Json::string(e))
          Json::object(new_m)
        }
        _ => detail
      }
    None => ()
  }
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
