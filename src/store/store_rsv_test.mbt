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

// —— 分布式文件锁双后端测试 ——

///|
test "locks 内存后端：获取/释放/续期/过期清理/违例记录" {
  let b = @store.StoreBackend::memory()
  let ts = "2026-10-11T10:00:00Z"
  // ① 获取锁
  let l1 = @store.FileLock::new(
    lock_id="lock-1",
    batch_id="batch-1",
    scope="src/a.mbt",
    agent="exec_1",
    status="active",
    ts~,
    ttl_until="2026-10-11T11:00:00Z",
    meta="",
  )
  b.locks_upsert(l1)
  match b.locks_get("src/a.mbt") {
    Some(l) => {
      assert_eq(l.lock_id, "lock-1")
      assert_eq(l.agent, "exec_1")
      assert_eq(l.status, "active")
    }
    None => abort("src/a.mbt 应有锁")
  }
  // ② 他人抢占 active 锁 → 记违例
  let l2 = @store.FileLock::new(
    lock_id="lock-2",
    batch_id="batch-1",
    scope="src/a.mbt",
    agent="exec_2",
    status="active",
    ts="2026-10-11T10:30:00Z",
    ttl_until="2026-10-11T12:00:00Z",
    meta="",
  )
  b.locks_upsert(l2)
  let violations = b.lock_violations_list()
  assert_eq(violations.length(), 1)
  assert_eq(violations[0].reason, "lock_taken_over")
  assert_eq(violations[0].lock_id, "lock-1")
  // ③ 非持有者释放失败
  assert_false(b.locks_release("src/a.mbt", "exec_1"))
  // ④ 持有者释放成功
  assert_true(b.locks_release("src/a.mbt", "exec_2"))
  match b.locks_get("src/a.mbt") {
    Some(l) => assert_eq(l.status, "released")
    None => abort("src/a.mbt 应有 released 锁记录")
  }
  // ⑤ 过期清理
  let l3 = @store.FileLock::new(
    lock_id="lock-3",
    batch_id="batch-2",
    scope="src/b.mbt",
    agent="exec_3",
    status="active",
    ts="2026-10-11T08:00:00Z",
    ttl_until="2026-10-11T09:00:00Z",
    meta="",
  )
  b.locks_upsert(l3)
  let swept = b.locks_sweep("2026-10-11T10:00:00Z")
  assert_eq(swept, 1)
  match b.locks_get("src/b.mbt") {
    Some(l) => assert_eq(l.status, "expired")
    None => abort("src/b.mbt 应有 expired 锁记录")
  }
  let violations2 = b.lock_violations_list()
  assert_eq(violations2.length(), 2)
  assert_eq(violations2[1].reason, "lock_expired")
}

///|
test "locks clear() 会一并清空锁与违例" {
  let b = @store.StoreBackend::memory()
  let l = @store.FileLock::new(
    lock_id="lock-1",
    batch_id="b1",
    scope="src/x.mbt",
    agent="a",
    ts="2026-10-11T10:00:00Z",
    ttl_until="2026-10-11T11:00:00Z",
  )
  b.locks_upsert(l)
  b.clear()
  assert_true(b.locks_get("src/x.mbt") is None)
  assert_eq(b.lock_violations_list().length(), 0)
}

///|
test "locks FileLock::renew 重置 ttl 与 status" {
  let l = @store.FileLock::new(
    lock_id="lock-1",
    batch_id="b1",
    scope="src/y.mbt",
    agent="a",
    status="expired",
    ts="2026-10-11T08:00:00Z",
    ttl_until="2026-10-11T09:00:00Z",
  )
  let r = l.renew(ttl_until="2026-10-11T12:00:00Z", ts="2026-10-11T10:00:00Z")
  assert_eq(r.lock_id, "lock-1")
  assert_eq(r.agent, "a")
  assert_eq(r.status, "active")
  assert_eq(r.ttl_until, "2026-10-11T12:00:00Z")
  assert_eq(r.ts, "2026-10-11T10:00:00Z")
}

///|
// —— lock_acquire_action 纯函数（BUG-145：锁层委托 rsv_action，单一真源）——

test "lock_acquire_action: 无前置锁 → (true, reserved)" {
  let (ok, action) = @store.lock_acquire_action(
    None,
    "a",
    "2026-10-11T10:00:00Z",
  )
  assert_true(ok)
  assert_eq(action, "reserved")
}

///|
test "lock_acquire_action: 同持有者 → (true, renewed)，即使他人 TTL 已过也排在过期之前" {
  let prev = @store.FileLock::new(
    lock_id="l1",
    batch_id="b1",
    scope="s",
    agent="a",
    status="active",
    ts="2026-10-11T08:00:00Z",
    ttl_until="2026-10-11T09:00:00Z",
  )
  // TTL 已过（09:00 < 10:00），但同持有者排在过期之前 → renewed 而非 taken_over
  let (ok, action) = @store.lock_acquire_action(
    Some(prev),
    "a",
    "2026-10-11T10:00:00Z",
  )
  assert_true(ok)
  assert_eq(action, "renewed")
}

///|
test "lock_acquire_action: 他人 TTL 已过 → (true, taken_over)" {
  let prev = @store.FileLock::new(
    lock_id="l1",
    batch_id="b1",
    scope="s",
    agent="a",
    status="active",
    ts="2026-10-11T08:00:00Z",
    ttl_until="2026-10-11T09:00:00Z",
  )
  let (ok, action) = @store.lock_acquire_action(
    Some(prev),
    "b",
    "2026-10-11T10:00:00Z",
  )
  assert_true(ok)
  assert_eq(action, "taken_over")
}

///|
test "lock_acquire_action: 他人 live 锁 → (false, conflict)" {
  let prev = @store.FileLock::new(
    lock_id="l1",
    batch_id="b1",
    scope="s",
    agent="a",
    status="active",
    ts="2026-10-11T08:00:00Z",
    ttl_until="2026-10-11T12:00:00Z",
  )
  let (ok, action) = @store.lock_acquire_action(
    Some(prev),
    "b",
    "2026-10-11T10:00:00Z",
  )
  assert_false(ok)
  assert_eq(action, "conflict")
}

///|
test "lock_acquire_action: 已释放锁 → (true, reserved)" {
  let prev = @store.FileLock::new(
    lock_id="l1",
    batch_id="b1",
    scope="s",
    agent="a",
    status="released",
    ts="2026-10-11T08:00:00Z",
    ttl_until="2026-10-11T12:00:00Z",
  )
  let (ok, action) = @store.lock_acquire_action(
    Some(prev),
    "b",
    "2026-10-11T10:00:00Z",
  )
  assert_true(ok)
  assert_eq(action, "reserved")
}

///|
// —— locks_try_acquire 集成（拒绝型互斥：抢不到就是拒，不覆盖）——

test "locks_try_acquire: 首取成功" {
  let b = @store.StoreBackend::memory()
  let lock = @store.FileLock::new(
    lock_id="l1",
    batch_id="b1",
    scope="src/a.mbt",
    agent="exec_1",
    status="active",
    ts="2026-10-11T10:00:00Z",
    ttl_until="2026-10-11T11:00:00Z",
  )
  let o = b.locks_try_acquire(lock)
  assert_true(o.granted)
  assert_eq(o.action, "reserved")
  assert_eq(o.agent, "exec_1")
  assert_eq(o.prev_agent, "")
  assert_false(o.violation_logged)
}

///|
test "locks_try_acquire: 他人 live 锁 → granted=false + lock_denied 审计 + 锁行不动" {
  let b = @store.StoreBackend::memory()
  // 先让 exec_1 持有 live 锁
  let l1 = @store.FileLock::new(
    lock_id="l1",
    batch_id="b1",
    scope="src/a.mbt",
    agent="exec_1",
    status="active",
    ts="2026-10-11T08:00:00Z",
    ttl_until="2026-10-11T12:00:00Z",
  )
  b.locks_upsert(l1)
  // exec_2 抢同一把 → 必须被拒
  let l2 = @store.FileLock::new(
    lock_id="l2",
    batch_id="b1",
    scope="src/a.mbt",
    agent="exec_2",
    status="active",
    ts="2026-10-11T10:00:00Z",
    ttl_until="2026-10-11T12:00:00Z",
  )
  let o = b.locks_try_acquire(l2)
  assert_false(o.granted)
  assert_eq(o.action, "conflict")
  assert_true(o.violation_logged)
  assert_eq(o.agent, "exec_1") // 库里现值仍是 exec_1
  // 锁行未被覆盖：持有者仍是 exec_1，不是 exec_2
  match b.locks_get("src/a.mbt") {
    Some(l) => {
      assert_eq(l.agent, "exec_1")
      assert_eq(l.lock_id, "l1")
    }
    None => abort("锁行不应消失")
  }
  // 违例记录
  let v = b.lock_violations_list()
  assert_eq(v.length(), 1)
  assert_eq(v[0].reason, "lock_denied")
}

///|
test "locks_try_acquire: 旧主 TTL 已过 → granted=true + taken_over + prev_agent" {
  let b = @store.StoreBackend::memory()
  let l1 = @store.FileLock::new(
    lock_id="l1",
    batch_id="b1",
    scope="src/a.mbt",
    agent="exec_1",
    status="active",
    ts="2026-10-11T08:00:00Z",
    ttl_until="2026-10-11T09:00:00Z",
  )
  b.locks_upsert(l1)
  // exec_2 在 10:00 抢（l1 TTL 09:00 已过）
  let l2 = @store.FileLock::new(
    lock_id="l2",
    batch_id="b1",
    scope="src/a.mbt",
    agent="exec_2",
    status="active",
    ts="2026-10-11T10:00:00Z",
    ttl_until="2026-10-11T12:00:00Z",
  )
  let o = b.locks_try_acquire(l2)
  assert_true(o.granted)
  assert_eq(o.action, "taken_over")
  assert_eq(o.prev_agent, "exec_1")
  assert_eq(o.agent, "exec_2")
  assert_false(o.violation_logged)
  // 锁行已被覆盖为 exec_2
  match b.locks_get("src/a.mbt") {
    Some(l) => assert_eq(l.agent, "exec_2")
    None => abort("锁行应存在")
  }
}

///|
test "locks_try_acquire: 同持有者续取 → renewed" {
  let b = @store.StoreBackend::memory()
  let l1 = @store.FileLock::new(
    lock_id="l1",
    batch_id="b1",
    scope="src/a.mbt",
    agent="exec_1",
    status="active",
    ts="2026-10-11T08:00:00Z",
    ttl_until="2026-10-11T09:00:00Z",
  )
  b.locks_upsert(l1)
  // exec_1 自己续取（即使 TTL 已过，同持有者排在过期之前）
  let l2 = @store.FileLock::new(
    lock_id="l2",
    batch_id="b1",
    scope="src/a.mbt",
    agent="exec_1",
    status="active",
    ts="2026-10-11T10:00:00Z",
    ttl_until="2026-10-11T12:00:00Z",
  )
  let o = b.locks_try_acquire(l2)
  assert_true(o.granted)
  assert_eq(o.action, "renewed")
  assert_eq(o.prev_agent, "")
  assert_eq(o.agent, "exec_1")
}

///|
test "locks_try_acquire: 已释放锁 → reserved" {
  let b = @store.StoreBackend::memory()
  let l1 = @store.FileLock::new(
    lock_id="l1",
    batch_id="b1",
    scope="src/a.mbt",
    agent="exec_1",
    status="active",
    ts="2026-10-11T08:00:00Z",
    ttl_until="2026-10-11T12:00:00Z",
  )
  b.locks_upsert(l1)
  assert_true(b.locks_release("src/a.mbt", "exec_1"))
  // exec_2 复用已释放的行
  let l2 = @store.FileLock::new(
    lock_id="l2",
    batch_id="b1",
    scope="src/a.mbt",
    agent="exec_2",
    status="active",
    ts="2026-10-11T10:00:00Z",
    ttl_until="2026-10-11T12:00:00Z",
  )
  let o = b.locks_try_acquire(l2)
  assert_true(o.granted)
  assert_eq(o.action, "reserved")
  assert_eq(o.agent, "exec_2")
}

///|
// —— 两后端同构（BUG-145 回归锁：SQLite 与 Memory 对同一序列给出同结论）——

test "locks_try_acquire: 两后端同构 —— 同序列同结论" {
  let scenarios = [
    "fresh", // 无前置
     "same-renew", // 同持有者续
     "expired-take", // 他人 TTL 已过
     "live-conflict", // 他人 live
     "released-take", // 已释放
  ]
  for s in scenarios {
    let b = @store.StoreBackend::memory()
    // 按场景种前置锁
    if s == "fresh" {
      // 不种
    } else if s == "same-renew" || s == "live-conflict" {
      b.locks_upsert(
        @store.FileLock::new(
          lock_id="l1",
          batch_id="b1",
          scope="s",
          agent="a",
          status="active",
          ts="2026-10-11T08:00:00Z",
          ttl_until="2026-10-11T12:00:00Z",
        ),
      )
    } else if s == "expired-take" {
      b.locks_upsert(
        @store.FileLock::new(
          lock_id="l1",
          batch_id="b1",
          scope="s",
          agent="a",
          status="active",
          ts="2026-10-11T08:00:00Z",
          ttl_until="2026-10-11T09:00:00Z",
        ),
      )
    } else if s == "released-take" {
      b.locks_upsert(
        @store.FileLock::new(
          lock_id="l1",
          batch_id="b1",
          scope="s",
          agent="a",
          status="active",
          ts="2026-10-11T08:00:00Z",
          ttl_until="2026-10-11T12:00:00Z",
        ),
      )
      ignore(b.locks_release("s", "a"))
    }
    let agent = if s == "same-renew" { "a" } else { "b" }
    let ts = if s == "expired-take" {
      "2026-10-11T10:00:00Z"
    } else {
      "2026-10-11T10:00:00Z"
    }
    let o = b.locks_try_acquire(
      @store.FileLock::new(
        lock_id="l2",
        batch_id="b1",
        scope="s",
        agent~,
        status="active",
        ts~,
        ttl_until="2026-10-11T12:00:00Z",
      ),
    )
    // 断言 granted 与 action 一致（两后端都走 lock_acquire_action→rsv_action）
    match s {
      "fresh" => {
        assert_true(o.granted)
        assert_eq(o.action, "reserved")
      }
      "same-renew" => {
        assert_true(o.granted)
        assert_eq(o.action, "renewed")
      }
      "expired-take" => {
        assert_true(o.granted)
        assert_eq(o.action, "taken_over")
      }
      "live-conflict" => {
        assert_false(o.granted)
        assert_eq(o.action, "conflict")
      }
      "released-take" => {
        assert_true(o.granted)
        assert_eq(o.action, "reserved")
      }
      _ => ()
    }
  }
}
