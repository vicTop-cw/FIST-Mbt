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

///|
test "subcmd-3：doctor 判决——⏭️ 跳过不计失败，有 ❌ 才回非 0（BUG-391）" {
  // 全过 / 有跳过无失败 / 全跳过：都必须是 0（e2e_irm_line 要求 doctor=0 的那一格不能被跳过判红）
  assert_eq(doctor_failed_count(5, 5, 0), 0)
  assert_eq(doctor_failed_count(4, 5, 1), 0)
  assert_eq(doctor_failed_count(0, 5, 5), 0)
  // 反向对照：旧口径把跳过算进失败（total-ok），这里必须区分出来
  assert_eq(doctor_failed_count(4, 5, 0), 1)
  assert_eq(doctor_failed_count(3, 5, 1), 1)
}

///|
test "subcmd-4：doctor 体检库跟着 FIST_DB_PATH 改道，不再裸落 cwd（BUG-392）" {
  // 未设/空串改道针 = 现状面逐字不变（空串视为未设置，与 SqliteStore::db_path_from_env 同口径）
  assert_eq(doctor_db_path(None), DOCTOR_DB_NAME)
  assert_eq(doctor_db_path(Some("")), DOCTOR_DB_NAME)
  // 改道针生效：库落在被指向的那个目录里，而不是进程 cwd
  assert_eq(
    doctor_db_path(Some("C:/fist-runs/redirected.db")),
    "C:/fist-runs/_fist_doctor_check.db",
  )
  assert_eq(
    doctor_db_path(Some("/var/tmp/fist/fist-mbt.db")),
    "/var/tmp/fist/_fist_doctor_check.db",
  )
  assert_eq(
    doctor_db_path(Some("C:\\fist-runs\\redirected.db")),
    "C:\\fist-runs\\_fist_doctor_check.db",
  )
  // 反向对照：改道针本身是个纯相对名时，没有目录可跟着走，不许凭空造出 `/_…` 这种越界路径
  assert_eq(doctor_db_path(Some("redirected.db")), DOCTOR_DB_NAME)
}
