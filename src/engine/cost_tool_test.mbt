/// cost_tool_test.mbt —— 成本统计工具测试（aggregate_stats 之外的 budget_check）。
/// BUG-181 两条回归锁：
/// ① 超支时 remaining 为负（=超支额），不许静默归零；
/// ② limit<=0 视为非法预算（valid=false + action=rejected），不报误导性"切换免费模型"。

///|
/// BUG-181①：超支额必须可见——remaining 为负（=current-limit），不再被抹成 0。
test "BUG-181：cost_budget_check 超支时 remaining 为负（超支额可见）" {
  let j = @engine.budget_check(100.0, 150.0)
  match j.value("exceeded") {
    Some(True) => ()
    Some(False) => abort("150>100 应 exceeded: " + j.stringify())
    _ => abort("exceeded 缺失: " + j.stringify())
  }
  match j.value("remaining") {
    Some(Number(n, ..)) => assert_eq(n.to_int(), -50)
    _ =>
      abort(
        "超支后 remaining 应为 -50（BUG-181 静默归零）: " +
        j.stringify(),
      )
  }
  match j.value("action") {
    Some(String(a)) => assert_eq(a, "switch_free")
    _ => abort("action 缺失: " + j.stringify())
  }
  // reason 应带超支额，不只说"超限"
  match j.value("reason") {
    Some(String(r)) =>
      if !r.contains("超支额") {
        abort("reason 应说明超支额: " + r)
      }
    _ => abort("reason 缺失: " + j.stringify())
  }
}

///|
/// BUG-181②：limit<=0 是非法预算，不是"已超支"——不得报 switch_free 误导 action。
/// limit=0 时 current>=0 恒真，旧实现无条件 exceeded=true + switch_free。
test "BUG-181：cost_budget_check limit<=0 视为非法预算，不报误导性 action" {
  let j0 = @engine.budget_check(0.0, 5.0)
  match j0.value("valid") {
    Some(False) => ()
    Some(True) => abort("limit=0 应 valid=false: " + j0.stringify())
    _ => abort("valid 字段缺失: " + j0.stringify())
  }
  match j0.value("exceeded") {
    Some(False) => ()
    Some(True) =>
      abort(
        "limit=0 不应判 exceeded（BUG-181 旧行为）: " + j0.stringify(),
      )
    _ => abort("exceeded 缺失: " + j0.stringify())
  }
  match j0.value("action") {
    Some(String(a)) => assert_eq(a, "rejected")
    _ => abort("limit=0 应 action=rejected: " + j0.stringify())
  }

  let jneg = @engine.budget_check(-10.0, 1.0)
  match jneg.value("action") {
    Some(String(a)) => assert_eq(a, "rejected")
    _ => abort("limit<0 应 action=rejected: " + jneg.stringify())
  }
}

///|
/// 回归零：正常预算、未超支——行为不变（remaining>0、action=continue）。
test "BUG-181：正常预算未超支时行为不变" {
  let j = @engine.budget_check(100.0, 30.0)
  match j.value("valid") {
    Some(True) => ()
    _ => abort("正常预算应 valid=true: " + j.stringify())
  }
  match j.value("exceeded") {
    Some(False) => ()
    _ => abort("30<100 不应 exceeded: " + j.stringify())
  }
  match j.value("remaining") {
    Some(Number(n, ..)) => assert_eq(n.to_int(), 70)
    _ => abort("remaining 应 70: " + j.stringify())
  }
  match j.value("action") {
    Some(String(a)) => assert_eq(a, "continue")
    _ => abort("action 应 continue: " + j.stringify())
  }
}
