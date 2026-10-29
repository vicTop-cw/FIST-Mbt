// ============================================================================
// BUG-477 / BUG-478：S3 门的两个不一致
//
// BUG-477：`rsv_try_set` / `locks_try_acquire` 走 `judged_role_gated`（**只验签、
//  不消费 nonce**）⇒ 同一张票可**无限重放**（实测：首次与重复用票回执完全相同）。
//   修法：改用 `judged_role_with_nonce`（与 `claim` 同源，验签通过后消费）。
//   ⚠️ **不能把消费塞进 `judged_role_gated`** —— 它被 5 处消费（含只读的
//   `challenge_pending_count`），塞进去会让那 5 处全变成「读一次就消费」。
//
// BUG-478：`reserve_*` / `lock_*` 六工具**不接受 namespace、不调 `engine_for_ns`**，
//   而公钥按 ns 隔离 ⇒ **非 default ns 的票一定验不过**。
//   修法：七工具全加 `namespace` + `engine_for_ns` 路由（零回归：不传 ⇒ default ⇒ 主引擎）。
// ============================================================================

///|
/// 【BUG-477·锁 1】★ **两个门真的会消费 nonce**（端到端，不是断言源码）。
///
/// 做法：登记公钥 → 取票 → 真签名 → 第一次通过 → **同一张票再来一次必须被判重放**。
/// 这格测的是 `s3_consume_nonce` 真的被调到，且**跨调用**有效。
test "df_01_rsv_and_lock_consume_nonce_across_calls" {
  let agent = "df-agent"
  let eng = bz_eng_with_key(agent, bz_pub_a())
  let nonce = eng.s3_issue_challenge_auto(agent)
  let sig = bz_sign(bz_seed_a(), nonce)
  // ══════════════════════════════════════════════════════════════════════
  // ★ **必须走真实引擎函数 `rsv_try_set`**，不能直接调 `judged_role_with_nonce`。
  //
  // 第一版我直接调门函数 —— 结果变异实测暴露了缺陷：
  // 把 `rsv_try_set` 退回 `judged_role_gated` 时，**本格照样绿**
  // （红的只有别处的形态计数锁）。因为「门函数会消费」是对的，
  // **但被测的是「消费者接的是哪一个门」** —— 判例-29 的老坑：
  // **测了机制 ≠ 测了实现路径**。
  // ══════════════════════════════════════════════════════════════════════
  let r1 = eng.rsv_try_set(
    scope="df/scope",
    agent~,
    ttl_until="2026-10-29T23:59:59Z",
    created_at="2026-10-29T00:00:00Z",
    challenge_nonce=Some(nonce),
    challenge_sig=Some(sig),
  )
  let rs1 = match r1 {
    Ok(o) => o.action
    Err(e) => abort("首次 rsv_try_set 失败：" + e)
  }
  if !(rs1.contains("challenge_verified")) {
    abort("首次应 challenge_verified，实际 `" + rs1 + "`")
  }
  // ② ★ 同一张票再来一次 ⇒ 必须判重放
  let r2 = eng.rsv_try_set(
    scope="df/scope2",
    agent~,
    ttl_until="2026-10-29T23:59:59Z",
    created_at="2026-10-29T00:00:01Z",
    challenge_nonce=Some(nonce),
    challenge_sig=Some(sig),
  )
  let rs2 = match r2 {
    Ok(o) => o.action
    Err(e) =>
      abort(
        "第二次 rsv_try_set 应返回回执(判重放)，实际 Err：" + e,
      )
  }
  if !(rs2.contains("challenge_replayed")) {
    abort(
      "同一张票第二次应判 challenge_replayed，实际 `" +
      rs2 +
      "` —— rsv_try_set 走的是不消费 nonce 的门 = BUG-477 未修",
    )
  }
}

///|
/// 【BUG-477·锁 2】**`judged_role_gated` 本身仍然不消费**（保护那 5 处只读消费者）。
///
/// 这条是「不能把消费塞进门函数」的机器化守卫：
/// 若有人图省事把 `s3_consume_nonce` 塞进 `judged_role_gated`，
/// `challenge_pending_count` 这类只读调用就会把票吃掉 ⇒ 本格会红。
test "df_02_gated_does_not_consume" {
  let agent = "df-agent2"
  let eng = bz_eng_with_key(agent, bz_pub_a())
  let nonce = eng.s3_issue_challenge_auto(agent)
  let sig = bz_sign(bz_seed_a(), nonce)
  // 连调两次 judged_role_gated ⇒ **两次都应 verified**（它不消费）
  let (_a, s1) = judged_role_gated(
    eng,
    agent,
    Some(nonce),
    challenge_sig=Some(sig),
  )
  let (_b, s2) = judged_role_gated(
    eng,
    agent,
    Some(nonce),
    challenge_sig=Some(sig),
  )
  if s1 != "challenge_verified" || s2 != "challenge_verified" {
    abort(
      "`judged_role_gated` 应**只验签不消费**（两次都 verified），实际 " +
      s1 +
      " / " +
      s2 +
      " —— 有人把消费塞进了门函数，会毒害 5 处只读消费者",
    )
  }
}

///|
/// 【BUG-478·锁 3】★ **七个 reserve/lock 工具都有 `namespace` 且都路由**。
///
/// 判例-29：断言的是**接线形态**（schema 有参数 + handler 调 `engine_for_ns`），
/// 不是「引擎函数能工作」——后者锁 2 已覆盖，两段都要。
test "df_03_reserve_lock_tools_route_by_namespace" {
  let raw = @fs.read_file_to_string("src/server/server.mbt") catch {
    _ => abort("读不到 server.mbt")
  }
  let mut code = ""
  for line in raw.split("\n") {
    let s = line.to_owned()
    let l = s.trim()
    if l.has_prefix("///") || l.has_prefix("//") {
      continue
    }
    code = code + s + "\n"
  }
  let tools : Array[String] = [
    "reserve_scope", "reserve_check", "reserve_release", "lock_acquire", "lock_renew",
    "lock_release", "lock_status",
  ]
  for t in tools {
    let blk = df_block(code, t)
    if !(blk.contains("\"namespace\": string_prop")) {
      abort(
        t +
        " 的 schema 没有 namespace 参数 —— 公钥按 ns 隔离 ⇒ 非 default ns 必验不过",
      )
    }
    if !(blk.contains("engine_for_ns(")) {
      abort(
        t +
        " 的 handler 没调 engine_for_ns —— namespace 参数是死参数",
      )
    }
  }
}

// ── 小工具（真 Ed25519，不自造哈希）─────────────────────────────────────

///|
/// 按**工具块边界**切分（判例-32：不用固定行窗口）。
fn df_block(code : String, name : String) -> String {
  let i = match df_find(code, "\"" + name + "\",", 0) {
    Some(x) => x
    None => abort("找不到工具：" + name)
  }
  let rest = df_slice(code, i + 1, code.length())
  let j = match df_find(rest, "s1 = instrumented_tool(", 0) {
    Some(x) => x
    None => rest.length()
  }
  df_slice(rest, 0, j)
}

///|
fn df_find(hay : String, needle : String, from : Int32) -> Int32? {
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
fn df_slice(s : String, from : Int32, to : Int32) -> String {
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
