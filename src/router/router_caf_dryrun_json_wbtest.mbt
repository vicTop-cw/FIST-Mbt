///|
/// R37：CAF dry_run 预览 JSON 输出的契约锁（验收标准 3 的纯计算侧）。
/// 钉死 `caf_dry_run_to_json` 输出标准 3 形状：
/// `{"suggestion": model, "base": model, "reordered": bool, "top_k": Int, "basis":[{model,rate,avg_cost,count}]}`
/// 复用 model_router_caf_wbtest 的 helper 生成真实 CafDryRun（whitebox，可读私有字段）。

///|
/// 标准 3 形状：suggestion=重排后模型、base=纯 pick、basis 每条含 rate/avg_cost/count。
test "caf_dj_1_标准3形状" {
  let r = mrc_router(true)
  let dr = r.pick_caf_dry_run(
    now=mrc_now(),
    caf_memory=mrc_memory(),
    context="test context",
    k=10,
  )
  let json = caf_dry_run_to_json(dr)
  let obj = match json {
    Json::Object(m) => m
    _ => abort("顶层应为对象")
  }
  let sugg = match obj.get("suggestion") {
    Some(Json::String(s)) => s
    _ => abort("suggestion 应为字符串")
  }
  let base = match obj.get("base") {
    Some(Json::String(s)) => s
    _ => abort("base 应为字符串")
  }
  let reordered = match obj.get("reordered") {
    Some(Json::True) => true
    Some(Json::False) => false
    _ => abort("reordered 应为布尔")
  }
  let top_k = match obj.get("top_k") {
    Some(Json::Number(n, ..)) => n.to_int()
    _ => abort("top_k 应为数字")
  }
  // suggestion 必须等于真实 picked.model_name，base 等于真实 base.model_name
  if sugg != dr.picked.model_name {
    abort("suggestion 应等于 picked.model_name，实际 " + sugg)
  }
  if base != dr.base.model_name {
    abort("base 应等于 base.model_name，实际 " + base)
  }
  if reordered != dr.reordered {
    abort("reordered 应与真实值一致")
  }
  if top_k != dr.top_k {
    abort("top_k 应与真实值一致")
  }
  let basis = match obj.get("basis") {
    Some(Json::Array(a)) => a
    _ => abort("basis 应为数组")
  }
  if basis.length() != dr.basis.length() {
    abort("basis 长度应一致，实际 " + basis.length().to_string())
  }
  if basis.length() == 0 {
    abort("basis 不应为空（标准 3 需返回历史依据）")
  }
  // 逐条校验 basis 字段形状
  for item in basis {
    let bobj = match item {
      Json::Object(m) => m
      _ => abort("basis 元素应为对象")
    }
    if bobj.get("model") is None {
      abort("basis 元素缺 model")
    }
    if bobj.get("rate") is None {
      abort("basis 元素缺 rate")
    }
    if bobj.get("avg_cost") is None {
      abort("basis 元素缺 avg_cost")
    }
    if bobj.get("count") is None {
      abort("basis 元素缺 count")
    }
  }
}

///|
/// 形状不变量：basis 每条 rate ∈ [0,1]、count ≥ 1、avg_cost ≥ 0、model 非空。
/// rate = success/total（真实数据 total>0 时），count = total。
test "caf_dj_2_basis字段不变量" {
  let r = mrc_router(true)
  let dr = r.pick_caf_dry_run(
    now=mrc_now(),
    caf_memory=mrc_memory(),
    context="test context",
    k=10,
  )
  let json = caf_dry_run_to_json(dr)
  let obj = match json {
    Json::Object(m) => m
    _ => abort("顶层应为对象")
  }
  let basis = match obj.get("basis") {
    Some(Json::Array(a)) => a
    _ => abort("basis 应为数组")
  }
  for item in basis {
    let bobj = match item {
      Json::Object(m) => m
      _ => abort("basis 元素应为对象")
    }
    let model = match bobj.get("model") {
      Some(Json::String(s)) => s
      _ => abort("model 应为字符串")
    }
    if model.length() == 0 {
      abort("model 不应为空")
    }
    let rate = match bobj.get("rate") {
      Some(Json::Number(n, ..)) => n
      _ => abort("rate 应为数字")
    }
    if rate < 0.0 || rate > 1.0 {
      abort("rate 应在 [0,1]，实际 " + rate.to_string())
    }
    let cost = match bobj.get("avg_cost") {
      Some(Json::Number(n, ..)) => n
      _ => abort("avg_cost 应为数字")
    }
    if cost < 0.0 {
      abort("avg_cost 不应为负，实际 " + cost.to_string())
    }
    let count = match bobj.get("count") {
      Some(Json::Number(n, ..)) => n.to_int()
      _ => abort("count 应为数字")
    }
    if count < 1 {
      abort(
        "count 应 ≥ 1（有历史依据才进 basis），实际 " +
        count.to_string(),
      )
    }
  }
}
