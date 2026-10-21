/// store/store_rsv.mbt —— 作用域预订（拿来主义：Interlinked 文件预订 → 多 agent 并发编辑冲突预防）
///
/// 让多个 AI 客户端（并发 agent）在同一命名空间/工作区协作时，可对文件/目录/资源"作用域"
/// 做轻量预订：预订在 TTL 内独占，其他 agent `reserve_check` 会被告知持有者，避免同时改同一文件。
/// 双后端（内存 + SQLite）一致，供 server 工具调用。

///|
/// 内存后端：写入/覆盖某作用域预订。（返回值约定：Ok(msg)，不使用）
pub fn MemoryStore::rsv_set(
  self : MemoryStore,
  scope~ : String,
  agent~ : String,
  ttl_until~ : String,
  created_at~ : String,
) -> Result[String, String] {
  self.reservations.set(scope, (agent, ttl_until, created_at))
  Ok("reserved")
}

///|
/// 内存后端：查询某作用域预订（未预订返回 None）。
pub fn MemoryStore::rsv_get(
  self : MemoryStore,
  scope : String,
) -> (String, String, String)? {
  self.reservations.get(scope)
}

///|
/// 内存后端：释放预订（仅持有者可释放；不存在或非持有者返回 false）。
pub fn MemoryStore::rsv_release(
  self : MemoryStore,
  scope : String,
  agent : String,
) -> Bool {
  match self.reservations.get(scope) {
    Some((a, _, _)) if a == agent => {
      self.reservations.remove(scope)
      true
    }
    _ => false
  }
}

///|
/// 内存后端：列出全部预订（升序，无指定顺序保证）。
pub fn MemoryStore::rsv_list(
  self : MemoryStore,
) -> Array[(String, String, String)] {
  let out : Array[(String, String, String)] = []
  for (_, v) in self.reservations {
    out.push(v)
  }
  out
}

// —— BUG-136：跨进程裁决的预订（rsv_try_*）——

///|
/// 预订裁决结果。`agent`/`ttl_until` 一律是**库里现值**（conflict 时即 held_by），
/// 不是调用方想要的那个值——回执不许由请求反推。
pub struct RsvOutcome {
  reserved : Bool
  /// reserved | renewed | taken_over | conflict
  action : String
  /// 仅 taken_over 非空：被让渡掉的原持有者
  prev_agent : String
  agent : String
  ttl_until : String
}

///|
/// 裁决规则**单一真源**：给定写前快照与本次请求，判「该不该写」＋动作标签。
/// 两个后端都从这里取标签，SQLite 侧的 `ON CONFLICT ... WHERE` 编码的是同一条规则
/// （`reservations.agent = excluded.agent OR reservations.ttl_until < excluded.created_at`）。
/// 同持有者排在过期之前：自己续一条已过期的预订，报 renewed 而不是 taken_over（与旧口径逐字一致）。
pub fn rsv_action(
  prev : (String, String, String)?,
  agent : String,
  now : String,
) -> (Bool, String) {
  match prev {
    None => (true, "reserved")
    Some((owner, _, _)) if owner == agent => (true, "renewed")
    Some((_, ttl, _)) if ttl < now => (true, "taken_over")
    _ => (false, "conflict")
  }
}

///|
/// 内存后端：按裁决写预订，**写后回读**收口。
/// 旧形状（先 rsv_get 判空再无条件 rsv_set）在跨进程下会双方都读到空闲、双方都写成功；
/// 内存后端本来没有那个窗口，但两后端必须同一形状，否则单测永远绿而 SQLite 红（BUG-85/BUG-79 的旧例）。
pub fn MemoryStore::rsv_try_set(
  self : MemoryStore,
  scope~ : String,
  agent~ : String,
  ttl_until~ : String,
  created_at~ : String,
) -> Result[RsvOutcome, String] {
  let prev = self.rsv_get(scope)
  let (may_write, action) = rsv_action(prev, agent, created_at)
  let prev_agent = match prev {
    Some((o, _, _)) if action == "taken_over" => o
    _ => ""
  }
  if may_write {
    ignore(self.rsv_set(scope~, agent~, ttl_until~, created_at~))
  }
  // 结论以库里的现值为准：内存后端在这里必然与请求一致，写成回读是为了两后端同构
  match self.rsv_get(scope) {
    Some((owner, ttl, _)) if owner == agent =>
      Ok(RsvOutcome::{
        reserved: true,
        action,
        prev_agent,
        agent,
        ttl_until: ttl,
      })
    Some((owner, ttl, _)) =>
      Ok(RsvOutcome::{
        reserved: false,
        action: "conflict",
        prev_agent: "",
        agent: owner,
        ttl_until: ttl,
      })
    None =>
      Ok(RsvOutcome::{
        reserved: false,
        action: "conflict",
        prev_agent: "",
        agent: "",
        ttl_until: "",
      })
  }
}

// —— 执行者能力注册（Marketplace 雏形跨进程持久化，R31）——

///|
/// 内存后端：写入/覆盖一个执行者的能力注册（幂等）。
pub fn MemoryStore::executor_save(
  self : MemoryStore,
  name~ : String,
  abilities_json~ : String,
  created_at~ : String,
) -> Result[String, String] {
  self.executors.set(name, (abilities_json, created_at))
  Ok("saved")
}

///|
/// 内存后端：列出全部执行者 (name, abilities_json, created_at)。
pub fn MemoryStore::executor_list(
  self : MemoryStore,
) -> Array[(String, String, String)] {
  let out : Array[(String, String, String)] = []
  for (k, v) in self.executors {
    out.push((k, v.0, v.1))
  }
  out
}

///|
/// 内存后端：清空全部执行者能力注册（Marketplace 重置/整洁）。
pub fn MemoryStore::executor_clear(self : MemoryStore) -> Bool {
  self.executors.clear()
  true
}

// —— 分布式文件锁（内存后端）——

///|
/// 锁层复用预订层裁决真源的前置归一：把锁的写前快照折成 `rsv_action` 的输入。
/// 非 `active`（released / expired / violated）一律视作「无人持锁」→ `None`，
/// 于是「复用一条已释放/已扫出的行」走 `reserved`，与预订层同一形状。
fn lock_prev_for_action(prev : FileLock?) -> (String, String, String)? {
  match prev {
    Some(l) if l.status == "active" => Some((l.agent, l.ttl_until, l.ts))
    _ => None
  }
}

///|
/// 锁层「该不该写」的裁决：**逐字委托 `rsv_action`**，不另写谓词。
///
///   - 为什么必须有这一层（BUG-145 / 多 agent 锁机制报告 R24·R25）：`locks_upsert` 原先
///     自带一段手写 forked 谓词，只决定「要不要追加一条 `lock_taken_over` 违例」，
///     随后**无条件覆盖写**——把 `rsv_action` 本应回的 `(false, "conflict")` 丢弃了。
///     后果是 `lock_acquire` 恒回 active：A 持 live 锁时 B 照样「拿到」同一把锁，
///     而设计文档 v3 的 lk2 明确要求「A 持锁后 B `lock_acquire` → granted=false, blocked_by=A」。
///   - 单一真源纪律：冲突矩阵只写在 `rsv_action` 一处（同持有者排在过期之前那条亦然），
///     本函数只做形状归一，因此预订层与锁层不可能各自漂移。
///   - `now` 传本次请求的时间戳（与旧 forked 谓词的 `lock.ts` 同一口径）。
pub fn lock_acquire_action(
  prev : FileLock?,
  agent : String,
  now : String,
) -> (Bool, String) {
  rsv_action(lock_prev_for_action(prev), agent, now)
}

///|
/// 锁获取裁决结果（与 `RsvOutcome` 同一纪律：结论来自**写后回读**，不由请求反推）。
pub struct LockAcquireOutcome {
  granted : Bool
  /// reserved | renewed | taken_over | conflict
  action : String
  /// 仅 taken_over 非空：被让渡掉的原持有者
  prev_agent : String
  /// 库里现值：granted 时是自己，conflict 时即现持有者（held_by）
  agent : String
  /// 库里现值的 ttl_until
  ttl_until : String
  /// 本次是否留下了一条违例记录（conflict 记 lock_denied）
  violation_logged : Bool
} derive(Debug)

///|
pub extend LockAcquireOutcome with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// 内存后端：把锁写入（按 scope 唯一，覆盖旧值；旧锁若 active 且非本人且未过期则记违例）。
///
/// **这是底层原语，不是互斥门**：它永远落库（last-write-wins），只在覆盖他人 live 锁时
/// 留一条 `lock_taken_over` 事后审计。要「抢不到就拒」请用 `locks_try_acquire`。
pub fn MemoryStore::locks_upsert(self : MemoryStore, lock : FileLock) -> Unit {
  match self.file_locks.get(lock.scope) {
    Some(old) if old.status == "active" &&
      old.agent != lock.agent &&
      old.ttl_until >= lock.ts =>
      self.lock_violations.push(LockViolation::{
        ts: lock.ts,
        agent: lock.agent,
        scope: lock.scope,
        reason: "lock_taken_over",
        lock_id: old.lock_id,
      })
    _ => ()
  }
  self.file_locks.set(lock.scope, lock)
}

///|
/// 内存后端：按裁决抢锁（BUG-145）——**抢不到就是拒绝，不是覆盖**。
/// 形状与 `rsv_try_set` 逐字同构：写前快照过 `lock_acquire_action`（委托 `rsv_action`）
/// 定标签，结论一律由**写后回读**定——回执不许由请求反推。
/// conflict 时落一条 `lock_denied` 违例（拒夺审计），锁行**不动**，现持有者原样保住。
pub fn MemoryStore::locks_try_acquire(
  self : MemoryStore,
  lock : FileLock,
) -> LockAcquireOutcome {
  let prev = self.locks_get(lock.scope)
  let (may_write, action) = lock_acquire_action(prev, lock.agent, lock.ts)
  let prev_agent = match prev {
    Some(o) if action == "taken_over" => o.agent
    _ => ""
  }
  if may_write {
    self.file_locks.set(lock.scope, lock)
  }
  match self.locks_get(lock.scope) {
    Some(l) if l.agent == lock.agent =>
      LockAcquireOutcome::{
        granted: true,
        action,
        prev_agent,
        agent: lock.agent,
        ttl_until: l.ttl_until,
        violation_logged: false,
      }
    Some(l) => {
      self.lock_violations.push(LockViolation::{
        ts: lock.ts,
        agent: lock.agent,
        scope: lock.scope,
        reason: "lock_denied",
        lock_id: lock.lock_id,
      })
      LockAcquireOutcome::{
        granted: false,
        action: "conflict",
        prev_agent: "",
        agent: l.agent,
        ttl_until: l.ttl_until,
        violation_logged: true,
      }
    }
    None =>
      LockAcquireOutcome::{
        granted: false,
        action: "conflict",
        prev_agent: "",
        agent: "",
        ttl_until: "",
        violation_logged: false,
      }
  }
}

///|
/// 内存后端：查询某 scope 的锁（不存在返回 None）。
pub fn MemoryStore::locks_get(self : MemoryStore, scope : String) -> FileLock? {
  self.file_locks.get(scope)
}

///|
/// 内存后端：列出全部锁。
pub fn MemoryStore::locks_list(self : MemoryStore) -> Array[FileLock] {
  let out : Array[FileLock] = []
  self.file_locks.each(fn(_, l) { out.push(l) })
  out
}

///|
/// 内存后端：释放某 scope 的锁（仅持有者可释放；不存在或非持有者返回 false）。
pub fn MemoryStore::locks_release(
  self : MemoryStore,
  scope : String,
  agent : String,
) -> Bool {
  match self.file_locks.get(scope) {
    Some(l) if l.agent == agent => {
      let released = FileLock::{ ..l, status: "released", }
      self.file_locks.set(scope, released)
      true
    }
    _ => false
  }
}

///|
/// 内存后端：清理过期锁（status=active 且 ttl_until < now → 标记 expired，记违例）。
/// 返回被清理的锁数量。
pub fn MemoryStore::locks_sweep(self : MemoryStore, now : String) -> Int32 {
  let mut count = 0
  let scopes = self.file_locks.keys()
  for scope in scopes {
    match self.file_locks.get(scope) {
      Some(l) if l.status == "active" && l.ttl_until < now => {
        let expired = FileLock::{ ..l, status: "expired", }
        self.file_locks.set(scope, expired)
        self.lock_violations.push(LockViolation::{
          ts: now,
          agent: l.agent,
          scope: l.scope,
          reason: "lock_expired",
          lock_id: l.lock_id,
        })
        count = count + 1
      }
      _ => ()
    }
  }
  count
}

///|
/// 内存后端：列出违例记录。
pub fn MemoryStore::lock_violations_list(
  self : MemoryStore,
) -> Array[LockViolation] {
  self.lock_violations
}
