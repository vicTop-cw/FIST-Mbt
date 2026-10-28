// ============================================================================
// BUG-430 / S3 **第六段**：首登验签的**端到端**锁（引擎层）
//
// 证明「攻击者真的不能替别人首登」：
//   ① 攻击者拿自己的私钥、对**服务端签发的** challenge 签名
//      —— 但他的公钥 ≠ 要登记的公钥 ⇒ 验签失败
//   ② 合法持有者用自己私钥签 ⇒ 验签通过
//
// ⚠️ 这里的签名只用于**测试夹具**（固定 seed 现算）。
//   生产服务端**没有也不会有**代签能力（server_bug430_s3_keytool_wbtest 有锁钉住）。
// ============================================================================

///|
fn bs_seed(which : Int32) -> Bytes {
  if which == 0 {
    b"\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a"
  } else {
    b"\xa5\xa5\xa5\xa5\xa5\xa5\xa5\xa5\xa5\xa5\xa5\xa5\xa5\xa5\xa5\xa5\xa5\xa5\xa5\xa5\xa5\xa5\xa5\xa5\xa5\xa5\xa5\xa5\xa5\xa5\xa5\xa5"
  }
}

///|
fn bs_pub_hex(which : Int32) -> String {
  @mooncry.bytes_to_hex(@mooncry.ed25519_public_key(bs_seed(which)))
}

///|
fn bs_sign(which : Int32, msg : String) -> String {
  @mooncry.bytes_to_hex(
    @mooncry.ed25519_sign(bs_seed(which), @utf8.encode(msg)),
  )
}

///|
/// 【首登·锁 1】★ **攻击者不能替别人首登**（端到端，最核心的一格）。
///
/// 场景：受害者要登记的是一把公钥（`victim_pk`），攻击者只想抢注这个身份。
///   · 攻击者能自选「公钥」参数（他填自己的 `attacker_pk`）—— 这挡不住；
///   · 但**验签**要求：`proof_sig` 必须由 `pubkey_hex` 对应的私钥签出。
///   · 攻击者若填**自己的**公钥+自己的签名 ⇒ 验签通过，但登记的是**他的**公钥
///     ⇒ 之后受害者来登记时，因「已有公钥且不同」被拒（第五段）⇒ 他锁不进去；
///   · 攻击者若填**受害者的**公钥+自己的签名 ⇒ **验签失败**（拿不到受害者私钥）。
///
/// 本格钉后者：**换钥不成立**。
test "bs_v1_attacker_cannot_forge_proof_for_victim_key" {
  let victim_pk = bs_pub_hex(0)
  let challenge = "fist-s3-challenge:v1:some-agent:12345"
  // 攻击者用自己的私钥签 —— 但它验不过 victim_pk
  let attacker_sig = bs_sign(1, challenge)
  assert_false(verify_challenge_sig(victim_pk, challenge, attacker_sig))
  // 合法持有者用自己的私钥签 ⇒ 通过
  let victim_sig = bs_sign(0, challenge)
  assert_true(verify_challenge_sig(victim_pk, challenge, victim_sig))
}

///|
/// 【首登·锁 2】**没签名 / 坏签名 ⇒ 验不过**（fail-closed）。
test "bs_v2_missing_or_bad_proof_fails_closed" {
  let pk = bs_pub_hex(0)
  let challenge = "fist-s3-challenge:v1:agent:1"
  // 空串
  assert_false(verify_challenge_sig(pk, challenge, ""))
  // 坏 hex
  assert_false(verify_challenge_sig(pk, challenge, "zzzz"))
  // 正确签名但**换了 challenge**（重放/篡改）
  let sig = bs_sign(0, challenge)
  assert_false(verify_challenge_sig(pk, "fist-s3-challenge:v1:agent:999", sig))
}

///|
/// 【首登·锁 3】★ **challenge 由服务端签发且每次不同**（防离线预计算）。
///
/// 若 nonce 可预测/可复用，调用方就能离线预计算并提前签好 ⇒ 验签失效。
test "bs_v3_challenge_is_server_issued_and_unique" {
  let eng = FistEngine::new(store=@store.StoreBackend::memory())
  let a = eng.s3_issue_challenge_auto("agent-x")
  let b = eng.s3_issue_challenge_auto("agent-x")
  if a == b {
    abort(
      "两次签发得到同一个 challenge —— 调用方可离线预计算并复用，验签失效",
    )
  }
  // nonce 里绑定 agent（换主体即失效）
  assert_true(a.contains("agent-x"))
  // 且都被登记为「待消费」
  assert_true(s3_consume_nonce("agent-x", a))
  assert_true(s3_consume_nonce("agent-x", b))
  // 消费过一次就不能再用（防重放）
  assert_false(s3_consume_nonce("agent-x", a))
}
