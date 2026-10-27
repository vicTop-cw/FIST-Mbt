/// locks_upsert_equiv_test.mbt —— BUG-438 的成对锁：`locks_upsert` 在两后端**语义必须一致**。
///
/// **病灶**：同一个底层原语 `locks_upsert` 在两后端**行为相反**：
/// - 内存版（`store_rsv.mbt::MemoryStore::locks_upsert`）：**无条件** `file_locks.set(scope, lock)`
///   ⇒ 永远落库（last-write-wins），只在覆盖他人 live 锁时记一条 `lock_taken_over` 事后审计
/// - SQLite 版（`store_sqlite.mbt::SqliteStore::locks_upsert`）：`ON CONFLICT … DO UPDATE … WHERE …`
///   ⇒ **条件写**，条件不满足时**静默不写**
///
/// 而 `MemoryStore::locks_upsert` 的注释写明这是**底层原语、不是互斥门**：
/// 「它永远落库（last-write-wins）… 要『抢不到就拒』请用 `locks_try_acquire`」。
/// ⇒ **内存版是对的，SQLite 版的条件写是缺陷**（本文件的锁钉这件事）。
///
/// **为什么必须锁**：两后端行为相反时，调用方**无从区分**自己在哪个后端上 ——
/// 同一段业务代码在内存测试里过、在生产 SQLite 里静默失效（或反过来）。

///|
/// 造一把锁（`FileLock` 的字段都是包内私有，跨包只能用 `new`）。
fn _lk(scope : String, agent : String, ts : String) -> @store.FileLock {
  @store.FileLock::new(
    lock_id="L-" + scope,
    batch_id="B1",
    scope~,
    agent~,
    status="active",
    ts~,
    ttl_until="2099-01-01T00:00:00Z",
  )
}

///|
/// 锁 1：**覆盖他人 live 锁时，两后端都必须真的写进去**（last-write-wins）。
///
/// 修前 SQLite 版带 `WHERE file_locks.status != 'active' OR …` ⇒ 条件不满足 ⇒ **不写**
/// ⇒ `locks_get` 拿到的还是**旧 agent**；内存版则是新 agent ⇒ 两后端分叉。本格钉住「一致」。
test "bug438_upsert_overwrites_others_live_lock_on_both_backends" {
  // 内存后端
  let mem = @store.MemoryStore::new()
  ignore(mem.locks_upsert(_lk("S1", "A", "2026-01-01T00:00:00Z")))
  ignore(mem.locks_upsert(_lk("S1", "B", "2026-01-01T00:00:05Z")))
  let mem_owner = match mem.locks_get("S1") {
    Some(l) => l.agent_of()
    None => ""
  }
  assert_eq(mem_owner, "B") // 覆盖成功（last-write-wins）

  // SQLite 后端
  match @store.SqliteStore::open(":memory:") {
    None => fail("sqlite open 失败：本格没跑到被测面")
    Some(sql) => {
      ignore(sql.locks_upsert(_lk("S1", "A", "2026-01-01T00:00:00Z")))
      ignore(sql.locks_upsert(_lk("S1", "B", "2026-01-01T00:00:05Z")))
      let sql_owner = match sql.locks_get("S1") {
        Some(l) => l.agent_of()
        None => ""
      }
      // ★ 修复点：SQLite 也必须覆盖（修前这里是 "A" ⇒ 与本格断言不符 ⇒ 红）
      assert_eq(sql_owner, "B")
    }
  }
}

///|
/// 锁 2：**覆盖他人 live 锁必须留 `lock_taken_over` 审计**（两后端都要记）。
///
/// 防「拿掉 WHERE 顺手把审计也拿掉」：审查条件是「旧锁 active + 非本人 + 未过期」，
/// 两后端必须用同一条件。本格在 SQLite 侧断言违例数 ≥ 1、内存侧断言 ≥ 1。
test "bug438_upsert_records_lock_taken_over_on_both_backends" {
  // 内存后端
  let mem = @store.MemoryStore::new()
  ignore(mem.locks_upsert(_lk("S2", "A", "2026-01-01T00:00:00Z")))
  ignore(mem.locks_upsert(_lk("S2", "B", "2026-01-01T00:00:05Z")))
  assert_true(mem.lock_violations_list().length() >= 1)

  // SQLite 后端
  match @store.SqliteStore::open(":memory:") {
    None => fail("sqlite open 失败：本格没跑到被测面")
    Some(sql) => {
      ignore(sql.locks_upsert(_lk("S2", "A", "2026-01-01T00:00:00Z")))
      ignore(sql.locks_upsert(_lk("S2", "B", "2026-01-01T00:00:05Z")))
      assert_true(sql.lock_violations_list().length() >= 1)
    }
  }
}

///|
/// 锁 3：**同一 agent 覆盖自己的锁** ⇒ 不记审计（两后端一致）。
///
/// 防「审计条件写宽了」：本人续订自己的锁不是「夺锁」，不该留违例。
test "bug438_upsert_self_overwrite_records_no_violation" {
  let mem = @store.MemoryStore::new()
  ignore(mem.locks_upsert(_lk("S3", "A", "2026-01-01T00:00:00Z")))
  ignore(mem.locks_upsert(_lk("S3", "A", "2026-01-01T00:00:05Z")))
  assert_eq(mem.lock_violations_list().length(), 0)

  match @store.SqliteStore::open(":memory:") {
    None => fail("sqlite open 失败：本格没跑到被测面")
    Some(sql) => {
      ignore(sql.locks_upsert(_lk("S3", "A", "2026-01-01T00:00:00Z")))
      ignore(sql.locks_upsert(_lk("S3", "A", "2026-01-01T00:00:05Z")))
      assert_eq(sql.lock_violations_list().length(), 0)
    }
  }
}
