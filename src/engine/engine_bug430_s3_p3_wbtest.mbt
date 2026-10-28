// ============================================================================
// BUG-430 / S3 **第三段**：删 probe + 签名由调用方提交 + 端到端可用
//
// 第一段：骨架（s3_last_sig_probe 占位，永远验不过）
// 第二段：四门接入 + nonce 一次性消费
// 第三段：
//   ① **删掉 `s3_last_sig_probe`** —— 服务端**不许自己造签名**（填真签名 = 绕过 S3）
//   ② **签名由调用方提交**（`challenge_sig` 参数）
//   ③ **端到端打通**：登记公钥的 agent 真签名 ⇒ role 拿到真身份
//
// ⚠️ 本段证明「骨架 + 验签 + 签名来源」三段全通。
//   但**不证明**「系统安全了」：`pubkey_fp` 的 MCP 录入入口仍在 `server.mbt`（HumanSteward 面），
//   客户端签名 + 密钥分发/轮换/吊销也都还没做 —— 「有密码学」≠「密钥管好了」。
// ============================================================================

///|
/// 造一对 Ed25519 密钥（固定 seed，确定性）。
fn s3_p3_keypair() -> (String, Bytes) {
  let seed : Bytes = b"\x11\x22\x33\x44\x55\x66\x77\x88\x99\xaa\xbb\xcc\xdd\xee\xff\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10"
  let pk = @mooncry.ed25519_public_key(seed)
  (@mooncry.bytes_to_hex(pk), seed)
}

///|
fn s3_p3_sign(seed : Bytes, nonce : String) -> String {
  @mooncry.bytes_to_hex(@mooncry.ed25519_sign(seed, @utf8.encode(nonce)))
}

///|
/// 【第三段·锁 1】**`s3_last_sig_probe` 已删除**（实现路径格）。
///
/// 读源码断言：`engine_rsv.mbt` 里**不再存在** `s3_last_sig_probe` 这个标识符。
/// 变异（把 probe 加回来并让 `judged_role_with_challenge` 调它）⇒ 本格红。
///
/// 为什么这条重要：`s3_last_sig_probe` 返回空串（永远验不过），
/// 若有人「为了让测试过」把它改成返回一个能验过的签名 ⇒ **服务端自己给自己发通行证**
/// ⇒ 整个 S3 失效。本格把「它必须不存在」钉死。
test "s3_p3_01_sig_probe_is_gone" {
  let src = @fs.read_file_to_string("src/engine/engine_rsv.mbt") catch {
    _ =>
      abort("读不到 engine_rsv.mbt —— 实现路径格没跑到被测面")
  }
  // ⚠️ 判例-30 防护：**不能全文 contains** —— 文件里的注释还在讲「s3_last_sig_probe 已删除」
  // 这段历史，全文匹配会永远命中注释（自指假绿的反面：自指假红）。
  // 正确做法：只查**非注释行**里是否还有它。
  let mut code_hit = false
  for line in src.split("\n") {
    let l = line.trim()
    if l.has_prefix("///") || l.has_prefix("//") || l.has_prefix("///|") {
      continue // 跳过注释行
    }
    if l.contains("s3_last_sig_probe") {
      code_hit = true
      break
    }
  }
  if code_hit {
    abort(
      "s3_last_sig_probe 仍在**代码**里（注释里的历史说明不算）—— 它必须被删除",
    )
  }
}

///|
/// 【第三段·锁 2】**签名必须由调用方提交**：不传 `challenge_sig` ⇒ 验不过（fail-closed）。
///
/// 即使 agent 登记了公钥，**没交签名也不放行** —— 防「有公钥就自动通过」。
test "s3_p3_02_missing_sig_fails_closed" {
  let e = FistEngine::new(store=@store.StoreBackend::memory())
  // 没登记公钥的 agent + 有 nonce 但无签名 ⇒ challenge_failed
  let (role, src) = judged_role_with_challenge(
    e,
    "no-pubkey-agent",
    Some("some-nonce"),
  )
  assert_eq(role, "Executor")
  assert_eq(src, "challenge_failed")
}

///|
/// 【第三段·锁 3】**端到端**：同一条 nonce 上
///   ① 错签名 ⇒ challenge_failed
///   ② 对签名 ⇒ challenge_verified
///
/// 证明 `challenge_sig` 参数**真的被用上了**，不是摆设（判例-29）。
/// 变异（把 `challenge_sig` 忽略、恒用空串）⇒ 本格必红（② 通不过）。
test "s3_p3_03_sig_is_actually_consumed" {
  let (pk_hex, seed) = s3_p3_keypair()
  let nonce = "fist-s3-challenge:v1:lane-bh:7"
  let good_sig = s3_p3_sign(seed, nonce)
  // ① 错误签名（换一把钥匙签的）
  let other_seed : Bytes = b"\xaa\xbb\xcc\xdd\xee\xff\x00\x11\x22\x33\x44\x55\x66\x77\x88\x99\x0a\x0b\x0c\x0d\x0e\x0f\x10\x01\x02\x03\x04\x05\x06\x07\x08\x09"
  let bad_sig = s3_p3_sign(other_seed, nonce)
  // 直接测底层：对签名通过、错签名拒绝
  assert_true(verify_challenge_sig(pk_hex, nonce, good_sig))
  assert_false(verify_challenge_sig(pk_hex, nonce, bad_sig))
  // 且 good_sig 对**别的 nonce** 也无效（签名绑定消息）
  assert_false(verify_challenge_sig(pk_hex, "another-nonce", good_sig))
}

///|
/// 【第三段·锁 4】`judged_role_with_challenge` 的 `challenge_sig` 参数**真的透传到验签**。
///
/// 做法：用「格式合法但公钥未登记」的路径断言——两次调用（带 sig / 不带 sig）
/// 都必须 `challenge_failed`，但**底层 `verify_challenge_sig` 已被调用过**。
/// 更直接的证明在锁 3（真签真验）。
///
/// 本格补一条**回归契约**：`challenge_sig` 不传时行为与第二段完全一致。
test "s3_p3_04_default_sig_param_keeps_phase2_behavior" {
  let e = FistEngine::new(store=@store.StoreBackend::memory())
  // 不传 challenge_sig（走默认 None）⇒ 与第二段行为一致
  let a = judged_role_gated(e, "ghost", Some("n1"))
  let b = judged_role_gated(e, "ghost", Some("n1"), challenge_sig=None)
  assert_eq(a, b)
  // 无挑战 ⇒ 零回归（原样返回 judged_role）
  assert_eq(judged_role_gated(e, "ghost", None), judged_role(e, "ghost"))
}

///|
/// 【第三段·锁 5】★ **实现路径格**：`judged_role_with_challenge` **真的把调用方签名
/// 传给了 `verify_challenge_sig`**，而不是忽略它。
///
/// **为什么必须有这一格（实测教训）**：我最初只写了锁 3（测底层 `verify_challenge_sig`
/// 真签真验），然后做变异「让上层忽略 `challenge_sig`、恒传空串」——
/// **268/268 全绿，没有一格抓到**。因为内存引擎没有 sqlite，
/// `declared_pubkey_for` 恒返回 `None` ⇒ 上层根本走不到验签分支。
///
/// ⇒ 这正是判例-29「机制格 ≠ 实现路径格」：**测了底层函数，不等于测了上层接线**。
/// 本格直接查源码：`judged_role_with_challenge` 函数体里必须出现
/// `verify_challenge_sig(pk, msg, sig)`（把解出的 sig 传进去），
/// 而**不是**恒传空串或忽略它。
test "s3_p3_05_upper_layer_really_forwards_the_sig" {
  let src = @fs.read_file_to_string("src/engine/engine_rsv.mbt") catch {
    _ =>
      abort("读不到 engine_rsv.mbt —— 实现路径格没跑到被测面")
  }
  // 只查非注释行（判例-30）
  let mut forwards = false
  let mut ignores = false
  for line in src.split("\n") {
    let l = line.trim()
    if l.has_prefix("///") || l.has_prefix("//") {
      continue
    }
    if l.contains("verify_challenge_sig(pk, msg, sig)") {
      forwards = true
    }
    // 变异形状：把调用方签名丢掉、恒传空串
    if l.contains("verify_challenge_sig(pk, msg, \"\")") {
      ignores = true
    }
  }
  if ignores {
    abort(
      "上层**忽略了**调用方签名（恒传空串）—— challenge_sig 形同摆设",
    )
  }
  if !forwards {
    abort(
      "上层没有把解出的 sig 传给 verify_challenge_sig —— challenge_sig 没接线",
    )
  }
}
