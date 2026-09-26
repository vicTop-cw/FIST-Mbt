/// selfdrive_round_tick.mbt —— 自驱式编程 · 轮次生命周期决策引擎（R115，v1）
///
/// 纯计算、零依赖、不碰 store/文件/网络。
/// 四层判定（按优先级）：
///   L1 卡死检测（STALLED）—— idle_secs > watchdog_timeout_sec
///   L2 目标达成（GOAL_ACHIEVED）—— required 条件全命中 + confidence >= 0.85
///   L3 轮次耗尽（ROUND_COMPLETE）—— 95%+ done + 无阻塞 + 无活跃
///   L4 继续推进（CONTINUE）
///
/// snapshot 必填：in_flight / ready_count / done_count / blocked_count
/// snapshot 可选：idle_secs / watchdog_timeout_sec / round_n / target_text /
///   artifacts_passed / done_task_titles / evidence_text / namespace /
///   total_count / round_threshold_pct / now

///|
fn get_int_field(
  m : Map[String, Json],
  key : String,
  default? : Int = 0,
) -> Int {
  match m.get(key) {
    Some(Number(n)) => n.to_int()
    _ => default
  }
}

///|
fn get_str_field(m : Map[String, Json], key : String) -> String {
  match m.get(key) {
    Some(String(s)) => s
    _ => ""
  }
}

///|
fn get_bool_field(
  m : Map[String, Json],
  key : String,
  default? : Bool = false,
) -> Bool {
  match m.get(key) {
    Some(True) => true
    Some(False) => false
    _ => default
  }
}

///|
fn get_map(snapshot : Json) -> Map[String, Json] {
  match snapshot {
    Object(m) => m
    _ => Map([])
  }
}

///|
fn has_prefix(s : String, prefix : String) -> Bool {
  s.has_prefix(prefix)
}

///|
/// 评估 target 里的关键词是否命中（done_task_titles / evidence_text / artifacts_passed）。
/// conds 格式：["keyword1", "keyword2"] 或 ["- [x] file.md", "- [ ] 三形态对齐"]
fn evaluate_target_simple(target_text : String, snapshot : Json) -> Json {
  let sm = get_map(snapshot)
  // 收集所有证据文本
  let all_text : Array[String] = []
  match sm.get("done_task_titles") {
    Some(Array(arr)) =>
      for t in arr {
        match t {
          Object(tm) => {
            let title = get_str_field(tm, "title")
            let desc = get_str_field(tm, "description")
            if title.length() > 0 {
              all_text.push(title)
            }
            if desc.length() > 0 {
              all_text.push(desc)
            }
          }
          _ => ()
        }
      }
    _ => ()
  }
  match sm.get("evidence_text") {
    Some(String(ev)) => all_text.push(ev)
    _ => ()
  }
  match sm.get("artifacts_passed") {
    Some(Array(arr)) =>
      for a in arr {
        match a {
          Object(am) => {
            let ok = get_bool_field(am, "ok", default=false)
            if ok {
              let apath = get_str_field(am, "path")
              if apath.length() > 0 {
                all_text.push(apath)
              }
            }
          }
          _ => ()
        }
      }
    _ => ()
  }
  let evidence_all = all_text.join(" ")

  // 解析 target 条件
  let required_keywords : Array[String] = []
  let optional_keywords : Array[String] = []
  let lines = target_text.split("\n")
  for raw_line in lines {
    let line = raw_line.trim().to_string()
    if line.length() == 0 {
      continue
    }
    let mut body = ""
    let mut is_req = true
    if has_prefix(line, "- [x]") || has_prefix(line, "- [X]") {
      is_req = true
      body = line.substring(start=5).trim().to_string()
    } else if has_prefix(line, "- [ ]") {
      is_req = false
      body = line.substring(start=5).trim().to_string()
    } else {
      // fallback：整行当 keyword
      body = line
    }
    if body.length() >= 2 {
      if is_req {
        required_keywords.push(body)
      } else {
        optional_keywords.push(body)
      }
    }
  }
  let has_cond = required_keywords.length() > 0 ||
    optional_keywords.length() > 0

  let mut req_matched = 0
  for kw in required_keywords {
    if evidence_all.contains(kw) {
      req_matched = req_matched + 1
    }
  }
  let req_total = required_keywords.length()
  let mut opt_matched = 0
  for kw in optional_keywords {
    if evidence_all.contains(kw) {
      opt_matched = opt_matched + 1
    }
  }
  let opt_total = optional_keywords.length()

  let confidence = if req_total > 0 {
    req_matched.to_double() / req_total.to_double()
  } else if opt_total > 0 {
    opt_matched.to_double() / opt_total.to_double()
  } else {
    let done = get_int_field(sm, "done_count", default=0)
    if done > 0 {
      0.5
    } else {
      0.0
    }
  }

  let m : Map[String, Json] = Map([])
  m.set("confidence", Json::number(confidence))
  m.set("required_matched", Json::number(req_matched.to_double()))
  m.set("required_total", Json::number(req_total.to_double()))
  m.set("optional_matched", Json::number(opt_matched.to_double()))
  m.set("optional_total", Json::number(opt_total.to_double()))
  m.set("has_conditions", Json::boolean(has_cond))
  m.set(
    "matched_keywords",
    Json::number((req_matched + opt_matched).to_double()),
  )
  m.set("total_keywords", Json::number((req_total + opt_total).to_double()))
  Json::object(m)
}

///|
/// 轮次耗尽判定。
fn is_round_exhausted(snapshot : Json, threshold : Double) -> Json {
  let sm = get_map(snapshot)
  let done = get_int_field(sm, "done_count", default=0)
  let blocked = get_int_field(sm, "blocked_count", default=0)
  let inflight = get_int_field(sm, "in_flight", default=0)
  let ready = get_int_field(sm, "ready_count", default=0)
  let denom = if done + blocked > 0 { done + blocked } else { 1 }
  let progress = done.to_double() / denom.to_double()
  let no_blocked = blocked == 0
  let no_active = inflight == 0 && ready == 0
  let exhausted = progress >= threshold && no_blocked && no_active
  let m : Map[String, Json] = Map([])
  m.set("exhausted", Json::boolean(exhausted))
  m.set("progress", Json::number(progress))
  m.set("threshold", Json::number(threshold))
  m.set("done", Json::number(done.to_double()))
  m.set("blocked", Json::number(blocked.to_double()))
  m.set("in_flight", Json::number(inflight.to_double()))
  m.set("ready", Json::number(ready.to_double()))
  m.set("no_blocked", Json::boolean(no_blocked))
  m.set("no_active", Json::boolean(no_active))
  Json::object(m)
}

///|
/// 轮次生命周期决策引擎（v1 核心入口，纯计算零依赖）。
pub fn selfdrive_round_tick(snapshot : Json) -> Json {
  let sm = get_map(snapshot)
  let ns = get_str_field(sm, "namespace")
  let round_n = get_int_field(sm, "round_n", default=1)
  let target = get_str_field(sm, "target_text")
  let idle = get_int_field(sm, "idle_secs", default=0)
  let timeout = get_int_field(sm, "watchdog_timeout_sec", default=7200)
  let now_ts = get_str_field(sm, "now")
  let threshold_pct = get_int_field(sm, "round_threshold_pct", default=95)
  let threshold = threshold_pct.to_double() / 100.0

  // L1: 卡死
  if idle > timeout && timeout > 0 {
    let m : Map[String, Json] = Map([])
    m.set("schema", Json::string("fist.selfdrive.round_tick/1"))
    m.set("verdict", Json::string("STALLED"))
    m.set("action", Json::string("HEAL_OR_END"))
    m.set(
      "reason",
      Json::string(
        "idle_secs=" +
        idle.to_string() +
        " > watchdog_timeout_sec=" +
        timeout.to_string(),
      ),
    )
    m.set("confidence", Json::number(0.9))
    m.set("round_n", Json::number(round_n.to_double()))
    m.set("stalled_secs", Json::number(idle.to_double()))
    m.set("goal_eval", Json::null())
    m.set("round_eval", Json::null())
    m.set("namespace", Json::string(ns))
    m.set("timestamp", Json::string(now_ts))
    return Json::object(m)
  }

  // L2: 目标达成
  let goal_eval = evaluate_target_simple(target, snapshot)
  let goal_conf = match goal_eval {
    Object(gm) =>
      match gm.get("confidence") {
        Some(Number(n)) => n
        _ => 0.0
      }
    _ => 0.0
  }
  let req_total = match goal_eval {
    Object(gm) =>
      match gm.get("required_total") {
        Some(Number(n)) => n.to_int()
        _ => 0
      }
    _ => 0
  }
  let req_matched = match goal_eval {
    Object(gm) =>
      match gm.get("required_matched") {
        Some(Number(n)) => n.to_int()
        _ => 0
      }
    _ => 0
  }
  let has_cond = match goal_eval {
    Object(gm) =>
      match gm.get("has_conditions") {
        Some(True) => true
        _ => false
      }
    _ => false
  }
  let all_req_matched = (req_total == 0 && !has_cond) ||
    (req_total > 0 && req_matched == req_total)
  if has_cond && all_req_matched && goal_conf >= 0.85 {
    let m : Map[String, Json] = Map([])
    m.set("schema", Json::string("fist.selfdrive.round_tick/1"))
    m.set("verdict", Json::string("GOAL_ACHIEVED"))
    m.set("action", Json::string("STOP_ALL"))
    m.set(
      "reason",
      Json::string(
        "目标全部 required 条件命中，confidence=" +
        goal_conf.to_string(),
      ),
    )
    m.set("confidence", Json::number(goal_conf))
    m.set("round_n", Json::number(round_n.to_double()))
    m.set("stalled_secs", Json::number(idle.to_double()))
    m.set("goal_eval", goal_eval)
    m.set("round_eval", Json::null())
    m.set("namespace", Json::string(ns))
    m.set("timestamp", Json::string(now_ts))
    return Json::object(m)
  }

  // L3: 轮次耗尽
  let round_eval = is_round_exhausted(snapshot, threshold)
  let exhausted = match round_eval {
    Object(rm) =>
      match rm.get("exhausted") {
        Some(True) => true
        _ => false
      }
    _ => false
  }
  if exhausted {
    let m : Map[String, Json] = Map([])
    m.set("schema", Json::string("fist.selfdrive.round_tick/1"))
    m.set("verdict", Json::string("ROUND_COMPLETE"))
    m.set("action", Json::string("START_NEXT_ROUND"))
    m.set(
      "reason",
      Json::string(
        "本轮进度已扫干净（无阻塞、无待领取），可启动 round " +
        (round_n + 1).to_string(),
      ),
    )
    m.set("confidence", Json::number(0.9))
    m.set("round_n", Json::number(round_n.to_double()))
    m.set("next_round", Json::number((round_n + 1).to_double()))
    m.set("stalled_secs", Json::number(idle.to_double()))
    m.set("goal_eval", goal_eval)
    m.set("round_eval", round_eval)
    m.set("namespace", Json::string(ns))
    m.set("timestamp", Json::string(now_ts))
    return Json::object(m)
  }

  // L4: 继续
  let inflight = get_int_field(sm, "in_flight", default=0)
  let ready = get_int_field(sm, "ready_count", default=0)
  let tip = if inflight > 0 {
    "项目正常执行中，继续盯紧"
  } else if ready > 0 {
    "有待领取任务，调 task_triage pick_next"
  } else {
    "空闲但目标未达成，调 publish_next 或新需求"
  }
  let m : Map[String, Json] = Map([])
  m.set("schema", Json::string("fist.selfdrive.round_tick/1"))
  m.set("verdict", Json::string("CONTINUE"))
  m.set("action", Json::string("PICK_NEXT"))
  m.set("reason", Json::string(tip))
  m.set("confidence", Json::number(goal_conf))
  m.set("round_n", Json::number(round_n.to_double()))
  m.set("stalled_secs", Json::number(idle.to_double()))
  m.set("goal_eval", goal_eval)
  m.set("round_eval", round_eval)
  m.set("namespace", Json::string(ns))
  m.set("timestamp", Json::string(now_ts))
  Json::object(m)
}
