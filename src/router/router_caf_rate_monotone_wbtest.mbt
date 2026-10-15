///|
/// R39：CAF 重排的**成功率不降**契约锁（验收标准 2「成功率不降」的纯计算侧）。
///
/// 标准 2 要求「开启后不增成本且成功率不降」。R38 已钉「不增成本」（caf_cost_1/2），
/// 但**未钉「成功率不降」**：若 CAF 把 base 的 free-a（rate 0.5）重排到 free-b（rate 1.0），
/// 重排是提升；但若重排到 rate 更低者，则违反标准 2。
/// 现有锁 `caf_dry_2` 只测 base/picked **不同**，未测**方向**（picked rate ≥ base rate）。
/// 本锁钉死「重排后 picked 的 rate ≥ base 的 rate」。
fn caf_dry_rate(stats : Array[CafModelStats], model : String) -> Double {
  for s in stats {
    if s.model == model {
      if s.total > 0 {
        return s.success.to_double() / s.total.to_double()
      }
      return 0.0
    }
  }
  0.0
}

///|
/// 重排后成功率不低于 base：mrc_memory 里 base=pick→free-a（rate 0.5），
/// CAF 重排→free-b（rate 1.0）。断言 picked rate ≥ base rate 且确实发生重排。
test "caf_rate_1_重排后成功率不低于base" {
  let r = mrc_router(true)
  let dr = r.pick_caf_dry_run(
    now=mrc_now(),
    caf_memory=mrc_memory(),
    context="test context",
    k=10,
  )
  if !dr.reordered {
    abort("本记忆应触发重排")
  }
  let base_rate = caf_dry_rate(dr.basis, dr.base.model_name)
  let picked_rate = caf_dry_rate(dr.basis, dr.picked.model_name)
  if picked_rate < base_rate {
    abort(
      "CAF 重排后成功率应不低于 base，base rate=" +
      base_rate.to_string() +
      " picked rate=" +
      picked_rate.to_string(),
    )
  }
  // 额外：确认这个场景确实是"低成功率 base 被替换成高成功率 picked"
  if dr.base.model_name != "free-a" || dr.picked.model_name != "free-b" {
    abort(
      "预期 base=free-a picked=free-b，实际 base=" +
      dr.base.model_name +
      " picked=" +
      dr.picked.model_name,
    )
  }
  if picked_rate <= base_rate {
    abort(
      "应严格提升（0.5 → 1.0），实际 base=" +
      base_rate.to_string() +
      " picked=" +
      picked_rate.to_string(),
    )
  }
}

///|
/// R46 · 标准 2 的 A/B 端到端真源锁（补齐 CAF 验收状态 L44「⚠ Python 预演 → 真源」缺口）。
/// caf_cost_1/2 与 caf_rate_1 分别锁了「成本决胜」与「成功率不降」，但**未锁 A/B 整体对比**——
/// 标准 2 要求「开启后成功率不降**且**成本不增」，需端到端比较 A（关闭 CAF 原序选首）与 B（开启 CAF 重排选首）。
///
/// 场景：free-a 邻域内 rate 0.5（1 ok + 1 fail）cost 0.1；free-b 邻域内 rate 1.0（1 ok）cost 0.1。
/// A 组按原序选 free-a；B 组 caf_soft_reorder 后选 free-b（rate 更高且 cost 不增）。
fn caf_ab_stats_lookup(
  stats : Array[CafModelStats],
  model : String,
) -> (Double, Double) {
  for s in stats {
    if s.model == model {
      let rate = if s.total > 0 {
        s.success.to_double() / s.total.to_double()
      } else {
        0.0
      }
      return (rate, s.avg_cost)
    }
  }
  abort("stats 里找不到模型 " + model)
}

///|
test "caf_ab_1_开启后成功率不降成本不增" {
  let h = caf_feature_hash("ab test context")
  let mem = CafMemory::new()
  mem.push(
    CafRecord::new(
      feature_hash=h,
      model="free-a",
      ok=true,
      cost=0.1,
      ts="2026-10-15T10:00:00Z",
    ),
  )
  mem.push(
    CafRecord::new(
      feature_hash=h,
      model="free-a",
      ok=false,
      cost=0.1,
      ts="2026-10-15T11:00:00Z",
    ),
  )
  mem.push(
    CafRecord::new(
      feature_hash=h,
      model="free-b",
      ok=true,
      cost=0.1,
      ts="2026-10-15T12:00:00Z",
    ),
  )
  let stats = caf_stats(mem.all())
  let candidates : Array[String] = ["free-a", "free-b"]
  // A 组（关闭 CAF，按原序选首）= free-a
  let (a_rate, a_cost) = caf_ab_stats_lookup(stats, "free-a")
  // B 组（开启 CAF，caf_soft_reorder 后选首）= 应重排到 free-b
  let reordered = caf_soft_reorder(candidates, stats)
  if reordered.length() != 2 {
    abort("应返回 2 个候选，实际 " + reordered.length().to_string())
  }
  if reordered[0] != "free-b" {
    abort(
      "标准 2 违约：重排首位应为 rate 1.0 的 free-b，实际 " +
      reordered[0],
    )
  }
  let (b_rate, b_cost) = caf_ab_stats_lookup(stats, reordered[0])
  // 标准 2 核心：开启后成功率不降（B rate ≥ A rate）
  if b_rate < a_rate {
    abort(
      "开启后成功率下降：" +
      b_rate.to_string() +
      " < " +
      a_rate.to_string(),
    )
  }
  // 标准 2 核心：开启后成本不增（B cost ≤ A cost）
  if b_cost > a_cost {
    abort(
      "开启后成本增加：" +
      b_cost.to_string() +
      " > " +
      a_cost.to_string(),
    )
  }
}
