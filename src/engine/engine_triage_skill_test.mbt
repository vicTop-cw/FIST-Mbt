/// engine_triage_skill_test.mbt —— task_triage 的 skill 路由增强（improvement-plan §5.2-4）黑盒测试
/// 覆盖：skill 命中度排序（排在能力匹配之后、优先级之前）、SKILL→MODE 建议、大小写不敏感、
///       零回归锁（skill="" 时排序/输出与不传 skill 完全一致）。测试只走公开 API（triage/skill=）。
/// 说明：triage 复用 engine.list_all()（当前生效命名空间的任务集），测试在默认命名空间发布根任务。

///|
fn tsk_engine() -> @engine.FistEngine {
  @engine.FistEngine::new()
}

///|
fn tsk_publish(e : @engine.FistEngine, desc : String) -> String {
  match
    e.publish(
      project_dir="/proj/tskill",
      description=desc,
      created_by="human_steward",
      now="2026-10-10T10:00:00Z",
    ) {
    Ok(id) => id
    Err(m) => abort("publish failed: \{m}")
  }
}

///|
/// 取 triage 返回的 tasks 数组（已按排行序）。
fn tsk_tasks(j : Json) -> Array[Json] {
  match j.value("tasks") {
    Some(Array(arr)) => arr
    _ => abort("tasks 缺失: " + j.stringify())
  }
}

///|
fn tsk_id(row : Json) -> String {
  match row.value("id") {
    Some(String(s)) => s
    _ => abort("id 缺失: " + row.stringify())
  }
}

///|
fn tsk_ids(j : Json) -> Array[String] {
  tsk_tasks(j).map(fn(r) { tsk_id(r) })
}

///|
fn tsk_first(j : Json) -> String {
  let arr = tsk_tasks(j)
  if arr.is_empty() {
    abort("tasks 为空")
  }
  tsk_id(arr[0])
}

///|
fn tsk_skill_hits(j : Json, id : String) -> Array[String] {
  for row in tsk_tasks(j) {
    if tsk_id(row) == id {
      return match row.value("skill_hits") {
        Some(Array(h)) =>
          h.map(fn(v) {
            match v {
              String(s) => s
              _ => abort("skill_hits 元素非字符串")
            }
          })
        _ => abort("skill_hits 缺失: " + row.stringify())
      }
    }
  }
  abort("未找到任务: " + id)
}

///|
fn tsk_sugg_mode(j : Json) -> String {
  match j.value("suggestion") {
    Some(Object(m)) =>
      match m.get("mode") {
        Some(String(s)) => s
        _ => abort("suggestion.mode 缺失")
      }
    _ => abort("suggestion 缺失: " + j.stringify())
  }
}

///|
test "skill 路由正路径：tdd 命中任务排头部，suggestion.mode==fix_and_merge" {
  let e = tsk_engine()
  let a = tsk_publish(e, "用 tdd 先写测试再实现调度器")
  let _b = tsk_publish(e, "脑暴 ideation 生成候选功能清单")
  let j = e.triage("", "exec_demo", "", skill="tdd")
  // tdd 命中的 a 应排头部（同 priority/importance/depth，靠 skill 命中度决胜）
  assert_eq(tsk_first(j), a)
  assert_true(tsk_skill_hits(j, a).contains("tdd"))
  // SKILL→MODE：tdd → fix_and_merge
  assert_eq(tsk_sugg_mode(j), "fix_and_merge")
  // skill 参数应回显
  match j.value("skill") {
    Some(String(s)) => assert_eq(s, "tdd")
    _ => abort("skill 应回显")
  }
}

///|
test "skill 空串零回归锁：排序与不传 skill 一致，skill_hits 全空，suggestion 无 mode" {
  let e = tsk_engine()
  let _a = tsk_publish(e, "用 tdd 先写测试再实现调度器")
  let _b = tsk_publish(e, "脑暴 ideation 生成候选功能清单")
  let j0 = e.triage("", "exec_demo", "") // 不传 skill（旧调用面）
  let j1 = e.triage("", "exec_demo", "", skill="") // 显式空串
  // 排序完全一致（零回归）
  assert_eq(tsk_ids(j0), tsk_ids(j1))
  // 所有任务 skill_hits 都为空数组
  for row in tsk_tasks(j0) {
    match row.value("skill_hits") {
      Some(Array(arr)) => assert_eq(arr.length(), 0)
      _ => abort("skill_hits 应存在且为数组")
    }
  }
  // suggestion.mode 键存在但为空串（无 skill 建议）
  assert_eq(tsk_sugg_mode(j0), "")
}

///|
test "skill 命中大小写不敏感：desc 含 TDD 而 skill=tdd 仍命中" {
  let e = tsk_engine()
  let a = tsk_publish(e, "遵循 TDD 红绿重构写核心模块")
  let _b = tsk_publish(e, "脑暴 ideation 收集点子")
  let j = e.triage("", "exec_demo", "", skill="tdd")
  assert_eq(tsk_first(j), a)
  assert_true(tsk_skill_hits(j, a).contains("tdd"))
}

///|
test "skill 路由不误报：描述无关时 grill-me 不命中、mode 为空；真命中时 mode==verify" {
  let e = tsk_engine()
  let a = tsk_publish(e, "梳理 API 文档清单")
  let j = e.triage("", "exec_demo", "", skill="grill-me")
  // 描述无关 → 不命中
  assert_eq(tsk_skill_hits(j, a).length(), 0)
  assert_eq(tsk_sugg_mode(j), "")
  // 对照：描述真含 grill-me → 命中且 mode==verify
  let b = tsk_publish(e, "让 grill-me 挑战我的实现方案")
  let j2 = e.triage("", "exec_demo", "", skill="grill-me")
  assert_eq(tsk_first(j2), b)
  assert_true(tsk_skill_hits(j2, b).contains("grill-me"))
  assert_eq(tsk_sugg_mode(j2), "verify")
}
