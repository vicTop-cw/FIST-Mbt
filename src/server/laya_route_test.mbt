/// laya_route_test.mbt —— 决策分支模块（laya_route）规则式回退测试
///
/// 覆盖：纯计算 `route_decision`——feature_route 关键词打分选族 / 复杂度→split_n / 确定性。
/// 该模块是「无 Laya 时的自包含决策分支」，纯计算无外部依赖，固定输入必有固定输出。

///|
/// 读 JSON 字符串字段（沿用 memory_test 的读取约定）。
fn lr_str(j : Json, key : String) -> String {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(String(s)) => s
        _ => "<null>"
      }
    _ => "<null>"
  }
}

///|
/// 读 JSON 数字为 int。
fn lr_int(j : Json, key : String) -> Int {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(Number(n, ..)) => n.to_int()
        _ => -1
      }
    _ => -1
  }
}

///|
/// 读 JSON 布尔。
fn lr_bool(j : Json, key : String) -> Bool {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(True) => true
        _ => false
      }
    _ => false
  }
}

///|
test "route_1_scan_description_picks_scan_family" {
  // 含"扫描/缺陷/审计"等词的任务 → 应路由到「代码质量扫描」，source=fallback
  let j = route_decision(
    "对 src 目录做缺陷扫描与静态审计，找潜在问题", 0,
  )
  assert_eq(lr_str(j, "source"), "fallback")
  assert_eq(lr_str(j, "feature_route"), "代码质量扫描")
  // 无复杂度信号 → 不判定 complex，split_n 用基线 3
  assert_eq(lr_bool(j, "complex"), false)
  assert_eq(lr_int(j, "split_n"), 3)
}

///|
test "route_2_short_simple_gives_baseline_split" {
  // 短且无明显复杂度信号 → 不判定 complex，split_n 回退基线 3
  let j = route_decision("简单任务", 0)
  assert_eq(lr_bool(j, "complex"), false)
  assert_eq(lr_int(j, "split_n"), 3)
}

///|
test "route_3_split_hint_respected" {
  // split_n_hint=5 且不复杂 → split_n=5
  let j = route_decision("简单任务", 5)
  assert_eq(lr_int(j, "split_n"), 5)
}

///|
test "route_4_complexity_word_increases_split" {
  // 含"重构/多任务"信号且 hint=3 → split_n=4（+1，钳在 2..6）
  let j = route_decision("对本项目做多任务重构", 3)
  assert_eq(lr_bool(j, "complex"), true)
  assert_eq(lr_int(j, "split_n"), 4)
}

///|
test "route_5_deterministic_same_input_same_output" {
  // 确定性：同输入两次 → 相同 feature_route 与 split_n
  let desc = "重排关键路径上的并行派单与依赖拓扑，找出瓶颈"
  let j1 = route_decision(desc, 3)
  let j2 = route_decision(desc, 3)
  assert_eq(lr_str(j1, "feature_route"), lr_str(j2, "feature_route"))
  assert_eq(lr_int(j1, "split_n"), lr_int(j2, "split_n"))
}
