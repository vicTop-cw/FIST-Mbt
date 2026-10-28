///|
/// BUG-455 补测：`src/server` 里零覆盖工具的**行为断言**（第一批 4 格）。
///
/// 挑这 4 个的理由（其余 26 个的理由见 `reports/2026-10-27-bug455-coverage-report.md`）：
///   · `reserve_check`   —— 互斥面的**读侧**（写侧 `reserve_scope` 有锁，读侧零覆盖）
///   · `lock_release`    —— 并发锁的**释放**面（最容易被漏掉的一半）
///   · `store_close`     —— 多租户 ns 的**关闭**（数据面：关错了库就「消失」）
///   · `assistant_status`—— 助理选举读侧（写侧 `assistant_claim` 有锁）
///
/// ⚠️ 全部断言**行为的返回值**，不断言源码字符串。
/// 变异对照见 `b455_L5_*`。

///|
/// 造一个内存后端的引擎（不碰真实 sqlite 文件）。
fn b455_engine() -> @engine.FistEngine {
  @engine.FistEngine::new(store=@store.StoreBackend::memory())
}

///|
/// 【R1】`reserve_check` 读侧：写入什么就如实报出什么。
///
///   ① 没人预订 ⇒ `rsv_get` 返回 `None`
///   ② 写入后 ⇒ 返回 `(holder, ttl)`，**逐字等于写入值**
///   ③ 重复读 ⇒ 不变（读侧无副作用）
test "b455_reserve_check_reports_written_state" {
  let e = b455_engine()
  assert_eq(e.rsv_get("sc/a"), None)
  let _ = e.rsv_set(
    scope="sc/a",
    agent="owner-x",
    ttl_until="2099-01-01T00:00:00Z",
    created_at="2026-10-27T00:00:00Z",
  )
  match e.rsv_get("sc/a") {
    None => abort("B455-R1: 写入后 rsv_get 应返回 Some")
    Some((holder, ttl, _created)) => {
      assert_eq(holder, "owner-x")
      assert_eq(ttl, "2099-01-01T00:00:00Z")
    }
  }
  match e.rsv_get("sc/a") {
    None => abort("B455-R1: 第三次读应仍返回 Some")
    Some((holder2, _, _)) => assert_eq(holder2, "owner-x")
  }
}

///|
/// 【L1】`lock_release` 只释放**自己的**锁。
///
///   ① 他人尝试释放 ⇒ **false**，锁**仍在**（防「谁都能删别人的锁」）
///   ② 本人释放 ⇒ `true`，之后 `locks_get` 返回 None
test "b455_lock_release_only_owner_can_release" {
  let e = b455_engine()
  let lock = @store.FileLock::new(
    lock_id="lk-1",
    batch_id="b",
    scope="lk/s",
    agent="owner-y",
    status="active",
    ts="2026-10-27T00:00:00Z",
    ttl_until="2099-01-01T00:00:00Z",
    meta="",
  )
  let _ = e.locks_try_acquire(lock)
  assert_false(e.locks_release("lk/s", "attacker-z"))
  assert_true(e.locks_get("lk/s") is Some(_))
  assert_true(e.locks_release("lk/s", "owner-y"))
  // ⚠️ 实测发现：`locks_release` **不删行**，只把 status 改成 "released"
  // （`MemoryStore::locks_release` → `FileLock::{ ..l, status: "released" }`）
  // ⇒ 断言必须是「status 变了」，不是「行没了」。这条语义差异正是本测试的价值：
  //   若有人以为释放=删除，会写出基于「locks_get == None」的错误逻辑。
  match e.locks_get("lk/s") {
    None =>
      abort("B455-L1: 释放后行仍在（status=released），不该是 None")
    Some(l) => assert_eq(l.status_of(), "released")
  }
}

///|
/// 【L5 · 变异对照】`locks_release` 对「从没锁过的 scope」必须返回 **false**。
///
/// 若实现退化成「永远 true」（变异形状），本格先红 ⇒ 说明 L1 那条断言的判别力来源还在。
/// 实测（见报告 §证据）：把 `MemoryStore::locks_release` 改成恒 true ⇒ L1 + L5 双红。
test "b455_L5_release_has_a_real_negative_path" {
  let e = b455_engine()
  assert_false(e.locks_release("never/locked", "anyone"))
}

///|
/// 【S1】`store_close` 的边界：关没打开过的 ns 不崩，且**不影响别的 ns**。
///
/// 数据面（关错了库就「消失」）：
///   ① 关不存在的 ⇒ ns 列表长度不变
///   ② 关一个 ⇒ 只少那一个，**别的还留着**
test "b455_store_close_does_not_affect_others" {
  let ms = @store.MultiStore::new(data_dir="temp/b455-ns")
  let _ = ms.open(ns="ns-one", data_dir="temp/b455-ns")
  let _ = ms.open(ns="ns-two", data_dir="temp/b455-ns")
  let before = ms.ns_list()
  assert_true(before.contains("ns-one"))
  assert_true(before.contains("ns-two"))
  // ① 关不存在的 ⇒ 不崩、不变
  ms.close("ns-never-opened")
  assert_eq(ms.ns_list().length(), before.length())
  // ② 关一个 ⇒ 只少那一个
  ms.close("ns-one")
  let after = ms.ns_list()
  assert_false(after.contains("ns-one"))
  assert_true(after.contains("ns-two"))
}

///|
/// 【A1】`assistant_status` 读侧三态：空 ⇒ 登记 ⇒ 退位。
///
///   ① 空 ⇒ list 空 + active_primary = None
///   ② 登记一条 active primary ⇒ list 有 1 条 + primary 是它
///   ③ 改 status=resigned ⇒ **primary 变 None，但登记行还在**（退位不删行）
test "b455_assistant_status_three_phases" {
  let e = b455_engine()
  assert_eq(e.assistant_list().length(), 0)
  assert_eq(e.assistant_active_primary(), None)
  let reg = @store.AssistantReg::new(
    agent="asst-a",
    mode="all",
    is_primary=true,
    registered_at="2026-10-27T00:00:00Z",
    heartbeat_at="2026-10-27T00:00:00Z",
    status="active",
  )
  e.assistant_upsert(reg)
  assert_eq(e.assistant_list().length(), 1)
  match e.assistant_active_primary() {
    None => abort("B455-A1: 登记 active primary 后应能读到")
    Some(r) => assert_eq(r.agent, "asst-a")
  }
  // ③ 退位：primary 消失，登记行仍在
  assert_true(e.assistant_set_status("asst-a", "resigned"))
  assert_eq(e.assistant_active_primary(), None)
  assert_eq(e.assistant_list().length(), 1)
}
