/// engine/engine_rsv.mbt —— 作用域预订（拿来主义：Interlinked 文件预订 → 多 agent 并发冲突预防）
///
/// 转发到后端 StoreBackend 的 rsv_*，供 server 工具统一走引擎，避免跨层直接摸 store。

///|
pub fn FistEngine::rsv_set(
  self : FistEngine,
  scope~ : String,
  agent~ : String,
  ttl_until~ : String,
  created_at~ : String,
) -> Result[String, String] {
  self.store.rsv_set(scope~, agent~, ttl_until~, created_at~)
}

///|
/// 按裁决抢预订（BUG-136）：互斥由后端定，工具面只渲染结论——不许在这里先读后写。
pub fn FistEngine::rsv_try_set(
  self : FistEngine,
  scope~ : String,
  agent~ : String,
  ttl_until~ : String,
  created_at~ : String,
) -> Result[@store.RsvOutcome, String] {
  self.store.rsv_try_set(scope~, agent~, ttl_until~, created_at~)
}

///|
pub fn FistEngine::rsv_get(
  self : FistEngine,
  scope : String,
) -> (String, String, String)? {
  self.store.rsv_get(scope)
}

///|
pub fn FistEngine::rsv_release(
  self : FistEngine,
  scope : String,
  agent : String,
) -> Bool {
  self.store.rsv_release(scope, agent)
}

///|
pub fn FistEngine::rsv_list(
  self : FistEngine,
) -> Array[(String, String, String)] {
  self.store.rsv_list()
}

// —— 分布式文件锁（引擎层转发到 StoreBackend）——

///|
pub fn FistEngine::locks_upsert(
  self : FistEngine,
  lock : @store.FileLock,
) -> Unit {
  self.store.locks_upsert(lock)
}

///|
pub fn FistEngine::locks_get(
  self : FistEngine,
  scope : String,
) -> @store.FileLock? {
  self.store.locks_get(scope)
}

///|
pub fn FistEngine::locks_list(self : FistEngine) -> Array[@store.FileLock] {
  self.store.locks_list()
}

///|
pub fn FistEngine::locks_release(
  self : FistEngine,
  scope : String,
  agent : String,
) -> Bool {
  self.store.locks_release(scope, agent)
}

///|
pub fn FistEngine::locks_sweep(self : FistEngine, now : String) -> Int {
  self.store.locks_sweep(now)
}

///|
pub fn FistEngine::lock_violations_list(
  self : FistEngine,
) -> Array[@store.LockViolation] {
  self.store.lock_violations_list()
}
