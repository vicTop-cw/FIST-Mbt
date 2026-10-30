
///|
/// R223：监控器的前缀单调性（runtime monitoring 的核心保证）。
///
/// 安全属性一旦被违反，再多状态也不能修复 —— 这是运行时监控能被信任的前提：
/// 报警之后继续灌数据，结论不能自己变回 Hold/Unknown。若求解器有 bug（例如
/// globally 只在整段轨迹上判、遇到长度变化就重算成 Unknown），该性质就会破。
/// 既有的 13 格只测单点结论，测不出这种「随轨迹增长而反悔」。
///
/// （R221 曾写过同名文件但用了不存在的 not_/or_/until_ 构造器、未验证即被打断；
/// 本版只用真源里实际存在的 API：atom/globally/eventually/and_/next_/implies
/// 加枚举变体 Not/Or/Until 直构，写完立刻验证。）
test "G p 的 Violated 在任意扩展下保持（前缀单调性）" {
  let p = atom("p")
  let g = globally(p)
  let prefix : Array[State] = [State::new().set("p", true), State::new().set("p", false)]
  assert_eq(evaluate(g, prefix), Violated, msg="前缀应已 Violated")
  let tails : Array[Array[State]] = [
    [State::new().set("p", true)],
    [State::new().set("p", true), State::new().set("p", true)],
    [State::new().set("p", false), State::new().set("p", true)],
  ]
  for tail in tails {
    let longer : Array[State] = []
    for s in prefix {
      longer.push(s)
    }
    for s in tail {
      longer.push(s)
    }
    assert_eq(evaluate(g, longer), Violated, msg="扩展后 Violated 被翻转 —— 监控器会反悔")
  }
}

///|
/// R223：F p 的 Hold 只增不减（对偶方向）。
test "F p 的 Hold 在任意扩展下保持" {
  let p = atom("p")
  let f = eventually(p)
  let prefix : Array[State] = [State::new().set("p", false), State::new().set("p", true)]
  assert_eq(evaluate(f, prefix), Hold, msg="前缀应已 Hold")
  let longer : Array[State] = [
    State::new().set("p", false),
    State::new().set("p", true),
    State::new().set("p", false),
    State::new().set("p", false),
  ]
  assert_eq(evaluate(f, longer), Hold, msg="扩展后 Hold 被翻转")
}

///|
/// R223：monitor_step 与 evaluate 不得各说各话（包装面 = 实现面）。
test "monitor_step 与 evaluate 结论一致" {
  let p = atom("p")
  let q = atom("q")
  let fs : Array[LtlFormula] = [
    p,
    Not(p),
    and_(p, q),
    Or(p, q),
    next_(p),
    eventually(p),
    globally(p),
    implies(p, q),
    Until(p, q),
  ]
  let traces : Array[Array[State]] = [
    [],
    [State::new().set("p", true)],
    [State::new().set("p", false), State::new().set("q", true)],
    [State::new().set("p", true), State::new().set("q", true), State::new().set("p", false)],
  ]
  for f in fs {
    for tr in traces {
      assert_eq(monitor_step(f, tr), evaluate(f, tr), msg="monitor_step 与 evaluate 分叉")
    }
  }
}

///|
/// R223：and_ 的逐面可分解性（组合监控成立的前提）。
test "and_ 的 Hold/Violated 可分解" {
  let a = atom("p")
  let b = atom("q")
  let traces : Array[Array[State]] = [
    [State::new().set("p", true), State::new().set("q", true)],
    [State::new().set("p", true), State::new().set("q", false)],
    [State::new().set("p", false), State::new().set("q", true)],
    [State::new().set("p", false), State::new().set("q", false)],
  ]
  for tr in traces {
    let v_ab = evaluate(and_(a, b), tr)
    let v_a = evaluate(a, tr)
    let v_b = evaluate(b, tr)
    if v_ab == Hold {
      assert_eq(v_a, Hold, msg="and_ Hold 但左面非 Hold")
      assert_eq(v_b, Hold, msg="and_ Hold 但右面非 Hold")
    }
    if v_ab == Violated {
      let any_violated = if v_a == Violated || v_b == Violated {
        true
      } else {
        false
      }
      assert_true(any_violated, msg="and_ Violated 但两面都不 Violated")
    }
  }
}
