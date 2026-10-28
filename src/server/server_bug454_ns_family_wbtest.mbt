// ============================================================================
// BUG-454：`tx_contract` / `task_challenge` / `task_cleanup` 缺 namespace
//           （BUG-452 普查的「待议 3 个」）
//
// ★ `tx_contract` 的错误**比「查不到」更糟**：
//   缺 ns ⇒ 它拿**主库同名任务**去算迁移预检 ⇒ 给出与 `get(namespace=…)` **相反**的结论。
//   「查不到」调用方知道有问题；「错误结论」调用方**据此做错决策**。
//
// 判例-30 防护：查源码时跳过注释行。
// ============================================================================

///|
fn bq_code_only(raw : String) -> String {
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
fn bq_block(src : String, name : String) -> String {
  let i = match bq_find_at(src, "\"" + name + "\",", 0) {
    Some(x) => x
    None => abort("找不到工具：" + name)
  }
  bq_slice(src, i, i + 6000)
}

///|
/// 【ns·锁 1】`tx_contract` **按 ns 路由**，且 `transition_contract` 作用在路由后的引擎上。
///
/// 这格钉「结论正确」的前提：只有作用在**目标 ns 的引擎**上，
/// 预检才会看到那个库里的任务（而不是主库同名任务）。
test "bq_01_tx_contract_routes_by_ns" {
  let raw = @fs.read_file_to_string("src/server/server.mbt") catch {
    _ => abort("读不到 server.mbt")
  }
  let src = bq_code_only(raw)
  let blk = bq_block(src, "tx_contract")
  if !blk.contains("\"namespace\": string_prop(") {
    abort("tx_contract 的 schema 缺 namespace")
  }
  if !blk.contains("engine_for_ns(ns_tx)") {
    abort(
      "tx_contract 没有按 ns 路由（仍用全局 engine ⇒ 拿主库同名任务算，结论相反）",
    )
  }
  // ★ 判据用「eng_tx 与 transition_contract 都出现」，不硬拼跨行字面
  //   （实测踩过：字符串里写 "\n          .transition_contract(" 与源码真实换行对不上 ⇒ 恒不匹配）
  if !blk.contains("eng_tx") || !blk.contains(".transition_contract(") {
    abort("transition_contract 没有作用在路由后的 eng_tx 上")
  }
  // 不许残留旧形态：`engine` 单独成行、下一行以 `.transition_contract(` 开头。
  // 做法：逐行扫，维护「上一行是否为裸 engine」的布尔，不在字符串上做 replace/trim 转换
  // （实测踩过：`trim()`/`replace()` 返回的是 StringView，赋给 String 会类型不符；
  //  且硬拼 "eng_tx\n          .transition_contract(" 与真实换行对不上 ⇒ 恒不匹配）
  let mut prev_was_bare_engine = false
  for l in blk.split("\n") {
    let line = l.to_string()
    let t = line.trim()
    if prev_was_bare_engine && t.has_prefix(".transition_contract(") {
      abort(
        "仍用全局 engine 做 transition_contract —— 旧形态残留，结论仍会相反",
      )
    }
    prev_was_bare_engine = t == "engine"
  }
}

///|
/// 【ns·锁 2】**零回归**：三个工具的 namespace 缺省都必须是 `"default"`。
test "bq_02_all_three_default_to_default" {
  let raw = @fs.read_file_to_string("src/server/server.mbt") catch {
    _ => abort("读不到 server.mbt")
  }
  let src = bq_code_only(raw)
  for name in ["tx_contract", "task_challenge", "task_cleanup"] {
    let blk = bq_block(src, name)
    if !blk.contains("get_str(args, \"namespace\", default=\"default\")") {
      abort(
        name +
        " 的 namespace 缺省不是 \"default\" —— 不传会走到别的库",
      )
    }
  }
}

///|
/// 【ns·锁 3】`task_challenge` 与 `task_cleanup` 也按 ns 路由。
test "bq_03_challenge_and_cleanup_route_by_ns" {
  let raw = @fs.read_file_to_string("src/server/server.mbt") catch {
    _ => abort("读不到 server.mbt")
  }
  let src = bq_code_only(raw)
  let ch = bq_block(src, "task_challenge")
  if !ch.contains("engine_for_ns(ns_ch)") {
    abort("task_challenge 没有按 ns 路由")
  }
  if !ch.contains("eng_ch.challenge(") {
    abort("challenge 没有作用在路由后的 eng_ch 上")
  }
  let cl = bq_block(src, "task_cleanup")
  if !cl.contains("engine_for_ns(ns_tc)") {
    abort("task_cleanup 没有按 ns 路由")
  }
  if !cl.contains("@ops.cleanup_archived(eng_tc,") {
    abort("cleanup_archived 没有作用在路由后的 eng_tc 上")
  }
}

///|
/// 【ns·锁 4】★ **`task_cleanup` 刻意不遍历所有 ns**（不可逆删除不该跨库）。
///
/// 这条锁的是**设计决策**：批量清理若自动遍历所有租户库，
/// 一次调用会波及多个库、事后无法核对到底删了哪些。
/// 变异（改成遍历所有 ns）⇒ 本格红，逼着重新评审这个决策。
test "bq_04_cleanup_does_not_sweep_all_namespaces" {
  let raw = @fs.read_file_to_string("src/server/server.mbt") catch {
    _ => abort("读不到 server.mbt")
  }
  let src = bq_code_only(raw)
  let cl = bq_block(src, "task_cleanup")
  // 不许出现**任何**遍历形态。
  // ⚠️ 检测词不能只写 "for ns in" —— 实测变异用的 `for ns_x in …` 就漏过了。
  //   改为逐行扫：只要出现 `for ` 且同一行含 ` in `，就是遍历形态。
  for line in cl.split("\n") {
    let s = line.to_string()
    let t = s.trim()
    if t.has_prefix("for ") && t.contains(" in ") {
      abort(
        "task_cleanup 里出现了遍历（" +
        s.trim().to_string() +
        "）—— " +
        "不可逆删除不该跨库遍历（一次调用波及多个租户库，事后无法核对）",
      )
    }
  }
  // 不许出现读取「已打开 ns 清单」的调用
  for bad in ["active_namespaces", "foreach_ns"] {
    if cl.contains(bad) {
      abort(
        "task_cleanup 里出现了 `" +
        bad +
        "` —— 那是「遍历所有库」的入口",
      )
    }
  }
  // 且必须明确只清一个库
  if !cl.contains("eng_tc") {
    abort(
      "task_cleanup 没有单一目标引擎 —— 无法保证只清一个库",
    )
  }
}

// ── 小工具 ──────────────────────────────────────────────────────────────

///|
fn bq_find_at(hay : String, needle : String, from : Int32) -> Int32? {
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
fn bq_slice(s : String, from : Int32, to : Int32) -> String {
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
