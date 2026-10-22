/// DAG 传递环检测测试（BUG-213）：dag_depend 必须拒绝会成环的依赖边
///
/// 独立于 dag_ext_test.mbt（并发 WIP），自带小工具函数造图，避免共享辅助函数。

///|
/// 造一条链 C→B→A（C 依赖 B，B 依赖 A，A 无依赖）+ 独立节点 D。
fn cycle_test_engine() -> @engine.FistEngine {
  let e = @engine.FistEngine::new()
  let specs : Array[(String, Array[String])] = [
    ("A", []),
    ("B", ["A"]),
    ("C", ["B"]),
    ("D", []),
  ]
  for s in specs {
    let (id, deps) = s
    let t = @core.Task::new(
      id~,
      project_dir="/proj/demo",
      description="环检测任务 \{id}",
      created_at="2026-01-01T00:00:00Z",
      depends_on=deps,
    )
    ignore(e.store.create_task(t))
  }
  e
}

///|
/// 直接给任务追加依赖（绕过 dag_depend，用于构造前置状态）。
fn add_dep(e : @engine.FistEngine, task_id : String, dep_id : String) -> Unit {
  ignore(e.dag_depend(task_id~, dep_id~, now="2026-01-01T05:00:00Z"))
}

///|
test "dag_depend: 传递环被拒绝（BUG-213）" {
  let e = cycle_test_engine()
  // 已存在 B→A（B 依赖 A）、C→B（C 依赖 B），即 C 传递依赖 A。
  // 现在尝试 A 依赖 C：会形成 A→C→B→A 环。
  match e.dag_depend(task_id="A", dep_id="C", now="2026-01-01T05:00:00Z") {
    Err(m) =>
      // 必须拒绝——修复前这里返回 Ok，测试 RED
      assert_true(m.length() > 0)
    Ok(_) => abort("传递环应被拒绝：A 依赖 C 会形成 A→C→B→A")
  }
  // 落库面未被污染：A 的 depends_on 仍是空
  let a = e.store.get_task("A").unwrap()
  assert_false(a.depends_on.contains("C"))
}

///|
test "dag_depend: 传递可达性正确（非环合法，BUG-213 对照）" {
  let e = cycle_test_engine()
  // D 依赖 A：D 与 A 之间无既有依赖链，合法。
  add_dep(e, "D", "A")
  let d = e.store.get_task("D").unwrap()
  assert_true(d.depends_on.contains("A"))
  // 二次依赖 C（D 依赖 C 后：C→B→A 与 D→C 并存，无环）。
  add_dep(e, "D", "C")
  let d2 = e.store.get_task("D").unwrap()
  assert_true(d2.depends_on.contains("C"))
  // 再尝试 C 依赖 D：会形成 C→D→C 环。
  match e.dag_depend(task_id="C", dep_id="D", now="2026-01-01T05:00:00Z") {
    Err(_) => ()
    Ok(_) => abort("C 依赖 D 应被拒绝：已有 D 依赖 C")
  }
}
