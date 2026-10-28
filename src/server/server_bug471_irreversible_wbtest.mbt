// ============================================================================
// BUG-471 第 1 批：`delete` / `archive` 的身份门（**都是不可逆操作**）
//
// ★ 本单的核心发现（推翻了「delete 才不可逆」的直觉）：
//   `src/core/core_task.mbt:547` —— `Task::reopen` 对 `Archived` **明确拒绝**：
//     `Archived => Err("已归档任务不可 reopen，请重新发布")`
//   ⇒ **归档也无法恢复原任务**（只能重新发布，丢掉历史 id 与子树关联）。
//   ⇒ `archive` 与 `delete` **都不可逆** ⇒ **同强度门**。
//
// 四格：
//   锁1 内存后端未传身份 ⇒ 放行（**零回归**契约）
//   锁2 sqlite 未授权 ⇒ 拒（**加严**）
//   锁3 sqlite 授权 ⇒ 放
//   锁4 实现路径格：两个 handler 都真的接了门（strip_ws 归一化，防 fmt 假红）
// ============================================================================

///|
/// 【门·锁 1】**零回归**：内存后端 + 未传身份 ⇒ `agent_write_gate` 放行。
///
/// 这是「既有测试不受影响」的依据 —— 全仓绝大多数测试跑在内存后端上。
test "co_01_memory_backend_open_for_both" {
  let eng = @engine.FistEngine::new(store=@store.StoreBackend::memory())
  // delete：未传 agent ⇒ 空串 ⇒ 兜底 "manual"
  let d_id = acl_claim_identity("", "")
  match agent_write_gate(eng, d_id, "any-ns") {
    Ok(_) => ()
    Err(e) =>
      abort(
        "内存后端 delete 的门应放行（零回归），实际 Err：" + e,
      )
  }
  // archive：未传 by ⇒ 缺省 human_steward
  let a_id = acl_claim_identity("human_steward", "human_steward")
  match agent_write_gate(eng, a_id, "any-ns") {
    Ok(_) => ()
    Err(e) =>
      abort(
        "内存后端 archive 的门应放行（零回归），实际 Err：" +
        e,
      )
  }
}

///|
/// 【门·锁 2/3】★ **sqlite 双向**：未授权拒、授权放。
///
/// 这是「门真的会拒」的核心证据 —— 走完整 `agents_acl_grant` → `agents_acl_check`
/// 真链路，不是断言源码字面。
test "co_02_sqlite_denies_then_allows" {
  let db = "temp/bug471_irreversible_wbtest.db"
  match @store.SqliteStore::open(db) {
    None => fail("open bug471 wbtest db failed")
    Some(store) => {
      let eng = @engine.FistEngine::new(
        store=@store.StoreBackend::sqlite(store),
      )
      assert_eq(eng.heartbeat_backend(), "sqlite")
      let ns = "bug471-wbtest"
      let now = "2026-10-28T12:00:00Z"
      // delete 的身份（新增 agent 参数）
      let d_id = acl_claim_identity("deleter-1", "deleter-1")
      // ① 归零基线：显式收权（fail-closed 起点）
      ignore(
        eng.agents_acl_grant(
          agent_id=d_id.fp(),
          ns~,
          can_read=true,
          can_write=false,
          pid_bound=false,
          now~,
          by="selftest",
        ),
      )
      ignore(eng.agents_acl_ensure(agent_id=d_id.fp(), ns~, now~))
      // ★ 未授权 ⇒ 必须拒（delete 的物理删除不该被任意人触发）
      if not(agent_write_gate(eng, d_id, ns) is Err(_)) {
        abort(
          "未授权身份竟通过了 delete 的门 —— BUG-471 未修（任何人可物理删除任务）",
        )
      }
      // ② 授权 ⇒ 放
      ignore(
        eng.agents_acl_grant(
          agent_id=d_id.fp(),
          ns~,
          can_read=true,
          can_write=true,
          pid_bound=false,
          now~,
          by="human_steward",
        ),
      )
      if not(agent_write_gate(eng, d_id, ns) is Ok(_)) {
        abort("已授权身份被拒 —— 门太严，会误伤正当删除")
      }
    }
  }
}

///|
/// 【门·锁 4】★ **实现路径格**：`delete` 与 `archive` 的 handler**都真的接了门**。
///
/// 判例-29：测了 `agent_write_gate` 本身 ≠ 测了两个 handler 接上了它。
/// 判例-30/34 防护：**逐行扫跳过注释** + `strip_ws` 归一化（防 `moon fmt` 重排假红）。
test "co_03_both_handlers_are_wired" {
  let raw = @fs.read_file_to_string("src/server/server.mbt") catch {
    _ => abort("读不到 server.mbt")
  }
  let mut code = ""
  for line in raw.split("\n") {
    let s = line.to_string()
    let l = s.trim()
    if l.has_prefix("///") || l.has_prefix("//") {
      continue
    }
    code = code + s + "\n"
  }
  // 期望的接线形状（各自的身份来源不同，这正是「不能照抄」的地方）
  let cases : Array[(String, String)] = [
    ("delete", "agent_write_gate(eng,acl_claim_identity(agent,agent),ns)"),
    ("archive", "agent_write_gate(eng,acl_claim_identity(by,by),ns)"),
  ]
  for c in cases {
    let (tool, expect) = c
    let i = match co_find(code, "\"" + tool + "\",", 0) {
      Some(x) => x
      None => abort("找不到工具：" + tool)
    }
    let rest = co_slice(code, i, i + 6000)
    let j = match co_find(rest, "s1 = instrumented_tool(", 0) {
      Some(x) => x
      None => rest.length()
    }
    let blk = co_slice(rest, 0, j)
    let flat = co_strip_ws(blk)
    if not(flat.contains(expect)) {
      abort(
        tool +
        " 的 handler **没有**接 ACL 门，或身份来源不对。" +
        "期望形状（去空白）：" +
        expect,
      )
    }
  }
}

// ── 小工具 ──────────────────────────────────────────────────────────────

///|
fn co_strip_ws(s : String) -> String {
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
fn co_find(hay : String, needle : String, from : Int32) -> Int32? {
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
fn co_slice(s : String, from : Int32, to : Int32) -> String {
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
