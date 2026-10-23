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
  // 2092 起最坏 case (25203*86400 ≈ 2.18e9) 已越过 Int32
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

///|
/// R13-R1 bugfind（BUG-175）：sec 分支守卫原为 `length >= 17`，
/// 但 parse_digits(chars, 17, len=2) 访问 chars[17] 与 chars[18]——
/// 17 字符时 chars[17] 越界、18 字符时 chars[18] 越界 → 数组下标 panic。
/// 收紧到 >= 19 后，length<19 一律按 sec=0 处理，不 panic。
test "iso_to_secs: 17 字符（截在秒段前）不 panic，sec 按 0" {
  // "2024-01-01T00:00:" = 17 字符；旧守卫 17>=17 通过 → chars[17] 越界 panic。
  // 修复后 sec=0，结果为 day=1 * 86400 + 0 = 86400
  let s = iso_to_secs("2024-01-01T00:00:")
  assert_eq(s, 86400)
}

///|
test "iso_to_secs: 18 字符（秒段缺一位）不 panic，sec 按 0" {
  // "2024-01-01T00:00:0" = 18 字符；旧守卫 18>=17 通过 → chars[18] 越界 panic。
  let s = iso_to_secs("2024-01-01T00:00:0")
  assert_eq(s, 86400)
}

///|
test "iso_to_secs: 19 字符完整时间戳秒段正常解析" {
  // "2024-01-01T00:00:01" = 19 字符（索引 0..18）；守卫 >= 19 通过，sec=1。
  let s = iso_to_secs("2024-01-01T00:00:01")
  assert_eq(s, 86401)
}

///|
/// R128：字段范围校验。`parse_digits` 只按两位数字累加、不校验范围——
/// `year=2091, day=99` 时 days = 67*365 + 334 + 99 = 24888，
/// `days * 86400 = 2,150,323,200 > 2^31-1`，旧实现 Int32 绕回。
test "iso_to_secs: day=99 返回 -1（R128 Int32 溢出）" {
  assert_eq(iso_to_secs("2091-12-99T23:59:59"), -1)
}

///|
/// R128：月/日/时/分/秒越界一律按解析失败返回 -1（此前 mon 越界被静默按 0 处理）。
test "iso_to_secs: 月日时分秒越界返回 -1" {
  assert_eq(iso_to_secs("2091-13-31T23:59:59"), -1)
  assert_eq(iso_to_secs("2091-00-31T23:59:59"), -1)
  assert_eq(iso_to_secs("2091-12-00T23:59:59"), -1)
  assert_eq(iso_to_secs("2091-12-31T24:00:00"), -1)
  assert_eq(iso_to_secs("2091-12-31T23:60:00"), -1)
  assert_eq(iso_to_secs("2091-12-31T23:59:60"), -1)
}

///|
/// R129：分隔符错位必须判失败（字段数字全合法，旧实现会静默算出值）。
test "iso_to_secs: 分隔符错位返回 -1" {
  assert_eq(iso_to_secs("2024:01-01T00:00:00"), -1)
  assert_eq(iso_to_secs("2024-01:01T00:00:00"), -1)
  assert_eq(iso_to_secs("2024-01-01X00:00:00"), -1)
  assert_eq(iso_to_secs("2024-01-01T00;00:00"), -1)
  assert_eq(iso_to_secs("2024-01-01T00:00;00"), -1)
}

///|
/// R129：文档声明的空格分隔仍须接受（T/t 同义）。
test "iso_to_secs: 空格与小写 t 分隔符可用" {
  assert_eq(iso_to_secs("2024-01-01 00:00:01"), 86401)
  assert_eq(iso_to_secs("2024-01-01t00:00:01"), 86401)
}

///|
/// R128：parse_digits 遇非数字字符返回 -1（'a' 的 char_int 是 49，落在秒段合法区间内，
/// 只靠范围检查挡不住，必须逐字符验数字）。
test "iso_to_secs: 非数字字段返回 -1" {
  assert_eq(iso_to_secs("20x1-12-31T23:59:59"), -1)
  assert_eq(iso_to_secs("2024-01-01T00:00:0a"), -1)
}

///|
/// R129：跨解析器顺序锁暴露的病灶——非闰月表让 2024-02-29 与 2024-03-01 同值，
/// 且不存在的日历日被静默接受。改为真闰年口径 + 当月天数校验。
test "iso_to_secs: 闰日与 3 月 1 日可区分，不存在日期返回 -1" {
  assert_eq(iso_to_secs("2024-02-29T00:00:00"), 5_184_000)
  assert_eq(iso_to_secs("2024-03-01T00:00:00"), 5_270_400)
  assert_eq(iso_to_secs("2025-02-29T00:00:00"), -1)
  assert_eq(iso_to_secs("2024-02-30T00:00:00"), -1)
  assert_eq(iso_to_secs("2024-04-31T00:00:00"), -1)
}

///|
/// R128：Int64 计算 + 窄化的上界边界读数（含闰日累计后仍在 Int32 内）。
test "iso_to_secs: 2091-12-31T23:59:59 边界值仍可解析" {
  assert_eq(iso_to_secs("2091-12-31T23:59:59"), 2_146_003_199)
}
