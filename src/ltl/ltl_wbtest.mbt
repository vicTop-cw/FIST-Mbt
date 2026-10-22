// LTL runtime monitor 白盒测试

///|
test "原子命题真/假" {
  let s1 = State::new().set("p".to_string(), true)
  let s2 = State::new().set("p".to_string(), false)
  assert_eq(evaluate(atom("p".to_string()), [s1]), Hold)
  assert_eq(evaluate(atom("p".to_string()), [s2]), Violated)
}

///|
test "否定算子" {
  let s = State::new().set("p".to_string(), true)
  assert_eq(evaluate(Not(atom("p".to_string())), [s]), Violated)
  assert_eq(evaluate(Not(Not(atom("p".to_string()))), [s]), Hold)
}

///|
test "合取与析取" {
  let s = State::new().set("p".to_string(), true).set("q".to_string(), false)
  assert_eq(
    evaluate(And(atom("p".to_string()), atom("q".to_string())), [s]),
    Violated,
  )
  assert_eq(
    evaluate(Or(atom("p".to_string()), atom("q".to_string())), [s]),
    Hold,
  )
}

///|
test "G p 全局不变式：违反即 Violated" {
  let f = globally(atom("p".to_string()))
  let s1 = State::new().set("p".to_string(), true)
  let s2 = State::new().set("p".to_string(), true)
  let s3 = State::new().set("p".to_string(), false)
  assert_eq(evaluate(f, [s1, s2, s3]), Violated)
}

///|
test "G p 全局不变式：全程成立 → Unknown（有限轨迹保守）" {
  let f = globally(atom("p".to_string()))
  let s1 = State::new().set("p".to_string(), true)
  let s2 = State::new().set("p".to_string(), true)
  assert_eq(evaluate(f, [s1, s2]), Unknown)
}

///|
test "F p 终将：出现即 Hold" {
  let f = eventually(atom("p".to_string()))
  let s1 = State::new().set("p".to_string(), false)
  let s2 = State::new().set("p".to_string(), false)
  let s3 = State::new().set("p".to_string(), true)
  assert_eq(evaluate(f, [s1, s2, s3]), Hold)
}

///|
test "F p 终将：未出现 → Unknown" {
  let f = eventually(atom("p".to_string()))
  let s1 = State::new().set("p".to_string(), false)
  let s2 = State::new().set("p".to_string(), false)
  assert_eq(evaluate(f, [s1, s2]), Unknown)
}

///|
test "X 下一状态" {
  let f = Next(atom("p".to_string()))
  let s1 = State::new().set("p".to_string(), false)
  let s2 = State::new().set("p".to_string(), true)
  assert_eq(evaluate(f, [s1, s2]), Hold)
  assert_eq(evaluate(f, [s1]), Unknown)
}

///|
test "U 直到：ψ 出现前 φ 必须成立" {
  let f = Until(atom("p".to_string()), atom("q".to_string()))
  let s1 = State::new().set("p".to_string(), true).set("q".to_string(), false)
  let s2 = State::new().set("p".to_string(), true).set("q".to_string(), false)
  let s3 = State::new().set("p".to_string(), false).set("q".to_string(), true)
  assert_eq(evaluate(f, [s1, s2, s3]), Hold)
  let bad = State::new().set("p".to_string(), false).set("q".to_string(), false)
  assert_eq(evaluate(f, [bad, s3]), Violated)
}

///|
test "implies 蕴含：p → q" {
  let f = implies(atom("p".to_string()), atom("q".to_string()))
  let s1 = State::new().set("p".to_string(), true).set("q".to_string(), false)
  assert_eq(evaluate(f, [s1]), Violated)
  let s2 = State::new().set("p".to_string(), false).set("q".to_string(), false)
  assert_eq(evaluate(f, [s2]), Hold)
  let s3 = State::new().set("p".to_string(), true).set("q".to_string(), true)
  assert_eq(evaluate(f, [s3]), Hold)
}

///|
test "任务生命周期不变式：G(pending -> F claimed)" {
  let f = globally(
    implies(
      atom("pending".to_string()),
      eventually(atom("claimed".to_string())),
    ),
  )
  let s1 = State::new()
    .set("pending".to_string(), true)
    .set("claimed".to_string(), false)
  let s2 = State::new()
    .set("pending".to_string(), false)
    .set("claimed".to_string(), true)
  let s3 = State::new()
    .set("pending".to_string(), false)
    .set("claimed".to_string(), false)
    .set("executing".to_string(), true)
  assert_eq(evaluate(f, [s1, s2, s3]), Unknown)
}

///|
test "formula_to_string 可读输出" {
  let f = globally(
    implies(atom("p".to_string()), eventually(atom("q".to_string()))),
  )
  let s = formula_to_string(f)
  assert_true(s.contains("U"))
  assert_true(s.contains("p"))
  assert_true(s.contains("q"))
}

///|
test "空轨迹常量" {
  assert_eq(evaluate(ltl_true(), []), Hold)
  assert_eq(evaluate(atom("p".to_string()), []), Unknown)
}
