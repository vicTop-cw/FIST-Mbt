/// engine_leaf_rank_gate_wbtest.mbt —— BUG-451：`claim` 的 RANK_GATE 必须认叶子。
///
/// **病灶**（`engine.mbt` claim 的 Gate 1）：旧实现只读 `t.get_level()` 作准入档
/// （`let task_level = t.get_level()`），**未用 `t.is_leaf()`**。
/// 而 `task_plan_deep` 拆出的叶子 `level` 继承父链（`子任务 level = 父级 + 1`），
/// 深度 ≥2 的叶子 level 就是 2（师长档）⇒ 现网执行体 Executor(rank 5) / Leader(rank 4)
/// **永久无法认领任何深度≥2 的叶子**，只能 human_steward(rank 0) 代领
/// ⇒ **拆解失去意义**（这是本条的危害，不是"少一个便利"）。
///
/// **设计意图的真源**：`src/display/rank.mbt` 的 `leaf_label(_) = "士兵"`
/// ——「叶子原子任务固定为士兵（无论层级）」。引擎层不 import 展示层（依赖方向），
/// 故 `engine.mbt` 就地取满档 `leaf_claim_level() = 7`，语义对齐由本文件钉住。
///
/// **本文件四格**（对应派单硬要求 ③）：
///   锁 1：Executor(rank 5) **能**认领 level=2 的**叶子**（修复本体）
///   锁 2：Executor(rank 5) **不能**认领 level=2 的**非叶子**（零回归）
///   锁 3：HumanSteward(rank 0) 能认领任何任务（例外通吃，防"修过头成一刀切"）
///   锁 4：纯函数级——叶子准入档恒满档、非叶子保留原 level（不依赖端到端夹具）

///|
/// 锁 1（**修复本体**）：level=2 的**叶子**必须可被 Executor 认领。
///
/// 夹具：`Task::new(depth=1, level=2)` ⇒ `is_leaf() == true`。
/// 断言：`claim` 返回 **Ok**（不是 Err）。修复前这里必是 `RANK_GATE ... level=2`。
test "bug451_lock1_executor_can_claim_level2_leaf" {
  let e = FistEngine::new()
  let t = @core.Task::new(
    id="T-leaf-l2",
    project_dir="/proj/leaf",
    description="叶子任务（level=2）",
    depth=1,
    level=2,
    created_at="2026-10-27T00:00:00Z",
  )
  // 钉夹具本身：depth=1 ⇒ is_leaf 必须为 true，否则这格测的不是叶子
  if !t.is_leaf() {
    abort("夹具失效：depth=1 的 task 竟然不是叶子")
  }
  match e.store.create_task(t) {
    _ => ()
  }
  match
    e.claim(
      task_id="T-leaf-l2",
      assignee="exec-lane",
      now="2026-10-27T00:01:00Z",
    ) {
    Ok(tk) => assert_eq(tk.assignee, Some("exec-lane"))
    Err(m) =>
      abort(
        "★BUG-451 未修：Executor 仍无法认领 level=2 叶子（拆解失去意义）。实际: \{m}",
      )
  }
}

///|
/// 锁 2（**零回归**）：level=2 的**非叶子**仍然要 rank ≤ 2 才能领。
///
/// 夹具：`Task::new(depth=3, level=2)` ⇒ `is_leaf() == false`。
/// 断言：Executor(rank 5) 被拒，且文案含 `RANK_GATE` 与 `level=2`。
test "bug451_lock2_executor_still_cannot_claim_level2_nonleaf" {
  let e = FistEngine::new()
  let t = @core.Task::new(
    id="T-nonleaf-l2",
    project_dir="/proj/leaf",
    description="非叶子任务（level=2）",
    depth=3,
    level=2,
    created_at="2026-10-27T00:00:00Z",
  )
  if t.is_leaf() {
    abort("夹具失效：depth=3 的 task 竟然是叶子")
  }
  match e.store.create_task(t) {
    _ => ()
  }
  let msg = match
    e.claim(
      task_id="T-nonleaf-l2",
      assignee="exec-lane",
      now="2026-10-27T00:01:00Z",
    ) {
    Ok(_) => "<ok>"
    Err(m) => m
  }
  assert_true(msg.contains("RANK_GATE"))
  // 文案里的准入档必须是原 level（2），不能被叶子规则污染成 7
  assert_true(msg.contains("level=2"))
}

///|
/// 锁 3（**防修过头**）：HumanSteward(rank 0) 例外通吃 —— 叶子与非叶子都能领。
test "bug451_lock3_human_steward_can_claim_anything" {
  let e = FistEngine::new()
  let leaf = @core.Task::new(
    id="T-hs-leaf",
    project_dir="/proj/leaf",
    description="叶子",
    depth=1,
    level=0,
    created_at="2026-10-27T00:00:00Z",
  )
  let nonleaf = @core.Task::new(
    id="T-hs-nonleaf",
    project_dir="/proj/leaf",
    description="非叶子",
    depth=4,
    level=0,
    created_at="2026-10-27T00:00:00Z",
  )
  match e.store.create_task(leaf) {
    _ => ()
  }
  match e.store.create_task(nonleaf) {
    _ => ()
  }
  match
    e.claim(
      task_id="T-hs-leaf",
      assignee="human_steward",
      now="2026-10-27T00:01:00Z",
    ) {
    Ok(_) => ()
    Err(m) => abort("HumanSteward 应可领叶子，实际被拒: \{m}")
  }
  match
    e.claim(
      task_id="T-hs-nonleaf",
      assignee="human_steward",
      now="2026-10-27T00:01:00Z",
    ) {
    Ok(_) => ()
    Err(m) => abort("HumanSteward 应可领非叶子，实际被拒: \{m}")
  }
}

///|
/// 锁 4（⭐ **变异对照**）：纯函数级断言「叶子准入档 = 满档 7、非叶子 = 原 level」。
///
/// **为什么需要这一格**：锁 1 是端到端格，它红了只说明「领不到」，不说明**是哪一行**导致的。
/// 本格直接钉住 `leaf_claim_level()` 与 `rank_can_claim` 的组合语义：
///   · `rank_can_claim(5, leaf_claim_level())` 必须为 **true**（Executor 够格）
///   · `rank_can_claim(5, 2)` 必须为 **false**（非叶子 level=2 仍拒）
/// **变异实测**：把 `engine.mbt` 的 `if t.is_leaf() { leaf_claim_level() } else { task_level }`
/// 改回 `let tlevel = task_level` ⇒ 本格第一条断言必红（5 <= 7 会变 5 <= 2）。
test "bug451_lock4_leaf_claim_level_is_widest" {
  // 叶子满档：任何非 0 军衔都够格
  assert_eq(leaf_claim_level(), 7)
  assert_true(rank_can_claim(5, leaf_claim_level())) // Executor
  assert_true(rank_can_claim(4, leaf_claim_level())) // Leader
  assert_true(rank_can_claim(7, leaf_claim_level())) // 排长
  assert_true(rank_can_claim(0, leaf_claim_level())) // 司令
  // 非叶子保留原 level：Executor 对 level=2 必须拒
  assert_false(rank_can_claim(5, 2))
  assert_false(rank_can_claim(4, 2))
  // 边界：rank == level 恰好放行（`<=` 语义，防改成 `<`）
  assert_true(rank_can_claim(2, 2))
  // 司令例外对任意 level 成立
  assert_true(rank_can_claim(0, 0))
  assert_true(rank_can_claim(0, 2))
}
