/// engine_scope_perm_order_wbtest.mbt —— BUG-419 的成对锁：规则匹配必须对表顺序免疫。
///
/// 缺陷原形：`find_matching_rule` 注释称「最长 pattern 优先」，实现却是「第一条匹配即返回」。
/// 现网规则表的顺序**恰好正确**（细节在前、泛化在后）⇒ 侥幸无事故。
///
/// **但实测（Lane U）证明雷是真的**：把一条更宽的 `src/` 规则注入表首后，
///   src/store/store_sqlite.mbt  → 旧实现命中 `src/`（HumanSteward, Leader）
///                              → 最长优先命中 `src/store/store_sqlite.mbt`（HumanSteward）
///   ⇒ **HumanSteward 独占被静默降级成 Leader 也能改**
///   src/server/server.mbt 同理。
/// 两个方向都无报错、无日志、无测试红 —— 这正是「静默遮蔽」。
///
/// 本文件钉三件事：
///   ① 现网规则表下，最长优先与旧行为**完全一致**（零回归证明）
///   ② 造「宽规则排在窄规则前面」的现场 ⇒ 最长优先**仍返回窄规则**（若退回第一条匹配必红）
///   ③ 变异对照：删掉按长度降序 ⇒ 锁 2 必红

///|
/// 锁 1：现网规则表下最长优先 = 旧行为（零回归）
///
/// 对一批真实 scope 断言「最长优先」返回的规则，与「遍历原表第一条命中」返回的规则，
/// 是**同一条 pattern**（不是同一个 struct —— PermissionRule 无 eq，比 pattern 字符串）。
test "scope_perm_order_wb1_no_regression_on_current_table" {
  let scopes = [
    "src/store/store_sqlite.mbt", "src/store/store.mbt", "src/server/server.mbt",
    "moon.mod", "src/core/core_task.mbt", "src/engine/engine.mbt", "src/router/model_router.mbt",
    "src/display/soldier.mbt", "cmd/cli/main.mbt", "plugins/source/x.md", "scripts/foo.py",
    "docs/x.md", "memory/x.md", "templates/x.md", "patches/x.sh", "moon.pkg",
  ]
  for scope in scopes {
    // 旧语义：原表顺序下第一条命中
    let mut old_pattern = ""
    let mut old_found = false
    for rule in scope_permissions {
      if not(old_found) && scope_matches_pattern(scope, rule.pattern) {
        old_pattern = rule.pattern
        old_found = true
      }
    }
    // 新语义：最长优先
    let new_pattern = match find_matching_rule(scope) {
      None => ""
      Some(r) => r.pattern
    }
    assert_eq(new_pattern, old_pattern)
  }
}

///|
/// 锁 2（**关键**）：宽规则排在窄规则前面 ⇒ 最长优先仍返回窄规则
///
/// 这是 BUG-419 的**反例现场**：若实现退回「第一条匹配即返回」，
/// `src/store/store_sqlite.mbt` 会命中先出现的宽规则 `src/` ⇒ 本格必红。
test "scope_perm_order_wb2_wide_rule_first_still_picks_narrow" {
  // 故意把宽规则 `src/` 放在最前面（模拟「未来有人加宽规则并插到表首」）
  let rules = [
    PermissionRule::{
      pattern: "src/",
      allowed_roles: ["HumanSteward", "Leader"],
      reason: "宽规则（测试夹具）：整棵源码树",
    },
    PermissionRule::{
      pattern: "src/store/store_sqlite.mbt",
      allowed_roles: ["HumanSteward"],
      reason: "窄规则（测试夹具）：数据库层唯一真源",
    },
  ]
  // 最长优先必须返回窄规则 ⇒ 只有 HumanSteward
  let hit = match find_matching_rule_in("src/store/store_sqlite.mbt", rules) {
    None => abort("未命中任何规则 —— 匹配本身坏了")
    Some(r) => r
  }
  assert_eq(hit.pattern, "src/store/store_sqlite.mbt")
  assert_eq(hit.allowed_roles.length(), 1)
  assert_eq(hit.allowed_roles[0], "HumanSteward")
  // 关键断言：Leader 不在允许角色里（若被宽规则遮蔽，这里会是 2 且含 Leader）
  if hit.allowed_roles.contains("Leader") {
    fail(
      "★遮蔽未被修：宽规则 src/ 盖掉了窄规则的 HumanSteward 独占",
    )
  }
}

///|
/// 锁 3（变异对照，判例-29）：直接断言 `find_matching_rule_in` 的实现里**真在做长度降序**
///
/// 为什么需要这一格：锁 1/2 只能证明「当前实现返回对了」，
/// 若有人把 `ordered.sort_by(...)` 删掉但恰好规则表顺序仍正确，锁 1/2 还是绿的。
///
/// 判例-30 防护：用**带缩进的精确代码片段**断言（注释里写的是中文说明，
/// 不会出现 `  ordered.sort_by(` 这种真代码形状）。
test "scope_perm_order_wb3_sort_by_wired" {
  let src = @fs.read_file_to_string(
    "src/engine/engine_scope_perm.mbt",
    encoding="utf8",
  ) catch {
    _ =>
      abort(
        "读 src/engine/engine_scope_perm.mbt 失败：接线格没跑到被测面",
      )
  }
  assert_true(src.contains("  let ordered = rules.copy()"))
  assert_true(src.contains("  ordered.sort_by("))
  assert_true(src.contains("  for rule in ordered {"))
}
