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
/// 最近登记的**曾任**主助理（不要求 `status == "active"`）—— BUG-431。
///
/// 为什么必须与 `assistant_active_primary` 分开：
/// `assistant_sweep` 会把心跳陈旧的主助理标 `dead`，而 `active_primary` **只认 active**
/// ⇒ sweep 跑过之后 `claim` 看到 `prev = None` ⇒ `assistant_claim_action` 判 **`elected`**
/// 且 `prev_agent = ""` ⇒ `server.mbt` 的留痕分支（只在 `taken_over` 时记）**不记违例**。
/// ⇒ **同一个业务事件**（B 心跳陈旧、A 接管）会因「sweep 是否恰好先跑过」
/// 产出两种不同的账本结果（一种有 `force_takeover` 案底、一种没有）。
///
/// 语义边界（刻意的）：
/// - **`dead` 参与** —— 它正是「曾持有、已陈旧」的那一档，接管要认它
/// - **`resigned` 排除** —— 主动退位后应重新选举（旧语义），不算被接管
/// - 排序键与 `active_primary` 一致（`registered_at` 最新），只放宽 status 过滤
pub fn FistEngine::assistant_last_primary(
  self : FistEngine,
) -> @store.AssistantReg? {
  let mut best : @store.AssistantReg? = None
  for r in self.store.assistant_list() {
    if r.is_primary && r.status != "resigned" {
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
