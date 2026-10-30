// ============================================================================
// BUG-471 批 2 + 批 3：7 个生命周期工具的身份门
//   批2（质量闸门）：submit / reject
//   批3（状态类）：  plan / retry / pause / resume / reopen_task
//
// ★ 门的两类依据（**不是所有门都同强度**）：
//   · 质量闸门（submit/reject）：与 `verify` **对称** —— 都是「对任务结论负责」
//     ⇒ 同一道 ACL 写门，理由见 submit 处的注释。
//   · 状态类（plan/retry/pause/resume/reopen_task）：改变的是**流转状态**，
//     不产出「质量结论」⇒ 同一道门，但**不额外加强**（没有 K of N 之类的附加要求）。
//
// 三格：
//   锁1 七个 handler 都真的接了门（实现路径格，各自断言各自的身份来源）
//   锁2 sqlite 双向：未授权拒、授权放（真链路）
//   锁3 零回归：内存后端 + 未传身份 ⇒ 放行
// ============================================================================

///|
/// 【门·锁 1】★ **实现路径格**：7 个 handler 各自接了门，且**身份来源正确**。
///
/// `reject` / `plan` 复用 `by`；其余 5 个（submit/retry/pause/resume/reopen_task）
/// 新增 `agent`。**用两组不同的期望串**断言 —— 这正是「不能一刀切」的地方。
///
/// 判例-30/34 防护：逐行扫跳注释 + `strip_ws` 归一化（防 `moon fmt` 重排假红）。
test "ct_01_seven_handlers_wired" {
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
  // (工具, 期望的门接线形状)
  let by_group : Array[String] = ["reject", "plan"]
  let agent_group : Array[String] = [
    "submit", "retry", "pause", "resume", "reopen_task",
  ]
  for tool in by_group {
    let blk = ct_block(code, tool)
    let flat = ct_strip_ws(blk)
    if !flat.contains("agent_write_gate(eng,acl_claim_identity(by,by),ns)") {
      abort(tool + " 没接门（或身份来源不是 by）")
    }
  }
  for tool in agent_group {
    let blk = ct_block(code, tool)
    let flat = ct_strip_ws(blk)
    if !flat.contains(
        "agent_write_gate(eng,acl_claim_identity(agent,agent),ns)",
      ) {
      abort(tool + " 没接门（或身份来源不是 agent）")
    }
  }
}

///|
/// 【门·锁 2】★ **sqlite 双向**：未授权 ⇒ 拒；授权 ⇒ 放。
///
/// 走完整 `agents_acl_grant` → `agents_acl_check` 真链路。
/// 只要这条成立，7 个工具共用的 `agent_write_gate` 就会对它们都生效
/// （它们传的是**同一个**门函数，锁 1 已断言接线）。
test "ct_02_sqlite_gate_denies_then_allows" {
  let db = "temp/bug471_b23_wbtest.db"
  match @store.SqliteStore::open(db) {
    None => fail("open bug471 b23 wbtest db failed")
    Some(store) => {
      let eng = @engine.FistEngine::new(
        store=@store.StoreBackend::sqlite(store),
      )
      assert_eq(eng.heartbeat_backend(), "sqlite")
      let ns = "bug471-b23"
      let now = "2026-10-28T13:00:00Z"
      let id = acl_claim_identity("lane-ct-agent", "lane-ct-agent")
      // ① 收权 ⇒ 拒
      ignore(
        eng.agents_acl_grant(
          agent_id=id.fp(),
          ns~,
          can_read=true,
          can_write=false,
          pid_bound=false,
          now~,
          by="selftest",
        ),
      )
      ignore(eng.agents_acl_ensure(agent_id=id.fp(), ns~, now~))
      if !(agent_write_gate(eng, id, ns) is Err(_)) {
        abort("未授权身份通过了门 —— 批 2/3 的修复无效")
      }
      // ② 授权 ⇒ 放
      ignore(
        eng.agents_acl_grant(
          agent_id=id.fp(),
          ns~,
          can_read=true,
          can_write=true,
          pid_bound=false,
          now~,
          by="human_steward",
        ),
      )
      if !(agent_write_gate(eng, id, ns) is Ok(_)) {
        abort("已授权身份被拒 —— 门太严")
      }
    }
  }
}

///|
/// 【门·锁 3】**零回归**：内存后端 + 未传身份 ⇒ 放行。
///
/// 这是「既有测试不受影响」的依据：全仓绝大多数测试跑在内存后端。
test "ct_03_memory_backend_zero_regression" {
  let eng = @engine.FistEngine::new(store=@store.StoreBackend::memory())
  // 未传 agent ⇒ 空串 ⇒ 兜底 manual
  match agent_write_gate(eng, acl_claim_identity("", ""), "any-ns") {
    Ok(_) => ()
    Err(e) =>
      abort("内存后端应放行（零回归契约），实际 Err：" + e)
  }
  // reject / plan 未传 by ⇒ 缺省值（各工具自己给的缺省）
  match
    agent_write_gate(
      eng,
      acl_claim_identity("human_steward", "human_steward"),
      "any-ns",
    ) {
    Ok(_) => ()
    Err(e) => abort("内存后端应放行（by 缺省），实际 Err：" + e)
  }
}

// ── 小工具 ──────────────────────────────────────────────────────────────

///|
fn ct_strip_ws(s : String) -> String {
  let mut out = ""
  for ch in s.split("") {
    let c = ch.to_owned()
    if c == " " || c == "\t" || c == "\n" || c == "\r" {
      continue
    }
    out = out + c
  }
  out
}

///|
/// 按**工具块边界**切分（不用固定行窗口 —— 判例-32 的教训）。
fn ct_block(code : String, name : String) -> String {
  let i = match ct_find(code, "\"" + name + "\",", 0) {
    Some(x) => x
    None => abort("找不到工具：" + name)
  }
  let rest = ct_slice(code, i + 1, code.length())
  let j = match ct_find(rest, "s1 = instrumented_tool(", 0) {
    Some(x) => x
    None => rest.length()
  }
  ct_slice(rest, 0, j)
}

///|
fn ct_find(hay : String, needle : String, from : Int32) -> Int32? {
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
fn ct_slice(s : String, from : Int32, to : Int32) -> String {
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
