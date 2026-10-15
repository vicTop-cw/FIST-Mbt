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
