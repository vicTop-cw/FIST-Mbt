///|
/// bugreport_overflow_wbtest.mbt —— bug_parse_int 溢出哨兵回归（R12-R2，BUG-215）。
/// 为什么是 wbtest：需要包内可见的 `bug_parse_int`（黑盒拿不到私有 fn）。
/// 病灶：MoonBit Int 为 32 位，异常长数字串会在 `acc * 10 + d` 处溢出并静默绕回。
/// 新实现：`acc >= 200_000_000` 时 break（不产出乱数）。
test "bp_01_normal" {
  assert_true(bug_parse_int("7") == 7)
  assert_true(bug_parse_int("215") == 215)
}

///|
test "bp_02_leading_junk_break" {
  // 遇到非数字立即 break，返回已累积部分
  assert_true(bug_parse_int("12abc") == 12)
}

///|
test "bp_03_empty_or_nonnum" {
  assert_true(bug_parse_int("") == 0)
  assert_true(bug_parse_int("abc") == 0)
}

///|
test "bp_04_large_no_overflow" {
  // 24 位数字串：旧实现溢出为乱数（可能负/0）；新实现 break 在阈值处，
  // 返回值应 > 0 且与已累积的 2e8 附近一致（不绕回成负）
  let v = bug_parse_int("999999999999999999999999")
  assert_true(v > 0)
  assert_true(v >= 200_000_000)
}

///|
test "bp_05_just_below_threshold" {
  // 阈值前一位仍在累加（199999999 < 2e8）
  assert_true(bug_parse_int("199999999") == 199999999)
}
