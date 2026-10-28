// ============================================================================
// BUG-430 / S3 **第九段**：有钥匙就必须出示（软强制降权）
//
// 上一段（BUG-466）装了「取票窗口」，产品面能拿 challenge 并验签通过。
// 但还剩最后一个口子：**「有钥匙的人可以不用钥匙进门」**。
//
//   · agent 有公钥 + 传 challenge   ⇒ challenge_verified   ✅
//   · agent 有公钥 + **不传**       ⇒ 仍按自报角色放行     ❌ ← 本段堵
//   · agent 没公钥 + 不传           ⇒ 原样（合理）
//
// 规则（增量，只加严不放宽）：
//   有公钥 + 无 challenge ⇒ ("Executor", "challenge_required")  降级，不拒
//   没公钥 + 无 challenge ⇒ judged_role 原样                     零回归
//
// 本文件锁：
//   锁 1  有钥匙 + 真签名 ⇒ challenge_verified（稳定）
//   锁 2  有钥匙 + 不传   ⇒ challenge_required **且角色降到 Executor**
//   锁 3  没钥匙 + 不传   ⇒ **原样**（与 judged_role 逐字相同，零回归）
//   锁 4（变异对照）删掉「有钥匙必须验签」判断 ⇒ 锁 2 必红
// ============================================================================

///|
/// 测试密钥对（复用 BUG-466 已验证可用的 seed）。
fn cf_seed() -> Bytes {
  b"\x3a\x7f\x21\xb4\x5c\x0e\x99\x12\xaa\x3d\x61\x8f\x24\xbe\x07\xc5\xd8\x19\x42\xe0\x7b\x53\x96\x2c\x1a\x88\xf4\x0d\x6e\x31\xb7\x95"
}

///|
fn cf_pub_hex() -> String {
  @mooncry.bytes_to_hex(@mooncry.ed25519_public_key(cf_seed()))
}

///|
fn cf_sign(msg : String) -> String {
  @mooncry.bytes_to_hex(@mooncry.ed25519_sign(cf_seed(), @utf8.encode(msg)))
}

///|
/// 建引擎；`with_key=true` 时给该 agent 登记公钥，否则不给。
fn cf_eng(agent : String, with_key : Bool) -> FistEngine {
  let sql = match @store.SqliteStore::open(":memory:") {
    Some(s) => s
    None => abort("sqlite open 失败：本格没跑到被测面")
  }
  let eng = FistEngine::new(store=@store.StoreBackend::sqlite(sql))
  if with_key {
    match
      eng.agents_register(
        agent_id=agent_fp_of(agent),
        agent_type="executor",
        role="Leader",
        soldier="工兵",
        pubkey_fp=cf_pub_hex(),
        pid=1,
        now="2026-10-28T00:00:00Z",
      ) {
      Err(e) => abort("agents_register 应成功：" + e)
      Ok(_) => ()
    }
  }
  eng
}

///|
/// 锁 1：**有钥匙 + 真签名 ⇒ challenge_verified**（修前能过，修后必须仍能过）。
test "bug430cf_c1_keyed_with_valid_sig_verifies" {
  let agent = "cf-keyed-ok"
  let eng = cf_eng(agent, true)
  let chal = eng.s3_issue_challenge_auto(agent)
  let (role, src) = judged_role_with_nonce(
    eng, agent, Some(chal), challenge_sig=Some(cf_sign(chal)),
  )
  assert_eq(src, "challenge_verified")
  // 拿到的是登记的角色（Leader），不是被降级的 Executor
  assert_eq(role, "Leader")
}

///|
/// 锁 2（★ 本段核心）：**有钥匙但不出示 ⇒ 降级，且降级可见**。
///
/// 两件事同时断言：
///   ① `role_source == "challenge_required"`（不是静默降权）
///   ② `role == "Executor"`（fail-closed，不认它自称的 Leader）
test "bug430cf_c2_keyed_without_challenge_is_downgraded" {
  let agent = "cf-keyed-nochal"
  let eng = cf_eng(agent, true)
  let (role, src) = judged_role_gated(eng, agent, None)
  assert_eq(src, "challenge_required")
  assert_eq(role, "Executor")
  // 可见性：action 面必须有专门的后缀
  assert_eq(auth_tag("challenge_required"), "+challenge_required")
}

///|
/// 锁 3（★ 零回归）：**没钥匙 + 不传 ⇒ 与修前逐字相同**。
///
/// 判据是「与 `judged_role` 的结果**逐字相同**」，不是「看起来对」。
/// 既要 role 相同，也要 role_source 相同（`declared` / `inferred` 原样保留）。
test "bug430cf_c3_unkeyed_without_challenge_is_unchanged" {
  let agent = "cf-nokey"
  let eng = cf_eng(agent, false)
  let (role, src) = judged_role_gated(eng, agent, None)
  let (role_ref, src_ref) = judged_role(eng, agent)
  // ★ 逐字相同（零回归的硬判据）
  assert_eq(role, role_ref)
  assert_eq(src, src_ref)
  // 且**不能**被误标成新态
  assert_true(src != "challenge_required")
}

///|
/// 锁 4（⭐ **变异对照**）：把「有钥匙必须验签」的判断改坏
/// （等价于 `declared_pubkey_for(...) is Some(_)` 恒 false）⇒ 锁 2 必红。
///
/// **不 grep 源码字符串**（会命中注释 ⇒ 判例-30 自指假绿），
/// 只断言行为：同一 agent（有钥匙、不传 challenge）在修好后必须是
/// `challenge_required`；若那条判断失效，它会退回 `declared` / `inferred`。
test "bug430cf_c4_variant_removing_keyed_check_breaks_lock2" {
  let agent = "cf-variant"
  let eng = cf_eng(agent, true)
  let (_role, src) = judged_role_gated(eng, agent, None)
  // ★ 修好后必须是 challenge_required
  assert_eq(src, "challenge_required")
  // ★ 若判断被删，这里会是 judged_role 的原值（declared / inferred）——两者必不同
  let (_r2, src_ref) = judged_role(eng, agent)
  assert_true(src != src_ref)
}

///|
/// 锁 5：**降级会真的让高权操作被拒**（软强制的作用点）。
///
/// 光「role 变成 Executor」不足以说明危害 —— 必须证明它在**军衔门**上真的掉档。
/// `rank_of_role("Leader")` 与 `rank_of_role("Executor")` 必须不同，
/// 且 Executor 的军衔不能认领高层级任务。
test "bug430cf_c5_downgrade_actually_costs_authority" {
  let agent = "cf-authority"
  let eng = cf_eng(agent, true)
  let (role_downgraded, _) = judged_role_gated(eng, agent, None)
  let (role_claimed, _) = judged_role(eng, agent)
  assert_eq(role_downgraded, "Executor")
  assert_eq(role_claimed, "Leader")
  // 两个角色的军衔必须不同（否则降级等于没降）
  let ar_d = rank_of_role(role_downgraded)
  let ar_c = rank_of_role(role_claimed)
  assert_true(ar_d != ar_c)
  // fail-closed 的方向：降级后的军衔**比原来小**（数值大 = 权限窄）
  assert_true(ar_d > ar_c)
}

///|
/// 锁 6（⚠️ **本单发现的真 bug，必须钉死**）：
/// **预取认证标签绝不能消费 nonce** —— 否则 `claim` 内部那次拿到 `challenge_replayed`，
/// 而回执却显示 `+challenge_verified`（**假绿回执**）。
///
/// 实测代价（修前 `server.mbt` 的写法）：生产面 `claim` 回
/// `action = '+challenge_verified'`，但 `judged_role_with_nonce` 第二次返回
/// `challenge_replayed` ⇒ **行为其实是未认证/降级的，而回执说认证通过**。
/// 比不显示更糟：调用方以为认证过了。
///
/// 本格同时钉住：
///   ① `judged_role_with_challenge` **不消费** nonce（可安全预取）
///   ② `judged_role_with_nonce` **消费** nonce（验签通过后）
///   ⇒ 两者差别正是「预取该用哪一个」的判据。
test "bug430cf_c6_prefetch_must_not_consume_nonce" {
  let agent = "cf-prefetch"
  let eng = cf_eng(agent, true)
  let chal = eng.s3_issue_challenge_auto(agent)
  let sig = cf_sign(chal)
  // ① 只验签、不消费的那一侧：连调两次都必须 verified（nonce 未被吃掉）
  let (_r1, w1) = judged_role_with_challenge(eng, agent, Some(chal), challenge_sig=Some(sig))
  let (_r2, w2) = judged_role_with_challenge(eng, agent, Some(chal), challenge_sig=Some(sig))
  assert_eq(w1, "challenge_verified")
  assert_eq(w2, "challenge_verified")   // ← 若此句红，说明 with_challenge 也消费了 ⇒ 不能用于预取

  // ② 会消费的那一侧：第一次 verified，**第二次必 replayed**
  let chal2 = eng.s3_issue_challenge_auto(agent)
  let sig2 = cf_sign(chal2)
  let (_n1, n1) = judged_role_with_nonce(eng, agent, Some(chal2), challenge_sig=Some(sig2))
  assert_eq(n1, "challenge_verified")
  let (_n2, n2) = judged_role_with_nonce(eng, agent, Some(chal2), challenge_sig=Some(sig2))
  assert_eq(n2, "challenge_replayed")   // ← 这就是「预取会造成 claim 看到 replayed」的机理
}
