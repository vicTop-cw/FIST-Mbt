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
pub fn FistEngine::rsv_get(self : FistEngine, scope : String) -> (String, String, String)? {
  self.store.rsv_get(scope)
}

///|
pub fn FistEngine::rsv_release(self : FistEngine, scope : String, agent : String) -> Bool {
  self.store.rsv_release(scope, agent)
}

///|
pub fn FistEngine::rsv_list(self : FistEngine) -> Array[(String, String, String)] {
  self.store.rsv_list()
}