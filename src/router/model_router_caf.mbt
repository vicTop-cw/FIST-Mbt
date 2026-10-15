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
/// 配额游标仍随 pick 推进（软性提示不额外消耗配额——采用重排第一名时不额外
/// 占用一次 pick 名额，下一次 pick 仍从原游标继续）。
///
/// `pick_caf_dry_run` 是零副作用预览（验收标准 3 的纯计算部分）：通过克隆
/// self 的配置与游标构造 probe router，让 base pick 的游标推进与 window_start
/// 副作用不污染原 config。调用方可据此实现 `dry_run=true` 的预览路径。

///|
/// CAF dry_run 预览结果：建议模型 + 历史依据。
/// 验收标准 3 预期产物形状：`{"suggestion": model, "basis": [{model, rate, avg_cost, count, ...}]}`。
pub struct CafDryRun {
  /// 不含 CAF 的 base pick 决策（对照）
  base : RouteDecision
  /// 应用 CAF 软性重排后的决策
  picked : RouteDecision
  /// 是否发生了重排（true 表示 picked.model_name != base.model_name）
  reordered : Bool
  /// Top-K 邻域统计（历史依据），供调用方展示 rate/avg_cost/count
  basis : Array[CafModelStats]
  /// 检索的 k 值
  top_k : Int
} derive(Debug)

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
  self.apply_caf(d, now~, caf_memory~, context~, k~, unhealthy_ids~)
}

///|
/// 在已有 pick 决策 d 之上做 CAF 软性重排（纯函数，不再重新 pick，不推进游标）。
/// 供 pick_caf 与 pick_caf_dry_run 共用，确保两者的"应用 CAF"路径完全一致。
pub fn ModelRouter::apply_caf(
  self : ModelRouter,
  d : RouteDecision,
  now~ : String,
  caf_memory~ : CafMemory,
  context~ : String,
  k~ : Int,
  unhealthy_ids? : Array[String] = [],
) -> (RouteDecision, Bool) {
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

///|
/// 验收标准 3（dry_run 预览）的纯计算部分：零副作用 peek。
/// 内部克隆 self 的配置与游标（pool 数组值拷贝，window_start/冷却不污染原 config），
/// 在 clone 上跑一次 pick，再在同一 decision 上 apply_caf，返回 base/picked 对照
/// 与历史依据。**调用方无任何副作用**：原 self 的 free_idx/paid_idx/current_tier/
/// last_pick 与 config.free_models[].window_start 均不被改动。
pub fn ModelRouter::pick_caf_dry_run(
  self : ModelRouter,
  now~ : String,
  caf_memory~ : CafMemory,
  context~ : String,
  k~ : Int,
  unhealthy_ids? : Array[String] = [],
) -> CafDryRun {
  let probe = self.clone_for_peek()
  let base = probe.pick(now~, unhealthy_ids~)
  let (picked, reordered) = probe.apply_caf(
    base,
    now~,
    caf_memory~,
    context~,
    k~,
    unhealthy_ids~,
  )
  {
    base,
    picked,
    reordered,
    basis: caf_memory.knn_stats(context, k),
    top_k: k,
  }
}

///|
/// 克隆 self 用于零副作用 peek：config 的 pool 数组按值拷贝（元素为 ModelQuota 值，
/// window_start / cooldown_until 的后续写入不回流原 config），游标与档位原样带入。
fn ModelRouter::clone_for_peek(self : ModelRouter) -> ModelRouter {
  {
    config: clone_pools(self.config),
    free_idx: self.free_idx,
    paid_idx: self.paid_idx,
    current_tier: self.current_tier,
    switch_count: self.switch_count,
    last_switch_at: self.last_switch_at,
    last_reason: self.last_reason,
    last_pick: self.last_pick,
  }
}

///|
/// 把 RouterConfig 的两个模型池做**值拷贝**（不共享 Array 元素）。
/// 用于 dry_run：pick 会对选中的 quota 写 window_start，若不拷贝会污染原 config。
/// 不能写 `map(fn(m){m})` —— MoonBit 对恒等闭包做 copy elision，返回的仍是原 object
/// 引用，后续 `pick` 写 `window_start` 会回流原 config（实测踩坑，见 caf_dry_1）。
fn clone_pools(config : RouterConfig) -> RouterConfig {
  {
    window_seconds: config.window_seconds,
    threshold_pct: config.threshold_pct,
    free_models: config.free_models.map(fn(m : ModelQuota) {
      ModelQuota::new(
        name=m.name,
        tier=m.tier,
        limit=m.limit,
        used=m.used,
        window_start=m.window_start,
        lane=m.lane,
        price_per_call=m.price_per_call,
        price_per_1k=m.price_per_1k,
        rank=m.rank,
        cooldown_until=m.cooldown_until,
      )
    }),
    paid_models: config.paid_models.map(fn(m : ModelQuota) {
      ModelQuota::new(
        name=m.name,
        tier=m.tier,
        limit=m.limit,
        used=m.used,
        window_start=m.window_start,
        lane=m.lane,
        price_per_call=m.price_per_call,
        price_per_1k=m.price_per_1k,
        rank=m.rank,
        cooldown_until=m.cooldown_until,
      )
    }),
    ofm_endpoint: config.ofm_endpoint,
    use_laya: config.use_laya,
    use_caf_memory: config.use_caf_memory,
  }
}
