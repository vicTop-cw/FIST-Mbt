/// engine_eval_test.mbt —— 反馈收敛（R111 · Evaluator-Optimizer schema 蒸馏）测试。
/// 覆盖：四段完整无缺陷 → pass / 有缺陷+证据+修复 → fail 结构化 / 缺陷缺证据 → evidence_missing /
/// 缺陷缺修复 → fix_missing / 仅 Defects 段 → section_missing / 空文本 → 全缺段。纯函数无需库。

///|
fn ef_verdict(j : Json) -> String {
  match j.value("verdict") {
    Some(Json::String(s)) => s
    _ => abort("verdict 缺失: " + j.stringify())
  }
}

///|
fn ef_count(j : Json, key : String) -> Int {
  match j.value("counts") {
    Some(Json::Object(m)) =>
      match m.get(key) {
        Some(Json::Number(n, ..)) => n.to_int()
        _ => abort("counts." + key + " 缺失: " + j.stringify())
      }
    _ => abort("counts 缺失: " + j.stringify())
  }
}

///|
fn ef_schema_items(j : Json, key : String) -> Array[String] {
  match j.value("schema") {
    Some(Json::Object(m)) =>
      match m.get(key) {
        Some(Json::Array(arr)) =>
          arr.map(fn(v) {
            match v {
              Json::String(s) => s
              _ => ""
            }
          })
        _ => abort("schema." + key + " 缺失: " + j.stringify())
      }
    _ => abort("schema 缺失: " + j.stringify())
  }
}

///|
fn ef_flags(j : Json) -> Array[String] {
  match j.value("flags") {
    Some(Json::Array(arr)) =>
      arr.map(fn(v) {
        match v {
          Json::String(s) => s
          _ => ""
        }
      })
    _ => abort("flags 缺失: " + j.stringify())
  }
}

///|
fn ef_has_flag(j : Json, prefix : String) -> Bool {
  ef_flags(j).any(fn(f) { f.has_prefix(prefix) })
}

///|
fn ef_eval(e : @engine.FistEngine, fb : String) -> Json {
  e.eval_feedback(fb)
}

///|
fn new_eval_engine() -> @engine.FistEngine {
  @engine.FistEngine::new()
}

///|
test "eval_feedback：四段完整且无缺陷 → pass（optimizer 可收敛）" {
  let e = new_eval_engine()
  let j = ef_eval(
    e, "## Defects\n（无）\n## Evidence\n- 全部验收项实测通过\n## Fix\n- 无需修复\n## Acceptance\n- 301 项测试全绿\n- 守卫族全 PASS",
  )
  assert_eq(ef_verdict(j), "pass")
  assert_eq(ef_count(j, "defects"), 0)
  assert_eq(ef_count(j, "acceptance"), 2)
  assert_eq(ef_has_flag(j, "section_missing"), false)
}

///|
test "eval_feedback：有缺陷+证据+修复 → fail（定向回灌 E/O 闭环）" {
  let e = new_eval_engine()
  let j = ef_eval(
    e, "## Defects\n- 迁移契约检查缺 IN-6 身份字段校验\n- 文档计数未同步\n## Evidence\n- engine_contract_test 用例 2 复现\n- check_tools_sync FAIL\n## Fix\n- 补 IN-6 校验\n- 同步 README 计数\n## Acceptance\n- 新增测试通过\n- 守卫族全 PASS",
  )
  assert_eq(ef_verdict(j), "fail")
  assert_eq(ef_count(j, "defects"), 2)
  assert_eq(ef_count(j, "evidence"), 2)
  assert_eq(ef_count(j, "fix"), 2)
  assert_eq(ef_count(j, "acceptance"), 2)
  assert_eq(
    ef_schema_items(j, "defects")[0],
    "迁移契约检查缺 IN-6 身份字段校验",
  )
  assert_eq(ef_has_flag(j, "evidence_missing"), false)
  assert_eq(ef_has_flag(j, "fix_missing"), false)
  assert_eq(ef_has_flag(j, "section_missing"), false)
}

///|
test "eval_feedback：有缺陷但缺证据 → fail + evidence_missing" {
  let e = new_eval_engine()
  let j = ef_eval(
    e, "## Defects\n- 状态机迁移缺回稳证明\n## Fix\n- 补 state_stable 断言\n## Acceptance\n- 测试通过",
  )
  assert_eq(ef_verdict(j), "fail")
  assert_eq(ef_has_flag(j, "evidence_missing"), true)
  assert_eq(ef_has_flag(j, "fix_missing"), false)
}

///|
test "eval_feedback：有缺陷但缺修复 → fail + fix_missing" {
  let e = new_eval_engine()
  let j = ef_eval(
    e, "## Defects\n- 看板渲染缩进错误\n## Evidence\n- board_ascii_test 复现\n## Acceptance\n- 看板测试通过",
  )
  assert_eq(ef_verdict(j), "fail")
  assert_eq(ef_has_flag(j, "fix_missing"), true)
  assert_eq(ef_has_flag(j, "evidence_missing"), false)
}

///|
test "eval_feedback：仅 Defects 段 → fail + section_missing 三缺" {
  let e = new_eval_engine()
  let j = ef_eval(e, "## Defects\n- 交付物与文档不一致")
  assert_eq(ef_verdict(j), "fail")
  assert_eq(ef_count(j, "defects"), 1)
  assert_eq(ef_has_flag(j, "section_missing"), true)
  // 缺 Evidence/Fix/Acceptance
  let flags = ef_flags(j)
  let mut found = false
  for f in flags {
    if f.has_prefix("section_missing:") &&
      f.contains("Evidence") &&
      f.contains("Fix") &&
      f.contains("Acceptance") {
      found = true
    }
  }
  assert_eq(found, true)
}

///|
test "eval_feedback：空文本 → fail + 全段缺失" {
  let e = new_eval_engine()
  let j = ef_eval(e, "")
  assert_eq(ef_verdict(j), "fail")
  assert_eq(ef_count(j, "defects"), 0)
  assert_eq(ef_has_flag(j, "section_missing"), true)
}
