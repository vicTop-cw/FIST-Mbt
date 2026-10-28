// ============================================================================
// BUG-430 / S3 **收尾**：四道门的 MCP 实现真的从 args 读 challenge 并透传
//
// 背景：schema 已加 `challenge` / `challenge_sig`（dc8ef707），
// 但**工具实现没读它们** ⇒ 调用方传了也没用。
//
// ⚠️ 「四道门」= 使用 `judged_role` 取数面的四道：
//     rsv_set / rsv_try_set / locks_try_acquire / claim
//   `execute` **不在其内** —— 它走 `execute_with_meta`，该函数**不调 judged_role**
//   （实测 grep 计数 = 0）⇒ 不需要、也不该接挑战。
//
// 判例-30 防护：本文件的断言**跳过注释行**再查源码，
// 否则「注释里讲 challenge」会被误当成「代码里接了 challenge」。
// ============================================================================

///|
/// 去掉注释行后的源码（只留代码面，用于判例-30 防护）。
fn code_only(src : String) -> String {
  let mut acc = ""
  for line in src.split("\n") {
    // `split` 的元素是 StringView ⇒ 先转成 String 再判前缀/拼接
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
/// 【收尾·锁 1】**工具实现真的从 args 读 challenge**（实现路径格）。
///
/// 断言 `server.mbt` 的**代码面**里出现：
///   · `opt_challenge(args)` —— 统一的读取入口（3 处：reserve_scope / lock_acquire / claim）
///   · `get_str(args, "challenge")` —— 真正读参数
///
/// 变异（删掉 challenge 读取）⇒ 本格红。
test "s3_wire_01_tools_read_challenge_from_args" {
  let raw = @fs.read_file_to_string("src/server/server.mbt") catch {
    _ => abort("读不到 server.mbt —— 实现路径格没跑到被测面")
  }
  let src = code_only(raw)
  // ① 统一的读取入口必须存在
  assert_true(src.contains("fn opt_challenge(args : Json)"))
  // ② 它必须真的读这两个键
  assert_true(src.contains("get_str(args, \"challenge\")"))
  assert_true(src.contains("get_str(args, \"challenge_sig\")"))
  // ③ 三门各自调用过它（reserve_scope / lock_acquire / claim）⇒ 至少 3 次
  let mut n = 0
  let mut start = 0
  while true {
    let idx = find_from_ci(src, "let ch = opt_challenge(args)", start)
    if idx < 0 {
      break
    }
    n = n + 1
    start = idx + 1
  }
  if n < 3 {
    abort(
      "只有 " +
      n.to_string() +
      " 道门调用了 opt_challenge(args)，期望 ≥ 3（reserve_scope / lock_acquire / claim）",
    )
  }
}

///|
/// 【收尾·锁 2】**空串必须等价于「没传」**（零回归的关键）。
///
/// `opt_challenge` 对空串返回 `(None, None)` ⇒ 引擎走原逻辑。
/// 若把空串当成 `Some("")`，**所有旧调用方**都会进入验签分支 ⇒ 全部 challenge_failed
/// ⇒ 灾难性回归。本格钉住这个契约。
test "s3_wire_02_empty_challenge_is_none" {
  // 用假 args 直接测纯函数（不需要起服务）
  let empty : Json = Json::object(Map([]))
  let (c1, s1) = opt_challenge(empty)
  assert_true(c1 is None) // 没传 challenge ⇒ None
  assert_true(s1 is None)
  // 显式传空串 ⇒ 同样 None（MCP 层「没传」与「传空串」难区分，必须同义）
  let blank : Json = Json::object(
    Map([("challenge", Json::string("")), ("challenge_sig", Json::string(""))]),
  )
  let (c2, s2) = opt_challenge(blank)
  assert_true(c2 is None)
  assert_true(s2 is None)
  // 传了真值 ⇒ Some
  let real : Json = Json::object(
    Map([
      ("challenge", Json::string("n1")),
      ("challenge_sig", Json::string("sig1")),
    ]),
  )
  let (c3, s3) = opt_challenge(real)
  match c3 {
    Some(v) => assert_eq(v, "n1")
    None => abort("传了 challenge 却返回 None")
  }
  match s3 {
    Some(v) => assert_eq(v, "sig1")
    None => abort("传了 challenge_sig 却返回 None")
  }
  // 只传 challenge 不传 sig ⇒ (Some, None) ⇒ 引擎按「没交签名」fail-closed
  let half : Json = Json::object(Map([("challenge", Json::string("n2"))]))
  let (c4, s4) = opt_challenge(half)
  assert_true(c4 is Some(_))
  assert_true(s4 is None)
}

///|
/// 【收尾·锁 3】**三门都把 ch.0 / ch.1 透传给了引擎**（不是读了就丢）。
///
/// 断言代码面里出现：
///   · `challenge_nonce=ch.0`（≥3 次）
///   · `challenge_sig=ch.1`（≥3 次）
///
/// 变异（读了但没传）⇒ 本格红。
test "s3_wire_03_tools_forward_challenge_to_engine" {
  let raw = @fs.read_file_to_string("src/server/server.mbt") catch {
    _ => abort("读不到 server.mbt")
  }
  let src = code_only(raw)
  let n_nonce = count_ci(src, "challenge_nonce=ch.0")
  let n_sig = count_ci(src, "challenge_sig=ch.1")
  if n_nonce < 3 {
    abort(
      "challenge_nonce=ch.0 只出现 " +
      n_nonce.to_string() +
      " 次，期望 ≥ 3",
    )
  }
  if n_sig < 3 {
    abort(
      "challenge_sig=ch.1 只出现 " +
      n_sig.to_string() +
      " 次，期望 ≥ 3",
    )
  }
}

///|
/// 【收尾·锁 4】`execute` **不在四道门内**（它不调 `judged_role`），故不需要接挑战。
///
/// 这条防「为了凑四门而给 execute 硬接一个没用的参数」——
/// `execute` 走 `execute_with_meta`，角色取数面不经过 `judged_role`。
test "s3_wire_04_execute_is_not_a_judged_role_gate" {
  let raw = @fs.read_file_to_string("src/engine/engine.mbt") catch {
    _ => abort("读不到 engine.mbt")
  }
  let src = code_only(raw)
  // 截 execute_with_meta 函数体：从定义到下一个 `pub fn`
  let start = find_from_ci(src, "pub fn FistEngine::execute_with_meta(", 0)
  if start < 0 {
    abort("找不到 execute_with_meta 定义")
  }
  let rest = substring_from(src, start + 10)
  let end = find_from_ci(rest, "\npub fn ", 0)
  let body = if end < 0 { rest } else { substring_to(rest, end) }
  if body.contains("judged_role") {
    abort(
      "execute_with_meta 里出现了 judged_role —— 那它就该接挑战，四道门清单需要更新",
    )
  }
}

// ── 小工具（避免依赖外部字符串库）────────────────────────────────────────

///|
fn find_from_ci(hay : String, needle : String, from : Int32) -> Int32 {
  let h = hay.to_array()
  let nd = needle.to_array()
  if nd.length() == 0 || nd.length() > h.length() {
    return -1
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
      return i
    }
    i = i + 1
  }
  -1
}

///|
fn count_ci(hay : String, needle : String) -> Int32 {
  let mut n = 0
  let mut start = 0
  while true {
    let idx = find_from_ci(hay, needle, start)
    if idx < 0 {
      break
    }
    n = n + 1
    start = idx + needle.length()
  }
  n
}

///|
fn substring_from(s : String, from : Int32) -> String {
  let a = s.to_array()
  if from >= a.length() {
    return ""
  }
  let mut out = ""
  let mut i = from
  while i < a.length() {
    out = out + a[i].to_string()
    i = i + 1
  }
  out
}

///|
fn substring_to(s : String, to : Int32) -> String {
  let a = s.to_array()
  let mut out = ""
  let mut i = 0
  let lim = if to > a.length() { a.length() } else { to }
  while i < lim {
    out = out + a[i].to_string()
    i = i + 1
  }
  out
}
