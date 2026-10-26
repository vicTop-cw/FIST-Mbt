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
/// 锁 2（**BUG-421 落地后的改判**）：整名 `"leader"` 抢 `src/engine/` ⇒ **被硬拒**。
///
/// **改判记录**：本格原先钉的是相反的事 —— `"leader"` 能拿到锁（当时 `infer_role_from_agent`
/// 的整名白名单还留着一档，本格被写成「BUG-421 的现状锚点」）。BUG-421 把白名单删掉后，
/// 本格如约变红，按当时的注释改成现在的语义（**军官只来自 `agents.role` 登记**）。
///
/// 内存后端 `agents` 表恒空 ⇒ 只剩推断这一层 ⇒ 覆盖「名字即身份」这条攻击面。
test "lock_perm_wb2_leader_name_denied_on_engine" {
  let e = FistEngine::new()
  let o = e.locks_try_acquire(lock_of("src/engine/x.mbt", "leader"))
  assert_false(o.granted)
  assert_eq(o.action, "permission_denied")
}

///|
/// 锁 2b（防修过头 · **正例**）：**登记 `agents.role=Leader` 的 agent** 才拿得到军官面。
///
/// 这一格是 BUG-421 关闭「自报名字」通道后**唯一**的合法路径：
/// 身份必须在 `agents` 表被显式登记（当前唯一写入面是 server 内部，
/// 没有面向 agent 的自助登记工具 —— 这是 BUG-421 的既定代价，见账本该条「风险」段）。
///
/// 注意 `agent_type` 必须**不是** `"server"`：`"server"` 是「本进程自身份」，
/// BUG-422 把这类记录整条剔出角色裁决 —— 用 `"server"` 登记的话本格会（正确地）红。
test "lock_perm_wb2b_registered_leader_allowed_on_engine" {
  let db = "temp/lock_perm_registered_leader_wb.db"
  let e = match FistEngine::open_sqlite(db) {
    None => abort("open_sqlite 失败：" + db)
    Some(x) => x
  }
  let lane = "lock-perm-leader-lane"
  match
    e.agents_register(
      agent_id=agent_fp_of(lane),
      agent_type="executor",
      role="Leader",
      soldier="工兵",
      pubkey_fp="",
      pid=7,
      now="2026-10-27T00:00:00Z",
    ) {
    Err(msg) => abort("agents_register 失败：" + msg)
    Ok(_) => ()
  }
  let o = e.locks_try_acquire(lock_of("src/engine/x.mbt", lane))
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
