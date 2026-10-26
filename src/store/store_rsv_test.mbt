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

///|
// —— SQLite 后端 locks_try_acquire（BUG-145 回归锁：拒绝型互斥必须在持久化库上成立）——
// 队友的「两后端同构」用例只跑了 memory()，下面补 SQLite 这一侧的硬断言——
// 尤其「他人 live 锁 → granted=false、锁行不被覆盖、落一条 lock_denied」。

test "locks_try_acquire: SQLite 后端 首取成功" {
  let db = "temp/lock_try_sqlite_fresh.db"
  match @store.SqliteStore::open(db) {
    None => abort("sqlite open failed: \{db}")
    Some(s) => ignore(s.clear())
  }
  let s = match @store.SqliteStore::open(db) {
    None => abort("sqlite reopen failed: \{db}")
    Some(s) => s
  }
  let b = @store.StoreBackend::sqlite(s)
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
test "locks_try_acquire: SQLite 后端 他人 live 锁 → granted=false + lock_denied + 锁行不动" {
  let db = "temp/lock_try_sqlite_conflict.db"
  match @store.SqliteStore::open(db) {
    None => abort("sqlite open failed: \{db}")
    Some(s) => ignore(s.clear())
  }
  let s = match @store.SqliteStore::open(db) {
    None => abort("sqlite reopen failed: \{db}")
    Some(s) => s
  }
  let b = @store.StoreBackend::sqlite(s)
  // exec_1 先持有一把 live 锁
  b.locks_upsert(
    @store.FileLock::new(
      lock_id="l1",
      batch_id="b1",
      scope="src/a.mbt",
      agent="exec_1",
      status="active",
      ts="2026-10-11T08:00:00Z",
      ttl_until="2026-10-11T12:00:00Z",
    ),
  )
  // exec_2 抢同一把 → 必须被拒（这是 BUG-145 修复的核心契约）
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
  // 锁行未被覆盖：持有者仍是 exec_1、lock_id 仍是 l1（旧形状会让 exec_2 也 reserved）
  match b.locks_get("src/a.mbt") {
    Some(l) => {
      assert_eq(l.agent, "exec_1")
      assert_eq(l.lock_id, "l1")
    }
    None => abort("SQLite 锁行不应消失")
  }
  // 恰好一条 lock_denied 违例
  let v = b.lock_violations_list()
  assert_eq(v.length(), 1)
  assert_eq(v[0].reason, "lock_denied")
}

///|
test "locks_try_acquire: SQLite 后端 旧主 TTL 已过 → taken_over + 覆盖为 exec_2" {
  let db = "temp/lock_try_sqlite_takeover.db"
  match @store.SqliteStore::open(db) {
    None => abort("sqlite open failed: \{db}")
    Some(s) => ignore(s.clear())
  }
  let s = match @store.SqliteStore::open(db) {
    None => abort("sqlite reopen failed: \{db}")
    Some(s) => s
  }
  let b = @store.StoreBackend::sqlite(s)
  b.locks_upsert(
    @store.FileLock::new(
      lock_id="l1",
      batch_id="b1",
      scope="src/a.mbt",
      agent="exec_1",
      status="active",
      ts="2026-10-11T08:00:00Z",
      ttl_until="2026-10-11T09:00:00Z", // 在 10:00 之前已过期
    ),
  )
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
  match b.locks_get("src/a.mbt") {
    Some(l) => assert_eq(l.agent, "exec_2")
    None => abort("SQLite 锁行应被接管")
  }
}

///|
test "locks_try_acquire: SQLite 后端 已释放锁 → reserved 复用行" {
  let db = "temp/lock_try_sqlite_released.db"
  match @store.SqliteStore::open(db) {
    None => abort("sqlite open failed: \{db}")
    Some(s) => ignore(s.clear())
  }
  let s = match @store.SqliteStore::open(db) {
    None => abort("sqlite reopen failed: \{db}")
    Some(s) => s
  }
  let b = @store.StoreBackend::sqlite(s)
  b.locks_upsert(
    @store.FileLock::new(
      lock_id="l1",
      batch_id="b1",
      scope="src/a.mbt",
      agent="exec_1",
      status="active",
      ts="2026-10-11T08:00:00Z",
      ttl_until="2026-10-11T12:00:00Z",
    ),
  )
  assert_true(b.locks_release("src/a.mbt", "exec_1"))
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

// ============================================================================
// BUG-431 / Lane AJ：**双后端等价性锁**（MemoryStore ↔ SqliteStore）
//
// 为什么这组锁必须存在（Lane AH 等价性审计 e9cd1ac7 发现的结构性盲区）：
//   落锁之前 `grep -c 'MemoryStore' src/store/store_rsv_test.mbt` = **0**
//   而 `SqliteStore` = 13 —— 即**整个 rsv 测试面只跑了一个后端**。
//   而 `store_rsv.mbt:110-112` 的原地注释**早就警告过这个形状**：
//   「两后端必须同一形状，否则单测永远绿而 SQLite 红」。**警告还在，盲区也还在。**
//
// 本组锁的形状（每个 test 自己造两个库，天然隔离）：
//   · 同输入喂 MemoryStore 与 SqliteStore::open(":memory:")
//   · 把两边**返回的结构体序列化成 JSON 再比**（moon test 吞掉通过测试的 stdout，
//     所以必须用断言而不是 println —— 这是 Lane AH 探针的原始设计，保留）
//   · 不依赖上一格状态：每格 `rsv_pair` / `lock_pair` 内部各自 `new()` / `open()`
//
// 覆盖量（对应 Lane AH 的 20 组，一格不少）：
//   rsv_action 四分支 4/4 · ttl 与 now 的 <,==,> 3/3 · agent 相同/不同/空 3/3
//   锁：无锁/有锁 2/2 · 锁 status 4 种 · ttl 边界
//   变异对照 2 格（证明这组锁**真的在看**规则，而不是恒绿）
// ============================================================================

///|
/// `RsvOutcome` → 稳定字符串（字段顺序固定，便于逐字比对）。
fn eq_rsv_json(o : @store.RsvOutcome) -> String {
  "{" +
  "\"reserved\":" +
  o.reserved.to_string() +
  ",\"action\":\"" +
  o.action +
  "\"" +
  ",\"prev_agent\":\"" +
  o.prev_agent +
  "\"" +
  ",\"agent\":\"" +
  o.agent +
  "\"" +
  ",\"ttl_until\":\"" +
  o.ttl_until +
  "\"}"
}

///|
/// 在两个**独立新建**的后端上跑同一组预订请求，返回 (内存侧 JSON, SQLite 侧 JSON)。
///
/// `prev` = 预先用 `rsv_set` 种下的既有预订（agent, ttl_until, created_at）。
/// 每个调用**都新建两个库** ⇒ 不依赖任何上一格的状态（`":memory:"` 每次 open 都是新库）。
fn eq_rsv_pair(
  prev : (String, String, String)?,
  req_agent : String,
  req_ttl : String,
  req_created : String,
) -> (String, String) {
  let mem = @store.MemoryStore::new()
  let sql = match @store.SqliteStore::open(":memory:") {
    Some(s) => s
    None => return ("{\"error\":\"sqlite open\"}", "{\"error\":\"sqlite open\"}")
  }
  match prev {
    Some((a, ttl, ts)) => {
      ignore(mem.rsv_set(scope="S", agent=a, ttl_until=ttl, created_at=ts))
      ignore(sql.rsv_set(scope="S", agent=a, ttl_until=ttl, created_at=ts))
    }
    None => ()
  }
  let m = mem.rsv_try_set(
    scope="S",
    agent=req_agent,
    ttl_until=req_ttl,
    created_at=req_created,
  )
  let s = sql.rsv_try_set(
    scope="S",
    agent=req_agent,
    ttl_until=req_ttl,
    created_at=req_created,
  )
  let mj = match m {
    Ok(o) => eq_rsv_json(o)
    Err(e) => "{\"err\":\"" + e + "\"}"
  }
  let sj = match s {
    Ok(o) => eq_rsv_json(o)
    Err(e) => "{\"err\":\"" + e + "\"}"
  }
  (mj, sj)
}

///|
/// 【等价锁 1】预订裁决：rsv_action 四分支 + ttl/now 三态 + agent 三态（10 组）
///
/// **为什么这格会在变异下红**：两后端共用 `rsv_action` 单一真源，
/// 但 SQLite 侧另有一条 `ON CONFLICT … WHERE` 谓词编码同一规则
/// （`reservations.agent = excluded.agent OR reservations.ttl_until < excluded.created_at`）。
/// 若有人把 SQL 那侧改成 `<=`（即判 `ttl == now` 也算过期），
/// **`EDGE other(ttl==now)` 这组就会内存说 conflict、SQLite 说 taken_over ⇒ 本格 abort**。
test "rsv 双后端等价：B1~B4 四分支 + ttl/now 边界 + agent 三态" {
  let cases : Array[(String, (String, String, String)?, String, String, String)] = [
    ("B1 none->reserved", None, "A", "t2", "t1"),
    ("B1 none->reserved(空 agent)", None, "", "t2", "t1"),
    ("B2 self->renewed", Some(("A", "t9", "t0")), "A", "t9", "t1"),
    ("B2 self->renewed(ttl==now)", Some(("A", "t1", "t0")), "A", "t9", "t1"),
    ("B2 self->renewed(ttl<now)", Some(("A", "t0", "t0")), "A", "t9", "t1"),
    ("B3 other->taken_over(ttl<now)", Some(("B", "t0", "t0")), "A", "t9", "t1"),
    ("EDGE other(ttl==now)", Some(("B", "t1", "t0")), "A", "t9", "t1"),
    ("B4 other->conflict(ttl>now)", Some(("B", "t9", "t0")), "A", "t9", "t1"),
    ("EDGE empty->empty", Some(("", "t9", "t0")), "", "t9", "t1"),
    ("EDGE empty->A", Some(("", "t9", "t0")), "A", "t9", "t1"),
  ]
  for (label, prev, ra, rt, rc) in cases {
    let (mj, sj) = eq_rsv_pair(prev, ra, rt, rc)
    if mj != sj {
      abort("双后端预订分歧 [" + label + "]\n  内存 = " + mj + "\n  SQLite = " + sj)
    }
  }
  // 至少跑过一组，防空转（判例：「空集合恒真」不算证明）
  assert_true(cases.length() == 10)
}

///|
/// `LockAcquireOutcome` → 稳定字符串。
fn eq_lock_json(o : @store.LockAcquireOutcome) -> String {
  "{" +
  "\"granted\":" +
  o.granted.to_string() +
  ",\"action\":\"" +
  o.action +
  "\"" +
  ",\"prev_agent\":\"" +
  o.prev_agent +
  "\"" +
  ",\"agent\":\"" +
  o.agent +
  "\"" +
  ",\"ttl_until\":\"" +
  o.ttl_until +
  "\"" +
  ",\"violation_logged\":" +
  o.violation_logged.to_string() +
  "}"
}

///|
fn eq_mk_lock(
  agent : String,
  status : String,
  ts : String,
  ttl : String,
) -> @store.FileLock {
  @store.FileLock::new(
    lock_id="L1",
    batch_id="B1",
    scope="S",
    agent~,
    status~,
    ts~,
    ttl_until=ttl,
    meta="",
  )
}

///|
/// 在两个独立新建的后端上跑同一组锁请求，返回 (内存侧 JSON, SQLite 侧 JSON)。
fn eq_lock_pair(
  prev : (String, String, String, String)?,
  req_agent : String,
  req_ts : String,
  req_ttl : String,
) -> (String, String) {
  let mem = @store.MemoryStore::new()
  let sql = match @store.SqliteStore::open(":memory:") {
    Some(s) => s
    None => return ("{\"error\":\"sqlite open\"}", "{\"error\":\"sqlite open\"}")
  }
  match prev {
    Some((pa, ps, pts, pttl)) => {
      let l = eq_mk_lock(pa, ps, pts, pttl)
      mem.locks_upsert(l)
      sql.locks_upsert(l)
    }
    None => ()
  }
  let req = eq_mk_lock(req_agent, "active", req_ts, req_ttl)
  let m = mem.locks_try_acquire(req)
  let s = sql.locks_try_acquire(req)
  (eq_lock_json(m), eq_lock_json(s))
}

///|
/// 【等价锁 2】锁层裁决：无锁/有锁 2/2 + status 四种 + ttl 边界（10 组）
///
/// **为什么这格会在变异下红**：
///   · 若有人把「非 active 折成 None」的折叠条件去掉（`status == "active"` 不看 status）
///     ⇒ `L4 released->reserved` / `L5 expired` / `L6 violated` 三组会从 reserved 变 conflict；
///   · 若有人在 SQLite 侧把 `ttl < now` 写成 `<=` ⇒ `LEDGE other(ttl==now)` 这组分歧。
test "rsv 双后端等价：锁层无锁/有锁 + status 四种 + ttl 边界" {
  let cases : Array[(String, (String, String, String, String)?, String, String, String)] = [
    ("L0 none->reserved", None, "A", "t1", "t9"),
    ("L1 self->renewed", Some(("A", "active", "t0", "t9")), "A", "t1", "t9"),
    ("L2 other->conflict", Some(("B", "active", "t0", "t9")), "A", "t1", "t9"),
    ("L3 other->taken_over(ttl<now)", Some(("B", "active", "t0", "t0")), "A", "t1", "t9"),
    ("LEDGE other(ttl==now)", Some(("B", "active", "t0", "t1")), "A", "t1", "t9"),
    ("L4 released->reserved", Some(("B", "released", "t0", "t9")), "A", "t1", "t9"),
    ("L5 expired->reserved", Some(("B", "expired", "t0", "t9")), "A", "t1", "t9"),
    ("L6 violated->reserved", Some(("B", "violated", "t0", "t9")), "A", "t1", "t9"),
    ("LEDGE empty->empty", Some(("", "active", "t0", "t9")), "", "t1", "t9"),
    ("LEDGE empty->A", Some(("", "active", "t0", "t9")), "A", "t1", "t9"),
  ]
  for (label, prev, ra, rt, rttl) in cases {
    let (mj, sj) = eq_lock_pair(prev, ra, rt, rttl)
    if mj != sj {
      abort("双后端锁分歧 [" + label + "]\n  内存 = " + mj + "\n  SQLite = " + sj)
    }
  }
  assert_true(cases.length() == 10)
}

///|
/// 【等价锁 3】`locks_sweep(now) -> Int32` 清扫数一致（Lane AH 的缺口项）
///
/// **为什么断言清扫数而不只是「都成功」**：`locks_sweep` 返回 `Int32`（清掉几条），
/// 若两后端对「什么算过期」的判据不同，**返回的数字会不同**。
/// 只断言 `Ok`/不 panic 会让「清 3 条 vs 清 0 条」这种真分歧溜过去。
///
/// 场景：种 4 条锁（2 条 ttl 已过、1 条 ttl == now、1 条未过），`sweep("t1")` ⇒
/// 严格 `<` 口径下应清 **2** 条（ttl 已过那两条），`ttl == now` 那条**不该被清**。
test "rsv 双后端等价：locks_sweep 清扫数（Int32）一致" {
  let mem = @store.MemoryStore::new()
  let sql = match @store.SqliteStore::open(":memory:") {
    Some(s) => s
    None => abort("sqlite open 失败")
  }
  // (scope, agent, status, ts, ttl_until) —— ttl 相对 sweep 时刻 now="t1"
  let seeds : Array[(String, String, String, String, String)] = [
    ("S1", "A", "active", "t0", "t0"), // ttl < now ⇒ 该被清
    ("S2", "A", "active", "t0", "t0"), // ttl < now ⇒ 该被清
    ("S3", "A", "active", "t0", "t1"), // ttl == now ⇒ **不该被清**（严格 <）
    ("S4", "A", "active", "t0", "t9"), // ttl > now ⇒ 不该被清
  ]
  for (sc, ag, st, ts, ttl) in seeds {
    let l = @store.FileLock::new(
      lock_id="L-" + sc,
      batch_id="B1",
      scope=sc,
      agent=ag,
      status=st,
      ts=ts,
      ttl_until=ttl,
      meta="",
    )
    mem.locks_upsert(l)
    sql.locks_upsert(l)
  }
  let m_n = mem.locks_sweep("t1")
  let s_n = sql.locks_sweep("t1")
  if m_n != s_n {
    abort(
      "双后端 locks_sweep 清扫数分歧：内存清 " +
      m_n.to_string() +
      " 条，SQLite 清 " +
      s_n.to_string() +
      " 条（同为 4 条种子、now=t1）",
    )
  }
  // 清扫数本身也要对：ttl ∈ {t0,t0,t1,t9}、now=t1 ⇒ 严格 < 只清 t0 那两条
  assert_eq(m_n, 2)
}

///|
/// 【变异对照 1】`ttl < now` 的严格性真的被测到（判例-29/30）
///
/// 把 `rsv_action` 的 `ttl < now` 写成 `ttl <= now`（本仓最易犯的错），
/// 在 `ttl == now` 边界上**结果必须不同** —— 若相同，说明「严格 <」这条规则
/// 没有任何一格在测，等价锁就是恒绿的假锁。
test "rsv 变异对照：strict_lt 在 ttl==now 边界上可分辨" {
  let prev = Some(("B", "t1", "t0"))
  // 真实现：ttl == now ⇒ **不算过期** ⇒ conflict（严格 <）
  let (ok_w, ok_a) = @store.rsv_action(prev, "A", "t1")
  assert_eq(ok_w, false)
  assert_eq(ok_a, "conflict")
  // 变异实现：把谓词写成 `<=` ⇒ 同一输入得 taken_over（用独立的纯函数表达，不改生产码）
  let mut_a = mut_rsv_action_le(prev, "A", "t1")
  assert_eq(mut_a, "taken_over")
  // ★ 两者在 ttl==now 这一格上**必须不同** ⇒ 证明「严格 <」被真测到
  assert_true(ok_a != mut_a)
}

///|
/// 变异版裁决（仅用于证明"严格 <"可分辨）：把 `ttl < now` 写成 `ttl <= now`。
fn mut_rsv_action_le(
  prev : (String, String, String)?,
  agent : String,
  now : String,
) -> String {
  match prev {
    None => "reserved"
    Some((owner, _, _)) if owner == agent => "renewed"
    Some((_, ttl, _)) if ttl <= now => "taken_over"
    _ => "conflict"
  }
}

///|
/// 【变异对照 2】锁层「非 active 折成 None」真的被测到（判例-29/30）
///
/// 若有人把 `status == "active"` 这个折叠条件去掉（不看 status），
/// `active` 与 `released` 两种输入会得到**相同**裁决 ⇒ 本格红。
test "rsv 变异对照：锁 status 折叠条件可分辨" {
  let active = @store.FileLock::new(
    lock_id="L1",
    batch_id="B1",
    scope="S",
    agent="B",
    status="active",
    ts="t0",
    ttl_until="t9",
    meta="",
  )
  let released = @store.FileLock::new(
    lock_id="L1",
    batch_id="B1",
    scope="S",
    agent="B",
    status="released",
    ts="t0",
    ttl_until="t9",
    meta="",
  )
  // active ⇒ 有人持 ⇒ conflict
  let a = @store.lock_acquire_action(Some(active), "A", "t1")
  assert_eq(a.0, false)
  assert_eq(a.1, "conflict")
  // released ⇒ 折成 None ⇒ reserved
  let r = @store.lock_acquire_action(Some(released), "A", "t1")
  assert_eq(r.0, true)
  assert_eq(r.1, "reserved")
  // ★ 两种 status 结果**必须不同** ⇒ 证明折叠条件真的在起作用
  assert_true(a.1 != r.1)
}
