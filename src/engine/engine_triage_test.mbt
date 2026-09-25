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
/// 在 triage 返回里查找 id 任务，断言其 depends_on 恰为 [dep]。找到返回 true。
fn triage_row_has_dep(j : Json, id : String, dep : String) -> Bool {
  match j.value("tasks") {
    Some(Array(arr)) => {
      let mut found = false
      for row in arr {
        match row.value("id") {
          Some(String(s)) if s == id => {
            match row.value("depends_on") {
              Some(Array(d)) if d.length() == 1 =>
                match d[0] {
                  String(did) if did == dep => found = true
                  _ => ()
                }
              _ => ()
            }
          }
          _ => ()
        }
      }
      found
    }
    _ => false
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

///|
/// 完成一条根任务（无子任务，直接闭环）。
fn complete_root(e : @engine.FistEngine, tid : String) -> Unit {
  ignore(e.claim(task_id=tid, assignee="x", now="2026-09-05T10:06:00Z"))
  ignore(e.execute(task_id=tid, deliverable="done", now="2026-09-05T10:07:00Z"))
  ignore(e.submit(task_id=tid, now="2026-09-05T10:08:00Z"))
  ignore(
    e.verify(task_id=tid, verifier="v", now="2026-09-05T10:09:00Z"),
  )
}

///|
test "task_triage 暴露真实 DAG 依赖 depends_on（复用 dag_depend 前驱链）" {
  let e = tr_engine()
  let a = tr_publish(e, "前置根A（先做）")
  let b = tr_publish(e, "依赖根B（后做）")
  ignore(e.dag_depend(task_id=b, dep_id=a, now="2026-09-05T10:01:00Z"))
  // B 依赖 A：DAG 建边后 B 待领取但依赖未满足 → 不入 triage
  let j0 = e.triage("", "exec_demo", "")
  assert_eq(triage_row_has_dep(j0, b, a), false)
  // 完成 A，B 依赖满足 → 可领取并入 triage，且暴露 depends_on=[A]
  complete_root(e, a)
  let j = e.triage("", "exec_demo", "")
  assert_eq(triage_row_has_dep(j, b, a), true)
}

///|
test "selfdrive_pick_next 按推荐取走一条并认领；无可领取时不改动" {
  let e = tr_engine()
  let id = tr_publish(e, "打磨编排引擎调度")
  let j = e.pick_next("", "exec_demo", "编排", "2026-09-05T10:01:00Z")
  match j.value("claimed") {
    Some(True) => ()
    _ => abort("应认领成功: " + j.stringify())
  }
  match j.value("picked") {
    Some(String(pid)) => assert_eq(pid, id)
    _ => abort("picked 应等于根任务")
  }
  // 认领后该任务不再是待领取，再取单应无可领取
  let j2 = e.pick_next("", "exec_demo", "", "2026-09-05T10:02:00Z")
  match j2.value("claimed") {
    Some(False) => ()
    _ => abort("已认领后再取应无可领取: " + j2.stringify())
  }
}
