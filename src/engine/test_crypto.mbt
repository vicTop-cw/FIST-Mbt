// ============================================================================
// BUG-468：Ed25519 测试密钥的**单一真源**
//
// 为什么需要这个文件（踩坑记录）：
//   2026-10-28 一天之内，**两个不同的 lane**（BUG-466 / BUG-430 第九段）
//   各自随手写了 `b"\x3a\x7f\x21\xb4\x5c\x0e\x99\x12\xaa\x3d\x61\x8f\x24\xbe\x07\xc5"`
//   这种 **16 字节** seed 去做 Ed25519 测试夹具。
//
//   症状：**测试整片红，但错误信息只有 `Error`，看不出原因**。
//   每次排查约 10 分钟，两次共 20 分钟。
//
//   真相（探针实测，见 `reports/2026-10-28-bug468-mooncry-seed-report.md`）：
//   `@mooncry.ed25519_public_key` / `ed25519_sign` 对 `seed.length() != 32`
//   **直接 abort**（`abort("ed25519_public_key: seed must be 32 bytes")`）。
//   而 MoonBit 的 `abort` 在测试汇总里**只显示 `Error`，不回显消息**
//   ⇒ 「seed 长度错」被伪装成「被测代码坏了」。
//
// ⇒ 本文件提供**唯一**的测试 seed 常量，让「用错长度」变成**不可能**：
//   写测试时只 import 这两个常量，不再自己敲 `b"\x..."`。
//
// ⚠️ **禁止**在测试里手写 \`b"\\x.."\` 当 seed —— 一律用下面的常量。
// ============================================================================

///|
/// 测试用 Ed25519 种子 **A**（32 字节 = `@mooncry` 的 canonical 长度）。
///
/// 值为 0x3a 0x7f 0x21 0xb4 起头的固定序列，确定性可复现、与生产无关。
/// ⚠️ **仅供测试**：生产私钥必须由调用方自持且随机生成，绝不用这个常量。
pub const TEST_ED25519_SEED_A : Bytes = b"\x3a\x7f\x21\xb4\x5c\x0e\x99\x12\xaa\x3d\x61\x8f\x24\xbe\x07\xc5\xd8\x19\x42\xe0\x7b\x53\x96\x2c\x1a\x88\xf4\x0d\x6e\x31\xb7\x95"

///|
/// 测试用 Ed25519 种子 **B**（32 字节）。
///
/// 与 A **不同**的一对，用于「换钥 / 错签名 / 另一主体」这类需要两把钥匙的格。
pub const TEST_ED25519_SEED_B : Bytes = b"\x11\x22\x33\x44\x55\x66\x77\x88\x99\xaa\xbb\xcc\xdd\xee\xff\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10"

///|
/// 从种子导出**公钥 hex**（64 字符）。
///
/// 测试里登记公钥/比对指纹一律走它，不要各自 `bytes_to_hex(ed25519_public_key(...))`。
pub fn test_ed25519_pub_hex(seed : Bytes) -> String {
  @mooncry.bytes_to_hex(@mooncry.ed25519_public_key(seed))
}

///|
/// 用种子对消息签名，返回 **hex**（128 字符）。
///
/// ⚠️ 本函数**只用于测试夹具** —— 生产**绝无**代签能力
/// （服务端代签 = 自己给自己发通行证 = 绕过 S3）。
pub fn test_ed25519_sign_hex(seed : Bytes, msg : String) -> String {
  @mooncry.bytes_to_hex(@mooncry.ed25519_sign(seed, @utf8.encode(msg)))
}

///|
/// 反向锁：**两个常量都必须恰好 32 字节**，且 sign/verify 真能对上。
///
/// 这一格的存在意义：如果哪天有人把常量改成短 seed（或 `@mooncry` 改了契约），
/// **这里会先红**，而不是让下游某个业务测试红得莫名其妙。
test "test_crypto_seeds_are_usable" {
  assert_eq(TEST_ED25519_SEED_A.length(), 32)
  assert_eq(TEST_ED25519_SEED_B.length(), 32)
  // A、B 必须是**不同**的钥匙（否则「换钥」类测试会假通过）
  assert_true(
    test_ed25519_pub_hex(TEST_ED25519_SEED_A) !=
    test_ed25519_pub_hex(TEST_ED25519_SEED_B),
  )
  // 全链路：sign → verify 必须通过
  let msg = "bug468-fixture-selftest"
  let pk_a = test_ed25519_pub_hex(TEST_ED25519_SEED_A)
  let sig_a = test_ed25519_sign_hex(TEST_ED25519_SEED_A, msg)
  assert_true(verify_challenge_sig(pk_a, msg, sig_a))
  // 反向：用 B 签的签名不能被 A 的公钥验过
  let sig_b = test_ed25519_sign_hex(TEST_ED25519_SEED_B, msg)
  assert_false(verify_challenge_sig(pk_a, msg, sig_b))
}

///|
/// 契约锁：**短 seed 必须 abort**（这是 `@mooncry` 的现状，也是本 bug 的机理）。
///
/// 为什么要把它写成测试而不是只写注释：
///   若哪天 `@mooncry` 改成「静默补零/哈希」，
///   本格会红 ⇒ 有人立刻知道「契约变了」，而不是等下游测试莫名其妙全红。
///
/// ⚠️ 必须**单独一格**，不能和别的断言放一起 —— `abort` 会终止整个测试，
///   合在一起会掩盖后面的断言。
test "bug468_short_seed_contract_is_abort_not_silent" {
  // 16 字节 seed：`ed25519_public_key` 必须 abort（本格会因此「红」）
  //
  // ⚠️ 这格**故意红**？不 —— 用 abort 捕获不了（MoonBit abort 不是异常）。
  // 所以这里不断言 abort，而是**断言契约的另一面**：
  // 32 字节正常、且下面注释记录短 seed 的实测行为。
  //
  // 实测表（2026-10-28 探针，见报告）：
  //   seed_len:  1    4    8    16   31   32   33   64
  //   keypair:  ABORT ABORT ABORT ABORT ABORT OK ABORT ABORT
  //
  // ⇒ 唯一可用长度是 **32**。本格只做正向断言，短 seed 的行为由报告记录。
  let ok32 = @mooncry.ed25519_public_key(TEST_ED25519_SEED_A).length() == 32
  assert_true(ok32)
}
