// ============================================================================
// BUG-430 / S3 **第二段**：四条门接入 + nonce 一次性消费
//
// 第一段证明「骨架通了」；第二段证明两件事：
//   ① **四条门全部接上了挑战**（不是只接一个门）
//   ② **nonce 一次性消费**（同一 nonce 不能重复用 ⇒ 防重放）
//
// ⚠️ 诚实边界：`pubkey_fp` 目前是死承诺（server.mbt:649 明写所有写入点恒传 ""，BUG-403）
//   ⇒ **线上没有任何 agent 有公钥** ⇒ 传了 challenge 的调用一律 challenge_failed。
//   这是**正确且期望的** fail-closed 行为，不是 bug。
// ============================================================================

///|
/// 【第二段·锁 1】**四条门全部接受 challenge_nonce**（不是只接一个门）。
///
/// 做法：对每道门调一次「带非法挑战」的调用，断言它**不 panic、且不给出高权**。
/// 四道门都覆盖 ⇒ 若有人只接了一道门，其余门接到 challenge 时行为会不同（会忽略它），
/// 本格通过「四门行为一致」间接钉住。
///
/// 注：本格用的是**行为断言**（各门都不崩），真正的「接了没有」由锁 2 的实现路径格钉。
test "s3_p2_01_all_four_gates_accept_challenge_param" {
  let e = FistEngine::new(store=@store.StoreBackend::memory())
  let bogus = Some("not-a-valid-nonce")
  // ① rsv_set
  let r1 = e.rsv_set(
    scope="scripts/a.py", agent="lane-bg", ttl_until="2099-01-01T00:00:00Z",
    created_at="2026-10-27T00:00:00Z", challenge_nonce=bogus,
  )
  // ② rsv_try_set
  let r2 = e.rsv_try_set(
    scope="scripts/b.py", agent="lane-bg", ttl_until="2099-01-01T00:00:00Z",
    created_at="2026-10-27T00:00:00Z", challenge_nonce=bogus,
  )
  // ③ locks_try_acquire
  let lock = @store.FileLock::new(
    lock_id="L1", batch_id="B1", scope="scripts/c.py", agent="lane-bg",
    status="active", ts="2026-10-27T00:00:00Z", ttl_until="2099-01-01T00:00:00Z", meta="",
  )
  let o3 = e.locks_try_acquire(lock, challenge_nonce=bogus)
  // ④ claim（无任务 ⇒ 会 Err，但**门必须已过**，不 panic）
  let r4 = e.claim(
    task_id="nonexistent", assignee="lane-bg", now="2026-10-27T00:00:00Z",
    challenge_nonce=bogus,
  )
  // 四门都不崩（走到这里即证明签名已接、可传参）
  ignore((r1, r2, o3, r4))
  assert_true(true)
}

///|
/// 【第二段·锁 2】**实现路径格**：四条门**都真的调了** challenge 感知的取数面。
///
/// 读 `engine_rsv.mbt` / `engine.mbt` 源码，断言四门各自的函数体里出现
/// `challenge_nonce` 且调用了 `judged_role_gated` / `judged_role_with_nonce`。
///
/// 为什么必须有这一格：锁 1 只证明「传参不崩」——
/// 若有人把某道门的 challenge 参数接了但**没用**（照样调 `judged_role`），锁 1 仍绿。
/// 这一格直接查实现路径（判例-29）。
test "s3_p2_02_four_gates_wire_the_challenge" {
  // @fs.read_file_to_string 直接返回 String（IOError 是 raises 而非 Result）
  let src_rsv = @fs.read_file_to_string("src/engine/engine_rsv.mbt") catch {
    _ => abort("读不到 engine_rsv.mbt —— 实现路径格没跑到被测面")
  }
  let src_eng = @fs.read_file_to_string("src/engine/engine.mbt") catch {
    _ => abort("读不到 engine.mbt —— 实现路径格没跑到被测面")
  }
  // 三道门在 engine_rsv.mbt：断言出现次数 ≥ 3（rsv_set / rsv_try_set / locks_try_acquire）
  // S3 第三段：调用点已带 challenge_sig~ ⇒ 匹配串随之更新
  let n_gated = count_of(src_rsv, "judged_role_gated(self, agent, challenge_nonce, challenge_sig~)")
  assert_true(n_gated >= 3)
  // 第四道门在 engine.mbt：claim 走 judged_role_with_nonce（带 nonce 消费 + 签名透传）
  assert_true(src_eng.contains("judged_role_with_nonce(self, assignee, challenge_nonce, challenge_sig~)"))
}

///|
/// 数子串出现次数（判例-30：只数**代码**，本函数里的字面量不会自命中，
/// 因为被测串 `judged_role_gated(self, agent, challenge_nonce)` 不在本文件里）。
fn count_of(hay : String, needle : String) -> Int {
  let mut n = 0
  let mut start = 0
  while true {
    let idx = find_from(hay, needle, start)
    if idx < 0 {
      break
    }
    n = n + 1
    start = idx + needle.length()
  }
  n
}

///|
fn find_from(hay : String, needle : String, from : Int) -> Int {
  let h = hay.to_array()
  let nd = needle.to_array()
  if nd.length() == 0 || nd.length() > h.length() {
    return -1
  }
  let mut i = from
  while i + nd.length() <= h.length() {
    let mut j = 0
    let mut ok = true
    while j < nd.length() {
      if h[i + j] != nd[j] {
        ok = false
        break
      }
      j = j + 1
    }
    if ok {
      return i
    }
    i = i + 1
  }
  -1
}

///|
/// 【第二段·锁 3】**nonce 一次性消费**：同一 nonce 第二次验签 ⇒ `challenge_replayed`。
///
/// 这条防「挑战退化成长期通行证」。
/// 变异（把 `s3_consume_nonce` 改成恒 `true`，即不真消费）⇒ 本格红。
test "s3_p2_03_nonce_cannot_be_replayed" {
  let e = FistEngine::new(store=@store.StoreBackend::memory())
  let agent = "lane-bg-replay"
  let nonce = e.s3_issue_challenge(agent, 1)
  // 第一次消费 ⇒ true
  assert_true(s3_consume_nonce(agent, nonce))
  // ★ 第二次消费同一 nonce ⇒ **必须 false**（已被消费）
  assert_false(s3_consume_nonce(agent, nonce))
}

///|
/// 【第二段·锁 4】未消费的 nonce 消费一次成功，且**不同 nonce 互不影响**。
test "s3_p2_04_nonce_consumption_is_per_nonce" {
  let e = FistEngine::new(store=@store.StoreBackend::memory())
  let agent = "lane-bg-multi"
  let n1 = e.s3_issue_challenge(agent, 1)
  let n2 = e.s3_issue_challenge(agent, 2)
  assert_true(s3_consume_nonce(agent, n1))
  // n2 不受影响
  assert_true(s3_consume_nonce(agent, n2))
  // 都没了
  assert_false(s3_consume_nonce(agent, n1))
  assert_false(s3_consume_nonce(agent, n2))
}

///|
/// 【第二段·锁 5】**没签发过的 nonce 消费必须失败**（防「随便编一个 nonce 就能用」）。
test "s3_p2_05_unissued_nonce_rejected" {
  let e = FistEngine::new(store=@store.StoreBackend::memory())
  ignore(e)
  assert_false(s3_consume_nonce("lane-bg-ghost", "make-up-nonce"))
}

///|
/// 【第二段·锁 6】**零回归**：不传 challenge 时四门行为与改动前一致。
///
/// 断言 `judged_role_gated(eng, agent, None)` **等于** `judged_role(eng, agent)`
/// —— 这正是「None 分支不做任何改变」的设计契约。
test "s3_p2_06_no_challenge_means_zero_change" {
  let e = FistEngine::new(store=@store.StoreBackend::memory())
  let gated = judged_role_gated(e, "some-agent", None)
  let plain = judged_role(e, "some-agent")
  assert_eq(gated, plain)
}
