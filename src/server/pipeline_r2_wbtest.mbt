/// pipeline_r2_wbtest.mbt —— Round 2 修复的白盒回归锁：BUG-18（Laya 延迟/预算错配）
/// 与 BUG-3（audit_log 假空）。
///
/// 为什么放在白盒：两个被锁点都在 server.mbt 的**内部**（预算常量 / 返回体构造器），
/// handler 本身是 async 且会真起子进程，同步测试无法 await——沿用 BUG-14/BUG-16 的做法，
/// 守在被修复的那个唯一决策点上，并对源码文本加锁（防"实现还在但调用点被改回旧写法"）。

///|
/// 从 JSON 文本里抠一个整数字段（键后第一个数字串）；抠不到返回 -1。
/// 只用于 .mcp.json 的 timeout_ms 这种小字段，不引第三方解析器。
fn r2_json_int_field(text : String, key : String) -> Int {
  let cs = text.to_array()
  let pat = "\"" + key + "\""
  let ps = pat.to_array()
  let mut at = -1
  let mut i = 0
  while at < 0 && i + ps.length() <= cs.length() {
    let mut matched = true
    for k = 0; k < ps.length(); k = k + 1 {
      if cs[i + k] != ps[k] {
        matched = false
      }
    }
    if matched {
      at = i
    }
    i = i + 1
  }
  if at < 0 {
    return -1
  }
  let mut j = at + ps.length()
  // 跳过 : 与空白
  while j < cs.length() &&
        (cs[j] == ':' || cs[j] == ' ' || cs[j] == '\n' || cs[j] == '\t') {
    j = j + 1
  }
  let mut n = 0
  let mut digits = 0
  while j < cs.length() && cs[j] >= '0' && cs[j] <= '9' {
    n = n * 10 + (cs[j].to_int() - 48)
    digits = digits + 1
    j = j + 1
  }
  if digits == 0 {
    -1
  } else {
    n
  }
}

///|
/// 统计子串出现次数（文本锁用）。
/// 不用 `hay.split(needle).length()`：本版本 `String::split` 返回**消费式 Iter**，
/// 第一次 `length()` 走完迭代、第二次读到 0，判据会恒返 -1（假红灯，测的是判据自己）。
fn r2_count(hay : String, needle : String) -> Int {
  let cs = hay.to_array()
  let ps = needle.to_array()
  if ps.length() == 0 {
    return 0
  }
  let mut n = 0
  let mut i = 0
  while i + ps.length() <= cs.length() {
    let mut matched = true
    for k = 0; k < ps.length(); k = k + 1 {
      if cs[i + k] != ps[k] {
        matched = false
      }
    }
    if matched {
      n = n + 1
      i = i + ps.length()
    } else {
      i = i + 1
    }
  }
  n
}

///|
/// 读项目根下的文件，读不到就 abort（防"文件路径不对→两边都是空串→假绿"）。
fn r2_read_or_abort(path : String) -> String {
  match mem_read(path) {
    Some(c) => c
    None =>
      abort(
        "不可读 \{path}（测试必须在项目根跑）——该守卫无法自证",
      )
  }
}

///|
/// 客户端超时真源的候选路径，顺序即优先级（BUG-86）。
/// 根 `.mcp.json` 在 254de24 被改名成 `.mcp.dev.json`，而守卫族/生成器/本锁仍指旧名——
/// 只读单一文件名会把"真源搬家"误报成"配置坏了"，反过来写死新名又会在下次搬家时又红。
/// 与 scripts/gen_plugins.py 的 MCP_CANDIDATES 同口径，两处名单由本锁对齐。
fn r2_mcp_candidates() -> Array[String] {
  [".mcp.json", ".mcp.dev.json"]
}

///|
/// 用 " / " 串起候选名（本版本 String 没有 join；手写以免把名单第二份抄进消息里）。
fn r2_slash_join(xs : Array[String]) -> String {
  let mut s = ""
  for x in xs {
    if not(s.is_empty()) {
      s = s + " / "
    }
    s = s + x
  }
  s
}

///|
/// 取第一个可读的 MCP 启动真源文本；全都读不到才 abort（防"路径不对→空串→假绿"）。
fn r2_root_mcp_text() -> String {
  for p in r2_mcp_candidates() {
    match mem_read(p) {
      Some(c) => return c
      None => ()
    }
  }
  abort(
    "不可读 MCP 启动真源（试过 " +
    r2_slash_join(r2_mcp_candidates()) +
    "）——该守卫无法自证",
  )
}

///|
test "BUG-18：sidecar/probe 预算必须严格小于 .mcp.json 的客户端超时（实测 278.77s 的病根）" {
  // 真源是 MCP 启动配置的 timeout_ms：镜像常量必须与它一致，且两个服务端预算之和要留在它下面
  let mcp = r2_root_mcp_text()
  let client_ms = r2_json_int_field(mcp, "timeout_ms")
  assert_true(client_ms > 0)
  assert_eq(laya_client_budget_ms, client_ms)
  // 病灶复现锁：旧值 300000 > 客户端 30000，客户端先超时→调用方看到"无响应"
  assert_true(laya_sidecar_budget_ms < client_ms)
  assert_true(laya_probe_budget_ms < client_ms)
  assert_true(laya_probe_budget_ms + laya_sidecar_budget_ms < client_ms)
  // 服务端最坏路径必须早于客户端出结论（留余量给 spawn 与 MCP 往返）
  assert_true(
    client_ms - (laya_probe_budget_ms + laya_sidecar_budget_ms) >= 1000,
  )
}

///|
test "BUG-18：probe 结果进程内缓存带 TTL，且 handler 不再无条件重探" {
  // TTL 边界（纯函数，摘掉任一条件都会红：恒新鲜/恒不新鲜/忘了 0 值）
  let now = 1770000000000L
  assert_false(laya_probe_cache_fresh(now, 0L))
  assert_false(laya_probe_cache_fresh(now, -1L))
  assert_true(laya_probe_cache_fresh(now, now - 1L))
  assert_true(laya_probe_cache_fresh(now, now - laya_probe_ttl_ms + 1L))
  assert_false(laya_probe_cache_fresh(now, now - laya_probe_ttl_ms))
  assert_false(laya_probe_cache_fresh(now, now - laya_probe_ttl_ms - 1000L))
  // TTL 必须是"有限窗口"，不能被人改成永不失效
  assert_true(laya_probe_ttl_ms > 0L && laya_probe_ttl_ms <= 3600000L)
  // 调用点锁：两处（laya_decide / task_plan_deep 的 laya_auto）都走缓存版
  let src = r2_read_or_abort("src/server/server.mbt")
  assert_true(r2_count(src, "laya_probe_cached(") >= 3)
  assert_eq(r2_count(src, "300000,"), 0)
}

///|
test "BUG-18：no_sidecar 逃生门存在、默认关闭，且描述写明预算对齐" {
  let src = r2_read_or_abort("src/server/server.mbt")
  // schema 里有这个可选参数，且默认 false（传参不改既有行为）
  assert_true(src.contains("\"no_sidecar\": bool_prop("))
  assert_true(src.contains("get_bool(args, \"no_sidecar\", default=false)"))
  // 规范「工具命名即文档」：描述必须讲清两侧预算关系
  assert_true(src.contains("timeout_ms=30000"))
  assert_true(src.contains("laya_sidecar_budget_ms"))
  // 逃生门分支必须真给 decision（走 route_decision），而不是回一个空降级
  assert_true(r2_count(src, "route_decision(context, split_n_hint)") >= 3)
}

///|
test "BUG-3：audit_log 返回体自我说明（scope/note），空结果不等于没有治理动作" {
  let empty = audit_log_payload([])
  match empty.value("scope") {
    Some(Json::String(s)) => assert_eq(s, "process")
    _ =>
      abort(
        "缺 scope=process，空结果又变回不可区分: " +
        empty.stringify(),
      )
  }
  match empty.value("note") {
    Some(Json::String(n)) => {
      assert_true(n.contains("call_log"))
      assert_true(n.contains("空"))
    }
    _ => abort("缺 note：审计面会伪装成什么都没发生")
  }
  match empty.value("entries") {
    Some(Json::Array(arr)) => assert_eq(arr.length(), 0)
    _ => abort("entries 字段缺失")
  }
  // 有条目时 count/entries 同步增长，scope 仍是 process（不是"落库了"的假承诺）
  let log = @ops.AuditLog::new()
  log.record(
    action="run_check_denied",
    actor="tester",
    task_id="T-r2",
    detail="cmd=rm 被白名单拒",
    now="2026-09-26T12:00:00Z",
  )
  let full = audit_log_payload(log.entries())
  assert_eq(r2_json_int_field(full.stringify(), "count"), 1)
  match full.value("entries") {
    Some(Json::Array(arr)) => {
      assert_eq(arr.length(), 1)
      match arr[0].value("action") {
        Some(Json::String(a)) => assert_eq(a, "run_check_denied")
        _ => abort("条目缺 action")
      }
    }
    _ => abort("有条目时 entries 缺失")
  }
  match full.value("scope") {
    Some(Json::String(s)) => assert_eq(s, "process")
    _ => abort("scope 丢失")
  }
  // 调用点锁：handler 必须真的用这个构造器（改回裸数组就红）
  let src = r2_read_or_abort("src/server/server.mbt")
  assert_true(src.contains("audit_log_payload(entries).stringify()"))
  // 设计注释与对外契约同源（src/ops/audit.mbt 里必须写明"不落库是设计 + 空≠无动作"）
  let ops = r2_read_or_abort("src/ops/audit.mbt")
  assert_true(ops.contains("不落库"))
  assert_true(ops.contains("BUG-3"))
}
