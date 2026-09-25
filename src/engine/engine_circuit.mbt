/// engine_circuit.mbt —— 熔断器三态状态机（R104，Nygard Release It! 2007 / Fowler / Azure / AWS 蒸馏落地）。
/// Closed（正常放行，窗口内失败计数）→ 达阈值 → Open（fail-fast 拒绝，微秒返回不耗资源）→
/// 恢复定时器到期 → Half-Open（放行探测请求）→ 探测成功 Closed / 探测失败回 Open。
/// 编排中间层定位：不真调外部服务，状态推进 + 决策（allow_call 指示调用方可否放行），持久化双后端。

///|
/// 上报一次失败并推进熔断状态机。窗口内失败达阈值 → Open（记 opened_at）；Half-Open 探测失败 → 回 Open。
pub fn FistEngine::circuit_fail(
  self : FistEngine,
  ns? : String = "default",
  circuit~ : String,
  now_secs~ : Int,
  window_secs? : Int = 60,
  threshold? : Int = 3,
  recovery_secs? : Int = 30,
) -> Json {
  let row = self.store.cb_get(ns, circuit)
  let (state, failures, w, thr, rec, opened_at, last_fail_ts) = match row {
    None => ("closed", 0, window_secs, threshold, recovery_secs, 0, 0)
    Some(r) => r
  }
  let (new_state, new_failures, new_opened) = if state == "open" {
    // 已熔断：保持 Open（调用方按 allow_call=false 快速失败）
    ("open", failures, opened_at)
  } else if state == "half_open" {
    // Half-Open 探测失败 → 回 Open，重启恢复定时器
    ("open", thr, now_secs)
  } else {
    // Closed：窗口内计数
    let nf = if now_secs - last_fail_ts > w { 1 } else { failures + 1 }
    if nf >= thr {
      ("open", nf, now_secs)
    } else {
      ("closed", nf, 0)
    }
  }
  ignore(
    self.store.cb_save(
      ns,
      circuit,
      new_state,
      new_failures,
      w,
      thr,
      rec,
      new_opened,
      now_secs,
      now_secs.to_string(),
    ),
  )
  cb_json(circuit, new_state, new_failures, w, thr, rec, new_opened, now_secs)
}

///|
/// 上报一次成功：Closed 复位计数；Half-Open 探测成功 → Closed；Open 保持。
pub fn FistEngine::circuit_succeed(
  self : FistEngine,
  ns? : String = "default",
  circuit~ : String,
  now_secs~ : Int,
) -> Json {
  let row = self.store.cb_get(ns, circuit)
  let (state, failures, w, thr, rec, opened_at, last_fail_ts) = match row {
    None => ("closed", 0, 60, 3, 30, 0, 0)
    Some(r) => r
  }
  let (new_state, new_failures, new_opened) = if state == "half_open" {
    ("closed", 0, 0)
  } else if state == "open" {
    ("open", failures, opened_at)
  } else {
    ("closed", 0, 0)
  }
  ignore(
    self.store.cb_save(
      ns,
      circuit,
      new_state,
      new_failures,
      w,
      thr,
      rec,
      new_opened,
      now_secs,
      now_secs.to_string(),
    ),
  )
  cb_json(circuit, new_state, new_failures, w, thr, rec, new_opened, now_secs)
}

///|
/// 查询熔断状态（含 Half-Open 到期判定：Open 且 elapsed≥recovery → 转 Half-Open 放行探测）。
pub fn FistEngine::circuit_status(
  self : FistEngine,
  ns? : String = "default",
  circuit~ : String,
  now_secs~ : Int,
) -> Json {
  let row = self.store.cb_get(ns, circuit)
  let (state, failures, w, thr, rec, opened_at, last_fail_ts) = match row {
    None => ("closed", 0, 60, 3, 30, 0, 0)
    Some(r) => r
  }
  let (eff_state, eff_failures, eff_opened) = if state == "open" &&
    opened_at > 0 &&
    now_secs - opened_at >= rec {
    // 恢复定时器到期 → Half-Open，放行探测
    ignore(
      self.store.cb_save(
        ns,
        circuit,
        "half_open",
        failures,
        w,
        thr,
        rec,
        opened_at,
        now_secs,
        now_secs.to_string(),
      ),
    )
    ("half_open", failures, opened_at)
  } else {
    (state, failures, opened_at)
  }
  cb_json(circuit, eff_state, eff_failures, w, thr, rec, eff_opened, now_secs)
}

///|
fn cb_json(
  circuit : String,
  state : String,
  failures : Int,
  w : Int,
  thr : Int,
  rec : Int,
  opened_at : Int,
  now_secs : Int,
) -> Json {
  let allow = state != "open"
  let m = Map::new()
  m.set("circuit", Json::string(circuit))
  m.set("state", Json::string(state))
  m.set("failures", Json::number(failures.to_double()))
  m.set("window_secs", Json::number(w.to_double()))
  m.set("threshold", Json::number(thr.to_double()))
  m.set("recovery_secs", Json::number(rec.to_double()))
  m.set("opened_at", Json::number(opened_at.to_double()))
  m.set("allow_call", Json::boolean(allow))
  m.set(
    "note",
    Json::string(
      "熔断器三态（Nygard Release It! 2007 / Fowler / Azure 蒸馏）：Closed 放行 / Open fail-fast 拒绝 / Half-Open 放行探测，探测成功回 Closed、失败回 Open。",
    ),
  )
  Json::object(m)
}
