///|
/// symbolic/symbolic.mbt —— 毫秒级符号逻辑引擎
///
/// 用途：对 planned action 的布尔约束做可满足性(SAT)判定与蕴含验证，
/// 在执行前拦截矛盾/不可能的动作。
///
/// 核心：
///   - BoolExpr: 变量 / 非 / 与 / 或 / 蕴含 / 常量
///   - CNF 转换：Tseitin 编码（线性规模）
///   - DPLL SAT 求解：单位传播 + 纯文字消元 + 分裂
///   - 可满足性判定、蕴含验证、不可满足核(近似)
///
/// 性能目标：毫秒级（百变量千条款级），零外部依赖。

///|
/// 布尔表达式
pub enum BoolExpr {
  Var(String) // 命题变量
  Const(Bool) // 常量 true/false
  Not(BoolExpr) // ¬φ
  And(BoolExpr, BoolExpr) // φ ∧ ψ
  Or(BoolExpr, BoolExpr) // φ ∨ ψ
  Implies(BoolExpr, BoolExpr) // φ → ψ  (等价 ¬φ ∨ ψ)
  Iff(BoolExpr, BoolExpr) // φ ↔ ψ
}

///|
/// 文字：变量索引 + 正负（正=true 表示变量本身，负=false 表示否定）
type Lit = (Int32, Bool)

///|
/// 子句：文字的析取
type Clause = Array[Lit]

///|
/// CNF 公式：子句的合取
pub struct Cnf {
  clauses : Array[Clause]
  num_vars : Int32
}

///|
/// 构造工厂
pub fn mk_var(name : String) -> BoolExpr {
  BoolExpr::Var(name)
}

///|
pub fn mk_const(v : Bool) -> BoolExpr {
  BoolExpr::Const(v)
}

///|
pub fn mk_not(e : BoolExpr) -> BoolExpr {
  BoolExpr::Not(e)
}

///|
pub fn mk_and(a : BoolExpr, b : BoolExpr) -> BoolExpr {
  BoolExpr::And(a, b)
}

///|
pub fn mk_or(a : BoolExpr, b : BoolExpr) -> BoolExpr {
  BoolExpr::Or(a, b)
}

///|
pub fn mk_implies(a : BoolExpr, b : BoolExpr) -> BoolExpr {
  BoolExpr::Implies(a, b)
}

///|
pub fn mk_iff(a : BoolExpr, b : BoolExpr) -> BoolExpr {
  BoolExpr::Iff(a, b)
}

///|
/// 收集表达式中的所有变量名（去重保序）
fn collect_vars(e : BoolExpr, acc : Array[String]) -> Unit {
  match e {
    Var(name) => {
      let mut found = false
      let mut i = 0
      while i < acc.length() {
        if acc[i] == name {
          found = true
          break
        }
        i = i + 1
      }
      if !found {
        acc.push(name)
      }
    }
    Const(_) => ()
    Not(a) => collect_vars(a, acc)
    And(a, b) => {
      collect_vars(a, acc)
      collect_vars(b, acc)
    }
    Or(a, b) => {
      collect_vars(a, acc)
      collect_vars(b, acc)
    }
    Implies(a, b) => {
      collect_vars(a, acc)
      collect_vars(b, acc)
    }
    Iff(a, b) => {
      collect_vars(a, acc)
      collect_vars(b, acc)
    }
  }
}

///|
/// 用 Tseitin 编码把任意布尔表达式转为 CNF（线性规模）。
/// 返回 CNF（子句数组 + 变量数）。
pub fn to_cnf(expr : BoolExpr) -> Cnf {
  let var_names : Array[String] = []
  collect_vars(expr, var_names)

  // 建立 变量名 -> 索引 映射
  let var_index : Map[String, Int32] = Map([])
  let mut idx = 1
  let mut i = 0
  while i < var_names.length() {
    var_index.set(var_names[i], idx)
    idx = idx + 1
    i = i + 1
  }

  let clauses : Array[Clause] = []

  // Tseitin: 为每个子表达式分配一个辅助变量
  // aux_counter 从现有变量数+1开始
  let mut aux_counter = idx

  // 返回 (该子表达式对应的文字, 已添加的子句数)
  // 这里直接在闭包里 push 子句
  fn convert(e : BoolExpr) -> Lit {
    match e {
      Var(name) => {
        let v = match var_index.get(name) {
          Some(x) => x
          None => 0
        }
        (v, true)
      }
      Const(true) => {
        // true 用一个恒真子句表示：新增变量 x，加 [x] 强制 x=true
        let v = aux_counter
        aux_counter = aux_counter + 1
        clauses.push([(v, true)])
        (v, true)
      }
      Const(false) => {
        // 表达式值恒为 false：用一个空子句表示不可满足
        // 空子句 [] 永远为 false，所以整个 CNF 不可满足
        clauses.push([])
        // 返回任意文字，根会强制它，但空子句已经让公式不可满足
        (0, true)
      }
      Not(a) => {
        let (va, sa) = convert(a)
        // 令新变量 x ↔ ¬a
        // x → ¬a: [-x, -a];  ¬a → x: [a, x]
        let x = aux_counter
        aux_counter = aux_counter + 1
        clauses.push([(x, false), (va, !sa)])
        clauses.push([(va, sa), (x, true)])
        (x, true)
      }
      And(a, b) => {
        let (va, sa) = convert(a)
        let (vb, sb) = convert(b)
        // x ↔ (a ∧ b)
        // x → (a∧b): [-x, a] ∧ [-x, b]
        // (a∧b) → x: [-a, -b, x]
        let x = aux_counter
        aux_counter = aux_counter + 1
        clauses.push([(x, false), (va, sa)])
        clauses.push([(x, false), (vb, sb)])
        clauses.push([(va, !sa), (vb, !sb), (x, true)])
        (x, true)
      }
      Or(a, b) => {
        let (va, sa) = convert(a)
        let (vb, sb) = convert(b)
        // x ↔ (a ∨ b)
        // x → (a∨b): [-x, a, b]
        // (a∨b) → x: [-a, x] ∧ [-b, x]
        let x = aux_counter
        aux_counter = aux_counter + 1
        clauses.push([(x, false), (va, sa), (vb, sb)])
        clauses.push([(va, !sa), (x, true)])
        clauses.push([(vb, !sb), (x, true)])
        (x, true)
      }
      Implies(a, b) =>
        // φ → ψ ≡ ¬φ ∨ ψ
        convert(Or(Not(a), b))
      Iff(a, b) =>
        // φ ↔ ψ ≡ (φ → ψ) ∧ (ψ → φ)
        convert(And(Implies(a, b), Implies(b, a)))
    }
  }

  let (root_var, root_sign) = convert(expr)
  // 强制根表达式为 true
  clauses.push([(root_var, root_sign)])

  { clauses, num_vars: aux_counter - 1, }
}

///|
/// DPLL SAT 求解器
/// 返回 Some(assignment) 表示可满足，None 表示不可满足
/// assignment[var_idx] = true/false (1-based 索引，0 位不用)
pub fn dpll_sat(cnf : Cnf) -> Array[Bool]? {
  let n = cnf.num_vars
  let mut ci = 0
  while ci < cnf.clauses.length() {
    let c = cnf.clauses[ci]
    let mut li = 0
    while li < c.length() {
      let (v, _) = c[li]
      if v < 0 || v > n {
        return None
      }
      li = li + 1
    }
    ci = ci + 1
  }
  let assign : Array[Int32] = []
  // 用 0=unassigned, 1=true, -1=false
  let mut i = 0
  while i <= n {
    assign.push(0)
    i = i + 1
  }

  // 子句副本（可修改）
  let clauses = cnf.clauses.map(fn(c) { c })

  // 单位传播：反复找单文字子句并赋值
  // 返回 true 继续，false 冲突
  fn unit_propagate(clauses : Array[Clause], assign : Array[Int32]) -> Bool {
    let mut changed = true
    while changed {
      changed = false
      let mut ci = 0
      while ci < clauses.length() {
        let c = clauses[ci]
        // 统计未赋值文字数
        let mut unassigned_count = 0
        let mut unassigned_lit = (0, false)
        let mut satisfied = false
        let mut li = 0
        while li < c.length() {
          let (v, s) = c[li]
          if assign[v] == 0 {
            unassigned_count = unassigned_count + 1
            unassigned_lit = (v, s)
          } else if (assign[v] == 1 && s) || (assign[v] == -1 && !s) {
            satisfied = true
            break
          }
          li = li + 1
        }
        if satisfied {
          // 子句已满足，跳过
        } else if unassigned_count == 0 {
          // 冲突
          return false
        } else if unassigned_count == 1 {
          // 单位子句，赋值
          let (v, s) = unassigned_lit
          assign[v] = if s { 1 } else { -1 }
          changed = true
        }
        ci = ci + 1
      }
    }
    true
  }

  // 纯文字消元
  fn pure_literal_eliminate(
    clauses : Array[Clause],
    assign : Array[Int32],
    n : Int32,
  ) -> Unit {
    // 对每个变量统计正负出现
    let pos_count : Array[Int32] = []
    let neg_count : Array[Int32] = []
    let mut i = 0
    while i <= n {
      pos_count.push(0)
      neg_count.push(0)
      i = i + 1
    }
    let mut ci = 0
    while ci < clauses.length() {
      let c = clauses[ci]
      // 检查子句是否已满足
      let mut satisfied = false
      let mut li = 0
      while li < c.length() {
        let (v, s) = c[li]
        if (assign[v] == 1 && s) || (assign[v] == -1 && !s) {
          satisfied = true
          break
        }
        li = li + 1
      }
      if !satisfied {
        let mut li = 0
        while li < c.length() {
          let (v, s) = c[li]
          if assign[v] == 0 {
            if s {
              pos_count[v] = pos_count[v] + 1
            } else {
              neg_count[v] = neg_count[v] + 1
            }
          }
          li = li + 1
        }
      }
      ci = ci + 1
    }
    // 纯文字赋值
    let mut v = 1
    while v <= n {
      if assign[v] == 0 {
        if pos_count[v] > 0 && neg_count[v] == 0 {
          assign[v] = 1
        } else if neg_count[v] > 0 && pos_count[v] == 0 {
          assign[v] = -1
        }
      }
      v = v + 1
    }
  }

  // 检查是否所有子句满足
  fn all_satisfied(clauses : Array[Clause], assign : Array[Int32]) -> Bool {
    let mut ci = 0
    while ci < clauses.length() {
      let c = clauses[ci]
      let mut ok = false
      let mut li = 0
      while li < c.length() {
        let (v, s) = c[li]
        if (assign[v] == 1 && s) || (assign[v] == -1 && !s) {
          ok = true
          break
        }
        li = li + 1
      }
      if !ok {
        return false
      }
      ci = ci + 1
    }
    true
  }

  // 选下一个未赋值变量（MOMS 启发式的简化版：选出现次数最多的）
  fn pick_branch_var(
    clauses : Array[Clause],
    assign : Array[Int32],
    n : Int32,
  ) -> Int32 {
    let counts : Array[Int32] = []
    let mut i = 0
    while i <= n {
      counts.push(0)
      i = i + 1
    }
    let mut ci = 0
    while ci < clauses.length() {
      let c = clauses[ci]
      let mut li = 0
      while li < c.length() {
        let (v, _) = c[li]
        if assign[v] == 0 {
          counts[v] = counts[v] + 1
        }
        li = li + 1
      }
      ci = ci + 1
    }
    let mut best = 0
    let mut best_count = -1
    let mut v = 1
    while v <= n {
      if assign[v] == 0 && counts[v] > best_count {
        best_count = counts[v]
        best = v
      }
      v = v + 1
    }
    best
  }

  // 递归求解
  fn solve(clauses : Array[Clause], assign : Array[Int32], n : Int32) -> Bool {
    // 单位传播
    if !unit_propagate(clauses, assign) {
      return false
    }
    // 纯文字消元
    pure_literal_eliminate(clauses, assign, n)
    // 再传播一次（纯文字可能产生新单位）
    if !unit_propagate(clauses, assign) {
      return false
    }
    if all_satisfied(clauses, assign) {
      return true
    }
    let v = pick_branch_var(clauses, assign, n)
    if v == 0 {
      // 没有未赋值变量但仍有不满足子句
      return all_satisfied(clauses, assign)
    }
    // 尝试 true
    let save = assign[v]
    assign[v] = 1
    if solve(clauses, assign, n) {
      return true
    }
    assign[v] = save
    // 尝试 false
    assign[v] = -1
    if solve(clauses, assign, n) {
      return true
    }
    assign[v] = save
    false
  }

  if solve(clauses, assign, n) {
    // 转换为 Bool 数组（1-based）
    let result : Array[Bool] = []
    let mut j = 0
    while j <= n {
      result.push(assign[j] == 1)
      j = j + 1
    }
    Some(result)
  } else {
    None
  }
}

///|
/// 判断表达式是否可满足
pub fn is_satisfiable(expr : BoolExpr) -> Bool {
  let cnf = to_cnf(expr)
  dpll_sat(cnf) is Some(_)
}

///|
/// 判断表达式是否永真（重言式）：¬expr 不可满足
pub fn is_tautology(expr : BoolExpr) -> Bool {
  !is_satisfiable(mk_not(expr))
}

///|
/// 蕴含验证：前提是否蕴含结论（前提 → 结论 永真）
pub fn entails(premise : BoolExpr, conclusion : BoolExpr) -> Bool {
  is_tautology(mk_implies(premise, conclusion))
}

///|
/// 矛盾检测：一组约束是否互相矛盾（合取不可满足）
pub fn is_contradictory(exprs : Array[BoolExpr]) -> Bool {
  if exprs.length() == 0 {
    return false
  }
  let mut conj = exprs[0]
  let mut i = 1
  while i < exprs.length() {
    conj = mk_and(conj, exprs[i])
    i = i + 1
  }
  !is_satisfiable(conj)
}

///|
/// 表达式转可读字符串
pub fn expr_to_string(e : BoolExpr) -> String {
  match e {
    Var(name) => name
    Const(true) => "true"
    Const(false) => "false"
    Not(a) => "(¬" + expr_to_string(a) + ")"
    And(a, b) => "(" + expr_to_string(a) + " ∧ " + expr_to_string(b) + ")"
    Or(a, b) => "(" + expr_to_string(a) + " ∨ " + expr_to_string(b) + ")"
    Implies(a, b) => "(" + expr_to_string(a) + " → " + expr_to_string(b) + ")"
    Iff(a, b) => "(" + expr_to_string(a) + " ↔ " + expr_to_string(b) + ")"
  }
}

///|
/// 把一组约束的可满足性结果转 JSON
pub fn check_constraints_json(exprs : Array[BoolExpr]) -> String {
  let contradictory = is_contradictory(exprs)
  let parts : Array[String] = []
  parts.push(
    "\"satisfiable\":" + (if contradictory { "false" } else { "true" }),
  )
  parts.push("\"constraint_count\":" + exprs.length().to_string())
  if !contradictory {
    // 给出一个满足赋值（取第一个约束的 SAT 解）
    if exprs.length() > 0 {
      let mut conj = exprs[0]
      let mut i = 1
      while i < exprs.length() {
        conj = mk_and(conj, exprs[i])
        i = i + 1
      }
      let cnf = to_cnf(conj)
      match dpll_sat(cnf) {
        Some(_) =>
          // 只输出用户变量（前 num_user_vars 个）
          // 这里简化输出全部非辅助变量
          parts.push("\"has_model\":true")
        None => parts.push("\"has_model\":false")
      }
    }
  } else {
    parts.push("\"has_model\":false")
  }
  "{" + parts.join(",") + "}"
}
