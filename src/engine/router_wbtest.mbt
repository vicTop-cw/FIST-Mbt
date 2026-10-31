/// engine/router_wbtest.mbt —— `router.mbt` 的风险词判定白盒锁（R101）
///
/// ## 为什么补这个文件
///
/// **BUG-202（high）的修复没有测试。** 实测（R101）：
/// ```
/// grep -rn "contains_risk_kw" src/ --include="*test*.mbt" --include="*wbtest*.mbt"  → 0 命中
/// ```
/// 而 `BUG-202` 的修复（`memory/bugs.md` 的 `### FIXED(2026-10-15T10:26:00Z / BUG-202)`）原文写：
/// > `src/engine/router.mbt L76-97` 的 `contains_risk_kw` 改用同包 `scheduler.mbt` 的 `_has_word`
///
/// **⇒ 也就是说：把「子串匹配」换成「词边界匹配」这件事**已经被修**，但没有锁。**
/// **⇒ 没有锁 = 下一个人可以静默改回子串匹配，而 `plan_route` 会把「workforce」判成 L4 不可逆。**
///
/// 而 `plan_route` 本身**零调用者**（实测：全仓只有 `src/engine/router.mbt` 自己的定义，
/// 没有 `server.mbt` 接线、没有其他 src 引用）⇒ **它是这个判定的唯一消费者，
/// 而它连一条执行路径都没有 ⇒ 这个 bug 的修复面**完全在测试之外**。**
///
/// ## 变异对照（判例-29/30 硬要求）
///
/// 把 `contains_risk_kw` 的 `_has_word(lower, kw)` 改回 `lower.contains(kw)`（子串匹配，BUG-202 的原始形态）
/// ⇒ **`risk_word_is_boundary_aware` 必红**（`workforce` / `execution` 会被误判为风险）。
///
/// ## 本格锁三件事
///
/// 1. **真风险词必须命中**（`delete` / `drop` / `exec` 等）
/// 2. **词边界内的误命中必须不命中**（BUG-202 的正身：`execution` / `workforce` / `formatting`）
/// 3. **大小写不敏感**（`DELETE` 也该命中）

///|
test "risk_word_hits_real_keywords" {
  // 真风险词必须命中（各族取一个代表）
  assert_true(contains_risk_kw("delete the table"))
  assert_true(contains_risk_kw("drop database"))
  assert_true(contains_risk_kw("run exec command"))
  assert_true(contains_risk_kw("force push"))
  assert_true(contains_risk_kw("publish release"))
}

///|
test "risk_word_is_boundary_aware" {
  // ⚠️ **BUG-202 的正身**：子串匹配会把这些**误判**成 L4 不可逆，词边界匹配不会。
  //
  // `execution` 含子串 `exec`、`workforce` 含子串 `force`、`formatting` 含子串 `format`
  // —— 而它们**都不是风险动作**。
  assert_false(contains_risk_kw("improve the execution speed"))
  assert_false(contains_risk_kw("analyze workforce data"))
  assert_false(contains_risk_kw("fix formatting issues"))
  // 其它族的同形误命中
  assert_false(contains_risk_kw("undeleted records"))
}

///|
test "risk_word_case_insensitive" {
  // 大小写不敏感（实现里先 `desc.to_lower()`）
  assert_true(contains_risk_kw("DELETE the table"))
  assert_true(contains_risk_kw("Drop Database"))
  // 而大小写变形的**非风险词**仍不命中
  assert_false(contains_risk_kw("Improve the EXECUTION speed"))
}

///|
test "risk_word_multi_word_boundaries" {
  // 词边界：连字符/下划线算分隔符吗？—— 实现用 `_has_word`，
  // 本格只锁「独立词命中」这一条（分隔符细节由 `_has_word` 自己的测试负责）
  assert_true(contains_risk_kw("please delete the file"))
  assert_true(contains_risk_kw("we must truncate this"))
  // 而「词的一部分」不命中
  assert_false(contains_risk_kw("undeleted records"))
}
