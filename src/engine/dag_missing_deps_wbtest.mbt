///|
/// ══════════════════════════════════════════════════════════════════════════
/// BUG-460 白盒锁：`deps_report` 的依赖三态 + 与 `deps_satisfied` 的零回归契约
///
/// 缺陷：`deps_satisfied` 对「依赖存在但未完成」与「依赖 id 不存在」**都**返回 `false`
/// ⇒ 上游分不清「等一个会完成的前置」与「等一个永远不存在的前置」，
/// 后者会把任务**永久卡死而看板看不出异常**。
///
/// 本文件只锁**新增加法式** API，不改 `deps_satisfied` 的任何既有断言
/// （它在 `src/engine/dag_core_wbtest.mbt:158/231` 的 5 个出口锁保持原样）。
///
/// 夹具（`dm460_setup`）：
/// ```
/// A        (无依赖)                 ← 基准：直接 satisfied
/// B        ← [A]                    ← A 未完成时 pending
/// ORPHAN   ← [GHOST]                ← GHOST 库里不存在 ⇒ missing
/// MIXED    ← [A, GHOST]             ← 混合：missing 优先，但 pending 也点名
/// DUP      ← [A, A, GHOST, GHOST]   ← 重复 id 只点一次名
/// ```
/// ══════════════════════════════════════════════════════════════════════════

///|
/// 建一个任务（依赖列表显式给）。
fn dm460_mk(e : FistEngine, id : String, deps : Array[String]) -> Unit {
  ignore(
    e.store.create_task(
      @core.Task::new(
        id~,
        project_dir="/proj/dm460",
        description="node " + id,
        created_at="2026-01-01T00:00:00Z",
        depends_on=deps,
      ),
    ),
  )
}

///|
/// 把任务标成「已完成」（`Task` 不可变，只能整条 `from_db` 换一条）。
fn dm460_complete(e : FistEngine, id : String) -> Unit {
  match e.store.get_task(id) {
    Some(t) =>
      ignore(
        e.store.update_task(
          @core.Task::from_db(
            t.id,
            t.parent_id,
            t.project_dir,
            t.ns,
            t.priority,
            t.importance,
            t.depth,
            t.split_n,
            t.level,
            "已完成",
            t.assignee,
            t.description,
            t.deliverable,
            t.created_at,
            "2026-01-01T00:00:01Z",
            Some("human_steward"),
            t.cleanup_mode,
            t.depends_on,
            false,
          ),
        ),
      )
    None => abort("夹具损坏：任务 " + id + " 不存在")
  }
}

///|
fn dm460_setup() -> FistEngine {
  let e = FistEngine::new()
  dm460_mk(e, "A", [])
  dm460_mk(e, "B", ["A"])
  dm460_mk(e, "ORPHAN", ["GHOST"])
  dm460_mk(e, "MIXED", ["A", "GHOST"])
  dm460_mk(e, "DUP", ["A", "A", "GHOST", "GHOST"])
  e
}

///|
/// 锁 1：**全满足** ⇒ `DepsSatisfied`，两个点名列表都空。
///
/// 两段都钉：①无依赖的任务（A）本身就是 satisfied；②依赖全完成后（B ← A，A 已完成）
/// 也转成 satisfied —— 防实现只判"有没有 depends_on"。
test "dm460_all_satisfied_is_satisfied" {
  let e = dm460_setup()
  let a = e.deps_report("A")
  assert_eq(a.state, DepsSatisfied)
  assert_true(a.is_satisfied())
  assert_eq(a.missing_deps.length(), 0)
  assert_eq(a.pending_deps.length(), 0)
  // B 的依赖 A 完成后 ⇒ 全满足
  dm460_complete(e, "A")
  let b = e.deps_report("B")
  assert_eq(b.state, DepsSatisfied)
  assert_true(b.is_satisfied())
  assert_eq(b.state.to_string(), "satisfied")
}

///|
/// 锁 2：**依赖存在但未完成** ⇒ `DepsPending`，且 `pending_deps` 点名 A、`missing_deps` 空。
///
/// 这一格与锁 3 成对：只把「有依赖 ⇒ false」翻成枚举而不区分 pending/missing 的实现，
/// 会在锁 2 与锁 3 之间**必红一格**。
test "dm460_pending_dep_is_pending" {
  let e = dm460_setup()
  let r = e.deps_report("B") // B ← A，A 仍 pending
  assert_eq(r.state, DepsPending)
  assert_false(r.is_satisfied())
  assert_eq(r.pending_deps.length(), 1)
  assert_eq(r.pending_deps[0], "A")
  assert_eq(r.missing_deps.length(), 0)
  assert_eq(r.state.to_string(), "pending")
}

///|
/// 锁 3：**依赖 id 不存在** ⇒ `DepsMissing`，且 `missing_deps` 点名那个幽灵 id。
///
/// 这是 BUG-460 的病灶格：把 `None` 分支写成 `pending.push`（"反正是没完成"）本格必红。
test "dm460_missing_dep_is_missing_and_named" {
  let e = dm460_setup()
  let r = e.deps_report("ORPHAN") // ORPHAN ← GHOST（库里没有）
  assert_eq(r.state, DepsMissing)
  assert_false(r.is_satisfied())
  assert_eq(r.missing_deps.length(), 1)
  assert_eq(r.missing_deps[0], "GHOST")
  assert_eq(r.pending_deps.length(), 0)
  assert_eq(r.state.to_string(), "missing")
}

///|
/// 锁 4：**任务自身不存在** ⇒ `DepsNoTask`（显式第四态），不是 `DepsMissing`、更不是 satisfied。
///
/// 裁定见 `deps_report` 文档注释①：`DepsMissing` 的语义是"依赖里有幽灵"，
/// 而此刻连依赖表本身都没有；混成一档会让调用方把"task_id 打错了"读成"某个上游被删了"。
/// 选显式枚举而非 `Err`：同包风格无错误通道，且模式匹配穷尽 ⇒ 漏处理编译期就报错。
/// 同格钉住与旧 API 的**一致性**：`deps_satisfied` 对它仍必须是 `false`（零回归）。
test "dm460_self_missing_is_no_task" {
  let e = dm460_setup()
  let r = e.deps_report("NO_SUCH_TASK")
  assert_eq(r.state, DepsNoTask)
  assert_false(r.is_satisfied())
  assert_eq(r.missing_deps.length(), 0)
  assert_eq(r.pending_deps.length(), 0)
  assert_eq(r.state.to_string(), "no_task")
  // 旧 API 语义不动：任务不存在仍 false
  assert_false(e.deps_satisfied("NO_SUCH_TASK"))
}

///|
/// 锁 5：**混合**（同时有 pending 与 missing）⇒ 结论 `DepsMissing`（missing 优先），
/// 但 `pending_deps` 也照实点名 —— 优先级只决定"结论态"，不吃掉信息。
///
/// 裁定见 `deps_report` 文档注释②：pending 会随时间自愈，missing 不会，
/// 所以"整体不可执行的原因"归档为 missing；而两个列表都填，
/// 保证"除了配置错之外还差 A"这种信息不被优先级丢掉。
test "dm460_mixed_missing_wins_but_both_named" {
  let e = dm460_setup()
  let r = e.deps_report("MIXED") // MIXED ← [A(pending), GHOST(missing)]
  assert_eq(r.state, DepsMissing)
  assert_eq(r.missing_deps.length(), 1)
  assert_eq(r.missing_deps[0], "GHOST")
  assert_eq(r.pending_deps.length(), 1)
  assert_eq(r.pending_deps[0], "A")
  // 依赖列表原序保真：MIXED 的 depends_on 是 [A, GHOST]，pending/missing 各取自己那一支
  // 把 A 补完成后：missing 仍在 ⇒ 结论不变，但 pending 清空（证明两个列表独立计算，不是复读结论）
  dm460_complete(e, "A")
  let r2 = e.deps_report("MIXED")
  assert_eq(r2.state, DepsMissing)
  assert_eq(r2.missing_deps.length(), 1)
  assert_eq(r2.pending_deps.length(), 0)
}

///|
/// 锁 6：`depends_on` 里**同一个 id 重复出现**时，点名列表去重（按原序只出现一次）。
///
/// 不去重的话，"缺 1 个"会被报成"缺 2 个"，看板上的风险等级直接翻倍。
test "dm460_duplicate_dep_ids_named_once" {
  let e = dm460_setup()
  let r = e.deps_report("DUP") // DUP ← [A, A, GHOST, GHOST]
  assert_eq(r.state, DepsMissing)
  assert_eq(r.missing_deps.length(), 1)
  assert_eq(r.missing_deps[0], "GHOST")
  assert_eq(r.pending_deps.length(), 1)
  assert_eq(r.pending_deps[0], "A")
}

///|
/// 锁 7：**与 `deps_satisfied` 的零回归契约** —— `is_satisfied() == deps_satisfied()` 恒成立。
///
/// 这是加法式改造最该钉的不变量：新 API 一旦与旧 API 反向
/// （比如把 missing 当成 satisfied 放过，或把 pending 报成 satisfied），
/// 上游同时用两者的调用方就会得到互相打脸的答案。旧 API 的**结果**一个都不许变。
test "dm460_parity_with_deps_satisfied" {
  let e = dm460_setup()
  let ids : Array[String] = ["A", "B", "ORPHAN", "MIXED", "DUP", "NO_SUCH_TASK"]
  for id in ids {
    assert_eq(e.deps_report(id).is_satisfied(), e.deps_satisfied(id))
  }
  // 状态变化后仍然一致（B 由 pending 转 satisfied；MIXED 因 GHOST 仍 false）
  dm460_complete(e, "A")
  for id in ids {
    assert_eq(e.deps_report(id).is_satisfied(), e.deps_satisfied(id))
  }
  assert_true(e.deps_report("B").is_satisfied())
  assert_false(e.deps_report("MIXED").is_satisfied())
}

///|
/// 锁 8：**变异对照锁**（判例-29/30）—— 把 `deps_report` 里缺失分支的
/// `None => missing.push(tid)` 改成 `None => pending.push(tid)`（"反正是没完成"），
/// 本格必须红。
///
/// 三条断言分别盯住变异的三个后果：①结论态从 missing 变 pending；
/// ②`missing_deps` 少一条；③`pending_deps` 多出一条。
/// **改坏的是代码不是注释**：变异点落在 `deps_report` 的 `match self.store.get_task(tid)`
/// 分支体（engine.mbt），不是本文件里的任何字面量 —— 因此本格不会因"模式串还在文件里"而假绿。
test "dm460_mutation_missing_as_pending_must_go_red" {
  let e = dm460_setup()
  let r = e.deps_report("ORPHAN") // 纯 missing，不含任何 pending 成分
  assert_eq(r.state, DepsMissing) // 变异后：DepsPending ⇒ 红
  assert_false(r.state == DepsPending) // 同一条的显式反断言（读错断言消息时不至于含混）
  assert_eq(r.missing_deps.length(), 1) // 变异后：0 ⇒ 红
  assert_eq(r.pending_deps.length(), 0) // 变异后：1 ⇒ 红
}
