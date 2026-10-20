/// bug335_ns_route_wbtest.mbt —— BUG-335 回归锁：publish_parallel 在隔离 ns 下的引擎路由。
///
/// 缺陷：c9ea8b3 把 23 个业务工具接进 engine_for_ns 后，publish_parallel（显式 ns）被裂到
/// {cwd}/{ns}.db（mstore 库级隔离），而 e2e_heartbeat_xproc 的 no-ns 调用（claim/execute/heartbeat）
/// 与 heal/watchdog（本就走 default 引擎 + ns 过滤）都在 default 引擎（FIST_DB_PATH）⇒ 显式 ns 的
/// 任务行落进 mstore 库、default 引擎查不到 ⇒ 跨进程看护 8 格红。
///
/// 本锁钉住路由**决策**（publish_parallel_route，纯函数，环境无关）：
///   隔离模式（FIST_DB_PATH 已设）→ 显式 ns 必须收进 default；
///   未隔离 → 显式 ns 走独立库（M5 库级物理隔离，store_isolation_probe C3 依赖，零回归）。
/// 端到端（任务真的可从该 ns 在 default 引擎查得到）由 CI 门禁 e2e_heartbeat_xproc.py 承担。

///|
/// 隔离模式：显式 ns 收进 default（e2e_heartbeat_xproc 承重——no-ns 调用在 default 引擎查得到）
test "BUG-335 隔离 ns：publish_parallel 显式 ns 收进 default" {
  assert_eq(publish_parallel_route("hb-xproc", true), "default")
}

///|
/// 未隔离：显式 ns 走独立库（M5 库级物理隔离，store_isolation_probe C3 依赖，零回归）
test "BUG-335 非隔离 ns：publish_parallel 显式 ns 走独立库" {
  assert_eq(publish_parallel_route("hb-xproc", false), "ns:hb-xproc")
}

///|
/// default / 空 ns 恒收 default（隔离与否都不变）
test "BUG-335 default/空 ns 恒收 default" {
  assert_eq(publish_parallel_route("default", true), "default")
  assert_eq(publish_parallel_route("default", false), "default")
  assert_eq(publish_parallel_route("", true), "default")
  assert_eq(publish_parallel_route("", false), "default")
}
