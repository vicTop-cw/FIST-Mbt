// 符号逻辑引擎白盒测试

///|
test "可满足：p ∨ ¬p" {
  let p = mk_var("p")
  let expr = mk_or(p, mk_not(p))
  assert_true(is_satisfiable(expr))
  assert_true(is_tautology(expr))
}

///|
test "不可满足：p ∧ ¬p" {
  let p = mk_var("p")
  let expr = mk_and(p, mk_not(p))
  assert_false(is_satisfiable(expr))
  assert_false(is_tautology(expr))
}

///|
test "蕴含验证：p ∧ q ⊨ p" {
  let p = mk_var("p")
  let q = mk_var("q")
  let premise = mk_and(p, q)
  assert_true(entails(premise, p))
}

///|
test "蕴含不成立：p ∨ q ⊭ p" {
  let p = mk_var("p")
  let q = mk_var("q")
  let premise = mk_or(p, q)
  assert_false(entails(premise, p))
}

///|
test "矛盾检测：多约束互相矛盾" {
  let p = mk_var("p")
  let q = mk_var("q")
  let exprs = [p, mk_not(p), q]
  assert_true(is_contradictory(exprs))
}

///|
test "非矛盾：多约束可满足" {
  let p = mk_var("p")
  let q = mk_var("q")
  let exprs = [p, q, mk_or(p, q)]
  assert_false(is_contradictory(exprs))
}

///|
test "蕴含等价：p → q ≡ ¬p ∨ q" {
  let p = mk_var("p")
  let q = mk_var("q")
  let a = mk_implies(p, q)
  let b = mk_or(mk_not(p), q)
  assert_true(entails(a, b))
  assert_true(entails(b, a))
}

///|
test "常量 true/false" {
  assert_true(is_satisfiable(mk_const(true)))
  assert_false(is_satisfiable(mk_const(false)))
  assert_true(is_tautology(mk_const(true)))
}

///|
test "iff 双向蕴含" {
  let p = mk_var("p")
  let q = mk_var("q")
  let expr = mk_iff(p, q)
  // p ↔ q 可满足
  assert_true(is_satisfiable(expr))
  // p ↔ q 不等价于 p → q（前者更强）
  assert_true(entails(mk_iff(p, q), mk_implies(p, q)))
}

///|
test "多变量可满足性" {
  let a = mk_var("a")
  let b = mk_var("b")
  let c = mk_var("c")
  // (a ∨ b) ∧ (¬a ∨ c) ∧ (¬b ∨ ¬c)
  let expr = mk_and(
    mk_or(a, b),
    mk_and(mk_or(mk_not(a), c), mk_or(mk_not(b), mk_not(c))),
  )
  assert_true(is_satisfiable(expr))
}

///|
test "表达式字符串输出" {
  let p = mk_var("p")
  let q = mk_var("q")
  let expr = mk_and(p, mk_or(q, mk_not(p)))
  let s = expr_to_string(expr)
  assert_true(s.contains("p"))
  assert_true(s.contains("q"))
}

///|
test "check_constraints_json 矛盾约束" {
  let p = mk_var("p")
  let json = check_constraints_json([p, mk_not(p)])
  assert_true(json.contains("\"satisfiable\":false"))
  assert_true(json.contains("\"has_model\":false"))
}
