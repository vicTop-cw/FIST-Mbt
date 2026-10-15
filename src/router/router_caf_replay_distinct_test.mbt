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

///|
/// R47 · 标准 1「候选集置换不变」真源锁（补齐 CAF 验收状态 L32 声明未锁的缺口）。
///
/// 验收文档声明「排列性质：排序结果对候选集置换保持不变」，但 caf_c1_1/2/3 只锁了
/// **上下文区分度**，未锁**排列性质**。若 `caf_soft_reorder` 依赖输入顺序（如按数组下标
/// 隐式参与排序），置换候选集会让回放优先级漂移 → 标准 1「离线回放可复现」违约。
///
/// 前提：候选都是有依据模型且 rate 互不相同（无 tie）→ 排序由 rate 决定，与输入顺序无关。
/// tie 时的 FIFO 稳定由 R13 `caf_soft_reorder_tie_stable` 锁，不在本锁范围。
test "caf_c1_4_候选集置换不变" {
  let mem = c1_mem()
  // 全量聚合，保证 m_free（rate 0.667）与 m_premium（rate 1.0）都在 stats 里
  let stats = caf_stats(mem.all())
  let base : Array[String] = ["m_free", "m_premium"]
  let perm : Array[String] = ["m_premium", "m_free"]
  let r_base = caf_soft_reorder(base, stats)
  let r_perm = caf_soft_reorder(perm, stats)
  if r_base.length() != 2 {
    abort("应返回 2 个候选，实际 " + r_base.length().to_string())
  }
  // 排列性质核心：首位恒为 rate 更高的 m_premium（与输入顺序无关）
  if r_base[0] != "m_premium" || r_perm[0] != "m_premium" {
    abort(
      "排列性质违约：首位应恒为 m_premium，实际 base=" +
      r_base[0] +
      " perm=" +
      r_perm[0],
    )
  }
  // 完整序列一致（逐位置比对，Array 用 == 依赖语言实现，这里显式循环更稳）。
  // 注意：MoonBit 半开区间 `0..<len`（不遍历 len），闭区间 `0..=len-1` 才含 len-1；
  // 写成 `0..<=2` 会遍历 0,1,2 三次 → 第 3 次 r_base[2] 越界 panic。
  for i in 0..<r_base.length() {
    if r_base[i] != r_perm[i] {
      abort(
        "排列性质违约：位置 " +
        i.to_string() +
        " base=" +
        r_base[i] +
        " perm=" +
        r_perm[i],
      )
    }
  }
}
