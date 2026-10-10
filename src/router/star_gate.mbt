/// star_gate.mbt —— Star 门客户端验证（方向二 P1-a，D1=A：签名清单 + TTL）
///
/// 真源：`.github/workflows/attest.yml` 的 `attest` / `selfcheck` 两个 job。模型为
///   fist-mbt 不实时查 GitHub，而是拉取仓库每 6 小时签发的 `_attest/attestation.json`，
///   用清单里自带的 `public_key_hex` 验签 + 校验 login ∈ list + 校验 `now <= issued_at + ttl_seconds`。
///
/// 诚实边界（见 docs/improvement-plan-20261010.md §3.2）：
///   这是**弱门禁 / 仪式感门禁**，不是强门禁——客户端拿到的是公开清单，用户改本地缓存即可绕过。
///   强门禁需要自建服务端网关（远期，需用户自备主机）。本文件只做「清单可信 + 名单 + 有效期」的判定，
///   不承担密钥保管、不承担清单拉取/缓存（那是另一个任务）。
///
/// 「算力由 GitHub 承担」的准确含义：GitHub 只承担【证明发布】（workflow + Pages），
///   推理算力在用户自己的厂商免费端点上（本文件即该推理部分）。
///
/// 纯计算、零 IO、无网络、无绝对路径；不硬编码任何密钥，密钥只以 hex 形式出现在被验签的清单里。

///|
/// Star 门判定结果。顺序即 star_gate_verify 的判定顺序：
///   Unreadable → BadFormat → BadSignature → Stale → NoSuchUser → Valid
pub enum StarVerdict {
  /// 清单 JSON **语法**无法解析（不是 JSON 语法错误、是字段结构错误 → 走 BadFormat）
  Unreadable
  /// 清单可解析，但 format / algorithm 不是本门格式，或字段缺失/类型错
  BadFormat
  /// canonical 重建后的验签失败（签名与 list/issued_at/ttl 不匹配，或 hex 非法）
  BadSignature
  /// 清单已过期：now_epoch > issued_at + ttl_seconds
  Stale
  /// 清单有效但 user_login 不在授权名单里
  NoSuchUser
  /// 全部通过
  Valid
} derive(Eq, Debug, Show)

///|
/// 验签结果。字段保持私有可见性（白盒测试可构造；黑盒只读 verdict/reason）。
pub struct StarGateOutcome {
  verdict : StarVerdict
  /// 人可读的中文原因，便于把「为什么没放行」写进日志/回执
  reason : String
  /// 名单条目数（供调用方做量级/异常观察，如异常超大名单）
  list_count : Int
  /// 回显本次判定使用的 now_epoch，便于审计与复现
  now_epoch : Int64
}

///|
/// 从 JSON 解析出的、验签所需的最小结构。
struct StarAttestData {
  list : Array[String]
  issued_at : Int64
  ttl_seconds : Int64
  public_key_hex : String
  signature_hex : String
}

///|
/// 构造 StarGateOutcome 的统一入口，避免每处漏填字段。
fn star_outcome(
  verdict : StarVerdict,
  reason : String,
  list_count : Int,
  now_epoch : Int64,
) -> StarGateOutcome {
  { verdict, reason, list_count, now_epoch }
}

///|
/// canonical 重建 —— 与 attest.yml 的 `json.dumps({"list":…,"issued_at":…,"ttl_seconds":…},
/// sort_keys=True, separators=(",", ":"))` **逐字节一致**，即形如
///   `{"issued_at":<n>,"list":["a","b"],"ttl_seconds":<n>}`
/// sort_keys 使键序固定为 issued_at → list → ttl_seconds。
///
/// 前提（重要）：login 只含 ASCII 字母/数字/连字符（GitHub 用户名规则），因此
///   **不需要** JSON 字符串转义（`"` `\` 与控制字符都不可能出现在 login 里）。若未来放开该约束，
///   必须同步改成与 `json.dumps(ensure_ascii=True)` 等价的转义实现，否则验签会静默失败。
pub fn star_canonical(list : Array[String], issued_at : Int64, ttl_seconds : Int64) -> String {
  let buf = StringBuilder::new(size_hint=64)
  buf.write_string("{\"issued_at\":")
  buf.write_string(issued_at.to_string())
  buf.write_string(",\"list\":[")
  for i in 0..<list.length() {
    if i > 0 {
      buf.write_string(",")
    }
    buf.write_string("\"")
    buf.write_string(list[i])
    buf.write_string("\"")
  }
  buf.write_string("],\"ttl_seconds\":")
  buf.write_string(ttl_seconds.to_string())
  buf.write_string("}")
  buf.to_string()
}

///|
/// hex 解码：复用 mooncry 的 `hex_to_bytes_or`（已是 Result 版、不 abort），不重复造轮子。
/// 奇数长度或含非 hex 字符 → Err。
pub fn hex_decode(s : String) -> Result[Bytes, String] {
  @mooncry.hex_to_bytes_or(s)
}

///|
/// hex 编码：复用 mooncry 的 `bytes_to_hex`（小写）。
pub fn hex_encode(b : Bytes) -> String {
  @mooncry.bytes_to_hex(b)
}

///|
/// 从已解析的 Json 里提取验签所需字段。任一字段缺失或类型不符 → None（调用方按 BadFormat 处理）。
fn star_extract_fields(j : Json) -> Option[StarAttestData] {
  let list = match j.value("list") {
    Some(Array(items)) => {
      let out : Array[String] = []
      for item in items {
        match item {
          String(s) => out.push(s)
          _ => return None
        }
      }
      out
    }
    _ => return None
  }
  let issued_at = match j.value("issued_at") {
    Some(Number(n, ..)) => n.to_int64()
    _ => return None
  }
  let ttl_seconds = match j.value("ttl_seconds") {
    Some(Number(n, ..)) => n.to_int64()
    _ => return None
  }
  let public_key_hex = match j.value("public_key_hex") {
    Some(String(s)) => s
    _ => return None
  }
  let signature_hex = match j.value("signature_hex") {
    Some(String(s)) => s
    _ => return None
  }
  Some({ list, issued_at, ttl_seconds, public_key_hex, signature_hex })
}

///|
/// Star 门客户端验证入口。判定顺序是契约（为什么这样排，见末尾「判定顺序」注释）：
///   ① JSON 语法解析失败                          → Unreadable
///   ② format / algorithm 非本门格式              → BadFormat
///   ③ canonical 重建 + Ed25519 验签失败          → BadSignature
///   ④ now_epoch > issued_at + ttl_seconds        → Stale
///   ⑤ user_login ∉ list                          → NoSuchUser
///   ⑥ 全过                                       → Valid
pub fn star_gate_verify(
  attestation_json : String,
  user_login : String,
  now_epoch : Int64,
) -> StarGateOutcome {
  // ① 语法层失败：字符串不是合法 JSON，什么都读不出来，直接 Unreadable（不吞错，原因写进 reason）
  let j : Json = @json.parse(attestation_json) catch {
    e => return star_outcome(Unreadable, "JSON 解析失败: \{e}", 0, now_epoch)
  }
  // ② 格式与算法先验：不是本门产物就不该继续判，避免把别的东西误当成有效证明
  //    （BadFormat 也覆盖字段缺失/类型错：见 star_extract_fields 返回 None 的分支）
  match j.value("format") {
    Some(String(f)) if f == "fist-star-gate-attestation/v1" => ()
    _ =>
      return star_outcome(
        BadFormat, "format 必须是 fist-star-gate-attestation/v1", 0, now_epoch,
      )
  }
  match j.value("algorithm") {
    Some(String(a)) if a == "ed25519" => ()
    _ => return star_outcome(BadFormat, "algorithm 必须是 ed25519", 0, now_epoch)
  }
  let data = match star_extract_fields(j) {
    Some(d) => d
    None =>
      return star_outcome(
        BadFormat,
        "清单缺少必要字段（list/issued_at/ttl_seconds/public_key_hex/signature_hex）",
        0,
        now_epoch,
      )
  }
  // ③ 密码学层：重建 canonical 并用清单自带的公钥验签。签名不可信 → 后面 TTL/名单都无意义
  let canonical = star_canonical(data.list, data.issued_at, data.ttl_seconds)
  let pub_key = match hex_decode(data.public_key_hex) {
    Ok(b) => b
    Err(e) =>
      return star_outcome(
        BadSignature, "public_key_hex 不是合法 hex: \{e}", data.list.length(), now_epoch,
      )
  }
  let sig = match hex_decode(data.signature_hex) {
    Ok(b) => b
    Err(e) =>
      return star_outcome(
        BadSignature, "signature_hex 不是合法 hex: \{e}", data.list.length(), now_epoch,
      )
  }
  let msg = canonical.to_bytes()
  if not(@mooncry.ed25519_verify(pub_key, msg, sig)) {
    return star_outcome(
      BadSignature, "Ed25519 验签失败（清单可能被篡改）", data.list.length(), now_epoch,
    )
  }
  // ④ 时间层：now == issued_at + ttl 仍有效（严格大于才过期）
  if now_epoch > data.issued_at + data.ttl_seconds {
    return star_outcome(
      Stale, "清单已过期（now > issued_at + ttl_seconds）", data.list.length(), now_epoch,
    )
  }
  // ⑤ 名单：验签通过只说明「这份清单确实是持私钥方签的」，但用户可能不在名单里
  if not(data.list.contains(user_login)) {
    return star_outcome(NoSuchUser, "user_login 不在授权名单里", data.list.length(), now_epoch)
  }
  star_outcome(Valid, "验签通过，login 在名单内且未过期", data.list.length(), now_epoch)
}

///|
/// 判定顺序为什么是「先验签，再查 TTL / user」——顺序不是随意排的，理由有三：
///   1. 验签是**事实性**前置条件：TTL 与名单都是被签名的字段，若签名都不可信，谈 TTL/user 毫无意义。
///      先验签可避免「被伪造的有效期内、被伪造的名单成员」这种自欺结果。
///   2. 顺序与成本匹配：验签是六步里唯一涉及密码学（慢）的一步，放在前面做一次性失败早退，
///      后面都是 O(1)/O(n) 的廉价比较，早退最省。
///   3. 顺序与可诊断性匹配：Unreadable（语法）→ BadFormat（结构）→ BadSignature（密码学）→
///      Stale（时间）→ NoSuchUser（身份）→ Valid，是按「问题离输入越近越先报」排列，
///      报错时能一眼看出问题发生在哪一层，便于日志审计。