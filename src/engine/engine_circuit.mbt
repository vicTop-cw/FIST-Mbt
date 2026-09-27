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
///
/// BUG-34：半开态必须**节流**——旧实现 `allow = state != "open"` 让恢复窗内所有调用全部放行，
/// 半开退化成"换个名字的 closed"，正是要防的下游踩踏（工具描述一直承诺"放行探测请求，其余仍快速失败"，
/// 承诺与实现相反）。
/// 配额计数复用已持久化的 `failures` 列（半开态下它的含义是"本恢复窗已放行探测数"）：
/// 不扩 cb 表列 ⇒ 不动 native/js 双后端与既有迁移，也就不必把"跨进程计数"做成分布式预算
/// （上一轮 NOT-FIXED 的理由 ① 因此不成立）。
/// 探测丢失兜底：拿到配额却既不 succeed 也不 fail 时，超过一个 recovery 窗就把配额重置——
/// 否则一次被吞掉的探测会把半开态永久锁在快速失败（那是把旧 bug 换成新 bug）。
pub fn FistEngine::circuit_status(
  self : FistEngine,
  ns? : String = "default",
  circuit~ : String,
  now_secs~ : Int,
  probe_limit? : Int = 1,
) -> Json {
  let row = self.store.cb_get(ns, circuit)
  let (state, failures, w, thr, rec, opened_at, last_ts) = match row {
    None => ("closed", 0, 60, 3, 30, 0, 0)
    Some(r) => r
  }
  // ① Open 到期 → Half-Open，并把"已放行探测数"清零
  let (eff_state, eff_failures) = if state == "open" &&
    opened_at > 0 &&
    now_secs - opened_at >= rec {
    ignore(
      self.store.cb_save(
        ns,
        circuit,
        "half_open",
        0,
        w,
        thr,
        rec,
        opened_at,
        now_secs,
        now_secs.to_string(),
      ),
    )
    ("half_open", 0)
  } else {
    (state, failures)
  }
  if eff_state != "half_open" {
    cb_json(circuit, eff_state, eff_failures, w, thr, rec, opened_at, now_secs)
  } else {
    // ② 探测丢失（一个恢复窗内没有任何上报）⇒ 配额重置
    let stale = rec > 0 && last_ts > 0 && now_secs - last_ts >= rec
    let granted = if stale { 0 } else { eff_failures }
    // probe_limit<=0 = 运维侧显式关掉节流（回到"半开全放行"的旧行为，要在返回体里看得见）
    if probe_limit <= 0 || granted < probe_limit {
      ignore(
        self.store.cb_save(
          ns,
          circuit,
          "half_open",
          granted + 1,
          w,
          thr,
          rec,
          opened_at,
          now_secs,
          now_secs.to_string(),
        ),
      )
      cb_json(
        circuit,
        "half_open",
        granted + 1,
        w,
        thr,
        rec,
        opened_at,
        now_secs,
        probe_limit~,
      )
    } else {
      // 配额用尽：仍半开、仍记着 opened_at（等探测结果或下一个恢复窗），但对调用方快速失败
      cb_json(
        circuit,
        "half_open",
        granted,
        w,
        thr,
        rec,
        opened_at,
        now_secs,
        probe_limit~,
        deny=true,
      )
    }
  }
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
  probe_limit? : Int = 1,
  deny? : Bool = false,
) -> Json {
  let allow = state != "open" && not(deny)
  // 半开态下 failures 复用为"已放行探测数"，另给显式字段，免得读侧按失败数解释
  let probes = if state == "half_open" { failures } else { 0 }
  let m = Map::new()
  m.set("circuit", Json::string(circuit))
  m.set("state", Json::string(state))
  m.set("failures", Json::number(failures.to_double()))
  m.set("window_secs", Json::number(w.to_double()))
  m.set("threshold", Json::number(thr.to_double()))
  m.set("recovery_secs", Json::number(rec.to_double()))
  m.set("opened_at", Json::number(opened_at.to_double()))
  m.set("allow_call", Json::boolean(allow))
  m.set("probes_granted", Json::number(probes.to_double()))
  m.set("probe_limit", Json::number(probe_limit.to_double()))
  m.set(
    "note",
    Json::string(
      "熔断器三态（Nygard Release It! 2007 / Fowler / Azure 蒸馏）：Closed 放行 / Open fail-fast 拒绝 / Half-Open 只放行 probe_limit 次探测（默认 1），探测成功回 Closed、失败回 Open；半开态下 failures=probes_granted（已放行探测数，不是失败数），配额用尽即 allow_call=false，超过一个 recovery 窗无上报则重置。",
    ),
  )
  Json::object(m)
}
