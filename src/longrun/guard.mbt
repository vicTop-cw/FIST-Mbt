/// guard.mbt —— T0r56 长程任务护栏（提案方案 C · P1）。
///
/// 职责边界（只做 guard，不越界）：
///   · **双阈值熔断**（提案 D2=C）：token 预算超限 **或** 失败比例超阈，
///     任一超限即拦截（allowed=false）——两个阈值是「或」关系，
///     任一条失控都足以叫停，不是两条都爆才拦。
///   · **幂等键任务内去重**（提案 D3=A）：判定与登记复用 core 的
///     `Task::idempotency_add` / `has_idempotency_key`（单真源，不另立一套）。
///
/// 设计口径（与 P0 同形）：
///   · **裁决是纯函数**（`guard_decision`），IO 只是它的外壳
///     —— 判例-29：机制格必须能被白盒直接断言。
///   · 阈值不进库、不落配置：默认值以常量钉在这里，调用面可逐次覆盖
///     （预算单位由调用方定义，库内只比大小、不解释单位——与 budget_used 注释同口径）。

///|
/// 失败比例默认阈值（百分比）：提案 D2 的 B 选项示例值 30%。
pub const GUARD_FAILURE_RATIO_PCT : Int32 = 30

///|
/// 失败比例判定的最小样本数：总数不足时**不**启用比例阈值——
/// 3 步里失败 1 步（33%）就熔断，会让长程任务刚起步就被噪声打死。
pub const GUARD_MIN_SAMPLES : Int32 = 3

///|
/// 失败比例（百分比，向下取整）：`failed / total * 100`。
/// total<=0 时返回 0（没有样本就没有失败，比例不参与裁决）。
pub fn failure_ratio_pct(failed : Int32, total : Int32) -> Int32 {
  if total <= 0 {
    0
  } else {
    failed * 100 / total
  }
}

///|
/// **guard 双阈值裁决（纯函数，P1 的核心，提案 D2=C）**。
///
/// 拦截条件（任一命中即 allowed=false，并把原因写进 reasons）：
///   1. **预算超限**：`budget_limit > 0` 且 `budget_used > budget_limit`
///      （limit<=0 表示未设预算，该阈值不参与裁决）；
///   2. **失败比例超阈**：`total >= min_samples` 且
///      `failure_ratio_pct(failed, total) > ratio_pct`（严格大于——恰好在阈值上
///      不拦，3/10=30% 不是超限，4/10=40% 才是）。
///
/// 返回 `(allowed, reasons)`：reasons 为空即放行；每条原因点名是哪个阈值、
/// 实得多少、限多少——调用方（人/agent）据此知道该续跑还是该收尾。
pub fn guard_decision(
  budget_used : Int64,
  budget_limit : Int64,
  failed : Int32,
  total : Int32,
  ratio_pct : Int32,
  min_samples : Int32,
) -> (Bool, Array[String]) {
  let reasons : Array[String] = []
  if budget_limit > 0L && budget_used > budget_limit {
    reasons.push(
      "预算超限：已用 \{budget_used} > 上限 \{budget_limit}（token 口径由调用方定义）",
    )
  }
  if total >= min_samples {
    let actual = failure_ratio_pct(failed, total)
    if actual > ratio_pct {
      reasons.push(
        "失败比例超阈：\{failed}/\{total}=\{actual}% > 阈值 \{ratio_pct}%",
      )
    }
  }
  (reasons.is_empty(), reasons)
}
