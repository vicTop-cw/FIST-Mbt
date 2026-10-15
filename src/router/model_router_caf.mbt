/// model_router_caf.mbt —— P2c §2.2：ModelRouter 的 CAF 记忆软性重排 pick 变体
///
/// 设计决策（文档见 docs/2026-10-15-fist-mbt-caf-p2c-wiring-design.md）：
///   - 只在 `config.use_caf_memory=true` 且 `caf_memory` 提供时生效
///   - 不改配额、不改档位切换（软性排序，不破硬约束）
///   - 候选集 = 当前活跃池的模型名（与 pool_pick 同池同容量）
///   - 若重排第一名与原 pick 决策不同且健康可用 → 采用重排第一名
///
/// 为什么不改 pick_inner：pick_inner 多分支返回，插排序会牵动配额游标更新，
/// 风险高。本函数在 `pick` 之上做**一层 wrapper**，把软性提示落到 decision 层；
/// 配额游标不推进（软性提示不消耗配额——下一次 pick 仍从原游标继续）。

///|
/// 在配额筛选之后、最终返回之前插入 CAF 软性重排的 pick 变体。
/// 返回 (decision, 是否发生了重排)。
pub fn ModelRouter::pick_caf(
  self : ModelRouter,
  now~ : String,
  caf_memory~ : CafMemory,
  context~ : String,
  k~ : Int,
  unhealthy_ids? : Array[String] = [],
  laya_prefer_tier? : String = "",
) -> (RouteDecision, Bool) {
  let d = self.pick(now~, unhealthy_ids~, laya_prefer_tier~)
  if !self.config.use_caf_memory {
    return (d, false)
  }
  if !d.available || d.model_name.is_empty() {
    return (d, false)
  }
  let pool = self.active_pool()
  if pool.length() < 2 {
    return (d, false)
  }
  let candidates = pool.map(fn(m) { m.name })
  let stats = caf_memory.knn_stats(context, k)
  let reordered = caf_soft_reorder(candidates, stats)
  if reordered.length() == 0 || reordered[0] == d.model_name {
    return (d, false)
  }
  // 软性重排命中不同模型 → 检查它是否健康可用（配额硬约束不破）
  let alt_name = reordered[0]
  let mut alt : ModelQuota? = None
  for m in pool {
    if m.name == alt_name {
      alt = Some(m)
      break
    }
  }
  match alt {
    None => (d, false)
    Some(m) =>
      if m.usage_pct() < self.config.threshold_pct &&
        !m.is_exhausted() &&
        !m.in_cooldown(now) &&
        !is_model_unhealthy(m.name, unhealthy_ids) {
        (
          {
            model_name: m.name,
            tier: self.current_tier,
            reason: d.reason + "; caf reorder → " + m.name,
            switched: d.switched,
            next_switch_at: d.next_switch_at,
            available: true,
            fallback_chain: compute_fallback_chain(
              self.config,
              m.name,
              unhealthy_ids~,
            ),
            laya_reason: d.laya_reason,
          },
          true,
        )
      } else {
        (d, false)
      }
  }
}
