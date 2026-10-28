/// rx_rate_limit_wbtest.mbt —— A1 可落地性锁（RX-MBT 限速语义 vs 本模块 5h 滚动窗口）
///
/// 为什么有这个文件：计划 `docs/plans/2026-10-22-rx-mbt-lightweight-proposal.md` 的
/// A1 要求「用 `@rx.rate_limit(ms)` / `@rx.throttle(ms)` 驱动 5h 滚动窗口计数」。
/// 查完 RX-MBT 0.3.0 的 API 后判定 **A1 不可原样落地，降级为 A1'**（保留手搓计数、
/// 抽成单一真源接口）。本文件把这个判定钉成可执行证据，而不是只写在报告里：
///
///   rx_1  证明 `Clock` 是**虚拟时钟**（从 0 起、只能 advance），没有墙钟源；
///   rx_2  证明 `rate_limit/throttle` 是「每窗口最多 1 个、窗口内**丢弃**」，
///         既表达不了每模型 N 次配额，也没有剩余配额读回口；
///   rx_3  锁 A1' 抽出的窗口门（起点只写一次 / `>=` 边界到期 / 记账只 +1）；
///   rx_4  锁准入判定四条硬约束（阈值严格小于 / 耗尽 / 冷却 / 黑名单）；
///   rx_5  **变异对照格**：把窗口记账 choke point 改坏必须红（改坏点落在代码，不是注释）。
///
/// 结论：本模块的窗口记账仍是确定性手搓计数（`model_router.mbt` 的 `quota_window_*` /
/// `quota_admitted` 一组），但已收敛为单一真源；`now` 是唯一时钟注入点。

///|
/// rx_1：RX-MBT `Clock` 是虚拟时钟——从 0 起、只能 `advance` 推进，没有墙钟源。
///
/// 证据（真源 `.mooncakes/vicTop-cw/RX-MBT/rx/ops_time.mbt:20-41`）：
/// `Clock::new()` 的 ms 从 0 开始，`now()` 只是读这个计数，`advance()` 才推进。
/// ⇒ 生产环境没人调 `advance_time` 时它永远停在 0，5h 窗口会永不到期（用量只增不减，
/// 最后全池假性耗尽）。本模块的时间戳由服务端盖章（BUG-33 政策），换不上这个虚拟时钟。
test "rx_1_Clock 是虚拟时钟：从 0 起、只能 advance、无墙钟源" {
  let c = @rx.Clock::new()
  assert_eq(c.now(), 0L)
  // 不推进就一直停在 0——没有"读当前墙钟"的入口
  assert_eq(c.now(), 0L)
  c.advance(18_000_000L) // 5h = 18_000_000ms
  assert_eq(c.now(), 18_000_000L)
  // 再建一个 Clock 仍是 0：每个时钟各自从 0 起，不存在全局墙钟基准
  assert_eq(@rx.Clock::new().now(), 0L)
}

///|
/// rx_2：`rate_limit_on` / `throttle_on` 的语义是「每窗口最多放行 1 个值，窗口内多余的
/// 值**静默丢弃**」——不是「每窗口 N 个配额」，也不是「排队/计数」。
///
/// 证据（真源 `.mooncakes/vicTop-cw/RX-MBT/rx/ops_time.mbt:288-352`）：
/// `if now >= last_fired { emit; last_fired = now + ms }`，else 什么都不做。
/// 本模块要的是「每模型 5h 内 limit=100/50 次 + 可读回 used/remaining/usage_pct」：
///   * 配额 N>1 表达不了（同一窗口第 2..N 个值会被丢掉）；
///   * 没有剩余配额/已用计数的读回 API（流里没有值时就什么都看不见）。
/// ⇒ 若强行拿它当配额计数器，真实调用会被**少记**，`used/usage_report` 直接失真。
test "rx_2_rate_limit 是每窗口 1 个且丢弃，表达不了每模型 N 次配额" {
  let clock = @rx.Clock::new()
  let src : @rx.PublishSubject[Int32, Unit] = @rx.PublishSubject::new()
  let got : Array[Int32] = []
  let sub = src
    .as_observable()
    .rate_limit_on(clock, 60_000L)
    .subscribe(@rx.Observer::on_next_only(fn(v : Int32) { got.push(v) }))
  // 同一窗口内连发 5 次，相当于「配额 5 次的模型被打满」的调用序列
  for i in 0..<5 {
    src.on_next(i)
  }
  // 只放行 1 个，其余 4 个被丢弃 —— 配额 N>1 在这里直接丢失读数
  assert_eq(got.length(), 1)
  assert_eq(got[0], 0)
  // 窗口推进后才再放行下一个
  clock.advance(60_000L)
  src.on_next(9)
  assert_eq(got.length(), 2)
  assert_eq(got[1], 9)
  sub.dispose()
}

///|
/// rx_3：A1' 抽出的窗口门——起点只写一次、恰满窗口（`>=` 边界）重置、记账只 +1。
/// 这是原 `window_reset_check` / `record_call` / `pick_with_*` 五处重复逻辑的共同真源。
test "rx_3_窗口门：起点只写一次、>= 边界重置、每次记账只 +1" {
  let m = ModelQuota::new(name="m", tier=Free, limit=2)
  // 起点空 ⇒ open 写入 now，且不碰 used
  quota_window_open(m, "2026-01-01T00:00:00Z")
  assert_eq(m.window_start, "2026-01-01T00:00:00Z")
  assert_eq(m.used, 0)
  // 同一窗口内 open 不得把起点往后推（否则窗口永不到期）
  quota_window_open(m, "2026-01-01T01:00:00Z")
  assert_eq(m.window_start, "2026-01-01T00:00:00Z")
  // 记账：每次 +1
  quota_window_consume(m, "2026-01-01T01:00:00Z", 18000)
  quota_window_consume(m, "2026-01-01T02:00:00Z", 18000)
  assert_eq(m.used, 2)
  // 差 1 秒未满 5h ⇒ 不重置，只 +1
  quota_window_consume(m, "2026-01-01T04:59:59Z", 18000)
  assert_eq(m.used, 3)
  assert_eq(m.window_start, "2026-01-01T00:00:00Z")
  // 恰满 5h（>= 边界）⇒ 老用量清零后本次 +1，起点推到 now
  quota_window_consume(m, "2026-01-01T05:00:00Z", 18000)
  assert_eq(m.used, 1)
  assert_eq(m.window_start, "2026-01-01T05:00:00Z")
  // 非法时间戳不得清零用量（坏时间戳当作"不到期"，不是"全清"）
  quota_window_consume(m, "garbage", 18000)
  assert_eq(m.used, 2)
  assert_eq(m.window_start, "2026-01-01T05:00:00Z")
}

///|
/// rx_4：准入判定四条硬约束（`quota_admitted` 是 `pool_pick` 的唯一真源）。
/// 阈值是**严格小于**：95.0 已达阈值 ⇒ 不放行。
test "rx_4_准入判定：阈值 95 边界、耗尽、冷却、黑名单逐条生效" {
  let now = "2026-01-01T00:00:00Z"
  // 94% < 95% 放行；95% 不放行
  assert_true(
    quota_admitted(
      ModelQuota::new(name="a", tier=Free, limit=100, used=94),
      95.0,
      now,
      [],
    ),
  )
  assert_false(
    quota_admitted(
      ModelQuota::new(name="b", tier=Free, limit=100, used=95),
      95.0,
      now,
      [],
    ),
  )
  // 耗尽（limit=1 已用 1）
  assert_false(
    quota_admitted(
      ModelQuota::new(name="c", tier=Free, limit=1, used=1),
      95.0,
      now,
      [],
    ),
  )
  // 冷却中
  assert_false(
    quota_admitted(
      ModelQuota::new(
        name="d",
        tier=Free,
        limit=100,
        cooldown_until="2026-01-01T01:00:00Z",
      ),
      95.0,
      now,
      [],
    ),
  )
  // 黑名单
  assert_false(
    quota_admitted(ModelQuota::new(name="e", tier=Free, limit=100), 95.0, now, [
      "e",
    ]),
  )
  // 无限配额（limit<=0）永不耗尽，也不受阈值影响
  assert_true(
    quota_admitted(
      ModelQuota::new(name="f", tier=Free, limit=0, used=10_000),
      95.0,
      now,
      [],
    ),
  )
}

///|
/// rx_5（**变异对照格**）：窗口记账 choke point 每次只 +1，且到期重置后从 0 起算。
///
/// 变异实验（已实测，改坏点落在**代码**不是注释，判例-30 的自指假绿不适用——
/// 本格断言的是函数**行为读数**，不 grep 源码字符串）：
///   * 把 `model_router.mbt` 的 `quota_window_consume` 里 `m.used = m.used + 1`
///     改成 `m.used = m.used + 2` ⇒ 本格第一处断言 2≠1 直接红；
///   * 把 `quota_window_reset_if_expired` 的重置分支删掉 ⇒ 到期后断言 5≠1 红；
///   * 还原后本格恢复绿。
test "rx_5_变异对照：窗口记账只 +1，到期重置后从 0 起算" {
  let m = ModelQuota::new(name="mut", tier=Free, limit=10)
  quota_window_consume(m, "2026-01-01T00:00:00Z", 18000)
  // ← 变异点 A：改成 +2 时这里立刻 2 ≠ 1
  assert_eq(m.used, 1)
  // 窗口内再记 3 次 ⇒ 精确 4，不多不少
  quota_window_consume(m, "2026-01-01T00:00:01Z", 18000)
  quota_window_consume(m, "2026-01-01T00:00:02Z", 18000)
  quota_window_consume(m, "2026-01-01T00:00:03Z", 18000)
  assert_eq(m.used, 4)
  // ← 变异点 B：删掉到期重置时这里会是 5 ≠ 1
  quota_window_consume(m, "2026-01-01T05:00:00Z", 18000)
  assert_eq(m.used, 1)
}
