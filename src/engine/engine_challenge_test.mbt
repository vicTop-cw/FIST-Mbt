/// engine_challenge_test.mbt —— Challenger 进阶变体测试
/// 覆盖：对已完成任务发起进阶变体→新根任务带 [challenge]/from 溯源/重要度升档；
/// 对未完成任务拒绝；feeling 策略回退；扩规模因子写入描述。
/// R29 追加：可选 critic 防漂移门禁（空库放行 / 当前策略漂移→自动降档 / 全部漂移→拒发）。

///|
fn ch_engine() -> @engine.FistEngine {
  @engine.FistEngine::new()
}

///|
fn ch_publish(e : @engine.FistEngine, desc : String) -> String {
  match
    e.publish(
      project_dir="/proj/challenge",
      description=desc,
      created_by="human_steward",
      now="2026-09-05T10:00:00Z",
    ) {
    Ok(id) => id
    Err(m) => abort("publish failed: \{m}")
  }
}

///|
fn ch_complete(e : @engine.FistEngine, id : String) -> Unit {
  ignore(e.claim(task_id=id, assignee="exec_1", now="2026-09-05T10:01:00Z"))
  ignore(e.execute(task_id=id, deliverable="done", now="2026-09-05T10:02:00Z"))
  ignore(e.submit(task_id=id, now="2026-09-05T10:03:00Z"))
  match e.verify(task_id=id, verifier="ver_1", now="2026-09-05T10:04:00Z") {
    Ok(_) => ()
    Err(m) => abort("verify failed: \{m}")
  }
}

///|
/// 造一个档案库并把 note 入档（用于 critic 门禁测试的"既有资产/漂移源"）。
fn ch_arc_with(note : String) -> @evolve.Archive {
  let arc = @evolve.Archive::new("mem-challenge-critic")
  let art = @evolve.Artifact::create(
    id="seed-" + note.hash().to_string(),
    parent_id=None,
    goal="[lesson] 测试",
    note~,
    code="",
    score=0.9,
    parts=Map([]),
    created_at="2026-09-05T09:00:00Z",
  )
  @evolve.Archive::add(arc, art)
  arc
}

///|
test "task_challenge 对已完成任务发布进阶变体：新根带 [challenge]/溯源/重要度升档" {
  let e = ch_engine()
  let id = ch_publish(e, "实现一个基础计算器")
  ch_complete(e, id)
  match e.challenge(task_id=id, by="auto", now="2026-09-05T10:05:00Z") {
    Err(m) => abort("challenge on completed should succeed: \{m}")
    Ok(j) => {
      // new_id 应为顺延根任务（非源任务 T0 → T0r2）
      let new_id = match j.value("new_id") {
        Some(String(s)) => s
        _ => abort("missing new_id: " + j.stringify())
      }
      assert_eq(new_id.has_prefix("T0r2"), true)
      match e.get_task(new_id) {
        Some(t) => {
          assert_eq(t.description.contains("[challenge]"), true)
          assert_eq(t.description.contains("from T0"), true)
          // 重要度升档：默认 publish 为"中" → 挑战后"高"
          assert_eq(t.importance, "高")
          assert_eq(t.get_depth(), 3)
        }
        None => abort("new challenge task missing")
      }
    }
  }
}

///|
test "task_challenge 拒绝未完成任务，且策略回退到底  scale" {
  let e = ch_engine()
  let id = ch_publish(e, "待领取的任务")
  // 未完成：拒绝
  match e.challenge(task_id=id, by="auto", now="2026-09-05T10:01:00Z") {
    Err(m) => assert_eq(m.contains("已完成/已归档"), true)
    Ok(_) => abort("challenge on pending should reject")
  }
  // 完成后再发，非法策略回退 scale 且 factor 写入描述
  ch_complete(e, id)
  match
    e.challenge(
      task_id=id,
      by="auto",
      factor=3,
      strat="bogus-strategy",
      now="2026-09-05T10:05:00Z",
    ) {
    Err(m) => abort("challenge with bogus strat should succeed: \{m}")
    Ok(j) => {
      match j.value("strat") {
        Some(String(s)) => assert_eq(s, "scale")
        _ => abort("strat should fallback to scale")
      }
      let new_id = match j.value("new_id") {
        Some(String(s)) => s
        _ => abort("missing new_id")
      }
      match e.get_task(new_id) {
        Some(t) => assert_eq(t.description.contains("3 倍"), true)
        None => abort("new challenge task missing")
      }
    }
  }
}

///|
test "task_challenge critic 门禁：空库放行（critic_status=admitted 且带评审）" {
  let e = ch_engine()
  let id = ch_publish(e, "实现一个基础计算器")
  ch_complete(e, id)
  // 空档案库：无既有资产可漂移 → 直接放行，status=admitted，critic 附上评审
  let arc = @evolve.Archive::new("mem-challenge-critic-empty")
  match
    e.challenge(
      task_id=id,
      by="auto",
      now="2026-09-05T10:05:00Z",
      critic=Some(arc),
    ) {
    Err(m) => abort("空库门禁应放行: \{m}")
    Ok(j) =>
      match j.value("critic_status") {
        Some(String(s)) => assert_eq(s, "admitted")
        _ => abort("critic_status 应为 admitted: " + j.stringify())
      }
  }
}

///|
test "task_challenge critic 门禁：当前策略漂移 → 自动降档到非漂移策略" {
  let e = ch_engine()
  let id = ch_publish(e, "实现一个基础计算器")
  ch_complete(e, id)
  // 档案库只"抄袭"了 scale 帧；scale 会被判课程漂移 → 自动降档 generalize（首个非漂移）
  let src_desc = "实现一个基础计算器"
  let scale_frame = "把规模/负载/覆盖度提升到 2 倍并保持语义正确与可验证（扩规模上难度）"
  let arc = ch_arc_with(ch_desc(id, src_desc, scale_frame))
  match
    e.challenge(
      task_id=id,
      by="auto",
      strat="scale",
      factor=2,
      now="2026-09-05T10:05:00Z",
      critic=Some(arc),
    ) {
    Err(m) => abort("漂移应自动降档而非报错: \{m}")
    Ok(j) => {
      match j.value("critic_status") {
        Some(String(s)) => assert_eq(s, "degraded")
        _ => abort("critic_status 应为 degraded: " + j.stringify())
      }
      match j.value("strat") {
        Some(String(s)) => assert_eq(s, "generalize")
        _ => abort("漂移后应降档到 generalize: " + j.stringify())
      }
    }
  }
}

///|
test "task_challenge critic 门禁：全部策略皆漂移 → 拒发且不出新根任务" {
  let e = ch_engine()
  let id = ch_publish(e, "实现一个基础计算器")
  ch_complete(e, id)
  let src_desc = "实现一个基础计算器"
  let frames = [
    "把规模/负载/覆盖度提升到 2 倍并保持语义正确与可验证（扩规模上难度）",
    "摆脱对具体场景的依赖，抽象为通用能力并覆盖边界与异常（泛化上难度）",
    "去掉自带提示/约束，从空白规格重新推导且不降低正确性与完备性（去提示上难度）",
    "增加硬约束（性能/并发/兼容），并在新约束成立的同时保证原有行为零回归（加约束上难度）",
  ]
  // 档案库把四个策略帧的完整挑战题全"抄袭"了 → 每一帧变体都与既有资产重合=1.0（同质坍缩）
  let arc = @evolve.Archive::new("mem-challenge-critic-all")
  for fr in frames {
    let art = @evolve.Artifact::create(
      id="seed-all-" + fr.hash().to_string(),
      parent_id=None,
      goal="[lesson] 测试",
      note=ch_desc(id, src_desc, fr),
      code="",
      score=0.9,
      parts=Map([]),
      created_at="2026-09-05T09:00:00Z",
    )
    @evolve.Archive::add(arc, art)
  }
  // 全部策略皆漂移 → 拒发，且不产生任何新根任务
  match
    e.challenge(
      task_id=id,
      by="auto",
      strat="scale",
      now="2026-09-05T10:05:00Z",
      critic=Some(arc),
    ) {
    Err(m) => assert_eq(m.contains("防漂移门禁拒绝"), true)
    Ok(_) => abort("全部策略漂移应拒发")
  }
  // 未产生新任务（依旧 1 个源任务）
  assert_eq(e.list_all().length(), 1)
}
