// Omega 强验证（可选开关）测试。
// 覆盖：
//   1) 开关默认关闭时行为与现状完全一致（子任务无标记、语料环节不可用、执行无需语料）
//   2) 开关开启后：子任务带 [omega:required] 标记，执行前必须语料审核通过，可打回重做
//   3) 成果复验门禁、打回重做与打回超限升级（防死循环）
//   4) 验证者不得审核自己创建的语料
//   5) 语料真正落库 specs 表（同一 SQLite 库换引擎实例仍可读）

///|
fn os_engine() -> @engine.FistEngine {
  @engine.FistEngine::new()
}

///|
fn os_publish(
  e : @engine.FistEngine,
  desc? : String = "Omega 强验证根任务",
) -> String {
  match
    e.publish(
      project_dir="/proj/omega",
      description=desc,
      created_by="human_steward",
      now="2026-09-17T09:00:00Z",
    ) {
    Ok(id) => id
    Err(m) => abort("publish failed: \{m}")
  }
}

///|
fn os_split(e : @engine.FistEngine, id : String, omega : Bool) -> Unit {
  ignore(e.claim(task_id=id, assignee="leader_a", now="2026-09-17T09:01:00Z"))
  match
    e.plan_deep(
      task_id=id,
      split_n=2,
      by="leader_a",
      now="2026-09-17T09:02:00Z",
      omega_strong_verify=omega,
    ) {
    Ok(_) => ()
    Err(m) => abort("plan_deep failed: \{m}")
  }
}

///|
fn os_first_child(e : @engine.FistEngine, id : String) -> String {
  let cs = e.children_of(id)
  if cs.length() == 0 {
    abort("no child task")
  }
  cs[0].get_id()
}

///|
fn os_marked(e : @engine.FistEngine, id : String) -> Bool {
  e
  .children_of(id)
  .any(fn(t) { t.get_description().contains("[omega:required]") })
}

///|
test "omega 开关默认关闭：子任务无标记、行为与现状一致" {
  let e = os_engine()
  let id = os_publish(e, desc="Omega 默认关闭根任务")
  os_split(e, id, false)
  let cid = os_first_child(e, id)
  assert_false(os_marked(e, id))
  match e.omega_status(id) {
    Ok(j) => assert_true(j.stringify().contains("\"omega_enabled\":false"))
    Err(m) => abort("omega_status failed: \{m}")
  }
  // 未开启强验证：语料环节不可用（不产生任何副作用）
  match
    e.omega_spec_create(
      task_id=cid,
      author="spec_author",
      content="不该被创建的语料",
      now="2026-09-17T09:03:00Z",
    ) {
    Ok(_) => abort("未开启强验证的任务不应允许创建语料")
    Err(m) => assert_true(m.contains("未开启 Omega 强验证"))
  }
  // 未开启强验证：执行无需任何语料，与既有流程一致
  ignore(e.claim(task_id=cid, assignee="exec_1", now="2026-09-17T09:04:00Z"))
  match
    e.execute(task_id=cid, deliverable="成果 v1", now="2026-09-17T09:05:00Z") {
    Ok(t) => assert_true(t.get_status().is_executing())
    Err(m) => abort("默认关闭时执行不应被拦截: \{m}")
  }
}

///|
test "omega 开启后：执行前必须语料审核通过，打回可重做" {
  let e = os_engine()
  let id = os_publish(e, desc="Omega 开启根任务")
  os_split(e, id, true)
  let cid = os_first_child(e, id)
  // 子任务已带强验证标记
  match e.get_task(cid) {
    Some(t) => assert_true(t.get_description().contains("[omega:required]"))
    None => abort("child missing: \{cid}")
  }
  assert_true(os_marked(e, id))
  ignore(e.claim(task_id=cid, assignee="exec_1", now="2026-09-17T09:03:00Z"))
  // ① 尚无语料 -> 禁止进入执行
  match
    e.execute(task_id=cid, deliverable="成果 v1", now="2026-09-17T09:04:00Z") {
    Ok(_) => abort("无语料时不应放行执行")
    Err(m) => assert_true(m.contains("尚未创建语料"))
  }
  // ② 语料创建者创建语料
  match
    e.omega_spec_create(
      task_id=cid,
      author="spec_author",
      content="验收标准 v1",
      now="2026-09-17T09:05:00Z",
    ) {
    Ok(j) => {
      let s = j.stringify()
      assert_true(s.contains("\"status\":\"pending\""))
      assert_true(s.contains("\"next_action\":\"omega_spec_review\""))
    }
    Err(m) => abort("omega_spec_create failed: \{m}")
  }
  // ③ 未审核通过前仍禁止执行
  match
    e.execute(task_id=cid, deliverable="成果 v1", now="2026-09-17T09:06:00Z") {
    Ok(_) => abort("语料未通过时不应放行执行")
    Err(m) => assert_true(m.contains("未通过审核"))
  }
  // ④ 验证者打回重做
  match
    e.omega_spec_review(
      task_id=cid,
      reviewer="verifier",
      verdict="reject",
      reason="验收标准不明确",
      now="2026-09-17T09:07:00Z",
    ) {
    Ok(j) => {
      let s = j.stringify()
      assert_true(s.contains("\"verdict\":\"rejected\""))
      assert_true(s.contains("\"next_action\":\"omega_spec_create\""))
    }
    Err(m) => abort("omega_spec_review failed: \{m}")
  }
  // ⑤ 语料创建者重做 + 验证者通过 -> 放行执行
  match
    e.omega_spec_create(
      task_id=cid,
      author="spec_author",
      content="验收标准 v2（可量化）",
      now="2026-09-17T09:08:00Z",
    ) {
    Ok(_) => ()
    Err(m) => abort("omega_spec_create v2 failed: \{m}")
  }
  match
    e.omega_spec_review(
      task_id=cid,
      reviewer="verifier",
      verdict="approve",
      now="2026-09-17T09:09:00Z",
    ) {
    Ok(j) => assert_true(j.stringify().contains("\"next_action\":\"execute\""))
    Err(m) => abort("omega_spec_review approve failed: \{m}")
  }
  match
    e.execute(task_id=cid, deliverable="成果 v1", now="2026-09-17T09:10:00Z") {
    Ok(t) => assert_true(t.get_status().is_executing())
    Err(m) => abort("语料通过后执行应放行: \{m}")
  }
  // ⑥ 状态查询可见轮次与打回次数
  match e.omega_status(cid) {
    Ok(j) => {
      let s = j.stringify()
      assert_true(s.contains("\"spec_rounds\":2"))
      assert_true(s.contains("\"spec_rejected\":1"))
      assert_true(s.contains("\"spec_status\":\"approved\""))
    }
    Err(m) => abort("omega_status failed: \{m}")
  }
}

///|
test "omega 成果复验门禁、打回重做与超限升级（防死循环）" {
  let e = os_engine()
  let id = os_publish(e, desc="Omega 复验根任务")
  os_split(e, id, true)
  let cid = os_first_child(e, id)
  ignore(e.claim(task_id=cid, assignee="exec_1", now="2026-09-17T09:03:00Z"))
  ignore(
    e.omega_spec_create(
      task_id=cid,
      author="spec_author",
      content="验收标准",
      now="2026-09-17T09:04:00Z",
    ),
  )
  ignore(
    e.omega_spec_review(
      task_id=cid,
      reviewer="verifier",
      verdict="approve",
      now="2026-09-17T09:05:00Z",
    ),
  )
  ignore(
    e.execute(task_id=cid, deliverable="成果 v1", now="2026-09-17T09:06:00Z"),
  )
  ignore(e.submit(task_id=cid, now="2026-09-17T09:07:00Z"))
  // ① 未做成果复验 -> 禁止验收
  match
    e.verify(task_id=cid, verifier="human_steward", now="2026-09-17T09:08:00Z") {
    Ok(_) => abort("未复验时不应放行验收")
    Err(m) => assert_true(m.contains("尚未做成果复验"))
  }
  // ② 复验不达标打回（max_rounds=1），任务退回执行
  match
    e.omega_result_verify(
      task_id=cid,
      reviewer="verifier",
      verdict="fail",
      reason="成果未达标",
      now="2026-09-17T09:09:00Z",
      max_rounds=1,
    ) {
    Ok(j) => {
      let s = j.stringify()
      assert_true(s.contains("\"verdict\":\"rejected\""))
      assert_true(s.contains("已打回"))
      assert_true(s.contains("\"escalated\":false"))
    }
    Err(m) => abort("omega_result_verify failed: \{m}")
  }
  // ③ 再次复验仍不达标 -> 触发打回上限，升级人工，任务暂停
  match
    e.omega_result_verify(
      task_id=cid,
      reviewer="verifier",
      verdict="fail",
      reason="重做后仍不达标",
      now="2026-09-17T09:10:00Z",
      max_rounds=1,
    ) {
    Ok(j) => {
      let s = j.stringify()
      assert_true(s.contains("\"escalated\":true"))
      assert_true(s.contains("\"needs_human_review\":true"))
      assert_true(s.contains("\"task_paused\":true"))
      assert_true(s.contains("\"next_action\":\"human_review\""))
    }
    Err(m) => abort("omega_result_verify escalate failed: \{m}")
  }
  // ④ 升级后仍不可验收（不会死循环自行放行）
  match
    e.verify(task_id=cid, verifier="human_steward", now="2026-09-17T09:11:00Z") {
    Ok(_) => abort("升级人工后不应自动放行验收")
    Err(_) => ()
  }
  // ⑤ 状态查询可见升级记录
  match e.omega_status(cid) {
    Ok(j) => {
      let s = j.stringify()
      assert_true(s.contains("\"escalated\":true"))
      assert_true(s.contains("\"result_rejected\":1"))
    }
    Err(m) => abort("omega_status failed: \{m}")
  }
}

///|
test "omega 验证者不得审核自己创建的语料" {
  let e = os_engine()
  let id = os_publish(e, desc="Omega 自审拦截根任务")
  os_split(e, id, true)
  let cid = os_first_child(e, id)
  ignore(
    e.omega_spec_create(
      task_id=cid,
      author="human_steward",
      content="自建语料",
      now="2026-09-17T09:03:00Z",
    ),
  )
  match
    e.omega_spec_review(
      task_id=cid,
      reviewer="human_steward",
      verdict="approve",
      now="2026-09-17T09:04:00Z",
    ) {
    Ok(_) => abort("验证者不应能审核自己创建的语料")
    Err(m) => assert_true(m.contains("不可审核自己"))
  }
}

///|
test "omega 语料真正落库：同一 SQLite 库换引擎实例仍可读" {
  let db = "omega_strong_persist.db"
  // 幂等：先经 SqliteStore 公共 API 清空上次残留任务，保证测试可重复执行
  match @store.SqliteStore::open(db) {
    Some(s) => ignore(s.clear())
    None => abort("sqlite open failed: \{db}")
  }
  let e0 = match @engine.FistEngine::open_sqlite(db) {
    Some(x) => x
    None => abort("open_sqlite failed: \{db}")
  }
  let id = os_publish(e0, desc="Omega 持久化根任务")
  os_split(e0, id, true)
  let cid = os_first_child(e0, id)
  match
    e0.omega_spec_create(
      task_id=cid,
      author="spec_author",
      content="持久化语料",
      now="2026-09-17T10:00:00Z",
    ) {
    Ok(_) => ()
    Err(m) => abort("omega_spec_create failed: \{m}")
  }
  let s0 = match e0.omega_status(cid) {
    Ok(j) => j.stringify()
    Err(m) => abort("omega_status before reopen failed: \{m}")
  }
  // 换一个引擎实例重新打开同一 SQLite 库：语料仍在（证明写入了 specs 表）
  let e1 = match @engine.FistEngine::open_sqlite(db) {
    Some(x) => x
    None => abort("reopen_sqlite failed: \{db}")
  }
  match e1.omega_status(cid) {
    Ok(j) => {
      let s = j.stringify()
      // 新实例经 specs 表读回了本轮的语料记录，且与旧实例看到的内容一致
      assert_true(s.contains("\"spec_type\":\"spec\""))
      assert_true(s.contains("\"spec_status\":\"pending\""))
      assert_true(s.contains("\"spec_rounds\":"))
      // 新实例与旧实例看到完全相同的语料记录（同一 SQLite 库，跨实例可读）
      assert_eq(s, s0)
    }
    Err(m) => abort("omega_status after reopen failed: \{m}")
  }
}

///|
test "omega 打回自动落 [lesson] 教训（spec 打回 + 复验打回 + 超限升级），同一库可读" {
  let db = "omega_auto_lesson.db"
  // 幂等：先经 SqliteStore 公共 API 清空上次残留任务，保证测试可重复执行
  match @store.SqliteStore::open(db) {
    Some(s) => ignore(s.clear())
    None => abort("sqlite open failed: \{db}")
  }
  let e = match @engine.FistEngine::open_sqlite(db) {
    Some(x) => x
    None => abort("open_sqlite failed: \{db}")
  }
  let id = os_publish(e, desc="Omega 自动回流根任务")
  os_split(e, id, true)
  let cid = os_first_child(e, id)
  ignore(e.claim(task_id=cid, assignee="exec_1", now="2026-09-17T09:03:00Z"))
  // ① 语料被打回（带原因）：自动落 [lesson] omega.spec_rejected
  ignore(
    e.omega_spec_create(
      task_id=cid,
      author="spec_author",
      content="验收标准 v1",
      now="2026-09-17T09:04:00Z",
    ),
  )
  match
    e.omega_spec_review(
      task_id=cid,
      reviewer="verifier",
      verdict="reject",
      reason="验收标准不量化",
      now="2026-09-17T09:05:00Z",
    ) {
    Ok(j) => assert_true(j.stringify().contains("\"learned_lesson\":true"))
    Err(m) => abort("spec_review reject failed: \{m}")
  }
  // ② 语料重做 + 审核通过 + 执行 + 提交，进入成果复验
  ignore(
    e.omega_spec_create(
      task_id=cid,
      author="spec_author",
      content="验收标准 v2（可量化）",
      now="2026-09-17T09:06:00Z",
    ),
  )
  match
    e.omega_spec_review(
      task_id=cid,
      reviewer="verifier",
      verdict="approve",
      now="2026-09-17T09:07:00Z",
    ) {
    Ok(_) => ()
    Err(m) => abort("spec approve failed: \{m}")
  }
  ignore(
    e.execute(task_id=cid, deliverable="成果 v1", now="2026-09-17T09:08:00Z"),
  )
  ignore(e.submit(task_id=cid, now="2026-09-17T09:09:00Z"))
  // ③ 成果复验打回（max_rounds=1）：落 [lesson] omega.result_rejected
  match
    e.omega_result_verify(
      task_id=cid,
      reviewer="verifier",
      verdict="fail",
      reason="成果未达标",
      now="2026-09-17T09:10:00Z",
      max_rounds=1,
    ) {
    Ok(j) => assert_true(j.stringify().contains("\"learned_lesson\":true"))
    Err(m) => abort("result_verify reject failed: \{m}")
  }
  // ④ 复验仍不达标 -> 超限升级人工：落 [lesson] omega.escalated
  match
    e.omega_result_verify(
      task_id=cid,
      reviewer="verifier",
      verdict="fail",
      reason="重做后仍不达标",
      now="2026-09-17T09:11:00Z",
      max_rounds=1,
    ) {
    Ok(j) => assert_true(j.stringify().contains("\"learned_lesson\":true"))
    Err(m) => abort("result_verify escalate failed: \{m}")
  }
  // ⑤ 换引擎实例读取同一库：三类教训均已沉淀且可检索（原因被记进 note）
  let s = match @store.SqliteStore::open(db) {
    Some(x) => x
    None => abort("reopen sqlite failed: \{db}")
  }
  let join = s
    .evolve_list()
    .map(fn(j) { j.stringify() })
    .fold_left(init="", fn(a, x) { a + x })
  assert_true(join.contains("[lesson] omega.spec_rejected"))
  assert_true(join.contains("验收标准不量化"))
  assert_true(join.contains("[lesson] omega.result_rejected"))
  assert_true(join.contains("成果未达标"))
  assert_true(join.contains("[lesson] omega.escalated"))
}
