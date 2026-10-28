// ============================================================================
// BUG-452：`conflicts_check` 缺 `namespace` 参数 —— 非 default ns 的任务查不到
//
// 病灶：工具实现用**全局 `engine`**（主库）做 `check_claim`，且 schema 无 `namespace`
// ⇒ 任务在独立 ns 库里时**恒报 task not found** ⇒ **并行门第 4 道在非 default ns 里不可用**。
//
// 同族（本段一并修）：`heartbeat` / `task_challenge` 也只用全局 engine 取任务。
//
// 判例-30 防护：查源码时跳过注释行。
// ============================================================================

///|
/// 跳过注释行后的源码。
fn bo_code_only(raw : String) -> String {
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
/// 【ns·锁 1】`conflicts_check` 的 schema **有 `namespace`**，且实现**按 ns 路由**。
///
/// 两条一起钉：
///   ① schema 有参数（否则调用方传不进来）
///   ② 实现里有 `engine_for_ns(ns)` 且**不再用裸 `engine`** 做 check_claim
///      （只加 schema 不改实现 = 传了也没用，判例-29）
test "bo_01_conflicts_check_routes_by_ns" {
  let raw = @fs.read_file_to_string("src/server/server.mbt") catch {
    _ => abort("读不到 server.mbt")
  }
  let src = bo_code_only(raw)
  // ① schema：conflicts_check 块里必须有 namespace
  let i_def = find_at(src, "\"conflicts_check\",", 0)
  if i_def < 0 {
    abort("找不到 conflicts_check 定义")
  }
  let blk = slice(src, i_def, i_def + 2500)
  if !blk.contains("\"namespace\": string_prop(") {
    abort("conflicts_check 的 schema 缺 namespace 参数")
  }
  // ② 实现：必须 engine_for_ns，且 check_claim 的对象是路由后的引擎
  if !blk.contains("engine_for_ns(ns)") {
    abort(
      "conflicts_check 实现没有按 ns 路由（仍用全局 engine ⇒ 非 default ns 查不到）",
    )
  }
  if !blk.contains("@ops.check_claim(eng,") {
    abort(
      "check_claim 没有用路由后的 eng（改了 schema 却没改实现）",
    )
  }
  // ③ 不许再出现「用全局 engine 做 check_claim」的旧形态
  if blk.contains("@ops.check_claim(engine,") {
    abort("仍有 @ops.check_claim(engine, …) —— 旧形态残留")
  }
}

///|
/// 【ns·锁 2】**零回归**：`namespace` 缺省必须是 `default`。
///
/// 不传 ⇒ 走主库 ⇒ 行为与旧版完全一致。
test "bo_02_default_namespace_is_default" {
  let raw = @fs.read_file_to_string("src/server/server.mbt") catch {
    _ => abort("读不到 server.mbt")
  }
  let src = bo_code_only(raw)
  let i_def = find_at(src, "\"conflicts_check\",", 0)
  let blk = slice(src, i_def, i_def + 2500)
  if !blk.contains("get_str(args, \"namespace\", default=\"default\")") {
    abort(
      "conflicts_check 的 namespace 缺省不是 \"default\" —— 不传会走到别的库",
    )
  }
}

///|
/// 【ns·锁 3】同族工具 `heartbeat` 也按 ns 路由（普查发现的问题一并修）。
test "bo_03_heartbeat_routes_by_ns" {
  let raw = @fs.read_file_to_string("src/server/server.mbt") catch {
    _ => abort("读不到 server.mbt")
  }
  let src = bo_code_only(raw)
  let i_def = find_at(src, "\"heartbeat\",", 0)
  if i_def < 0 {
    abort("找不到 heartbeat 定义")
  }
  let blk = slice(src, i_def, i_def + 2500)
  if !blk.contains("\"namespace\": string_prop(") {
    abort("heartbeat 的 schema 缺 namespace")
  }
  if !blk.contains("engine_for_ns(ns_hb)") {
    abort(
      "heartbeat 没有按 ns 路由（非 default ns 的任务取不到 ⇒ 心跳静默失效）",
    )
  }
}

///|
/// 【ns·锁 4】**引擎路由的语义**（本单依赖它，故一并钉住）。
///
/// ⚠️ 我先写错的版本：以为「未打开的 ns ⇒ Err」。**实测不是** ——
/// `MultiStore::get` 对合法但未打开的 ns 会**惰性打开（建一个新库）**并返回 `Some`
/// ⇒ `engine_for_ns` 返回 `Ok(那个新库的引擎)`。
/// **这是设计（惰性多租户），不是 bug**，但它决定了本单的性质：
///   传了 `namespace="rx-rhop"` ⇒ 拿到的是** rx-rhop 那个库**（不是主库）
///   ⇒ 里面有没有任务取决于该库是否真的被 store_open 过 / 有没有数据。
///
/// ⇒ 本格钉三件事：
///   ① `default` / `""` ⇒ 主库（同一个引擎语义）
///   ② 合法 ns ⇒ **Ok**（惰性打开）
///   ③ **非法 ns ⇒ Err**（这条是 BUG-433 的真防线：非法 ns 不许静默回落主库）
test "bo_04_route_semantics" {
  match engine_for_ns("default") {
    Ok(_) => ()
    Err(_) => abort("engine_for_ns(\"default\") 应成功")
  }
  match engine_for_ns("") {
    Ok(_) => ()
    Err(_) => abort("engine_for_ns(\"\") 应等同 default")
  }
  // 合法 ns ⇒ 惰性打开 ⇒ Ok（这是设计，不是「静默回落主库」——
  // 拿到的是**那个 ns 的库**，不是主库）
  match engine_for_ns("zzneveropenedbo452") {
    Ok(_) => ()
    Err(_) => abort("合法 ns 应惰性打开成功")
  }
  // ★ 真防线：**非法** ns 必须 Err（不许静默回落主库 —— 那会把操作打到主库任务上）
  match engine_for_ns("bad ns with spaces") {
    Ok(_) =>
      abort(
        "非法 ns 竟返回 Ok —— 静默回落主库，delete/archive 会打到主库任务",
      )
    Err(_) => ()
  }
  match engine_for_ns("bad/ns") {
    Ok(_) => abort("含斜杠的非法 ns 竟返回 Ok")
    Err(_) => ()
  }
}

// ── 小工具 ──────────────────────────────────────────────────────────────

///|
fn find_at(hay : String, needle : String, from : Int32) -> Int32 {
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
fn slice(s : String, from : Int32, to : Int32) -> String {
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
