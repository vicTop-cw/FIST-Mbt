/// engine_challenge_test.mbt —— Challenger 进阶变体测试
/// 覆盖：对已完成任务发起进阶变体→新根任务带 [challenge]/from 溯源/重要度升档；
/// 对未完成任务拒绝；feeling 策略回退；扩规模因子写入描述。

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
