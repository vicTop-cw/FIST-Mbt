///|
/// ops_ts_wbtest.mbt —— iso_to_secs 上下界回归（R12-R5，BUG-217）。
/// 病灶：`if year < 2024` 有下界但无上界，year=9999 时 days*86400 溢出 Int32。
/// 修复：对称加 `if year > 2091` 上界。
/// wbtest 原因：`iso_to_secs` 是 pub，但 `parse_digits`/`char_int` 是私有，
/// 不过本测试只测 pub 接口即可，故用 `_wbtest.mbt` 保持与 ops_ts.mbt 同包。
test "iso_to_secs: 正常时间戳" {
  // 2024-01-02T00:00:00 → day=2, *86400 = 172800
  let s = iso_to_secs("2024-01-02T00:00:00")
  assert_eq(s, 172800)
}

///|
test "iso_to_secs: 2024 首日 = 86400" {
  // day=1（月份天数数组从 0 开始，Jan=0），*86400 = 86400
  let s = iso_to_secs("2024-01-01T00:00:00")
  assert_eq(s, 86400)
}

///|
test "iso_to_secs: 下界外返回 -1" {
  let s = iso_to_secs("2023-12-31T23:59:59")
  assert_eq(s, -1)
}

///|
test "iso_to_secs: 上界 2092 返回 -1（BUG-217 溢出）" {
  // 2092 起最坏 case (25185*86400 ≈ 2.18e9) 已越过 Int32
  let s = iso_to_secs("2092-12-31T23:59:59")
  assert_eq(s, -1)
}

///|
test "iso_to_secs: 上界边界 2091 不 panic" {
  // 2091 是最坏 case 仍 < 2^31-1 的最后一年
  let s = iso_to_secs("2091-01-01T00:00:00")
  assert_true(s >= 0)
}

///|
test "iso_to_secs: 极端 9999 返回 -1（BUG-217 原病灶）" {
  let s = iso_to_secs("9999-12-31T23:59:59")
  assert_eq(s, -1)
}

///|
test "iso_to_secs: 短字符串返回 -1" {
  let s = iso_to_secs("2024")
  assert_eq(s, -1)
}
