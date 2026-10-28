///|
/// ══════════════════════════════════════════════════════════════════════════
/// BUG-466：challenge 的 **StoreBackend 分发**（内存真实现 + SQLite 落库）。
///
/// ## 与 BUG-439/441 的对照（这是本文件要避免的形态）
///
/// BUG-439（熔断器）与 BUG-441（saga）的病灶都是：**内存后端返回占位值**
/// （`None` / `Ok(())` / `[]`），而占位值是合法值 ⇒ 工具不报错、回执齐全、**功能从未生效**。
///
/// 这里**不重复那个错误**：内存后端**真实读写** `MemoryStore.challenges`。
/// 但内存后端的 nonce **跨不了进程**（它就在本进程内存里）——
/// **这一点由 `challenge_persisted()` 如实披露**，让调用面看得见。
///
/// ## 为什么 `persisted` 要单独一个函数
///
/// 「有没有真的落库」是**部署属性**，不是调用参数：同一个工具在内存后端跑出来的
/// `+challenge_verified` 与在 SQLite 后端跑出来的**可信度不同**（前者换进程就失效）。
/// 调用方拿到 `challenge_persisted=false` 就知道「这次验签只在本次进程生命周期内成立」。
/// ══════════════════════════════════════════════════════════════════════════
///
///|
/// 后端是否**真正持久化**了 challenge（`true` = SQLite 落库、跨进程可见；
/// `false` = 内存后端，只在本次进程生命周期内有效）。
pub fn StoreBackend::challenge_persisted(self : StoreBackend) -> Bool {
  match self {
    Mem(_) => false
    Sql(_) => true
  }
}

///|
/// 签发一张 challenge（两个后端**都真写**）。
pub fn StoreBackend::challenge_issue(
  self : StoreBackend,
  ns : String,
  agent_fp : String,
  nonce : String,
  issued_at : String,
) -> Result[Unit, String] {
  match self {
    Mem(m) => {
      // 真写内存 Map（**不是占位**）。幂等：已存在则不覆盖 issued_at。
      let k = challenge_key(ns, agent_fp, nonce)
      if m.challenges.contains(k) {
        Ok(())
      } else {
        m.challenges.set(k, (issued_at, false))
        Ok(())
      }
    }
    Sql(s) => s.challenge_issue(ns, agent_fp, nonce, issued_at)
  }
}

///|
/// **原子一次性消费**（两个后端同语义：返回 `true` ⇔ 本次调用把它从「未消费」变成「已消费」）。
pub fn StoreBackend::challenge_consume(
  self : StoreBackend,
  ns : String,
  agent_fp : String,
  nonce : String,
) -> Bool {
  match self {
    Mem(m) => {
      let k = challenge_key(ns, agent_fp, nonce)
      match m.challenges.get(k) {
        None => false
        Some((issued_at, consumed)) =>
          if consumed {
            false
          } else {
            m.challenges.set(k, (issued_at, true))
            true
          }
      }
    }
    Sql(s) => s.challenge_consume(ns, agent_fp, nonce)
  }
}

///|
/// 清理过期/已消费的 challenge，返回删除行数。
pub fn StoreBackend::challenge_cleanup(
  self : StoreBackend,
  cutoff : String,
) -> Int32 {
  match self {
    Mem(m) => {
      let keys : Array[String] = []
      m.challenges.each(fn(k, v) {
        let (issued_at, consumed) = v
        if consumed || issued_at < cutoff {
          keys.push(k)
        }
      })
      let mut n : Int32 = 0
      for k in keys {
        m.challenges.remove(k)
        n = n + 1
      }
      n
    }
    Sql(s) => s.challenge_cleanup(cutoff)
  }
}

///|
/// BUG-467：**保守档清理（默认推荐）** —— 只删「签发早于 cutoff」的行，**不管消费与否**。
///
/// 与激进档 `challenge_cleanup` 的差别：这一档**保留 cutoff 之内的审计证据**
/// （`consumed=1` 是「这张票被用过」的唯一记录）。表仍受「签发时间上界」约束不会无限长。
pub fn StoreBackend::challenge_cleanup_conservative(
  self : StoreBackend,
  cutoff : String,
) -> Int32 {
  match self {
    Mem(m) => {
      let keys : Array[String] = []
      m.challenges.each(fn(k, v) {
        let (issued_at, _consumed) = v
        if issued_at < cutoff {
          keys.push(k)
        }
      })
      let mut n : Int32 = 0
      for k in keys {
        m.challenges.remove(k)
        n = n + 1
      }
      n
    }
    Sql(s) => s.challenge_cleanup_conservative(cutoff)
  }
}

///|
/// BUG-467：**激进档清理** —— 额外删已消费的行（**审计证据一并丢失**）。
pub fn StoreBackend::challenge_cleanup_aggressive(
  self : StoreBackend,
  cutoff : String,
) -> Int32 {
  match self {
    Mem(m) => {
      let keys : Array[String] = []
      m.challenges.each(fn(k, v) {
        let (issued_at, consumed) = v
        if consumed || issued_at < cutoff {
          keys.push(k)
        }
      })
      let mut n : Int32 = 0
      for k in keys {
        m.challenges.remove(k)
        n = n + 1
      }
      n
    }
    Sql(s) => s.challenge_cleanup_aggressive(cutoff)
  }
}

///|
/// BUG-467：表**总行数**（让「表在长」可观测）。
pub fn StoreBackend::challenge_total_count(self : StoreBackend) -> Int32 {
  match self {
    Mem(m) => {
      let mut n : Int32 = 0
      m.challenges.each(fn(_k, _v) { n = n + 1 })
      n
    }
    Sql(s) => s.challenge_total_count()
  }
}

///|
/// BUG-467：**已消费**的票数。
pub fn StoreBackend::challenge_consumed_count(self : StoreBackend) -> Int32 {
  match self {
    Mem(m) => {
      let mut n : Int32 = 0
      m.challenges.each(fn(_k, v) {
        let (_issued, consumed) = v
        if consumed {
          n = n + 1
        }
      })
      n
    }
    Sql(s) => s.challenge_consumed_count()
  }
}

///|
/// 只读诊断：某 agent 在 ns 下**未消费**的票数。
pub fn StoreBackend::challenge_pending_count(
  self : StoreBackend,
  ns : String,
  agent_fp : String,
) -> Int32 {
  match self {
    Mem(m) => {
      let mut n : Int32 = 0
      m.challenges.each(fn(k, v) {
        let (_issued, consumed) = v
        let prefix = challenge_prefix(ns, agent_fp)
        if !consumed && k.has_prefix(prefix) {
          n = n + 1
        }
      })
      n
    }
    Sql(s) => s.challenge_pending_count(ns, agent_fp)
  }
}

///|
/// `challenge_key` 的前缀（用于内存后端按 (ns, agent_fp) 过滤）。
fn challenge_prefix(ns : String, agent_fp : String) -> String {
  ns + "\u{0}" + agent_fp + "\u{0}"
}
