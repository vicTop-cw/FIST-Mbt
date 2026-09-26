/// engine_eval.mbt —— 反馈收敛（R111 · Evaluator-Optimizer schema 蒸馏）。
/// 把自由文本反馈归一为四段式 Defects/Evidence/Fix/Acceptance 契约 + 确定性 verdict：
/// 无缺陷且 acceptance 非空 → pass（optimizer 可收敛）；否则 fail + 缺段/证据/修复标注。
/// 纯计算只读不写库（决策建议，执行权在调用方；与 plan_revise 反馈修订互补）。

///|
/// 从反馈文本解析某 `## 段名` 下的 `- 列表项`（遇到下一个 `## ` 标题即结束）。
fn parse_section(text : String, header : String) -> Array[String] {
  let out : Array[String] = []
  let mut in_section = false
  for line in text.split("\n") {
    let t = line.trim()
    if t.starts_with("## ") {
      in_section = t == ("## " + header)
    } else if in_section && t.starts_with("- ") {
      let s = t.to_owned()
      out.push(s.substring(start=2, end=s.length()))
    }
  }
  out
}

///|
/// 反馈文本中是否存在某 `## 段名` 标题（段"在场"判定，与条目数无关）。
fn section_present(text : String, header : String) -> Bool {
  for line in text.split("\n") {
    if line.trim() == ("## " + header) {
      return true
    }
  }
  false
}

///|
/// 反馈收敛：归一为四段式 schema + verdict（E/O 蒸馏：生成→评估→定向修订→收敛）。
/// 返回 { ok, task_id, schema:{defects,evidence,fix,acceptance}, counts, verdict, flags, note }。
pub fn FistEngine::eval_feedback(
  self : FistEngine,
  feedback : String,
  task_id? : String = "",
) -> Json {
  let defects = parse_section(feedback, "Defects")
  let evidence = parse_section(feedback, "Evidence")
  let fix = parse_section(feedback, "Fix")
  let acceptance = parse_section(feedback, "Acceptance")
  let d = defects.length()
  let e = evidence.length()
  let f = fix.length()
  let a = acceptance.length()
  let flags : Array[String] = []
  if d > 0 && e == 0 {
    flags.push("evidence_missing")
  }
  if d > 0 && f == 0 {
    flags.push("fix_missing")
  }
  let missing : Array[String] = []
  let has_defects = section_present(feedback, "Defects")
  if !has_defects {
    missing.push("Defects")
  }
  let has_evidence = section_present(feedback, "Evidence")
  if !has_evidence {
    missing.push("Evidence")
  }
  let has_fix = section_present(feedback, "Fix")
  if !has_fix {
    missing.push("Fix")
  }
  let has_acceptance = section_present(feedback, "Acceptance")
  if !has_acceptance {
    missing.push("Acceptance")
  }
  if missing.length() > 0 {
    flags.push("section_missing:" + missing.join(","))
  }
  let verdict = if d == 0 && a > 0 { "pass" } else { "fail" }
  let (sc_d, sc_e, sc_f, sc_a) = (d.to_double(), e.to_double(), f.to_double(), a.to_double())
  Json::object({
    "ok": Json::boolean(true),
    "task_id": Json::string(task_id),
    "schema": Json::object({
      "defects": Json::array(defects.map(Json::string)),
      "evidence": Json::array(evidence.map(Json::string)),
      "fix": Json::array(fix.map(Json::string)),
      "acceptance": Json::array(acceptance.map(Json::string)),
    }),
    "counts": Json::object({
      "defects": Json::number(sc_d),
      "evidence": Json::number(sc_e),
      "fix": Json::number(sc_f),
      "acceptance": Json::number(sc_a),
    }),
    "verdict": Json::string(verdict),
    "flags": Json::array(flags.map(Json::string)),
    "note": Json::string(
      "反馈收敛（Evaluator-Optimizer schema 蒸馏）：feedback 归一为 Defects/Evidence/Fix/Acceptance 四段式——无缺陷且 acceptance 非空 → pass 可收敛；否则 fail 定向回灌（Defects→Fix→再 eval→pass 闭环，硬上限防死循环）。",
    ),
  })
}
