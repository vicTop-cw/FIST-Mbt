///|
/// BUG-106 的白盒锁：子命令词法与退出码只在 `subcmd.mbt` 一处定义，
/// 这里成对钉「别名归位」与「未知必非 0、已知必 0」两半。
test "subcmd-1：长/短别名归位，不再落未知臂（BUG-106）" {
  assert_eq(parse_subcmd("--version"), Version)
  assert_eq(parse_subcmd("-V"), Version)
  assert_eq(parse_subcmd("version"), Version)
  assert_eq(parse_subcmd("--help"), Help)
  assert_eq(parse_subcmd("-h"), Help)
  assert_eq(parse_subcmd("help"), Help)
  assert_eq(parse_subcmd("serve"), Serve)
  assert_eq(parse_subcmd("demo"), Demo)
  assert_eq(parse_subcmd("doctor"), Doctor)
  assert_eq(parse_subcmd(""), NoArgs)
}

///|
test "subcmd-2：未知子命令回非 0，已知臂回 0（BUG-106 第二半，成对反向对照）" {
  assert_eq(exit_code_of(parse_subcmd("--nope")), USAGE_ERROR_EXIT_CODE)
  assert_eq(exit_code_of(parse_subcmd("versoin")), USAGE_ERROR_EXIT_CODE)
  assert_eq(USAGE_ERROR_EXIT_CODE, 2)
  for
    s in [
      "serve", "version", "--version", "-V", "demo", "doctor", "help", "--help",
      "-h", "",
    ] {
    assert_eq(exit_code_of(parse_subcmd(s)), 0)
  }
}
