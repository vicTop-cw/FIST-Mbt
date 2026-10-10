///|
/// store_sqlite_executions_wbtest.mbt —— parse_simple_double 溢出哨兵回归（R12-R2）。
/// 为什么是 wbtest 不是 test：需要包内可见的 `parse_simple_double`（黑盒拿不到私有 fn）。
/// 场景：成本字段若被写入异常大字符串（如 "999999999999999999999"），
/// 旧实现在 `integer_part * 10 + d` 处 Int 溢出并**静默**产出乱数。
/// 新实现超过阈值（2e9）改用 Double 累积，保证大数解析仍单调递增（不绕回）。
test "sse_01_normal_double" {
  let v = parse_simple_double("3.14")
  assert_true((v - 3.14).abs() < 0.000000001)
}

test "sse_02_negative" {
  let v = parse_simple_double("-42.5")
  assert_true((v + 42.5).abs() < 0.000000001)
}

test "sse_03_leading_spaces" {
  let v = parse_simple_double("  123")
  assert_true((v - 123.0).abs() < 0.000000001)
}

/// 大数：超过 Int32 阈值（2e9）不应绕回。旧实现溢出为负值或乱数。
test "sse_04_large_integer_no_overflow" {
  let v = parse_simple_double("3000000000")
  // 3e9 超出 Int32（2.147e9），溢出后变负；新实现应回到 Double 累积
  assert_true(v > 0.0)
  assert_true((v - 3000000000.0).abs() < 1.0)
}

/// 超大数：连续很多位整数部分，仍不应溢出为 0 或负。
test "sse_05_very_large_integer" {
  let v = parse_simple_double("999999999999999999999999")
  // 溢出哨兵触发后 int_double 累积，结果应 > 1e20（虽非精确，但不应绕回）
  assert_true(v > 100000000000000000000.0)
}

/// 空串 / 纯符号 → 0（旧行为不回归）
test "sse_06_empty_and_sign_only" {
  let v1 = parse_simple_double("")
  let v2 = parse_simple_double("-")
  assert_true((v1 - 0.0).abs() < 0.000000001)
  assert_true((v2 - 0.0).abs() < 0.000000001)
}