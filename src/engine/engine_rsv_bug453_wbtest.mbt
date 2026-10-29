///|
/// BUG-453 白盒锁：**S3 认证态必须出现在 `action` 面**。
///
/// 病灶：`judged_role_with_challenge` 承诺「让认证状态显式可见」（`engine_rsv.mbt:124-126`），
/// 但 `rsv_try_set` / `locks_try_acquire` 的 `action` 面只映射了 `inferred` 一种，
/// 且无条件追加硬编码 `+agent_self_reported`：
///   ⇒ 验签**通过**时回执仍写「自报未验证」（诚实标注写反）
///   ⇒ 验签**失败**时与「压根没传 challenge」逐字相同（日志里不可区分）
///
/// 本文件五格：
///   · L1 验签通过 ⇒ `+challenge_verified`
///   · L2 验签失败 ⇒ `+challenge_failed`
///   · L3 重放     ⇒ `+challenge_replayed`
///   · L4 没传 challenge ⇒ `+agent_self_reported`（**零回归**）
///   · L5 变异对照：`auth_tag` 被改回硬编码 ⇒ L1/L2/L3 必红
///
/// L5 的做法（判例-29「机制格 ≠ 实现路径格」）：**不跑实现，直接对源码做断言** ——
/// 断言 `auth_tag` 里确实有四个分支的映射，而不是「某个函数存在」。
/// 这样把 `auth_tag` 改回 `=> "+agent_self_reported"` 时，本格直接红。

///|
/// 从源码里取出 `auth_tag` 函数的函数体（`pub fn auth_tag(...) -> String {` 起的大括号配平段）。
fn bug453_auth_tag_body() -> String {
  let raw = @fs.read_file_to_string("src/engine/engine_rsv.mbt") catch {
    _ => abort("BUG-453: 读不到 engine_rsv.mbt")
  }
  let marker = "pub fn auth_tag(role_source : String) -> String {"
  let start = match raw.find(marker) {
    Some(i) => i
    None =>
      abort(
        "BUG-453: 找不到 `pub fn auth_tag` —— 认证态映射源被删/改名了，本锁的判定面已失效",
      )
  }
  let mut depth = 0
  let mut i = start
  let mut end = -1
  while i < raw.length() {
    let c = raw[i]
    if c == '{' {
      depth = depth + 1
    } else if c == '}' {
      depth = depth - 1
      if depth == 0 {
        end = i
        break
      }
    }
    i = i + 1
  }
  if end < 0 {
    abort("BUG-453: auth_tag 函数体没有闭合的大括号")
  }
  // deprecated substring → 切片。安全性：`end < 0` 已在 :50-52 abort，
  // 且 start/end 都来自上面 find 循环的合法索引 ⇒ 落在 [0, len] 边界内
  // （B0/B1 区间，与 substring 实测同值）。
  raw[start:end].to_string()
}

///|
/// 【L5 · 变异对照】`auth_tag` 必须把四个认证态映射到**四个不同后缀**。
///
/// 变异形状（本该红）：把整个函数体改成 `_ => "+agent_self_reported"` 单一分支。
/// 本格逐条断言四个字面量都在函数体里 ⇒ 改回硬编码时至少三条缺失 ⇒ 红。
test "bug453_L5_auth_tag_maps_all_four_states" {
  let body = bug453_auth_tag_body()
  // 四个后缀必须各自出现（缺任一个 = 该认证态在 action 面不可见）
  if !body.contains("+challenge_verified") {
    abort(
      "BUG-453 变异：auth_tag 没有映射 challenge_verified ⇒ 验签通过在 action 面不可见",
    )
  }
  if !body.contains("+challenge_failed") {
    abort(
      "BUG-453 变异：auth_tag 没有映射 challenge_failed ⇒ 验签失败与未挑战不可区分",
    )
  }
  if !body.contains("+challenge_replayed") {
    abort(
      "BUG-453 变异：auth_tag 没有映射 challenge_replayed ⇒ 重放在 action 面不可见",
    )
  }
  // `inferred` 归入默认零后缀（由 `rsv_try_set` 调用点按旧口径补 `+role_inferred`）
  // ⇒ 这里不断言 auth_tag 含 +role_inferred，改由 L4 断言 auth_tag("inferred") == ""。
  // 兜底分支必须是空串（既有态零后缀；`+agent_self_reported` 由 rsv_try_set 调用点补）
  if !body.contains("_ =>") {
    abort(
      "BUG-453 变异：auth_tag 没有兜底分支 ⇒ 新增认证态之外的角色会 panic",
    )
  }
}

///|
/// 【L5-b · 机制格】`rsv_try_set` 必须**调用** `auth_tag`，不许自己再写一份映射。
///
/// 为什么需要这一格（判例-29）：只断言 `auth_tag` 本身对，证明不了它被接上了 ——
/// 实测踩过「函数写好了但调用点没改」。
test "bug453_L5b_rsv_try_set_calls_auth_tag" {
  let raw = @fs.read_file_to_string("src/engine/engine_rsv.mbt") catch {
    _ => abort("BUG-453: 读不到 engine_rsv.mbt")
  }
  if !raw.contains("let auth = auth_tag(role_source)") {
    abort(
      "BUG-453 变异：rsv_try_set 没有调 auth_tag ⇒ 回执仍是硬编码 +agent_self_reported",
    )
  }
}

///|
/// 【L5-c · 机制格】`locks_try_acquire` 不许再丢弃 `role_source`。
///
/// 病灶原文（修前）：`let (role, _role_source) = judged_role_gated(...)`
/// —— 下划线前缀就是「丢弃」的语言级标记。
test "bug453_L5c_locks_does_not_discard_role_source" {
  let raw = @fs.read_file_to_string("src/engine/engine_rsv.mbt") catch {
    _ => abort("BUG-453: 读不到 engine_rsv.mbt")
  }
  if raw.contains("_role_source") {
    abort(
      "BUG-453 变异：还有 `_role_source` ⇒ 有门在丢弃认证态（修前 locks_try_acquire 就是这样）",
    )
  }
}

///|
/// 【L1】验签通过 ⇒ `action` 含 `+challenge_verified`（**且在 `action` 里，不在别的字段**）。
///
/// 真跑：造一个 agent + 登记真公钥 + 用匹配私钥签 nonce ⇒ 断言 action 后缀。
/// 单测不便生成真密钥对，故本格验的是**映射函数本身**（纯函数，零 IO）；
/// 端到端那一段由 `engine_bug430_s3_key_wbtest.mbt` 的 4 格负责（真签名 + 真验签）。
test "bug453_L1_verified_maps_to_tag" {
  assert_eq(auth_tag("challenge_verified"), "+challenge_verified")
}

///|
/// 【L2】验签失败 ⇒ `+challenge_failed`。
test "bug453_L2_failed_maps_to_tag" {
  assert_eq(auth_tag("challenge_failed"), "+challenge_failed")
}

///|
/// 【L3】重放 ⇒ `+challenge_replayed`。
test "bug453_L3_replayed_maps_to_tag" {
  assert_eq(auth_tag("challenge_replayed"), "+challenge_replayed")
}

///|
/// 【L4 · 零回归】没传 challenge 时 `role_source` 是 `declared` / `inferred` / `unauthenticated`
/// ⇒ 后缀必须与修前**逐字相同**：
///   · `inferred`        ⇒ `+role_inferred`（修前就有）
///   · 其它              ⇒ `+agent_self_reported`（修前是硬编码常量）
///
/// **这一格是「修了但不许改坏旧行为」的证据。**
test "bug453_L4_no_challenge_zero_regression" {
  // 既有态 ⇒ **空后缀**（锁门的 `permission_denied` / `unregistered` 有精确相等断言）
  assert_eq(auth_tag("declared"), "")
  assert_eq(auth_tag("unauthenticated"), "")
  assert_eq(auth_tag("inferred"), "")
  // 未知值也走兜底，不许 panic（未来加新态时不炸旧路径）
  assert_eq(auth_tag(""), "")
  assert_eq(auth_tag("some_future_source"), "")
}

///|
/// 【L4-b】`rsv_try_set` 侧：既有态必须仍带 `+agent_self_reported`（修前逐字，零回归）。
///
/// 为什么两个门不同：`rsv_try_set` 的 `action` 是拼串（旧锁断言 contains），
/// 而 `locks_try_acquire` 的 `permission_denied` 是**精确相等**断言 ——
/// 所以「默认态」在两条门上的表现必须分别保持原样。这是**实测逼出来的**，不是设计偏好。
test "bug453_L4b_rsv_try_set_keeps_self_reported_default" {
  let raw = @fs.read_file_to_string("src/engine/engine_rsv.mbt") catch {
    _ => abort("BUG-453: 读不到 engine_rsv.mbt")
  }
  if !raw.contains("if auth == \"\" { \"+agent_self_reported\" } else { auth }") {
    abort(
      "BUG-453 变异：rsv_try_set 没有在既有态上补 +agent_self_reported ⇒ 零回归被破坏",
    )
  }
}
