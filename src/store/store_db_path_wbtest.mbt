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

///|
/// 首尾空白 trim（r197/r241 实证的上游成因面：FIST_DB_PATH 带尾随空格 ⇒
/// 去打开 `fist-mbt.db `（带空格）⇒ Windows 落 0 字节 stray 文件）。
/// 缺这一格时「尾随空格」再次静默逃逸——本仓 stray 复发的唯一根因锁。
test "db_path_from_env: 首尾空白 trim 后采用" {
  // 尾随空格（实测复发的精确形态）
  assert_eq(SqliteStore::db_path_from_env(Some("fist-mbt.db ")), "fist-mbt.db")
  // 前导 + 尾随
  assert_eq(SqliteStore::db_path_from_env(Some(" fist-mbt.db ")), "fist-mbt.db")
  // 任意路径同理
  assert_eq(
    SqliteStore::db_path_from_env(Some(" temp/ns-probe/run.db ")),
    "temp/ns-probe/run.db",
  )
}

///|
/// trim 后为空串 ⇒ 与空串同语义回默认（「   」不是路径）。
test "db_path_from_env: 纯空白视为未设置" {
  assert_eq(SqliteStore::db_path_from_env(Some("   ")), "fist-mbt.db")
  assert_eq(SqliteStore::db_path_from_env(Some(" \t ")), "fist-mbt.db")
}

///|
/// 防过度修复对照：trim 只动首尾，**路径中间的空白**是合法名的一部分，不得动。
/// 缺这一格时任何「把空白全删掉」的过修都会静默通过前面三格。
test "db_path_from_env: 路径中间空白不受影响" {
  assert_eq(
    SqliteStore::db_path_from_env(Some("temp/ns db/x.db")),
    "temp/ns db/x.db",
  )
}
