// ============================================================================
// BUG-472 / BUG-473：**死参数**普查的锁
//
// 派单称两处「声明了但不验」：
//   BUG-472  `plan` 的 challenge / challenge_sig
//   BUG-473  `execute` 的 agent
//
// ★ 本单核实结果：
//   · BUG-472 **成立** —— `plan` 引擎不经过角色取数面 ⇒ 该字段已**摘掉**（不是接线）
//   · BUG-473 **不成立（误报）** —— `execute` 的 agent 由 `execute_write_identity`
//     读取（`get_str(args, "agent")`），Gamma 的探针没覆盖到那个辅助函数
//
// 判例-30/34 防护：**逐行扫跳注释** + 用**工具块边界**切分（不靠固定行窗口
// —— 本单实测：我用「起始行 +230」的窗口扫 agent_register_key，
//   漏掉了 270 行处的 `get_str(args,"proof_sig")`，差点把正确实现判成死参数）。
// ============================================================================

///|
/// 【死参数·锁 1】★ **`plan` 不该再声明 `challenge` / `challenge_sig`**。
///
/// 理由：`FistEngine::plan` **不经过角色取数面**（`judged_role*` 出现 0 次）⇒
/// 声明了也没人读 = 死参数（判例-29 的第三种「假接线」）。
///
/// 这也是「接线 vs 摘掉」的判据：**引擎有没有读者**。
/// 变异（把 challenge 加回 plan 的 schema）⇒ 本格红。
test "cr_01_plan_must_not_declare_challenge" {
  let raw = @fs.read_file_to_string("src/server/server.mbt") catch {
    _ => abort("读不到 server.mbt")
  }
  let blk = cr_tool_block(raw, "plan")
  if cr_has_code(blk, "challenge") {
    abort(
      "plan 的 schema 又声明了 challenge/challenge_sig —— " +
      "但它的引擎不经过角色取数面，没人会读这个参数（死参数）。" +
      "要么先给 plan 加身份门，再接 challenge（顺序不能反）。",
    )
  }
}

///|
/// 【死参数·锁 2】★ **`plan` 的引擎确实不经过角色取数面**（摘掉 schema 的依据）。
///
/// 这条把「为什么摘掉」钉成可执行断言：若将来 `FistEngine::plan` 真加了角色门，
/// 本格会红 ⇒ 提醒「现在该按 claim 的做法接 challenge 了」。
test "cr_02_plan_engine_has_no_role_gate" {
  let raw = @fs.read_file_to_string("src/engine/engine.mbt") catch {
    _ => abort("读不到 engine.mbt")
  }
  let body = cr_func_body(raw, "pub fn FistEngine::plan(")
  if body.length() == 0 {
    abort("切不到 FistEngine::plan 函数体 —— 本格没跑到被测面")
  }
  for needle in ["judged_role(", "judged_role_gated(", "judged_role_with_nonce("] {
    if cr_has_code(body, needle) {
      abort(
        "FistEngine::plan 里出现了 `" + needle + "` —— 它已接入角色取数面！" +
        "那就**应该**给 plan 接 challenge，并更新本文件与 cr_01。",
      )
    }
  }
}

///|
/// 【死参数·锁 3】★ **`execute` 的 `agent` 真的被读**（BUG-473 是误报的锁）。
///
/// 判据：`execute` handler 必须经由 `execute_write_identity` 解析身份，
/// 而该辅助函数里必须有 `get_str(args, "agent")`。
/// **两段都要断言** —— 只看 handler 会漏（gamma 的探针就是这么漏的）。
test "cr_03_execute_agent_is_actually_read" {
  let raw = @fs.read_file_to_string("src/server/server.mbt") catch {
    _ => abort("读不到 server.mbt")
  }
  // ① handler 里调了 identity 链
  let handler = cr_tool_block(raw, "execute")
  if not(cr_has_code(handler, "execute_write_identity(")) {
    abort(
      "execute 的 handler 没调 execute_write_identity —— 身份解析链断了",
    )
  }
  // ② 辅助函数里真读了 agent
  let helper = cr_func_body(raw, "fn execute_write_identity(")
  if helper.length() == 0 {
    abort("切不到 execute_write_identity —— 本格没跑到被测面")
  }
  if not(cr_has_code(helper, "get_str(args, \"agent\")")) {
    abort(
      "execute_write_identity 里没有 get_str(args, \"agent\") —— " +
      "那 BUG-473（agent 是死参数）就**成立**了，请重新评估。",
    )
  }
}

// ── 小工具（按**工具块边界**切分，不用固定行窗口）────────────────────────

///|
/// 跳注释行，只留代码面。
fn cr_code_only(raw : String) -> String {
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
/// 在代码面里查 needle。
fn cr_has_code(raw : String, needle : String) -> Bool {
  cr_code_only(raw).contains(needle)
}

///|
/// 切出某工具块：从 `"<name>",` 到**下一个** `s1 = instrumented_tool(` 之前。
///
/// ⚠️ 不用「起始行 + N 行」的固定窗口 —— 本单实测：
/// 用 +230 窗口扫 `agent_register_key` 时漏掉了 270 行处的 `get_str(args,"proof_sig")`，
/// **差点把正确实现判成死参数**（判例-32「探针先在新样本上标定」同族）。
fn cr_tool_block(raw : String, name : String) -> String {
  let marker = "\"" + name + "\","
  let i = match cr_find(raw, marker, 0) {
    Some(x) => x
    None => abort("找不到工具：" + name)
  }
  let rest = cr_slice(raw, i + 1, raw.length())
  let j = match cr_find(rest, "s1 = instrumented_tool(", 0) {
    Some(x) => x
    None => rest.length()
  }
  cr_slice(rest, 0, j)
}

///|
/// 切出某函数体：从签名到下一个 `\npub fn ` 或 `\nfn ` 之前。
fn cr_func_body(raw : String, sig : String) -> String {
  let i = match cr_find(raw, sig, 0) {
    Some(x) => x
    None => return ""
  }
  let rest = cr_slice(raw, i + 1, raw.length())
  let a = match cr_find(rest, "\npub fn ", 0) {
    Some(x) => x
    None => rest.length()
  }
  let b = match cr_find(rest, "\nfn ", 0) {
    Some(x) => x
    None => rest.length()
  }
  let end = if a < b { a } else { b }
  cr_slice(rest, 0, end)
}

///|
fn cr_find(hay : String, needle : String, from : Int) -> Int? {
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
fn cr_slice(s : String, from : Int, to : Int) -> String {
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
