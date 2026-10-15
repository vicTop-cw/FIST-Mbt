/// star_gate_wbtest.mbt —— `star_gate.mbt` 的白盒测试（whitebox，可看私有字段）。
///
/// 用 mooncry 的 RFC 8032 Ed25519 已知向量做真验签（seed `00..1f` → pk 固定），
/// 覆盖 six 判定 + canonical 逐字节 + hex 正/负路径。判定顺序是契约，测试按顺序断言。

///|
let sg_seed : Bytes = b"\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f"

///|
/// 已知向量：seed `00..1f` 对应的 Ed25519 公钥（mooncry RFC 向量，跨库对表过）。
let sg_known_pk_hex : String = "03a107bff3ce10be1d70dd18e74bc09967e4d6309ba50d5f1ddc8664125531b8"

///|
/// 构造一份**签名正确**的 attestation JSON（format/algorithm 正确 + 真 Ed25519 签名）。
/// 签名的 canonical 只覆盖 {list, issued_at, ttl_seconds}——与 attest.yml 一致。
fn sg_sign_attest(
  list : Array[String],
  issued_at : Int64,
  ttl_seconds : Int64,
) -> String {
  let canonical = star_canonical(list, issued_at, ttl_seconds)
  let sig = @mooncry.ed25519_sign(sg_seed, canonical.to_bytes())
  let pk = @mooncry.ed25519_public_key(sg_seed)
  sg_attest_json(list, issued_at, ttl_seconds, hex_encode(pk), hex_encode(sig))
}

///|
/// 手工拼 attestation JSON（不用 @json.stringify，保证字节可控、canonical 不漂移）。
fn sg_attest_json(
  list : Array[String],
  issued_at : Int64,
  ttl_seconds : Int64,
  pk_hex : String,
  sig_hex : String,
) -> String {
  let buf = StringBuilder::new(size_hint=256)
  buf.write_string(
    "{\"format\":\"fist-star-gate-attestation/v1\",\"algorithm\":\"ed25519\",\"list\":[",
  )
  for i in 0..<list.length() {
    if i > 0 {
      buf.write_string(",")
    }
    buf.write_string("\"")
    buf.write_string(list[i])
    buf.write_string("\"")
  }
  buf.write_string("],\"issued_at\":")
  buf.write_string(issued_at.to_string())
  buf.write_string(",\"ttl_seconds\":")
  buf.write_string(ttl_seconds.to_string())
  buf.write_string(",\"public_key_hex\":\"")
  buf.write_string(pk_hex)
  buf.write_string("\",\"signature_hex\":\"")
  buf.write_string(sig_hex)
  buf.write_string("\"}")
  buf.to_string()
}

///|
test "star_canonical 逐字节匹配 attest.yml 的 json.dumps(sort_keys=True)" {
  let list : Array[String] = ["octocat", "alice"]
  let c = star_canonical(list, 1000000000L, 21600L)
  inspect(
    c,
    content="{\"issued_at\":1000000000,\"list\":[\"octocat\",\"alice\"],\"ttl_seconds\":21600}",
  )
}

///|
test "star_canonical 空名单" {
  let list : Array[String] = []
  let c = star_canonical(list, 5L, 6L)
  inspect(c, content="{\"issued_at\":5,\"list\":[],\"ttl_seconds\":6}")
}

///|
test "hex_decode / hex_encode 往返 + 正负路径" {
  let raw : Bytes = b"\xde\xad\xbe\xef"
  inspect(hex_encode(raw), content="deadbeef")
  if hex_decode("deadbeef") is Ok(_) {

  } else {
    fail("合法 hex 应 Ok")
  }
  if hex_decode("abc") is Err(_) {

  } else {
    fail("奇数长度 hex 应 Err")
  }
  if hex_decode("zz") is Err(_) {

  } else {
    fail("非 hex 字符应 Err")
  }
}

///|
test "star_gate_verify 全通过 → Valid" {
  let list : Array[String] = ["octocat", "alice"]
  let j = sg_sign_attest(list, 1000000000L, 21600L)
  let o = star_gate_verify(j, "alice", 1000000001L)
  inspect(o.verdict, content="Valid")
  inspect(o.list_count, content="2")
  inspect(o.now_epoch, content="1000000001")
}

///|
test "star_gate_verify 边界 now==issued_at+ttl 仍 Valid" {
  let list : Array[String] = ["octocat"]
  let j = sg_sign_attest(list, 1000L, 100L)
  let o = star_gate_verify(j, "octocat", 1100L)
  inspect(o.verdict, content="Valid")
}

///|
test "star_gate_verify 签名被篡改 → BadSignature" {
  let list : Array[String] = ["octocat"]
  let j = sg_sign_attest(list, 1000L, 100L)
  let _ = j
  // 篡改：改 ttl_seconds 而不重签 → canonical 变，验签必败
  let tampered = sg_attest_json(list, 1000L, 101L, sg_known_pk_hex, "00")
  let o = star_gate_verify(tampered, "octocat", 1000L)
  inspect(o.verdict, content="BadSignature")
  inspect(o.list_count, content="1")
}

///|
test "star_gate_verify login 不在名单 → NoSuchUser" {
  let list : Array[String] = ["octocat"]
  let j = sg_sign_attest(list, 1000L, 10000L)
  let o = star_gate_verify(j, "mallory", 1001L)
  inspect(o.verdict, content="NoSuchUser")
}

///|
test "star_gate_verify 已过期 → Stale" {
  let list : Array[String] = ["octocat"]
  let j = sg_sign_attest(list, 1000L, 100L)
  let o = star_gate_verify(j, "octocat", 1101L)
  inspect(o.verdict, content="Stale")
}

///|
test "star_gate_verify 非法 JSON → Unreadable" {
  let o = star_gate_verify("not json{", "octocat", 0L)
  inspect(o.verdict, content="Unreadable")
}

///|
test "star_gate_verify format 非本门 → BadFormat" {
  let bad = "{\"format\":\"other/v1\",\"algorithm\":\"ed25519\",\"list\":[\"octocat\"],\"issued_at\":1,\"ttl_seconds\":1,\"public_key_hex\":\"00\",\"signature_hex\":\"00\"}"
  let o = star_gate_verify(bad, "octocat", 1L)
  inspect(o.verdict, content="BadFormat")
}

///|
test "star_gate_verify algorithm 非 ed25519 → BadFormat" {
  let bad = "{\"format\":\"fist-star-gate-attestation/v1\",\"algorithm\":\"rsa\",\"list\":[\"octocat\"],\"issued_at\":1,\"ttl_seconds\":1,\"public_key_hex\":\"00\",\"signature_hex\":\"00\"}"
  let o = star_gate_verify(bad, "octocat", 1L)
  inspect(o.verdict, content="BadFormat")
}

///|
test "star_gate_verify 缺 list 字段 → BadFormat" {
  let bad = "{\"format\":\"fist-star-gate-attestation/v1\",\"algorithm\":\"ed25519\",\"issued_at\":1,\"ttl_seconds\":1,\"public_key_hex\":\"00\",\"signature_hex\":\"00\"}"
  let o = star_gate_verify(bad, "octocat", 1L)
  inspect(o.verdict, content="BadFormat")
}

///|
test "star_gate_verify public_key_hex 非 hex → BadSignature" {
  let list : Array[String] = ["octocat"]
  let bad = sg_attest_json(list, 1000L, 100L, "zznothex", sg_known_pk_hex)
  let o = star_gate_verify(bad, "octocat", 1000L)
  // 公钥坏 → 判 BadSignature（reason 说明是 hex 问题），不是 BadFormat
  inspect(o.verdict, content="BadSignature")
  inspect(o.list_count, content="1")
}

///|
/// 钉死入口（star_gate_verify_pinned）的白盒锁。
/// 覆盖三态：公钥一致 → 与原入口同判定；公钥不符 → BadSignature（reason 点明「钉死」）；
/// 空期望公钥 → fail-closed BadSignature。

///|
test "star_gate_verify_pinned 公钥一致 == star_gate_verify（零回归等价）" {
  let list : Array[String] = ["octocat"]
  let j = sg_sign_attest(list, 1000L, 10000L)
  let a = star_gate_verify(j, "octocat", 1001L)
  let b = star_gate_verify_pinned(j, "octocat", 1001L, sg_known_pk_hex)
  inspect(a.verdict, content="Valid")
  inspect(b.verdict, content="Valid")
  inspect(b.list_count, content="1")
}

///|
test "star_gate_verify_pinned 公钥不符 → BadSignature（reason 点明钉死）" {
  let list : Array[String] = ["octocat"]
  // payload 用的是 sg_known_pk_hex；期望公钥给另一个合法 hex（64 个 0）
  let j = sg_sign_attest(list, 1000L, 10000L)
  let other_pk = "0".repeat(64)
  let o = star_gate_verify_pinned(j, "octocat", 1001L, other_pk)
  inspect(o.verdict, content="BadSignature")
  inspect(o.list_count, content="1")
  if o.reason.contains("钉死") {

  } else {
    fail(
      "pinned 公钥不符的 reason 应点明「钉死」，实际: \{o.reason}",
    )
  }
}

///|
test "star_gate_verify_pinned 空期望公钥 → BadSignature（fail-closed，不退化）" {
  let list : Array[String] = ["octocat"]
  let j = sg_sign_attest(list, 1000L, 10000L)
  let o = star_gate_verify_pinned(j, "octocat", 1001L, "")
  inspect(o.verdict, content="BadSignature")
  inspect(o.list_count, content="1")
  if o.reason.contains("fail-closed") {

  } else {
    fail(
      "空期望公钥的 reason 应点明 fail-closed，实际: \{o.reason}",
    )
  }
}

///|
test "star_gate_verify_pinned 公钥一致 + login 不在名单 → NoSuchUser（钉死不改变后续判定）" {
  let list : Array[String] = ["octocat"]
  let j = sg_sign_attest(list, 1000L, 10000L)
  let o = star_gate_verify_pinned(j, "mallory", 1001L, sg_known_pk_hex)
  inspect(o.verdict, content="NoSuchUser")
}

///|
/// 路由门禁策略（star_gate_policy）的白盒锁。
/// 覆盖三态 + 未放行两种子判定：未启用（放行+告警）/ 启用无 attestation（fail-closed）/
/// 启用齐备（按 verdict：Valid 放行、BadSignature/NoSuchUser 拦截）。

///|
test "star_gate_policy 未配置公钥 → 门未启用 + 放行 + 告警" {
  let p = star_gate_policy("", "", "octocat", 1000L)
  inspect(p.gate_enabled, content="false")
  inspect(p.free_pool_unlocked, content="true")
  if p.note.contains("未启用") &&
    p.note.contains("FIST_STAR_GATE_PUBKEY_HEX") {

  } else {
    fail(
      "未配置公钥的 note 应点明「未启用」与 env 名，实际: \{p.note}",
    )
  }
}

///|
test "star_gate_policy 配置公钥但无 attestation → 门启用 + fail-closed 拦截" {
  let p = star_gate_policy(sg_known_pk_hex, "", "octocat", 1000L)
  inspect(p.gate_enabled, content="true")
  inspect(p.free_pool_unlocked, content="false")
  if p.note.contains("fail-closed") {

  } else {
    fail(
      "启用无 attestation 的 note 应点明 fail-closed，实际: \{p.note}",
    )
  }
}

///|
test "star_gate_policy 齐备且验签通过 → 放行，verdict=Valid" {
  let list : Array[String] = ["octocat", "alice"]
  let j = sg_sign_attest(list, 1000L, 10000L)
  let p = star_gate_policy(sg_known_pk_hex, j, "alice", 1001L)
  inspect(p.gate_enabled, content="true")
  inspect(p.free_pool_unlocked, content="true")
  inspect(p.verdict, content="Some(Valid)")
  if p.note.contains("验签通过") {

  } else {
    fail("放行的 note 应点明「验签通过」，实际: \{p.note}")
  }
}

///|
test "star_gate_policy 齐备但公钥不符 → 拦截，verdict=BadSignature" {
  let list : Array[String] = ["octocat"]
  let j = sg_sign_attest(list, 1000L, 10000L)
  let other_pk = "1".repeat(64)
  let p = star_gate_policy(other_pk, j, "octocat", 1001L)
  inspect(p.gate_enabled, content="true")
  inspect(p.free_pool_unlocked, content="false")
  inspect(p.verdict, content="Some(BadSignature)")
  if p.note.contains("未放行") {

  } else {
    fail("拦截的 note 应点明「未放行」，实际: \{p.note}")
  }
}

///|
test "star_gate_policy 齐备但 login 不在名单 → 拦截，verdict=NoSuchUser" {
  let list : Array[String] = ["octocat"]
  let j = sg_sign_attest(list, 1000L, 10000L)
  let p = star_gate_policy(sg_known_pk_hex, j, "mallory", 1001L)
  inspect(p.gate_enabled, content="true")
  inspect(p.free_pool_unlocked, content="false")
  inspect(p.verdict, content="Some(NoSuchUser)")
}

///|
test "star_gate_release_default_pubkey_hex 是合法 Ed25519 公钥（64 hex / 32 字节）" {
  let hex = star_release_default_pubkey_hex
  if hex.length() != 64 {
    fail(
      "发布默认公钥必须是 64 hex 字符，实际长度 \{hex.length()}：\{hex}",
    )
  }
  match hex_decode(hex) {
    Ok(b) =>
      if b.length() != 32 {
        fail(
          "发布默认公钥解码后不是 32 字节：长度 \{b.length()}",
        )
      }
    Err(e) => fail("发布默认公钥 hex 解码失败：\{e}")
  }
}

///|
test "star_gate_release_default_pubkey_hex 与发布模板 .mcp.example.json 钉死值一致" {
  // 单一真源锁：路由侧常量必须 == 发布模板里 FIST_STAR_GATE_PUBKEY_HEX 的值。
  // 换钥必须同步改这两处 + 仓库 secret ED25519_PRIVATE_KEY_HEX，否则验签不过全员锁死。
  let template_pinned_hex = "01773e6ed3ff3fceaaf545a3f26a9627a0e91e736e6a3ed353ac3d6bb5a3f32a"
  assert_eq(star_release_default_pubkey_hex, template_pinned_hex)
}

///|
test "star_gate_verify 恶意 1e300 issued_at+ttl 不 panic（BUG-196 溢出回归）" {
  // 旧代码：`issued_at + ttl_seconds`（Int64）在两边都饱和到 Int64 max 时溢出 → panic。
  // 构造一份自签的合法 attestation，但 JSON 里 issued_at/ttl_seconds 写 1e300（科学计数法 →
  // 解析为 Double），走通验签步后触发④时间层的加法溢出路径。
  let list : Array[String] = ["octocat"]
  let big = 9223372036854775807L
  // canonical 使用 to_int64() 的饱和值（Int64 max），与 star_extract_fields 的产物一致
  let canonical = star_canonical(list, big, big)
  let sig = @mooncry.ed25519_sign(sg_seed, canonical.to_bytes())
  let pk = @mooncry.ed25519_public_key(sg_seed)
  let j = "{\"format\":\"fist-star-gate-attestation/v1\",\"algorithm\":\"ed25519\",\"list\":[\"octocat\"],\"issued_at\":1e300,\"ttl_seconds\":1e300,\"public_key_hex\":\"" +
    hex_encode(pk) +
    "\",\"signature_hex\":\"" +
    hex_encode(sig) +
    "\"}"
  let o = star_gate_verify(j, "octocat", 1000L)
  // 修复后：改用 Double 比较，1e300+1e300 远大于 1000 → 未过期；login 在名单内 → Valid
  inspect(o.verdict, content="Valid")
}
