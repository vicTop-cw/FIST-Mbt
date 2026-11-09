/// src/server/model_router_ops_bug585_wbtest.mbt —— BUG-585 回归锁（冷却加法 Int32 绕回 ⇒ 冷却被静默清除）
///
/// ## 缺陷形态（修前真源 `model_router_ops.mbt:682`）
///
/// `let cool_until = @router.secs_to_iso(now_secs + secs)` 是一步**裸 Int32 加法**：
/// `secs` 来自 env `FIST_MODEL_COOLDOWN_SECS`，经 `bug_parse_int`（`src/server/bugreport.mbt:263-278`，
/// `acc>=2e8` 即 break ⇒ 上限约 1e9 秒）**只要 >0 就采纳**。2026 年 `now_secs≈1.77e9`，
/// 于是 `secs` 只要超过 `2^31-1 - now_secs`（≈3.8e8，逐年递减）就**绕回成负值** ⇒
/// `secs_to_iso` 走负秒分支产出 **""** ⇒ `in_cooldown(...,"")` 恒 false ⇒
/// **冷却静默清除**（fail-open，回执零字，调用方以为已冷却）。本仓 `in_cooldown` 的
/// cool 臂（BUG-206）防了「冷却形同虚设」，却没防「算式自己把冷却写成空」这一头。
///
/// ## 修复后的行为面（本文件锁住）
///
/// - 算式收敛到 `mr_cooldown_deadline`：**加法前**做域校验（减法形式，绕回点不参与运算），
///   越界一律显式 `Err`，文案点名配置项名 + 从当前 `now_secs` 推导的可用上限（BUG-580 判例：
///   荒谬输入报错，不静默；上限不写死年份常数，由 `@router.iso_domain_upper_secs()` 反解）。
/// - `now` 本身非法/域外 ⇒ 同样显式 `Err`（修前：`secs_to_iso(-1 + 300)` 写出 1970 假截止，
///   那比空串更像「成功了」）。
/// - `secs<=0` ⇒ `Err`（BUG-580 C2 同族：负值/零不许静默采纳）。
/// - 合法路径逐字零回归：`secs=300` 仍得 `now+300` 的 ISO；`mr_record_failure` 的
///   「模型不在池中 ⇒ Ok」不变。
///
/// ## 变异对照（判例-29/30：改坏的是代码行，不是注释）
///
///   · 把 `mr_cooldown_deadline` 的两道守卫删掉、直接 `Ok(@router.secs_to_iso(now_secs + secs))`
///     （= **修前形态**）⇒ `bug585_absurd_cooldown_secs_is_rejected_not_silently_cleared`、
///     `bug585_cooldown_deadline_domain_edge_two_sides`、
///     `bug585_poison_chain_empty_cooldown_never_locks` 三格全红。
///   · 把可用上限写成固定常数（如 `2147483647 - now_secs`）⇒ 域边界格红（上界必须是
///     `iso_to_secs` 自己声明的域，不是 Int32 max）。
///   · 把 `now_secs < 0` 那档改回放行 ⇒ `bug585_out_of_domain_clock_is_explicit_error` 红。

///|
/// 本文件统一时钟（合法、域内，`iso_to_secs` 精确等于 1790000000）。
let bug585_now = "2026-09-23T16:00:00Z"

///|
/// 复现格（修前必红 = 见文件头变异对照第一发）：荒谬的 `FIST_MODEL_COOLDOWN_SECS`
/// 必须**显式报错**并点名配置项与可用上限，绝不产出 ""。
test "bug585_absurd_cooldown_secs_is_rejected_not_silently_cleared" {
  let now_secs = @router.iso_to_secs(bug585_now)
  assert_eq(@router.secs_to_iso(now_secs), bug585_now) // 前提可核对：被加数就是这一秒
  // 修前的病灶：这一步在 Int32 下绕回负值，secs_to_iso 产出 ""（不报错、不回执）
  let hostile = 400000000
  assert_true(
    now_secs.to_int64() + hostile.to_int64() > 2147483647L,
    msg="前提：该 secs 确实越过 Int32 上界（否则本格测不到绕回）",
  )
  match mr_cooldown_deadline(bug585_now, hostile) {
    Err(e) => {
      assert_true(
        e.contains("FIST_MODEL_COOLDOWN_SECS"),
        msg="错误文案必须点名配置项名，实际=\{e}",
      )
      // 可用上限从当前 now_secs 按公式推导，不写死年份常数
      let bound = @router.iso_domain_upper_secs()
      let max_secs = bound - now_secs
      assert_true(
        e.contains(max_secs.to_string()),
        msg="错误文案必须给出可用上限 \{max_secs}，实际=\{e}",
      )
      assert_true(max_secs > 0 && max_secs < hostile)
    }
    Ok(s) =>
      abort(
        "荒谬 secs 被静默采纳，得到 cool_until='\{s}'（BUG-585 本体）",
      )
  }
  // 更大的值（bug_parse_int 的上限附近）同样拒绝，不许「越界越深越像成功」
  match mr_cooldown_deadline(bug585_now, 999999999) {
    Err(_) => ()
    Ok(s) => abort("secs=999999999 仍被静默采纳：'\{s}'")
  }
}

///|
/// 后果格（判例-29：机制格≠实现路径格）：修前那条 "" 一旦写进 cooldown_until，
/// `in_cooldown` 就**永远** false —— 冷却这一层保护整条消失。本格把「服务端算式 →
/// 路由准入判定」这条链钉住：守卫放行的一定是可用 ISO，且真在冷却期。
test "bug585_poison_chain_empty_cooldown_never_locks" {
  // 跨包取档位走 router 的 pub 解析入口 `ModelTier::from_string`（枚举构造子的跨包写法
  // 在本版工具链不稳：`@router.Free` 被判成「read-only type」——测试不许依赖实现细节）
  let free_tier = match @router.ModelTier::from_string("free") {
    Some(t) => t
    None => abort("前提：'free' 必须能解析成档位")
  }
  let q = @router.ModelQuota::new(name="free-a", tier=free_tier, limit=5)
  // ① 病灶的可观测面：空冷却截止 = 永不冷却（这就是修前绕回后的落点）
  q.mark_failure("")
  assert_false(
    q.in_cooldown(bug585_now),
    msg="前提：'' 走 fail-open，不是永久锁",
  )
  // ② 守卫后的合法截止必须真的锁住模型（「不静默」的另一半：写进去的值要有效）
  let ok = match mr_cooldown_deadline(bug585_now, 300) {
    Ok(s) => s
    Err(e) => abort("合法 secs=300 被拒：\{e}")
  }
  let q2 = @router.ModelQuota::new(name="free-b", tier=free_tier, limit=5)
  q2.mark_failure(ok)
  assert_true(q2.in_cooldown(bug585_now), msg="300 秒冷却必须生效")
  assert_eq(
    ok,
    "2026-09-23T16:05:00Z",
    msg="零回归：截止 == now+300 逐字不变",
  )
}

///|
/// 正常路径不变格：合法值逐字零回归 + `mr_record_failure` 的既有语义没被守卫改动。
test "bug585_normal_cooldown_path_unchanged" {
  // 默认 300 秒（env 未设时 mr_record_failure 用的就是这个值）
  match mr_cooldown_deadline(bug585_now, 300) {
    Ok(s) => assert_eq(s, "2026-09-23T16:05:00Z")
    Err(e) => abort("合法输入被拒：\{e}")
  }
  // 常见量级（1 小时 / 1 天）同样精确
  match mr_cooldown_deadline("2026-11-05T00:00:00Z", 3600) {
    Ok(s) => assert_eq(s, "2026-11-05T01:00:00Z")
    Err(e) => abort("合法输入被拒：\{e}")
  }
  // 既有防御语义：模型不在池中 ⇒ Ok(())（守卫不许把这条路径变成 Err）
  match
    mr_record_failure("bug585-nonexistent-dir", "no-such-model", ns="bug585") {
    Ok(_) => ()
    Err(e) => abort("模型不在池中应回 Ok，实得 Err：\{e}")
  }
}

///|
/// 边界格：域上界的**两侧各一格** + 「上界本身必须是 iso_to_secs 的域，不是 Int32 max」。
test "bug585_cooldown_deadline_domain_edge_two_sides" {
  let now_secs = @router.iso_to_secs(bug585_now)
  let bound = @router.iso_domain_upper_secs()
  // 派生上界必须 == iso_to_secs 自己声明的边界（写死 Int32 max 的变异在这里红）
  assert_eq(bound, @router.iso_to_secs("2037-12-31T23:59:59Z"))
  assert_true(bound < 2147483647, msg="域上界必须严格小于 Int32 max")
  let max_secs = bound - now_secs
  // ① 恰好用满：可表示的最晚冷却截止
  match mr_cooldown_deadline(bug585_now, max_secs) {
    Ok(s) => assert_eq(s, "2037-12-31T23:59:59Z")
    Err(e) => abort("恰在域内上界应放行：\{e}")
  }
  // ② 越界一格：显式 Err（修前这里是「静默 ""」或「2038 假日期」两种坏形态）
  match mr_cooldown_deadline(bug585_now, max_secs + 1) {
    Err(_) => ()
    Ok(s) => abort("越界一格仍被采纳：'\{s}'")
  }
  // ③ 时钟已经走到域上界那一秒：可用上限 = 0，任何正 secs 都必须显式拒绝
  match mr_cooldown_deadline("2037-12-31T23:59:59Z", 1) {
    Err(e) =>
      assert_true(
        e.contains("FIST_MODEL_COOLDOWN_SECS"),
        msg="文案点名配置项，实际=\{e}",
      )
    Ok(s) => abort("声明域最后一秒仍写入冷却：'\{s}'")
  }
}

///|
/// 另一半缺陷（修前必红）：`now` 本身非法/域外时，修前的算式是
/// `secs_to_iso(-1 + 300)` ⇒ 写出 **"1970-01-01T00:04:59Z"** 这种看着完全合法的假截止
/// （比空串更坏：下游把它当真实冷却期，且永远「已过期」）。修后一律显式 Err。
test "bug585_out_of_domain_clock_is_explicit_error" {
  match mr_cooldown_deadline("not-a-date", 300) {
    Err(e) =>
      assert_true(
        e.contains("1970-01-01T00:04:59Z") || e.contains("可表示域"),
        msg="实际=\{e}",
      )
    Ok(s) =>
      abort("非法 now 被静默采纳成假截止 '\{s}'（修前形态）")
  }
  // 2038 起（声明域外，BUG-218）同样显式失败，不产出假值
  match mr_cooldown_deadline("2038-01-01T00:00:00Z", 300) {
    Err(_) => ()
    Ok(s) => abort("域外时钟被静默采纳成假截止 '\{s}'")
  }
  // secs 非正（含负值）不许静默采纳 —— BUG-580 C2 同族
  match mr_cooldown_deadline(bug585_now, 0) {
    Err(_) => ()
    Ok(s) => abort("secs=0 被静默采纳：'\{s}'")
  }
  match mr_cooldown_deadline(bug585_now, -5) {
    Err(_) => ()
    Ok(s) => abort("secs=-5 被静默采纳：'\{s}'")
  }
}
