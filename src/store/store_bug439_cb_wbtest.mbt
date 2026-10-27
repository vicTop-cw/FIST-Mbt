// ============================================================================
// BUG-439 熔断器内存后端的锁（Lane AV）
//
// 病灶：`StoreBackend::cb_get(Mem)` 恒 None、`cb_save(Mem)` 是 no-op
//   ⇒ 引擎侧 failures 永远读到 0，`nf = 0 + 1 = 1`，`1 >= threshold(3)` 永不成立
//   ⇒ **内存后端永不熔断**。
// 形态：**假绿** —— 工具不报错、回执字段齐全、保护从未生效。
//
// 本文件的锁钉三件事：
//   1. cb_save 后 cb_get 能读回（状态真的存下来了）
//   2. 三态判定的**输入**真的在累积（failures 会增长到 threshold）
//   3. 两后端 cb_get 读回**同形状**（逐字段同序，语义等价）
//
// ⚠️ 判例-30 防护：断言的是**运行时返回元组**，不是源码字符串。
// ============================================================================

///|
/// 【锁 1】内存后端 `cb_save` 后 `cb_get` 必须**读得回**（此前恒 None）。
///
/// 变异（把 `Mem(m) => m.circuit_breakers.set(...)` 改回 `Mem(_) => Ok(())`）⇒ 本格红。
test "bug439_mem_cb_save_then_get_roundtrip" {
  let b = StoreBackend::memory()
  // 存前：空
  assert_true(b.cb_get("ns1", "circ-a") is None)
  // 存
  match b.cb_save("ns1", "circ-a", "closed", 2, 60, 3, 30, 0, 1700000000, "2026-10-27T00:00:00Z") {
    Err(e) => abort("cb_save 应成功：" + e)
    Ok(_) => ()
  }
  // 读回：**必须不是 None**
  match b.cb_get("ns1", "circ-a") {
    None => abort("BUG-439 复发：内存后端 cb_get 仍是 None（cb_save 没真正写入）")
    Some(t) => {
      assert_eq(t.0, "closed")  // state
      assert_eq(t.1, 2)         // failures
      assert_eq(t.2, 60)        // window_secs
      assert_eq(t.3, 3)         // threshold
      assert_eq(t.4, 30)        // recovery_secs
      assert_eq(t.5, 0)         // opened_at
      assert_eq(t.6, 1700000000) // last_fail_ts
    }
  }
}

///|
/// 【锁 2】failures **真的会累积到 threshold**（保护生效的前提）。
///
/// 这是「保护真的生效了」的最小证据链：
///   cb_get → None ⇒ failures=0 ⇒ nf=1 ⇒ save(failures=1)
///   cb_get → failures=1 ⇒ nf=2 ⇒ save(failures=2)
///   cb_get → failures=2 ⇒ nf=3 ⇒ 3 >= threshold(3) ⇒ **应当熔断**
/// 修前：每轮 cb_get 都返回 None ⇒ failures 恒 0 ⇒ 到不了 3 ⇒ 永不熔断。
test "bug439_mem_cb_failures_accumulate_to_threshold" {
  let b = StoreBackend::memory()
  let threshold : Int32 = 3
  let mut failures : Int32 = 0
  let mut rounds = 0
  // 模拟引擎侧的三轮失败累积（与 circuit_fail 的内部算法同构）
  while rounds < 3 {
    let cur = match b.cb_get("ns2", "circ-b") {
      None => 0
      Some(t) => t.1
    }
    failures = cur + 1
    ignore(
      b.cb_save("ns2", "circ-b", "closed", failures, 60, threshold, 30, 0, 1700000000 + rounds, "t"),
    )
    rounds = rounds + 1
  }
  // ★ 三轮后 failures 必须真的到 3（修前恒为 1）
  assert_eq(failures, 3)
  // 且从这个状态出发，`failures >= threshold` 成立 ⇒ 门可以熔断
  assert_true(failures >= threshold)
  let stored = match b.cb_get("ns2", "circ-b") {
    None => abort("BUG-439 复发：累积后仍读不回")
    Some(t) => t.1
  }
  assert_eq(stored, 3)
}

///|
/// 【锁 3】内存后端与 SQLite 后端 `cb_get` 读回**逐字段同形状**。
///
/// 「同形状」= 元组 7 位、每一位语义一致（state/failures/window/threshold/recovery/opened_at/last_fail_ts）。
/// 注意：`updated_at` 不参与（内存版无该字段，且它不进三态判定）。
test "bug439_mem_and_sql_cb_get_same_shape" {
  let mem = StoreBackend::memory()
  let sql = match SqliteStore::open(":memory:") {
    Some(s) => StoreBackend::sqlite(s)
    None => abort("sqlite open 失败：本格没跑到被测面")
  }
  let args : (String, Int32, Int32, Int32, Int32, Int32) = ("open", 5, 60, 3, 30, 1700000123)
  let (st, fa, wi, th, re, la) = args
  ignore(mem.cb_save("ns3", "circ-c", st, fa, wi, th, re, 1700000000, la, "t"))
  ignore(sql.cb_save("ns3", "circ-c", st, fa, wi, th, re, 1700000000, la, "t"))
  let m = match mem.cb_get("ns3", "circ-c") {
    None => abort("内存后端读不回")
    Some(t) => t
  }
  let s = match sql.cb_get("ns3", "circ-c") {
    None => abort("SQLite 后端读不回")
    Some(t) => t
  }
  assert_eq(m, s)   // 七元组逐字段相等
}

///|
/// 【锁 4】不同 (ns, circuit) **不串味**（复合键正确性）。
///
/// 若 key 拼错（如用 `:` 分隔而与名字里的 `:` 碰撞），两条记录会互相覆盖。
test "bug439_mem_cb_keys_are_isolated" {
  let b = StoreBackend::memory()
  ignore(b.cb_save("a:b", "c", "open", 7, 60, 3, 30, 0, 1, "t"))
  ignore(b.cb_save("a", "b:c", "closed", 0, 60, 3, 30, 0, 2, "t"))
  let x = match b.cb_get("a:b", "c") {
    None => abort("a:b / c 读不回")
    Some(t) => t
  }
  let y = match b.cb_get("a", "b:c") {
    None => abort("a / b:c 读不回")
    Some(t) => t
  }
  assert_eq(x.0, "open")
  assert_eq(x.1, 7)
  assert_eq(y.0, "closed")
  assert_eq(y.1, 0)
}
