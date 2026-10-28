// ============================================================================
// BUG-430 / S3 **第六段**：首登也验签 —— 堵抢注
//
// 前五段只保证「登记后不可改」，**没保证「第一次是本人登记的」**。
// 抢注成功 = 攻击者**永久拥有**那个身份（合法持有者反而永远通不过）。
//
// 本段规则（两步）：
//   ① 不带 challenge ⇒ 只签发挑战，**不改库**
//   ② 带 challenge + proof_sig ⇒ 验签通过**才**落库
//
// ⚠️ challenge 必须**服务端签发**（调用方自选 ⇒ 可离线预计算并预先签好 ⇒ 验签失效）
//
// 判例-30 防护：查源码时跳过注释行。
// ============================================================================

///|
fn bs_code_only(raw : String) -> String {
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
fn bs_block(src : String, name : String) -> String {
  let i = match bs_find(src, "\"" + name + "\",", 0) {
    Some(x) => x
    None => abort("找不到工具：" + name)
  }
  bs_slice(src, i, i + 9000)
}

///|
/// 【抢注·锁 1】第一步（不带 challenge）**只签发挑战、不改库**。
///
/// 关键断言：回执里 `mode == "challenge_issued"`、带 `challenge`、
/// 且**明确写 `registered: false`** —— 否则调用方会误以为已经登记。
test "bs_01_phase1_issues_challenge_without_writing" {
  let raw = @fs.read_file_to_string("src/server/server.mbt") catch {
    _ => abort("读不到 server.mbt")
  }
  let src = bs_code_only(raw)
  let blk = bs_block(src, "agent_register_key")
  if !blk.contains("\"mode\": Json::string(\"challenge_issued\")") {
    abort("第一步没有标明 mode=challenge_issued")
  }
  if !blk.contains("\"challenge\": Json::string(issued)") {
    abort("第一步没有把 challenge 返回给调用方")
  }
  if !blk.contains("\"registered\": Json::boolean(false)") {
    abort("第一步没有明确 registered=false —— 调用方会误以为已登记")
  }
  // 第一步必须**在写库之前** return
  let i_issue = match bs_find(blk, "eng.s3_issue_challenge_auto(", 0) {
    Some(x) => x
    None => abort("第一步没调 s3_issue_challenge_auto —— challenge 不是服务端签发的")
  }
  let i_touch = match bs_find(blk, "agent_touch_first_seen(", 0) {
    Some(x) => x
    None => abort("找不到写库调用")
  }
  if i_issue >= i_touch {
    abort("签发挑战发生在写库之后 —— 顺序错了")
  }
}

///|
/// 【抢注·锁 2】传了 challenge 但没传 proof_sig ⇒ **拒绝**。
test "bs_02_challenge_without_proof_rejected" {
  let raw = @fs.read_file_to_string("src/server/server.mbt") catch {
    _ => abort("读不到 server.mbt")
  }
  let blk = bs_block(bs_code_only(raw), "agent_register_key")
  if !blk.contains("传了 challenge 却没传 proof_sig") {
    abort("没有「传 challenge 但没传 proof_sig ⇒ 拒绝」的路径")
  }
}

///|
/// 【抢注·锁 3】★ **验签是硬门**：失败一律拒绝，不落库。
///
/// 断言三点：
///   ① 调用 `verify_challenge_sig(pubkey_hex, challenge, proof_sig)`
///      —— **公钥是本次登记的那把**，消息是 **challenge 原文**
///   ② 失败路径是 `return Err`（不是忽略）
///   ③ 验签出现在写库**之前**
test "bs_03_proof_is_verified_before_write" {
  let raw = @fs.read_file_to_string("src/server/server.mbt") catch {
    _ => abort("读不到 server.mbt")
  }
  let blk = bs_block(bs_code_only(raw), "agent_register_key")
  if !blk.contains("@engine.verify_challenge_sig(pubkey_hex, challenge, proof_sig)") {
    abort(
      "没有用「本次要登记的公钥 + challenge 原文」验 proof_sig —— " +
      "验签参数错了就等于没验",
    )
  }
  if !blk.contains("首登验签失败") {
    abort("验签失败没有明确拒绝文案")
  }
  let i_verify = match bs_find(blk, "@engine.verify_challenge_sig(", 0) {
    Some(x) => x
    None => abort("找不到验签调用")
  }
  let i_touch = match bs_find(blk, "agent_touch_first_seen(", 0) {
    Some(x) => x
    None => abort("找不到写库调用")
  }
  if i_verify >= i_touch {
    abort("验签在写库之后 —— 那时已经落库了，验签形同虚设")
  }
}

///|
/// 【抢注·锁 4】★ **challenge 必须服务端签发**（用 `s3_issue_challenge_auto`，
/// 计数器由服务端 `Ref` 单调递增，不给调用方）。
///
/// 为什么这条是独立的格：若实现改成「接受调用方传的 challenge」（不查是不是自己发的），
/// 攻击者就能自己选 challenge + 自己签 ⇒ **验签完全失效**，但前面几条锁**都还是绿的**。
/// 本格钉的是「签发权在服务端」这个前提。
test "bs_04_challenge_is_server_issued" {
  let raw = @fs.read_file_to_string("src/server/server.mbt") catch {
    _ => abort("读不到 server.mbt")
  }
  let blk = bs_block(bs_code_only(raw), "agent_register_key")
  if !blk.contains("eng.s3_issue_challenge_auto(") {
    abort("没有用服务端自选计数器的 s3_issue_challenge_auto —— challenge 可能由调用方自选")
  }
  // 引擎侧必须用 Ref 计数器（不是纯函数直出）
  let eng = @fs.read_file_to_string("src/engine/engine_rsv.mbt") catch {
    _ => abort("读不到 engine_rsv.mbt")
  }
  let eng_code = bs_code_only(eng)
  if !eng_code.contains("let s3_challenge_counter : Ref[Int32]") {
    abort("引擎侧没有进程级单调计数器 —— 调用方可预计算 nonce")
  }
  if !eng_code.contains("s3_challenge_counter.val = ") {
    abort("计数器没有递增 —— 每个 challenge 的 nonce 会相同")
  }
}

// ── 小工具 ──────────────────────────────────────────────────────────────

///|
fn bs_find(hay : String, needle : String, from : Int) -> Int? {
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
fn bs_slice(s : String, from : Int, to : Int) -> String {
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
