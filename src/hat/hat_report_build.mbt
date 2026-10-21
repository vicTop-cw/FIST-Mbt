/// hat_report_build.mbt —— HexaMind 六元自驱决策 · 最终裁决报告组装（纯计算）
///
/// 把 topic + 已解析 config + 各单元报告 + 分歧 + 收敛读数，组装成一份可读的
/// 裁决报告（结构体 + Markdown 正文）。**引擎只给读数，终审门 = 用户**。

///|
/// 一次 HexaMind 裁决报告。
pub struct HatVerdictReport {
  topic : String
  status : String
  // converged | partial | diverged
  convergence : ConvergeResult
  divergences : Array[Divergence]
  reports : Array[HatReport]
  should_iterate : Bool
  terminal_gate : String
  // 恒 "user"
  markdown : String
}

///|
/// 组装最终报告。round 从 1 起；reports 未校验的（如空 evidence）自动跳过并诚实标注。
pub fn build_report(
  topic : String,
  config : HatConfig,
  reports : Array[HatReport],
  round : Int32,
) -> HatVerdictReport {
  // 只保留合法报告（不崩溃，空/非法项被剔除并计入 skipped）
  let valid : Array[HatReport] = []
  let mut skipped = 0
  for r in reports {
    match valid_report(r) {
      Ok(_) => valid.push(r)
      Err(_) => skipped = skipped + 1
    }
  }

  let divergences = extract_divergences(valid)
  let convergence = converge(valid, config.policy, round)
  let md = render_markdown(
    topic, config, valid, divergences, convergence, skipped,
  )

  {
    topic,
    status: convergence.status,
    convergence,
    divergences,
    reports: valid,
    should_iterate: convergence.should_iterate,
    terminal_gate: "user",
    markdown: md,
  }
}

// ---------------------------------------------------------------------------
// Markdown 渲染
// ---------------------------------------------------------------------------

///|
fn render_markdown(
  topic : String,
  config : HatConfig,
  reports : Array[HatReport],
  divergences : Array[Divergence],
  c : ConvergeResult,
  skipped : Int32,
) -> String {
  let mut s = "# HexaMind 六元裁决报告\n\n"
  s = s + "**议题**：" + topic + "\n\n"
  s = s +
    "**收敛状态**：" +
    status_zh(c.status) +
    "（" +
    c.status +
    "）\n\n"
  s = s + "## 收敛读数\n\n"
  s = s +
    "- 一致率 rate：" +
    c.rate.to_string() +
    "（agree=" +
    c.agree.to_string() +
    " / total=" +
    c.total.to_string() +
    "，阈值 " +
    c.threshold.to_string() +
    "）\n"
  s = s + "- 阻止收敛的分歧：" + c.blocking.to_string() + "\n"
  s = s + "- 建议再迭代：" + c.should_iterate.to_string() + "\n"
  s = s +
    "- 轮次：" +
    c.round.to_string() +
    "/" +
    c.max_rounds.to_string() +
    "\n"
  s = s +
    "- 终审门：" +
    c.terminal_gate +
    "（引擎只给读数，不代用户裁决）\n"
  if skipped > 0 {
    s = s + "- 被剔除的非法报告：" + skipped.to_string() + " 条\n"
  }
  s = s + "\n"

  // 各单元
  s = s + "## 各单元结论\n\n"
  s = s + "| 单元 | 帽子 | 判决 | 置信度 | 依据 |\n"
  s = s + "|---|---|---|---|---|\n"
  for r in reports {
    let el = match hexa_for_id(r.element_id) {
      Ok(e) => e.name_zh + "（" + r.element_id + "）"
      Err(_) => r.element_id
    }
    let ev = r.evidence.replace(old="\n", new=" ")
    s = s +
      "| " +
      el +
      " | " +
      // BUG-205：本列是"帽子"，此前误填 r.verdict（与"判决"列重复）。
      // 六元代号→六顶帽 id 的单真源是 hexa_hat_id（white/red/black/yellow/green/blue）。
      hexa_hat_id(r.element_id) +
      " | " +
      r.verdict +
      " | " +
      r.confidence.to_string() +
      " | " +
      ev +
      " |\n"
  }
  s = s + "\n"

  // 分歧
  s = s + "## 分歧清单（程序化提取，零 LLM 自评）\n\n"
  if divergences.is_empty() {
    s = s + "无分歧。\n"
  } else {
    s = s + "| 类型 | 左 | 右 | 严重度 | 说明 |\n"
    s = s + "|---|---|---|---|---|\n"
    for d in divergences {
      s = s +
        "| " +
        d.kind +
        " | " +
        d.left +
        " | " +
        d.right +
        " | " +
        d.severity.to_string() +
        " | " +
        d.detail +
        " |\n"
    }
  }
  s = s + "\n## 已选六元\n\n"
  let mut ids = ""
  for i = 0; i < config.elements.length(); i = i + 1 {
    if i > 0 {
      ids = ids + ", "
    }
    ids = ids + config.elements[i].id
  }
  s = s +
    "[" +
    ids +
    "]；策略：max_rounds=" +
    config.policy.max_rounds.to_string() +
    "，threshold=" +
    config.policy.converge_threshold.to_string() +
    "，debate=" +
    config.policy.debate_enabled.to_string() +
    "。\n"
  s
}

///|
fn status_zh(status : String) -> String {
  match status {
    "converged" => "已收敛"
    "partial" => "部分收敛"
    "diverged" => "未收敛"
    _ => status
  }
}
