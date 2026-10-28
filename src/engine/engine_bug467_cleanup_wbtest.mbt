///|
/// BUG-467 引擎侧锁：清理的**接线**与**可观测性**。
///
/// 为什么这两格在 engine 包而不是 store 包：它们要用 `FistEngine`
/// （store 包不能反向依赖 engine）。而 C1~C3（清理策略本身）在 store 包——
/// 那一层不需要 engine，**分层对**。

///|
/// 【C4】表大小可观测：`challenge_table_stats` 的 (total, consumed, pending) 如实。
test "c467_c4_table_stats_are_observable" {
  let e = FistEngine::new(store=@store.StoreBackend::memory())
  // 空表
  let (t0, c0, p0) = e.challenge_table_stats()
  assert_eq(t0, 0)
  assert_eq(c0, 0)
  assert_eq(p0, 0)
  // 签两张、消费一张
  let n1 = e.s3_issue_challenge(
    "agent-c4",
    9001,
    ns="ns-c4",
    issued_at="2026-10-28T00:00:00Z",
  )
  let _n2 = e.s3_issue_challenge(
    "agent-c4",
    9002,
    ns="ns-c4",
    issued_at="2026-10-28T00:00:00Z",
  )
  assert_true(e.s3_consume_nonce("agent-c4", n1, ns="ns-c4"))
  let (t1, c1, p1) = e.challenge_table_stats()
  assert_eq(t1, 2)
  assert_eq(c1, 1)
  assert_eq(p1, 1)
}

///|
/// 【C5】**签发时顺带清理**真的接上了（判例-29：机制格 ≠ 实现路径格）。
///
/// 只测 `challenge_cleanup_conservative` 本身对，证明不了它被**接线**了。
/// 这一格走真实签发路径：先塞一张过期票，再签发一张新票（带 cleanup_cutoff），
/// 断言过期票**被顺带清掉了**。
test "c467_c5_cleanup_is_wired_into_issue" {
  let e = FistEngine::new(store=@store.StoreBackend::memory())
  // 手工塞一张过期票（确定性注入时间戳，不用 sleep）
  ignore(
    e.store.challenge_issue("ns-c5", "fp-c5", "ancient", "2020-01-01T00:00:00Z"),
  )
  let (before, _c, _p) = e.challenge_table_stats()
  assert_eq(before, 1)
  // 走真实签发路径，带 cleanup_cutoff（2050 ⇒ 清掉 2020 那张）
  ignore(
    e.s3_issue_challenge(
      "agent-c5",
      9100,
      ns="ns-c5",
      issued_at="2099-01-01T00:00:00Z",
      cleanup_cutoff="2050-01-01T00:00:00Z",
    ),
  )
  // 断言：过期那张被顺带清掉 ⇒ 总数仍是 1（只剩新签的）
  let (after, _c2, _p2) = e.challenge_table_stats()
  if after != 1 {
    abort(
      "c467-C5 **签发时清理没接上** —— 过期票仍在（总数 " +
      after.to_string() +
      "，期望 1）",
    )
  }
}
