// ============================================================================
// BUG-430 / S3 **第四段**：`agent_register_key` 工具的实现路径锁
//
// 病灶（我在变异实测中发现的）：工具写好了，但**没有锁** ——
// 把 `agent_touch_first_seen` 里的 `pubkey_fp=pubkey_hex` 改回 `""`（BUG-403 死承诺原状），
// **424/424 全绿，一格都没抓到**，因为工具本身没被测过。
//
// ⇒ 判例-29「机制格 ≠ 实现路径格」的又一实例：
//    引擎层的 s3_key_* 锁证明「有公钥就能过」，但没证明「工具真的把公钥写进去了」。
//
// 判例-30 防护：断言前先跳过注释行。
// ============================================================================

///|
/// 去掉注释行的源码（只留代码面）。
fn srv_code_only(src : String) -> String {
  let mut acc = ""
  for line in src.split("\n") {
    let s = line.to_owned()
    let l = s.trim()
    if l.has_prefix("///") || l.has_prefix("//") {
      continue
    }
    acc = acc + s + "\n"
  }
  acc
}

///|
/// 【工具·锁 1】`agent_register_key` 工具**存在**且登记了 schema。
test "s3_keytool_01_tool_is_registered" {
  let raw = @fs.read_file_to_string("src/server/server.mbt") catch {
    _ => abort("读不到 server.mbt")
  }
  let src = srv_code_only(raw)
  assert_true(src.contains("\"agent_register_key\""))
  // 三个必填参数都在 schema 里
  assert_true(src.contains("\"pubkey_hex\": string_prop("))
  assert_true(src.contains("[\"agent_id\", \"namespace\", \"pubkey_hex\"]"))
}

///|
/// 【工具·锁 2】★ **`agent_touch_first_seen` 真的把公钥写进 `agents_register`**
/// （实现路径格 —— 变异实测中唯一能抓到「公钥录入被删」的格）。
///
/// 断言代码面里出现 `pubkey_fp=pubkey_hex`（不是 `pubkey_fp=""`）。
test "s3_keytool_02_pubkey_is_actually_written" {
  let raw = @fs.read_file_to_string("src/server/server.mbt") catch {
    _ => abort("读不到 server.mbt")
  }
  let src = srv_code_only(raw)
  // ① 必须把 pubkey_hex 传给 agents_register
  if !src.contains("pubkey_fp=pubkey_hex") {
    abort(
      "agent_touch_first_seen 没有把 pubkey_hex 写进 agents_register —— " +
      "公钥录入是死承诺（BUG-403 原状）",
    )
  }
  // ② 反向断言：`agent_touch_first_seen` 那条路径不许再出现恒空串（那正是变异形状）。
  //    ⚠️ **R24 修：原断言扫全文件，但 `agent_revoke_key` 会「合法地」传空串**
  //    （吊销 = 清空公钥，`agents_set_pubkey(agent_id=fp, pubkey_fp="")`）⇒ 全文件扫描会误伤。
  //    收紧到**形态**：`pubkey_fp="",` 带逗号 = 传给 `agents_register` 的实参（死承诺现场）；
  //    `pubkey_fp="")` 带右括号 = 传给 `agents_set_pubkey` 的末参（吊销，合法）。
  //    只查代码面（`srv_code_only` 已剥注释，注释里讲「此前恒传」的历史不误伤）。
  if src.contains("pubkey_fp=\"\",") {
    abort(
      "`agent_touch_first_seen` 仍在给 agents_register 传 pubkey_fp=\"\" —— 公钥录入被退回死承诺",
    )
  }
}

///|
/// 【工具·锁 3】工具**在落库前校验公钥形状**（32 字节），坏公钥不许进库。
///
/// 为什么重要：坏公钥一旦进库，症状是「这个 agent 永远认证失败」——
/// 而失败信息只有 `challenge_failed`，极难反查到「当初公钥就录错了」。
test "s3_keytool_03_pubkey_shape_is_validated" {
  let raw = @fs.read_file_to_string("src/server/server.mbt") catch {
    _ => abort("读不到 server.mbt")
  }
  let src = srv_code_only(raw)
  assert_true(src.contains("pk.length() != 32"))
  assert_true(src.contains("hex_to_bytes_or(pubkey_hex)"))
}

///|
/// 【工具·锁 4】★ **服务端没有「代签」能力**（安全底线）。
///
/// 断言 `server.mbt` 的**代码面**里**不出现** `ed25519_sign`。
/// 服务端代签 = 服务端自己给自己发通行证 = 绕过 S3。
///
/// 只允许 `ed25519_verify`（验）与 `ed25519_public_key`（测试夹具里派生公钥，
/// 但那是 wbtest 文件，不在 server.mbt 里）。
test "s3_keytool_04_server_never_signs" {
  let raw = @fs.read_file_to_string("src/server/server.mbt") catch {
    _ => abort("读不到 server.mbt")
  }
  let src = srv_code_only(raw)
  if src.contains("ed25519_sign") {
    abort(
      "server.mbt 的代码面里出现了 ed25519_sign —— " +
      "服务端**不许**代签（那等于自己给自己发通行证，绕过 S3）",
    )
  }
  // 但验签必须在（否则 S3 无从生效）—— 验签在引擎包里，这里只确认 server 不签
}
