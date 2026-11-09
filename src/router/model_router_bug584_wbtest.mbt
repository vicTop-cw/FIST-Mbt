/// src/router/model_router_bug584_wbtest.mbt —— BUG-584 回归锁（`in_cooldown` 的 now 臂守卫不对称 ⇒ 模型永久锁死）
///
/// ## 缺陷形态（修前真源 `model_router.mbt:163-175`）
///
/// BUG-206 只给 **cool 臂**加了域外守卫（`if cool_secs <= 0 { return false }` ⇒ fail-open），
/// **now 臂**没防：`iso_to_secs(now_iso)` 对域外/非法输入（`y<1970`、`y>2037`、坏串）返回
/// **-1 哨兵**，而 `-1 < cool_secs` 恒真 ⇒ `in_cooldown` 恒真 ⇒ **该模型被永久锁死**
/// （`quota_admitted`/`pool_pick` 永久跳过它，`mark_failure` 也解不开——锁的是判定，不是数据）。
/// 同一个函数的注释自述意图是「fail-open 放行……比永久锁死可恢复」——now 臂的行为与意图
/// **直接矛盾**（注释说 A，代码做 not-A，正是判例-30 那族「自述与实现脱节」）。
///
/// ## 修复后的行为面（本文件锁住）
///
/// - now 侧域外/非法 ⇒ **fail-open**（不在冷却），与 cool 臂同判、与注释意图一致。
/// - 合法 now 的三段边界（早于 / 等于 / 晚于 `cooldown_until`）**零回归**。
/// - epoch-0（`1970-01-01T00:00:00Z`，secs==0）刻意按哨兵处理 ⇒ fail-open：与 cool 臂的
///   `<= 0` 同判。1970 墙钟不是本模块的正常输入，宁可放行也不许把「量不准」当「锁死」。
/// - `window_expired` 的**同形检查**：这一侧刻意维持 **fail-closed**（不过期），因为过期分支
///   会把 `used` 清零并把 `window_start` 改写成这个坏 `now`（=「用坏时钟清零用量」，R231 已锁），
///   与冷却「放行」的方向**相反**是本模块的既定协议。本文件用**哨兵可区分格**
///   （域外 now + 负 window_seconds）把那一格显式守卫钉住。
///
/// ## 变异对照（判例-29/30：改坏的是代码行，不是注释）
///
/// - 删掉 `in_cooldown` 里新增的 `if now_secs <= 0 { return false }` ⇒
///   `bug584_out_of_domain_now_does_not_permanently_lock_model`、
///   `bug584_malformed_now_does_not_permanently_lock_model`、
///   `bug584_pre_epoch_year_now_is_not_a_permanent_lock`、
///   `bug584_pool_pick_recovers_when_clock_is_out_of_domain` **四格全红**（这就是修前形态）。
/// - 把 `window_expired` 的 `if elapsed < 0 { return false }` 改成 `return true` ⇒
///   `bug584_window_expired_same_shape_stays_fail_closed` 红（含负窗口可区分格）。
/// - 把 `elapsed >= window_seconds` 改成 `elapsed > window_seconds` ⇒
///   同格的「恰满窗口应过期」断言红（边界语义 `>=`，与 rt_6 一致）。

///|
fn bug584_cooled_model(cooldown_until : String) -> ModelQuota {
  let q = ModelQuota::new(name="free-a", tier=Free, limit=5)
  q.mark_failure(cooldown_until)
  q
}

///|
/// 复现格①（修前必红）：墙钟走到声明域之外（2038 起，BUG-218 的 1970..2037 边界）——
/// 冷却数据完全合法，`in_cooldown` 却因 `-1 < cool_secs` 恒真而**永久锁死**模型。
test "bug584_out_of_domain_now_does_not_permanently_lock_model" {
  let q = bug584_cooled_model("2026-09-23T16:05:00Z")
  assert_eq(iso_to_secs("2038-01-01T00:00:00Z"), -1) // 前提：域外 ⇒ -1 哨兵
  assert_false(
    q.in_cooldown("2038-01-01T00:00:00Z"),
    msg="now 域外必须 fail-open（修前：-1<cool 恒真 ⇒ 永久锁死）",
  )
  assert_false(
    q.in_cooldown("2037-12-31T23:59:59Z"),
    msg="域内且已晚于冷却截止：本来就应为 false（方向不许被改坏）",
  )
  assert_false(
    q.in_cooldown("2099-12-31T23:59:59Z"),
    msg="远超声明域同样 fail-open",
  )
}

///|
/// 复现格②（修前必红）：非法 `now` 串——**今天就能到达**的那一半（调用方传坏时间戳
/// 即可把某模型永久锁死，不需要等到 2038）。
test "bug584_malformed_now_does_not_permanently_lock_model" {
  let q = bug584_cooled_model("2026-09-23T16:05:00Z")
  assert_eq(iso_to_secs(""), -1)
  assert_false(
    q.in_cooldown(""),
    msg="空 now 是「量不出来」，不得当「永在冷却」（修前恒真）",
  )
  assert_false(q.in_cooldown("not-a-date"), msg="坏串 now 同样 fail-open")
  assert_false(
    q.in_cooldown("2026-09-23T16:00"),
    msg="秒段被截断（length<19 ⇒ iso_to_secs 判非法）同样不得锁死",
  )
}

///|
/// 复现格③（修前必红）：`y<1970` 的另一半声明域外（1969 与 2038 同因：都是 -1 哨兵）。
test "bug584_pre_epoch_year_now_is_not_a_permanent_lock" {
  let q = bug584_cooled_model("2026-09-23T16:05:00Z")
  assert_eq(iso_to_secs("1969-12-31T23:59:59Z"), -1)
  assert_false(
    q.in_cooldown("1969-12-31T23:59:59Z"),
    msg="1970 之下也是域外哨兵，修前 -1<cool 恒真 ⇒ 锁死",
  )
}

///|
/// 后果格（修前必红）：永久锁死不是「一个函数返回错值」，而是**准入判定把可用模型全跳过**
/// ⇒ 路由报不可用。这一格打的是调用面可观测后果（判例-29：机制格≠实现路径格）。
test "bug584_pool_pick_recovers_when_clock_is_out_of_domain" {
  let q0 = bug584_cooled_model("2026-09-23T16:05:00Z")
  let pool = [q0]
  match pool_pick(pool, 0, 95.0, now="2038-01-01T00:00:00Z") {
    Some(i) =>
      assert_eq(
        i,
        0,
        msg="域外 now 下模型必须仍可选（fail-open），不得因哨兵被永久跳过",
      )
    None =>
      abort(
        "域外 now 让唯一候选被永久锁死 —— 正是 BUG-584 的后果面",
      )
  }
  // 反向对照：合法 now 且仍在冷却窗口内时，必须**仍然**跳过（修好不许把冷却改成没有）
  match pool_pick(pool, 0, 95.0, now="2026-09-23T16:04:00Z") {
    Some(i) => abort("合法冷却期内不应放行：得到下标 \{i}")
    None => ()
  }
}

///|
/// 正常路径不变格：三段边界（早于/等于/晚于）与「无冷却」逐条零回归。
test "bug584_normal_cooldown_three_segments_unchanged" {
  let q = bug584_cooled_model("2026-09-23T16:05:00Z")
  assert_true(
    q.in_cooldown("2026-09-23T16:04:59Z"),
    msg="早 1 秒 ⇒ 在冷却",
  )
  assert_false(
    q.in_cooldown("2026-09-23T16:05:00Z"),
    msg="恰好到点 ⇒ 不在冷却（严格 <）",
  )
  assert_false(
    q.in_cooldown("2026-09-23T16:05:01Z"),
    msg="晚 1 秒 ⇒ 不在冷却",
  )
  // 声明域内的最早合法时刻（epoch 秒 = 1）仍要算「在冷却」——守卫不许吞掉合法小值
  assert_true(
    q.in_cooldown("1970-01-01T00:00:01Z"),
    msg="域内合法 now 不得被 fail-open 吞掉",
  )
  let fresh = ModelQuota::new(name="free-b", tier=Free, limit=5)
  assert_false(
    fresh.in_cooldown("2026-09-23T16:00:00Z"),
    msg="cooldown_until 空 = 无冷却",
  )
}

///|
/// 边界格：epoch-0 与 cool 臂的既定口径（`<= 0` 视同哨兵）—— 刻意选择，写死在锁里，
/// 免得后人把 `<= 0` 当笔误改成 `< 0` 时无声改变 1970 墙钟这一格的语义。
test "bug584_epoch_zero_and_cool_arm_sentinels_documented" {
  let q = bug584_cooled_model("2026-09-23T16:05:00Z")
  assert_false(
    q.in_cooldown("1970-01-01T00:00:00Z"),
    msg="epoch-0 与 cool 臂 `<=0` 同判：按哨兵 fail-open（本模块的正常时钟不是 1970）",
  )
  // cool 臂（BUG-206 原锁）不许被 now 臂的改动带回归
  let q2 = bug584_cooled_model("2099-01-01T00:00:00Z")
  assert_false(
    q2.in_cooldown("2026-09-23T16:00:00Z"),
    msg="Y2038 后冷却截止不锁死（BUG-206）",
  )
  let q3 = bug584_cooled_model("1970-01-01T00:00:00Z")
  assert_false(
    q3.in_cooldown("2026-09-23T16:00:00Z"),
    msg="cool_secs==0 走哨兵 ⇒ 放行",
  )
  let q4 = bug584_cooled_model("garbage")
  assert_false(
    q4.in_cooldown("2026-09-23T16:00:00Z"),
    msg="非法冷却截止 ⇒ 放行",
  )
}

///|
/// 同形检查格（`window_expired`）：与 `in_cooldown` **同一个 -1 哨兵**，但方向刻意相反。
/// 这里必须是 fail-closed：过期分支会 `used=0` 并把 `window_start` 写成这个坏 now
/// （=「用坏时钟清零用量」，R231 已锁），比「窗口暂不过期」危险；`window_reset_check`
/// 上游的 `now_s < 0 ⇒ 0 次重置` 是同一条方向。残余后果如实记账：墙钟越过声明域(>2037)
/// ⇒ 窗口永不 expired ⇒ 用量只增不减 —— 出路是时钟 Int64 化迁移，不在本门里偷偷绕过。
test "bug584_window_expired_same_shape_stays_fail_closed" {
  let start = "2026-09-23T16:00:00Z"
  // ① 域外 / 非法 now ⇒ 不过期（两种负 elapsed 成因同方向）
  assert_false(
    window_expired(start, "2038-01-01T00:00:00Z", 18000),
    msg="now 域外：量不出来不能当该重置",
  )
  assert_false(
    window_expired(start, "not-a-date", 18000),
    msg="now 非法：同上",
  )
  // ② 哨兵可区分格（R231 同技术）：**只有**负窗口 + 哨兵这一格能让
  //    「删掉 elapsed<0 显式守卫」的变异发红（-1 >= -5 会被误判为过期）。
  assert_false(
    window_expired(start, "2038-01-01T00:00:00Z", -5),
    msg="域外 now + 负窗口：哨兵(-1)必须拦住，不得误判过期",
  )
  assert_false(
    window_expired("", "2038-01-01T00:00:00Z", -5),
    msg="非法 start + 域外 now + 负窗口：同上",
  )
  // ③ 正常三段边界零回归（`>=` 语义，恰满即到期）
  assert_true(
    window_expired(start, "2026-09-23T21:00:00Z", 18000),
    msg="恰 5h ⇒ 过期",
  )
  assert_false(
    window_expired(start, "2026-09-23T20:59:59Z", 18000),
    msg="差 1 秒 ⇒ 未过期",
  )
  // ④ 时钟倒挂（两端都合法、now 早于 start）：同为负 elapsed，同样不过期
  assert_false(
    window_expired("2026-09-23T21:00:00Z", start, 18000),
    msg="倒挂不得重置用量",
  )
}
