// ============================================================================
// BUG-430 / S3 **第一段**：挑战-签名-验签的骨架锁
//
// 本段要证明的是「挑战真的接进了角色取数面」，**不是**「写了个 verify 没人调」
// （判例-29）。所以核心格是 `s3_min_01` —— 它断言 `judged_role_with_challenge`
// 的**返回值**，而不是断言「某个函数存在」。
//
// ⚠️ 诚实边界：S3 第一段**不改变安全属性**。真正生效要等：
//   ① 握手把 nonce 真发出去 ② 客户端真签名 ③ 服务端存得住公钥
// ============================================================================

///|
/// 造一个内存引擎（S3 第一段不需要真库）。
fn s3_eng() -> FistEngine {
  FistEngine::new(store=@store.StoreBackend::memory())
}

///|
/// 【s3_min_01】**没有挑战 ⇒ 角色降级为 Executor + 来源标注 unauthenticated**。
///
/// 这是 Alpha 指定的最小里程碑：它证明「挑战接进了取数面」——
/// 若把 `judged_role_with_challenge` 里的 `None` 分支删掉/写成直接调 `judged_role`，
/// `role_source` 就不会是 `unauthenticated` ⇒ 本格必红。
test "s3_min_01_no_nonce_no_leader" {
  let e = s3_eng()
  let (role, source) = judged_role_with_challenge(e, "fist-mbt", None)
  assert_eq(role, "Executor")
  assert_eq(source, "unauthenticated")
}

///|
/// 【s3_min_02】有 nonce 但**公钥未登记** ⇒ `challenge_failed`（fail-closed）。
///
/// 防「有挑战就当通过」：没登记公钥的 agent 不可能验签成功。
test "s3_min_02_nonce_without_registered_pubkey_fails" {
  let e = s3_eng()
  let (role, source) = judged_role_with_challenge(
    e, "ghost-agent", Some(issue_challenge_nonce("ghost-agent", 1)),
  )
  assert_eq(role, "Executor")
  assert_eq(source, "challenge_failed")
}

///|
/// 【s3_min_03】`issue_challenge_nonce` 是**纯函数且确定**：同输入同输出、不同输入不同输出。
///
/// 这条钉「nonce 可复现」——第二段要把它改成真随机时，会在这里被提醒。
test "s3_min_03_nonce_is_deterministic_and_distinct" {
  let a1 = issue_challenge_nonce("lane-be", 1)
  let a2 = issue_challenge_nonce("lane-be", 1)
  let b = issue_challenge_nonce("lane-be", 2)
  let c = issue_challenge_nonce("other", 1)
  assert_eq(a1, a2)          // 同输入 ⇒ 同输出
  assert_true(a1 != b)       // 计数器不同 ⇒ 不同
  assert_true(a1 != c)       // agent 不同 ⇒ 不同
  // nonce 里绑定了 agent（换主体即失效）
  assert_true(a1.contains("lane-be"))
}

///|
/// 【s3_min_04】**验签函数真的在工作**：真签真验通过，篡改则拒。
///
/// 这是「不是桩」的证明 —— 用 `@mooncry` 真生成密钥对、真签名。
/// 变异（把 `verify_challenge_sig` 改成恒 true）⇒ 篡改那一路必红。
test "s3_min_04_verify_challenge_sig_really_verifies" {
  // 固定 seed（确定性、可复现）
  let seed : Bytes = b"\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f"
  let pk = @mooncry.ed25519_public_key(seed)
  let nonce = issue_challenge_nonce("lane-be", 42)
  let msg = @utf8.encode(nonce)
  let sig = @mooncry.ed25519_sign(seed, msg)
  let pk_hex = @mooncry.bytes_to_hex(pk)
  let sig_hex = @mooncry.bytes_to_hex(sig)
  // ① 真签真验 ⇒ true
  assert_true(verify_challenge_sig(pk_hex, nonce, sig_hex))
  // ② 篡改 nonce ⇒ false
  assert_false(verify_challenge_sig(pk_hex, nonce + "-tampered", sig_hex))
  // ③ 换公钥 ⇒ false
  let seed2 : Bytes = b"\xff\xfe\xfd\xfc\xfb\xfa\xf9\xf8\xf7\xf6\xf5\xf4\xf3\xf2\xf1\xf0\xef\xee\xed\xec\xeb\xea\xe9\xe8\xe7\xe6\xe5\xe4\xe3\xe2\xe1\xe0"
  let pk2_hex = @mooncry.bytes_to_hex(@mooncry.ed25519_public_key(seed2))
  assert_false(verify_challenge_sig(pk2_hex, nonce, sig_hex))
  // ④ 坏 hex / 错长度 ⇒ false（fail-closed，不 panic）
  assert_false(verify_challenge_sig("zz", nonce, sig_hex))
  assert_false(verify_challenge_sig(pk_hex, nonce, "ab"))
}
