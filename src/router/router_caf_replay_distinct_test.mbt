///|
/// R40：CAF 离线回放的**上下文区分度**契约锁（验收标准 1 的 MoonBit 真源锁）。
///
/// 标准 1「离线回放可复现」的核心契约：
/// 简单任务 context → 命中 m_free（rate 0.93）；复杂任务 context → 命中 m_premium（rate 1.0）。
/// 即**不同任务类型的特征哈希必须命中不同的历史记录邻域**，否则离线回放无法区分任务类型。
/// 现有锁 `caf_knn_search_topk/boundary/k_greater_than_records` 只测 Top-K 的**返回数量**与边界，
/// **没测区分度**——若不同 context 都命中同一组记录，回放就退化成"单一优先级"。
/// 本锁钉死"不同 context → 不同模型"这一标准 1 前提。
fn c1_mem() -> CafMemory {
  let mem = CafMemory::new()
  let hs = caf_feature_hash("simple task")
  let hc = caf_feature_hash("complex task")
  mem.push(
    CafRecord::new(
      feature_hash=hs,
      model="m_free",
      ok=true,
      cost=1.0,
      ts="2026-10-15T10:00:00Z",
    ),
  )
  mem.push(
    CafRecord::new(
      feature_hash=hs,
      model="m_free",
      ok=true,
      cost=1.0,
      ts="2026-10-15T11:00:00Z",
    ),
  )
  mem.push(
    CafRecord::new(
      feature_hash=hs,
      model="m_free",
      ok=false,
      cost=1.0,
      ts="2026-10-15T12:00:00Z",
    ),
  )
  mem.push(
    CafRecord::new(
      feature_hash=hc,
      model="m_premium",
      ok=true,
      cost=5.0,
      ts="2026-10-15T13:00:00Z",
    ),
  )
  mem.push(
    CafRecord::new(
      feature_hash=hc,
      model="m_premium",
      ok=true,
      cost=5.0,
      ts="2026-10-15T14:00:00Z",
    ),
  )
  mem.push(
    CafRecord::new(
      feature_hash=hc,
      model="m_premium",
      ok=true,
      cost=5.0,
      ts="2026-10-15T15:00:00Z",
    ),
  )
  mem
}

///|
/// 简单任务 context 回放命中 m_free（其邻域 rate 0.667 > m_premium 在该 context 下的 0）。
/// k=3 时精确 hash 匹配（编辑距离 0）的 3 条 simple 记录排前，首条即 m_free。
test "caf_c1_1_简单任务回放命中m_free" {
  let mem = c1_mem()
  let stats = caf_stats(mem.knn_search("simple task", 3))
  if stats.is_empty() {
    abort("knn_search 应返回非空")
  }
  if stats[0].model != "m_free" {
    abort("简单任务回放首位应为 m_free，实际 " + stats[0].model)
  }
  if stats[0].success != 2 || stats[0].total != 3 {
    abort(
      "简单任务邻域应统计 2 成功 3 总，实际 " +
      stats[0].success.to_string() +
      "/" +
      stats[0].total.to_string(),
    )
  }
}

///|
/// 复杂任务 context 回放命中 m_premium（rate 1.0），与简单任务的 m_free 区分。
/// 若此锁红，说明不同 context 未命中不同邻域，离线回放无法区分任务类型。
test "caf_c1_2_复杂任务回放命中m_premium" {
  let mem = c1_mem()
  let stats = caf_stats(mem.knn_search("complex task", 3))
  if stats.is_empty() {
    abort("knn_search 应返回非空")
  }
  if stats[0].model != "m_premium" {
    abort("复杂任务回放首位应为 m_premium，实际 " + stats[0].model)
  }
  if stats[0].success != 3 || stats[0].total != 3 {
    abort(
      "复杂任务邻域应统计 3 成功 3 总，实际 " +
      stats[0].success.to_string() +
      "/" +
      stats[0].total.to_string(),
    )
  }
}

///|
/// 两任务类型**严格区分**：简单任务邻域首位 m_free、复杂任务邻域首位 m_premium，
/// 且简单任务 rate (0.667) < 复杂任务 rate (1.0)（复杂任务更可靠 → 回放优先 premium）。
test "caf_c1_3_两种任务类型严格区分" {
  let mem = c1_mem()
  let simple = caf_stats(mem.knn_search("simple task", 3))
  let complex = caf_stats(mem.knn_search("complex task", 3))
  if simple[0].model == complex[0].model {
    abort(
      "不同任务类型应命中不同模型，实际均为 " +
      simple[0].model,
    )
  }
  let simple_rate = simple[0].success.to_double() / simple[0].total.to_double()
  let complex_rate = complex[0].success.to_double() /
    complex[0].total.to_double()
  if complex_rate <= simple_rate {
    abort(
      "复杂任务回放成功率应高于简单任务，实际 simple=" +
      simple_rate.to_string() +
      " complex=" +
      complex_rate.to_string(),
    )
  }
}
