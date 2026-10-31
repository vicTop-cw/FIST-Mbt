///|
/// R220：**模型校验锁** —— `dpll_sat` 返回 `Some(model)` 时，`model` 必须**真的满足每一条子句**。
///
/// 为什么补这一格：既有 12 格只断言 `is_satisfiable(expr)` 的**布尔结论**（sat / unsat），
/// **从不校验返回的赋值本身**。一个「判定正确、模型给错」的求解器能让那 12 格全绿，
/// 而下游一旦照着 model 执行动作，就会**按一个假模型走**。
/// ⇒ 对 SAT 求解器而言，「sat/unsat 对了」与「模型可用」是**两件事**（判例-33 同族：
/// 结论面 ≠ 交付面）。
///
/// 语义约定（`symbolic.mbt` doc 注释）：`assignment[var_idx]`，**1-based，0 位不用**。
/// ⇒ 子句里的文字 `(v, s)` 满足 ⟺ `model[v] == s`。
test "dpll_sat 返回的模型必须满足全部子句" {
  let cases : Array[BoolExpr] = [
    mk_or(mk_var("p"), mk_not(mk_var("p"))), // 永真
    mk_and(
      mk_or(mk_var("a"), mk_var("b")),
      mk_or(mk_not(mk_var("a")), mk_var("c")),
    ),
    mk_implies(mk_var("p"), mk_var("q")),
    mk_iff(mk_var("x"), mk_var("y")),
    mk_and(
      mk_var("m"),
      mk_and(mk_var("n"), mk_not(mk_or(mk_var("m"), mk_var("n")))),
    ),
  ]
  for e in cases {
    let cnf = to_cnf(e)
    match dpll_sat(cnf) {
      None => ()
      Some(model) =>
        for clause in cnf.clauses {
          let mut satisfied = false
          for lit in clause {
            let (v, s) = lit
            if v >= 0 && v < model.length() && model[v] == s {
              satisfied = true
            }
          }
          assert_true(
            satisfied,
            msg="dpll_sat 返回了 model，但有子句不被该 model 满足",
          )
        }
    }
  }
}

///|
/// R220：**可满足 ⟺ 有模型** 的双向一致（`is_satisfiable` 与 `dpll_sat` 不得各说各话）。
///
/// `is_satisfiable` 是 `dpll_sat(...).is_some()` 的投影 —— 一旦有人把它改写成"另一套判定"
/// （例如换启发式但忘了同步），这两面就会分叉，而**分叉只会以"某个下游用错"的形式暴露**。
test "is_satisfiable 与 dpll_sat 双向一致" {
  let cases : Array[BoolExpr] = [
    mk_var("p"),
    mk_not(mk_var("p")),
    mk_and(mk_var("p"), mk_not(mk_var("p"))), // unsat
    mk_implies(mk_var("p"), mk_var("q")),
    mk_and(
      mk_implies(mk_var("p"), mk_var("q")),
      mk_and(mk_var("p"), mk_not(mk_var("q"))),
    ), // unsat
    mk_const(true),
    mk_const(false),
  ]
  for e in cases {
    let has_model = match dpll_sat(to_cnf(e)) {
      None => false
      Some(_) => true
    }
    assert_eq(
      is_satisfiable(e),
      has_model,
      msg="is_satisfiable 与 dpll_sat 结论分叉",
    )
  }
}
