/// engine/cost_tool_wbtest.mbt —— `cost_tool` 的 JSON 入口与预算判据白盒锁（R99）
///
/// ## 为什么补这个文件
///
/// 实测（R99）：`src/engine/cost_tool.mbt` 的两个 pub 函数在**全仓测试文本里零出现**：
///   · `budget_check(limit, current)`  —— 预算判据本体
///   · `budget_check_json(args)`       —— MCP 工具的 JSON 入口
///
/// 而这两个函数各自带着**两处已修 bug 的承诺**，没有锁 = 下一个人可以静默改回去：
///
/// | 承诺 | 出处 | 本文件哪格锁它 |
/// |---|---|---|
/// | 缺 `limit` 时**不得**回退 100.0（那会谎报「预算充足」）| BUG-211 | `json_missing_limit_is_rejected` |
/// | 非法预算（`limit <= 0`）**不做超支判定**，直接 rejected | BUG-181② | `nonpositive_limit_short_circuits` |
/// | 超支时 `remaining` **保留负值**（=超支额），不抹成 0 | BUG-181① | `exceeded_keeps_negative_remaining` |
///
/// ## 变异对照（判例-29/30 硬要求）
///
/// 把 `budget_check_json` 的 `_ => 0.0` 改回 `_ => 100.0` ⇒ `json_missing_limit_is_rejected` **必红**。
/// 把 `budget_check` 的 `remaining = limit - current` 改成 `max(0, …)` ⇒ `exceeded_keeps_negative_remaining` **必红**。
/// 删掉 `if limit <= 0.0` 短路 ⇒ `nonpositive_limit_short_circuits` **必红**。

///|
/// 从 JSON 结果里取布尔键（`jget` 只解 Number/String，必须直接 match）。
fn bc_key(j : Json, k : String) -> Json? {
  match j {
    Object(m) => m.get(k)
    _ => None
  }
}

///|
test "json_missing_limit_is_rejected" {
  // ⚠️ **BUG-211 的正身**：缺 `limit` 必须回退 **0.0**（走非法预算分支），
  //    而不是回退 100.0 —— 后者会让 `current=50` 被判「预算充足」，那是**谎报**。
  let r = budget_check_json(Json::object({ "current": Json::number(50.0) }))
  // 拿不到 limit ⇒ limit=0 ⇒ valid=false / exceeded=false / action=rejected
  assert_eq(bc_key(r, "valid") |> Option::unwrap, Json::boolean(false))
  assert_eq(bc_key(r, "exceeded") |> Option::unwrap, Json::boolean(false))
  // ⚠️ 关键：若回退成 100.0，则 limit 会是 100、current 50 ⇒ valid=true
  //    ⇒ 下面这条会红。这就是本格的变异对照点。
  let lim = match bc_key(r, "limit") {
    Some(Number(n, ..)) => n
    _ => -1.0
  }
  assert_eq(lim, 0.0)
}

///|
test "json_full_form_computes_correctly" {
  // 正常形：limit=100 / current=40 ⇒ 未超支、remaining=60
  let r = budget_check_json(
    Json::object({ "limit": Json::number(100.0), "current": Json::number(40.0) }),
  )
  assert_eq(bc_key(r, "valid") |> Option::unwrap, Json::boolean(true))
  assert_eq(bc_key(r, "exceeded") |> Option::unwrap, Json::boolean(false))
  let rem = match bc_key(r, "remaining") {
    Some(Number(n, ..)) => n
    _ => -1.0
  }
  assert_eq(rem, 60.0)
}

///|
test "json_missing_current_defaults_zero" {
  // 缺 `current` 回退 0.0 是**合理**的（0 消耗 ≠ 谎报）—— 与缺 limit 的性质不同
  let r = budget_check_json(Json::object({ "limit": Json::number(10.0) }))
  assert_eq(bc_key(r, "valid") |> Option::unwrap, Json::boolean(true))
  assert_eq(bc_key(r, "exceeded") |> Option::unwrap, Json::boolean(false))
}

///|
test "nonpositive_limit_short_circuits" {
  // BUG-181②：limit <= 0 ⇒ **不做过支判定**，直接 rejected
  // 连「current 很大」也不报 exceeded（因为根本没做判定）
  let r = budget_check(0.0, 999.0)
  assert_eq(bc_key(r, "valid") |> Option::unwrap, Json::boolean(false))
  assert_eq(bc_key(r, "exceeded") |> Option::unwrap, Json::boolean(false))
  let act = match bc_key(r, "action") {
    Some(String(s)) => s
    _ => ""
  }
  assert_eq(act, "rejected")
  // 负数同理
  let r2 = budget_check(-5.0, 1.0)
  assert_eq(bc_key(r2, "valid") |> Option::unwrap, Json::boolean(false))
}

///|
test "exceeded_keeps_negative_remaining" {
  // BUG-181①：超支时 `remaining` **保留负值**（= 超支额），不抹成 0
  // 这一格是变异对照点：把 `limit - current` 改成 `max(0, …)` 必红
  let r = budget_check(100.0, 150.0)
  assert_eq(bc_key(r, "exceeded") |> Option::unwrap, Json::boolean(true))
  let rem = match bc_key(r, "remaining") {
    Some(Number(n, ..)) => n
    _ => 999.0
  }
  assert_eq(rem, -50.0)
}

///|
test "boundary_exactly_at_limit_is_exceeded" {
  // 边界：`current >= limit` ⇒ exceeded（**等号算超支**）
  let r = budget_check(100.0, 100.0)
  assert_eq(bc_key(r, "exceeded") |> Option::unwrap, Json::boolean(true))
  // 差一点点不算超支
  let r2 = budget_check(100.0, 99.999)
  assert_eq(bc_key(r2, "exceeded") |> Option::unwrap, Json::boolean(false))
}
