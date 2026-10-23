/// omega_gate_wbtest.mbt —— BUG-75 的成对锁：外部判据的回执必须带得出"判据打了什么"。
///
/// 缺陷原形（本轮验证段亲自撞上）：run_check 回执只有
/// {ok, check_id, task_id, round, status, note}，stdout/stderr 只进 specs 表且无工具可读回。
/// 于是 passed 时举不出判据文本、只能本地重跑同一条命令（＝退回 run_check 要防的自述路径），
/// failed 时更糟：只知退出码非 0，不知是断言红、路径不存在还是被白名单拒。
/// 这里钉三件事：
///   ① 尾巴必须带回来，且取的是**末** N 字符（判据的关键信息在结尾）；
///   ② 回显的 status 必须是**从 check_json 推导**的那份，调用方谎报无效；
///   ③ 解析失败/字段缺失时安静回空串，不得因为"没输出"就让回执本身失败。

///|
fn og_engine() -> FistEngine {
  FistEngine::new()
}

///|
/// 造一个存在的任务（gate_check_record 对不存在的 task_id 直接 Err）。
fn og_task(e : FistEngine) -> String {
  match
    e.publish(
      project_dir=".",
      description="BUG-75 回执诊断锁",
      created_by="human_steward",
      now="2026-09-27T06:00:00Z",
    ) {
    Ok(x) => x
    Err(m) => abort("publish failed: \{m}")
  }
}

///|
/// 拼 run_check 真实产出形态的 JSON（{ok, code, stdout, stderr}）。
/// 用 stringify 而不是手写转义：字面量里连环 \" 在这个仓里已经咬过不止一次。
fn og_check_json(ok : Bool, stdout : String, stderr : String) -> String {
  let m : Map[String, Json] = Map([])
  m.set("ok", Json::boolean(ok))
  m.set("code", Json::number(if ok { 0.0 } else { 1.0 }))
  m.set("stdout", Json::string(stdout))
  m.set("stderr", Json::string(stderr))
  Json::object(m).stringify()
}

///|
fn og_repeat(ch : Char, n : Int32) -> String {
  let out : Array[Char] = []
  let mut i = 0
  while i < n {
    out.push(ch)
    i = i + 1
  }
  String::from_array(out)
}

///|
/// 从回执 Json 里取字符串字段（取不到就 abort，让测试失败信息直说哪个字段没了）。
fn og_str(rec : Json, key : String) -> String {
  match rec {
    Object(m) =>
      match m.get(key) {
        Some(String(s)) => s
        _ => abort("回执缺字符串字段 \{key}：\{rec.stringify()}")
      }
    _ => abort("回执不是 JSON 对象：\{rec.stringify()}")
  }
}

///|
/// 从回执 Json 里取布尔字段。
fn og_bool(rec : Json, key : String) -> Bool {
  match rec {
    Object(m) =>
      match m.get(key) {
        Some(True) => true
        Some(False) => false
        _ => abort("回执缺布尔字段 \{key}：\{rec.stringify()}")
      }
    _ => abort("回执不是 JSON 对象")
  }
}

///|
fn og_record(
  e : FistEngine,
  task_id : String,
  json : String,
  status : String,
) -> Json {
  match e.gate_check_record(task_id, json, status, "2026-09-27T06:01:00Z") {
    Ok(r) => r
    Err(m) => abort("gate_check_record failed: \{m}")
  }
}

///|
test "og_1_回执必须带回 stdout_tail 且 status 用推导值" {
  let e = og_engine()
  let tid = og_task(e)
  let payload = og_check_json(true, "PASS 六守卫全绿\nPASS 453/453\n", "")
  // 调用方故意谎报 status：回执里出现的必须是推导出的 "passed"
  let rec = og_record(e, tid, payload, "failed-由调用方随口给的")
  assert_eq(og_str(rec, "status"), "passed")
  assert_true(og_str(rec, "stdout_tail").contains("453/453"))
  assert_eq(og_str(rec, "stderr_tail"), "")
  assert_eq(og_bool(rec, "output_truncated"), false)
  // 记录成功 ≠ 判据通过：回执顶层 ok 说的是"这条记录落库成功"
  assert_true(og_bool(rec, "ok"))
}

///|
test "og_2_长输出取的是末N字符而不是前N" {
  let e = og_engine()
  let tid = og_task(e)
  let n = gate_check_tail_limit()
  // 前 n 个是噪声 H、后 n 个是结尾 T：谁取前一半，谁的尾巴里就会留着 H
  let long_out = og_repeat('H', n) + og_repeat('T', n)
  let rec = og_record(
    e,
    tid,
    og_check_json(false, long_out, long_out),
    "passed",
  )
  let out = og_str(rec, "stdout_tail")
  let err = og_str(rec, "stderr_tail")
  assert_eq(out.length(), n)
  assert_eq(out.contains("H"), false)
  assert_eq(out, og_repeat('T', n))
  assert_eq(err.length(), n)
  assert_eq(err.contains("H"), false)
  assert_true(og_bool(rec, "output_truncated"))
  // 判据失败时，谎报的 status 不许污染回执（这条同时防"把 passed 塞进 note 蒙混"）
  assert_eq(og_str(rec, "status"), "failed")
}

///|
test "og_3_坏JSON与缺字段一律安静回空串不报错" {
  let e = og_engine()
  let tid = og_task(e)
  // ① 整份不是 JSON：fail-closed 判 failed，但尾巴安静为空
  let bad = og_record(e, tid, "这不是 JSON", "passed")
  assert_eq(og_str(bad, "status"), "failed")
  assert_eq(og_str(bad, "stdout_tail"), "")
  assert_eq(og_bool(bad, "output_truncated"), false)
  // ② 是 JSON 但 stdout 不是字符串：同样回空串，不得抛
  let wm : Map[String, Json] = Map([])
  wm.set("ok", Json::boolean(true))
  wm.set("stdout", Json::number(123.0))
  let rec2 = og_record(e, tid, Json::object(wm).stringify(), "whatever")
  assert_eq(og_str(rec2, "stdout_tail"), "")
  assert_eq(og_str(rec2, "status"), "passed")
  // ③ 单元层：短串原样返回、不置 truncated
  let (s, cut) = _json_str_tail(og_check_json(true, "短", ""), "stdout", 100)
  assert_eq(s, "短")
  assert_eq(cut, false)
}

///|
/// 造一个带外部判据闸门标记（[gate:required]）的任务。
fn og_gate_task(e : FistEngine) -> String {
  match
    e.publish(
      project_dir=".",
      description="BUG-376 闸门锁：[gate:required] 无记录不得验收",
      created_by="human_steward",
      now="2026-09-27T06:00:00Z",
    ) {
    Ok(x) => x
    Err(m) => abort("publish failed: \{m}")
  }
}

///|
/// BUG-376：零 run_check 记录仍判通过是假绿——缺记录必须拒绝并给可读原因。
test "og_4_缺外部检查记录时闸门拒绝并给可读原因（BUG-376）" {
  let e = og_engine()
  let tid = og_gate_task(e)
  match e.gate_verify_gate(tid) {
    Err(msg) => {
      assert_true(msg.contains("尚无外部检查记录"))
      assert_true(msg.contains(tid))
    }
    Ok(_) => abort("带 [gate:required] 的任务无记录时应拒绝验收")
  }
}

///|
/// 最新记录 passed 且新鲜 -> 放行。
test "og_5_新鲜且 passed 的检查记录放行" {
  let e = og_engine()
  let tid = og_gate_task(e)
  ignore(
    og_record(
      e,
      tid,
      og_check_json(true, "PASS 六守卫全绿\n", ""),
      "passed",
    ),
  )
  match e.gate_verify_gate(tid) {
    Ok(_) => assert_true(true)
    Err(m) => abort("新鲜 passed 记录应放行：\{m}")
  }
}

///|
/// 记录早于任务最后更新 -> 拒绝（改完代码后不许用旧记录蒙混）。
test "og_6_检查记录早于任务更新时拒绝（新鲜度）" {
  let e = og_engine()
  let tid = og_gate_task(e)
  ignore(og_record(e, tid, og_check_json(true, "PASS\n", ""), "passed"))
  // 任务在记录之后被认领/更新（updated_at 后移）
  match
    e.claim(task_id=tid, assignee="human_steward", now="2026-09-27T07:00:00Z") {
    Ok(_) => ()
    Err(m) => abort("claim failed: \{m}")
  }
  match e.gate_verify_gate(tid) {
    Err(msg) => {
      assert_true(msg.contains("早于任务最后更新"))
      assert_true(msg.contains("请重新执行 run_check"))
    }
    Ok(_) => abort("陈旧记录应拒绝验收")
  }
}

///|
/// 未带 [gate:required] 的任务直接放行（默认关闭即现状，零侵入）。
test "og_7_未标记任务放行（零侵入）" {
  let e = og_engine()
  let tid = og_task(e) // 无 gate 标记
  match e.gate_verify_gate(tid) {
    Ok(_) => assert_true(true)
    Err(m) => abort("未标记任务应直接放行：\{m}")
  }
}
