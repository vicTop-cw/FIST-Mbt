// ============================================================================
// BUG-469：六个工具**不接** `challenge` 的定夺锁
//
// 派单要求给六个工具（execute / submit / verify / reject / retry / archive）接 challenge。
// **核完代码后：六个全部不接。**
//
// 判据（BUG-472 立的）：**引擎有没有 challenge 消费点？**
//   `challenge` 的唯一消费者是 `judged_role_gated` / `judged_role_with_nonce`。
//   全仓生产代码只有 **2 处**调用：
//     · `src/engine/engine.mbt`（`FistEngine::claim` → `judged_role_with_nonce`）
//     · `src/engine/engine_rsv.mbt`（`rsv_try_set` / `locks_try_acquire` → `judged_role_gated`）
//   六个目标工具的引擎函数**一个都不在其中** ⇒ 接了也是死参数。
//
// ⚠️ 反过来说：若将来某个工具的引擎真加了角色门（cr_02 那类锁会红），
// 那时才该给它接 challenge —— **顺序是先有身份门，再谈认证**。
// ============================================================================

///|
/// 【不接·锁 1】★ **六工具既不声明 challenge，引擎也没有角色消费点**（双向断言）。
///
/// 只断言「schema 没声明」不够 —— 有人可能直接传 args 进引擎；
/// 只断言「引擎没有 judged_role」也不够 —— 有人可能又加回 schema。
/// **两段都断**。
test "cw_01_six_tools_have_no_challenge_and_no_role_consumer" {
  let srv = @fs.read_file_to_string("src/server/server.mbt") catch {
    _ => abort("读不到 server.mbt")
  }
  let eng = @fs.read_file_to_string("src/engine/engine.mbt") catch {
    _ => abort("读不到 engine.mbt")
  }
  let rsv = @fs.read_file_to_string("src/engine/engine_rsv.mbt") catch {
    _ => abort("读不到 engine_rsv.mbt")
  }
  // ① schema 面：六个工具都不许声明 challenge
  for tool in ["execute", "submit", "verify", "reject", "retry", "archive"] {
    let blk = cw_tool_block(srv, tool)
    if cw_code_has(blk, "\"challenge\": string_prop") {
      abort(
        tool + " 又声明了 challenge —— 但它的引擎没有角色消费点（死参数）。" +
        "要么先给引擎加 judged_role 门，再接 challenge。",
      )
    }
  }
  // ② 引擎面：六个函数里不许出现 judged_role 消费点
  let fns = [
    ("engine.mbt", eng, "pub fn FistEngine::execute_with_meta("),
    ("engine.mbt", eng, "pub fn FistEngine::submit("),
    ("engine.mbt", eng, "pub fn FistEngine::verify("),
    ("engine.mbt", eng, "pub fn FistEngine::reject_task("),
    ("engine.mbt", eng, "pub fn FistEngine::retry_task("),
    ("engine_rsv.mbt", rsv, "pub fn FistEngine::archive("),
  ]
  for entry in fns {
    let (label, src, sig) = entry
    let body = cw_func_body(src, sig)
    if body.length() == 0 {
      continue // 函数可能不在该文件，跳过（不是失败）
    }
    for needle in ["judged_role_gated(", "judged_role_with_nonce("] {
      if cw_code_has(body, needle) {
        abort(
          label + " 的 " + sig + " 里出现了 `" + needle + "` —— " +
          "它已接入角色取数面！那就**应该**接 challenge 了（并更新本文件）。",
        )
      }
    }
  }
}

///|
/// 【不接·锁 2】★ **挑战消费点清单**：只在下面这些函数里，六个目标工具**一个都不在**。
///
/// 本单实测清单（按函数名断言，不按裸计数 —— 计数会被定义行/新函数干扰）：
///   · `engine.mbt`      `FistEngine::claim`
///   · `engine_rsv.mbt`  `rsv_set` / `rsv_try_set` / `locks_try_acquire`
///                       / `challenge_pending_count`
/// 六个目标工具（execute/submit/verify/reject/retry/archive）**都不在其中**。
///
/// 若将来某个目标工具的引擎真加了角色门 ⇒ 本格红 ⇒ 提醒「六工具该重评」。
test "cw_02_consumer_whitelist_excludes_six_tools" {
  let targets = [
    "execute_with_meta", "submit", "verify", "reject_task", "retry_task",
    "archive_force", "archive",
  ]
  for f in ["src/engine/engine.mbt", "src/engine/engine_rsv.mbt"] {
    let src = @fs.read_file_to_string(f) catch {
      _ => abort("读不到 " + f)
    }
    for t in targets {
      // 逐个可能的签名形态找（找不到就跳过，不失败）
      for sig in [
        "pub fn FistEngine::" + t + "(",
        "pub fn FistEngine::" + t + " (",
      ] {
        let body = cw_func_body(src, sig)
        if body.length() == 0 {
          continue
        }
        for needle in ["judged_role_gated(", "judged_role_with_nonce("] {
          if cw_code_has(body, needle) {
            abort(
              f + " 的 " + t + " 里出现了 `" + needle + "` —— " +
              "消费点清单变了，六工具「不该接 challenge」的结论**需要重新评审**。",
            )
          }
        }
      }
    }
  }
}

///|
/// 【C 类·锁 3】`lock_acquire.ts` / `lock_renew.ts` 属**设计如此**（BUG-33 时间戳盖章）。
///
/// 断言：两处 schema 描述里**必须**写明「服务端盖章/不接受覆盖」。
/// 若有人把描述改回去（变成「默认当前时间」这种会误导的写法），本格红 ——
/// **因为正是那段描述让 `check_dead_params.py` 把它判成 C 类而不是死参数。**
test "cw_03_ts_descriptions_state_server_stamped" {
  let srv = @fs.read_file_to_string("src/server/server.mbt") catch {
    _ => abort("读不到 server.mbt")
  }
  for tool in ["lock_acquire", "lock_renew"] {
    let blk = cw_tool_block(srv, tool)
    if not(cw_code_has(blk, "服务端盖章")) {
      abort(
        tool + " 的 ts 描述里没有「服务端盖章」字样 —— " +
        "它是 C 类设计如此（BUG-33），描述必须让调用方知道传了也无效。",
      )
    }
  }
}

// ── 小工具 ──────────────────────────────────────────────────────────────

///|
fn cw_code_only(raw : String) -> String {
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
fn cw_code_has(raw : String, needle : String) -> Bool {
  cw_code_only(raw).contains(needle)
}

///|
fn cw_count_code(raw : String, needle : String) -> Int {
  let hay = cw_code_only(raw)
  let h = hay.to_array()
  let nd = needle.to_array()
  if nd.length() == 0 {
    return 0
  }
  let mut cnt = 0
  let mut i = 0
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
      cnt = cnt + 1
      i = i + nd.length()
    } else {
      i = i + 1
    }
  }
  cnt
}

///|
/// 按**工具块边界**切分（不用固定行窗口 —— 判例-32 教训）。
fn cw_tool_block(srv : String, name : String) -> String {
  let i = match cw_find(srv, "\"" + name + "\",", 0) {
    Some(x) => x
    None => abort("找不到工具：" + name)
  }
  let rest = cw_slice(srv, i + 1, srv.length())
  let j = match cw_find(rest, "s1 = instrumented_tool(", 0) {
    Some(x) => x
    None => rest.length()
  }
  cw_slice(rest, 0, j)
}

///|
fn cw_func_body(src : String, sig : String) -> String {
  let i = match cw_find(src, sig, 0) {
    Some(x) => x
    None => return ""
  }
  let rest = cw_slice(src, i + 1, src.length())
  let a = match cw_find(rest, "\npub fn ", 0) {
    Some(x) => x
    None => rest.length()
  }
  let b = match cw_find(rest, "\nfn ", 0) {
    Some(x) => x
    None => rest.length()
  }
  let c = match cw_find(rest, "\npub async fn ", 0) {
    Some(x) => x
    None => rest.length()
  }
  let mut end = if a < b { a } else { b }
  if c < end {
    end = c
  }
  cw_slice(rest, 0, end)
}

///|
fn cw_find(hay : String, needle : String, from : Int) -> Int? {
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
fn cw_slice(s : String, from : Int, to : Int) -> String {
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