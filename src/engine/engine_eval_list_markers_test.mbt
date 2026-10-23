/// engine_eval_list_markers_test.mbt —— R135：反馈列表项解析不能只认 `- `。
///
/// 病灶：`parse_section` 只收 `- ` 开头的行，Markdown 另外两种无序列表（`* ` / `+ `）
/// 与有序列表（`1. ` / `1) `）写在 `## Defects` 下会被**静默忽略**——`d == 0`
/// 于是 verdict 直接判 pass，缺陷被契约层吞掉（与 BUG-31 未知键静默忽略同族）。
/// 对照组：`## Defects\n（无）` 这种非列表的自由文本仍应是「无缺陷」，不许误红。
///
/// R135 同族收口：既不是列表项、也不是「无」标记的散文行（如「缺陷：A 和 B」）
/// 同样读不到缺陷数——现在计 defects_unparsed 并 fail-closed，不再静默 pass。

///|
fn efx_verdict(j : Json) -> String {
  match j.value("verdict") {
    Some(Json::String(s)) => s
    _ => abort("verdict 缺失: " + j.stringify())
  }
}

///|
fn efx_count(j : Json, key : String) -> Int32 {
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
fn efx_eval(fb : String) -> Json {
  @engine.FistEngine::new().eval_feedback(fb)
}

///|
test "efx_1 星号列表缺陷必须计入并 fail" {
  let j = efx_eval(
    "## Defects\n* 状态机迁移缺回稳证明\n## Evidence\n* 复现脚本已跑\n## Fix\n* 补 state_stable 断言\n## Acceptance\n* 新增测试通过",
  )
  assert_eq(efx_count(j, "defects"), 1)
  assert_eq(efx_verdict(j), "fail")
}

///|
test "efx_2 加号与有序列表缺陷必须计入并 fail" {
  let j = efx_eval(
    "## Defects\n+ 文档计数未同步\n1. 迁移契约缺 IN-6 字段校验\n2) 守卫族漏一格\n## Evidence\n- 复现\n## Fix\n- 补校验\n## Acceptance\n- 全绿",
  )
  assert_eq(efx_count(j, "defects"), 3)
  assert_eq(efx_verdict(j), "fail")
}

///|
test "efx_3 自由文本（无）仍是零缺陷 pass（不误红）" {
  let j = efx_eval(
    "## Defects\n（无）\n## Evidence\n- 实测通过\n## Fix\n- 无需修复\n## Acceptance\n- 测试全绿",
  )
  assert_eq(efx_count(j, "defects"), 0)
  assert_eq(efx_verdict(j), "pass")
}

///|
test "efx_4 有序验收项计入 acceptance" {
  let j = efx_eval(
    "## Defects\n（无）\n## Evidence\n- 实测通过\n## Fix\n- 无需修复\n## Acceptance\n1. 全仓测试通过\n2. 电池 0 失败",
  )
  assert_eq(efx_count(j, "acceptance"), 2)
  assert_eq(efx_verdict(j), "pass")
}

///|
fn efx_flags(j : Json) -> Array[String] {
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
test "efx_5 散文缺陷不许静默读成零缺陷：defects_unparsed + fail" {
  let j = efx_eval(
    "## Defects\n缺陷：迁移契约缺 IN-6 校验，文档计数也没同步\n## Evidence\n- 复现脚本已跑\n## Fix\n- 补校验\n## Acceptance\n- 测试全绿",
  )
  assert_eq(efx_count(j, "defects"), 0)
  assert_eq(efx_count(j, "defects_unparsed"), 1)
  assert_eq(efx_verdict(j), "fail")
  assert_eq(efx_flags(j).any(fn(f) { f.has_prefix("defects_unparsed:") }), true)
}

///|
test "efx_6 显式「无」标记（none / 暂无 / （无））仍是零缺陷 pass" {
  for marker in ["none", "NONE", "暂无", "(无)", "（无）", "n/a"] {
    let j = efx_eval(
      "## Defects\n" +
      marker +
      "\n## Evidence\n- 实测通过\n## Fix\n- 无需修复\n## Acceptance\n- 测试全绿",
    )
    assert_eq(efx_count(j, "defects_unparsed"), 0)
    assert_eq(efx_verdict(j), "pass")
  }
}

///|
test "efx_7 散文与列表混写：列表照计、散文照报、仍 fail" {
  let j = efx_eval(
    "## Defects\n* 列表里的缺陷\n这条是散文补注\n## Evidence\n- 复现\n## Fix\n- 补\n## Acceptance\n- 全绿",
  )
  assert_eq(efx_count(j, "defects"), 1)
  assert_eq(efx_count(j, "defects_unparsed"), 1)
  assert_eq(efx_verdict(j), "fail")
}
