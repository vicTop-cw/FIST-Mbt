/// plan_revise_feedback_test.mbt —— R137：feedback 条目被静默丢弃时，工具不能回 basis="feedback"。
///
/// 病灶：`plan_revise` 对每条 feedback 只认 {task_id: 字符串, ok: 布尔}；缺键、类型不符
/// （如 `"ok": "false"`）一律 `_ => ()` 丢掉，可 `basis` 只看 `feedback.is_empty()`。
/// 于是「一条都没生效」的调用照样回 basis="feedback"，调用方以为失败判定被采纳，
/// 实际是按任务状态出的计划（与 BUG-31 静默忽略、R135 的 defects_unparsed 同族）。
/// 修复口径：条目分三类计数（applied / ignored / unmatched），ignored 或 unmatched 非零
/// 进 flags；只有至少一条真正作用到本子树时 basis 才是 "feedback"。

///|
fn prf_engine(
  specs : Array[(String, String, Array[String])],
) -> @engine.FistEngine {
  let e = @engine.FistEngine::new()
  for s in specs {
    let (id, parent, deps) = s
    let t = @core.Task::new(
      id~,
      project_dir="/proj/demo",
      description="plan revise feedback 任务 \{id}",
      parent_id=parent,
      created_at="2026-10-23T02:00:00Z",
      depends_on=deps,
    )
    ignore(e.store.create_task(t))
  }
  e
}

///|
fn prf_basis(j : Json) -> String {
  match j.value("basis") {
    Some(Json::String(s)) => s
    _ => abort("basis 缺失: " + j.stringify())
  }
}

///|
fn prf_fb_count(j : Json, key : String) -> Int32 {
  match j.value("feedback") {
    Some(Json::Object(m)) =>
      match m.get(key) {
        Some(Json::Number(n, ..)) => n.to_int()
        _ => abort("feedback." + key + " 缺失: " + j.stringify())
      }
    _ => abort("feedback 缺失: " + j.stringify())
  }
}

///|
fn prf_flags(j : Json) -> Array[String] {
  let out : Array[String] = []
  match j.value("flags") {
    Some(Json::Array(a)) =>
      for x in a {
        match x {
          Json::String(s) => out.push(s)
          _ => abort("flags 元素非字符串: " + j.stringify())
        }
      }
    _ => abort("flags 缺失: " + j.stringify())
  }
  out
}

///|
fn prf_has_flag(flags : Array[String], prefix : String) -> Bool {
  let mut hit = false
  for f in flags {
    if f.has_prefix(prefix) {
      hit = true
    }
  }
  hit
}

///|
test "prf_1 类型不符的 ok 被丢弃后 basis 不得冒称 feedback" {
  let e = prf_engine([("R4", "", []), ("X", "R4", []), ("Y", "R4", ["X"])])
  let fb : Array[Json] = [
    Json::object({ "task_id": Json::string("X"), "ok": Json::string("false") }),
  ]
  let j = e.plan_revise("R4", feedback=fb)
  // 一条都没生效 ⇒ 依据只能是真实状态，不能被冒称成 feedback
  assert_eq(prf_basis(j), "status")
  assert_eq(prf_fb_count(j, "total"), 1)
  assert_eq(prf_fb_count(j, "applied"), 0)
  assert_eq(prf_fb_count(j, "ignored"), 1)
  assert_eq(prf_fb_count(j, "unmatched"), 0)
  assert_eq(prf_has_flag(prf_flags(j), "feedback_unparsed:"), true)
}

///|
test "prf_2 子树外的 task_id 不生效，须报 unmatched 而不是当成反馈依据" {
  let e = prf_engine([("R5", "", []), ("X", "R5", [])])
  let fb : Array[Json] = [
    Json::object({
      "task_id": Json::string("GHOST"),
      "ok": Json::boolean(false),
    }),
  ]
  let j = e.plan_revise("R5", feedback=fb)
  assert_eq(prf_basis(j), "status")
  assert_eq(prf_fb_count(j, "applied"), 0)
  assert_eq(prf_fb_count(j, "unmatched"), 1)
  assert_eq(prf_fb_count(j, "ignored"), 0)
  assert_eq(prf_has_flag(prf_flags(j), "feedback_unmatched:"), true)
}

///|
test "prf_3 混写：有效条目照常生效，废条目计数暴露" {
  let e = prf_engine([("R6", "", []), ("X", "R6", []), ("Y", "R6", ["X"])])
  let fb : Array[Json] = [
    Json::object({ "task_id": Json::string("X"), "ok": Json::boolean(true) }),
    Json::object({ "task_id": Json::string("Y"), "ok": Json::string("true") }),
  ]
  let j = e.plan_revise("R6", feedback=fb)
  assert_eq(prf_basis(j), "feedback")
  assert_eq(prf_fb_count(j, "total"), 2)
  assert_eq(prf_fb_count(j, "applied"), 1)
  assert_eq(prf_fb_count(j, "ignored"), 1)
  assert_eq(prf_has_flag(prf_flags(j), "feedback_unparsed:"), true)
  // X 被显式 ok → keep；Y 依赖 X → ready
  let keep = match j.value("keep") {
    Some(Json::Array(a)) =>
      a.map(fn(x) {
        match x {
          Json::String(s) => s
          _ => ""
        }
      })
    _ => abort("keep 缺失")
  }
  assert_eq(keep.join(","), "X")
}

///|
test "prf_4 空 feedback 反向对照：basis=status 且不误报 flags" {
  let e = prf_engine([("R7", "", []), ("X", "R7", [])])
  let j = e.plan_revise("R7")
  assert_eq(prf_basis(j), "status")
  assert_eq(prf_fb_count(j, "total"), 0)
  assert_eq(prf_fb_count(j, "applied"), 0)
  assert_eq(prf_fb_count(j, "ignored"), 0)
  assert_eq(prf_fb_count(j, "unmatched"), 0)
  assert_eq(prf_flags(j).length(), 0)
}
