///|
/// BUG-467 白盒锁：challenge 表的**清理策略**。
///
/// ## 病灶
///
/// `challenge_cleanup` 从 BUG-466 起就存在，但**从来没有任何调用点** ——
/// 表随签发量**只增不减**。一张只增不减的表在生产上是定时炸弹：
/// 它不会马上出事，但会在某个时刻出事。
///
/// ## 本文件四类锁
///
/// · **C1 清理真删**：过期票被删，**新鲜票留下**
/// · **C2 未过期票仍可用**（硬要求 ②）：清完之后，未过期的票**仍能消费成功**
/// · **C3 保守 vs 激进**：保守档保留已消费的审计证据；激进档丢掉
/// · **C4 可观测**：`challenge_table_stats` 的三个数如实反映表状态
///
/// ⚠️ 判例-31：**不用 sleep**。过期与否由**确定性注入的 `issued_at`** 决定
/// （显式给 `2020-01-01` 与 `2099-01-01` 两种时间戳），不依赖真实时钟。

///|
/// 【C1】清理真删：`issued_at` 早于 cutoff 的票被删，晚于的留下。
///
/// **确定性注入**：两张票的时间戳分别是 `2020-01-01`（很早）与 `2099-01-01`（很晚），
/// cutoff 取 `2050-01-01` ⇒ 前者必删、后者必留。**与真实时钟无关。**
test "c467_c1_cleanup_deletes_expired_keeps_fresh" {
  let db = bug462_unique_db("c467c1")
  let ns = "ns-c1"
  let fp = "fp-c1"
  match SqliteStore::open(db) {
    None => abort("c467-C1: 打不开库")
    Some(s) => {
      // 一张「过期」（2020）、一张「新鲜」（2099）
      ignore(s.challenge_issue(ns, fp, "old-ticket", "2020-01-01T00:00:00Z"))
      ignore(s.challenge_issue(ns, fp, "new-ticket", "2099-01-01T00:00:00Z"))
      assert_eq(s.challenge_total_count(), 2)
      // 清理 cutoff = 2050 ⇒ 只应删掉 old-ticket
      let deleted = s.challenge_cleanup_conservative("2050-01-01T00:00:00Z")
      if deleted != 1 {
        abort(
          "c467-C1 应删 1 行（过期那张），实际 " +
          deleted.to_string(),
        )
      }
      // 总数剩 1，且它必须是新的那张
      assert_eq(s.challenge_total_count(), 1)
      assert_eq(s.challenge_pending_count(ns, fp), 1)
      s.close()
    }
  }
}

///|
/// 【C2 · 硬要求 ②】**清完之后未过期的票仍然能消费**。
///
/// 这是清理最重要的安全属性：清理**不许**误伤仍然有效的票。
test "c467_c2_cleanup_does_not_break_unexpired_tickets" {
  let db = bug462_unique_db("c467c2")
  let ns = "ns-c2"
  let fp = "fp-c2"
  match SqliteStore::open(db) {
    None => abort("c467-C2: 打不开库")
    Some(s) => {
      ignore(s.challenge_issue(ns, fp, "stale", "2020-01-01T00:00:00Z"))
      ignore(s.challenge_issue(ns, fp, "live", "2099-01-01T00:00:00Z"))
      // 清掉过期的
      ignore(s.challenge_cleanup_conservative("2050-01-01T00:00:00Z"))
      // 核心断言：未过期那张**仍能消费成功**
      if !s.challenge_consume(ns, fp, "live") {
        abort(
          "c467-C2 **清理误伤了未过期的票** —— 清完之后它消费不了",
        )
      }
      // 过期那张已不在 ⇒ 消费必须 false（fail-closed，不是放行）
      assert_false(s.challenge_consume(ns, fp, "stale"))
      s.close()
    }
  }
}

///|
/// 【C3】保守档**保留**已消费的审计证据；激进档**丢掉**。
///
/// 为什么这条重要：`consumed=1` 是「这张票被用过」的**唯一记录**。
/// 旧实现（`consumed = 1 OR issued_at < ?`）无条件删它 ——
/// 与「为什么用标记而非删行」的设计自相矛盾。
test "c467_c3_conservative_keeps_audit_aggressive_drops" {
  let db = bug462_unique_db("c467c3")
  let ns = "ns-c3"
  let fp = "fp-c3"
  match SqliteStore::open(db) {
    None => abort("c467-C3: 打不开库")
    Some(s) => {
      // 一张新鲜的、已消费的票
      ignore(s.challenge_issue(ns, fp, "used", "2099-01-01T00:00:00Z"))
      assert_true(s.challenge_consume(ns, fp, "used"))
      assert_eq(s.challenge_consumed_count(), 1)
      // 保守档：cutoff 2050 ⇒ 这张票「新鲜」⇒ **不许删**
      let d1 = s.challenge_cleanup_conservative("2050-01-01T00:00:00Z")
      if d1 != 0 {
        abort(
          "c467-C3 保守档不该删新鲜的已消费票，实际删了 " +
          d1.to_string(),
        )
      }
      assert_eq(s.challenge_consumed_count(), 1)
      // 激进档：即使新鲜，已消费也删
      let d2 = s.challenge_cleanup_aggressive("2050-01-01T00:00:00Z")
      if d2 != 1 {
        abort("c467-C3 激进档应删 1 行，实际删 " + d2.to_string())
      }
      assert_eq(s.challenge_consumed_count(), 0)
      assert_eq(s.challenge_total_count(), 0)
      s.close()
    }
  }
}
