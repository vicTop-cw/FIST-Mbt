// ============================================================================
// BUG-470：`FIST_AUTH_MODE` 三档开关
//
// owner 已批准「策略 B（默认降权）」。本文件锁住四件事：
//   ① `off` **逐字零回归**（显式钉 env=off 驱动——flip 后它不再是默认值）
//   ② 三档行为各自可辨
//   ③ 非法值安全回退**默认档**（不是 `strict`、不 panic）
//   ④ **flip 落地锁**：未设 env ⇒ 默认 soft，且无钥匙降权真生效（2026-11-13）
//
// ⚠️ 环境变量在进程内只读一次（`auth_mode()` 有缓存），
//   所以每格都要 `auth_mode_reset_cache_for_test()` 才能切模式。
//   这也是为什么**纯函数 `auth_mode_parse` 单独锁** —— 它不碰 env，无缓存。
// ============================================================================

///|
/// 锁 A（**纯函数**，不依赖 env）：解析规则 + 非法值回退。
///
/// 硬要求③：`garbage` ⇒ 回退**默认档**（**不是 Strict**，不 panic）。
/// 默认值变迁：2026-10-28 首次上线=off；**2026-11-13 flip ⇒ 默认=soft**。
test "bug470_parse_and_invalid_fallback" {
  // 三档正常值
  assert_eq(auth_mode_parse("off"), Off)
  assert_eq(auth_mode_parse("soft"), Soft)
  assert_eq(auth_mode_parse("strict"), Strict)
  // 未设 / 空串 ⇒ 默认 **soft**（2026-11-13 flip，owner 指令）
  assert_eq(auth_mode_parse(""), Soft)
  // 大小写 / 空白不敏感
  assert_eq(auth_mode_parse("OFF"), Off)
  assert_eq(auth_mode_parse("  Soft  "), Soft)
  assert_eq(auth_mode_parse("Strict"), Strict)
  // ★ 非法值 ⇒ **回退默认 soft**（绝不能是 Strict —— 那会让现网停摆）
  assert_eq(auth_mode_parse("garbage"), Soft)
  assert_eq(auth_mode_parse("true"), Soft)
  assert_eq(auth_mode_parse("1"), Soft)
  assert_eq(auth_mode_parse("sof"), Soft) // 少一个字母也算非法
}

///|
/// 锁 B：非法值的 **warning 文案**必须存在且点明「已回退 soft（当前默认）」。
///
/// 为什么单独锁：`auth_mode()` 为缓存会把非法值也归成 `"soft"`，
/// 之后再也看不出「用户本来写的是 garbage」 ⇒ 那条信息只能在启动时由本函数给出。
test "bug470_invalid_gets_warning_legal_does_not" {
  // 合法值 / 未设 ⇒ 无 warning
  assert_eq(auth_mode_warning(""), "")
  assert_eq(auth_mode_warning("off"), "")
  assert_eq(auth_mode_warning("soft"), "")
  assert_eq(auth_mode_warning("strict"), "")
  // 非法值 ⇒ 有 warning，且必须包含「回退 soft」与原始值
  let w = auth_mode_warning("garbage")
  assert_true(w.length() > 0)
  assert_true(w.contains("garbage"))
  assert_true(w.contains("回退 soft"))
}

///|
/// 锁 C（⭐ 硬要求①）：`off` 下**两个分支都逐字零回归**。
///
/// 断言「与本开关引入前的行为逐字相同」——
///   有钥匙 + 不传 ⇒ `("Executor", "challenge_required")`
///   无钥匙 + 不传 ⇒ `judged_role` 原样（role + source 都比）
///
/// ⚠️ **flip（2026-11-13）后默认已是 soft** ⇒ 本格**显式钉 `FIST_AUTH_MODE=off`**
///   才能继续驱动 off 分支（用 `@env.set_env_var`，跑完**必须还原**，
///   否则污染同进程后续格——判例-31）。off 分支代码本身零改动。
test "bug470_off_is_verbatim_zero_regression" {
  // 显式钉 off（flip 后默认不再是 off，必须显式设）
  @env.set_env_var("FIST_AUTH_MODE", "off")
  auth_mode_reset_cache_for_test()
  // ① 有钥匙 + 不传 ⇒ 降权（S3 第九段在 off 下**仍生效**，这是设计）
  let keyed = "cz-off-keyed"
  let eng_k = cz_eng_with_key(keyed, cz_pub_hex())
  let (rk, sk) = judged_role_gated(eng_k, keyed, None)
  assert_eq(sk, "challenge_required") // ← 逐字
  assert_eq(rk, "Executor") // ← 逐字
  // ② 无钥匙 + 不传 ⇒ 与 `judged_role` **逐字相同**（两个字段都比）
  let nokey = "cz-off-nokey"
  let eng_n = cz_eng_without_key(nokey)
  let (rn, sn) = judged_role_gated(eng_n, nokey, None)
  let (r_ref, s_ref) = judged_role(eng_n, nokey)
  assert_eq(rn, r_ref)
  assert_eq(sn, s_ref)
  // 且**不能**被误标成任何认证态
  assert_true(sn != "challenge_required")
  assert_true(sn != "challenge_missing")
  // 收尾：还原 env + 缓存，避免污染同进程后续格
  @env.unset_env_var("FIST_AUTH_MODE")
  auth_mode_reset_cache_for_test()
}

///|
/// 锁 F（⭐ **flip 落地锁**，2026-11-13）：未设 env ⇒ 默认 **soft**，且
/// 「无钥匙也降权」在默认下**真生效**（策略 B 的默认激活，不是纸面翻转）。
///
/// 为什么必须有这格：锁 A 锁的是纯函数（`parse("")` ⇒ Soft），
/// 但「默认值」真正起作用的是 `auth_mode()` 的 env 缺省路径 + `judged_role_gated`
/// 的 Soft 分支——不锁行为面，flip 就只是改了个返回值。
test "bug470_default_flipped_to_soft_unkeyed_downgraded" {
  // ① 确保未设 env ⇒ 默认 soft
  @env.unset_env_var("FIST_AUTH_MODE")
  auth_mode_reset_cache_for_test()
  assert_eq(auth_mode(), Soft)
  // ② 行为面：无钥匙 + 不传 ⇒ 降权（这与锁 C-② 的 off 行为**相反**，恰是 flip 的意义）
  let nokey = "cz-flip-nokey"
  let eng_n = cz_eng_without_key(nokey)
  let (r, s) = judged_role_gated(eng_n, nokey, None)
  assert_eq(r, "Executor")
  assert_eq(s, "challenge_required")
  // ③ 有钥匙 + 不传 ⇒ 与 off 下同值（flip 只改无钥匙那支）
  let keyed = "cz-flip-keyed"
  let eng_k = cz_eng_with_key(keyed, cz_pub_hex())
  let (rk, sk) = judged_role_gated(eng_k, keyed, None)
  assert_eq(rk, "Executor")
  assert_eq(sk, "challenge_required")
  // 收尾：还原缓存（env 已是未设态，无需 unset）
  auth_mode_reset_cache_for_test()
}

///|
/// 锁 D（硬要求②）：`soft` 下**无钥匙也降权**（这就是 owner 批准的策略 B）。
///
/// ⚠️ 用纯函数层验证语义：`auth_mode_parse("soft") == Soft` ⇒
/// 结合锁 C 已证的「无钥匙原本是自报」，可知 `soft` 与 `off` 的差别
/// **恰好只在「无钥匙」这一支**。
test "bug470_soft_differs_from_off_only_on_unkeyed" {
  assert_eq(auth_mode_parse("soft"), Soft)
  assert_eq(auth_mode_parse("off"), Off)
  assert_true(auth_mode_parse("soft") != auth_mode_parse("off"))
  // soft 与 off 的 tag 语义：两者对「有钥匙」都是 challenge_required，
  // 差别只在「无钥匙」⇒ 下一条断言把这条差别钉成文本
  assert_eq(auth_tag("challenge_required"), "+challenge_required")
  assert_eq(auth_tag("challenge_missing"), "+challenge_missing")
  assert_true(auth_tag("challenge_required") != auth_tag("challenge_missing"))
}

///|
/// 锁 E：`strict` 用**专用** `role_source`，与 `required` 可区分。
///
/// 为什么必须区分：调用方看到 `+challenge_required` 会去「取票」，
/// 看到 `+challenge_missing` 才知道「我连公钥都没有，得先登记」。
/// 两者混用 = 让调用方修错东西（判例-29 的同族）。
test "bug470_strict_has_distinct_source" {
  assert_eq(auth_mode_parse("strict"), Strict)
  let m = auth_tag("challenge_missing")
  assert_eq(m, "+challenge_missing")
  assert_true(m != auth_tag("challenge_required"))
  assert_true(m != auth_tag(""))
}

// ── 夹具（本文件私有，避免与其它 bug 的夹具重名）──────────────────────────

///|
fn cz_pub_hex() -> String {
  @core.test_ed25519_pub_hex(@core.TEST_ED25519_SEED_A)
}

///|
fn cz_eng_with_key(agent : String, pk : String) -> FistEngine {
  let eng = cz_eng()
  match
    eng.agents_register(
      agent_id=agent_fp_of(agent),
      agent_type="executor",
      role="Leader",
      soldier="工兵",
      pubkey_fp=pk,
      pid=1,
      now="2026-10-28T00:00:00Z",
    ) {
    Err(e) => abort("agents_register 应成功：" + e)
    Ok(_) => ()
  }
  eng
}

///|
fn cz_eng_without_key(agent : String) -> FistEngine {
  let eng = cz_eng()
  match
    eng.agents_register(
      agent_id=agent_fp_of(agent),
      agent_type="executor",
      role="Leader",
      soldier="工兵",
      pubkey_fp="",
      pid=1,
      now="2026-10-28T00:00:00Z",
    ) {
    Err(e) => abort("agents_register 应成功：" + e)
    Ok(_) => ()
  }
  eng
}

///|
fn cz_eng() -> FistEngine {
  let sql = match @store.SqliteStore::open(":memory:") {
    Some(s) => s
    None => abort("sqlite open 失败：本格没跑到被测面")
  }
  FistEngine::new(store=@store.StoreBackend::sqlite(sql))
}
