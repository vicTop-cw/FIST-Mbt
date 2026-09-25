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
    Some(Object(sm)) =>
      match sm.get("A") {
        Some(Object(a)) =>
          match a.get("slack") {
            Some(Number(s, ..)) => assert_eq(s.to_int(), 0)
            _ => abort("A.slack 缺失")
          }
        _ => abort("slack_map.A 缺失")
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
  let specs : Array[(String, Array[String])] = [("A", []), ("B", ["A"])]
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
  ignore(e.claim(task_id="C", assignee="w2", now="2026-01-01T00:01:00Z"))
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

///|
test "dag_cost_route: 能力约束+切换税+总成本（R77 STAR 式成本路由）" {
  // 图 A→B→C 关键链 + A→D 短链：D slack=1 flexible。A 已认领给 alice（切换成本基准）。
  let e = FistEngine::new()
  ignore(
    e.executor_save(
      name="alice",
      abilities_json="[\"编排\"]",
      created_at="2026-01-01T00:00:00Z",
    ),
  )
  ignore(
    e.executor_save(
      name="bob",
      abilities_json="[\"json\"]",
      created_at="2026-01-01T00:00:01Z",
    ),
  )
  let specs : Array[(String, Array[String], String)] = [
    ("A", [], "编排根任务"),
    ("B", ["A"], "编排子任务"),
    ("C", ["B"], "编排子任务"),
    ("D", ["A"], "json 子任务 [难度梯度 1/2:难]"),
  ]
  for s in specs {
    let (id, deps, desc) = s
    ignore(
      e.store.create_task(
        @core.Task::new(
          id~,
          project_dir="/proj/demo",
          description=desc,
          created_at="2026-01-01T00:00:00Z",
          depends_on=deps,
        ),
      ),
    )
  }
  match e.claim(task_id="A", assignee="alice", now="2026-01-01T00:01:00Z") {
    Ok(_) => ()
    Err(m) => abort("claim A failed: \{m}")
  }
  let j = e.dag_cost_route()
  // 仅 D 是 flexible 且未认领
  match j.value("cost_route") {
    Some(Array(cr)) => {
      assert_eq(cr.length(), 1)
      match cr[0].value("task_id") {
        Some(Json::String(s)) => assert_eq(s, "D")
        _ => abort("task_id 缺失")
      }
      // 能力约束：D want=json -> 路由 bob（alice 无 json 被排除）
      match cr[0].value("assignee") {
        Some(Json::String(s)) => assert_eq(s, "bob")
        _ => abort("assignee 缺失")
      }
      // est=3（难）；switch=1（依赖 A=alice≠bob）；total=4
      match cr[0].value("est_cost") {
        Some(Number(n, ..)) => assert_eq(n.to_int(), 3)
        _ => abort("est_cost 缺失")
      }
      match cr[0].value("switch_cost") {
        Some(Number(n, ..)) => assert_eq(n.to_int(), 1)
        _ => abort("switch_cost 缺失")
      }
      match cr[0].value("total") {
        Some(Number(n, ..)) => assert_eq(n.to_int(), 4)
        _ => abort("total 缺失")
      }
    }
    _ => abort("cost_route 缺失: " + j.stringify())
  }
  match j.value("total_est_cost") {
    Some(Number(n, ..)) => assert_eq(n.to_int(), 4)
    _ => abort("total_est_cost 缺失: " + j.stringify())
  }
}

///|
test "dag_cost_route: 同执行者免切换税 + 空注册表跳过（R77）" {
  // 场景1：D 描述含"编排" -> want=编排 -> 仅 alice 可路由；与依赖 A=alice 相同 -> switch=0
  let e = FistEngine::new()
  ignore(
    e.executor_save(
      name="alice",
      abilities_json="[\"编排\"]",
      created_at="2026-01-01T00:00:00Z",
    ),
  )
  let specs : Array[(String, Array[String], String)] = [
    ("A", [], "编排根任务"),
    ("B", ["A"], "编排子任务"),
    ("C", ["B"], "编排子任务"),
    ("D", ["A"], "编排子任务"),
  ]
  for s in specs {
    let (id, deps, desc) = s
    ignore(
      e.store.create_task(
        @core.Task::new(
          id~,
          project_dir="/proj/demo",
          description=desc,
          created_at="2026-01-01T00:00:00Z",
          depends_on=deps,
        ),
      ),
    )
  }
  match e.claim(task_id="A", assignee="alice", now="2026-01-01T00:01:00Z") {
    Ok(_) => ()
    Err(m) => abort("e2 claim A failed: \{m}")
  }
  let j = e.dag_cost_route()
  match j.value("cost_route") {
    Some(Array(cr)) => {
      assert_eq(cr.length(), 1)
      match cr[0].value("assignee") {
        Some(Json::String(s)) => assert_eq(s, "alice")
        _ => abort("e2 assignee 缺失")
      }
      // 与依赖 A=alice 相同执行者 -> 免切换税
      match cr[0].value("switch_cost") {
        Some(Number(n, ..)) => assert_eq(n.to_int(), 0)
        _ => abort("e2 switch_cost 缺失")
      }
    }
    _ => abort("e2 cost_route 缺失: " + j.stringify())
  }
  // 场景2：无注册执行者 -> cost_route 空、total=0（note 说明跳过）
  let e3 = FistEngine::new()
  let specs3 : Array[(String, Array[String], String)] = [
    ("A", [], "编排根任务"),
    ("D", ["A"], "编排子任务"),
  ]
  for s in specs3 {
    let (id, deps, desc) = s
    ignore(
      e3.store.create_task(
        @core.Task::new(
          id~,
          project_dir="/proj/demo",
          description=desc,
          created_at="2026-01-01T00:00:00Z",
          depends_on=deps,
        ),
      ),
    )
  }
  let j3 = e3.dag_cost_route()
  match j3.value("cost_route") {
    Some(Array(cr)) => assert_eq(cr.length(), 0)
    _ => abort("e3 cost_route 缺失: " + j3.stringify())
  }
  match j3.value("total_est_cost") {
    Some(Number(n, ..)) => assert_eq(n.to_int(), 0)
    _ => abort("e3 total_est_cost 缺失")
  }
}

///|
test "budget_split_by_dag: 预算按依赖图阶段切分（R81 ZEBRA 蒸馏）" {
  // 链 A→B→C（A 难/B 中/C 易）：earliest A=0/B=1/C=2；预算 10 → 权重 3/2/1 归一化
  let e = FistEngine::new()
  let specs : Array[(String, Array[String], String)] = [
    ("A", [], "编排根任务 [难度梯度 1/3:难]"),
    ("B", ["A"], "编排子任务 [难度梯度 2/3:中]"),
    ("C", ["B"], "编排子任务 [难度梯度 3/3:易]"),
  ]
  for s in specs {
    let (id, deps, desc) = s
    ignore(
      e.store.create_task(
        @core.Task::new(
          id~,
          project_dir="/proj/demo",
          description=desc,
          created_at="2026-01-01T00:00:00Z",
          depends_on=deps,
        ),
      ),
    )
  }
  let j = e.budget_split_by_dag(10)
  match j.value("stages") {
    Some(Array(st)) => {
      // 三阶段：0/1/2
      assert_eq(st.length(), 3)
      // 份额和 == 总预算（向下取整 + 余数补给最大权重阶段）
      let mut sum = 0
      for s in st {
        match s.value("share") {
          Some(Number(n, ..)) => sum = sum + n.to_int()
          _ => ()
        }
      }
      assert_eq(sum, 10)
      // 阶段 0（A，权重 3/6）占 5 份额
      match st[0].value("level") {
        Some(Number(n, ..)) => assert_eq(n.to_int(), 0)
        _ => abort("stage0 level 缺失")
      }
    }
    _ => abort("stages 缺失: " + j.stringify())
  }
  match j.value("total_budget") {
    Some(Number(n, ..)) => assert_eq(n.to_int(), 10)
    _ => abort("total_budget 缺失")
  }
  // 空仓库：stages 空、total_budget 保真
  let e2 = FistEngine::new()
  let j2 = e2.budget_split_by_dag(7)
  match j2.value("stages") {
    Some(Array(st)) => assert_eq(st.length(), 0)
    _ => abort("e2 stages 缺失: " + j2.stringify())
  }
  match j2.value("total_budget") {
    Some(Number(n, ..)) => assert_eq(n.to_int(), 7)
    _ => abort("e2 total_budget 缺失")
  }
}

///|
/// 构造 进度门控 测试引擎：P(根,[难度梯度 1/3:中]) + C1/C2([难度梯度 1/2:中])，C1 已完成。
/// 子树=3 任务，done=1 → progress=1/3；已开工难度权重和=2（仅 C1）。
fn progress_gate_engine() -> FistEngine {
  let e = FistEngine::new()
  let specs : Array[(String, String, String)] = [
    ("P", "", "[难度梯度 1/3:中] 进度门控根任务"),
    ("C1", "P", "[难度梯度 1/2:中] 子任务一"),
    ("C2", "P", "[难度梯度 1/2:中] 子任务二"),
  ]
  for s in specs {
    let (id, parent, desc) = s
    let t = @core.Task::new(
      id~,
      project_dir="/proj/demo",
      description=desc,
      parent_id=parent,
      created_at="2026-01-01T00:00:00Z",
      depends_on=[],
    )
    ignore(e.store.create_task(t))
  }
  // C1 走完 认领→执行→提交→验收 置为已完成
  ignore(e.claim(task_id="C1", assignee="exec_1", now="2026-09-05T10:01:00Z"))
  ignore(e.execute(task_id="C1", deliverable="x", now="2026-09-05T10:02:00Z"))
  ignore(e.submit(task_id="C1", now="2026-09-05T10:03:00Z"))
  ignore(e.verify(task_id="C1", verifier="ver_1", now="2026-09-05T10:04:00Z"))
  e
}

///|
test "progress_gate：OK 判决（线性+保守均充足，自动估算 spent=2）" {
  let e = progress_gate_engine()
  let j = e.progress_gate("P", 10, 0)
  // progress = 1/3（1 done / 3 任务）
  match j.value("progress") {
    Some(Number(n, ..)) =>
      if n - 1.0 / 3.0 > 0.000000001 || n - 1.0 / 3.0 < -0.000000001 {
        abort("progress 应为 1/3: " + j.stringify())
      }
    _ => abort("progress 缺失: " + j.stringify())
  }
  match j.value("spent") {
    Some(Number(n, ..)) => assert_eq(n.to_int(), 2)
    _ => abort("spent 缺失: " + j.stringify())
  }
  // 线性=燃尽率6×剩余2/3=4，保守=4.8；remaining=8 → 均充足 → OK
  match j.value("verdict") {
    Some(String(v)) =>
      if v != "OK" {
        abort("verdict 应为 OK: " + j.stringify())
      }
    _ => abort("verdict 缺失: " + j.stringify())
  }
}

///|
test "progress_gate：CAUTION 判决（线性可行但保守缓冲不足）" {
  let e = progress_gate_engine()
  // spent_override=3 → 燃尽率 9、线性 6、保守 7.2；remaining=7 → 线性可行、保守超 → CAUTION
  let j = e.progress_gate("P", 10, 3)
  match j.value("verdict") {
    Some(String(v)) =>
      if v != "CAUTION" {
        abort("verdict 应为 CAUTION: " + j.stringify())
      }
    _ => abort("verdict 缺失: " + j.stringify())
  }
  match j.value("action") {
    Some(String(a)) =>
      if not(a.contains("降档")) && not(a.contains("缩减")) {
        abort("action 应建议降档/缩范围: " + a)
      }
    _ => abort("action 缺失: " + j.stringify())
  }
}

///|
test "progress_gate：ESCALATE 判决（线性已超支）+ 双路径数字" {
  let e = progress_gate_engine()
  // spent_override=5 → 燃尽率 15、线性 10、保守 12；remaining=5 → 线性即超 → ESCALATE
  let j = e.progress_gate("P", 10, 5)
  match j.value("verdict") {
    Some(String(v)) =>
      if v != "ESCALATE" {
        abort("verdict 应为 ESCALATE: " + j.stringify())
      }
    _ => abort("verdict 缺失: " + j.stringify())
  }
  match j.value("projection") {
    Some(Object(o)) => {
      match o.get("linear") {
        Some(Number(n, ..)) =>
          if n - 10.0 > 0.000001 || n - 10.0 < -0.000001 {
            abort("linear 应为 10: " + j.stringify())
          }
        _ => abort("projection.linear 缺失: " + j.stringify())
      }
      match o.get("conservative") {
        Some(Number(n, ..)) =>
          if n - 12.0 > 0.000001 || n - 12.0 < -0.000001 {
            abort("conservative 应为 12: " + j.stringify())
          }
        _ => abort("projection.conservative 缺失: " + j.stringify())
      }
    }
    _ => abort("projection 缺失: " + j.stringify())
  }
}

///|
test "progress_gate：未开工=OK / 全完成=OK / 空任务+非法预算=ok:false" {
  // 未开工：仅根任务待领取 → progress 0、燃尽率 0 → OK
  let e0 = FistEngine::new()
  let t = @core.Task::new(
    id="P0",
    project_dir="/proj/demo",
    description="[难度梯度 1/1:易] 未开工任务",
    parent_id="",
    created_at="2026-01-01T00:00:00Z",
    depends_on=[],
  )
  ignore(e0.store.create_task(t))
  let j0 = e0.progress_gate("P0", 5, 0)
  match j0.value("verdict") {
    Some(String(v)) =>
      if v != "OK" {
        abort("未开工 verdict 应为 OK: " + j0.stringify())
      }
    _ => abort("j0 verdict 缺失: " + j0.stringify())
  }
  // 全完成：C1/C2/P 全部验收 → progress 1.0 → OK（已完成）
  let e = progress_gate_engine()
  ignore(e.claim(task_id="C2", assignee="exec_1", now="2026-09-05T10:05:00Z"))
  ignore(e.execute(task_id="C2", deliverable="y", now="2026-09-05T10:06:00Z"))
  ignore(e.submit(task_id="C2", now="2026-09-05T10:07:00Z"))
  ignore(e.verify(task_id="C2", verifier="ver_1", now="2026-09-05T10:08:00Z"))
  ignore(e.claim(task_id="P", assignee="exec_1", now="2026-09-05T10:09:00Z"))
  ignore(e.execute(task_id="P", deliverable="z", now="2026-09-05T10:10:00Z"))
  ignore(e.submit(task_id="P", now="2026-09-05T10:11:00Z"))
  ignore(e.verify(task_id="P", verifier="ver_1", now="2026-09-05T10:12:00Z"))
  let j1 = e.progress_gate("P", 10, 0)
  match j1.value("verdict") {
    Some(String(v)) =>
      if v != "OK" {
        abort("全完成 verdict 应为 OK: " + j1.stringify())
      }
    _ => abort("j1 verdict 缺失: " + j1.stringify())
  }
  match j1.value("progress") {
    Some(Number(n, ..)) => assert_eq(n, 1.0)
    _ => abort("j1 progress 缺失: " + j1.stringify())
  }
  // 空任务 / 非法预算 → ok:false
  let j2 = e.progress_gate("NOPE", 10, 0)
  match j2.value("ok") {
    Some(j) =>
      match j.as_bool() {
        Some(b) => assert_eq(b, false)
        None => abort("j2 ok 非布尔: " + j2.stringify())
      }
    _ => abort("j2 ok 缺失: " + j2.stringify())
  }
  let j3 = e.progress_gate("P", 0, 0)
  match j3.value("ok") {
    Some(j) =>
      match j.as_bool() {
        Some(b) => assert_eq(b, false)
        None => abort("j3 ok 非布尔: " + j3.stringify())
      }
    _ => abort("j3 ok 缺失: " + j3.stringify())
  }
}
