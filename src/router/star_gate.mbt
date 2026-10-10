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
  { verdict, reason, list_count, now_epoch, }
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
pub fn star_canonical(
  list : Array[String],
  issued_at : Int64,
  ttl_seconds : Int64,
) -> String {
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
fn star_extract_fields(j : Json) -> StarAttestData? {
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
  Some({ list, issued_at, ttl_seconds, public_key_hex, signature_hex, })
}

///|
/// Star 门客户端验证入口。判定顺序是契约（为什么这样排，见末尾「判定顺序」注释）：
///   ① JSON 语法解析失败                          → Unreadable
///   ② format / algorithm 非本门格式              → BadFormat
///   ③ canonical 重建 + Ed25519 验签失败          → BadSignature
///   ④ now_epoch > issued_at + ttl_seconds        → Stale
///   ⑤ user_login ∉ list                          → NoSuchUser
///   ⑥ 全过                                       → Valid

///|
/// 钉死期望公钥后的 Star 门验证（消除「公钥自指」弱点，见 plan §3.2 第 6 点）。
///
/// 原 `star_gate_verify` 用**清单 payload 里自带的** `public_key_hex` 验签（见下面 ③ 步），
/// 该公钥与被验签的内容同源 → 对能改写 Pages/CI 产物的攻击者不构成认证（可换成自己的密钥对）。
/// 本入口把期望公钥**离线钉死**：
///   - `expected_public_key_hex` 非空且 == payload 的 `public_key_hex` → 用该公钥（= expected）验签，正常判定；
///   - `expected_public_key_hex` 非空但 != payload 的 `public_key_hex` → 直接 `BadSignature`（reason 点明「钉死不符」）；
///   - `expected_public_key_hex` 为空字符串 → **fail-closed** 返回 `BadSignature`，不静默退化为自指路径。
///
/// TTL / 名单判定与 `star_gate_verify` 完全一致；本入口是纯新增，原入口签名与语义不变。
pub fn star_gate_verify_pinned(
  attestation_json : String,
  user_login : String,
  now_epoch : Int64,
  expected_public_key_hex : String,
) -> StarGateOutcome {
  star_gate_verify_impl(
    attestation_json,
    user_login,
    now_epoch,
    Some(expected_public_key_hex),
  )
}

///|
pub fn star_gate_verify(
  attestation_json : String,
  user_login : String,
  now_epoch : Int64,
) -> StarGateOutcome {
  star_gate_verify_impl(attestation_json, user_login, now_epoch, None)
}

///|
/// 共享实现：`expected_public_key_hex` 为 `None` 走原自指路径（零回归），`Some(exp)` 走钉死路径。
fn star_gate_verify_impl(
  attestation_json : String,
  user_login : String,
  now_epoch : Int64,
  expected_public_key_hex : String?,
) -> StarGateOutcome {
  // ① 语法层失败：字符串不是合法 JSON，什么都读不出来，直接 Unreadable（不吞错，原因写进 reason）
  let j : Json = @json.parse(attestation_json) catch {
    e =>
      return star_outcome(Unreadable, "JSON 解析失败: \{e}", 0, now_epoch)
  }
  // ② 格式与算法先验：不是本门产物就不该继续判，避免把别的东西误当成有效证明
  //    （BadFormat 也覆盖字段缺失/类型错：见 star_extract_fields 返回 None 的分支）
  match j.value("format") {
    Some(String(f)) if f == "fist-star-gate-attestation/v1" => ()
    _ =>
      return star_outcome(
        BadFormat,
        "format 必须是 fist-star-gate-attestation/v1",
        0,
        now_epoch,
      )
  }
  match j.value("algorithm") {
    Some(String(a)) if a == "ed25519" => ()
    _ =>
      return star_outcome(
        BadFormat,
        "algorithm 必须是 ed25519",
        0,
        now_epoch,
      )
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
  // ③ 密码学层：先过钉死门（若配置了期望公钥），再重建 canonical 验签。签名不可信 → 后面 TTL/名单都无意义
  let canonical = star_canonical(data.list, data.issued_at, data.ttl_seconds)
  match expected_public_key_hex {
    Some(exp) if exp == "" =>
      return star_outcome(
        BadSignature,
        "未配置钉死的期望公钥（空值拒绝，fail-closed）",
        data.list.length(),
        now_epoch,
      )
    Some(exp) if exp != data.public_key_hex =>
      return star_outcome(
        BadSignature,
        "清单 public_key_hex 与钉死的期望公钥不符（可能是别处签发的清单）",
        data.list.length(),
        now_epoch,
      )
    _ => ()
  }
  let pub_key = match hex_decode(data.public_key_hex) {
    Ok(b) => b
    Err(e) =>
      return star_outcome(
        BadSignature,
        "public_key_hex 不是合法 hex: \{e}",
        data.list.length(),
        now_epoch,
      )
  }
  let sig = match hex_decode(data.signature_hex) {
    Ok(b) => b
    Err(e) =>
      return star_outcome(
        BadSignature,
        "signature_hex 不是合法 hex: \{e}",
        data.list.length(),
        now_epoch,
      )
  }
  let msg = canonical.to_bytes()
  if not(@mooncry.ed25519_verify(pub_key, msg, sig)) {
    return star_outcome(
      BadSignature,
      "Ed25519 验签失败（清单可能被篡改）",
      data.list.length(),
      now_epoch,
    )
  }
  // ④ 时间层：now == issued_at + ttl 仍有效（严格大于才过期）
  if now_epoch > data.issued_at + data.ttl_seconds {
    return star_outcome(
      Stale,
      "清单已过期（now > issued_at + ttl_seconds）",
      data.list.length(),
      now_epoch,
    )
  }
  // ⑤ 名单：验签通过只说明「这份清单确实是持私钥方签的」，但用户可能不在名单里
  if not(data.list.contains(user_login)) {
    return star_outcome(
      NoSuchUser,
      "user_login 不在授权名单里",
      data.list.length(),
      now_epoch,
    )
  }
  star_outcome(
    Valid,
    "验签通过，login 在名单内且未过期",
    data.list.length(),
    now_epoch,
  )
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

///|
/// Star 门路由门禁策略（纯计算、零 IO）。env 读取在 IO 层（model_router_ops）做完后把值传进来，
/// 本函数只做三态判定，可在 router 包内单测（star_gate_wbtest）。
///
/// 三态：
///   - `pinned_key_hex` 为空 → **门未启用**，`free_pool_unlocked=true`（保持现状不设门），note 是告警；
///   - `pinned_key_hex` 非空但 `attestation_json` 为空 → **门启用但 fail-closed**，`free_pool_unlocked=false`；
///   - 两者齐备 → 走 `star_gate_verify_pinned`，按 verdict 决定放行/拦截。
///
/// 为什么「未配置」放行而不是 fail-closed：这是单用户本地工具，默认没设公钥时若 fail-closed
/// 会直接把免费池锁死（等价于「装完就不能用」），是不可接受的默认降级。正确做法是把选择权交给
/// 部署者——**想用 Star 门才配置公钥**；未配置只打明显告警（note 会进 model_route 的 warnings）。
pub struct StarGatePolicyResult {
  /// 是否启用 Star 门（是否配置了钉死公钥）
  gate_enabled : Bool
  /// 免费池是否解锁（可放行）
  free_pool_unlocked : Bool
  /// 人可读说明（未启用时是告警，启用未放行时是失败原因）
  note : String
  /// 验签 verdict（门未启用或未提供 attestation 时缺省）
  verdict : StarVerdict?
} derive(Eq, Debug)

///|
pub fn StarGatePolicyResult::to_json(self : StarGatePolicyResult) -> Json {
  let v = match self.verdict {
    Some(x) => Json::string(x.to_string())
    None => Json::null()
  }
  Json::object({
    "gate_enabled": Json::boolean(self.gate_enabled),
    "free_pool_unlocked": Json::boolean(self.free_pool_unlocked),
    "note": Json::string(self.note),
    "verdict": v,
  })
}

///|
pub fn star_gate_policy(
  pinned_key_hex : String,
  attestation_json : String,
  user_login : String,
  now_epoch : Int64,
) -> StarGatePolicyResult {
  if pinned_key_hex.is_empty() {
    return {
      gate_enabled: false,
      free_pool_unlocked: true,
      note: "Star 门未启用：未配置钉死公钥（FIST_STAR_GATE_PUBKEY_HEX）。免费池保持现状不设门；要启用请配置公钥并传入 attestation",
      verdict: None,
    }
  }
  if attestation_json.is_empty() {
    return {
      gate_enabled: true,
      free_pool_unlocked: false,
      note: "Star 门已启用但未提供 attestation（fail-closed，未放行）：请从 GitHub Pages 拉取 attestation.json 后传入",
      verdict: None,
    }
  }
  let o = star_gate_verify_pinned(
    attestation_json, user_login, now_epoch, pinned_key_hex,
  )
  match o.verdict {
    Valid =>
      {
        gate_enabled: true,
        free_pool_unlocked: true,
        note: "Star 门验签通过：" + o.reason,
        verdict: Some(o.verdict),
      }
    _ =>
      {
        gate_enabled: true,
        free_pool_unlocked: false,
        note: "Star 门未放行：" + o.reason,
        verdict: Some(o.verdict),
      }
  }
}
