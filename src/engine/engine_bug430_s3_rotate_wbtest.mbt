// ============================================================================
// BUG-430 / S3 **第八段**：密钥轮换 + 吊销
//
// 背景：第七段对「已有公钥且与本次不同」一律拒绝 —— 那堵住了劫持，
// 但也意味着**私钥丢了就永久锁死**（抢注成功 = 正主再也要不回来）。
// 本段补上唯一合法的换钥通道：**必须由旧私钥对挑战签名**。
//
// 并且暴露一个此前被掩盖的结构性事实：
//   `agents_register` 的 `ON CONFLICT DO UPDATE SET` **不含 pubkey_fp**
//   ⇒ 没有 `agents_set_pubkey` 之前，公钥**一旦写入即永久不可变**
//   ⇒ 登记错了（含被抢注）该身份永久废掉。
//
// 本文件锁：
//   锁 1  store 层 `agents_set_pubkey` 写入后能读回（防「改了但没生效」）
//   锁 2  旧私钥签名正确 ⇒ 轮换成功（且换后新钥能过、旧钥不能过）
//   锁 3  旧私钥签名缺失 ⇒ 被拒
//   锁 4  旧私钥签名错误 ⇒ 被拒
//   锁 5  吊销 ⇒ pubkey_fp 被清空，此后挑战恒失败
//   锁 6（变异对照）把 old_sig_ok 换成 true ⇒ 锁 4 判定翻转（证明它真在起作用）
// ============================================================================

///|
/// 测试密钥对 A（固定 seed ⇒ 确定性可复现）。
fn bz_seed_a() -> Bytes {
  b"\x3a\x7f\x21\xb4\x5c\x0e\x99\x12\xaa\x3d\x61\x8f\x24\xbe\x07\xc5\xd8\x19\x42\xe0\x7b\x53\x96\x2c\x1a\x88\xf4\x0d\x6e\x31\xb7\x95"
}

///|
/// 测试密钥对 B（另一把，用来模拟「换钥」）。
fn bz_seed_b() -> Bytes {
  b"\x11\x22\x33\x44\x55\x66\x77\x88\x99\xaa\xbb\xcc\xdd\xee\xff\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10"
}

///|
fn bz_pub_a() -> String {
  @mooncry.bytes_to_hex(@mooncry.ed25519_public_key(bz_seed_a()))
}

///|
fn bz_pub_b() -> String {
  @mooncry.bytes_to_hex(@mooncry.ed25519_public_key(bz_seed_b()))
}

///|
/// 测试夹具：用 seed 对应的私钥签名（**仅测试用**，生产不许有代签）。
fn bz_sign(seed : Bytes, msg : String) -> String {
  @mooncry.bytes_to_hex(@mooncry.ed25519_sign(seed, @utf8.encode(msg)))
}

///|
/// 建 sqlite 引擎并把某 agent 的公钥直接写进 agents 表。
fn bz_eng_with_key(agent : String, pubkey : String) -> FistEngine {
  let sql = match @store.SqliteStore::open(":memory:") {
    Some(s) => s
    None => abort("sqlite open 失败：本格没跑到被测面")
  }
  let eng = FistEngine::new(store=@store.StoreBackend::sqlite(sql))
  match
    eng.agents_register(
      agent_id=agent_fp_of(agent),
      agent_type="test",
      role="Executor",
      soldier="工兵",
      pubkey_fp=pubkey,
      pid=1,
      now="2026-10-28T00:00:00Z",
    ) {
    Err(e) => abort("agents_register 应成功：" + e)
    Ok(_) => ()
  }
  eng
}

///|
fn bz_pubkey_of(eng : FistEngine, agent : String) -> String {
  match eng.store.sqlite_store() {
    None => ""
    Some(s) =>
      match s.agents_get(agent_fp_of(agent)) {
        None => ""
        Some(a) => a.pubkey_fp
      }
  }
}

///|
fn bz_store(eng : FistEngine) -> @store.SqliteStore {
  match eng.store.sqlite_store() {
    None => abort("本格需要 sqlite 后端")
    Some(s) => s
  }
}

///|
/// 锁 1（先跑）：**store 层 `agents_set_pubkey` 写入后能读回**。
///
/// 这是本段所有上层能力的地基：若它「改了但没生效」，轮换与吊销都会变成
/// 「回执说成功、库里还是旧的」—— 正是本单要防的假成功。
/// 判例-29：本格直接走 store 实现路径，不绕过它。
test "bug430_r1_store_set_pubkey_roundtrip" {
  let eng = bz_eng_with_key("bz-rt", bz_pub_a())
  assert_eq(bz_pubkey_of(eng, "bz-rt"), bz_pub_a())
  let st = bz_store(eng)
  // 改写 ⇒ 读回必须是新键
  match
    st.agents_set_pubkey(agent_id=agent_fp_of("bz-rt"), pubkey_fp=bz_pub_b()) {
    Err(e) => abort("agents_set_pubkey 应成功：" + e)
    Ok(_) => ()
  }
  assert_eq(bz_pubkey_of(eng, "bz-rt"), bz_pub_b())
  // 清空也必须真的生效（吊销的基础）
  match st.agents_set_pubkey(agent_id=agent_fp_of("bz-rt"), pubkey_fp="") {
    Err(e) => abort("清空应成功：" + e)
    Ok(_) => ()
  }
  assert_eq(bz_pubkey_of(eng, "bz-rt"), "")
}

///|
/// 锁 2：**旧私钥签名正确 ⇒ 轮换成功**（且换后新钥能过、旧钥不能过）。
test "bug430_r2_rotate_with_old_key_proof_succeeds" {
  let agent = "bz-rot-ok"
  let eng = bz_eng_with_key(agent, bz_pub_a())
  let chal = issue_challenge_nonce(agent, 1)
  let sig = bz_sign(bz_seed_a(), chal)
  // 判定面：旧钥签发得出 ⇒ rotate_allowed
  let old_ok = verify_challenge_sig(bz_pub_a(), chal, sig)
  assert_true(old_ok)
  assert_eq(
    key_rotate_verdict(bz_pub_a(), bz_pub_b(), sig, old_ok),
    key_rotate_allowed,
  )
  // 落地面：真的写进去
  let st = bz_store(eng)
  match
    st.agents_set_pubkey(agent_id=agent_fp_of(agent), pubkey_fp=bz_pub_b()) {
    Err(e) => abort("轮换写库失败：" + e)
    Ok(_) => ()
  }
  assert_eq(bz_pubkey_of(eng, agent), bz_pub_b())
  // ★ 换钥后：新私钥能过挑战，旧私钥不能
  let nonce = issue_challenge_nonce(agent, 2)
  let (_rn, src_new) = judged_role_with_challenge(
    eng,
    agent,
    Some(nonce),
    challenge_sig=Some(bz_sign(bz_seed_b(), nonce)),
  )
  assert_eq(src_new, "challenge_verified")
  let (_ro, src_old) = judged_role_with_challenge(
    eng,
    agent,
    Some(nonce),
    challenge_sig=Some(bz_sign(bz_seed_a(), nonce)),
  )
  assert_eq(src_old, "challenge_failed")
}

///|
/// 锁 3：**没提交 rotate_sig ⇒ 拒绝**（不能凭"我想换"就换）。
test "bug430_r3_rotate_without_proof_rejected" {
  assert_eq(
    key_rotate_verdict(bz_pub_a(), bz_pub_b(), "", false),
    key_rotate_reject_no_proof,
  )
  // 同键 / 无旧键 ⇒ 不需要轮换（走首登/幂等，别让它们误进拒绝分支）
  assert_eq(
    key_rotate_verdict("", bz_pub_b(), "", false),
    key_rotate_not_needed,
  )
  assert_eq(
    key_rotate_verdict(bz_pub_a(), bz_pub_a(), "", false),
    key_rotate_not_needed,
  )
}

///|
/// 锁 4：**提交了但签名验不过 ⇒ 拒绝**（不能凭"随便签个东西"就换）。
test "bug430_r4_rotate_with_bad_proof_rejected" {
  let chal = issue_challenge_nonce("bz-rot-bad", 1)
  // 用**错的**私钥（B）去签，却声称换到 B ⇒ 旧钥 A 验不过
  let wrong_sig = bz_sign(bz_seed_b(), chal)
  let old_ok = verify_challenge_sig(bz_pub_a(), chal, wrong_sig)
  assert_false(old_ok)
  assert_eq(
    key_rotate_verdict(bz_pub_a(), bz_pub_b(), wrong_sig, old_ok),
    key_rotate_reject_bad_proof,
  )
}

///|
/// 锁 5：**吊销 ⇒ pubkey_fp 被清空**，且此后挑战一律失败（fail-closed）。
test "bug430_r5_revoke_clears_key_and_fails_closed" {
  let agent = "bz-revoke"
  let eng = bz_eng_with_key(agent, bz_pub_a())
  assert_eq(bz_pubkey_of(eng, agent), bz_pub_a())
  // 吊销前：能过
  let n1 = issue_challenge_nonce(agent, 1)
  let (_r1, s1) = judged_role_with_challenge(
    eng,
    agent,
    Some(n1),
    challenge_sig=Some(bz_sign(bz_seed_a(), n1)),
  )
  assert_eq(s1, "challenge_verified")
  // 清空（吊销）
  let st = bz_store(eng)
  match st.agents_set_pubkey(agent_id=agent_fp_of(agent), pubkey_fp="") {
    Err(e) => abort("吊销失败：" + e)
    Ok(_) => ()
  }
  assert_eq(bz_pubkey_of(eng, agent), "")
  // ★ 吊销后：即使签名是真的，也没有公钥可验 ⇒ 恒 challenge_failed
  let n2 = issue_challenge_nonce(agent, 2)
  let (r2, s2) = judged_role_with_challenge(
    eng,
    agent,
    Some(n2),
    challenge_sig=Some(bz_sign(bz_seed_a(), n2)),
  )
  assert_eq(s2, "challenge_failed")
  assert_eq(r2, "Executor")
}

///|
/// 锁 6（⭐ **变异对照**）：把「旧钥签名」这一步的证据换成 `true`
/// （等价于删掉 `verify_challenge_sig(prev_key, ...)` 直接放行）⇒ 判定翻转成 allowed。
///
/// **不 grep 源码字符串**（会命中注释 ⇒ 判例-30 自指假绿），只断言行为翻转：
/// 正常路径下错签名 ⇒ `reject_bad_proof`；把 old_sig_ok 强置 true ⇒ `rotate_allowed`。
/// 两个结论必须不同，否则说明 old_sig_ok 根本没参与判定。
test "bug430_r6_variant_removing_old_key_check_breaks_lock" {
  let chal = issue_challenge_nonce("bz-var", 1)
  let bogus = bz_sign(bz_seed_b(), chal)
  let ok_normal = verify_challenge_sig(bz_pub_a(), chal, bogus)
  assert_false(ok_normal)
  // 正常 ⇒ 拒
  assert_eq(
    key_rotate_verdict(bz_pub_a(), bz_pub_b(), bogus, ok_normal),
    key_rotate_reject_bad_proof,
  )
  // ★ 变异（删掉验签的等价形态）⇒ 放行
  assert_eq(
    key_rotate_verdict(bz_pub_a(), bz_pub_b(), bogus, true),
    key_rotate_allowed,
  )
}

///|
/// 锁 7：**吊销判定面**——没键的 agent 报「无需吊销」而不是「吊销成功」。
///
/// 防「假安全」：回执说 revoked=true 而实际什么都没变，会让调用方误以为锁掉了。
test "bug430_r7_revoke_verdict_distinguishes_noop" {
  assert_eq(key_revoke_verdict(""), key_revoke_not_needed)
  assert_eq(key_revoke_verdict(bz_pub_a()), key_revoke_ok)
}

///|
/// 锁 8（**R3**）：轮换的 challenge **必须服务端签发且只能用一次**。
///
/// 为什么单独锁：首登早已用 `s3_issue_challenge_auto`（服务端单调递增计数器），
/// 理由是「调用方自选 counter ⇒ 可离线预计算 nonce 并提前签好 ⇒ 挑战退化为固定字符串
/// ⇒ 验签形同虚设」。**同一原则必须用在自己身上**：
/// 轮换若接受调用方自选 challenge，攻击者可预先算好 nonce、提前签好，
/// 之后任何时刻提交都成立 ⇒ 「旧私钥证明」被架空。
///
/// 三格断言：
///   · 服务端签发的 nonce ⇒ `s3_consume_nonce` 第一次 true（认）
///   · 同一 nonce 第二次 ⇒ false（**防重放**）
///   · 调用方自造（未签发的）nonce ⇒ false（**不认**）
test "bug430_r8_rotate_challenge_must_be_server_issued" {
  let agent = "bz-r3-replay"
  // 服务端签发（真实路径）
  let issued = s3_issue_challenge_auto_for_test(agent)
  assert_true(s3_consume_nonce(agent, issued))
  // ★ 同一 nonce 第二次 ⇒ 必须 false（防重放）
  assert_false(s3_consume_nonce(agent, issued))
  // ★ 调用方自造（没经服务端签发）⇒ 必须 false（不认）
  let forged = issue_challenge_nonce(agent, 999999)
  assert_false(s3_consume_nonce(agent, forged))
}

///|
/// 测试辅助：签发一个服务端 nonce（走与生产同一个 `issue_challenge_nonce` + 登记）。
///
/// ⚠️ 这里**不直接调 `FistEngine::s3_issue_challenge_auto`**（需要引擎实例），
/// 而是复刻它的两步：`issue_challenge_nonce(agent, n)` + 登记进 pending 表。
/// 但 pending 表是引擎包的私有 map ⇒ 用引擎实例更可靠，故本函数**由需要它的格直接内联**。
/// 见 `bug430_r9`（带引擎实例的版本）——本函数保留给不需要引擎的纯函数格。
fn s3_issue_challenge_auto_for_test(agent : String) -> String {
  // 用一个不冲突的计数区间，避免与其他格串号
  s3_issue_challenge_direct(agent, 77001)
}

///|
/// 直接登记一条待消费 nonce（等价于 `s3_issue_challenge` 的两步）。
fn s3_issue_challenge_direct(agent : String, counter : Int32) -> String {
  let nonce = issue_challenge_nonce(agent, counter)
  let k = agent_fp_of(agent)
  let cur = match s3_pending_nonces.get(k) {
    None => []
    Some(a) => a
  }
  cur.push(nonce)
  s3_pending_nonces.set(k, cur)
  nonce
}

///|
/// 锁 9（**R3 端到端**）：带引擎实例走一遍「服务端签发 → 旧私钥签 → 消费」。
test "bug430_r9_rotate_consumes_server_issued_challenge" {
  let agent = "bz-r3-e2e"
  let eng = bz_eng_with_key(agent, bz_pub_a())
  // ① 服务端签发（真实引擎路径）
  let chal = eng.s3_issue_challenge_auto(agent)
  // ② 旧私钥签
  let sig = bz_sign(bz_seed_a(), chal)
  assert_true(verify_challenge_sig(bz_pub_a(), chal, sig))
  // ③ 消费 + 验签（轮换 handler 的判定顺序）
  assert_true(s3_consume_nonce(agent, chal))
  // ★ ④ 重放同一 challenge ⇒ 消费失败 ⇒ 即使签名是对的也不认
  assert_false(s3_consume_nonce(agent, chal))
  // ⑤ 换钥落地
  let st = bz_store(eng)
  match
    st.agents_set_pubkey(agent_id=agent_fp_of(agent), pubkey_fp=bz_pub_b()) {
    Err(e) => abort("轮换写库失败：" + e)
    Ok(_) => ()
  }
  assert_eq(bz_pubkey_of(eng, agent), bz_pub_b())
}
