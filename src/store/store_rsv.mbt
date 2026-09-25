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
