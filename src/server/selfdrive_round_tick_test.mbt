/// selfdrive_round_tick_test.mbt —— R115 v1 测试
/// 四层判定：L1 卡死 → L2 目标达成 → L3 轮次耗尽 → L4 继续

///|
fn mk_snap(
  inflight : Int,
  ready : Int,
  done : Int,
  blocked : Int,
  target : String,
  idle : Int,
  round_n : Int,
  artifacts : Array[Json],
) -> Json {
  let m : Map[String, Json] = Map([])
  m.set("namespace", Json::string("scratch"))
  m.set("round_n", Json::number(round_n.to_double()))
  m.set("target_text", Json::string(target))
  m.set("idle_secs", Json::number(idle.to_double()))
  m.set("watchdog_timeout_sec", Json::number(7200.0))
  m.set("in_flight", Json::number(inflight.to_double()))
  m.set("ready_count", Json::number(ready.to_double()))
  m.set("done_count", Json::number(done.to_double()))
  m.set("blocked_count", Json::number(blocked.to_double()))
  m.set("round_threshold_pct", Json::number(95.0))
  m.set("artifacts_passed", Json::array(artifacts))
  m.set("evidence_text", Json::string("测试快照"))
  Json::object(m)
}

///|
fn ok(path : String) -> Json {
  let m : Map[String, Json] = Map([])
  m.set("path", Json::string(path))
  m.set("ok", Json::boolean(true))
  Json::object(m)
}

///|
fn verdict_of(r : Json) -> String {
  match r {
    Object(m) =>
      match m.get("verdict") {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
}

///|
fn action_of(r : Json) -> String {
  match r {
    Object(m) =>
      match m.get("action") {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
}

// === L1 卡死 ===

///|
test "R115 L1 卡死：idle > timeout → STALLED" {
  let snap = mk_snap(0, 0, 5, 0, "- [x] README.md", 10000, 1, [ok("README.md")])
  let r = selfdrive_round_tick(snap)
  assert_eq(verdict_of(r), "STALLED")
  assert_eq(action_of(r), "HEAL_OR_END")
}

///|
test "R115 L1 不误报：idle < timeout → 非 STALLED" {
  let snap = mk_snap(3, 2, 5, 0, "- [x] README.md", 3000, 1, [ok("README.md")])
  let r = selfdrive_round_tick(snap)
  assert_eq(verdict_of(r) == "STALLED", false)
}

// === L2 目标达成 ===

///|
test "R115 L2 目标达成：required 全命中 → GOAL_ACHIEVED" {
  let snap = mk_snap(0, 0, 10, 0, "- [x] README.md\n- [x] moon.mod", 100, 2, [
    ok("README.md"),
    ok("moon.mod"),
  ])
  let r = selfdrive_round_tick(snap)
  assert_eq(verdict_of(r), "GOAL_ACHIEVED")
  assert_eq(action_of(r), "STOP_ALL")
}

///|
test "R115 L2 部分命中不达成" {
  let snap = mk_snap(
    2,
    1,
    5,
    0,
    "- [x] 不存在的终极目标-xyzzy.abc\n- 另一个永远不会命中的条件-QRSTUV",
    100,
    1,
    [ok("README.md")],
  )
  let r = selfdrive_round_tick(snap)
  assert_eq(verdict_of(r) == "GOAL_ACHIEVED", false)
}

// === L3 轮次耗尽 ===

///|
test "R115 L3 轮次耗尽：95%+ done 无阻塞无活跃 → ROUND_COMPLETE" {
  let snap = mk_snap(
    0,
    0,
    20,
    0,
    "- [x] 不存在的终极目标-xyzzy.abc",
    60,
    1,
    [ok("README.md")],
  )
  let r = selfdrive_round_tick(snap)
  assert_eq(verdict_of(r), "ROUND_COMPLETE")
  assert_eq(action_of(r), "START_NEXT_ROUND")
}

///|
test "R115 L3 有阻塞不算耗尽" {
  let snap = mk_snap(
    0,
    0,
    20,
    2,
    "- [x] 不存在的终极目标-xyzzy.abc",
    60,
    1,
    [ok("README.md")],
  )
  let r = selfdrive_round_tick(snap)
  assert_eq(verdict_of(r), "CONTINUE")
}

///|
test "R115 L3 有活跃不算耗尽" {
  let snap = mk_snap(
    1,
    1,
    20,
    0,
    "- [x] 不存在的终极目标-xyzzy.abc",
    60,
    1,
    [ok("README.md")],
  )
  let r = selfdrive_round_tick(snap)
  assert_eq(verdict_of(r), "CONTINUE")
}

// === L4 继续 ===

///|
test "R115 L4 正常推进 → CONTINUE" {
  let snap = mk_snap(
    3,
    2,
    15,
    1,
    "- [x] 不存在的终极目标-xyzzy.abc",
    300,
    1,
    [ok("README.md")],
  )
  let r = selfdrive_round_tick(snap)
  assert_eq(verdict_of(r), "CONTINUE")
  assert_eq(action_of(r), "PICK_NEXT")
}

// === 卡死优先 ===

///|
test "R115 卡死优先于达成" {
  // 达成条件全满足 + 卡死 → 应该先判卡死
  let snap = mk_snap(0, 0, 10, 0, "- [x] README.md", 10000, 1, [ok("README.md")])
  let r = selfdrive_round_tick(snap)
  assert_eq(verdict_of(r), "STALLED")
}
