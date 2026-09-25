/// engine_triage_test.mbt —— 下一步该做啥（task_triage）测试
/// 覆盖：可领取任务排行 + suggestion + 难度标签复用；按 ns 过滤。
/// 说明：triage 与 status_summary/board 共用 engine.list_all()（即当前生效命名空间的任务集），
/// 因此测试在默认命名空间发布任务，再用 ns 参数在该集合内过滤。

///|
fn tr_engine() -> @engine.FistEngine {
  @engine.FistEngine::new()
}

///|
fn tr_publish(e : @engine.FistEngine, desc : String) -> String {
  match
    e.publish(
      project_dir="/proj/triage",
      description=desc,
      created_by="human_steward",
      now="2026-09-05T10:00:00Z",
    ) {
    Ok(id) => id
    Err(m) => abort("publish failed: \{m}")
  }
}

///|
test "task_triage 返回可领取排行 + suggestion，且带难度标签" {
  let e = tr_engine()
  let id = tr_publish(e, "构建一个编排引擎")
  ignore(
    e.plan_deep(
      task_id=id,
      split_n=2,
      by="leader",
      gradient=true,
      now="2026-09-05T10:01:00Z",
    ),
  )
  let j = e.triage("", "exec_demo", "")
  match j.value("count") {
    Some(Number(n, ..)) => assert_true(n.to_int() >= 1)
    _ => abort("count 缺失: " + j.stringify())
  }
  // suggestion 应指向某可领取任务
  match j.value("suggestion") {
    Some(Object(_)) => ()
    _ => abort("应有 suggestion: " + j.stringify())
  }
  // 至少第一条任务带难度标签（gradient 的 易/中/难 或 叶(可执行) 兜底）
  match j.value("tasks") {
    Some(Array(arr)) if not(arr.is_empty()) =>
      match arr[0].value("difficulty") {
        Some(String(d)) =>
          assert_true(
            d == "易" || d == "中" || d == "难" || d.contains("叶"),
          )
        _ => abort("difficulty 缺失")
      }
    _ => abort("tasks 不应为空")
  }
}

///|
test "task_triage 按 namespace 过滤：命中当前集合内该 ns，未命中为 0" {
  let e = tr_engine()
  ignore(tr_publish(e, "甲项目任务"))
  let j_x = e.triage("default", "exec_demo", "")
  match j_x.value("count") {
    Some(Number(n, ..)) => assert_eq(n.to_int(), 1)
    _ => abort("count 缺失 default: " + j_x.stringify())
  }
  // 不存在的 ns → count 0 且无 suggestion
  let j_z = e.triage("no-such-ns", "exec_demo", "")
  match j_z.value("count") {
    Some(Number(n, ..)) => assert_eq(n.to_int(), 0)
    _ => abort("count 缺失 z")
  }
  match j_z.value("suggestion") {
    None => ()
    _ => abort("空 ns 不应有 suggestion")
  }
}

///|
test "task_triage 能力偏好路由：want 命中的候选排头部" {
  let e = tr_engine()
  // 两条可领取根任务，一条描述含"编排引擎"，一条含"解析器"
  match
    e.publish(
      project_dir="/proj/triage",
      description="打磨编排引擎的调度与持久化",
      created_by="human_steward",
      now="2026-09-05T10:00:00Z",
    ) {
    Err(m) => abort("publish1 failed: \{m}")
    Ok(_) => ()
  }
  match
    e.publish(
      project_dir="/proj/triage",
      description="实现解析器的词法分析",
      created_by="human_steward",
      now="2026-09-05T10:00:00Z",
    ) {
    Err(m) => abort("publish2 failed: \{m}")
    Ok(_) => ()
  }
  // 再说 want=编排：编排那条应排头部
  let j = e.triage("", "exec_demo", "编排")
  match j.value("suggestion") {
    Some(Object(m)) =>
      match m.get("task_id") {
        Some(String(tid)) =>
          match e.get_task(tid) {
            Some(t) => assert_eq(t.description.contains("编排"), true)
            None => abort("suggestion tid missing in store")
          }
        _ => abort("suggestion.task_id 缺失")
      }
    _ => abort("应有 suggestion")
  }
  // want 应回显在返回里
  match j.value("want") {
    Some(String(w)) => assert_eq(w, "编排")
    _ => abort("want 应回显")
  }
}
