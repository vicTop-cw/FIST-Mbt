/// src/router/model_router_bug586_wbtest.mbt —— BUG-586 回归锁（window_seconds 同族加法绕回 ⇒ 展示字段坏值）
///
/// ## 缺陷形态（修前真源 `model_router.mbt:904 / :950 / :1190-1192`）
///
/// 三处 `next_switch_at` 都用同一条算式 `secs_to_iso(iso_to_secs(now) + window_seconds)`：
/// `window_seconds` 来自配置，`router_config.mbt` 的 `num_to_int_safe` 只钳 ±2e9、只拒非正，
/// 于是 2026 年（`now_secs≈1.79e9`）配上 `window_seconds=2_000_000_000` 时
/// **`now_secs + 2000000000` 越过 2^31-1 绕回负值** ⇒ `secs_to_iso` 产出
/// **""**（负秒分支）⇒ 展示字段空。另一半更隐蔽：绕回**没越过 0** 的那档（和落在
/// `2145916800..2147483647`，即 2038 年起）会写出一个 `iso_to_secs` 读不回来的**不可表示日期**
/// （"2038-01-01T00:00:00Z"），下游把它当非法时间戳——比空串更难查。
/// 影响面：仅 JSON 展示字段（准入逻辑走 `window_expired` 的**减法**，不经这条加法）。
///
/// ## 修复后的行为面（本文件锁住）
///
/// - 三处算式收敛到同一个 choke point，加法**先做域校验**（Int64 中间量），不许绕回。
/// - 截止时刻超出可表示域 ⇒ **饱和到域上界**（`secs_to_iso(iso_domain_upper_secs())`，
///   即 2037-12-31T23:59:59Z）：语义是「远在声明域之外，最远只能说这么多」，
///   刻意**不是**空串（空串是缺陷症状），也刻意**不是**不可表示日期。
/// - `now` 本身非法/域外 ⇒ `next_switch_at` = ""（「无法盖章」，修前这里会写出 1970 的 bogus 日期）。
/// - 合法窗口（默认 18000）逐字零回归。
///
/// ## 变异对照（判例-29/30：改坏的是代码行，不是注释）
///
/// - 把 choke point 里的 `if deadline > bound.to_int64()` 饱和分支删掉（退回裸 Int32 加法）⇒
///   `bug586_huge_window_seconds_does_not_wrap_deadline_to_empty`、
///   `bug586_domain_edge_is_exact_then_saturated` 红（这就是修前形态）。
/// - 把 `if now_secs < 0 { return "" }` 删掉 ⇒ `bug586_invalid_now_reports_unknown_not_bogus_1970` 红。
/// - 把饱和值从 `secs_to_iso(bound)` 改成 `secs_to_iso(bound + 1)`（或写死 2038）⇒
///   `bug586_domain_edge_is_exact_then_saturated` 与
///   `bug586_iso_domain_upper_is_derived_not_hardcoded` 红（域上界必须与 `iso_to_secs` 自己一致）。

///|
/// 造一个只有 window_seconds 可变的路由器（池与限额固定，路由分支必须可达）。
fn bug586_router(window_seconds : Int32) -> ModelRouter {
  let cfg = {
    window_seconds,
    threshold_pct: 95.0,
    free_models: [ModelQuota::new(name="free-a", tier=Free, limit=5)],
    paid_models: [ModelQuota::new(name="paid-a", tier=Paid, limit=5)],
    ofm_endpoint: "",
    use_laya: false,
    use_caf_memory: false,
    caf_default_preference: [],
    caf_min_evidences: 10,
  }
  ModelRouter::from_config(cfg)
}

///|
/// 本文件统一时钟：`iso_to_secs` 精确等于 1790000000（与 model_router_wbtest 的 rt_at 同源）。
let bug586_now = "2026-09-23T16:00:00Z"

///|
/// 复现格（修前必红）：配置给到 num_to_int_safe 允许的上界附近 ⇒ Int32 加法绕回负 ⇒
/// `next_switch_at` 被写成空串。
test "bug586_huge_window_seconds_does_not_wrap_deadline_to_empty" {
  let now_secs = iso_to_secs(bug586_now)
  assert_eq(secs_to_iso(now_secs), bug586_now) // 前提可核对：本格的被加数取的是同一秒
  assert_true(
    now_secs.to_int64() + 2000000000L > 2147483647L,
    msg="前提：2_000_000_000 这一档确实越过 Int32 上界（否则本格测不到绕回）",
  )
  // now_secs + 2000000000 > 2^31-1 —— 修前在这一格里绕回成负值 ⇒ secs_to_iso 给 ""
  let r = bug586_router(2000000000)
  let d = r.pick(now=bug586_now)
  assert_true(
    d.available,
    msg="本格要测的是展示字段，不是可用性",
  )
  if d.next_switch_at.is_empty() {
    abort(
      "next_switch_at 空 = Int32 绕回后 secs_to_iso 的负秒分支（BUG-586 本体）",
    )
  }
  // 饱和必须落在可表示域内：这条串要能被 iso_to_secs 读回来（修前两种坏形态都读不回）
  assert_true(
    iso_to_secs(d.next_switch_at) > 0,
    msg="next_switch_at 必须是可表示日期，实际=\{d.next_switch_at}",
  )
  assert_eq(
    d.next_switch_at,
    "2037-12-31T23:59:59Z",
    msg="超出声明域 ⇒ 饱和到域上界",
  )
}

///|
/// 边界格（修前必红）：域边界**两侧各一格**——恰好在域内要精确、越界一格要饱和，
/// 这样「删饱和分支」与「饱和算错一格」两种变异都能被区分出来。
test "bug586_domain_edge_is_exact_then_saturated" {
  let bound = iso_to_secs("2037-12-31T23:59:59Z")
  assert_true(bound > 0, msg="前提：2037-12-31T23:59:59Z 在声明域内")
  let w_max = bound - iso_to_secs(bug586_now)
  // ① 恰好用满可表示域：精确值（不得被饱和逻辑抢先夹掉，也不得绕回）
  let d_exact = bug586_router(w_max).pick(now=bug586_now)
  assert_eq(d_exact.next_switch_at, "2037-12-31T23:59:59Z")
  // ② 少 1 秒：仍精确
  let d_below = bug586_router(w_max - 1).pick(now=bug586_now)
  assert_eq(d_below.next_switch_at, "2037-12-31T23:59:58Z")
  // ③ 多 1 秒：和仍是合法 Int32（2145916800），但**日期已出声明域**——
  //    修前这里写出 "2038-01-01T00:00:00Z"（iso_to_secs 读不回 = 下游眼里的非法串）
  let d_over = bug586_router(w_max + 1).pick(now=bug586_now)
  assert_eq(
    d_over.next_switch_at,
    "2037-12-31T23:59:59Z",
    msg="越界一格 ⇒ 饱和到域上界，绝不写不可表示日期",
  )
  assert_true(iso_to_secs(d_over.next_switch_at) > 0)
}

///|
/// 正常路径不变格：默认窗口 18000 的读数逐字零回归（三处算式的公共形状各测一处）。
test "bug586_normal_window_unchanged" {
  // 期望值取的就是**修前那条算式本身**（零回归的定义：新算式在域内必须逐字等于旧算式）
  let expected = secs_to_iso(iso_to_secs(bug586_now) + 18000)
  let r = bug586_router(18000)
  let d = r.pick(now=bug586_now)
  assert_true(d.available)
  assert_eq(
    d.next_switch_at,
    expected,
    msg="合法窗口的截止时刻不得被域校验改动",
  )
  // 手动切换算式点（原 :1190-1192）同一条 choke point ⇒ 同一条读数
  let d2 = r.force_switch(tier=Paid, now=bug586_now)
  assert_true(d2.available)
  assert_eq(d2.next_switch_at, expected)
  // 软性提示算式点（原 :904）：pick 带 laya 档位提示，仍走同一条读数
  let d3 = r.pick(now=bug586_now, laya_prefer_tier="free")
  assert_eq(d3.next_switch_at, expected)
}

///|
/// 另一半缺陷（修前必红）：`now` 非法/域外时，修前的算式是 `secs_to_iso(-1 + 18000)` ⇒
/// 写出 **1970 的 bogus 截止时刻**（看起来完全合法）。修后如实报「无法盖章」= 空串。
test "bug586_invalid_now_reports_unknown_not_bogus_1970" {
  let r = bug586_router(18000)
  let d = r.pick(now="not-a-date")
  assert_eq(
    d.next_switch_at,
    "",
    msg="非法 now 不得产出可路由的假截止时刻（修前=1970-01-01T04:59:59Z）",
  )
  // 域外 now（2038 起）同理：空串，而不是 1970 的假值
  let d2 = r.pick(now="2038-01-01T00:00:00Z")
  assert_eq(d2.next_switch_at, "")
}

///|
/// 域上界必须是**反解出来的**，不是写死的年份常数（BUG-218 的边界由 `iso_to_secs` 自己
/// 定义；写死一个数就是下一颗漂移雷——本仓为同类自述滞后返工过多次）。
test "bug586_iso_domain_upper_is_derived_not_hardcoded" {
  let bound = iso_domain_upper_secs()
  assert_eq(
    bound,
    iso_to_secs("2037-12-31T23:59:59Z"),
    msg="派生上界必须 == iso_to_secs 自己的边界",
  )
  // 上界自身往返成立，上界 +1 不再成立（单调性：饱和点就落在这一格）
  assert_eq(secs_to_iso(bound), "2037-12-31T23:59:59Z")
  assert_eq(
    iso_to_secs(secs_to_iso(bound + 1)),
    -1,
    msg="上界之上一个秒已出声明域",
  )
  assert_true(
    bound < 2147483647,
    msg="上界必须严格小于 Int32 max（否则绕回仍在域内）",
  )
}
