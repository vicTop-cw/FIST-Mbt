///|
/// ops_selfdrive_overflow_wbtest.mbt —— sd_parse_int 溢出哨兵回归（R12-R2，BUG-215）。
/// 为什么是 wbtest：需要包内可见的 `sd_parse_int`（黑盒拿不到私有 fn）。
/// 病灶：MoonBit Int 为 32 位，异常长数字串会在 `v * 10 + d` 处溢出并静默绕回。
/// 新实现：`v >= 200_000_000` 时返回 None（调用方视为解析失败）。
test "sdp_01_normal" {
  match sd_parse_int("123") {
    Some(v) => assert_true(v == 123)
    None => fail("合法数字应解析成功")
  }
}

///|
test "sdp_02_leading_trim" {
  match sd_parse_int("  45  ") {
    Some(v) => assert_true(v == 45)
    None => fail("前后空白应被 trim")
  }
}

///|
test "sdp_03_empty_or_nonnum_returns_none" {
  assert_true(sd_parse_int("").is_none())
  assert_true(sd_parse_int("abc").is_none())
  assert_true(sd_parse_int("12a").is_none())
}

///|
test "sdp_04_large_no_overflow" {
  // 24 位数字串：旧实现溢出为乱数；新实现返回 None（不产出乱数）
  assert_true(sd_parse_int("999999999999999999999999").is_none())
}

///|
test "sdp_05_just_below_threshold_ok" {
  match sd_parse_int("199999999") {
    Some(v) => assert_true(v == 199999999)
    None => fail("199999999 仍在阈值内应解析成功")
  }
}

///|
test "sdp_06_over_threshold_none" {
  // 2000000001 第 10 位：v=200000000 >= int_safe（2e8），下次乘 10 会越界 → None
  assert_true(sd_parse_int("2000000001").is_none())
}
