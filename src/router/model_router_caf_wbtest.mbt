/// model_router_caf_wbtest.mbt —— P2c §2.2：pick_caf 软性重排的回归锁
///
/// 覆盖：
///   1. use_caf_memory=false → 零回归，返回原 pick 决策
///   2. 空 CAF 记忆 → 返回原决策
///   3. 软性重排命中不同模型且健康 → 采用重排第一名
///   4. 重排第一名在冷却期 → 回退原决策

///|
fn mrc_now() -> String {
  "2026-10-15T18:00:00Z"
}

///|
/// 造一个 CAF 路由器：free 2 模型（free-a/free-b），游标 0 起 → base pick 恒为 free-a
fn mrc_router(use_caf : Bool) -> ModelRouter {
  let cfg : RouterConfig = {
    window_seconds: 18000,
    threshold_pct: 95.0,
    free_models: [
      ModelQuota::new(name="free-a", tier=Free, limit=10),
      ModelQuota::new(name="free-b", tier=Free, limit=10),
    ],
    paid_models: [],
    ofm_endpoint: "",
    use_laya: false,
    use_caf_memory: use_caf,
  }
  ModelRouter::from_config(cfg)
}

///|
/// 造一份 CAF 记忆：free-a 50% 成功，free-b 100% 成功（同一 hash）
fn mrc_memory() -> CafMemory {
  let h = caf_feature_hash("test context")
  let mem = CafMemory::new()
  mem.push(
    CafRecord::new(
      feature_hash=h,
      model="free-a",
      ok=true,
      cost=1.0,
      ts="2026-10-15T10:00:00Z",
    ),
  )
  mem.push(
    CafRecord::new(
      feature_hash=h,
      model="free-a",
      ok=false,
      cost=1.0,
      ts="2026-10-15T11:00:00Z",
    ),
  )
  mem.push(
    CafRecord::new(
      feature_hash=h,
      model="free-b",
      ok=true,
      cost=1.0,
      ts="2026-10-15T12:00:00Z",
    ),
  )
  mem.push(
    CafRecord::new(
      feature_hash=h,
      model="free-b",
      ok=true,
      cost=1.0,
      ts="2026-10-15T13:00:00Z",
    ),
  )
  mem
}

///|
test "caf_pick_1_use_caf_memory_false 零回归" {
  let r = mrc_router(false)
  let (d, reordered) = r.pick_caf(
    now=mrc_now(),
    caf_memory=mrc_memory(),
    context="test context",
    k=10,
  )
  if reordered {
    abort("use_caf_memory=false 不应发生重排")
  }
  if d.model_name != "free-a" {
    abort("应返回 free-a，实际 " + d.model_name)
  }
}

///|
test "caf_pick_2_空记忆返回原决策" {
  let r = mrc_router(true)
  let empty = CafMemory::new()
  let (d, reordered) = r.pick_caf(
    now=mrc_now(),
    caf_memory=empty,
    context="test context",
    k=10,
  )
  if reordered {
    abort("空记忆不应发生重排")
  }
  if d.model_name != "free-a" {
    abort("应返回 free-a，实际 " + d.model_name)
  }
}

///|
test "caf_pick_3_软性重排命中更高成功率模型" {
  let r = mrc_router(true)
  let (d, reordered) = r.pick_caf(
    now=mrc_now(),
    caf_memory=mrc_memory(),
    context="test context",
    k=10,
  )
  if !reordered {
    abort("应发生重排")
  }
  if d.model_name != "free-b" {
    abort(
      "应重排到 free-b（100% 成功率 > free-a 50%），实际 " +
      d.model_name,
    )
  }
}

///|
test "caf_pick_4_重排第一名在冷却期则回退" {
  // 直接造一个 free-b 已在冷却期的路由器（冷却截止不能超 Y2038，BUG-218）
  let fb = ModelQuota::new(name="free-b", tier=Free, limit=10)
  fb.cooldown_until = "2026-10-15T18:10:00Z"
  let cfg : RouterConfig = {
    window_seconds: 18000,
    threshold_pct: 95.0,
    free_models: [ModelQuota::new(name="free-a", tier=Free, limit=10), fb],
    paid_models: [],
    ofm_endpoint: "",
    use_laya: false,
    use_caf_memory: true,
  }
  let r = ModelRouter::from_config(cfg)
  let pool = r.active_pool()
  if !pool[1].in_cooldown(mrc_now()) {
    abort("pool[1] 未处于冷却期")
  }
  let (d, reordered) = r.pick_caf(
    now=mrc_now(),
    caf_memory=mrc_memory(),
    context="test context",
    k=10,
  )
  if reordered {
    abort("冷却中的模型不应被采用")
  }
  if d.model_name != "free-a" {
    abort("应回退到 free-a，实际 " + d.model_name)
  }
}

///|
/// P2c §2.3 前置：pick_caf_dry_run 的零副作用承诺。
/// dry_run 之后，原路由器的游标 / 选中模型 / 配额 window_start 都必须原样不动。
test "caf_dry_1_dry_run 零副作用（游标/配额不被污染）" {
  let r = mrc_router(true)
  let free_idx_before = r.free_idx
  let ws_before = r.config.free_models[0].window_start
  let last_pick_before = r.last_pick
  let dr = r.pick_caf_dry_run(
    now=mrc_now(),
    caf_memory=mrc_memory(),
    context="test context",
    k=10,
  )
  if r.free_idx != free_idx_before {
    abort("dry_run 不应推进 free_idx")
  }
  if r.last_pick != last_pick_before {
    abort("dry_run 不应改动 last_pick")
  }
  if r.config.free_models[0].window_start != ws_before {
    abort("dry_run 不应写 window_start")
  }
  if !dr.reordered {
    abort("应命中重排（记忆显示 free-b 100%）")
  }
}

///|
/// P2c §2.3 前置：dry_run 的对照语义。
/// base 是纯 pick（游标 0 → free-a），picked 是 CAF 重排（free-b），basis 非空。
test "caf_dry_2_dry_run 返回 base/picked 对照与历史依据" {
  let r = mrc_router(true)
  let dr = r.pick_caf_dry_run(
    now=mrc_now(),
    caf_memory=mrc_memory(),
    context="test context",
    k=10,
  )
  if dr.base.model_name != "free-a" {
    abort("base 应为 free-a，实际 " + dr.base.model_name)
  }
  if dr.picked.model_name != "free-b" {
    abort("picked 应为 free-b，实际 " + dr.picked.model_name)
  }
  if !dr.reordered {
    abort("应报告发生了重排")
  }
  if dr.basis.length() == 0 {
    abort("basis 不应为空")
  }
  if dr.top_k != 10 {
    abort("top_k 应为 10，实际 " + dr.top_k.to_string())
  }
}

///|
/// P2c §2.3 前置：dry_run 的零回归。
/// use_caf_memory=false 时 picked == base 且 reordered=false。
test "caf_dry_3_dry_run 关闭 CAF 时零回归" {
  let r = mrc_router(false)
  let dr = r.pick_caf_dry_run(
    now=mrc_now(),
    caf_memory=mrc_memory(),
    context="test context",
    k=10,
  )
  if dr.reordered {
    abort("关闭 CAF 时不应重排")
  }
  if dr.picked.model_name != dr.base.model_name {
    abort("关闭 CAF 时 picked 应等于 base")
  }
}

///|
/// P2c §2.3 回写通路的前置真源：CafMemory::push 必须**真的**更新 count，
/// 且 push 后的记录必须能被 knn_stats 聚合、被 pick_caf_dry_run 消费。
/// 若 push 的 `self : CafMemory` 值接收导致 count/head 不传播（MoonBit 严格值语义），
/// 则 §2.3 的 `caf_memory.push(...)` 回写形同虚设——本条锁就是要钉死这一格。
test "caf_loop_1_记忆可写可读闭环（§2.3 回写通路真源）" {
  let mem = CafMemory::new()
  if mem.count != 0 {
    abort("初始 count 应为 0")
  }
  let h = caf_feature_hash("loop context")
  mem.push(
    CafRecord::new(
      feature_hash=h,
      model="free-a",
      ok=false,
      cost=1.0,
      ts="2026-10-15T10:00:00Z",
    ),
  )
  if mem.count != 1 {
    abort("push 1 次后 count 应为 1，实际 " + mem.count.to_string())
  }
  mem.push(
    CafRecord::new(
      feature_hash=h,
      model="free-a",
      ok=false,
      cost=1.0,
      ts="2026-10-15T11:00:00Z",
    ),
  )
  mem.push(
    CafRecord::new(
      feature_hash=h,
      model="free-b",
      ok=true,
      cost=1.0,
      ts="2026-10-15T12:00:00Z",
    ),
  )
  if mem.count != 3 {
    abort("3 次 push 后 count 应为 3，实际 " + mem.count.to_string())
  }
  // 记忆可读：knn_stats 聚合出 free-a / free-b 两条统计
  let stats = mem.knn_stats("loop context", 10)
  if stats.length() != 2 {
    abort("knn_stats 应聚合出 2 条，实际 " + stats.length().to_string())
  }
  // 记忆驱动决策：dry_run 应重排到 free-b（100% 成功 vs free-a 0%）
  let r = mrc_router(true)
  let dr = r.pick_caf_dry_run(
    now=mrc_now(),
    caf_memory=mem,
    context="loop context",
    k=10,
  )
  if !dr.reordered {
    abort("记忆应驱动重排")
  }
  if dr.picked.model_name != "free-b" {
    abort("应重排到 free-b，实际 " + dr.picked.model_name)
  }
}

///|
/// P2c+P2d 统一：默认偏好为空时，行为与 R29 完全一致（零回归）。
test "caf_pref_1_默认偏好为空时行为与无偏好一致" {
  let r = mrc_router(true)
  let dr_no = r.pick_caf_dry_run(
    now=mrc_now(),
    caf_memory=mrc_memory(),
    context="test context",
    k=10,
  )
  let dr_empty = r.pick_caf_dry_run(
    now=mrc_now(),
    caf_memory=mrc_memory(),
    context="test context",
    k=10,
    caf_default_preference=[],
    caf_min_evidences=10,
  )
  if dr_no.reordered != dr_empty.reordered {
    abort("偏好为空时 reordered 应一致")
  }
  if dr_no.picked.model_name != dr_empty.picked.model_name {
    abort("偏好为空时 picked 应一致")
  }
}

///|
/// P2c+P2d 统一：记忆不足时按冷启动偏好重排（base=free-a 但偏好 free-b → 切到 free-b）。
test "caf_pref_2_记忆不足按冷启动偏好重排" {
  let mem = CafMemory::new() // 空记忆，stats=0 < min_evidences=10
  let r = mrc_router(true)
  let dr = r.pick_caf_dry_run(
    now=mrc_now(),
    caf_memory=mem,
    context="pref context",
    k=10,
    caf_default_preference=["free-b"],
    caf_min_evidences=10,
  )
  if !dr.reordered {
    abort("记忆不足且偏好 free-b 时应重排到 free-b")
  }
  if dr.picked.model_name != "free-b" {
    abort("应选偏好 free-b，实际 " + dr.picked.model_name)
  }
}

///|
/// P2c+P2d 统一：记忆充足时偏好退化为成功率排序——即使偏好指定 free-a，
/// 若 free-b 证据更优，仍应选 free-b（真实证据优先于冷启动偏好）。
test "caf_pref_3_记忆充足时偏好退化为成功率排序" {
  let r = mrc_router(true)
  let dr = r.pick_caf_dry_run(
    now=mrc_now(),
    caf_memory=mrc_memory(),
    context="test context",
    k=10,
    caf_default_preference=["free-a"],
    caf_min_evidences=1, // mrc_memory 有 3 条 ≥ 1，视为记忆充足
  )
  if !dr.reordered {
    abort("记忆充足时应重排")
  }
  if dr.picked.model_name != "free-b" {
    abort(
      "记忆充足应选证据更优的 free-b，而不是偏好 free-a，实际 " +
      dr.picked.model_name,
    )
  }
}
