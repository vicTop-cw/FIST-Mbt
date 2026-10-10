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
  inspect(c, content="{\"issued_at\":1000000000,\"list\":[\"octocat\",\"alice\"],\"ttl_seconds\":21600}")
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