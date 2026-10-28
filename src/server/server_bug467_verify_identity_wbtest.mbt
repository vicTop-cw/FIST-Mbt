// ============================================================================
// BUG-467：`verify` 缺身份门 —— 任何调用方都能验收任何任务
//
// 病灶：`verify` 工具体原只有 `to_result(eng.verify(task_id~, verifier~, …))`
//   ⇒ **无角色门、无 ACL 门**，`verifier` 是自报串
//   ⇒ 任何能调到 MCP 的人都能把未完成任务盖成「已完成」。
//
// 修法：与 `execute` 对齐 —— `agent_write_gate(eng, acl_claim_identity(verifier, verifier), ns)`。
//
// 四格：
//   锁1 已授权 ⇒ 门通过（不与 verify 自身业务闸门混淆）
//   锁2 未授权 ⇒ 门拒绝
//   锁3 零回归：内存后端放行
//   锁4 归一化接线（**断言行内没有空格差异导致的假红**）
// ============================================================================

///|
/// 【verify 门·锁 3】**零回归**：内存后端 `agent_write_gate` 必须放行。
///
/// 这是「既有测试不受影响」的依据 —— 全仓绝大多数测试跑在内存后端上。
test "ci_01_memory_backend_gate_is_open_for_verify" {
  let eng = @engine.FistEngine::new(store=@store.StoreBackend::memory())
  let id = acl_claim_identity("some-verifier", "some-verifier")
  match agent_write_gate(eng, id, "any-ns") {
    Ok(_) => ()
    Err(e) => abort("内存后端 ACL 应放行（零回归契约），实际 Err：" + e)
  }
}

///|
/// 【verify 门·锁 1/2】★ **sqlite 后端：未授权拒、授权放**（真双向）。
///
/// 这是本单的核心证据链：
///   ① 显式收权 can_write=false ⇒ 门拒
///   ② `agents_acl_grant(can_write=true)` ⇒ 门放
///   **两道都用同一个 `acl_claim_identity(verifier, verifier)`** ——
///   与工具实现里的那一行逐字同源，不是另写一份判定。
test "ci_02_sqlite_gate_denies_then_allows" {
  let db = "temp/bug467_verify_identity_wbtest.db"
  match @store.SqliteStore::open(db) {
    None => fail("open bug467 wbtest db failed")
    Some(store) => {
      let eng = @engine.FistEngine::new(
        store=@store.StoreBackend::sqlite(store),
      )
      assert_eq(eng.heartbeat_backend(), "sqlite")
      let ns = "bug467-wbtest"
      let now = "2026-10-28T10:00:00Z"
      // 与工具实现**同一行**的身份解析
      let vid = acl_claim_identity("验收宪兵-1", "验收宪兵-1")
      // ① 归零基线：显式收权（fail-closed 起点）
      ignore(
        eng.agents_acl_grant(
          agent_id=vid.fp(),
          ns~,
          can_read=true,
          can_write=false,
          pid_bound=false,
          now~,
          by="selftest",
        ),
      )
      ignore(eng.agents_acl_ensure(agent_id=vid.fp(), ns~, now~))
      // ★ 未授权 ⇒ 必须拒
      if not(agent_write_gate(eng, vid, ns) is Err(_)) {
        abort(
          "未授权的 verifier 竟通过了 ACL 门 —— BUG-467 未修（任何调用方都能验收任何任务）",
        )
      }
      // ② 授权 ⇒ 通过
      ignore(
        eng.agents_acl_grant(
          agent_id=vid.fp(),
          ns~,
          can_read=true,
          can_write=true,
          pid_bound=false,
          now~,
          by="human_steward",
        ),
      )
      if not(agent_write_gate(eng, vid, ns) is Ok(_)) {
        abort("已授权的 verifier 被拒 —— 门太严，会误伤正当验收")
      }
    }
  }
}

///|
/// 【verify 门·锁 4】★ **实现路径格**：`verify` 工具体**真的调了** ACL 门。
///
/// 判例-29：只测「`agent_write_gate` 这个函数工作」（锁 1/2）**不等于**测了
/// 「`verify` 的 handler 接上了它」。本格直接查源码接线。
///
/// 判例-30/34 防护：**逐行扫、跳过注释**；用 `strip_ws` 归一化再比，
/// 不硬拼跨行字面（本仓被 `moon fmt` 重排过多次）。
test "ci_03_verify_handler_is_wired_to_acl_gate" {
  let raw = @fs.read_file_to_string("src/server/server.mbt") catch {
    _ => abort("读不到 server.mbt")
  }
  // ① 只留代码面（跳过注释行）
  let mut code = ""
  for line in raw.split("\n") {
    let s = line.to_string()
    let l = s.trim()
    if l.has_prefix("///") || l.has_prefix("//") {
      continue
    }
    code = code + s + "\n"
  }
  // ② 定位 verify 的工具块：从 `"verify",` 到下一处 `s1 = instrumented_tool(`
  let i = match find_ci(code, "\"verify\",", 0) {
    Some(x) => x
    None => abort("找不到 verify 工具定义")
  }
  let rest = slice_ci(code, i + 1, i + 6000)
  let j = match find_ci(rest, "s1 = instrumented_tool(", 0) {
    Some(x) => x
    None => rest.length()
  }
  let blk = slice_ci(rest, 0, j)
  // ③ 归一化：去所有空白后再找（防 fmt 重排导致假红）
  let flat = strip_ws(blk)
  if not(flat.contains("agent_write_gate(eng,acl_claim_identity(verifier,verifier),ns)")) {
    abort(
      "verify 的 handler **没有**接 ACL 门（或缺 acl_claim_identity 同源身份解析）。" +
      "只测门函数本身不够 —— 必须断言接线（判例-29）。",
    )
  }
}

// ── 小工具 ──────────────────────────────────────────────────────────────

///|
/// 去掉所有空白字符（空格 / 制表 / 换行）——用于「暴露面归一化」比对，
/// 避免 `moon fmt` 重排造成假红（R24 的教训）。
fn strip_ws(s : String) -> String {
  let mut out = ""
  for ch in s.split("") {
    let c = ch.to_string()
    if c == " " || c == "\t" || c == "\n" || c == "\r" {
      continue
    }
    out = out + c
  }
  out
}

///|
fn find_ci(hay : String, needle : String, from : Int) -> Int? {
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
fn slice_ci(s : String, from : Int, to : Int) -> String {
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
