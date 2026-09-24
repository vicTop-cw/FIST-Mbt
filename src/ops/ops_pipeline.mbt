/// ops_pipeline.mbt —— 提示词流水线状态机（pipeline_tick 单入口）
///
/// 与项目级约定 watchdog_meta_prompt.md 的状态机协议一一对应：
///   <project_dir>/currentState.txt                 状态词：Creating / Pending / Running / Closed
///   <project_dir>/Gen_Prompts/yyyyMMdd.HH.mm.ss.md 提示词（下划线开头为辅助文件，忽略）
///   <project_dir>/Reports/<提示词同名>.md           报告（报告先行：报告落盘先于 Closed）
///   <project_dir>/Gen_Prompts/_running.started      Running 起始时间戳
///
/// 针对「项目空转」（定时任务反复唤醒却不产生推进）的四条硬约束：
///   1) 幂等     —— 同一份提示词在命名空间内只发布一次根任务（描述内嵌 [prompt:<file>] 标记）；
///   2) 状态一致 —— 状态文件与 FIST-Mbt 任务状态双向校验，脏态只报不改，绝不空转覆盖；
///   3) 报告先行 —— Closed 必须已有对应报告，否则拒绝推进，确保「有产出才算一轮」；
///   4) 单入口   —— 一次调用返回 action，外部 cron / agent 按 action 分支，无需现场手写脚本。
///
/// ⚠ 与 watchdog_tick 的分工：watchdog_tick 负责「心跳回滚 + 续轮」的底层编排；
/// pipeline_tick 负责「提示词 → 任务 → 报告 → 状态」的上层状态机，仅作用于非 default 命名空间。
///
/// action 取值：generate / prompt_pending / execute / wait / write_report / closed / safe_exit

// ---------------------------------------------------------------------------
// 路径与文件工具
// ---------------------------------------------------------------------------

///|
/// 状态文件名（相对 project_dir）。
fn pipeline_state_path(project_dir : String) -> String {
  join_path(project_dir, "currentState.txt")
}

///|
/// 提示词目录（相对 project_dir）。
fn pipeline_gen_dir(project_dir : String) -> String {
  join_path(project_dir, "Gen_Prompts")
}

///|
/// Running 起始时间戳文件（下划线前缀，属辅助文件，不参与提示词挑选）。
fn pipeline_started_path(project_dir : String) -> String {
  join_path(pipeline_gen_dir(project_dir), "_running.started")
}

///|
/// 确保目录存在（已存在或创建失败均不抛错；调用方自行校验后续写入结果）。
fn ensure_dir(path : String) -> Unit {
  if @fs.path_exists(path) {
    return
  }
  @fs.create_dir(path) catch {
    _ => ()
  }
}

///|
/// 安全写入文本文件（失败返回 false，不抛错）。
fn pipeline_write(path : String, content : String) -> Bool {
  let r : Unit? = Some(@fs.write_string_to_file(path, content, encoding="utf8")) catch {
    _ => None
  }
  match r {
    Some(_) => true
    None => false
  }
}

///|
/// 读流水线状态词。
/// 文件缺失 / 读取失败 -> "absent"；内容不可识别 -> "invalid"。
fn pipeline_state(project_dir : String) -> String {
  match safe_read_text(pipeline_state_path(project_dir)) {
    None => "absent"
    Some(raw) =>
      if raw.contains("Creating") {
        "Creating"
      } else if raw.contains("Pending") {
        "Pending"
      } else if raw.contains("Running") {
        "Running"
      } else if raw.contains("Closed") {
        "Closed"
      } else {
        "invalid"
      }
  }
}

///|
/// 取目录内最新一份提示词文件名（忽略下划线辅助文件），无合法文件返回 None。
fn pipeline_latest_prompt(project_dir : String) -> String? {
  latest_meta_prompt_in_dir(pipeline_gen_dir(project_dir))
}

///|
/// 查找提示词对应的报告文件（报告名 = 提示词名）。
/// 兼容 `Reports/`（协议约定）与 `reports/`（历史小写目录）两种布局。
fn pipeline_report_of(project_dir : String, prompt_name : String) -> String? {
  let upper = join_path(join_path(project_dir, "Reports"), prompt_name)
  if @fs.path_exists(upper) {
    return Some(upper)
  }
  let lower = join_path(join_path(project_dir, "reports"), prompt_name)
  if @fs.path_exists(lower) {
    return Some(lower)
  }
  None
}

///|
/// 提示词在任务描述中的幂等标记（形如 `[prompt:20260920.06.55.14.md]`）。
fn pipeline_marker(prompt_name : String) -> String {
  "[prompt:" + prompt_name + "]"
}

///|
/// 在命名空间内扫描某提示词已发布的任务。
/// 返回 (活跃任务, 该提示词任务总数, 最近一次出现的状态词)。
/// 活跃 = 待领取 / 已领取 / 拆分中 / 执行中 / 待验收。
fn scan_prompt_tasks(
  engine : @engine.FistEngine,
  ns : String,
  prompt_name : String,
) -> (@core.Task?, Int, String) {
  let marker = pipeline_marker(prompt_name)
  let mut active : @core.Task? = None
  let mut count = 0
  let mut latest_status = ""
  for t in engine.list_in_ns(ns) {
    if t.description.contains(marker) {
      count = count + 1
      let st = t.get_status().to_string()
      latest_status = st
      if st == "待领取" ||
        st == "已领取" ||
        st == "拆分中" ||
        st == "执行中" ||
        st == "待验收" {
        active = Some(t)
      }
    }
  }
  (active, count, latest_status)
}

///|
/// 在命名空间内找「已完成且尚未续轮」的根任务（自动续轮的锚点）。
fn find_pending_advance(
  engine : @engine.FistEngine,
  ns : String,
) -> @core.Task? {
  let mut found : @core.Task? = None
  for t in engine.list_in_ns(ns) {
    let is_root = match t.get_parent() {
      Some(_) => false
      None => true
    }
    if is_root &&
      t.get_status().to_string() == "已完成" &&
      !t.deliverable.has_prefix(@engine.advance_mark_prefix()) {
      found = Some(t)
    }
  }
  found
}

// ---------------------------------------------------------------------------
// 返回 JSON 组装
// ---------------------------------------------------------------------------

///|
/// 基线返回结构（字段恒定，缺失项为 null，便于外部脚本稳定解析）。
fn pipeline_json(
  state_in : String,
  state_out : String,
  action : String,
  ns : String,
  note : String,
) -> Json {
  Json::object({
    "schema": Json::string("fist.pipeline_tick/1"),
    "action": Json::string(action),
    "state_in": Json::string(state_in),
    "state_out": Json::string(state_out),
    "namespace": Json::string(ns),
    "note": Json::string(note),
    "prompt_file": Json::null(),
    "prompt_path": Json::null(),
    "prompt_content": Json::null(),
    "report_path": Json::null(),
    "previous_report": Json::null(),
    "task_id": Json::null(),
    "healed": Json::array([]),
  })
}

///|
/// 就地追加 / 覆盖一个字段。
fn pj_set(j : Json, key : String, v : Json) -> Json {
  match j {
    Object(m) => m.set(key, v)
    _ => ()
  }
  j
}

///|
/// 组装一次 tick 的返回（自动推进分支共用）。
fn pj_make(
  state_in : String,
  state_out : String,
  action : String,
  ns : String,
  note : String,
  prompt_file : String?,
  prompt_path : String?,
  prompt_content : String?,
  report_path : String?,
  previous_report : String?,
  task_id : String?,
) -> Json {
  let mut j = pipeline_json(state_in, state_out, action, ns, note)
  match prompt_file {
    Some(s) => j = pj_set(j, "prompt_file", Json::string(s))
    None => ()
  }
  match prompt_path {
    Some(s) => j = pj_set(j, "prompt_path", Json::string(s))
    None => ()
  }
  match prompt_content {
    Some(s) => j = pj_set(j, "prompt_content", Json::string(s))
    None => ()
  }
  match report_path {
    Some(s) => j = pj_set(j, "report_path", Json::string(s))
    None => ()
  }
  match previous_report {
    Some(s) => j = pj_set(j, "previous_report", Json::string(s))
    None => ()
  }
  match task_id {
    Some(s) => j = pj_set(j, "task_id", Json::string(s))
    None => ()
  }
  j
}

// ---------------------------------------------------------------------------
// 主入口
// ---------------------------------------------------------------------------

///|
/// 流水线单次 tick（提示词驱动状态机，⚠ 仅用于定时任务 / 无人值守场景）。
///
/// 参数：
///   project_dir  项目根目录（内含 currentState.txt / Gen_Prompts / Reports）；
///   now          当前时间戳（如 2026-09-20T09:10:00+08:00）；
///   ns           作用域命名空间（默认 cron-auto，不得留空或 default）；
///   timeout_sec  Running 判定超时秒数（默认 2400 = 40 分钟）；
///   phase        调用阶段：
///                auto         （默认）自动推进：读状态 -> 决定动作 -> 写状态 -> 必要时发布任务；
///                prompt_ready 执行者已把新提示词落盘，由本调用把状态置为 Pending；
///                report_ready 执行者已把报告落盘，由本调用校验后把状态置为 Closed；
///   prompt_name  指定提示词文件名（可选，缺省取目录内最新一份）。
///
/// 返回 JSON：{ schema, action, state_in, state_out, namespace, note,
///             prompt_file, prompt_path, prompt_content, report_path,
///             previous_report, task_id, healed }。
/// 失败仅在参数非法 / 状态文件写入失败时返回 Err（绝不写脏数据、绝不 panic）。
pub fn pipeline_tick(
  engine : @engine.FistEngine,
  project_dir : String,
  now : String,
  ns? : String = "cron-auto",
  timeout_sec? : Int = 2400,
  phase? : String = "auto",
  prompt_name? : String = "",
) -> Result[Json, String] {
  if project_dir == "" {
    return Err("project_dir 不能为空")
  }
  if !@fs.path_exists(project_dir) {
    return Err("project_dir 不存在: " + project_dir)
  }
  let ns_final = if ns == "" { "default" } else { ns }
  if ns_final == "default" {
    return Err(
      "pipeline_tick 仅限非 default 命名空间（避免污染人工指挥流程）",
    )
  }
  let gen_dir = pipeline_gen_dir(project_dir)
  ensure_dir(gen_dir)
  let state_path = pipeline_state_path(project_dir)
  let state_in = pipeline_state(project_dir)
  let started_path = pipeline_started_path(project_dir)

  // ---- 阶段一：执行者已落盘提示词 -> Pending ----
  if phase == "prompt_ready" {
    let picked = if prompt_name != "" {
      Some(prompt_name)
    } else {
      pipeline_latest_prompt(project_dir)
    }
    match picked {
      None =>
        Ok(
          pj_make(
            state_in,
            state_in,
            "safe_exit",
            ns_final,
            "未找到任何合法提示词文件，保持原状态（不写脏数据）",
            None,
            None,
            None,
            None,
            None,
            None,
          ),
        )
      Some(pf) => {
        let ppath = join_path(gen_dir, pf)
        let ok = @fs.path_exists(ppath)
        if !ok {
          return Ok(
            pj_make(
              state_in,
              state_in,
              "safe_exit",
              ns_final,
              "指定提示词文件不存在: " + pf,
              Some(pf),
              Some(ppath),
              None,
              None,
              None,
              None,
            ),
          )
        }
        if !pipeline_write(state_path, "Pending") {
          return Err("写入 currentState.txt 失败: " + state_path)
        }
        Ok(
          pj_make(
            state_in,
            "Pending",
            "prompt_pending",
            ns_final,
            "提示词已落盘，状态置 Pending，等待发布执行",
            Some(pf),
            Some(ppath),
            None,
            None,
            None,
            None,
          ),
        )
      }
    }
  } else if phase == "report_ready" {
    let picked = if prompt_name != "" {
      Some(prompt_name)
    } else {
      pipeline_latest_prompt(project_dir)
    }
    match picked {
      None =>
        Ok(
          pj_make(
            state_in,
            state_in,
            "safe_exit",
            ns_final,
            "未找到提示词文件，无法定位报告",
            None,
            None,
            None,
            None,
            None,
            None,
          ),
        )
      Some(pf) =>
        match pipeline_report_of(project_dir, pf) {
          None =>
            // 报告先行：报告缺失时拒绝置 Closed，状态保持不变
            Ok(
              pj_make(
                state_in,
                state_in,
                "write_report",
                ns_final,
                "报告未落盘，拒绝置 Closed（报告先行），请先补写报告",
                Some(pf),
                None,
                None,
                None,
                None,
                None,
              ),
            )
          Some(rp) => {
            if !pipeline_write(state_path, "Closed") {
              return Err("写入 currentState.txt 失败: " + state_path)
            }
            Ok(
              pj_make(
                state_in,
                "Closed",
                "closed",
                ns_final,
                "报告已落盘，状态置 Closed，本轮闭环",
                Some(pf),
                None,
                None,
                Some(rp),
                None,
                None,
              ),
            )
          }
        }
    }
  } else {
    // ---- 阶段二：auto 自动推进 ----
    // 先做一次心跳超时回滚（仅供无人值守场景），结果随返回上报
    let healed = match
      heal_stale_tasks_from_store(engine, now, timeout_sec~, ns=ns_final) {
      Ok(l) => l
      Err(_) => []
    }
    let healed_json = Json::array(healed.map(fn(s) { Json::string(s) }))
    let j = match state_in {
      "absent" | "Creating" | "Closed" =>
        match
          advance_from_idle(
            engine, project_dir, now, ns_final, state_in, state_path,
          ) {
          Ok(x) => x
          Err(e) => return Err(e)
        }
      "Pending" =>
        match
          advance_from_pending(
            engine,
            project_dir,
            now,
            ns_final,
            gen_dir,
            state_path,
            started_path,
            only_prompt=prompt_name,
          ) {
          Ok(x) => x
          Err(e) => return Err(e)
        }
      "Running" =>
        advance_from_running(
          project_dir,
          now,
          ns_final,
          state_path,
          started_path,
          timeout_sec~,
        )
      _ =>
        pj_make(
          state_in,
          state_in,
          "safe_exit",
          ns_final,
          "状态文件内容不可识别，安全退出（未修改任何状态）",
          None,
          None,
          None,
          None,
          None,
          None,
        )
    }
    Ok(pj_set(j, "healed", healed_json))
  }
}

///|
/// 空闲态（absent / Creating / Closed）推进：准备生成新提示词。
/// Closed 时先做「报告先行」校验，上一轮报告缺失则拒绝续轮。
fn advance_from_idle(
  engine : @engine.FistEngine,
  project_dir : String,
  now : String,
  ns : String,
  state_in : String,
  state_path : String,
) -> Result[Json, String] {
  ignore(engine)
  ignore(now)
  let previous = pipeline_latest_prompt(project_dir)
  if state_in == "Closed" {
    match previous {
      Some(prev_p) =>
        match pipeline_report_of(project_dir, prev_p) {
          None =>
            return Ok(
              pj_make(
                state_in,
                "Closed",
                "write_report",
                ns,
                "上一轮已置 Closed 但报告缺失，拒绝续轮（报告先行）",
                Some(prev_p),
                None,
                None,
                None,
                None,
                None,
              ),
            )
          Some(prev_r) => {
            if !pipeline_write(state_path, "Creating") {
              return Err("写入 currentState.txt 失败: " + state_path)
            }
            return Ok(
              pj_make(
                state_in,
                "Creating",
                "generate",
                ns,
                "上一轮报告齐备，可生成本轮提示词",
                None,
                None,
                None,
                None,
                Some(prev_r),
                None,
              ),
            )
          }
        }
      None => ()
    }
  }
  if !pipeline_write(state_path, "Creating") {
    return Err("写入 currentState.txt 失败: " + state_path)
  }
  Ok(
    pj_make(
      state_in,
      "Creating",
      "generate",
      ns,
      "无在途任务，可生成本轮提示词（落盘后调用 phase=prompt_ready）",
      None,
      None,
      None,
      None,
      None,
      None,
    ),
  )
}

///|
/// Pending 推进：把最新提示词**幂等**地发布为根任务，并置 Running。
fn advance_from_pending(
  engine : @engine.FistEngine,
  project_dir : String,
  now : String,
  ns : String,
  gen_dir : String,
  state_path : String,
  started_path : String,
  only_prompt? : String = "",
) -> Result[Json, String] {
  // only_prompt 非空时只处理指定提示词；缺省取目录内最新一份
  let picked = if only_prompt != "" {
    Some(only_prompt)
  } else {
    pipeline_latest_prompt(project_dir)
  }
  let pf = match picked {
    None => {
      if !pipeline_write(state_path, "Creating") {
        return Err("写入 currentState.txt 失败: " + state_path)
      }
      return Ok(
        pj_make(
          "Pending",
          "Creating",
          "generate",
          ns,
          "状态为 Pending 但目录内无合法提示词，回退为 Creating",
          None,
          None,
          None,
          None,
          None,
          None,
        ),
      )
    }
    Some(p) => p
  }
  let ppath = join_path(gen_dir, pf)
  let (active, count, last_status) = scan_prompt_tasks(engine, ns, pf)
  // ---- 幂等分支：该提示词已发布过 ----
  if count > 0 {
    match active {
      Some(t) => {
        // 已发布且任务仍在途：状态纠正为 Running，绝不重复发布
        ignore(pipeline_write(state_path, "Running"))
        return Ok(
          pj_make(
            "Pending",
            "Running",
            "execute",
            ns,
            "该提示词已发布且任务在途（幂等命中，未重复发布），状态纠正为 Running",
            Some(pf),
            Some(ppath),
            None,
            None,
            None,
            Some(t.get_id()),
          ),
        )
      }
      None =>
        return Ok(
          pj_make(
            "Pending",
            "Pending",
            "write_report",
            ns,
            "该提示词任务已非活跃（最近状态: " +
            last_status +
            "），需先落盘报告再由 report_ready 置 Closed",
            Some(pf),
            Some(ppath),
            None,
            None,
            None,
            None,
          ),
        )
    }
  }
  // ---- 首次发布 ----
  let content = match safe_read_text(ppath) {
    Some(c) =>
      if c == "" {
        return Ok(
          pj_make(
            "Pending",
            "Pending",
            "safe_exit",
            ns,
            "提示词文件为空，拒绝发布（不写脏数据）",
            Some(pf),
            Some(ppath),
            None,
            None,
            None,
            None,
          ),
        )
      } else {
        c
      }
    None =>
      return Ok(
        pj_make(
          "Pending",
          "Pending",
          "safe_exit",
          ns,
          "提示词文件读取失败，拒绝发布",
          Some(pf),
          Some(ppath),
          None,
          None,
          None,
          None,
        ),
      )
  }
  let desc = content + "\n\n<!-- " + pipeline_marker(pf) + " -->"
  let tasks = engine.list_in_ns(ns)
  let mut new_id : String? = None
  if tasks.is_empty() {
    match
      engine.cold_publish(
        ns~,
        description=desc,
        created_by="watchdog",
        project_dir~,
        now~,
      ) {
      Ok(i) => new_id = Some(i)
      Err(_) => ()
    }
  } else {
    match find_pending_advance(engine, ns) {
      Some(prev) =>
        match
          engine.publish_next_round(
            ns~,
            description=desc,
            created_by="watchdog",
            prev_task_id=prev.get_id(),
            now~,
          ) {
          Ok(i) => new_id = Some(i)
          Err(_) => ()
        }
      None => ()
    }
  }
  match new_id {
    Some(i) => {
      ignore(pipeline_write(state_path, "Running"))
      ignore(pipeline_write(started_path, now))
      Ok(
        pj_make(
          "Pending",
          "Running",
          "execute",
          ns,
          "已发布本轮根任务（幂等标记 " +
          pipeline_marker(pf) +
          "），等待执行者接管",
          Some(pf),
          Some(ppath),
          Some(content),
          None,
          None,
          Some(i),
        ),
      )
    }
    None =>
      Ok(
        pj_make(
          "Pending",
          "Pending",
          "wait",
          ns,
          "命名空间内仍有在途任务或无可续轮根任务，本轮暂不发布",
          Some(pf),
          Some(ppath),
          Some(content),
          None,
          None,
          None,
        ),
      )
  }
}

///|
/// Running 推进：报告优先；报告缺失则按超时判定是否需补报告。
fn advance_from_running(
  project_dir : String,
  now : String,
  ns : String,
  state_path : String,
  started_path : String,
  timeout_sec~ : Int,
) -> Json {
  let picked = pipeline_latest_prompt(project_dir)
  let pf = match picked {
    None =>
      return pj_make(
        "Running",
        "Running",
        "safe_exit",
        ns,
        "状态为 Running 但目录内无合法提示词，安全退出",
        None,
        None,
        None,
        None,
        None,
        None,
      )
    Some(p) => p
  }
  match pipeline_report_of(project_dir, pf) {
    Some(rp) => {
      ignore(pipeline_write(state_path, "Closed"))
      pj_make(
        "Running",
        "Closed",
        "closed",
        ns,
        "报告已落盘，本轮闭环（状态置 Closed）",
        Some(pf),
        None,
        None,
        Some(rp),
        None,
        None,
      )
    }
    None => {
      let started = match safe_read_text(started_path) {
        Some(s) => s.trim().to_owned()
        None => ""
      }
      let stale = if started == "" {
        true
      } else {
        let t0 = iso_to_secs(started)
        let t1 = iso_to_secs(now)
        if t0 < 0 || t1 < 0 {
          false
        } else {
          t1 - t0 >= timeout_sec
        }
      }
      if stale {
        pj_make(
          "Running",
          "Running",
          "write_report",
          ns,
          "执行超时且报告缺失，需补写报告后再置 Closed",
          Some(pf),
          None,
          None,
          None,
          None,
          None,
        )
      } else {
        pj_make(
          "Running",
          "Running",
          "wait",
          ns,
          "任务执行中且未超时，保持等待",
          Some(pf),
          None,
          None,
          None,
          None,
          None,
        )
      }
    }
  }
}
