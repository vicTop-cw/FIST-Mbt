///|
/// R38：CAF 路由的**成本决胜**契约锁（验收标准 2「不增成本」的纯计算侧）。
///
/// `caf_soft_reorder` 排序键：邻域内 → rate 降序 → **avg_cost 升序** → 稳定序。
/// 现有锁 `caf_soft_reorder_tie_stable` 只测「同 rate + 同 cost → FIFO 稳定」，
/// **没测「同 rate 但 cost 不同 → cost 低优先」**。若 cost 不真正参与路由，
/// CAF 会选 rate 相同但更贵的模型 → **增成本**（违反标准 2「开启后不增成本」）。
///
/// stats 由真实 `CafRecord` 记忆经 `caf_stats` 聚合生成（全 pub API，避免构造
/// `CafModelStats` 的字面量语法歧义），确保测的是真源聚合口径。
fn caf_cost_mem() -> @router.CafMemory {
  let h = @router.caf_feature_hash("cost test context")
  let mem = @router.CafMemory::new()
  mem.push(
    @router.CafRecord::new(
      feature_hash=h,
      model="free-a",
      ok=true,
      cost=10.0,
      ts="2026-10-15T10:00:00Z",
    ),
  )
  mem.push(
    @router.CafRecord::new(
      feature_hash=h,
      model="free-a",
      ok=true,
      cost=10.0,
      ts="2026-10-15T11:00:00Z",
    ),
  )
  mem.push(
    @router.CafRecord::new(
      feature_hash=h,
      model="free-b",
      ok=true,
      cost=0.1,
      ts="2026-10-15T12:00:00Z",
    ),
  )
  mem.push(
    @router.CafRecord::new(
      feature_hash=h,
      model="free-b",
      ok=true,
      cost=0.1,
      ts="2026-10-15T13:00:00Z",
    ),
  )
  mem
}

///|
/// 同 rate 不同 cost → cost 低优先（cost 决胜）。
/// free-a 与 free-b 都 100% 成功（rate 均为 1.0），但 free-a avg_cost=10.0、free-b avg_cost=0.1。
/// 期望 free-b 排到 free-a 前面（否则 CAF 会在同成功率下选更贵的模型）。
test "caf_cost_1_同率不同成本_成本低优先" {
  let stats = @router.caf_stats(caf_cost_mem().all())
  let candidates : Array[String] = ["free-a", "free-b"]
  let out = @router.caf_soft_reorder(candidates, stats)
  if out.length() != 2 {
    abort("应返回 2 个候选，实际 " + out.length().to_string())
  }
  if out[0] != "free-b" {
    abort("同 rate 时应选成本低的 free-b，实际首位 " + out[0])
  }
  if out[1] != "free-a" {
    abort("第二位应为 free-a，实际 " + out[1])
  }
}

///|
/// 邻域优先胜过成本：只有 free-a 有历史依据（rate 0.5, cost 0.1），
/// free-b 不在邻域 → free-a 先。防止"为了省成本把无依据模型排到有依据的前面"。
test "caf_cost_2_邻域优先胜过成本" {
  let h = @router.caf_feature_hash("nb test context")
  let mem = @router.CafMemory::new()
  mem.push(
    @router.CafRecord::new(
      feature_hash=h,
      model="free-a",
      ok=true,
      cost=0.1,
      ts="2026-10-15T10:00:00Z",
    ),
  )
  mem.push(
    @router.CafRecord::new(
      feature_hash=h,
      model="free-a",
      ok=false,
      cost=0.1,
      ts="2026-10-15T11:00:00Z",
    ),
  )
  let stats = @router.caf_stats(mem.all())
  let candidates : Array[String] = ["free-a", "free-b"]
  let out = @router.caf_soft_reorder(candidates, stats)
  if out[0] != "free-a" {
    abort("邻域内的 free-a 应优先，实际首位 " + out[0])
  }
}
