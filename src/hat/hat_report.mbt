/// hat_report.mbt —— HexaMind 六元自驱决策 · 单元报告（纯计算）
///
/// 单顶帽（单元）返回的结构化结论：verdict + confidence + evidence + outcomes。
/// verdict ∈ {pass, reject, abstain}；evidence 必填非空；confidence ∈ [0,1]。
/// 与 ops_hats.HatVerdict 同语（verdict/evidence 语义一致），但多出 confidence 与
/// outcomes 两个键，用于分歧提取（hat_divergence.mbt）与置信度落差对比。

///|
/// 一个单元的报告。
pub struct HatReport {
  pub element_id : String
  // 六元代号（stargazer/.../nucleus）
  pub verdict : String
  // pass | reject | abstain
  pub confidence : Double
  // 0..1，该单元对自己结论的置信度
  pub evidence : String
  // 必填非空：该视角的依据/理由
  pub outcomes : Array[String]
  // 该单元产出的结构化条目（facts / risks / benefits / alternatives ...）
  pub raw : String
  // 原始文本（可空，用于回溯）
}

///|
/// 构造一条单元报告。**跨包构造必需**：MoonBit 下跨包 struct 只能函数构造。
pub fn hat_report(
  element_id : String,
  verdict : String,
  confidence : Double,
  evidence : String,
  outcomes : Array[String],
  raw : String,
) -> HatReport {
  { element_id, verdict, confidence, evidence, outcomes, raw, }
}

///|
/// 单条报告校验：未知六元 / 非法 verdict / 越界 confidence / 空 evidence 一律 Err。
pub fn valid_report(r : HatReport) -> Result[Unit, String] {
  match hexa_for_id(r.element_id) {
    Ok(_) => ()
    Err(m) => return Err(m)
  }
  if r.evidence.trim().is_empty() {
    return Err("element_id=" + r.element_id + " evidence 不能为空")
  }
  if r.confidence < 0.0 || r.confidence > 1.0 {
    return Err(
      "element_id=" +
      r.element_id +
      " confidence 必须在 [0,1]（收到 " +
      r.confidence.to_string() +
      "）",
    )
  }
  match r.verdict {
    "pass" => Ok(())
    "reject" => Ok(())
    "abstain" => Ok(())
    _ => Err("element_id=" + r.element_id + " 非法 verdict: " + r.verdict)
  }
}
