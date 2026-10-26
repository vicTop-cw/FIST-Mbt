/// lock_perm_wbtest.mbt —— BUG-424 锁权限门 · 4 格成对锁（engine 层接线）。
///
/// **为什么必须有 engine 层锁**：`engine_scope_perm_role_wbtest.mbt` 锁的是
/// `check_scope_permission` 这个**纯函数**；而「判定有没有真的接进 `locks_try_acquire`」
/// 在 `engine_rsv.mbt` 里 —— 纯函数全绿 + 接线被删掉也能过（判例-29：机制格 ≠ 实现路径格）。
/// 本文件全部走 `FistEngine::locks_try_acquire` **真实调用路径**。
///
/// **修法背景**：`engine_rsv.mbt` 的原注释（2026-10-22，挂了 4 天）称「锁的权限门禁暂时没接
/// —— LockAcquireOutcome 是 read-only 类型」。实测该说法不成立：字段只是**包内私有**
/// （跨包写 literal 被拒，与 read-only 无关），而 BUG-413 早用 `RsvOutcome::relabel`
/// 解决过同一障碍 ⇒ 本笔补 `LockAcquireOutcome::denied_by_permission()` +
/// `FileLock::agent_of()` / `scope_of()` 两个读访问器后接门。

///|
/// 造一把锁（字段都是 `@store.FileLock` 的包内私有项，跨包只能用它的 `new`）。
fn lock_of(scope : String, agent : String) -> @store.FileLock {
  @store.FileLock::new(
    lock_id="L1",
    batch_id="B1",
    scope~,
    agent~,
    ttl_until="2026-10-28T00:00:00+08:00",
    ts="2026-10-27T00:00:00+08:00",
  )
}

///|
/// 锁 1：Executor 抢 `src/engine/`（Leader 级保护面）⇒ **被硬拒**。
///
/// 这是 BUG-424 的正面格：接门前 `locks_try_acquire` 直接透传 store，
/// 任何名字都能拿到 `src/engine/` 的锁 ⇒ 本格必红。
test "lock_perm_wb1_executor_denied_on_engine" {
  let e = FistEngine::new()
  let o = e.locks_try_acquire(lock_of("src/engine/x.mbt", "exec-1"))
  assert_false(o.granted)
  assert_eq(o.action, "permission_denied")
}

///|
/// 锁 2：Leader 抢同一 scope ⇒ **拿到**（防修过头 —— 门不能把合法军官也挡了）。
///
/// 用整名 `"leader"` 而不是 `"lead-1"`：BUG-418 把子串匹配收窄为整名精确匹配后，
/// `lead-1` 已含子串失效（塌回 Executor）；`"leader"` 整名仍是 Leader（BUG-421 那条
/// 「整名单词仍买军官面」的政策状态）。⇒ **本格同时是 BUG-421 的现状锚点**：
/// 若哪天 BUG-421 落地（删掉整名 leader 白名单），本格会红，应同步改成
/// 「登记 `agents.role=Leader` 的 agent」。
test "lock_perm_wb2_leader_allowed_on_engine" {
  let e = FistEngine::new()
  let o = e.locks_try_acquire(lock_of("src/engine/x.mbt", "leader"))
  assert_true(o.granted)
}

///|
/// 锁 3：Executor 抢 `scripts/` ⇒ **拿到**（本该对 Executor 开放，防门做成「一律拒」）。
test "lock_perm_wb3_executor_allowed_on_scripts" {
  let e = FistEngine::new()
  let o = e.locks_try_acquire(lock_of("scripts/x.py", "exec-1"))
  assert_true(o.granted)
}

///|
/// 锁 4：**Unregistered 走 advisory** —— 未登记规则的 scope 放行，但标签能区分。
///
/// 与 BUG-413 的三态语义一致：`Unregistered` 是 advisory（不参与授权裁决），
/// 不是拒绝。本格防「把未登记也当成拒绝」的修过头。
test "lock_perm_wb4_unregistered_is_advisory" {
  let e = FistEngine::new()
  let o = e.locks_try_acquire(lock_of("reports/x.md", "exec-1"))
  assert_true(o.granted)
  assert_eq(o.action, "unregistered")
}
