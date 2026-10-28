// ============================================================================
// 为什么 `execute` / `verify` **不**接 S3 `challenge` / `challenge_sig`
// --- Lane CH 定夺（2026-10-28）
//
// 派单要求「给 execute / verify 接 challenge」。**核完代码后不接**，理由是
// **它们都不经过角色取数面** ⇒ 接了是**死参数**（判例-29 的反面：接一个没人读的参数）。
//
// 判例-30 防护：本文件的源码断言**逐行扫、跳过注释**，
// 不用 `contains` 全文匹配（注释里会讲这些标识符，全文匹配会假阳）。
//
// ⚠️ 这两格的作用是**防将来有人误加**：
//   若哪天 execute/verify 真接入了角色门（那说明设计变了），
//   本格会红，并提醒「四门清单 + S3 覆盖面需要重新评审」——
//   而不是让一个死参数悄悄留在 schema 里。
// ============================================================================

///|
/// 取某函数体的**代码面**（跳过注释行），供源码断言用。
fn ch_code_lines(raw : String) -> Array[String] {
  let out : Array[String] = []
  for line in raw.split("\n") {
    let s = line.to_string()
    let l = s.trim()
    if l.has_prefix("///") || l.has_prefix("//") {
      continue
    }
    out.push(s)
  }
  out
}

///|
/// 取 `Array[String]` 里从 `start_marker` 之后到 `end_marker` 之前的行。
fn ch_slice_between(
  lines : Array[String],
  start_marker : String,
  end_marker : String,
) -> Array[String] {
  let out : Array[String] = []
  let mut started = false
  for l in lines {
    if !started {
      if l.contains(start_marker) {
        started = true
        out.push(l)
      }
      continue
    }
    if l.contains(end_marker) {
      break
    }
    out.push(l)
  }
  out
}

///|
fn ch_contains_line(lines : Array[String], needle : String) -> Bool {
  for l in lines {
    if l.contains(needle) {
      return true
    }
  }
  false
}

///|
/// 【不接·锁 1】★ **`execute_with_meta` 不经过角色取数面**（`judged_role` 出现 0 次）。
///
/// 这条就是「为什么不给 execute 接 challenge」的**唯一依据**：
/// `challenge` 的唯一消费者是 `judged_role_gated` / `judged_role_with_nonce`。
/// 若函数体里根本不调它们，`challenge` 传进去**没有任何读者** ⇒ 死参数。
///
/// 变异（给 execute_with_meta 加一个 judged_role 调用）⇒ 本格红 ⇒ 提醒重新评审。
test "ch_execute_does_not_pass_role_resolution" {
  let raw = @fs.read_file_to_string("src/engine/engine.mbt") catch {
    _ => abort("读不到 engine.mbt")
  }
  let lines = ch_code_lines(raw)
  let body = ch_slice_between(
    lines, "pub fn FistEngine::execute_with_meta(", "\npub fn ",
  )
  if body.length() == 0 {
    abort(
      "切不到 execute_with_meta 函数体 —— 本格没跑到被测面",
    )
  }
  for
    needle in ["judged_role_gated(", "judged_role_with_nonce(", "judged_role("] {
    if ch_contains_line(body, needle) {
      abort(
        "execute_with_meta 里出现了 `" +
        needle +
        "` —— 它已经经过角色取数面了！" +
        "那就**应该**给它接 challenge（并更新本文件与四门清单），而不是继续留成死参数。",
      )
    }
  }
}

///|
/// 【不接·锁 2】★ **`verify` 也不经过角色取数面**。
///
/// `verify` 的门是 `omega_verify_gate` / `gate_verify_gate` / `docs_verify_gate`
/// —— 都是**业务闸门**，不是「你是谁」的门。所以它同样不该接 challenge。
test "ch_verify_does_not_pass_role_resolution" {
  let raw = @fs.read_file_to_string("src/engine/engine.mbt") catch {
    _ => abort("读不到 engine.mbt")
  }
  let lines = ch_code_lines(raw)
  let body = ch_slice_between(lines, "pub fn FistEngine::verify(", "\npub fn ")
  if body.length() == 0 {
    abort("切不到 verify 函数体 —— 本格没跑到被测面")
  }
  for
    needle in ["judged_role_gated(", "judged_role_with_nonce(", "judged_role("] {
    if ch_contains_line(body, needle) {
      abort(
        "verify 里出现了 `" +
        needle +
        "` —— 它已经经过角色取数面了！" +
        "那就**应该**给它接 challenge，并更新本文件与 S3 覆盖面清单。",
      )
    }
  }
  // 反向：确认它的门确实是业务闸门（防止我切错了函数体而误判）
  if !ch_contains_line(body, "omega_verify_gate(") {
    abort(
      "verify 的函数体里看不到 omega_verify_gate —— 可能切错函数体了，本格结论不可信",
    )
  }
}

///|
/// 【不接·锁 3】`execute` / `verify` 的 MCP schema **不该**声明 `challenge` / `challenge_sig`。
///
/// 若将来真接入（锁 1/2 变红），这里也会一起变红 —— 两处同时提醒。
/// 反之，若有人**只加了 schema 没接引擎**（正是 R25 Alpha 发现的「接口与实现分叉」反向版），
/// 本格会红并指出「这是死参数」。
test "ch_tools_do_not_declare_challenge_param" {
  let raw = @fs.read_file_to_string("src/server/server.mbt") catch {
    _ => abort("读不到 server.mbt")
  }
  let lines = ch_code_lines(raw)
  for tool in ["execute", "verify"] {
    // 工具块：从 `"<tool>",` 到下一个 `s1 = instrumented_tool(` 为止
    let marker = "\"" + tool + "\","
    let blk = ch_slice_between(lines, marker, "s1 = instrumented_tool(")
    if blk.length() == 0 {
      abort(
        "切不到 " + tool + " 的工具块 —— 本格没跑到被测面",
      )
    }
    for p in ["\"challenge\": string_prop(", "\"challenge_sig\": string_prop("] {
      if ch_contains_line(blk, p) {
        abort(
          tool +
          " 的 schema 声明了 " +
          p +
          " —— 但它的引擎函数不经过角色取数面（锁 1/锁 2），" +
          "这个参数**没有任何读者**，是死参数。要么接引擎+四门，要么别声明。",
        )
      }
    }
  }
}
