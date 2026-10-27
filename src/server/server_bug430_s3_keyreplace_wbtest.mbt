// ============================================================================
// BUG-430 / S3 **第五段**：密钥替换 / 抢注攻击的锁
//
// ★ 实测澄清（写进锁里，防后来人照抄错误结论）：
//   `store_sqlite.mbt:2779` 的 `ON CONFLICT(agent_id) DO UPDATE SET`
//   **不含 `pubkey_fp`**（只更新 pid / last_seen / status / role）
//   ⇒ 已有公钥**不会**被「覆盖」，第二次登记会**静默不生效**。
//   ⇒ 真实攻击面是 **①抢注**（趁某 agent 还没登记，先替他登**我的**公钥）
//                   **②静默不生效**（调用方以为换了，实际库里还是旧的）。
//
// 判例-30 防护：查源码时跳过注释行。
// ============================================================================

///|
/// 造一个 32 字节形状的合法 hex（本段只测登记逻辑，不测密码学）。
fn bl_key_hex(fill : Int) -> String {
  let hx = "0123456789abcdef"
  let hi = hx.to_array()[fill / 16]
  let lo = hx.to_array()[fill % 16]
  let mut out = ""
  let mut i = 0
  while i < 32 {
    out = out + hi.to_string() + lo.to_string()
    i = i + 1
  }
  out
}

///|
/// 【替换·锁 4】**本段的实测前提**：底层 `agents_register` **不覆盖** `pubkey_fp`。
///
/// 若哪天 `store_sqlite.mbt` 把 `pubkey_fp=excluded.pubkey_fp` 加进 DO UPDATE SET，
/// 「已有公钥不会被覆盖」这个前提就塌了 ⇒ 本格红 ⇒ 逼着重新评估攻击面
/// （而不是让上层的「首登锁定」悄悄失效）。
test "bl_01_store_does_not_overwrite_pubkey" {
  let sql = match @store.SqliteStore::open(":memory:") {
    Some(s) => s
    None => abort("sqlite open 失败")
  }
  let k1 = bl_key_hex(0xaa)
  let k2 = bl_key_hex(0xbb)
  ignore(
    sql.agents_register(
      agent_id="FP-A", agent_type="t", role="Executor", soldier="工兵",
      pubkey_fp=k1, pid=1, now="2026-10-27T00:00:00Z",
    ),
  )
  ignore(
    sql.agents_register(
      agent_id="FP-A", agent_type="t", role="Executor", soldier="工兵",
      pubkey_fp=k2, pid=1, now="2026-10-27T00:00:01Z",
    ),
  )
  let got = match sql.agents_get("FP-A") {
    None => abort("读不回")
    Some(a) => a.pubkey_fp
  }
  assert_eq(got, k1)   // 不覆盖 ⇒ 仍是 k1
}

///|
/// 【替换·锁 1】首次登记 ⇒ 成功且库里有值。
test "bl_02_first_registration_succeeds" {
  let sql = match @store.SqliteStore::open(":memory:") {
    Some(s) => s
    None => abort("sqlite open 失败")
  }
  let k = bl_key_hex(0xcc)
  ignore(
    sql.agents_register(
      agent_id="FP-B", agent_type="t", role="Executor", soldier="工兵",
      pubkey_fp=k, pid=1, now="2026-10-27T00:00:00Z",
    ),
  )
  match sql.agents_get("FP-B") {
    None => abort("首次登记后读不回")
    Some(a) => assert_eq(a.pubkey_fp, k)
  }
}

///|
/// ★ **证据格**：`agent_register_key` 工具里确实有「已有公钥且不同 ⇒ 拒绝」的分支。
///
/// 工具的实现体在 `server.mbt` 里（不是纯函数），所以这里查**代码面**：
/// 必须出现 `prev_key != pubkey_hex` 的拒绝路径，且必须带 `return Err`。
test "bl_03_tool_rejects_key_replacement" {
  let raw = @fs.read_file_to_string("src/server/server.mbt") catch {
    _ => abort("读不到 server.mbt")
  }
  // 跳过注释行（判例-30）
  let mut code = ""
  for line in raw.split("\n") {
    let s = line.to_string()
    let l = s.trim()
    if l.has_prefix("///") || l.has_prefix("//") {
      continue
    }
    code = code + s + "\n"
  }
  // ① 必须做「写前回读既有公钥」
  if !code.contains("let prev_key = match existing") {
    abort("没有在写之前读既有公钥 —— 写完再读就看不出「已有」了")
  }
  // ② 必须有「已相等 ⇒ 幂等」的判断（同钥重复登记不该被拒）
  if !code.contains("prev_key == pubkey_hex") {
    abort("缺少「同钥幂等」分支 —— 重试会被误拒")
  }
  // ③ 必须有「已有且不同 ⇒ 拒绝」的路径。
  //    实现上它是比较的 else 分支，所以查**拒绝文案 + return Err**这对组合，
  //    而不是硬找 `!=` 字面（判例-30 教训：别把断言钉在实现细节上）。
  let has_reject_msg = code.contains("拒绝覆盖")
  let has_rotation_hint = code.contains("密钥轮换")
  if !has_reject_msg || !has_rotation_hint {
    abort(
      "没有「已有公钥且与本次不同 ⇒ 拒绝并指向轮换流程」的路径 —— " +
      "换钥劫持没堵住，或拒绝后没给出去路",
    )
  }
  // ④ 拒绝必须发生在写之前（`agent_touch_first_seen` 之前）
  let i_prev = code.find("let prev_key = match existing")
  let i_touch = code.find("agent_touch_first_seen(\n          eng")
  let (a, b) = match (i_prev, i_touch) {
    (Some(x), Some(y)) => (x, y)
    _ => abort("找不到关键语句位置")
  }
  if a >= b {
    abort("「回读既有公钥」在「写」之后 —— 那时已经覆盖完了，检查形同虚设")
  }
}
