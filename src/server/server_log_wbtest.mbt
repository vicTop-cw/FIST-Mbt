///|
/// BUG-538 白盒锁 · 纯函数面（js/native 两目标都跑）：
/// 开关解析 / 目录前缀 / 路径解析 / 行构造 / 截断与净化。
/// IO 薄壳的行为格（正常写行 / off 零 IO / IO 失败静默）在
/// server_log_js_wbtest.mbt（js target 限定）+ 端到端冒烟。

///|
test "bug538_p1_开关解析_off大小写不敏感" {
  assert_false(server_log_env_off(None))
  assert_false(server_log_env_off(Some("")))
  assert_false(server_log_env_off(Some("/tmp/fist.log")))
  assert_true(server_log_env_off(Some("off")))
  assert_true(server_log_env_off(Some("OFF")))
  assert_true(server_log_env_off(Some(" Off ")))
}

///|
test "bug538_p2_目录前缀_认两种分隔符_裸文件名回空" {
  assert_eq(server_log_dir_of("data/x.db"), "data/")
  assert_eq(server_log_dir_of("data\\x.db"), "data\\")
  assert_eq(server_log_dir_of("/abs/x.db"), "/abs/")
  assert_eq(server_log_dir_of("x.db"), "")
}

///|
test "bug538_p3_路径解析_默认落db目录_显式覆盖_off归零" {
  // 默认：db 所在目录 + server.log
  assert_eq(server_log_resolve_path(None, "data/x.db"), "data/server.log")
  assert_eq(server_log_resolve_path(None, "a\\b\\c.db"), "a\\b\\server.log")
  // db 是裸文件名 ⇒ 退到 cwd 的 server.log（任务书：无 db path 退 cwd）
  assert_eq(server_log_resolve_path(None, "fist-mbt.db"), "server.log")
  // 显式路径原样
  assert_eq(
    server_log_resolve_path(Some("/var/log/fist.log"), "data/x.db"),
    "/var/log/fist.log",
  )
  // 空串视为未设置 ⇒ 默认路径
  assert_eq(server_log_resolve_path(Some(""), "data/x.db"), "data/server.log")
  // off ⇒ ""（关闭；所有写入对空路径都是 no-op）
  assert_eq(server_log_resolve_path(Some("OFF"), "data/x.db"), "")
  assert_eq(server_log_resolve_path(Some(" off "), "data/x.db"), "")
}

///|
test "bug538_p4_行构造_时间戳+前缀+事件+内容_换行结尾" {
  assert_eq(
    server_log_line("2026-11-02T07:40:00Z", "server.start", "version=test"),
    "2026-11-02T07:40:00Z [fist-mbt] server.start version=test\n",
  )
}

///|
test "bug538_p5_截断与净化_超长带标记_换行压平" {
  assert_eq(server_log_cap("abc", 5), "abc")
  assert_eq(server_log_cap("abcdef", 3), "abc...(capped)")
  assert_eq(server_log_cap("a\nb\rc", 10), "a b c")
  // 净化先于截断：换行不占截断预算、也不会混进截断面
  assert_eq(server_log_cap("a\nbcdef", 3), "a b...(capped)")
}

///|
test "bug538_p6_心跳_常量与行构造同一收口" {
  // 间隔常量：60 秒一行（低频；写死常量、不给配置面）
  assert_eq(SERVER_LOG_HEARTBEAT_MS, 60_000)
  // tick 上限：生产等效无限（60s × 20 亿 ≈ 3800 年，Int32 内）
  assert_eq(SERVER_LOG_HEARTBEAT_TICKS_MAX, 2_000_000_000)
  // 心跳行构造走 server_log_line（与其它事件同一收口），detail 带 pid
  assert_eq(
    server_log_line(
      "2026-11-02T08:00:00Z",
      "heartbeat",
      server_log_heartbeat_detail("4242"),
    ),
    "2026-11-02T08:00:00Z [fist-mbt] heartbeat alive pid=4242\n",
  )
}
