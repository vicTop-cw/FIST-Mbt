// 作用域预订（rsv）双后端测试。

///|
fn rsv_backend_mem() -> @store.StoreBackend {
  @store.StoreBackend::memory()
}

///|
test "rsv 内存后端：预订/持有冲突/释放/过期让渡" {
  let b = rsv_backend_mem()
  // 空闲预订成功
  ignore(
    b.rsv_set(
      scope="src/a.mbt",
      agent="exec_1",
      ttl_until="2026-09-25T12:00:00Z",
      created_at="2026-09-25T11:00:00Z",
    ),
  )
  // 同 agent 续期成功（rsv_set 覆盖）
  ignore(
    b.rsv_set(
      scope="src/a.mbt",
      agent="exec_1",
      ttl_until="2026-09-25T13:00:00Z",
      created_at="2026-09-25T11:05:00Z",
    ),
  )
  // 其他 agent 查询 → 非空（held by exec_1）
  match b.rsv_get("src/a.mbt") {
    Some((owner, _, _)) => assert_eq(owner, "exec_1")
    None => abort("src/a.mbt 应已被预订")
  }
  // 非持有者释放失败
  assert_false(b.rsv_release("src/a.mbt", "exec_2"))
  // 持有者释放成功
  assert_true(b.rsv_release("src/a.mbt", "exec_1"))
  assert_true(b.rsv_get("src/a.mbt") is None)
  // 过期后可让渡（ttl_until 早于"当前"，rsv_set 仍可覆盖——过期语义由 server 层判断）
  ignore(
    b.rsv_set(
      scope="src/b.mbt",
      agent="old",
      ttl_until="2026-09-25T09:00:00Z",
      created_at="2026-09-25T08:00:00Z",
    ),
  )
  ignore(
    b.rsv_set(
      scope="src/b.mbt",
      agent="new",
      ttl_until="2026-09-25T12:00:00Z",
      created_at="2026-09-25T11:00:00Z",
    ),
  )
  match b.rsv_get("src/b.mbt") {
    Some((owner, _t, _)) => assert_eq(owner, "new")
    None => abort("src/b.mbt 应已被 new 接管")
  }
}

///|
test "rsv clear() 会一并清空预订（双后端，防跨次残留）" {
  // 内存后端
  let mem = @store.StoreBackend::memory()
  ignore(
    mem.rsv_set(
      scope="src/mem.mbt",
      agent="a",
      ttl_until="2026-09-25T12:00:00Z",
      created_at="2026-09-25T11:00:00Z",
    ),
  )
  mem.clear()
  assert_true(mem.rsv_get("src/mem.mbt") is None)
  // SQLite 后端
  let db = "temp/rsv_clear_test.db"
  match @store.SqliteStore::open(db) {
    None => abort("sqlite open failed")
    Some(s) => {
      let b = @store.StoreBackend::sqlite(s)
      ignore(
        b.rsv_set(
          scope="src/sql.mbt",
          agent="a",
          ttl_until="2026-09-25T12:00:00Z",
          created_at="2026-09-25T11:00:00Z",
        ),
      )
      s.clear()
      assert_true(s.rsv_get("src/sql.mbt") is None)
    }
  }
}

///|
test "rsv SQLite 后端：同一库可持久化读回" {
  let db = "temp/rsv_persist_test.db"
  match @store.SqliteStore::open(db) {
    None => abort("sqlite open failed: \{db}")
    Some(s) => {
      let b = @store.StoreBackend::sqlite(s)
      ignore(
        b.rsv_set(
          scope="src/c.mbt",
          agent="exec_1",
          ttl_until="2026-09-25T12:00:00Z",
          created_at="2026-09-25T11:00:00Z",
        ),
      )
      // 换连接读回
      match @store.SqliteStore::open(db) {
        None => abort("reopen failed")
        Some(s2) => {
          let b2 = @store.StoreBackend::sqlite(s2)
          match b2.rsv_get("src/c.mbt") {
            Some((agent, ttl, _)) => {
              assert_eq(agent, "exec_1")
              assert_eq(ttl, "2026-09-25T12:00:00Z")
            }
            None => abort("src/c.mbt 应持久化读回")
          }
          assert_true(b2.rsv_release("src/c.mbt", "exec_1"))
        }
      }
    }
  }
}
