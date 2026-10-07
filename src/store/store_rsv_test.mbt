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

///|
/// BUG-136 的裁决规则本体：四条分支 + 一条边（自己那条已过期的预订，续期报 renewed
/// 而不是 taken_over）。规则做成纯函数是故意的——两个后端共用它，语义不可能分叉。
test "rsv_action：四种结论互斥，同持有者排在过期之前" {
  let now = "2026-10-07T00:00:00Z"
  // 空闲
  let (w0, a0) = @store.rsv_action(None, "exec_1", now)
  assert_true(w0)
  assert_eq(a0, "reserved")
  // 他人活体
  let (w1, a1) = @store.rsv_action(
    Some(("exec_2", "2026-10-07T23:00:00Z", "2026-10-07T00:00:00Z")),
    "exec_1",
    now,
  )
  assert_false(w1)
  assert_eq(a1, "conflict")
  // 同 agent（哪怕它自己那条已经过期）
  let (w2, a2) = @store.rsv_action(
    Some(("exec_1", "2020-01-01T00:00:00Z", "2020-01-01T00:00:00Z")),
    "exec_1",
    now,
  )
  assert_true(w2)
  assert_eq(a2, "renewed")
  // 他人过期 → 让渡
  let (w3, a3) = @store.rsv_action(
    Some(("exec_2", "2020-01-01T00:00:00Z", "2020-01-01T00:00:00Z")),
    "exec_1",
    now,
  )
  assert_true(w3)
  assert_eq(a3, "taken_over")
  // 成对反向：两条 may_write 里，conflict 只有一种来源（他人活体），不是"读不到就当冲突"
  let (w4, a4) = @store.rsv_action(
    Some(("exec_1", "2026-10-07T23:00:00Z", "2026-10-07T00:00:00Z")),
    "exec_1",
    now,
  )
  assert_true(w4)
  assert_eq(a4, "renewed")
}

///|
/// BUG-136 的双后端同语义锁：同一串请求打过来，内存与 SQLite 必须给**同样的四段结论**，
/// 且冲突那一次库里不许被覆盖（旧形状在这里会让第二个 agent 也拿到 reserved=true）。
test "rsv_try_set：空闲/活体冲突/续期/过期让渡，两后端逐字段一致" {
  let db = "temp/rsv_try_test.db"
  match @store.SqliteStore::open(db) {
    None => abort("sqlite open failed: \{db}")
    Some(s) => ignore(s.clear())
  }
  let sql_backend = match @store.SqliteStore::open(db) {
    None => abort("sqlite reopen failed: \{db}")
    Some(s) => @store.StoreBackend::sqlite(s)
  }
  let backends = [@store.StoreBackend::memory(), sql_backend]
  for b in backends {
    let backend_tag = b.backend_name()
    let scope = "src/try.mbt"
    // ① 空闲 → 抢到
    match
      b.rsv_try_set(
        scope~,
        agent="exec_1",
        ttl_until="2026-10-07T12:00:00Z",
        created_at="2026-10-07T11:00:00Z",
      ) {
      Err(e) => abort("\{backend_tag} 空闲预订应成功：\{e}")
      Ok(o) => {
        assert_true(o.reserved)
        assert_eq(o.action, "reserved")
        assert_eq(o.agent, "exec_1")
      }
    }
    // ② 他人活体 → 拒，且回执点名持有者；库里仍是 exec_1（旧码在这里会双双成功）
    match
      b.rsv_try_set(
        scope~,
        agent="exec_2",
        ttl_until="2026-10-07T13:00:00Z",
        created_at="2026-10-07T11:30:00Z",
      ) {
      Err(e) => abort("\{backend_tag} 冲突要如实返回：\{e}")
      Ok(o) => {
        assert_false(o.reserved)
        assert_eq(o.action, "conflict")
        assert_eq(o.agent, "exec_1")
        assert_eq(o.ttl_until, "2026-10-07T12:00:00Z")
      }
    }
    match b.rsv_get(scope) {
      Some((owner, _, _)) => assert_eq(owner, "exec_1")
      None => abort("\{backend_tag}：冲突之后持有者被抹掉了")
    }
    // ③ 同 agent → renewed
    match
      b.rsv_try_set(
        scope~,
        agent="exec_1",
        ttl_until="2026-10-07T14:00:00Z",
        created_at="2026-10-07T12:00:00Z",
      ) {
      Err(e) => abort("\{backend_tag} 续期应成功：\{e}")
      Ok(o) => {
        assert_true(o.reserved)
        assert_eq(o.action, "renewed")
        assert_eq(o.prev_agent, "")
      }
    }
    // ④ 他人已过期 → taken_over 并点名原持有者
    ignore(
      b.rsv_try_set(
        scope~,
        agent="exec_1",
        ttl_until="2020-01-01T00:00:00Z",
        created_at="2019-01-01T00:00:00Z",
      ),
    )
    match
      b.rsv_try_set(
        scope~,
        agent="exec_3",
        ttl_until="2026-10-07T16:00:00Z",
        created_at="2026-10-07T15:00:00Z",
      ) {
      Err(e) => abort("\{backend_tag} 让渡应成功：\{e}")
      Ok(o) => {
        assert_true(o.reserved)
        assert_eq(o.action, "taken_over")
        assert_eq(o.prev_agent, "exec_1")
      }
    }
  }
}
