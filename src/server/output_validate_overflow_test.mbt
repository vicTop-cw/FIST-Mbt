///|
/// output_validate_overflow_test.mbt —— R12-R8 bugfind：验证 ov_parse_int 的 int_safe
/// 上界守卫（BUG-221：旧实现缺守卫，长数字串溢出 Int32）。
/// 该函数是文件私有，故测试放在同包（server）内。
test "ov_parse_int 拒绝长数字串" {
  // 11 位 9（≈1e11）会超 int_safe（200_000_000）触发守卫
  assert_true(ov_parse_int("99999999999") is None)
  // 3 位正常数字应能解析
  assert_true(ov_parse_int("123") is Some(_))
  assert_eq(ov_parse_int("123"), Some(123))
}
