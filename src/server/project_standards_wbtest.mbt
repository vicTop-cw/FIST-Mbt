/// project_standards_wbtest.mbt —— R116 四态规范的白盒回归锁。
///
/// 为什么必须有：`project_standards` 是对外承诺"本项目怎么算合规"的工具，此前
/// **零测试覆盖**——它自己写成什么，守卫就信什么（BUG-22/30 那一类"主张宽于判据"）。
/// 本轮把三形态升级为「一源四态」，顺手把这份承诺钉死：
///   ① 计数稳定（通用 5 + 专项 5，checklist 7 项）；
///   ② cl7-plugin-forms-sync 存在且 gate=hard（插件态漂移必须能打回）；
///   ③ 文案不得残留"三形态/一源三态"（升级只改一处、别处仍说三态=文档假升级）；
///   ④ include_checklist=false 的调用面形状不变（零回归）。

///|
/// 带诊断的断言（本仓库 assert 的 msg 参数跨版本不稳，沿用 run_check_guard_test 的 abort 传话）。
fn ps_must(cond : Bool, msg : String) -> Unit {
  if cond {
    ()
  } else {
    abort(msg)
  }
}

///|
fn ps_str(j : Json, key : String) -> String {
  match j.value(key) {
    Some(Json::String(s)) => s
    _ => "<缺 String 字段 " + key + ">"
  }
}

///|
fn ps_arr_len(j : Json, key : String) -> Int {
  match j.value(key) {
    Some(Json::Array(arr)) => arr.length()
    _ => -1
  }
}

///|
fn ps_num(j : Json, key : String) -> Double {
  match j.value(key) {
    Some(Json::Number(n, ..)) => n
    _ => -1.0
  }
}

///|
test "R116：一源四态——规范文案不再自称三形态，且版本号已升档" {
  let j = project_standards("moonbit-mcp", true)
  let v = ps_str(j, "version")
  ps_must(v == "R116", "version 应为 R116，实际 " + v)
  ps_must(
    ps_str(j, "canonical_doc") == "AI-DEVELOPMENT-STANDARD.md",
    "规范必须指向单真源正文 AI-DEVELOPMENT-STANDARD.md（缺指针=机器投影与正文各说一套）",
  )
  let text = j.stringify()
  ps_must(
    !text.contains("三形态"),
    "规范里仍自称「三形态」：升级没改到这一处",
  )
  ps_must(
    !text.contains("一源三态"),
    "通用规则 r2 仍写「一源三态」",
  )
  ps_must(text.contains("一源四态"), "r2 应主张「一源四态」")
  ps_must(text.contains("四态必须对齐"), "f2 应主张四态对齐")
  ps_must(
    text.contains("gen_plugins.py"),
    "f2/r2 的查法必须指向真实生成器",
  )
}

///|
test "R116：checklist 7 项，cl7-plugin-forms-sync 为 hard 门" {
  let j = project_standards("moonbit-mcp", true)
  ps_must(ps_arr_len(j, "general_rules") == 5, "通用规则应恰 5 条")
  ps_must(ps_arr_len(j, "fist_specific_rules") == 5, "FIST 专项应恰 5 条")
  let cl = ps_arr_len(j, "checklist")
  ps_must(cl == 7, "checklist 应升为 7 项，实际 " + cl.to_string())
  let total = ps_num(j, "count_total")
  ps_must(
    total == 10.0,
    "count_total 应为 10（5+5，checklist 不计入），实际 " +
    total.to_string(),
  )
  let mut gate7 = "<无 cl7>"
  let mut ids = ""
  match j.value("checklist") {
    Some(Json::Array(arr)) =>
      for item in arr {
        let id = ps_str(item, "id")
        ids = ids + " " + id
        if id == "cl7-plugin-forms-sync" {
          gate7 = ps_str(item, "gate")
        }
      }
    _ => ()
  }
  ps_must(gate7 == "hard", "cl7 必须是 hard 门，实际 " + gate7)
  ps_must(
    ids.contains("cl6-doc-sync"),
    "cl6 不能被删掉（既有验收面）",
  )
  ps_must(ids.contains("cl1-mcp-exists"), "cl1 不能被删掉")
}

///|
test "R116：include_checklist=false 时不多发字段（零回归：既有调用面形状不变）" {
  let j = project_standards("moonbit-mcp", false)
  ps_must(ps_arr_len(j, "general_rules") == 5, "通用规则应仍 5 条")
  let text = j.stringify()
  ps_must(
    !text.contains("cl7-plugin-forms-sync"),
    "关 checklist 却仍下发 cl7：调用面形状变了",
  )
  ps_must(
    !text.contains("\"checklist\""),
    "关 checklist 却仍下发 checklist 字段",
  )
}
