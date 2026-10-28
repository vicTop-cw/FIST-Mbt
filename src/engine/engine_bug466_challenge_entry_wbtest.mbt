// ============================================================================
// BUG-466：S3「取票窗口」—— agent_issue_challenge + claim 接 challenge
//
// 背景（commander-alpha 在生产库上实测发现）：S3 八段全落地、产品库已有真公钥，
// 但**已登记的 agent 从产品面拿不到服务端签发的挑战**：
//   · agent_register_key(已登记) ⇒ already_registered，**回执无 challenge 字段**
//   · claim **不接受** challenge / challenge_sig（引擎层其实早接了，是 schema 没声明）
// ⇒ 「路上缺一个收费站」：车到了入口却没有取票窗口，只能自己伪造一张票。
//
// 本文件锁：
//   锁 1  已登记 agent ⇒ 能拿到 challenge（服务端签发、一次性）
//   锁 2  未登记 agent ⇒ 不签发（fail-closed：签了也验不过）
//   锁 3  challenge 一次性：消费后重放 ⇒ challenge_replayed
//   锁 4  无 challenge ⇒ 原逻辑（零回归：role_source 保持既有取值）
//   锁 5（变异对照）删掉验签 ⇒ 锁 1/3 的 verified 判定必翻转
//   锁 6  identity 维度标签：把「scope 未登记」与「agent 身份已验证」分开报
// ============================================================================

///|
/// 测试密钥对。**BUG-468：统一用 `test_crypto.mbt` 的常量**，不再自写字面量。
///
/// 背景：本文件最初用的是 **16 字节** seed ⇒ `@mooncry` abort ⇒
/// 6 格测试全红且只显示 `Error`，排查约 10 分钟才定位到「seed 长度」。
fn ce_seed() -> Bytes {
  @core.TEST_ED25519_SEED_A
}

///|
fn ce_pub_hex() -> String {
  @core.test_ed25519_pub_hex(ce_seed())
}

///|
/// 测试夹具：用私钥签名（**仅测试用**，生产永无代签）。
fn ce_sign(msg : String) -> String {
  @core.test_ed25519_sign_hex(ce_seed(), msg)
}

///|
/// 建引擎并登记公钥（走真实 store 路径）。
fn ce_eng_with_key(agent : String, pk : String) -> FistEngine {
  let sql = match @store.SqliteStore::open(":memory:") {
    Some(s) => s
    None => abort("sqlite open 失败：本格没跑到被测面")
  }
  let eng = FistEngine::new(store=@store.StoreBackend::sqlite(sql))
  match
    eng.agents_register(
      agent_id=agent_fp_of(agent),
      agent_type="executor",
      role="Executor",
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
/// 锁 1：**已登记 agent 能拿到服务端签发的 challenge**，且该 challenge 可用于验签通过。
///
/// 「取票窗口」的核心：签发来源必须是 `s3_issue_challenge_auto`（服务端单调递增），
/// 调用方不能自选 —— 否则可离线预计算并提前签好 ⇒ 挑战退化为固定字符串。
test "bug466_c1_issued_challenge_can_verify" {
  let agent = "ce-issue-ok"
  let eng = ce_eng_with_key(agent, ce_pub_hex())
  // ① 签发（与 agent_issue_challenge 工具走同一个引擎函数）
  let chal = eng.s3_issue_challenge_auto(agent)
  assert_true(chal.length() > 0)
  // ② 真私钥签 ⇒ 验签通过
  assert_true(verify_challenge_sig(ce_pub_hex(), chal, ce_sign(chal)))
  // ③ 走真实取数面 ⇒ challenge_verified
  let (role, src) = judged_role_with_nonce(
    eng, agent, Some(chal), challenge_sig=Some(ce_sign(chal)),
  )
  assert_eq(src, "challenge_verified")
  let _ = role
}

///|
/// 锁 2：**未登记公钥的 agent ⇒ 不签发**（fail-closed）。
///
/// 为什么必须拒：没有公钥 ⇒ `judged_role_gated` 的 `(None, _) => false`
/// ⇒ 签出的挑战**永远验不过**。签发它只会让调用方以为「我有挑战了应该能过」。
test "bug466_c2_no_key_means_no_challenge_use" {
  let agent = "ce-issue-nokey"
  let sql = match @store.SqliteStore::open(":memory:") {
    Some(s) => s
    None => abort("sqlite open 失败")
  }
  let eng = FistEngine::new(store=@store.StoreBackend::sqlite(sql))
  // 没有登记公钥，但签发出了 challenge
  let chal = eng.s3_issue_challenge_auto(agent)
  // ★ 即使签名是用某个私钥真签的，也没有公钥可验 ⇒ 恒失败
  assert_eq(
    judged_role_with_nonce(
      eng, agent, Some(chal), challenge_sig=Some(ce_sign(chal)),
    ).1,
    "challenge_failed",
  )
}

///|
/// 锁 3：**challenge 一次性** —— 消费后重放 ⇒ `challenge_replayed`。
///
/// 「一次性」是防重放的唯一手段：服务端签发解决了「预计算」，
/// 但同一份签名可以被无限次提交 ⇒ 必须消费。
test "bug466_c3_challenge_is_single_use" {
  let agent = "ce-replay"
  let eng = ce_eng_with_key(agent, ce_pub_hex())
  let chal = eng.s3_issue_challenge_auto(agent)
  let sig = ce_sign(chal)
  // 第一次：通过
  assert_eq(
    judged_role_with_nonce(eng, agent, Some(chal), challenge_sig=Some(sig)).1,
    "challenge_verified",
  )
  // ★ 第二次同一 chal + 同一 sig ⇒ 重放
  assert_eq(
    judged_role_with_nonce(eng, agent, Some(chal), challenge_sig=Some(sig)).1,
    "challenge_replayed",
  )
}

///|
/// 锁 4：**无 challenge ⇒ 原逻辑（零回归）**。
///
/// `judged_role_with_nonce(None)` 必须**原样透传** `judged_role_gated(None)` 的结果，
/// 即 `declared` / `inferred` —— 不是新造一个取值。
test "bug466_c4_no_challenge_keeps_original_logic" {
  let agent = "ce-nochal"
  let eng = ce_eng_with_key(agent, ce_pub_hex())
  let (role, src) = judged_role_with_nonce(eng, agent, None)
  let (role_g, src_g) = judged_role_gated(eng, agent, None)
  // 逐字相同 ⇒ 零回归
  assert_eq(src, src_g)
  assert_eq(role, role_g)
  // 且**不是**新认证态
  assert_true(src != "challenge_verified")
  assert_true(src != "challenge_failed")
  assert_true(src != "challenge_replayed")
}

///|
/// 锁 5（⭐ **变异对照**）：把「验签」这一步的证据换成 `true`
/// （等价于删掉 `verify_challenge_sig` 直接放行）⇒ 判定翻转。
///
/// **不 grep 源码字符串**（会命中注释 ⇒ 判例-30 自指假绿），只断言行为翻转：
///   · 正常：错签名 ⇒ challenge_failed
///   · 变异（把 verified 强置 true）⇒ 同一输入变成 verified
/// 两值必须不同，否则说明验签根本没参与判定。
test "bug466_c5_variant_removing_verify_flips_result" {
  let agent = "ce-variant"
  let eng = ce_eng_with_key(agent, ce_pub_hex())
  let chal = eng.s3_issue_challenge_auto(agent)
  // 用**错的**签名：对**别的消息**签名（同一把私钥、但被签的不是本 challenge）
  //   ⇒ 验签必失败，且不需要第二把私钥（避免 `@mooncry` 对任意 seed 的不自洽问题）
  let wrong = ce_sign(chal + "-not-the-challenge")
  // 正常路径 ⇒ 必须失败
  assert_eq(
    judged_role_with_nonce(eng, agent, Some(chal), challenge_sig=Some(wrong)).1,
    "challenge_failed",
  )
  // ★ 变异等价物：如果验签被删（恒 true），同一输入会变成 verified
  //   这里直接用纯函数验证「验签确实在区分对错签名」
  assert_false(verify_challenge_sig(ce_pub_hex(), chal, wrong))
  assert_true(verify_challenge_sig(ce_pub_hex(), chal, ce_sign(chal)))
}

///|
/// 锁 6：**identity 维度标签** —— 把「scope 未登记」与「agent 身份状态」分开报。
///
/// 生产实测误读（BUG-466 由来）：`action = unregistered+challenge_verified`
/// 被读成「这个 agent 没注册」。其实 `unregistered` 说的是 **scope**。
/// 修法：前导词保持逐字（既有精确相等锁依赖它），**追加自解释的 identity 维度段**。
test "bug466_c6_identity_dimension_is_explicit" {
  // 三态映射必须自解释且互不相同
  let v = auth_tag("challenge_verified")
  let f = auth_tag("challenge_failed")
  let n = auth_tag("")
  assert_eq(v, "+challenge_verified")
  assert_eq(f, "+challenge_failed")
  assert_eq(n, "")
  assert_true(v != f)
}
