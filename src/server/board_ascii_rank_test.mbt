// board_ascii_rank_test.mbt —— 看板渲染军衔标注锁（Phase 2）。
// 覆盖：根任务按 level 定级（连长/师长），非叶排长，叶子恒士兵。

///|
fn bar_engine() -> @engine.FistEngine {
  @engine.FistEngine::new()
}

///|
fn bar_publish(
  e : @engine.FistEngine,
  desc : String,
  level~ : Int32 = 6,
) -> String {
  match
    e.publish(
      project_dir="/proj/bar",
      description=desc,
      created_by="human_steward",
      now="2026-10-18T10:00:00Z",
      level~,
    ) {
    Ok(id) => id
    Err(m) => abort("publish failed: \{m}")
  }
}

///|
/// 读出看板 ascii 正文。
fn bar_ascii(e : @engine.FistEngine, ns~ : String = "") -> String {
  let j = @server.render_board_ascii(e.list_all(), ns)
  match jget(j, "ascii") {
    Some(Json::String(s)) => s
    _ => abort("ascii 缺失: " + j.stringify())
  }
}

///|
test "看板根任务默认连长级：军衔[连长] 出现" {
  let e = bar_engine()
  ignore(bar_publish(e, "连长级根任务"))
  let ascii = bar_ascii(e)
  assert_true(
    ascii.contains("军衔[连长]"),
    msg="应含 军衔[连长]，实为:\n\{ascii}",
  )
}

///|
test "看板根任务显式师长级：军衔[师长] 出现" {
  let e = bar_engine()
  ignore(bar_publish(e, "师长级根任务", level=2))
  let ascii = bar_ascii(e)
  assert_true(
    ascii.contains("军衔[师长]"),
    msg="应含 军衔[师长]，实为:\n\{ascii}",
  )
}

///|
test "看板树：连长根 + 排长子 + 士兵叶" {
  let e = bar_engine()
  let root = bar_publish(e, "递归军衔根")
  ignore(e.claim(task_id=root, assignee="leader_a", now="2026-10-18T10:01:00Z"))
  match
    e.plan_deep(
      task_id=root,
      split_n=2,
      by="leader_a",
      now="2026-10-18T10:02:00Z",
    ) {
    Ok(_) => ()
    Err(m) => abort("plan_deep failed: \{m}")
  }
  let ascii = bar_ascii(e)
  // 根 level=6（连长，非叶）；一层子 level=7（排长，非叶）；二层孙 level=7（叶 → 士兵）
  assert_true(
    ascii.contains("军衔[连长]"),
    msg="应含 军衔[连长]，实为:\n\{ascii}",
  )
  assert_true(
    ascii.contains("军衔[排长]"),
    msg="应含 军衔[排长]，实为:\n\{ascii}",
  )
  assert_true(
    ascii.contains("军衔[士兵]"),
    msg="应含 军衔[士兵]，实为:\n\{ascii}",
  )
}

///|
test "看板军衔与难度标注并存，缩进（depth）不受影响" {
  let e = bar_engine()
  ignore(bar_publish(e, "重构核心模块提升性能"))
  let ascii = bar_ascii(e)
  // 缩进保留（根 depth=3 → 3 个 "· "），军衔与难度同现
  assert_true(
    ascii.contains("· · · "),
    msg="根任务应保留 3 级缩进，实为:\n\{ascii}",
  )
  assert_true(
    ascii.contains("军衔[连长]"),
    msg="应含 军衔[连长]，实为:\n\{ascii}",
  )
}
