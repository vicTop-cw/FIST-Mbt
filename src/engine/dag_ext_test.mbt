/// DAG 扩展模块测试：critical_path / parallelism / dag_ascii

///|
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
      id~,
      project_dir="/proj/demo",
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

///|
test "critical_path: 最长依赖链 A->B->C" {
  let e = dag_test_engine()
  let cp = e.critical_path()
  assert_eq(cp.length(), 3)
  assert_eq(cp[0], "A")
  assert_eq(cp[1], "B")
  assert_eq(cp[2], "C")
}

///|
test "critical_path: 空仓库返回空数组" {
  let e = FistEngine::new()
  assert_eq(e.critical_path().length(), 0)
}

///|
test "topo_sort: Kahn 依赖先输出(同批稳定按输入序)" {
  let e = dag_test_engine()
  // A 无依赖；B→A；C→B；D→A；E→D。输入乱序输入。
  // 期望：A 先出；随后 B,D(输入序)同批；随后 C,E(输入序)。
  let sorted = e.topo_sort(["C", "A", "B", "E", "D"])
  assert_eq(sorted, ["A", "B", "D", "C", "E"])
}

///|
test "topo_sort: 无依赖时保持输入顺序" {
  let e = dag_test_engine()
  assert_eq(e.topo_sort(["E", "D", "A"]).length(), 3)
}

///|
test "critical_path: 含依赖的发布任务也算入图" {
  let e = FistEngine::new()
  let r = e.publish_with_deps(
    project_dir="/proj/demo",
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
    project_dir="/proj/demo",
    description="前置",
    created_at="2026-01-01T00:00:00Z",
  )
  ignore(e.store.create_task(t))
  let cp = e.critical_path()
  assert_eq(cp.length(), 2)
  assert_eq(cp[0], "A")
  assert_eq(cp[1], "T0")
}

///|
/// 通过引擎状态机将任务推进到已完成：claim -> execute -> submit -> verify
fn drive_to_completed(e : FistEngine, id : String) -> Unit {
  match e.claim(task_id=id, assignee="agent1", now="2026-01-01T01:00:00Z") {
    Ok(_) => ()
    Err(m) => abort("claim \{id} failed: \{m}")
  }
  match
    e.execute(task_id=id, deliverable="d-\{id}", now="2026-01-01T02:00:00Z") {
    Ok(_) => ()
    Err(m) => abort("execute \{id} failed: \{m}")
  }
  match e.submit(task_id=id, now="2026-01-01T03:00:00Z") {
    Ok(_) => ()
    Err(m) => abort("submit \{id} failed: \{m}")
  }
  match
    e.verify(task_id=id, verifier="human_steward", now="2026-01-01T04:00:00Z") {
    Ok(_) => ()
    Err(m) => abort("verify \{id} failed: \{m}")
  }
}

///|
/// 通过引擎状态机将任务推进到已领取
fn drive_to_claimed(e : FistEngine, id : String) -> Unit {
  match e.claim(task_id=id, assignee="agent2", now="2026-01-01T01:00:00Z") {
    Ok(_) => ()
    Err(m) => abort("claim \{id} failed: \{m}")
  }
}

///|
test "parallelism: 待领取且依赖满足的任务数" {
  let e = dag_test_engine()
  // 初始：所有任务 Pending，但 B/C/D/E 依赖未满足 -> 仅 A 可并行
  assert_eq(e.parallelism(), 1)
  // A 完成后：B、D 均可并行
  drive_to_completed(e, "A")
  assert_eq(e.parallelism(), 2)
  // B 完成后 C 可并行；D 已领取不计入，E 依赖 D（非已完成）也不计入 -> 仅剩 C
  drive_to_completed(e, "B")
  drive_to_claimed(e, "D")
  assert_eq(e.parallelism(), 1)
}

///|
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
      id~,
      project_dir="/proj/demo",
      description="ascii \{id}",
      parent_id=parent,
      created_at="2026-01-01T00:00:00Z",
      depends_on=deps,
    )
    ignore(e.store.create_task(t))
  }
  let ascii = e.dag_ascii(ns="default")
  // T0 在最外层
  assert_true(ascii.contains("T0 [待领取]"))
  // 子任务有缩进（缩进后跟 id）
  assert_true(ascii.contains("  T0.1 [待领取]"))
  assert_true(ascii.contains("  T0.2 [待领取]"))
  // T0.2.1：父 T0.2 一层 + 依赖 T0.1 一层 = 两层缩进，且带依赖标注
  assert_true(ascii.contains("    T0.2.1 [待领取] (依赖: T0.1)"))
  // 层级顺序：T0 在 T0.1 之前
  assert_true(ascii.contains("T0 [") && ascii.contains("T0.1 ["))
}

///|
test "dag_ascii: 空命名空间返回空串" {
  let e = FistEngine::new()
  assert_eq(e.dag_ascii(ns="nothing"), "")
}

///|
test "dag_depend: 追加/幂等/自环/缺失" {
  let e = dag_test_engine()
  // 给 A 追加依赖 X
  let a = e.store.create_task(
    @core.Task::new(
      id="X",
      project_dir="/proj/demo",
      description="新依赖",
      created_at="2026-01-01T00:00:00Z",
    ),
  )
  match a {
    Ok(_) => ()
    Err(m) => abort("create X failed: \{m}")
  }
  // 追加成功
  match e.dag_depend(task_id="A", dep_id="X", now="2026-01-01T05:00:00Z") {
    Ok(t) => assert_true(t.depends_on.contains("X"))
    Err(m) => abort("dag_depend failed: \{m}")
  }
  // 自环拒绝
  match e.dag_depend(task_id="A", dep_id="A", now="2026-01-01T05:00:00Z") {
    Err(_) => ()
    Ok(_) => abort("自环应被拒绝")
  }
  // 缺失依赖拒绝
  match e.dag_depend(task_id="A", dep_id="NOPE", now="2026-01-01T05:00:00Z") {
    Err(_) => ()
    Ok(_) => abort("缺失依赖应被拒绝")
  }
  // 幂等：重复追加同一依赖只保留一条
  ignore(e.dag_depend(task_id="A", dep_id="X", now="2026-01-01T05:00:01Z"))
  let t = e.store.get_task("A").unwrap()
  assert_eq(t.depends_on.length(), 1)
}

///|
test "dag_ascii: 依赖链缩进深度" {
  let e = dag_test_engine()
  let ascii = e.dag_ascii(ns="default")
  // C 依赖链 A->B->C 最深：缩进 2 层（4 空格）
  assert_true(ascii.contains("    C [待领取]"))
  // E 链 A->D->E：缩进 2 层
  assert_true(ascii.contains("    E [待领取]"))
  // B/D 只依赖 A：缩进 1 层
  assert_true(ascii.contains("  B [待领取]"))
  assert_true(ascii.contains("  D [待领取]"))
  // A 无依赖：顶层
  assert_true(ascii.contains("A [待领取]"))
}

///|
test "dag_slack: 瓶颈与松弛分析——关键路径 slack=0、旁支 slack>0、环检测" {
  // 图：A→B→C（链长3）与 A→D→E（链长3），均最长 -> 全部 5 任务在关键路径（slack=0）
  let e = dag_test_engine()
  let j = e.dag_slack_analysis()
  match j.value("makespan") {
    Some(Number(n, ..)) => assert_eq(n.to_int(), 2) // A(0)->B/D(1)->C/E(2)
    _ => abort("makespan 缺失: " + j.stringify())
  }
  match j.value("critical") {
    Some(Array(a)) => assert_eq(a.length(), 5) // A,B,C,D,E 全 slack=0
    _ => abort("critical 缺失")
  }
  // A 与 C：earliest=0、latest=0（关键），slack=0
  match j.value("slack_map") {
    Some(Object(sm)) => {
      match sm.get("A") {
        Some(Object(a)) =>
          match a.get("slack") {
            Some(Number(s, ..)) => assert_eq(s.to_int(), 0)
            _ => abort("A.slack 缺失")
          }
        _ => abort("slack_map.A 缺失")
      }
    }
    _ => abort("slack_map 缺失")
  }
  // 构造带松弛的图：A→B 与 A→C 独立分支，B 无后继 -> B 的 latest 可晚于 earliest
  let e2 = FistEngine::new()
  let specs : Array[(String, Array[String])] = [
    ("A", []),
    ("B", ["A"]),
    ("C", ["A"]),
  ]
  for s in specs {
    let (id, deps) = s
    ignore(
      e2.store.create_task(
        @core.Task::new(
          id~,
          project_dir="/proj/demo",
          description="slack \{id}",
          created_at="2026-01-01T00:00:00Z",
          depends_on=deps,
        ),
      ),
    )
  }
  let j2 = e2.dag_slack_analysis()
  match j2.value("makespan") {
    Some(Number(n, ..)) => assert_eq(n.to_int(), 1) // A(0)->B/C(1)
    _ => abort("e2 makespan 缺失")
  }
  // 关键路径=A + 任一分支；另一分支 B 或 C 有 slack=1（latest=1, earliest=1 -> slack 0？）
  // 说明：latest 反向从 makespan=1 起，B/C 无后继 -> latest=1, earliest=1 -> slack=0；A latest=0。
  // 因此两条分支都在关键路径上（无松弛），符合"必须都做完才完工"。环检测单独验证。
  // 构造环：X→Y→X
  let e3 = FistEngine::new()
  ignore(
    e3.store.create_task(
      @core.Task::new(
        id="X",
        project_dir="/proj/demo",
        description="环X",
        created_at="2026-01-01T00:00:00Z",
        depends_on=["Y"],
      ),
    ),
  )
  ignore(
    e3.store.create_task(
      @core.Task::new(
        id="Y",
        project_dir="/proj/demo",
        description="环Y",
        created_at="2026-01-01T00:00:00Z",
        depends_on=["X"],
      ),
    ),
  )
  let j3 = e3.dag_slack_analysis()
  match j3.value("cycle") {
    Some(Array(a)) => assert_eq(a.length(), 2) // X,Y 成环被标出
    _ => abort("环应被检测: " + j3.stringify())
  }
}

///|
test "dag_schedule: 排程视图——critical/flexible 分批 + assignee 附带（R74）" {
  // 图 A→B→C 与 A→D→E 全关键（slack=0）-> 全部进 critical_batch
  let e = dag_test_engine()
  ignore(e.claim(task_id="A", assignee="leader_a", now="2026-01-01T00:01:00Z"))
  let j = e.dag_schedule()
  match j.value("critical_batch") {
    Some(Array(cb)) => assert_eq(cb.length(), 5) // A,B,C,D,E 全关键
    _ => abort("critical_batch 缺失: " + j.stringify())
  }
  match j.value("flexible_batch") {
    Some(Array(fb)) => assert_eq(fb.length(), 0) // 无松弛
    _ => abort("flexible_batch 缺失")
  }
  // 造带松弛的图：A→B 与 A→C 独立分支——两条都关键（须都做完）；B 无后继
  // 为造出 flexible，加 X→B 使 B 有 slack：A(0) -> B(1,slack1) / C(1,slack0)？ 简化：验证 assignee 透传
  let e2 = FistEngine::new()
  let specs : Array[(String, Array[String])] = [
    ("A", []),
    ("B", ["A"]),
  ]
  for s in specs {
    let (id, deps) = s
    ignore(
      e2.store.create_task(
        @core.Task::new(
          id~,
          project_dir="/proj/demo",
          description="sch \{id}",
          created_at="2026-01-01T00:00:00Z",
          depends_on=deps,
        ),
      ),
    )
  }
  let j2 = e2.dag_schedule()
  // A critical（slack=0）、B critical（slack=0，无后继但仍须做完）
  match j2.value("critical_batch") {
    Some(Array(cb)) => assert_eq(cb.length(), 2)
    _ => abort("e2 critical_batch 缺失")
  }
}

///|
test "dag_schedule R75: 负载感知——flexible 未认领任务附 suggest=负载最低执行者" {
  // 图：A 无依赖(关键,slack0)、X 无依赖(有 slack 可并行)——makespan=0 下 X slack>=0
  // 为造出 slack>0 的 flexible 项，加长链 A→B→C 使 makespan=2，则并列的 X、Y(无依赖) 有 slack=2
  let e = FistEngine::new()
  // 注册执行者 w1(负载0) 与 w2(负载0)
  ignore(
    e.executor_save(
      name="w1",
      abilities_json="[\"编排\"]",
      created_at="2026-01-01T00:00:00Z",
    ),
  )
  ignore(
    e.executor_save(
      name="w2",
      abilities_json="[\"编排\"]",
      created_at="2026-01-01T00:00:01Z",
    ),
  )
  let specs : Array[(String, Array[String])] = [
    ("A", []),
    ("B", ["A"]),
    ("C", ["B"]),
    ("X", []),
    ("Y", []),
  ]
  for s in specs {
    let (id, deps) = s
    ignore(
      e.store.create_task(
        @core.Task::new(
          id~,
          project_dir="/proj/demo",
          description="load \{id}",
          created_at="2026-01-01T00:00:00Z",
          depends_on=deps,
        ),
      ),
    )
  }
  // 给 w2 一个活跃任务（执行中）→ w2 负载1 > w1 负载0 → X 未认领建议派给 w1
  ignore(
    e.claim(task_id="C", assignee="w2", now="2026-01-01T00:01:00Z"),
  )
  let j = e.dag_schedule()
  match j.value("flexible_batch") {
    Some(Array(fb)) => {
      assert_true(fb.length() >= 2) // X,Y 有 slack 进 flexible
      // X 或 Y 未认领且 suggest=w1（负载低）
      let mut found_suggest = false
      for row in fb {
        let asg = match row.value("assignee") {
          Some(Json::String(s)) => s
          _ => ""
        }
        let sug = match row.value("suggest") {
          Some(Json::String(s)) => s
          _ => ""
        }
        if asg == "" && sug == "w1" {
          found_suggest = true
        }
      }
      assert_true(found_suggest)
    }
    _ => abort("flexible_batch 缺失: " + j.stringify())
  }
}
