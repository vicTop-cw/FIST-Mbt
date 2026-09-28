///|
/// store_db_path_wbtest.mbt —— BUG-90 白盒锁：库路径由 FIST_DB_PATH 决定，
/// 未设置/空串必须逐字回落到 "fist-mbt.db"（零回归档）。
/// 为什么判纯函数而不是直接读环境：判据要能在任何环境下跑出同一结论；
/// 环境注入留给调用面实测（scripts/store_isolation_probe.py 起 serve 时带 env）。
test "db_path_from_env: 环境缺席回默认库（零回归）" {
  assert_eq(SqliteStore::db_path_from_env(None), "fist-mbt.db")
}

///|
test "db_path_from_env: 显式路径原样采用（隔离的唯一出口）" {
  assert_eq(
    SqliteStore::db_path_from_env(Some("temp/ns-probe/run.db")),
    "temp/ns-probe/run.db",
  )
}

///|
test "db_path_from_env: 空串视为未设置，不当成路径" {
  // 缺这条时 FIST_DB_PATH="" 会去打开空路径 ⇒ open 失败 ⇒ 静默回退内存版，
  // "隔离成功"的假象比崩溃更坏
  assert_eq(SqliteStore::db_path_from_env(Some("")), "fist-mbt.db")
  assert_eq(SqliteStore::db_path_from_env(Some("a.db")), "a.db")
}
