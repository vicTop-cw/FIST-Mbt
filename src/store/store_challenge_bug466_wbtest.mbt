///|
/// BUG-466 白盒锁：challenge nonce **落库 + 跨进程可消费**。
///
/// ## 病灶
///
/// 此前 nonce 只存在模块级 `s3_pending_nonces : Map[...]`（进程内）⇒ 多实例部署时：
///   A 进程签发 → 客户端拿票去请求 → 负载均衡打到 B 进程 → **B 的 Map 里没有**
///   ⇒ `challenge_replayed`（把「有效票」误判成「重放」）⇒ **部署即不可用**。
///
/// ## 本文件四类锁
///
/// · **L1 落库**：SQLite 后端签发后，**另一个 SqliteStore 实例**（模拟另一进程，
///   同一个 db 文件）能消费成功 ⇒ 证明票在**库里**而不是在内存里。
/// · **L2 一次性**：同一实例消费两次 ⇒ 第二次 false；
///   跨实例消费两次 ⇒ 第二次也 false。
/// · **L3 内存后端**：真实现（不是占位），且 `challenge_persisted()` **如实报 false**。
/// · **L4 变异对照**：把 `challenge_consume` 改成「永远 true」⇒ L2 必红。
///
/// ⚠️ 判例-31：跨进程用**两个独立 SqliteStore 实例指向同一个 db 文件**做确定性模拟，
/// **不用 sleep 抢时序** —— 两个实例的先后关系是确定的。

///|
/// 造一个临时的 sqlite 库路径（每用例唯一，不共享）。
fn c466_db(tag : String) -> String {
  bug462_unique_db(tag)
}

///|
/// 【L1 · 落库】A 实例签发 ⇒ **B 实例**（同一 db 文件、独立句柄）消费成功。
///
/// 这是本单的核心断言：票必须在**库里**，否则跨进程消费不掉。
/// 两个 `SqliteStore` 是**独立句柄**，模拟两个进程各自打开同一个 db ——
/// 与「进程内 Map」的区别正在于此：内存 Map 只有签发它的那个实例能看到。
test "c466_l1_nonce_issued_in_one_store_is_consumable_in_another" {
  let db = c466_db("l1")
  let ns = "ns-l1"
  let agent_fp = "fp-agent-l1"
  let nonce = "nonce-l1-0001"
  // A 实例：签发
  match SqliteStore::open(db) {
    None => abort("c466-L1: A 实例打不开库 " + db)
    Some(a) => {
      match a.challenge_issue(ns, agent_fp, nonce, "2026-10-28T00:00:00Z") {
        Err(e) => abort("c466-L1: 签发失败 " + e)
        Ok(_) => ()
      }
      assert_eq(a.challenge_pending_count(ns, agent_fp), 1)
      // ⚠️ 此处**不关闭** a：B 实例要在 a 仍持有句柄时打开同一文件，
      //    这才是真实的「两个进程同时连着同一个库」。
      // B 实例：消费（独立句柄）
      match SqliteStore::open(db) {
        None => abort("c466-L1: B 实例打不开同一个库")
        Some(b) => {
          let consumed = b.challenge_consume(ns, agent_fp, nonce)
          if !consumed {
            abort(
              "c466-L1 **跨实例消费失败** —— 票只活在本进程内存里（BUG-466 原状）",
            )
          }
          // B 看到的是「已消费」，A 也应看到（同一个库）
          assert_eq(b.challenge_pending_count(ns, agent_fp), 0)
          assert_eq(a.challenge_pending_count(ns, agent_fp), 0)
          b.close()
        }
      }
      a.close()
    }
  }
}

///|
/// 【L2a · 一次性 · 同一实例】消费两次 ⇒ 第二次 false。
test "c466_l2a_same_store_second_consume_is_false" {
  let db = c466_db("l2a")
  match SqliteStore::open(db) {
    None => abort("c466-L2a: 打不开库")
    Some(s) => {
      match s.challenge_issue("ns", "fp", "n1", "2026-10-28T00:00:00Z") {
        Err(e) => abort("c466-L2a: 签发失败 " + e)
        Ok(_) => ()
      }
      assert_true(s.challenge_consume("ns", "fp", "n1"))
      assert_false(s.challenge_consume("ns", "fp", "n1"))
      s.close()
    }
  }
}

///|
/// 【L2b · 一次性 · 跨实例】A 签发+B 消费 ⇒ 再来一个 C 实例消费**同一张票** ⇒ false。
///
/// 这条比 L2a 更关键：它证明「一次性」是**库级**的，不是「某个实例的内存状态」。
test "c466_l2b_cross_store_replay_is_rejected" {
  let db = c466_db("l2b")
  let ns = "ns-l2b"
  let fp = "fp-l2b"
  let nonce = "n-l2b-1"
  // A 签发
  match SqliteStore::open(db) {
    None => abort("c466-L2b: A 打不开")
    Some(a) => {
      ignore(a.challenge_issue(ns, fp, nonce, "2026-10-28T00:00:00Z"))
      a.close()
    }
  }
  // B 消费（成功）
  match SqliteStore::open(db) {
    None => abort("c466-L2b: B 打不开")
    Some(b) => {
      assert_true(b.challenge_consume(ns, fp, nonce))
      b.close()
    }
  }
  // C 重放（必须 false）
  match SqliteStore::open(db) {
    None => abort("c466-L2b: C 打不开")
    Some(c) => {
      if c.challenge_consume(ns, fp, nonce) {
        abort("c466-L2b **重放被接受** —— 一次性消费没跨进程生效")
      }
      c.close()
    }
  }
}

///|
/// 【L2c · 未签发的票】消费一个从没签发过的 nonce ⇒ false（fail-closed）。
test "c466_l2c_unknown_nonce_is_rejected" {
  let db = c466_db("l2c")
  match SqliteStore::open(db) {
    None => abort("c466-L2c: 打不开")
    Some(s) => {
      assert_false(s.challenge_consume("ns", "fp", "never-issued"))
      s.close()
    }
  }
}

///|
/// 【L2d · ns 隔离】在 ns-A 签发的票，在 ns-B 消费不掉。
///
/// 为什么必须锁：`agent_challenges` 的主键含 `ns`。若有人漏了 `ns` 条件，
/// 一张票就能跨命名空间复用 —— 那是 S3 上的横向越权。
test "c466_l2d_nonce_is_namespace_isolated" {
  let db = c466_db("l2d")
  let fp = "fp-l2d"
  match SqliteStore::open(db) {
    None => abort("c466-L2d: 打不开")
    Some(s) => {
      ignore(s.challenge_issue("ns-A", fp, "n-shared", "2026-10-28T00:00:00Z"))
      // 在 ns-B 消费同一 nonce ⇒ 必须 false
      if s.challenge_consume("ns-B", fp, "n-shared") {
        abort("c466-L2d **跨 ns 复用成功** —— 主键的 ns 条件失效")
      }
      // 在 ns-A 消费 ⇒ 成功（证明票本身是好的，只是隔离生效）
      assert_true(s.challenge_consume("ns-A", fp, "n-shared"))
      s.close()
    }
  }
}

///|
/// 【L3 · 内存后端】真实现（不是占位），且 `challenge_persisted()` **如实报 false**。
///
/// 判例-35：内存后端「弃用 ≠ 无害」。这里既不占位（真读写），也不假装跨进程
/// （`persisted=false` 如实披露），两条都做。
test "c466_l3_memory_backend_is_real_and_discloses_non_persistence" {
  let st = StoreBackend::memory()
  // ① 真实现：签发后能查到、能消费、二次消费 false（与 SQLite 同语义）
  ignore(st.challenge_issue("ns", "fp", "m1", "2026-10-28T00:00:00Z"))
  assert_eq(st.challenge_pending_count("ns", "fp"), 1)
  assert_true(st.challenge_consume("ns", "fp", "m1"))
  assert_false(st.challenge_consume("ns", "fp", "m1"))
  assert_eq(st.challenge_pending_count("ns", "fp"), 0)
  // ② 如实披露：内存后端不持久化
  assert_false(st.challenge_persisted())
  // ③ 对照：SQLite 后端报 true
  let db = c466_db("l3sql")
  match SqliteStore::open(db) {
    None => abort("c466-L3: sqlite 打不开")
    Some(s) => {
      let sql = StoreBackend::sqlite(s)
      assert_true(sql.challenge_persisted())
      s.close()
    }
  }
}

///|
/// 【L5 · 清理】`challenge_cleanup` 删已消费的 + 早于 cutoff 的，保留新鲜的。
test "c466_l5_cleanup_removes_consumed_and_expired" {
  let db = c466_db("l5")
  let ns = "ns-l5"
  let fp = "fp-l5"
  match SqliteStore::open(db) {
    None => abort("c466-L5: 打不开")
    Some(s) => {
      // 三张票：已消费 / 过期未消费 / 新鲜未消费
      ignore(s.challenge_issue(ns, fp, "consumed", "2026-10-28T00:00:00Z"))
      let _ = s.challenge_consume(ns, fp, "consumed")
      ignore(s.challenge_issue(ns, fp, "expired", "2020-01-01T00:00:00Z"))
      ignore(s.challenge_issue(ns, fp, "fresh", "2026-10-28T00:00:00Z"))
      let deleted = s.challenge_cleanup("2026-10-01T00:00:00Z")
      // 删了 consumed + expired 两张
      assert_eq(deleted, 2)
      // 新鲜的还剩一张
      assert_eq(s.challenge_pending_count(ns, fp), 1)
      s.close()
    }
  }
}
