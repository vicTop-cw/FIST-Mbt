/// store/store_assistant.mbt —— 项目助理登记（内存后端，multi-agent-lock v3 阶段2 精简版）
///
/// 助理选举/心跳/退位/清扫。SQLite 后端在 store_sqlite.mbt 侧实现同构语义，
/// 选举裁决共用 store.mbt 的 assistant_claim_action 单一真源。

///|
/// 内存后端：写入/覆盖一个助理登记（幂等）。
pub fn MemoryStore::assistant_upsert(
  self : MemoryStore,
  reg : AssistantReg,
) -> Unit {
  self.assistant_reg.set(reg.agent, reg)
}

///|
/// 内存后端：查询某 agent 的助理登记（不存在返回 None）。
pub fn MemoryStore::assistant_get(
  self : MemoryStore,
  agent : String,
) -> AssistantReg? {
  self.assistant_reg.get(agent)
}

///|
/// 内存后端：列出全部助理登记。
pub fn MemoryStore::assistant_list(self : MemoryStore) -> Array[AssistantReg] {
  let out : Array[AssistantReg] = []
  self.assistant_reg.each(fn(_, r) { out.push(r) })
  out
}

///|
/// 内存后端：改某 agent 登记的 status（dead / resigned 等；不存在返回 false）。
pub fn MemoryStore::assistant_set_status(
  self : MemoryStore,
  agent : String,
  status : String,
) -> Bool {
  match self.assistant_reg.get(agent) {
    Some(r) => {
      self.assistant_reg.set(agent, { ..r, status, })
      true
    }
    None => false
  }
}

///|
/// 内存后端：追加一条锁违例（助理接管等治理动作落案底）。
pub fn MemoryStore::lock_violations_push(
  self : MemoryStore,
  v : LockViolation,
) -> Unit {
  self.lock_violations.push(v)
}
