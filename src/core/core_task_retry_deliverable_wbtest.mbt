/// core_task_retry_deliverable_wbtest.mbt —— BUG-426 的成对锁：retry 必须清掉旧交付物。
///
/// 缺陷原形（运行期语义缺陷，单行正则查不出来）：
/// ```
/// execute(A) → submit → reject → retry → submit → verify
///                          ★deliverable 仍是 A   ★无门禁   ★验收的是 A
/// ```
/// 三处合起来构成：
///   1. `Task::reject`（:557）只改 status + 追加打回原因，**不动 deliverable**
///   2. `Task::retry`（:580）只把 Rejected→Executing，**同样不动 deliverable**
///   3. `FistEngine::submit`（engine.mbt:599）**没有 deliverable 新鲜度检查**
///
/// **决定性对照（证明这不是设计选择而是遗漏）**：同一条 `Rejected` 分支上，
/// 兄弟方法 `Task::reopen`（:549）**清了** `deliverable: ""` + `assignee: None`，
/// 而 `Task::retry` 两者都没清。
///
/// 危害链：`omega_strong.mbt:642` 用 `deliverable.trim() == ""` 判「尚无交付物」
/// ⇒ 旧废品被当成果复验，**判绿即真了账**；`board_ascii.mbt:252` 的假绿档系统性低估。
///
/// 本文件钉三件事：
///   ① `retry` 必须把 `deliverable` 清空（核心）
///   ② `retry` **保留 `assignee`**（防过度修复：retry 是同一人重做，不是回认领池）
///   ③ 与 `reopen` 的差异是有意的（reopen 清 assignee、retry 不清）

///|
/// 造一个「执行中 + 已写交付物」的任务（模拟 execute 之后）。
fn rt_executing_with_deliverable() -> Task {
  let t = Task::new(
    id="RT-1",
    project_dir=".",
    description="做一个东西",
    assignee="exec-1",
  )
  // 手工推进状态到 Executing（Task 的迁移方法要求前态合法，这里走最短路径）
  let t1 = match t.claim(assignee="exec-1") {
    Ok(x) => x
    Err(e) => abort("claim 失败：" + e)
  }
  let t2 = match t1.execute() {
    Ok(x) => x
    Err(e) => abort("execute 失败：" + e)
  }
  // 写一份"不合格的交付物 A"
  Task::with_deliverable(t2, "旧废品 A：不完整", "T1")
}

///|
/// 锁 1（**核心**）：`retry` 必须清空 `deliverable`
///
/// 若把 `deliverable: ""` 从 `retry` 里删掉（退回原实现），本格必红。
test "bug426_retry_clears_deliverable" {
  let t = rt_executing_with_deliverable()
  if t.deliverable == "" {
    fail("前置不成立：造出来的任务应带非空交付物")
  }
  // submit → reject → retry
  let submitted = match t.submit() {
    Ok(x) => x
    Err(e) => abort("submit 失败：" + e)
  }
  let rejected = match submitted.reject(reason="质量不过关") {
    Ok(x) => x
    Err(e) => abort("reject 失败：" + e)
  }
  // 打回时交付物**还没清**是正确的（要留证据说明被打回的是什么）
  if rejected.deliverable == "" {
    fail("reject 不该清交付物 —— 打回时要留证据")
  }
  let retried = match rejected.retry() {
    Ok(x) => x
    Err(e) => abort("retry 失败：" + e)
  }
  if retried.deliverable != "" {
    fail(
      "★BUG-426 未修：retry 后仍带着旧交付物 '" +
      retried.deliverable +
      "' ⇒ 会被当成本轮成果提交验收",
    )
  }
}

///|
/// 锁 2（防过度修复）：`retry` **必须保留 `assignee`**
///
/// `retry` 是「同一个人重做」，不是「回到可认领池」。
/// 若有人为了修 BUG-426 顺手把 assignee 也清了，本格必红。
test "bug426_retry_keeps_assignee" {
  let t = rt_executing_with_deliverable()
  let submitted = match t.submit() {
    Ok(x) => x
    Err(e) => abort("submit 失败：" + e)
  }
  let rejected = match submitted.reject() {
    Ok(x) => x
    Err(e) => abort("reject 失败：" + e)
  }
  let retried = match rejected.retry() {
    Ok(x) => x
    Err(e) => abort("retry 失败：" + e)
  }
  match retried.get_assignee() {
    None =>
      fail(
        "★过度修复：retry 不该清 assignee（那是 reopen 的语义）",
      )
    Some(a) =>
      if a != "exec-1" {
        fail("retry 应保留原 assignee=exec-1，实得 " + a)
      }
  }
}

///|
/// 锁 3（对照）：`reopen` 的语义与 `retry` **不同**，两者不可混
///
/// `reopen`：Rejected → Claimed，清 `deliverable` **且** 清 `assignee`（回认领池）
/// `retry` ：Rejected → Executing，清 `deliverable`、**保留** `assignee`（同一人重做）
///
/// 这一格钉住「两个方法的分工」，防未来有人把它们合并成一个。
test "bug426_reopen_vs_retry_semantics_differ" {
  let t = rt_executing_with_deliverable()
  let submitted = match t.submit() {
    Ok(x) => x
    Err(e) => abort("submit 失败：" + e)
  }
  let rejected = match submitted.reject() {
    Ok(x) => x
    Err(e) => abort("reject 失败：" + e)
  }
  // reopen：清交付物 + 清 assignee
  let reopened = match rejected.reopen() {
    Ok(x) => x
    Err(e) => abort("reopen 失败：" + e)
  }
  if reopened.deliverable != "" {
    fail("reopen 应当清交付物")
  }
  match reopened.get_assignee() {
    None => ()
    Some(a) => fail("reopen 应当清 assignee（回认领池），实得 " + a)
  }
}
