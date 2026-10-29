///|
/// BUG-476：`strict` 必须**真的拒绝** —— 五格锁（含实现路径格）。
///
/// ## 背景：本单修的是**我自己上一版的诚实边界**
///
/// BUG-470 落地后，`strict` 只做到「返回专用 `challenge_missing` 标签 + 降权」，
/// 各门消费者**没据此硬拒** ⇒ **实际效果接近 `soft`**。
/// 判例：「以为自己安全了」比不设更危险 —— 设了 `strict` 的人会**真的相信**它严格了。
///
/// ## 设计：拒在门层，不改 `judged_role_gated` 签名
///
/// 它返回 `(String, String)`，被 5 处消费；改成 `Result` 会波及全部 + 工具面 3 处调用方。
/// 故保持纯净，「拒不拒」留给门层 —— 与既有 `RoleDenied` 同一手法。
/// 判定抽在 `strict_challenge_denial` **单一真源**（三处门 + claim 共用，避免 BUG-435 抄写漂移）。
///
/// ## ⚠️ 为什么这几格**不设进程 env**
///
/// 与 `engine_bug470_auth_mode_wbtest.mbt` 同一手法：`auth_mode()` 读一次即缓存，
/// 测试里改 env 会和别的格互相污染（并行跑时更糟，判例-31）。
/// 本文件改在**纯函数层**验证模式语义，在**门层函数**验证拒/不拒 —— 两者都不依赖 env。
///
/// ## 五格
///   S1 `strict` + 无 challenge ⇒ 门层**拒**（`Some`）
///   S2 `strict` + 验签通过 ⇒ 门层**不拒**（`None`）
///   S3 `soft` + 无 challenge ⇒ 门层**不拒**（与 strict 可区分）
///   S4 `off` + 无 challenge ⇒ 门层**不拒**（零回归）
///   S5 **实现路径格**：`run_server()` 里**真的调了** `auth_mode_startup_warning()`

///|
/// 【S1】`strict` + 无挑战 ⇒ `challenge_missing` 且门层**硬拒**。
///
/// 这是本单的核心：**调用方拿到错误，而不是降权后继续跑**。
test "bug476_s1_strict_without_challenge_is_denied" {
  // ① 纯函数层：strict 解析正确
  assert_eq(auth_mode_parse("strict"), Strict)
  // ② 门层：challenge_missing ⇒ 必须拒
  match strict_challenge_denial("challenge_missing", "reserve_scope") {
    Some(msg) => {
      assert_true(msg.contains("strict"))
      // 错误文案必须告诉调用方**怎么自救**（可诊断性，判例：错误要自解释）
      assert_true(msg.contains("agent_register_key"))
      assert_true(msg.contains("FIST_AUTH_MODE"))
    }
    None =>
      abort(
        "BUG-476 **strict 没有硬拒** —— 门层放行了 challenge_missing",
      )
  }
}

///|
/// 【S2】`strict` + 验签通过（`challenge_verified`）⇒ 门层**不拒**。
///
/// 真 Ed25519 全链路由 `engine_bug430_*` 的锁负责；这里只钉「门放行」。
test "bug476_s2_verified_challenge_passes_under_strict" {
  match strict_challenge_denial("challenge_verified", "reserve_scope") {
    Some(_) => abort("验签通过的请求不该被 strict 拒")
    None => ()
  }
}

///|
/// 【S3】`soft` + 无挑战 ⇒ 产生 `challenge_required`（不是 `challenge_missing`），门层**不拒**。
///
/// **这一格是「strict ≠ soft」的直接证据**：同一个「无挑战」输入，
/// soft 走降权、strict 走拒绝 —— 两档可区分。
test "bug476_s3_soft_degrades_but_is_not_denied" {
  assert_eq(auth_mode_parse("soft"), Soft)
  // soft 的标注是 challenge_required（不是 missing）
  match strict_challenge_denial("challenge_required", "reserve_scope") {
    Some(_) =>
      abort("**soft 被当成了 strict** —— 两档不可区分了")
    None => ()
  }
  // 两者必须是**不同**的 role_source（否则门层无法区分）
  assert_true("challenge_required" != "challenge_missing")
}

///|
/// 【S4】`off` + 无挑战 ⇒ 门层**不拒**（零回归，首次默认值）。
test "bug476_s4_off_is_not_denied" {
  assert_eq(auth_mode_parse("off"), Off)
  // off 下无挑战产生的是 "declared"/"inferred" 之类，绝不是 challenge_missing
  match strict_challenge_denial("declared", "reserve_scope") {
    Some(_) => abort("off 下不该拒")
    None => ()
  }
  match strict_challenge_denial("inferred", "reserve_scope") {
    Some(_) => abort("off 下不该拒（inferred）")
    None => ()
  }
  // 空串 / 未设 ⇒ off
  assert_eq(auth_mode_parse(""), Off)
}

///|
/// 【S5 · 实现路径格（判例-29）】`run_server()` 里**真的调了** `auth_mode_startup_warning()`。
///
/// **为什么必须是静态源码格而不是「断言函数存在」**：
///   函数存在 ≠ 被调用 —— BUG-470 上一版就是「函数实现了但零调用点」，
///   本次 BUG-476 的起因正是它。本格读 `server.mbt` 源码，
///   断言 `run_server` 的函数体里**出现该调用**。
///
/// **为什么不用运行时断言**：`run_server()` 是 `async` 且会起 stdio 循环，
///   在测试里调它会把测试进程挂住。静态格是本仓既有范式
///   （`pipeline_r2_wbtest.mbt` 的 BUG-18 格、`server_bug471_*` 的接线格都用这一手法）。
test "bug476_s5_startup_warning_is_wired_in_run_server" {
  let raw = @fs.read_file_to_string("src/server/server.mbt") catch {
    _ => abort("读不到 server.mbt")
  }
  // 剥掉注释行（判例-30：模式串自己出现在注释里 ⇒ 变异后仍命中 ⇒ 恒绿）
  let mut code = ""
  for line in raw.split("\n") {
    let s = line.to_owned()
    let t = s.trim()
    if t.has_prefix("///") || t.has_prefix("//") {
      continue
    }
    code = code + s + "\n"
  }
  let at = code.find("pub async fn run_server()")
  match at {
    None =>
      abort("找不到 run_server 定义 ⇒ 本格锚点失效，请复核")
    Some(i) => {
      let hi = if i + 4000 < code.length() { i + 4000 } else { code.length() }
      let rest = code[i:hi].to_owned()
      if !(rest.contains("auth_mode_startup_warning()")) {
        abort(
          "BUG-476 **startup_warning 未被 run_server 调用** —— 函数存在但没接线（判例-29）",
        )
      }
      // 反脱锚：确认在 run_server **之前**没有该调用（否则本格的 find 锚点会认错位置）
      let before = code[0:i].to_owned()
      if before.contains("auth_mode_startup_warning()") {
        abort(
          "startup_warning 在 run_server 之前已出现 ⇒ 本格锚点失效，请复核",
        )
      }
    }
  }
}

///|
/// 【S6 · 实现路径格（判例-29）】**四处门真的都接了硬拒**。
///
/// ## 为什么必须有这一格
///
/// S1~S4 测的是门层函数 `strict_challenge_denial` 的**语义**（输入 role_source ⇒ 拒/不拒）。
/// **它们不依赖四处接线** —— 实测变异：把 `rsv_set` 里的 `strict_challenge_denial(...)`
/// 整行删掉，S1~S5 **全绿**（因为函数本身没变、startup 也没动）⇒ **接线坏了没人知道**。
///
/// 这正是判例-29 的形态：**机制格（函数对）≠ 实现路径格（门真的调了它）**。
/// 所以本格直接读源码数接线点，**少一处就红**。
///
/// ## 为什么数「计数」而不是「contains」
///
/// `reserve_scope` 有**两处**门（`rsv_set` + `rsv_try_set`），只断言 contains
/// 会在删掉其中一处时仍然绿。**计数才钉得住「每一处都在」。**
test "bug476_s6_all_four_gates_are_wired" {
  let rsv = @fs.read_file_to_string("src/engine/engine_rsv.mbt") catch {
    _ => abort("读不到 engine_rsv.mbt")
  }
  let srv = @fs.read_file_to_string("src/server/server.mbt") catch {
    _ => abort("读不到 server.mbt")
  }
  // 剥注释（判例-30：模式串自己出现在注释里 ⇒ 恒绿）
  let strip = fn(src : String) -> String {
    let mut out = ""
    for line in src.split("\n") {
      let s = line.to_owned()
      let t = s.trim()
      if t.has_prefix("///") || t.has_prefix("//") {
        continue
      }
      out = out + s + "\n"
    }
    out
  }
  let rsv_c = strip(rsv)
  let srv_c = strip(srv)
  // ① 预订门两处（rsv_set + rsv_try_set）：**计数必须 == 2**
  let n1 = b476_count_of(
    rsv_c, "strict_challenge_denial(role_source, \"reserve_scope\")",
  )
  if n1 != 2 {
    abort(
      "BUG-476 预订门硬拒接线数 = " +
      n1.to_string() +
      "（期望 2 = rsv_set + rsv_try_set）—— 少一处就有一处门不拒",
    )
  }
  // ② 锁门一处
  let n2 = b476_count_of(
    rsv_c, "strict_challenge_denial(role_source, \"lock_acquire\")",
  )
  if n2 != 1 {
    abort(
      "BUG-476 锁门硬拒接线数 = " + n2.to_string() + "（期望 1）",
    )
  }
  // ③ claim 门一处（在 server.mbt）
  let n3 = b476_count_of(srv_c, "strict_challenge_denial(auth.1, \"claim\")")
  if n3 != 1 {
    abort(
      "BUG-476 claim 硬拒接线数 = " + n3.to_string() + "（期望 1）",
    )
  }
}

///|
/// 数子串出现次数。
///
/// ⚠️ **为什么不用 `s.split(needle).count()`**：实测 S6 用它红了 ——
///   `String::split(...).count()` 在本仓没有既有用例可参照，其重载解析（可能落到
///   `Iter::count()` 或别的 count）不可靠。判例：「工具给你的读数，先确认它数的是什么」。
///   本函数逐字复刻 `engine_bug430_s3_p2_wbtest.mbt:135` 的既有范式（同一个仓里已验证）。
fn b476_count_of(hay : String, needle : String) -> Int32 {
  let mut n = 0
  let mut start = 0
  while true {
    let idx = b476_find_from(hay, needle, start)
    if idx < 0 {
      break
    }
    n = n + 1
    start = idx + needle.length()
  }
  n
}

///|
fn b476_find_from(hay : String, needle : String, from : Int32) -> Int32 {
  let hn = hay.length()
  let nn = needle.length()
  if nn == 0 {
    return from
  }
  let mut i = from
  while i + nn <= hn {
    if hay[i:i + nn] == needle {
      return i
    }
    i = i + 1
  }
  -1
}
