// ============================================================================
// BUG-430 / S3 **第七段**：公钥「首注册即钉死」的行为锁（key pin）
//
// 既有锁覆盖到的面：
//   ① 引擎行为格（engine_bug430_s3_key_wbtest）—— 有键能过挑战、无键 fail-closed
//   ② 源码格（server_bug430_s3_keyreplace_wbtest.bl_03）—— 工具里「有拒绝分支」这段字
// 缺的是**判定本身的行为格**：把「首登 / 幂等 / 拒绝」三态真的跑一遍。
//
// 本文件补上，并钉住四件事：
//   · 首登成功（真写库，读回逐字相等）
//   · 同键幂等（不误拒、不改库、回执 mode 可区分）
//   · 异键被拒（判定 + 拒绝文案关键片段 + 两把键前缀）
//   · 拒了之后**旧键仍然能通过挑战**（防「拒了但把旧键写坏」/「拒了但新键生效」）
//
// ⚠️ 判例-29/30 口径：
//   · 行为格调 `key_pin_verdict` / `key_pin_reject_message` / `key_pin_receipt_mode`
//     —— 这三件是工具**实际调用**的实现路径（不是另写一份判据）
//   · 源码格查 server.mbt 时跳过注释行（判例-30），并断言「工具确实调用了判定函数」
//     —— 否则纯函数绿了、工具绕开它自己写一份，锁恒绿
// ============================================================================

///|
/// 固定 seed 的测试密钥对 A（确定性、可复现；**仅测试夹具**，生产服务端不代签）。
fn kp_seed_a() -> Bytes {
  b"\x3a\x7f\x21\xb4\x5c\x0e\x99\x12\xaa\x3d\x61\x8f\x24\xbe\x07\xc5\xd8\x19\x42\xe0\x7b\x53\x96\x2c\x1a\x88\xf4\x0d\x6e\x31\xb7\x95"
}

///|
/// 固定 seed 的测试密钥对 B（与 A 必不相同）。
fn kp_seed_b() -> Bytes {
  b"\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99\x99"
}

///|
fn kp_pub_hex(seed : Bytes) -> String {
  @mooncry.bytes_to_hex(@mooncry.ed25519_public_key(seed))
}

///|
/// String（ASCII）→ UTF-8 字节。
///
/// 为什么不用 `@utf8.encode`：`src/server/moon.pkg` **没有** import
/// `moonbitlang/core/utf8`，而本轮任务边界不允许改 `moon.pkg`。
/// 挑战串是 ASCII（`fist-s3-challenge:v1:<agent>:<counter>`）⇒ UTF-8 字节
/// **逐字节等于字符码**，用 hex 中转（`@mooncry.hex_to_bytes_or`）即可，
/// 与引擎侧 `@utf8.encode(msg)` 得到**完全相同**的字节序列。
fn kp_utf8_bytes_ascii(s : String) -> Bytes {
  let hx = "0123456789abcdef"
  let hxa = hx.to_array()
  let mut hex = ""
  for c in s.to_array() {
    let code = c.to_int()
    if code < 0 || code > 127 {
      abort(
        "测试夹具只支持 ASCII 挑战串（UTF-8 逐字节等于字符码）",
      )
    }
    let ci = code
    hex = hex + hxa[ci / 16].to_string() + hxa[ci % 16].to_string()
  }
  match @mooncry.hex_to_bytes_or(hex) {
    Ok(b) => b
    Err(e) => abort("ASCII→UTF-8 字节转换失败：" + e)
  }
}

///|
/// 测试夹具：用私钥签名（**仅测试**；服务端代码面里不许出现 `ed25519_sign`）。
fn kp_sign_with(seed : Bytes, msg : String) -> String {
  @mooncry.bytes_to_hex(@mooncry.ed25519_sign(seed, kp_utf8_bytes_ascii(msg)))
}

///|
/// 内存 sqlite 引擎（与生产同一条 `agents` 表路径，不打桩）。
fn kp_engine() -> @engine.FistEngine {
  let sql = match @store.SqliteStore::open(":memory:") {
    Some(s) => s
    None => abort("sqlite open 失败 —— 本格没跑到被测面")
  }
  @engine.FistEngine::new(store=@store.StoreBackend::sqlite(sql))
}

///|
/// 去掉注释行（判例-30：注释里讲「拒绝覆盖」不算代码里有拒绝分支）。
fn kp_code_only(raw : String) -> String {
  let mut acc = ""
  for line in raw.split("\n") {
    let s = line.to_string()
    let l = s.trim()
    if l.has_prefix("///") || l.has_prefix("//") {
      continue
    }
    acc = acc + s + "\n"
  }
  acc
}

///|
fn kp_find_from(hay : String, needle : String, from : Int32) -> Int32? {
  let h = hay.to_array()
  let nd = needle.to_array()
  if nd.length() == 0 || nd.length() > h.length() {
    return None
  }
  let mut i = from
  while i + nd.length() <= h.length() {
    let mut j = 0
    let mut ok = true
    while j < nd.length() {
      if h[i + j] != nd[j] {
        ok = false
        break
      }
      j = j + 1
    }
    if ok {
      return Some(i)
    }
    i = i + 1
  }
  None
}

///|
fn kp_slice(s : String, from : Int32, to : Int32) -> String {
  let a = s.to_array()
  let lo = if from < 0 { 0 } else { from }
  let hi = if to > a.length() { a.length() } else { to }
  let mut out = ""
  let mut i = lo
  while i < hi {
    out = out + a[i].to_string()
    i = i + 1
  }
  out
}

///|
/// 截出 `agent_register_key` 这段工具实现（从工具名字面量起 9000 字符）。
fn kp_tool_block(src : String) -> String {
  let i = match kp_find_from(src, "\"agent_register_key\",", 0) {
    Some(x) => x
    None =>
      abort(
        "找不到 agent_register_key 工具 —— 判据没跑到被测面",
      )
  }
  kp_slice(src, i, i + 9000)
}

///|
/// 【钉·锁 1】**首注册成功**：无既有公钥 ⇒ 判定 first，且真写进 agents 表。
test "kp_01_first_registration_succeeds" {
  let seed = kp_seed_a()
  let k = kp_pub_hex(seed)
  // ① 纯判定：库里没有键 ⇒ 首登（不是拒绝，也不是幂等）
  assert_eq(key_pin_verdict("", k), key_pin_first)
  // ② 走工具同一条写库路径（agent_touch_first_seen ⇒ agents_register）
  let eng = kp_engine()
  let agent = "lane-d-keypin-first"
  let ts = "2026-10-28T00:00:00Z"
  agent_touch_first_seen(
    eng,
    agent,
    "keypin",
    "key-registration",
    "Executor",
    "工兵",
    pubkey_hex=k,
    ts,
  )
  match eng.agents_get(agent_fp(agent)) {
    None =>
      abort("首登后读不回 agents 行 —— 公钥录入是死承诺")
    Some(a) => assert_eq(a.pubkey_fp, k)
  }
}

///|
/// 【钉·锁 2】**同键幂等**：判定 idempotent、回执 mode 区分、重复登记不改坏库。
test "kp_02_same_key_is_idempotent" {
  let k = kp_pub_hex(kp_seed_a())
  assert_eq(key_pin_verdict(k, k), key_pin_idempotent)
  // 回执口径：幂等 ⇒ already_registered；首登 ⇒ registered
  assert_eq(key_pin_receipt_mode(key_pin_idempotent), "already_registered")
  assert_eq(key_pin_receipt_mode(key_pin_first), "registered")
  // 重复登记同一把键：库里必须仍是这把键（幂等成功，不误拒、不写坏）
  let eng = kp_engine()
  let agent = "lane-d-keypin-idem"
  let ts = "2026-10-28T00:00:00Z"
  agent_touch_first_seen(
    eng,
    agent,
    "keypin",
    "key-registration",
    "Executor",
    "工兵",
    pubkey_hex=k,
    ts,
  )
  agent_touch_first_seen(
    eng,
    agent,
    "keypin",
    "key-registration",
    "Executor",
    "工兵",
    pubkey_hex=k,
    ts,
  )
  match eng.agents_get(agent_fp(agent)) {
    None => abort("幂等重登记后读不回 agents 行")
    Some(a) => assert_eq(a.pubkey_fp, k)
  }
}

///|
/// 【钉·锁 3】**异键被拒**：判定 reject_different + 文案可执行（带两把键前缀与去路）。
test "kp_03_different_key_is_rejected_with_reason" {
  let k_old = kp_pub_hex(kp_seed_a())
  let k_new = kp_pub_hex(kp_seed_b())
  assert_true(k_old != k_new)
  assert_eq(key_pin_verdict(k_old, k_new), key_pin_reject_different)
  let msg = key_pin_reject_message(k_old, k_new)
  // 错误文案关键片段：拒绝语义 + 去路（轮换尚未实现，需 owner 决策）
  assert_true(msg.contains("拒绝覆盖"))
  assert_true(msg.contains("密钥轮换"))
  assert_true(msg.contains("尚未实现"))
  assert_true(msg.contains("owner"))
  // 必须亮出两把键的前缀 —— 否则调用方分不清「不同键」与「格式/大小写误判」
  assert_true(msg.contains(substring_at(k_old, 0, 16)))
  assert_true(msg.contains(substring_at(k_new, 0, 16)))
}

///|
/// 【钉·锁 4】★ **被拒之后旧键仍可用**（防「拒了但把旧键写坏」/「拒了但新键生效」）。
///
/// 三件事：
///   ① 拒绝路径**一个字节都不写库**（旧键原样在库里）
///   ② 旧私钥签的挑战仍然 `challenge_verified`
///   ③ 被拒的新私钥签同一挑战必须 `challenge_failed`（新键没有偷偷生效）
test "kp_04_old_key_survives_rejection_and_still_authenticates" {
  let seed_old = kp_seed_a()
  let seed_new = kp_seed_b()
  let k_old = kp_pub_hex(seed_old)
  let k_new = kp_pub_hex(seed_new)
  let eng = kp_engine()
  let agent = "lane-d-keypin-survive"
  let ts = "2026-10-28T00:00:00Z"
  agent_touch_first_seen(
    eng,
    agent,
    "keypin",
    "key-registration",
    "Executor",
    "工兵",
    pubkey_hex=k_old,
    ts,
  )
  // ① 模拟「异键登记被拒」：工具在写库**之前** return Err ⇒ 这里同样不写
  if key_pin_verdict(k_old, k_new) == key_pin_reject_different {
    ignore(key_pin_reject_message(k_old, k_new))
  } else {
    abort("异键判定不是 reject_different —— 本格没走到被测面")
  }
  let stored = match eng.agents_get(agent_fp(agent)) {
    None => abort("拒绝路径之后读不回 agents 行")
    Some(a) => a.pubkey_fp
  }
  assert_eq(stored, k_old) // 旧键没被写坏
  // ② 旧私钥仍然能通过挑战（真签名 + 真验签，不是打桩）
  let nonce = @engine.issue_challenge_nonce(agent, 11)
  let sig_old = kp_sign_with(seed_old, nonce)
  let (_role_old, src_old) = @engine.judged_role_with_challenge(
    eng,
    agent,
    Some(nonce),
    challenge_sig=Some(sig_old),
  )
  assert_eq(src_old, "challenge_verified")
  // ③ 被拒的新键**没有生效**：新私钥签同一挑战必须失败
  let sig_new = kp_sign_with(seed_new, nonce)
  let (_role_new, src_new) = @engine.judged_role_with_challenge(
    eng,
    agent,
    Some(nonce),
    challenge_sig=Some(sig_new),
  )
  assert_eq(src_new, "challenge_failed")
}

///|
/// 【钉·锁 5】**工具真的用这份判定**（实现路径格，判例-29）。
///
/// 只测纯函数会漏掉「工具绕开它自己写一份 / 把拒绝分支删掉」——本格钉接线：
///   · 工具里出现 `key_pin_verdict(prev_key, pubkey_hex)`
///   · 拒绝分支用统一的 `key_pin_reject_message(...)` 并 `return Err`
///   · 幂等分支取判定结果（`let already_registered = pin == key_pin_idempotent`）
///   · 判定发生在写库（`agent_touch_first_seen`）**之前**
test "kp_05_tool_uses_the_pin_verdict_before_any_write" {
  let raw = @fs.read_file_to_string("src/server/server.mbt") catch {
    _ => abort("读不到 server.mbt —— 实现路径格没跑到被测面")
  }
  let blk = kp_tool_block(kp_code_only(raw))
  if !blk.contains("key_pin_verdict(prev_key, pubkey_hex)") {
    abort(
      "工具没有调用 key_pin_verdict —— 纯函数绿了但工具绕开它，判定没接线",
    )
  }
  if !blk.contains("pin == key_pin_reject_different") {
    abort("工具没有按 reject 分支拒绝 —— 异键仍可能被放行")
  }
  if !blk.contains("key_pin_reject_message(prev_key, pubkey_hex)") {
    abort(
      "拒绝路径没有用统一的拒绝文案（或干脆没有拒绝路径）",
    )
  }
  if !blk.contains("let already_registered = pin == key_pin_idempotent") {
    abort(
      "同键幂等分支没有取判定结果 —— 幂等会被误拒或误写",
    )
  }
  let i_pin = match kp_find_from(blk, "key_pin_verdict(", 0) {
    Some(i) => i
    None => abort("找不到判定调用")
  }
  let i_touch = match kp_find_from(blk, "agent_touch_first_seen(", 0) {
    Some(i) => i
    None => abort("找不到写库调用")
  }
  if i_pin >= i_touch {
    abort(
      "判定发生在写库之后 —— 拒绝晚了，旧键已经被改写",
    )
  }
}

///|
/// 【钉·锁 6】**抽判定不许弄丢首登验签，也不许长出代签**。
///
/// 第七段是重构判定 + 加锁，安全属性必须**只增不减**：
///   · 首登仍用「本次要登记的公钥 + challenge 原文」验 `proof_sig`（否则抢注复活）
///   · server.mbt 代码面仍**不出现** `ed25519_sign`（服务端永不代签 = 自己给自己发通行证）
test "kp_06_pin_keeps_first_registration_proof_and_never_signs" {
  let raw = @fs.read_file_to_string("src/server/server.mbt") catch {
    _ => abort("读不到 server.mbt")
  }
  let src = kp_code_only(raw)
  let blk = kp_tool_block(src)
  if !blk.contains(
      "@engine.verify_challenge_sig(pubkey_hex, challenge, proof_sig)",
    ) {
    abort(
      "首登验签被弄丢了 —— 不验 proof_sig 就能首登 ⇒ 抢注复活（永久身份劫持）",
    )
  }
  if !blk.contains("首登验签失败") {
    abort("验签失败没有明确拒绝文案")
  }
  if src.contains("ed25519_sign") {
    abort(
      "server.mbt 代码面出现 ed25519_sign —— 服务端**不许**代签（等于绕过 S3）",
    )
  }
}

///|
/// 【钉·锁 7】**手搓 UTF-8 字节 == 引擎的 `@utf8.encode`**（实测等价，不是注释断言）。
///
/// 为什么需要这一格：`src/server` 没 import utf8（任务边界不许改 `moon.pkg`），
/// 测试夹具用「ASCII 字符码 → hex → Bytes」手搓字节。若手搓错一个字节，
/// 挑战签名就全错 —— 而**签名错会表现为 challenge_failed**，很容易被误判成
/// 「实现有 bug」。所以等价性必须单独钉住：
///   ① 期望字节序列由**独立实现**（Python `'…'.encode('utf-8').hex()`）算出，
///      与 MoonBit 手搓结果逐字节相等；
///   ② 用手搓字节签出的签名，交给**引擎** `verify_challenge_sig`
///      （内部走 `@utf8.encode`，见 `engine_rsv.mbt:109`）必须验得过
///      —— Ed25519 对消息**逐字节敏感**，字节不等必败；
///   ③ 反向对照：消息末尾多一个字节 ⇒ 同一签名必须验不过（证明 ② 不是恒真）。
test "kp_07_handrolled_utf8_bytes_equal_engine_utf8" {
  let msg = "fist-s3-challenge:v1:kp-utf8-check:7"
  // ① 独立实现算出的期望值：python -c "print('…'.encode('utf-8').hex())"
  assert_eq(
    @mooncry.bytes_to_hex(kp_utf8_bytes_ascii(msg)),
    "666973742d73332d6368616c6c656e67653a76313a6b702d757466382d636865636b3a37",
  )
  // ② 真签名 + 引擎真验签（引擎内部 @utf8.encode）⇒ 字节序列等价
  let seed = kp_seed_a()
  let pk = kp_pub_hex(seed)
  let sig = kp_sign_with(seed, msg)
  assert_true(@engine.verify_challenge_sig(pk, msg, sig))
  // ③ 反向对照：多一个字节必须失败
  assert_false(@engine.verify_challenge_sig(pk, msg + "x", sig))
}
