/// fist-evidence: 验收证据引擎 - Evidence 证据存储
///
/// 多租户隔离的证据仓：证据按租户 key 物理分离，互不可见，
/// 呼应"物理多租户隔离"验收项；同时提供全量证据报告输出。
/// 实现不依赖第三方 map 包：租户证据以 (key, list) 数组对存储，
/// 读写都按 key 过滤，保证租户间物理不可见。

///|
/// 一条修复证据：记录某 Spec 在某一轮被 apply_fix 真实修复的记录
pub struct FixEvidence {
  spec_id : String
  round : Int
  // 修复动作描述（由 apply_fix 返回）
  action : String
  // 修复后的校验结果（verify 返回）
  verify_result : String
}

///|
/// 构造一条修复证据
pub fn FixEvidence::new(
  spec_id : String,
  round : Int,
  action : String,
  verify_result : String,
) -> FixEvidence {
  { spec_id, round, action, verify_result, }
}

///|
/// 租户证据对：租户 key 与它名下的证据列表
struct TenantSlot {
  key : String
  list : Array[FixEvidence]
}

///|
/// 证据仓：按租户隔离存储
pub struct EvidenceStore {
  // 所有租户的证据槽（每个租户一个 slot，读写均按 key 精确过滤）
  slots : Array[TenantSlot]
}

///|
/// 新建一个空证据仓
pub fn EvidenceStore::new() -> EvidenceStore {
  { slots: [], }
}

///|
/// 查找某租户的证据列表（不存在时返回空列表；不跨租户读取）
fn EvidenceStore::slot_of(
  self : EvidenceStore,
  tenant : String,
) -> Array[FixEvidence] {
  let mut found : Array[FixEvidence] = []
  for slot in self.slots {
    if slot.key == tenant {
      found = slot.list
      break
    }
  }
  found
}

///|
/// 在指定租户下追加一条修复证据
pub fn EvidenceStore::add_evidence(
  self : EvidenceStore,
  tenant : String,
  ev : FixEvidence,
) -> EvidenceStore {
  let mut exists = false
  let new_slots : Array[TenantSlot] = []
  for slot in self.slots {
    if slot.key == tenant {
      // 该租户已有证据：追加到其列表
      let l = slot.list
      l.push(ev)
      new_slots.push({ key: slot.key, list: l, })
      exists = true
    } else {
      new_slots.push(slot)
    }
  }
  if !exists {
    new_slots.push({ key: tenant, list: [ev], })
  }
  { slots: new_slots, }
}

///|
/// 读取某租户的全部证据；其他租户不可见（物理隔离）
pub fn EvidenceStore::evidence_of(
  self : EvidenceStore,
  tenant : String,
) -> Array[FixEvidence] {
  self.slot_of(tenant)
}

///|
/// 是否存在某租户下的证据
pub fn EvidenceStore::has_evidence(
  self : EvidenceStore,
  tenant : String,
) -> Bool {
  self.evidence_of(tenant).length() > 0
}

///|
/// 全部租户 key（用于审计统计）
pub fn EvidenceStore::all_tenants(self : EvidenceStore) -> Array[String] {
  let keys : Array[String] = []
  for slot in self.slots {
    keys.push(slot.key)
  }
  keys
}

///|
/// 统计某租户在指定轮次之前的修复次数
pub fn EvidenceStore::count_fixes(
  self : EvidenceStore,
  tenant : String,
  up_to_round : Int,
) -> Int {
  let mut n = 0
  for ev in self.evidence_of(tenant) {
    if ev.round <= up_to_round {
      n = n + 1
    }
  }
  n
}

///|
/// 生成某租户的证据报告文本
pub fn EvidenceStore::report(self : EvidenceStore, tenant : String) -> String {
  let evs = self.evidence_of(tenant)
  let out : Array[String] = []
  out.push(
    "=== evidence report: tenant=" +
    tenant +
    " fixes=" +
    evs.length().to_string() +
    " ===",
  )
  for ev in evs {
    out.push(
      "  [r" +
      ev.round.to_string() +
      "] " +
      ev.spec_id +
      ": " +
      ev.action +
      " -> " +
      ev.verify_result,
    )
  }
  out.join("\n")
}
