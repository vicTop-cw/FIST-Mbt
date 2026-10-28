// 项目助理登记（assistant）双后端测试（multi-agent-lock v3 阶段2 精简版）。

///|
test "assistant_claim_action 裁决矩阵：elected/renewed/taken_over/conflict" {
  // 无现任 → elected
  let (ok1, a1, p1) = @store.assistant_claim_action(
    None,
    "asst_a",
    "2026-10-12T10:00:00Z",
    "2026-10-12T09:55:00Z",
  )
  assert_true(ok1)
  assert_eq(a1, "elected")
  assert_eq(p1, "")
  // 本人续任 → renewed
  let prev = @store.AssistantReg::new(
    agent="asst_a",
    mode="all",
    is_primary=true,
    registered_at="2026-10-12T09:00:00Z",
    heartbeat_at="2026-10-12T09:59:00Z",
    status="active",
  )
  let (ok2, a2, _) = @store.assistant_claim_action(
    Some(prev),
    "asst_a",
    "2026-10-12T10:00:00Z",
    "2026-10-12T09:55:00Z",
  )
  assert_true(ok2)
  assert_eq(a2, "renewed")
  // 现任心跳新鲜 → conflict
  let (ok3, a3, p3) = @store.assistant_claim_action(
    Some(prev),
    "asst_b",
    "2026-10-12T10:00:00Z",
    "2026-10-12T09:55:00Z",
  )
  assert_false(ok3)
  assert_eq(a3, "conflict")
  assert_eq(p3, "asst_a")
  // 现任心跳陈旧 → taken_over（记旧主）
  let (ok4, a4, p4) = @store.assistant_claim_action(
    Some(prev),
    "asst_b",
    "2026-10-12T10:00:00Z",
    "2026-10-12T09:59:30Z",
  )
  assert_true(ok4)
  assert_eq(a4, "taken_over")
  assert_eq(p4, "asst_a")
}

///|
test "assistant 双后端同构：claim → heartbeat → resign → sweep 标 dead" {
  let mem = @store.StoreBackend::memory()
  // —— 内存后端 ——
  // 空闲：无 active 主
  assert_eq(mem.assistant_list().length(), 0)
  // 当选
  mem.assistant_upsert(
    @store.AssistantReg::new(
      agent="asst_a",
      mode="all",
      is_primary=true,
      registered_at="2026-10-12T10:00:00Z",
      heartbeat_at="2026-10-12T10:00:00Z",
      status="active",
    ),
  )
  match mem.assistant_get("asst_a") {
    Some(r) => {
      assert_eq(r.agent, "asst_a")
      assert_true(r.is_primary)
    }
    None => abort("asst_a 应已登记")
  }
  // 心跳刷新
  mem.assistant_upsert(
    @store.AssistantReg::new(
      agent="asst_a",
      mode="all",
      is_primary=true,
      registered_at="2026-10-12T10:00:00Z",
      heartbeat_at="2026-10-12T10:01:00Z",
      status="active",
    ),
  )
  match mem.assistant_get("asst_a") {
    Some(r) => assert_eq(r.heartbeat_at, "2026-10-12T10:01:00Z")
    None => abort("asst_a 应已登记")
  }
  // 不存在者退位失败
  assert_false(mem.assistant_set_status("asst_nope", "resigned"))
  // 退位成功
  assert_true(mem.assistant_set_status("asst_a", "resigned"))
  match mem.assistant_get("asst_a") {
    Some(r) => assert_eq(r.status, "resigned")
    None => abort("asst_a 应仍登记（resigned）")
  }
  // 心跳陈旧者标 dead
  mem.assistant_upsert(
    @store.AssistantReg::new(
      agent="asst_stale",
      mode="all",
      is_primary=true,
      registered_at="2026-10-12T09:00:00Z",
      heartbeat_at="2026-10-12T09:00:00Z",
      status="active",
    ),
  )
  assert_true(mem.assistant_set_status("asst_stale", "dead"))
  match mem.assistant_get("asst_stale") {
    Some(r) => assert_eq(r.status, "dead")
    None => abort("asst_stale 应仍登记（dead）")
  }
  // —— SQLite 后端（同构） ——
  let db = bug462_unique_db("assistant_store_test")
  match @store.SqliteStore::open(db) {
    None => abort("sqlite open failed: \{db}")
    Some(s) => {
      let b = @store.StoreBackend::sqlite(s)
      ignore(b.clear()) // 先清旧，防持久化 DB 跨次残留（对照 executor_store_test 先清旧模式）
      assert_eq(b.assistant_list().length(), 0)
      b.assistant_upsert(
        @store.AssistantReg::new(
          agent="asst_a",
          mode="all",
          is_primary=true,
          registered_at="2026-10-12T10:00:00Z",
          heartbeat_at="2026-10-12T10:01:00Z",
          status="active",
        ),
      )
      match b.assistant_get("asst_a") {
        Some(r) => {
          assert_eq(r.heartbeat_at, "2026-10-12T10:01:00Z")
          assert_true(r.is_primary)
        }
        None => abort("sqlite: asst_a 应已登记")
      }
      assert_false(b.assistant_set_status("asst_nope", "resigned"))
      assert_true(b.assistant_set_status("asst_a", "resigned"))
      match b.assistant_get("asst_a") {
        Some(r) => assert_eq(r.status, "resigned")
        None => abort("sqlite: asst_a 应仍登记（resigned）")
      }
      b.assistant_upsert(
        @store.AssistantReg::new(
          agent="asst_stale",
          mode="all",
          is_primary=true,
          registered_at="2026-10-12T09:00:00Z",
          heartbeat_at="2026-10-12T09:00:00Z",
          status="active",
        ),
      )
      assert_true(b.assistant_set_status("asst_stale", "dead"))
      match b.assistant_get("asst_stale") {
        Some(r) => assert_eq(r.status, "dead")
        None => abort("sqlite: asst_stale 应仍登记（dead）")
      }
    }
  }
}

///|
test "assistant 双后端同构：违例落案底" {
  // —— 内存后端 ——
  let mem = @store.StoreBackend::memory()
  let before = mem.lock_violations_list().length()
  mem.lock_violations_push(
    @store.LockViolation::new(
      ts="2026-10-12T10:00:00Z",
      agent="asst_old",
      scope="assistant",
      reason="force_takeover",
      lock_id="asst_new",
    ),
  )
  let after = mem.lock_violations_list()
  assert_eq(after.length(), before + 1)
  assert_eq(after[after.length() - 1].reason, "force_takeover")
  assert_eq(after[after.length() - 1].agent, "asst_old")
  // —— SQLite 后端（同构） ——
  let db = bug462_unique_db("assistant_store_test")
  match @store.SqliteStore::open(db) {
    None => abort("sqlite open failed: \{db}")
    Some(s) => {
      let b = @store.StoreBackend::sqlite(s)
      let before2 = b.lock_violations_list().length()
      b.lock_violations_push(
        @store.LockViolation::new(
          ts="2026-10-12T10:00:00Z",
          agent="asst_old",
          scope="assistant",
          reason="force_takeover",
          lock_id="asst_new",
        ),
      )
      let after2 = b.lock_violations_list()
      assert_eq(after2.length(), before2 + 1)
      assert_eq(after2[after2.length() - 1].reason, "force_takeover")
      assert_eq(after2[after2.length() - 1].agent, "asst_old")
    }
  }
}
