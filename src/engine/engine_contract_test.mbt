/// engine_contract_test.mbt —— 迁移契约检查（R109 · Design by Contract 蒸馏）测试。
/// 覆盖：precondition 失败整笔拒绝回稳 / 三件套全通过 / invariant 失败（K 值非法）整笔拒绝回稳 /
/// claim 空 assignee 拒绝 / submit 对称 / reopen on Archived 拒绝。需 SQLite 后端。

///|
/// 构建干净的 SQLite 引擎（先清库保证用例幂等）。
fn contract_engine(db_path : String) -> @engine.FistEngine {
  match @store.SqliteStore::open(db_path) {
    Some(s) => ignore(s.clear())
    None => abort("sqlite open failed: " + db_path)
  }
  match @engine.FistEngine::open_sqlite(db_path) {
    None => abort("engine open failed: " + db_path)
    Some(e) => e
  }
}

///|
fn cx_verdict(j : Json) -> String {
  match j.value("verdict") {
    Some(Json::String(s)) => s
    _ => abort("verdict 缺失: " + j.stringify())
  }
}

///|
fn cx_phase(j : Json) -> String {
  match j.value("phase") {
    Some(Json::String(s)) => s
    _ => abort("phase 缺失: " + j.stringify())
  }
}

///|
fn cx_reasons(j : Json) -> Array[String] {
  match j.value("reasons") {
    Some(Json::Array(arr)) =>
      arr.map(
        fn(v) {
          match v {
            Json::String(s) => s
            _ => ""
          }
        },
      )
    _ => abort("reasons 缺失: " + j.stringify())
  }
}

///|
fn cx_target(j : Json) -> String {
  match j.value("target_state") {
    Some(Json::String(s)) => s
    _ => abort("target_state 缺失: " + j.stringify())
  }
}

///|
fn publish_croot(e : @engine.FistEngine, desc? : String = "契约测试根任务") -> String {
  match e.publish(
    project_dir="/proj/demo",
    description=desc,
    created_by="human_steward",
    now="2026-09-26T10:00:00Z",
  ) {
    Ok(id) => id
    Err(m) => abort("publish failed: \{m}")
  }
}

///|
test "tx_contract：precondition 失败整笔拒绝且状态回稳（待领取任务 execute）" {
  let e = contract_engine("tc_r109_t1.db")
  let id = publish_croot(e)
  let j = e.transition_contract(id, "execute")
  assert_eq(cx_verdict(j), "rejected")
  assert_eq(cx_phase(j), "precondition")
  assert_eq(cx_reasons(j).length(), 1)
  // 回稳：库中任务仍为待领取
  match e.get_task(id) {
    Some(t) => assert_eq(t.status_to_string(), "待领取")
    None => abort("task missing")
  }
}

///|
test "tx_contract：三件套全通过（已领取任务 execute → allowed 执行中）" {
  let e = contract_engine("tc_r109_t2.db")
  let id = publish_croot(e)
  ignore(e.claim(task_id=id, assignee="agent", now="2026-09-26T10:01:00Z"))
  let j = e.transition_contract(id, "execute")
  assert_eq(cx_verdict(j), "allowed")
  assert_eq(cx_phase(j), "all_pass")
  assert_eq(cx_target(j), "执行中")
  // 只读：库中任务仍未执行（回稳语义对称：检查不改库）
  match e.get_task(id) {
    Some(t) => assert_eq(t.status_to_string(), "已领取")
    None => abort("task missing")
  }
}

///|
test "tx_contract：invariant 失败整笔拒绝（K 值非法 depth=0 任务 execute：前置过、不变量拒、回稳）" {
  let e = contract_engine("tc_r109_t3.db")
  // 注入非法 K 值任务（depth=0）到 store，模拟上游缺陷产生的非法状态
  match @store.SqliteStore::open("tc_r109_t3.db") {
    Some(s) =>
      match s.create_task(@core.Task::new(id="K0", project_dir="/p", depth=0, split_n=3)) {
        Ok(_) => ()
        Err(m) => abort("create_task failed: " + m)
      }
    None => abort("sqlite open failed")
  }
  // 认领（claim 不校验 K 值）→ 已领取，precondition 可过
  ignore(e.claim(task_id="K0", assignee="agent", now="2026-09-26T10:01:00Z"))
  let j = e.transition_contract("K0", "execute")
  assert_eq(cx_verdict(j), "rejected")
  assert_eq(cx_phase(j), "invariant")
  // reasons 命中 IN-2（K 值非法）
  let reasons = cx_reasons(j)
  assert_eq(reasons.length(), 1)
  assert_eq(reasons[0].has_prefix("IN-2"), true)
  // 回稳：库中任务仍为已领取（execute 未被应用）
  match e.get_task("K0") {
    Some(t) => assert_eq(t.status_to_string(), "已领取")
    None => abort("task missing")
  }
}

///|
test "tx_contract：claim 空 assignee 前置拒绝" {
  let e = contract_engine("tc_r109_t4.db")
  let id = publish_croot(e)
  let j = e.transition_contract(id, "claim", assignee="")
  assert_eq(cx_verdict(j), "rejected")
  assert_eq(cx_phase(j), "precondition")
  match e.get_task(id) {
    Some(t) => assert_eq(t.status_to_string(), "待领取")
    None => abort("task missing")
  }
}

///|
test "tx_contract：submit 对称（执行中可提交 allowed；待验收再提交前置拒绝）" {
  let e = contract_engine("tc_r109_t5.db")
  let id1 = publish_croot(e, desc="任务甲")
  ignore(e.claim(task_id=id1, assignee="agent", now="2026-09-26T10:01:00Z"))
  ignore(e.execute(task_id=id1, deliverable="契约执行交付", now="2026-09-26T10:02:00Z"))
  let j1 = e.transition_contract(id1, "submit")
  assert_eq(cx_verdict(j1), "allowed")
  assert_eq(cx_target(j1), "待验收")
  ignore(e.submit(task_id=id1, now="2026-09-26T10:03:00Z"))
  let j2 = e.transition_contract(id1, "submit")
  assert_eq(cx_verdict(j2), "rejected")
  assert_eq(cx_phase(j2), "precondition")
}

///|
test "tx_contract：reopen on 已归档 前置拒绝" {
  let e = contract_engine("tc_r109_t6.db")
  let id = publish_croot(e)
  ignore(e.claim(task_id=id, assignee="agent", now="2026-09-26T10:01:00Z"))
  ignore(e.execute(task_id=id, deliverable="交付", now="2026-09-26T10:02:00Z"))
  ignore(e.submit(task_id=id, now="2026-09-26T10:03:00Z"))
  ignore(e.verify(task_id=id, verifier="human_steward", now="2026-09-26T10:04:00Z"))
  ignore(e.archive(task_id=id, by="human_steward", now="2026-09-26T10:05:00Z"))
  let j = e.transition_contract(id, "reopen")
  assert_eq(cx_verdict(j), "rejected")
  assert_eq(cx_phase(j), "precondition")
  match e.get_task(id) {
    Some(t) => assert_eq(t.status_to_string(), "已归档")
    None => abort("task missing")
  }
}
