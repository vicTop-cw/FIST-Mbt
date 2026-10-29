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
  desc~ : String = "Omega 强验证根任务",
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
  let db = ".fist-mbt/tmp/omega_strong_persist.db"
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
  let db = ".fist-mbt/tmp/omega_auto_lesson.db"
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
    .fold(init="", fn(a, x) { a + x })
  assert_true(join.contains("[lesson] omega.spec_rejected"))
  assert_true(join.contains("验收标准不量化"))
  assert_true(join.contains("[lesson] omega.result_rejected"))
  assert_true(join.contains("成果未达标"))
  assert_true(join.contains("[lesson] omega.escalated"))
}

///|
/// 预执行审计门禁：空交付物被拒（BUG-29 done_no_artifact 防线）。
test "omega_audit_gate_empty_deliverable_rejected" {
  let e = os_engine()
  let id = os_publish(e)
  ignore(e.claim(task_id=id, assignee="exec_1", now="2026-09-17T10:00:00Z"))
  let r = e.execute(task_id=id, deliverable="", now="2026-09-17T10:01:00Z")
  match r {
    Err(m) => assert_true(m.contains("预执行审计门禁"))
    Ok(_) => abort("空交付物不应通过审计门禁")
  }
  // 纯空白同样拒绝
  let r2 = e.execute(
    task_id=id,
    deliverable="   \n\t  ",
    now="2026-09-17T10:02:00Z",
  )
  match r2 {
    Err(m) => assert_true(m.contains("预执行审计门禁"))
    Ok(_) => abort("纯空白交付物不应通过审计门禁")
  }
}

///|
/// 预执行审计门禁：正常交付物放行。
test "omega_audit_gate_non_empty_passes" {
  let e = os_engine()
  let id = os_publish(e)
  ignore(e.claim(task_id=id, assignee="exec_1", now="2026-09-17T11:00:00Z"))
  match
    e.execute(
      task_id=id,
      deliverable="改了 src/foo.mbt：新增 bar 函数，附 3 条测试",
      now="2026-09-17T11:01:00Z",
    ) {
    Ok(_) => ()
    Err(m) => abort("正常交付物不应被拒: \{m}")
  }
}

///|
/// BUG-389 单元锁 ①：旧描述含 [omega:required]、新描述不含 → 结果仍含该标记。
/// （若丢失，omega_spec_create 会把「标记被 supervisor 覆盖」误报成「用户没开 Omega」。）
test "preserve_plan_markers_keeps_omega_mark" {
  let old = "实现缓存层 [omega:required]  [难度梯度 3]"
  let new = "实现缓存层"
  let got = @engine.preserve_plan_markers(old, new)
  assert_true(got.contains("[omega:required]"))
  // 用户写的新描述本体必须原样保留
  assert_true(got.contains("实现缓存层"))
}

///|
/// BUG-389 单元锁 ②：旧描述含 [边界四问 标记 → 结果仍含（含前导空格整段补回）。
test "preserve_plan_markers_keeps_boundary_mark" {
  let old = "校验空输入 [边界四问:空输入/极值/非法输入/资源极限——须有用例或声明不适用]"
  let new = "校验空输入"
  let got = @engine.preserve_plan_markers(old, new)
  // 按清单补回的是标记前缀 " [边界四问"（与 strip_plan_annotations 同一份清单）
  assert_true(got.contains("[边界四问"))
}

///|
/// BUG-389 单元锁 ③：旧描述不含任何标记、新描述也不含 → 原样返回（不追加空格、不改文本）。
test "preserve_plan_markers_noop_when_no_markers" {
  let old = "普通根任务"
  let new = "新描述"
  let got = @engine.preserve_plan_markers(old, new)
  assert_eq(got, new)
}

///|
/// BUG-389 单元锁 ④：新描述已含 [omega:required] → 不重复追加（幂等，防标记累积）。
test "preserve_plan_markers_no_duplicate_when_present" {
  let old = "任务 [omega:required]"
  let new = "任务 [omega:required]"
  let got = @engine.preserve_plan_markers(old, new)
  // 只出现一次
  let parts = got.split("[omega:required]")
  assert_eq(parts.count(), 2)
}

///|
/// BUG-389 端到端锁：supervisor_task_upsert 更新描述时不丢 decomposer 结构标记，
/// omega 门禁仍能读到 [omega:required]，omega_spec_create 不再误报「未开启 Omega 强验证」。
test "preserve_plan_markers_survives_supervisor_upsert" {
  let e = os_engine()
  let id = os_publish(e, desc="超级管家更新根任务")
  os_split(e, id, true)
  let cid = os_first_child(e, id)
  // 前置：子任务确实带着强验证标记
  match e.get_task(cid) {
    Some(t) => assert_true(t.get_description().contains("[omega:required]"))
    None => abort("child missing: \{cid}")
  }
  // 超级管家更新描述：只写业务文本，不带任何结构标记
  let item = Json::object({
    "task_id": Json::string(cid),
    "description": Json::string("缓存层重写，含 LRU 与 TTL"),
    "priority": Json::string(""),
    "depends_on": Json::array([]),
  })
  let r = e.supervisor_task_upsert(
    project_dir="/proj/omega",
    by="human_steward",
    [item],
    now="2026-09-17T10:30:00Z",
  )
  let rs = r.stringify()
  assert_true(rs.contains("\"action\":\"updated\""))
  // 标记必须仍在 description 里（BUG-389 修复点）
  match e.get_task(cid) {
    Some(t) => assert_true(t.get_description().contains("[omega:required]"))
    None => abort("child missing after upsert: \{cid}")
  }
  // 门禁不再误报：语料创建通道放行
  match
    e.omega_spec_create(
      task_id=cid,
      author="spec_author",
      content="缓存层验收标准",
      now="2026-09-17T10:31:00Z",
    ) {
    Ok(_) => ()
    Err(m) => abort("标记保留后语料创建不应被门禁拦下: \{m}")
  }
}

///|
/// 预执行审计门禁 Round 8 扩展：占位符交付物（fake-GREEN 形状）被拒。
/// 「done」/「完成」/「ok」/「yes」/「通过」这类词整串等于时，账本记完成但无产物可核，
/// 正是 BUG-29 done_no_artifact 病灶形状；大小写/标点容忍。
test "omega_audit_gate_placeholder_rejected" {
  let e = os_engine()
  let id = os_publish(e)
  ignore(e.claim(task_id=id, assignee="exec_1", now="2026-09-17T12:00:00Z"))
  let placeholders : Array[String] = [
    "done", "Done", "DONE", "完成", "ok", "OK", "yes", "Yes", "通过", "done.",
    "ok.", "完成。",
  ]
  for ph in placeholders {
    let r = e.execute(task_id=id, deliverable=ph, now="2026-09-17T12:01:00Z")
    match r {
      Err(m) => assert_true(m.contains("占位符"))
      Ok(_) => abort("占位符交付物不应通过审计门禁: [" + ph + "]")
    }
  }
}

///|
/// 预执行审计门禁 Round 8 扩展：含具体信息但带占位符字样的交付物仍放行（不过度拦截）。
test "omega_audit_gate_placeholder_in_sentence_passes" {
  let e = os_engine()
  let id = os_publish(e)
  ignore(e.claim(task_id=id, assignee="exec_1", now="2026-09-17T13:00:00Z"))
  match
    e.execute(
      task_id=id,
      deliverable="改完 src/x.mbt，测试通过，附 3 条",
      now="2026-09-17T13:01:00Z",
    ) {
    Ok(_) => ()
    Err(m) => abort("含具体信息的交付物不应被拒: \{m}")
  }
}

///|
/// 预执行审计门禁 Round 10 修复：注释承诺「空白/标点容忍」但旧实现只 to_lower，
/// `"Done ."` / `"完成！"` 这类「占位符 + 杂散空白/标点」能绕过。现在剔除全部非字母数字后比对。
test "omega_audit_gate_placeholder_punctuation_tolerant" {
  let e = os_engine()
  let id = os_publish(e)
  ignore(e.claim(task_id=id, assignee="exec_1", now="2026-09-17T14:00:00Z"))
  let sneaky : Array[String] = [
    " done ", "Done.", "完成！", "完成。", "ok!!", "O.K.", "通过,", "yes!",
    "finished.",
  ]
  for ph in sneaky {
    let r = e.execute(task_id=id, deliverable=ph, now="2026-09-17T14:01:00Z")
    match r {
      Err(m) =>
        if !m.contains("占位符") {
          abort("规整后仍是占位符却放行: [" + ph + "] → " + m)
        }
      Ok(_) =>
        abort(
          "杂散空白/标点的占位符不应通过审计门禁: [" +
          ph +
          "]",
        )
    }
  }
}

///|
/// 预执行审计门禁 Round 10 反向对照：带中文标点的真实交付物仍放行（不过度拦截）。
test "omega_audit_gate_placeholder_real_sentence_with_punctuation_passes" {
  let e = os_engine()
  let id = os_publish(e)
  ignore(e.claim(task_id=id, assignee="exec_1", now="2026-09-17T15:00:00Z"))
  match
    e.execute(
      task_id=id,
      deliverable="修复 src/server/server.mbt：task_plan_deep 的 DAG 依赖传递；附 5 条测试通过。",
      now="2026-09-17T15:01:00Z",
    ) {
    Ok(_) => ()
    Err(m) => abort("真实交付物不应被误伤: \{m}")
  }
}
