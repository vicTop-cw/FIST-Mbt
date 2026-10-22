/// dag_mc_r3_test.mbt —— BUG-24 回归锁：samples 必须有上界，且被钳制时如实回显。
///
/// 病灶：旧实现只有下界钳制（`if samples < 10 {10} else {samples}`），
/// 调用方传 samples=200000 会让单次 MCP 同步调用阻塞 >100s，而客户端超时 30s——
/// 调用方看到的是"无响应"而不是结果，且没有任何字段告诉它跑了多少。

///|
fn r3mc_num(j : Json, key : String) -> Double {
  match j.value(key) {
    Some(Number(n, ..)) => n
    _ => abort("缺 " + key + ": " + j.stringify())
  }
}

///|
fn r3mc_bool(j : Json, key : String) -> Bool {
  match j.value(key) {
    Some(Json::True) => true
    Some(Json::False) => false
    _ => abort("缺 " + key + ": " + j.stringify())
  }
}

///|
fn r3mc_str(j : Json, key : String) -> String {
  match j.value(key) {
    Some(String(s)) => s
    _ => abort("缺 " + key + ": " + j.stringify())
  }
}

///|
fn r3mc_engine() -> @engine.FistEngine {
  let e = @engine.FistEngine::new()
  let mk = fn(id : String, desc : String, deps : Array[String]) {
    let t = @core.Task::new(
      id~,
      project_dir="/proj/mc",
      description=desc,
      created_at="2026-01-01T00:00:00Z",
      depends_on=deps,
    )
    ignore(e.store.create_task(t))
  }
  mk("A", "MC 任务 A [难度梯度 中]", [])
  mk("B", "MC 任务 B [难度梯度 难]", ["A"])
  e
}

///|
test "BUG-24：samples 超上界必须被钳制，并回显 requested/capped/note（不假装跑满）" {
  let e = r3mc_engine()
  let j = e.dag_mc(samples=200000)
  let used = r3mc_num(j, "samples")
  if used != 5000.0 {
    abort("samples 未钳到上界 5000，实际 " + used.to_string())
  }
  let req = r3mc_num(j, "samples_requested")
  if req != 200000.0 {
    abort(
      "samples_requested 应如实回显 200000，实际 " + req.to_string(),
    )
  }
  if !r3mc_bool(j, "samples_capped") {
    abort(
      "被钳制却回 samples_capped=false：调用方无从知道少跑了",
    )
  }
  let note = r3mc_str(j, "cap_note")
  if !note.contains("5000") || !note.contains("30") {
    abort("cap_note 必须说清上限与客户端预算关系: " + note)
  }
}

///|
test "BUG-24 成对：预算内的 samples 不得被误钳（否则上界成了新的正确性缺陷）" {
  let e = r3mc_engine()
  let j = e.dag_mc(samples=800)
  if r3mc_bool(j, "samples_capped") {
    abort("samples=800 不该被钳制")
  }
  if r3mc_num(j, "samples") != 800.0 {
    abort("800 被改了")
  }
  // 下界钳制仍在（旧行为零回归）
  let low = e.dag_mc(samples=1)
  if r3mc_num(low, "samples") != 10.0 {
    abort("samples<10 应抬到 10")
  }
}
