///|
/// CAF dry_run 预览结果的 JSON 输出层（验收标准 3 的纯计算侧）。
///
/// 标准 3 预期产物形状：`{"suggestion": model, "basis": [{model, rate, avg_cost, count}]}`。
/// `pick_caf_dry_run` 已返回 `CafDryRun`（建议模型 + 历史依据），但缺 JSON 输出；
/// server 层接线（§2.3）时可直接用本函数把 `CafDryRun` 转成标准 3 形状，
/// 避免接线时在 server 层手搓 JSON（易错、易漂移）。
///
/// `rate` = success/total（total=0 时 0），`count` = total（与 `CafMemory::to_json` 的
/// by_model 聚合口径一致）。

///|
/// 把 CafDryRun 转成标准 3 形状的 JSON。
pub fn caf_dry_run_to_json(dr : CafDryRun) -> Json {
  Json::object({
    "suggestion": Json::string(dr.picked.model_name),
    "base": Json::string(dr.base.model_name),
    "reordered": Json::boolean(dr.reordered),
    "top_k": Json::number(dr.top_k.to_double()),
    "basis": Json::array(
      dr.basis.map(fn(s) {
        let rate = if s.total > 0 {
          s.success.to_double() / s.total.to_double()
        } else {
          0.0
        }
        Json::object({
          "model": Json::string(s.model),
          "rate": Json::number(rate),
          "avg_cost": Json::number(s.avg_cost),
          "count": Json::number(s.total.to_double()),
        })
      }),
    ),
  })
}
