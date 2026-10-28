///|
/// ══════════════════════════════════════════════════════════════════════════
/// BUG-467：challenge 表的**清理策略**（分两档，默认保守）。
///
/// ## 为什么清理策略现在是「两档」而不是一个 cutoff
///
/// 旧实现 `DELETE ... WHERE consumed = 1 OR issued_at < ?` **无条件删所有已消费的票** ——
/// 哪怕它 1 秒前刚被用掉。这带来两个问题：
///   1. **审计证据丢失**：`consumed=1` 是「这张票被用过」的**唯一记录**，
///      删掉后就无法回答「这个 agent 什么时候用过票」。
///   2. **与「为什么用标记而非删行」的设计自相矛盾**（见 `store_sqlite_challenge.mbt:21`）：
///      当初留标记就是为了审计，结果清理时又把它删了。
///
/// ⇒ 现在分两档：
///   · **保守档 `cleanup_conservative`（默认）**：只删**签发早于 cutoff** 的行
///     （无论消费与否）。⇒ 保留 cutoff 之内的全部审计证据，且表仍受时间上界约束。
///   · **激进档 `cleanup_aggressive`**：额外删掉**已消费**的行（连审计一起丢）。
///     只在确实需要压表大小时用。
///
/// ## 为什么默认 24h
///
/// · challenge 的生命周期是「签发 → 立即签 → 立即提交」，**分钟级**；
/// · 但调用方可能重试/排队 ⇒ 给足容错窗口；
/// · 24h 之后未消费的票**事实上已无用处**（调用方拿不到它了），删掉不影响正确性。
/// ⇒ 24h 是「够安全 + 够回收」的交点。
///
/// ## ⚠️ 删「过期未消费」的票 = 那些票作废 —— 可接受吗？
///
/// **可接受**，理由：
/// 1. 本仓 challenge **没有 TTL 强制语义**（`expires_hint` 只是回执里的提示字符串），
///    「过期」完全是清理侧的定义 ⇒ 24h 是**保守**值，不是紧箍咒；
/// 2. 未消费的票**只对签发它的调用方有用**，而调用方拿票后立刻签、立刻提交 ⇒
///    超过 24h 还没用的票，调用方**早就放弃了**；
/// 3. 万一真有人在 24h 后拿旧票来用 ⇒ `challenge_consume` 返回 `false`
///    ⇒ 走 fail-closed 的 `challenge_failed` 路径（**不是放行**）。
/// **⇒ 作废的票只会让本来就会失败的请求继续失败，不会让它们意外成功。**
/// ══════════════════════════════════════════════════════════════════════════
///

///|
/// **保守档（默认）**：删「签发早于 cutoff」的行，**不管有没有消费**。
///
/// 保留 cutoff 之内的全部审计证据；表仍受「签发时间上界」约束而不会无限增长。
pub fn SqliteStore::challenge_cleanup_conservative(
  self : SqliteStore,
  cutoff : String,
) -> Int32 {
  match self.db {
    None => 0
    Some(db) => {
      let sql = "DELETE FROM agent_challenges WHERE issued_at < ?"
      match db.prepare(sql) {
        None => 0
        Some(stmt) => {
          ignore(
            stmt.bind(1, @sqlite.SqlValue::Text(@encoding.encode(UTF8, cutoff))),
          )
          // ⚠️ DELETE 无结果行 ⇒ 必须 `execute()`（`step()` 恒 false）。
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
/// **激进档**：额外删掉**已消费**的行（**审计证据一并丢失**）。
///
/// 只在表确实需要压缩时用。⚠️ 用这一档要接受「查不到历史票的使用记录」。
pub fn SqliteStore::challenge_cleanup_aggressive(
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
/// 只读诊断：表**总行数**（让「表在长」可见）。供回执与白盒锁用。
pub fn SqliteStore::challenge_total_count(self : SqliteStore) -> Int32 {
  match self.db {
    None => 0
    Some(db) => {
      let sql = "SELECT COUNT(*) FROM agent_challenges"
      match db.prepare(sql) {
        None => 0
        Some(stmt) => {
          let mut n : Int32 = 0
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

///|
/// 只读诊断：**已消费**的票数。
pub fn SqliteStore::challenge_consumed_count(self : SqliteStore) -> Int32 {
  match self.db {
    None => 0
    Some(db) => {
      let sql = "SELECT COUNT(*) FROM agent_challenges WHERE consumed = 1"
      match db.prepare(sql) {
        None => 0
        Some(stmt) => {
          let mut n : Int32 = 0
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
