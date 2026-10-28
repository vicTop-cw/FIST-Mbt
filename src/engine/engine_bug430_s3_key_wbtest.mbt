// ============================================================================
// BUG-430 / S3 **第四段**：密钥管理 —— 有公钥的 agent 才能真正通过挑战
//
// 前三段证明的是「骨架通 / 接进四门 / 从 args 能传」；
// 本段证明**端到端真的能用**：
//   登记公钥 → 签发 nonce → 用**私钥**签名 → 验签通过 → 拿到真角色
//
// ⚠️ 本文件里的签名只用于**测试夹具**（用已知 seed 现算），
//   **生产服务端绝对不许提供「代签」能力** —— 那等于服务端自己给自己发通行证。
// ============================================================================

///|
/// 测试用密钥对。**BUG-468：统一用 `test_crypto.mbt` 的常量**，不再自写字面量。
fn s3_key_seed() -> Bytes {
  @core.TEST_ED25519_SEED_A
}

///|
fn s3_key_pub_hex() -> String {
  @core.test_ed25519_pub_hex(s3_key_seed())
}

///|
/// 测试夹具：用私钥对 nonce 签名（**仅测试用**，生产不许有）。
fn s3_key_sign(nonce : String) -> String {
  @core.test_ed25519_sign_hex(s3_key_seed(), nonce)
}

///|
/// 【密钥·锁 1】★ **有公钥的 agent 真的能通过挑战**（端到端）。
///
/// 链路：`agent_register_key` 落库公钥 → 引擎 `declared_pubkey_for` 读回
///      → `verify_challenge_sig` 用真公钥验真签名 → 通过。
///
/// 这条**不需要起 MCP server**：直接调引擎层同一组函数，
/// 但公钥是**真的写进 sqlite 的 agents 表**（不是打桩）。
test "s3_key_01_agent_with_key_can_pass_challenge" {
  let sql = match @store.SqliteStore::open(":memory:") {
    Some(s) => s
    None => abort("sqlite open 失败：本格没跑到被测面")
  }
  let eng = FistEngine::new(store=@store.StoreBackend::sqlite(sql))
  let agent = "lane-bk-keyagent"
  let pk = s3_key_pub_hex()
  // ① 登记公钥（走引擎层同一条 `agents_register` 路径 —— 工具只是它的薄封装）
  match
    eng.agents_register(
      agent_id=agent_fp_of(agent),
      agent_type="test",
      role="Leader",
      soldier="工兵",
      pubkey_fp=pk,
      pid=1,
      now="2026-10-27T00:00:00Z",
    ) {
    Err(e) => abort("agents_register 应成功：" + e)
    Ok(_) => ()
  }
  // ② 签发 nonce 并用私钥签名
  let nonce = issue_challenge_nonce(agent, 1)
  let sig = s3_key_sign(nonce)
  // ③ 走带挑战的角色取数
  let (role, src) = judged_role_with_challenge(
    eng,
    agent,
    Some(nonce),
    challenge_sig=Some(sig),
  )
  // ★ 必须 challenge_verified（修前没有公钥 ⇒ 恒 challenge_failed）
  if src != "challenge_verified" {
    abort(
      "有公钥 + 真签名却没通过挑战：role=" +
      role +
      " src=" +
      src +
      "（若为 challenge_failed ⇒ 公钥没真正落库或没被读到）",
    )
  }
  assert_eq(role, "Leader") // 拿到登记的 declared 角色
}

///|
/// 【密钥·锁 2】**没公钥的 agent ⇒ 挑战失败**（fail-closed）。
///
/// 防「没登记也放行」。这是 S3 的安全底线。
test "s3_key_02_agent_without_key_fails_closed" {
  let sql = match @store.SqliteStore::open(":memory:") {
    Some(s) => s
    None => abort("sqlite open 失败")
  }
  let eng = FistEngine::new(store=@store.StoreBackend::sqlite(sql))
  let agent = "lane-bk-nokey"
  let nonce = issue_challenge_nonce(agent, 1)
  let sig = s3_key_sign(nonce) // 签名是真的，但**公钥没登记**
  let (role, src) = judged_role_with_challenge(
    eng,
    agent,
    Some(nonce),
    challenge_sig=Some(sig),
  )
  assert_eq(role, "Executor")
  assert_eq(src, "challenge_failed")
}

///|
/// 【密钥·锁 3】**签名不对（换别人的私钥）⇒ 挑战失败**。
///
/// 防「随便签个东西就算过」。
test "s3_key_03_wrong_signature_fails_closed" {
  let sql = match @store.SqliteStore::open(":memory:") {
    Some(s) => s
    None => abort("sqlite open 失败")
  }
  let eng = FistEngine::new(store=@store.StoreBackend::sqlite(sql))
  let agent = "lane-bk-wrongsig"
  let pk = s3_key_pub_hex()
  ignore(
    eng.agents_register(
      agent_id=agent_fp_of(agent),
      agent_type="test",
      role="Leader",
      soldier="工兵",
      pubkey_fp=pk,
      pid=1,
      now="2026-10-27T00:00:00Z",
    ),
  )
  let nonce = issue_challenge_nonce(agent, 1)
  // 用**另一把**私钥签（公钥已登记的是 s3_key_seed 那对）
  let other_seed : Bytes = b"\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99"
  let bad_sig = @mooncry.bytes_to_hex(
    @mooncry.ed25519_sign(other_seed, @utf8.encode(nonce)),
  )
  let (role, src) = judged_role_with_challenge(
    eng,
    agent,
    Some(nonce),
    challenge_sig=Some(bad_sig),
  )
  assert_eq(role, "Executor")
  assert_eq(src, "challenge_failed")
}

///|
/// 【密钥·锁 4】`agents_register` 的 `pubkey_fp` **真的落库并可读回**。
///
/// 防「注册时传了但表里没存」——那正是 BUG-403 的「死承诺」形状。
test "s3_key_04_pubkey_is_persisted_and_readable" {
  let sql = match @store.SqliteStore::open(":memory:") {
    Some(s) => s
    None => abort("sqlite open 失败")
  }
  let pk = s3_key_pub_hex()
  let fp = agent_fp_of("lane-bk-persist")
  ignore(
    sql.agents_register(
      agent_id=fp,
      agent_type="test",
      role="Executor",
      soldier="工兵",
      pubkey_fp=pk,
      pid=1,
      now="2026-10-27T00:00:00Z",
    ),
  )
  match sql.agents_get(fp) {
    None => abort("agents_get 读不到刚注册的 agent")
    Some(a) => assert_eq(a.pubkey_fp, pk) // ★ 逐字相等
  }
}
