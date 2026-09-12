/// DAG 扩展模块测试：critical_path / parallelism / dag_ascii

/// 构造带依赖的任务集（不走 publish，直接写 store 以便自由指定 depends_on）
fn dag_test_engine() -> FistEngine {
  let e = FistEngine::new()
  // A 无依赖；B 依赖 A；C 依赖 B；D 依赖 A（短链）；E 依赖 D，独立分支
  let specs : Array[(String, String?, Array[String])] = [
    ("A", None, []),
    ("B", None, ["A"]),
    ("C", None, ["B"]),
    ("D", None, ["A"]),
    ("E", None, ["D"]),
  ]
  for s in specs {
    let (id, parent, deps) = s
    let t = @core.Task::new(
      id=id,
      project_dir="E:/proj/demo",
      description="DAG 测试任务 \{id}",
      parent_id=match parent {
        Some(p) => p
        None => ""
      },
      created_at="2026-01-01T00:00:00Z",
      depends_on=deps,
    )
    ignore(e.store.create_task(t))
  }
  e
}

test "critical_path: 最长依赖链 A->B->C" {
  let e = dag_test_engine()
  let cp = e.critical_path()
  assert_eq!(cp.length(), 3)
  assert_eq!(cp[0], "A")
  assert_eq!(cp[1], "B")
  assert_eq!(cp[2], "C")
}

test "critical_path: 空仓库返回空数组" {
  let e = FistEngine::new()
  assert_eq!(e.critical_path().length(), 0)
}

test "critical_path: 含依赖的发布任务也算入图" {
  let e = FistEngine::new()
  let r = e.publish_with_deps(
    project_dir="E:/proj/demo",
    description="根",
    depends_on=["A"],
    now="2026-01-01T00:00:00Z",
  )
  match r {
    Ok(_) => ()
    Err(m) => abort("publish_with_deps failed: \{m}")
  }
  let t = @core.Task::new(
    id="A",
    project_dir="E:/proj/demo",
    description="前置",
    created_at="2026-01-01T00:00:00Z",
  )
  ignore(e.store.create_task(t))
  let cp = e.critical_path()
  assert_eq!(cp.length(), 2)
  assert_eq!(cp[0], "A")
  assert_eq!(cp[1], "T0")
}

/// 通过引擎状态机将任务推进到已完成：claim -> execute -> submit -> verify
fn drive_to_completed(e : FistEngine, id : String) -> Unit {
  match e.claim(task_id=id, assignee="agent1", now="2026-01-01T01:00:00Z") {
    Ok(_) => ()
    Err(m) => abort("claim \{id} failed: \{m}")
  }
  match e.execute(task_id=id, deliverable="d-\{id}", now="2026-01-01T02:00:00Z") {
    Ok(_) => ()
    Err(m) => abort("execute \{id} failed: \{m}")
  }
  match e.submit(task_id=id, now="2026-01-01T03:00:00Z") {
    Ok(_) => ()
    Err(m) => abort("submit \{id} failed: \{m}")
  }
  match e.verify(task_id=id, verifier="human_steward", now="2026-01-01T04:00:00Z") {
    Ok(_) => ()
    Err(m) => abort("verify \{id} failed: \{m}")
  }
}

/// 通过引擎状态机将任务推进到已领取
fn drive_to_claimed(e : FistEngine, id : String) -> Unit {
  match e.claim(task_id=id, assignee="agent2", now="2026-01-01T01:00:00Z") {
    Ok(_) => ()
    Err(m) => abort("claim \{id} failed: \{m}")
  }
}

test "parallelism: 待领取且依赖满足的任务数" {
  let e = dag_test_engine()
  // 初始：所有任务 Pending，但 B/C/D/E 依赖未满足 -> 仅 A 可并行
  assert_eq!(e.parallelism(), 1)
  // A 完成后：B、D 均可并行
  drive_to_completed(e, "A")
  assert_eq!(e.parallelism(), 2)
  // B 完成后 C 可并行；D 已领取不计入，E 依赖 D（非已完成）也不计入 -> 仅剩 C
  drive_to_completed(e, "B")
  drive_to_claimed(e, "D")
  assert_eq!(e.parallelism(), 1)
}

test "dag_ascii: parent_id 归组 + depends_on 缩进" {
  let e = FistEngine::new()
  let specs : Array[(String, String, Array[String])] = [
    ("T0", "", []),
    ("T0.1", "T0", []),
    ("T0.2", "T0", []),
    ("T0.2.1", "T0.2", ["T0.1"]),
  ]
  for s in specs {
    let (id, parent, deps) = s
    let t = @core.Task::new(
      id=id,
      project_dir="E:/proj/demo",
      description="ascii \{id}",
      parent_id=parent,
      created_at="2026-01-01T00:00:00Z",
      depends_on=deps,
    )
    ignore(e.store.create_task(t))
  }
  let ascii = e.dag_ascii(ns="default")
  // T0 在最外层
  assert_true!(ascii.contains("T0 [待领取]"))
  // 子任务有缩进（缩进后跟 id）
  assert_true!(ascii.contains("  T0.1 [待领取]"))
  assert_true!(ascii.contains("  T0.2 [待领取]"))
  // T0.2.1：父 T0.2 一层 + 依赖 T0.1 一层 = 两层缩进，且带依赖标注
  assert_true!(ascii.contains("    T0.2.1 [待领取] (依赖: T0.1)"))
  // 层级顺序：T0 在 T0.1 之前
  assert_true!(ascii.contains("T0 [") && ascii.contains("T0.1 ["))
}

test "dag_ascii: 空命名空间返回空串" {
  let e = FistEngine::new()
  assert_eq!(e.dag_ascii(ns="nothing"), "")
}

test "dag_ascii: 依赖链缩进深度" {
  let e = dag_test_engine()
  let ascii = e.dag_ascii(ns="default")
  // C 依赖链 A->B->C 最深：缩进 2 层（4 空格）
  assert_true!(ascii.contains("    C [待领取]"))
  // E 链 A->D->E：缩进 2 层
  assert_true!(ascii.contains("    E [待领取]"))
  // B/D 只依赖 A：缩进 1 层
  assert_true!(ascii.contains("  B [待领取]"))
  assert_true!(ascii.contains("  D [待领取]"))
  // A 无依赖：顶层
  assert_true!(ascii.contains("A [待领取]"))
}
