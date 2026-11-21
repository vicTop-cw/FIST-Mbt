///|
/// F094 §四 构建互斥（scope=build）白盒判据：
/// 进程内账本路径（fb_store_mutate 的 None 降级分支），ns 独立免污染。
/// 语义：同项目同时只允许一个 build 绑定；冲突返回现持有者；同持有者幂等续期；
/// release 只持有者本人；run_check 前后 acquire/release 由 server.mbt 挂钩。
test "F094 构建互斥：acquire → 冲突点名 → 幂等 → release → 他人复得" {
  let ns = "wbtest-bm"
  let pd = "proj-bm-mutex"
  // 首个持有者成功（acquire 返回 "" = 无冲突）
  assert_eq(fb_build_mutex_acquire(ns, pd, "agent-a", "task-a1", 1000), "")
  // 第二方冲突：冲突串点名现持有者（fail-closed，不静默）
  let conflict = fb_build_mutex_acquire(ns, pd, "agent-b", "task-b1", 1010)
  assert_true(conflict.contains("agent-a"))
  // 同持有者重复 acquire：幂等续期，不算冲突
  assert_eq(fb_build_mutex_acquire(ns, pd, "agent-a", "task-a1", 1020), "")
  // 持有者释放后他人可复得
  fb_build_mutex_release(ns, pd, "agent-a", 1030)
  assert_eq(fb_build_mutex_acquire(ns, pd, "agent-b", "task-b1", 1040), "")
  // 非持有者释放无效（release 只认持有者本人）：agent-a 放不掉 agent-b 的锁
  fb_build_mutex_release(ns, pd, "agent-a", 1050)
  assert_true(
    fb_build_mutex_acquire(ns, pd, "agent-a", "task-a2", 1060).contains(
      "agent-b",
    ),
  )
  // 收尾清理
  fb_build_mutex_release(ns, pd, "agent-b", 1070)
}

///|
/// 构建互斥跨项目隔离：项目 A 被占不阻塞项目 B（互斥粒度 = 同一项目）。
test "F094 构建互斥：跨项目互不阻塞" {
  let ns = "wbtest-bm"
  assert_eq(fb_build_mutex_acquire(ns, "proj-bm-x", "agent-a", "t", 2000), "")
  assert_eq(fb_build_mutex_acquire(ns, "proj-bm-y", "agent-b", "t", 2010), "")
  fb_build_mutex_release(ns, "proj-bm-x", "agent-a", 2020)
  fb_build_mutex_release(ns, "proj-bm-y", "agent-b", 2030)
}
