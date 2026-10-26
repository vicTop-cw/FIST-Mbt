/// lock_legacy_grant_wbtest.mbt —— BUG-429 的成对锁：legacy_grant 不许在 granted=false 时打标。
///
/// 缺陷原形（统帅自己写的，Lane AD 审出来的）：
/// ```moonbit
/// o.relabel("renewed_legacy_grant", o.granted)   // ← 无条件标
/// ```
/// `locks_get`（:202）与 `locks_try_acquire`（:205）是**两次独立 IO** ——
/// 中间别的 agent 可以抢到同一把锁且 ttl 新鲜 ⇒ 本次写被后端拒 ⇒ `granted=false`。
///
/// 此时若无条件标 `renewed_legacy_grant`，回执就是
/// **`granted=false` + `action="renewed_legacy_grant"` + `agent=别人`** —— **三个字段互相矛盾**。
///
/// 同文件 `Unregistered` 分支写对了 `if o.granted`，**legacy 分支漏抄**。
///
/// ## 为什么本文件只有一格行为锁
///
/// 完整场景要求「两次 IO 之间被别人抢锁」，**单线程测试构造不出来**
/// （判例-31 明令不许用 `sleep` 抢时序）。
/// 所以：
///   · 锁 1 = **行为锁**：能构造的那一半（自己续自己 ⇒ granted=true ⇒ 必须标 legacy）
///   · 锁 2 = **接线格**：断言 `if o.granted` 那道闸真在源码里（这格脆弱，但比不锁好）
///
/// **⚠️ 锁 2 的诚实标注**：它是源码文本断言，实现重构会误判成断裂（本仓已踩过 3 次）。
/// 之所以仍然留它：`granted=false` 那一半**没有任何行为面能覆盖**，
/// 只能靠「代码里有这道闸」+ 人工复核。若将来有办法造并发，应把它换成行为锁。

///|
/// 锁 1（行为）：自己续自己的 active 锁 ⇒ `granted=true` 且 `action="renewed_legacy_grant"`
///
/// 这是 legacy_grant 的**正例**：权限门是 RoleDenied，但锁本来就是自己的、还活着。
test "legacy_grant_wb1_own_active_lock_renews" {
  let e = FistEngine::new()
  // 用 locks_upsert 直接造一把「自己持有的 active 锁」——
  // 它是零调用的底层原语（BUG-424 已确认为裸通道），这里正好用它造前置现场。
  let lock = @store.FileLock::new(
    lock_id="LG-1",
    batch_id="LG-B1",
    scope="src/engine/engine.mbt",
    agent="exec-legacy",
    status="active",
    ts="T1",
    ttl_until="T9",
    meta="",
  )
  e.locks_upsert(lock)
  // 同一 agent 再抢一次（=续期）⇒ 走 legacy 分支（Executor 对 src/engine/ 是 RoleDenied）
  let renewal = @store.FileLock::new(
    lock_id="LG-1",
    batch_id="LG-B1",
    scope="src/engine/engine.mbt",
    agent="exec-legacy",
    status="active",
    ts="T2",
    ttl_until="T99",
    meta="",
  )
  let o = e.locks_try_acquire(renewal)
  if not(o.granted) {
    fail("前置不成立：自己续自己的 active 锁应 granted=true")
  }
  if o.action != "renewed_legacy_grant" {
    fail(
      "legacy_grant 正例没打标：action=" + o.action + "（期望 renewed_legacy_grant）",
    )
  }
}

///|
/// 锁 2（接线格）：`granted=false` 那道闸真在源码里
///
/// **⚠️ 这格是源码文本断言，脆弱**（见文件头说明）。
/// 它守的是 BUG-429 的那一半：`granted=false` 时**不许**标 legacy。
test "legacy_grant_wb2_granted_guard_wired" {
  let src = @fs.read_file_to_string(
    "src/engine/engine_rsv.mbt",
    encoding="utf8",
  ) catch {
    _ => abort("读 src/engine/engine_rsv.mbt 失败：接线格没跑到被测面")
  }
  // 必须同时存在：`if o.granted {` 与 legacy 标签。两者都有才说明闸没被摘掉。
  assert_true(src.contains("if o.granted {"))
  assert_true(src.contains("renewed_legacy_grant"))
  // 反向：不许再出现「无条件 relabel(..., o.granted)」那个坏形状
  if src.contains("o.relabel(\"renewed_legacy_grant\", o.granted)") {
    fail("BUG-429 回退：又出现无条件 relabel(..., o.granted)")
  }
}

///|
/// 锁 3（反例）：别人持有的 active 锁 ⇒ 硬拒（不许借用 legacy 通道）
test "legacy_grant_wb3_others_lock_denied" {
  let e = FistEngine::new()
  let lock = @store.FileLock::new(
    lock_id="LG-2",
    batch_id="LG-B2",
    scope="src/engine/engine.mbt",
    agent="someone-else",
    status="active",
    ts="T1",
    ttl_until="T9",
    meta="",
  )
  e.locks_upsert(lock)
  // Executor 想抢别人持有的 src/engine 锁 ⇒ RoleDenied 且 existing.agent != 自己 ⇒ 硬拒
  let attempt = @store.FileLock::new(
    lock_id="LG-2",
    batch_id="LG-B2",
    scope="src/engine/engine.mbt",
    agent="exec-thief",
    status="active",
    ts="T2",
    ttl_until="T99",
    meta="",
  )
  let o = e.locks_try_acquire(attempt)
  if o.granted {
    fail("★越权：Executor 拿到了别人持有的 src/engine 锁")
  }
  if o.action == "renewed_legacy_grant" {
    fail("★legacy 通道被滥用：不是自己的锁却标了 renewed_legacy_grant")
  }
}
