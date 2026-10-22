/// engine/engine_assistant.mbt —— 项目助理登记（multi-agent-lock v3 阶段2 精简版）
///
/// 纯转发到后端 StoreBackend 的 assistant_*，供 server 工具统一走引擎，避免跨层直接摸 store。

///|
pub fn FistEngine::assistant_upsert(
  self : FistEngine,
  reg : @store.AssistantReg,
) -> Unit {
  self.store.assistant_upsert(reg)
}

///|
pub fn FistEngine::assistant_get(
  self : FistEngine,
  agent : String,
) -> @store.AssistantReg? {
  self.store.assistant_get(agent)
}

///|
pub fn FistEngine::assistant_list(
  self : FistEngine,
) -> Array[@store.AssistantReg] {
  self.store.assistant_list()
}

///|
pub fn FistEngine::assistant_set_status(
  self : FistEngine,
  agent : String,
  status : String,
) -> Bool {
  self.store.assistant_set_status(agent, status)
}

///|
/// 找现任 active 主助理（is_primary 且 status=active，取 registered_at 最新）。
pub fn FistEngine::assistant_active_primary(
  self : FistEngine,
) -> @store.AssistantReg? {
  let mut best : @store.AssistantReg? = None
  for r in self.store.assistant_list() {
    if r.is_primary && r.status == "active" {
      match best {
        None => best = Some(r)
        Some(b) if r.registered_at > b.registered_at => best = Some(r)
        _ => ()
      }
    }
  }
  best
}

///|
/// 记一条锁违例（助理接管等治理动作落案底）。
pub fn FistEngine::lock_violations_record(
  self : FistEngine,
  ts~ : String,
  agent~ : String,
  scope~ : String,
  reason~ : String,
  lock_id~ : String,
) -> Unit {
  self.store.lock_violations_push(
    @store.LockViolation::new(ts~, agent~, scope~, reason~, lock_id~),
  )
}
