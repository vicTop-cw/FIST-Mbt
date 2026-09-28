///|
/// ops_loop_wbtest.mbt —— 组合环 PipelineLoop 白盒测试（≥ 12 条）
/// 覆盖：构造 / 预设 / 校验 / 状态机流转 / 终止条件 / JSON 序列化

// ---------------------------------------------------------------------------
// loop_create
// ---------------------------------------------------------------------------

test "loop_create: 基础构造" {
  let lp = loop_create("t1", ["advance", "verify"], "2026-09-28T00:00:00Z")
  assert_eq(lp.name, "t1")
  assert_eq(lp.steps.length(), 2)
  assert_eq(lp.current_idx, 0)
  assert_eq(lp.round, 0)
  assert_eq(lp.max_rounds, 5)
  assert_eq(lp.created_at, "2026-09-28T00:00:00Z")
}

///|
test "loop_create: 全自定义参数" {
  let lp = loop_create(
    "custom",
    ["bugfind", "fix_and_merge"],
    "now",
    max_rounds = 10,
    stop_on_goal = false,
    stop_on_exceeded = false,
    baseline_test_count = 100,
    baseline_open_bug_count = 5,
  )
  assert_eq(lp.max_rounds, 10)
  assert_eq(lp.stop_on_goal, false)
  assert_eq(lp.stop_on_exceeded, false)
  assert_eq(lp.baseline_test_count, 100)
  assert_eq(lp.baseline_open_bug_count, 5)
}

// ---------------------------------------------------------------------------
// preset_loop
// ---------------------------------------------------------------------------

///|
test "preset_loop: fix-iterate" {
  match preset_loop("fix-iterate") {
    Ok((steps, desc)) => {
      assert_eq(steps.length(), 2)
      assert_eq(steps[0], "bugfind")
      assert_eq(steps[1], "fix_and_merge")
      assert_true(desc.contains("寻虫"))
    }
    _ => assert_true(false)
  }
}

///|
test "preset_loop: build-verify" {
  match preset_loop("build-verify") {
    Ok((steps, _)) => {
      assert_eq(steps.length(), 3)
      assert_eq(steps[0], "advance")
      assert_eq(steps[1], "verify")
      assert_eq(steps[2], "polish")
    }
    _ => assert_true(false)
  }
}

///|
test "preset_loop: full-iterate" {
  match preset_loop("full-iterate") {
    Ok((steps, _)) => assert_eq(steps.length(), 4)
    _ => assert_true(false)
  }
}

///|
test "preset_loop: 未知名称" {
  match preset_loop("no-such-loop") {
    Err(_) => assert_true(true)
    _ => assert_true(false)
  }
}

// ---------------------------------------------------------------------------
// validate_loop_steps
// ---------------------------------------------------------------------------

///|
test "validate_loop_steps: 合法 steps" {
  assert_true(validate_loop_steps(["advance", "bugfind"]).is_none())
  assert_true(
    validate_loop_steps(["advance", "polish", "verify", "bugfind", "fix_and_merge", "tidy"])
      .is_none()
  )
}

///|
test "validate_loop_steps: 空数组" {
  match validate_loop_steps([]) {
    Some(msg) => assert_true(msg.contains("empty"))
    None => assert_true(false)
  }
}

///|
test "validate_loop_steps: 非法 mode" {
  match validate_loop_steps(["advance", "hack"]) {
    Some(msg) => assert_true(msg.contains("hack"))
    None => assert_true(false)
  }
}

// ---------------------------------------------------------------------------
// loop_tick — 空 steps 立即停止
// ---------------------------------------------------------------------------

///|
test "loop_tick: 空 steps 立即停止" {
  let lp = loop_create("empty", [], "now")
  let result = loop_tick(lp, "later")
  assert_true(result.should_stop)
  assert_eq(result.stop_reason, "loop has no steps")
  assert_eq(result.next_mode, "")
}

// ---------------------------------------------------------------------------
// loop_tick — 正常推进
// ---------------------------------------------------------------------------

///|
test "loop_tick: 单步推进 2-steps 环" {
  let lp = loop_create("lp", ["advance", "verify"], "t0")
  let r1 = loop_tick(lp, "t1")
  assert_eq(r1.next_mode, "advance")
  assert_eq(r1.next_step_idx, 1)
  assert_eq(r1.next_round, 0)
  assert_true(not(r1.should_stop))

  let r2 = loop_tick(r1.loop_after, "t2")
  assert_eq(r2.next_mode, "verify")
  assert_eq(r2.next_step_idx, 0)
  assert_eq(r2.next_round, 1)
}

///|
test "loop_tick: 完整走满触发 max_rounds" {
  let lp = loop_create("lp", ["advance"], "t0", max_rounds = 3)
  let mut current = lp
  let mut last_stop = false
  for i in 0..<10 {
    let r = loop_tick(current, "t" + i.to_string())
    current = r.loop_after
    if r.should_stop {
      last_stop = true
      assert_true(r.stop_reason.contains("max_rounds"))
      break
    }
  }
  assert_true(last_stop)
}

// ---------------------------------------------------------------------------
// loop_tick — goal_reached 终止
// ---------------------------------------------------------------------------

///|
test "loop_tick: healthy + 零 blocked → goal_reached" {
  let lp = loop_create("lp", ["advance", "verify"], "t0", stop_on_goal = true)
  let r = loop_tick(
    lp,
    "t1",
    project_health_grade = "healthy",
    blocked_tasks = 0,
  )
  assert_true(r.should_stop)
  assert_true(r.stop_reason.contains("goal_reached"))
  assert_true(r.loop_after.goal_reached)
}

///|
test "loop_tick: healthy 但有 blocked → 不停" {
  let lp = loop_create("lp", ["advance", "verify"], "t0", stop_on_goal = true)
  let r = loop_tick(
    lp,
    "t1",
    project_health_grade = "healthy",
    blocked_tasks = 3,
  )
  assert_true(not(r.should_stop))
}

// ---------------------------------------------------------------------------
// loop_tick — exceeded 终止
// ---------------------------------------------------------------------------

///|
test "loop_tick: test_count 涨 10%+ → exceeded" {
  let lp = loop_create(
    "lp",
    ["advance"],
    "t0",
    baseline_test_count = 100,
    baseline_open_bug_count = 5,
  )
  let r = loop_tick(lp, "t1", current_test_count = 120, current_open_bug_count = 5)
  assert_true(r.should_stop)
  assert_true(r.stop_reason.contains("exceeded"))
  assert_true(r.loop_after.exceeded)
}

///|
test "loop_tick: open_bug 降 50%+ → exceeded" {
  let lp = loop_create(
    "lp",
    ["advance"],
    "t0",
    baseline_test_count = 100,
    baseline_open_bug_count = 10,
  )
  let r = loop_tick(lp, "t1", current_test_count = 100, current_open_bug_count = 4)
  assert_true(r.should_stop)
  assert_true(r.stop_reason.contains("exceeded"))
}

// ---------------------------------------------------------------------------
// loop_to_json 基本字段
// ---------------------------------------------------------------------------

///|
test "loop_to_json: 基本字段完整" {
  let lp = loop_create("j", ["advance", "bugfind"], "t0")
  let j = loop_to_json(lp)
  match j.value("name") {
    Some(n) => assert_true((match n { Json::String(_) => true; _ => false }))
    None => assert_true(false)
  }
  match j.value("steps") {
    Some(s) => assert_true((match s { Json::Array(_) => true; _ => false }))
    None => assert_true(false)
  }
  match j.value("status") {
    Some(s) => {
      match s {
        Json::String("active") => assert_true(true)
        _ => assert_true(false)
      }
    }
    None => assert_true(false)
  }
}

// ---------------------------------------------------------------------------
// loop_status_str
// ---------------------------------------------------------------------------

///|
test "loop_status_str: 5 种状态" {
  assert_eq(loop_status_str(Active), "active")
  assert_eq(loop_status_str(MaxRoundsHit), "max_rounds_hit")
  assert_eq(loop_status_str(GoalReached), "goal_reached")
  assert_eq(loop_status_str(Exceeded), "exceeded")
  assert_eq(loop_status_str(NoSteps), "no_steps")
}
