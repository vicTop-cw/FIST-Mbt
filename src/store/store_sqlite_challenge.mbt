///|
/// ══════════════════════════════════════════════════════════════════════════
/// BUG-466：S3 challenge nonce **落库**（agent_challenges 表）。
///
/// ## 为什么必须落库
///
/// 此前 nonce 存进程内 `s3_pending_nonces : Map[...]`（`engine_rsv.mbt:229`），
/// 代价是**跨进程不共享** ⇒ 多实例部署时：
///   A 进程 `agent_issue_challenge` 签发票 → 客户端拿票去请求
///   → 负载均衡打到 B 进程 → **B 的 Map 里没有这张票** → `challenge_replayed`（误判重放）
/// ⇒ **不是「功能弱一点」，是「部署即不可用」**。
/// Alpha 连续三轮报这条 R1 风险，本表让它从「既有限制」变成「已解决」。
///
/// ## 三个操作
///
/// · `issue`：INSERT OR IGNORE（**幂等**：同 nonce 重复签发不报错、不覆盖 issued_at）
/// · `consume`：`UPDATE ... SET consumed=1 WHERE ... AND consumed=0` + **判 changes()**
///   ⇒ **原子一次性消费**（并发下只有一个 UPDATE 能改到行，其余 rowcount=0）
/// · `cleanup`：删「已消费」或「签发早于 cutoff」的行 ⇒ 防无限增长
///
/// ## 为什么 `consumed` 用标记而不是删行
///
/// 删行后**无法区分「从未签发」与「已消费」** —— 前者应报 `challenge_replayed`（未知票），
/// 后者也应报，但审计上要能看出「这张票被用过」。更关键：并发下
/// `DELETE ... WHERE nonce=?` 若删到 0 行，无法判断是「不存在」还是「已被别人删掉」；
/// 而 `UPDATE ... WHERE consumed=0` 的 rowcount 精确表达「**我是那个把它从 0 变 1 的人**」。
/// ══════════════════════════════════════════════════════════════════════════
///

///|
/// 签发一张 challenge（落库）。`INSERT OR IGNORE` ⇒ 重复签发同 nonce 幂等。
pub fn SqliteStore::challenge_issue(
  self : SqliteStore,
  ns : String,
  agent_fp : String,
  nonce : String,
  issued_at : String,
) -> Result[Unit, String] {
  match self.db {
    None => Err("sqlite store 未打开")
    Some(db) => {
      let sql = "INSERT OR IGNORE INTO agent_challenges (ns, agent_fp, nonce, issued_at, consumed) VALUES (?, ?, ?, ?, 0)"
      match db.prepare(sql) {
        None => Err("sqlite prepare 失败: challenge_issue")
        Some(stmt) => {
          ignore(
            stmt.bind(1, @sqlite.SqlValue::Text(@encoding.encode(UTF8, ns))),
          )
          ignore(
            stmt.bind(
              2,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, agent_fp)),
            ),
          )
          ignore(
            stmt.bind(3, @sqlite.SqlValue::Text(@encoding.encode(UTF8, nonce))),
          )
          ignore(
            stmt.bind(
              4,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, issued_at)),
            ),
          )
          // ⚠️ **必须用 `execute()` 而不是 `step()`**：
          //   `Statement::step()` 返回「有没有下一行结果」——INSERT/UPDATE/DELETE
          //   **没有结果行** ⇒ step() 恒 false ⇒ 会被误判成「执行失败」。
          //   （实测：用它时表里插得进数据，但函数返回 Err、consume 恒 false。）
          let ok = stmt.execute()
          stmt.finalize()
          if ok {
            Ok(())
          } else {
            Err("sqlite execute 失败: challenge_issue")
          }
        }
      }
    }
  }
}

///|
/// **原子一次性消费**：把未消费的那张票标成已消费。
///
/// 返回 `true` ⇔ **本次调用**把它从 `consumed=0` 改成 `1`（并发下只有一个调用能看到 true）。
/// 返回 `false` ⇒ 票不存在 / 已被消费 / 不属于该 agent —— 三种情况**都按重放处理**（fail-closed）。
///
/// 判据是 `Database::changes()`（受影响行数），**不是**先 SELECT 再 UPDATE
/// （那是先读后写，两个并发请求会都读到 0 然后都更新成功 ⇒ 一次性失效）。
pub fn SqliteStore::challenge_consume(
  self : SqliteStore,
  ns : String,
  agent_fp : String,
  nonce : String,
) -> Bool {
  match self.db {
    None => false
    Some(db) => {
      let sql = "UPDATE agent_challenges SET consumed = 1 WHERE ns = ? AND agent_fp = ? AND nonce = ? AND consumed = 0"
      match db.prepare(sql) {
        None => false
        Some(stmt) => {
          ignore(
            stmt.bind(1, @sqlite.SqlValue::Text(@encoding.encode(UTF8, ns))),
          )
          ignore(
            stmt.bind(
              2,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, agent_fp)),
            ),
          )
          ignore(
            stmt.bind(3, @sqlite.SqlValue::Text(@encoding.encode(UTF8, nonce))),
          )
          // ⚠️ UPDATE 无结果行 ⇒ 必须 `execute()`（见 challenge_issue 的长注释）。
          let ok = stmt.execute()
          stmt.finalize()
          if !ok {
            return false
          }
          db.changes() > 0
        }
      }
    }
  }
}

///|
/// 清理：删「已消费」或「签发时间早于 `cutoff`」的行。
///
/// 为什么用 ISO 字符串直接比：本仓时间戳一律 `YYYY-MM-DDTHH:MM:SSZ`（定宽）⇒ **字典序 == 时间序**
/// （与 `assistant_claim_action` 的 cutoff 同口径）。
///
/// 返回删除行数。**未消费但已过 cutoff 的票也删** —— 它已过期，留着只会让表无限增长。
pub fn SqliteStore::challenge_cleanup(
  self : SqliteStore,
  cutoff : String,
) -> Int32 {
  match self.db {
    None => 0
    Some(db) => {
      let sql = "DELETE FROM agent_challenges WHERE consumed = 1 OR issued_at < ?"
      match db.prepare(sql) {
        None => 0
        Some(stmt) => {
          ignore(
            stmt.bind(1, @sqlite.SqlValue::Text(@encoding.encode(UTF8, cutoff))),
          )
          // ⚠️ DELETE 无结果行 ⇒ 必须 `execute()`。
          let ok = stmt.execute()
          stmt.finalize()
          if !ok {
            return 0
          }
          db.changes()
        }
      }
    }
  }
}

///|
/// 只读诊断：某 agent 在 ns 下**未消费**的票数（供白盒锁断言「签发后 +1、消费后 -1」）。
pub fn SqliteStore::challenge_pending_count(
  self : SqliteStore,
  ns : String,
  agent_fp : String,
) -> Int32 {
  match self.db {
    None => 0
    Some(db) => {
      let sql = "SELECT COUNT(*) FROM agent_challenges WHERE ns = ? AND agent_fp = ? AND consumed = 0"
      match db.prepare(sql) {
        None => 0
        Some(stmt) => {
          ignore(
            stmt.bind(1, @sqlite.SqlValue::Text(@encoding.encode(UTF8, ns))),
          )
          ignore(
            stmt.bind(
              2,
              @sqlite.SqlValue::Text(@encoding.encode(UTF8, agent_fp)),
            ),
          )
          let mut n = 0
          if stmt.step() {
            n = stmt.column_int(0)
          }
          stmt.finalize()
          n
        }
      }
    }
  }
}
