/// dag_core_wbtest.mbt —— BUG-455 第一批：4 个 DAG 核心方法此前**零测试**(测试文件里 0 次出现)。
///
/// 覆盖：`topo_sort` / `ready_tasks` / `critical_path` / `parallelism`。
/// **为什么这四个最该测**：它们全是**纯计算**（只读 store + 图算法），
/// 却一个都没有锁 —— 而 `dag_sort`/`dag_ready`/`dag_critical_path`/`dag_parallelism`
/// 四个 MCP 工具的全部实质逻辑就在这四个方法里（handler 只是纯转发）。
///
/// 建图模式照抄 `engine_dag_mc_wbtest.mbt`（`FistEngine::new()` 内存后端 + 直接 `create_task`），
/// **不走 `publish`** —— 因为 `publish` 带深度/默认值/根 id 顺延约束，会把"造图"这件事搞脏。
///
/// 图（4 节点，菱形）：
/// ```
///   A        A：无依赖
///   ├─ B     B：依赖 A
///   │  └─ D  D：依赖 B
///   └─ C     C：依赖 A
/// ```

///|
/// 造菱形图。**不建环**（环路径由 `dag_cycle_test.mbt` 覆盖）。
fn dag_core_setup() -> FistEngine {
  let e = FistEngine::new()
  let mk = fn(id : String, deps : Array[String]) {
    ignore(
      e.store.create_task(
        @core.Task::new(
          id~,
          project_dir="/proj/dagcore",
          description="node " + id,
          created_at="2026-01-01T00:00:00Z",
          depends_on=deps,
        ),
      ),
    )
  }
  mk("A", [])
  mk("B", ["A"])
  mk("C", ["A"])
  mk("D", ["B"])
  e
}

///|
/// 锁 1：`topo_sort` 必须把依赖排在前面（A 在 B/C 前，B 在 D 前）。
///
/// **输入故意打乱顺序**（D,B,A,C）—— 若实现只是"原样返回"或"按 id 字典序"，
/// 本格会红：「按 id 字典序」得到 A,B,C,D 恰好也对，所以额外断言 **C 在 D 前**（字典序会 C<D，
/// 而拓扑序里 C 与 D 无依赖关系，两者先后不做要求）—— 真正钉住的是**依赖约束**：
/// `index(A) < index(B) < index(D)` 且 `index(A) < index(C)`。
test "dag455_topo_sort_respects_dependency_order" {
  let e = dag_core_setup()
  let ordered = e.topo_sort(["D", "B", "A", "C"])
  assert_eq(ordered.length(), 4)
  let idx = fn(id : String) -> Int {
    let mut i = -1
    let mut n = 0
    for x in ordered {
      if x == id {
        i = n
      }
      n = n + 1
    }
    i
  }
  let ia = idx("A")
  let ib = idx("B")
  let ic = idx("C")
  let id_ = idx("D")
  assert_true(ia >= 0 && ib >= 0 && ic >= 0 && id_ >= 0)
  assert_true(ia < ib) // A 必须先于 B
  assert_true(ib < id_) // B 必须先于 D
  assert_true(ia < ic) // A 必须先于 C
}

///|
/// 锁 2：`ready_tasks` 只返回**依赖全部完成**的 pending 任务。
///
/// 初始全 pending ⇒ 只有 A（无依赖）ready。三个依赖它的（B/C/D）都不该出现。
test "dag455_ready_tasks_only_when_deps_completed" {
  let e = dag_core_setup()
  let ready = e.ready_tasks(ns_filter="default")
  assert_eq(ready.length(), 1)
  assert_eq(ready[0].id, "A")
}

///|
/// 锁 3：`critical_path` 返回**最长依赖链**（A→B→D，长度 3），不是任意一条链。
///
/// 图里还有一条 A→C（长度 2）—— 若实现取"随便一条"，会以 1/2 概率拿错；
/// 本格钉住「最长」这个语义。
test "dag455_critical_path_returns_longest_chain" {
  let e = dag_core_setup()
  let cp = e.critical_path()
  assert_eq(cp.length(), 3)
  assert_eq(cp[0], "A")
  assert_eq(cp[1], "B")
  assert_eq(cp[2], "D")
}

///|
/// 锁 4：`parallelism` 数的是「**当前可并行执行**的 pending 任务数」。
///
/// 初始全 pending ⇒ 只有 A 的依赖满足 ⇒ 1。
/// 把 A 变成「已完成」后 ⇒ B 和 C 同时 ready（D 仍被 B 挡住）⇒ 2。
/// **这一格同时钉住「依赖完成后解锁」与「不重复计数」**：若实现只数 pending 总数会得到 4/3。
test "dag455_parallelism_counts_ready_pending_not_all" {
  let e = dag_core_setup()
  assert_eq(e.parallelism(), 1) // 只有 A
  // 把 A 标成已完成：`Task` 不可变、没有 `with_status`（实测报 "has no method with_status"）
  // ⇒ 走 `from_db` 造同 id 的 Completed 行，再 `update_task` 覆盖。
  let a_done = @core.Task::from_db(
    "A",
    None,
    "/proj/dagcore",
    "default",
    "中",
    "中",
    3,
    3,
    6,
    "已完成",
    None,
    "node A",
    "",
    "2026-01-01T00:00:00Z",
    "2026-01-01T00:00:01Z",
    Some("human_steward"),
    "deferred",
    [],
    false,
  )
  ignore(e.store.update_task(a_done))
  assert_eq(e.parallelism(), 2) // B 和 C 解锁；D 仍被 B 挡住
}
