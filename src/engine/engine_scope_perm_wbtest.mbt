/// engine_scope_perm_wbtest.mbt —— BUG-413 的成对锁：三种拒绝面必须能被区分。
///
/// 缺陷原形（本轮实测）：`check_scope_permission` 返回 `Result[PermissionRule, String]`，
/// 把「有规则但角色不够」与「根本没有匹配规则」压成同一个 `Err(String)`。
/// 于是 explore 模式的并行门第 4 道（要求 reserve_scope 拿到 granted）**恒不可过**：
/// `reports/` 这类未登记路径永远拿不到 granted，只能靠人工「字面不相交」自律。
///
/// 本文件钉五件事：
///   ① 未登记路径 ⇒ Unregistered（新行为）
///   ② 已登记 + 够格 ⇒ Allowed（零回归）
///   ③ **HumanSteward 保护路径仍必须拒绝** —— 防 unregistered 被当成绕过口（最关键）
///   ④ 三种面互不相等（分类器判别力）
///   ⑤ 接线格：engine_rsv 的实现必须真的按三态分流，而不只是纯函数改对了（判例-29）

///|
/// 锁 1：**未登记路径** ⇒ Unregistered（BUG-413 新行为）
test "scope_perm_wb1_unregistered_path" {
  match check_scope_permission("reports/x.md", "Executor") {
    Unregistered(_) => ()
    Allowed =>
      abort(
        "未登记路径被判成 Allowed —— unregistered 分支没走到",
      )
    RoleDenied(e) =>
      abort("未登记仍走 fail-closed（BUG-413 未修）：" + e)
  }
}

///|
/// 锁 2：**已登记 + 够格** ⇒ Allowed（零回归）
test "scope_perm_wb2_registered_allowed" {
  match check_scope_permission("scripts/foo.py", "Executor") {
    Allowed => ()
    Unregistered(_) =>
      abort("已登记路径被判成 Unregistered —— 规则匹配坏了")
    RoleDenied(e) => abort("Executor 应可改 scripts/：" + e)
  }
}

///|
/// 锁 3（**最关键**）：**HumanSteward 保护路径仍必须拒绝**
/// —— 防 `unregistered` 被当成绕过口。
test "scope_perm_wb3_humansteward_still_denied" {
  let guarded = [
    "src/store/store_sqlite.mbt", "src/store/store.mbt", "src/server/server.mbt",
    "moon.mod",
  ]
  for scope in guarded {
    match check_scope_permission(scope, "Executor") {
      RoleDenied(_) => ()
      Allowed => abort("★保护被绕过：" + scope + " 对 Executor 放行")
      Unregistered(_) =>
        abort("★保护被绕过：" + scope + " 变成 unregistered")
    }
    // Leader 也改不了这四条（只有 HumanSteward）
    match check_scope_permission(scope, "Leader") {
      RoleDenied(_) => ()
      _ => abort("★豁免过宽：Leader 不该能改 " + scope)
    }
  }
}

///|
/// 锁 4：三种面必须互不相等（分类器判别力）
test "scope_perm_wb4_three_faces_distinct" {
  let tag = fn(v : ScopeVerdict) -> String {
    match v {
      Allowed => "allowed"
      RoleDenied(_) => "role_denied"
      Unregistered(_) => "unregistered"
    }
  }
  assert_eq(tag(check_scope_permission("scripts/x.py", "Executor")), "allowed")
  assert_eq(
    tag(check_scope_permission("reports/x.md", "Executor")),
    "unregistered",
  )
  assert_eq(
    tag(check_scope_permission("src/server/server.mbt", "Executor")),
    "role_denied",
  )
}

///|
/// 锁 5（**接线格**，判例-29）：`rsv_try_set` 的实现必须真的调用三态并分流，
/// 而不是只测了纯函数 check_scope_permission。
///
/// 为什么需要这一格：如果把 `engine_rsv.mbt` 里的三态分流改回 `Err(e) => Err(e)`，
/// 锁 1~4 全绿但它已经退化回 fail-closed —— **纯函数对了不等于接线对了**。
///
/// 判例-30 防护：用 `^` 行首锚定 + 只比对真实代码行，避免命中注释里的字面量。
test "scope_perm_wb5_rsv_try_set_wired" {
  let src = @fs.read_file_to_string(
    "src/engine/engine_rsv.mbt",
    encoding="utf8",
  ) catch {
    _ =>
      abort(
        "读 src/engine/engine_rsv.mbt 失败：接线格没跑到被测面",
      )
  }
  // 用**带缩进的精确代码片段**断言（判例-30：注释里写的是中文描述，
  // 不会出现 "    RoleDenied(e) => Err(e)" 这种带 4 空格缩进的真代码形状）。
  assert_true(src.contains("    RoleDenied(e) => Err(e)"))
  assert_true(src.contains("    Unregistered(_) =>"))
  assert_true(src.contains("o.relabel(\"unregistered\")"))
}
