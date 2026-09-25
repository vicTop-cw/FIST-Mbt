/// src/engine/docs_gate.mbt — 「文档即实现」验收门禁（可选开关，默认关闭）。
///
/// 把「文档-交付物一致性」从口头习惯升格为 verify 前的可选门禁：
/// 复用 @omega.check_structure(project_dir) 校验 README.md/CHANGELOG.md/reports 存在，
/// 用 @omega.check_report_format(deliverable) 校验回传五段式。
/// 任一未达标 → Err(含 item:detail 明细) 即打回 reason。与 omega_verify_gate /
/// gate_verify_gate 同构：仅在显式开启时生效，默认 Ok 不回归。

///|
/// 仅提取 check 结果里 passed=false 的失败明细，拼接成人语可读的错误文案。
/// 返回失败段数组（如全过则空）。
fn collect_failures(results : Array[Json]) -> Array[String] {
  let out : Array[String] = []
  for j in results {
    let mut item = "<unknown>"
    let mut detail = ""
    match j {
      Object(m) => {
        item = match m.get("item") {
          Some(String(s)) => s
          _ => "<unknown>"
        }
        detail = match m.get("detail") {
          Some(String(s)) => s
          _ => ""
        }
      }
      _ => ()
    }
    // 判定 passed：默认失败，仅当字段存在且为 true 才算过
    let ok = match j {
      Object(m) =>
        match m.get("passed") {
          Some(True) => true
          _ => false
        }
      _ => false
    }
    if !ok {
      out.push("\{item}: \{detail}")
    }
  }
  out
}

///|
/// 「文档即实现」验收门禁：task 需为 [docs:required] 或显式传 docs_check=true 时生效。
/// 校验结构与回传格式，任一项缺失/不达标 → Err（含明细）。
pub fn FistEngine::docs_verify_gate(
  self : FistEngine,
  task_id : String,
) -> Result[Unit, String] {
  let t = match self.store.get_task(task_id) {
    None => return Err("task not found: \{task_id}")
    Some(x) => x
  }
  let fail_buf : Array[String] = []
  // 1) 项目结构（README.md / CHANGELOG.md / reports/ 存在性）
  let proj = t.project_dir
  if proj.is_empty() {
    fail_buf.push("project_dir 为空，无法校验项目结构")
  } else {
    let struct_res = @omega.check_structure(proj)
    let f1 = collect_failures(struct_res)
    for x in f1 {
      fail_buf.push(x)
    }
  }
  // 2) 交付物回传五段式
  let dlv = t.deliverable
  let fmt_res = @omega.check_report_format(dlv)
  let f2 = collect_failures(fmt_res)
  for x in f2 {
    fail_buf.push(x)
  }
  if fail_buf.is_empty() {
    Ok(())
  } else {
    Err("文档一致性门禁未通过：\{fail_buf.join("；")}")
  }
}
