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
