// LTL (Linear Temporal Logic) runtime monitor
// 来源：five-directions/§一 P3「Runtime monitoring：按执行 trace 对 LTL 属性低开销认证」
// 设计：纯计算、零副作用、零外部依赖（仅 core/json 用于导出）。
// 支持算子：原子命题 / ¬(not) / ∧(and) / ∨(or) / X(next) / U(until) / F(eventually) / G(globally)
// 语义：有限轨迹（finite trace）下的 LTL 监控语义——
//   - trace 是状态序列，每个状态是一个 Atom -> Bool 的赋值
//   - 求值器在有限前缀上判断"属性是否仍可满足 / 是否已违反"
//   - 返回 Verdict：Hold（已确定满足）/ Violated（已确定违反）/ Unknown（前缀不足，需更多状态）
// 低开销：每个状态只遍历一次公式结构，O(|formula| * |trace|)，不构建自动机。
// 典型用法：把任务的状态变迁序列（pending→claimed→executing→...）作为 trace，
//   用 "G(pending -> F claimed)" 这类不变式在线监控。

///|
pub enum LtlFormula {
  Atom(String) // 原子命题
  Not(LtlFormula) // ¬φ
  And(LtlFormula, LtlFormula) // φ ∧ ψ
  Or(LtlFormula, LtlFormula) // φ ∨ ψ
  Next(LtlFormula) // X φ：下一状态 φ 成立
  Until(LtlFormula, LtlFormula) // φ U ψ：φ 一直成立直到 ψ 成立
  // F φ = true U φ
  // G φ = ¬F ¬φ
}

///|
/// 监控结论
pub enum Verdict {
  Hold // 属性在当前轨迹上已确定满足（对 safety/liveness 语义保守判定）
  Violated // 属性已被违反
  Unknown // 前缀不足，无法确定（需要更多状态）
} derive(Eq, Debug)

///|
pub extend Verdict with Eq::{not_equal, equal}

///|
pub extend Verdict with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// 用派生算子构造 F φ（eventually）
pub fn eventually(f : LtlFormula) -> LtlFormula {
  // F φ = true U φ；true 用 Atom("__true__") 表示，求值时恒真
  Until(Atom("__true__".to_string()), f)
}

///|
/// 用派生算子构造 G φ（globally）
pub fn globally(f : LtlFormula) -> LtlFormula {
  // G φ = ¬F ¬φ = ¬(true U ¬φ)
  Not(eventually(Not(f)))
}

///|
/// 构造 Implies：φ → ψ = ¬φ ∨ ψ
pub fn implies(p : LtlFormula, q : LtlFormula) -> LtlFormula {
  Or(Not(p), q)
}

///|
/// 原子命题便捷构造
pub fn atom(name : String) -> LtlFormula {
  Atom(name)
}

///|
/// 真常量（内部用 __true__ 原子）
pub fn ltl_true() -> LtlFormula {
  Atom("__true__".to_string())
}

///|
/// 一个状态：原子命题 -> 是否成立
/// 用 Map[String, Bool] 存储
pub struct State {
  atoms : Map[String, Bool]
}

///|
pub fn State::new() -> State {
  { atoms: Map([]), }
}

///|
pub fn State::set(self : State, name : String, value : Bool) -> State {
  self.atoms.set(name, value)
  self
}

///|
pub fn State::get(self : State, name : String) -> Bool {
  if name == "__true__" {
    true
  } else if name == "__false__" {
    false
  } else {
    match self.atoms.get(name) {
      Some(v) => v
      None => false // 未声明的原子默认 false
    }
  }
}

///|
/// 有限轨迹 LTL 求值（核心）
/// 语义采用"有限前缀 + 三值判定"：
///   - 对 safety 属性（G p），一旦某状态 p 不成立 → Violated
///   - 对 liveness 属性（F p），若轨迹结束 p 仍未出现 → Unknown（可能下一状态出现）
///   - Hold 只在"已确定无论后续如何都满足"时给出（保守）
pub fn evaluate(formula : LtlFormula, trace : Array[State]) -> Verdict {
  if trace.length() == 0 {
    // 空轨迹：只能判定常量类属性
    return eval_const(formula)
  }
  eval_at(formula, trace, 0)
}

///|
/// 在轨迹位置 i 处求值，返回三值判定
fn eval_at(formula : LtlFormula, trace : Array[State], i : Int32) -> Verdict {
  if i >= trace.length() {
    // 超出轨迹末尾：liveness 属性未完成 → Unknown
    return eval_end(formula)
  }
  let s = trace[i]
  match formula {
    Atom(name) => if s.get(name) { Hold } else { Violated }
    Not(f) =>
      match eval_at(f, trace, i) {
        Hold => Violated
        Violated => Hold
        Unknown => Unknown
      }
    And(p, q) => {
      let vp = eval_at(p, trace, i)
      let vq = eval_at(q, trace, i)
      // 合取：任一 Violated → Violated；两者 Hold → Hold；否则 Unknown
      if vp == Violated || vq == Violated {
        Violated
      } else if vp == Hold && vq == Hold {
        Hold
      } else {
        Unknown
      }
    }
    Or(p, q) => {
      let vp = eval_at(p, trace, i)
      let vq = eval_at(q, trace, i)
      // 析取：任一 Hold → Hold；两者 Violated → Violated；否则 Unknown
      if vp == Hold || vq == Hold {
        Hold
      } else if vp == Violated && vq == Violated {
        Violated
      } else {
        Unknown
      }
    }
    Next(f) =>
      if i + 1 >= trace.length() {
        // 下一状态不在轨迹内 → Unknown（可能下一状态满足）
        Unknown
      } else {
        eval_at(f, trace, i + 1)
      }
    Until(p, q) => eval_until(p, q, trace, i)
  }
}

///|
/// φ U ψ 的求值：
///   - 若当前 ψ 成立 → Hold（直到条件已满足）
///   - 否则若 φ 不成立 → Violated（在 ψ 出现前 φ 就破了）
///   - 否则继续往后看
fn eval_until(
  p : LtlFormula,
  q : LtlFormula,
  trace : Array[State],
  i : Int32,
) -> Verdict {
  let mut j = i
  while j < trace.length() {
    let vq = eval_at(q, trace, j)
    if vq == Hold {
      return Hold
    }
    let vp = eval_at(p, trace, j)
    if vp == Violated {
      return Violated
    }
    // vp 是 Hold 或 Unknown，vq 是 Violated 或 Unknown → 继续
    j = j + 1
  }
  // 轨迹走完仍未看到 ψ → Unknown（liveness 未完成）
  Unknown
}

///|
/// 轨迹结束时的判定（超出末尾）
fn eval_end(formula : LtlFormula) -> Verdict {
  match formula {
    Atom(_) => Unknown // 末尾原子无定义
    Not(f) => negate_unknown(eval_end(f))
    And(p, q) => combine_and_end(eval_end(p), eval_end(q))
    Or(p, q) => combine_or_end(eval_end(p), eval_end(q))
    Next(_) => Unknown
    Until(_, _) => Unknown // U 在末尾未完成 → Unknown
  }
}

///|
fn negate_unknown(v : Verdict) -> Verdict {
  match v {
    Hold => Violated
    Violated => Hold
    Unknown => Unknown
  }
}

///|
fn combine_and_end(a : Verdict, b : Verdict) -> Verdict {
  if a == Violated || b == Violated {
    Violated
  } else if a == Hold && b == Hold {
    Hold
  } else {
    Unknown
  }
}

///|
fn combine_or_end(a : Verdict, b : Verdict) -> Verdict {
  if a == Hold || b == Hold {
    Hold
  } else if a == Violated && b == Violated {
    Violated
  } else {
    Unknown
  }
}

///|
/// 空轨迹常量判定：只对纯常量结构给结论，否则 Unknown
fn eval_const(formula : LtlFormula) -> Verdict {
  match formula {
    Atom(name) =>
      if name == "__true__" {
        Hold
      } else if name == "__false__" {
        Violated
      } else {
        Unknown
      }
    Not(f) => negate_unknown(eval_const(f))
    And(p, q) => {
      let vp = eval_const(p)
      let vq = eval_const(q)
      if vp == Violated || vq == Violated {
        Violated
      } else if vp == Hold && vq == Hold {
        Hold
      } else {
        Unknown
      }
    }
    Or(p, q) => {
      let vp = eval_const(p)
      let vq = eval_const(q)
      if vp == Hold || vq == Hold {
        Hold
      } else if vp == Violated && vq == Violated {
        Violated
      } else {
        Unknown
      }
    }
    Next(_) => Unknown
    Until(_, _) => Unknown
  }
}

///|
/// 增量式监控：给定之前的监控状态 + 新状态，返回更新后的结论
/// 简化版：每次重算整个轨迹。生产版可做增量优化（保存子公式状态），
/// 但此处优先正确性与可读性，O(|formula| * |trace|) 已足够低开销。
pub fn monitor_step(formula : LtlFormula, trace : Array[State]) -> Verdict {
  evaluate(formula, trace)
}

///|
/// 把公式转成可读字符串（用于报告/调试）
pub fn formula_to_string(formula : LtlFormula) -> String {
  match formula {
    Atom(name) => name
    Not(f) => "(!" + formula_to_string(f) + ")"
    And(p, q) => "(" + formula_to_string(p) + " & " + formula_to_string(q) + ")"
    Or(p, q) => "(" + formula_to_string(p) + " | " + formula_to_string(q) + ")"
    Next(f) => "(X " + formula_to_string(f) + ")"
    Until(p, q) =>
      "(" + formula_to_string(p) + " U " + formula_to_string(q) + ")"
  }
}

///|
/// Verdict 转字符串
pub fn verdict_to_string(v : Verdict) -> String {
  match v {
    Hold => "hold"
    Violated => "violated"
    Unknown => "unknown"
  }
}

///|
/// 把一组状态序列转成 JSON 数组（每个状态是 {atom: bool}）
pub fn states_to_json(states : Array[State]) -> String {
  let parts : Array[String] = []
  let mut i = 0
  while i < states.length() {
    parts.push(state_to_json(states[i]))
    i = i + 1
  }
  "[" + parts.join(",") + "]"
}

///|
fn state_to_json(s : State) -> String {
  let parts : Array[String] = []
  for k in s.atoms.keys() {
    let v = s.get(k)
    parts.push(
      "\"" + json_escape(k) + "\":" + (if v { "true" } else { "false" }),
    )
  }
  "{" + parts.join(",") + "}"
}

///|
fn json_escape(s : String) -> String {
  let out : Array[String] = []
  let mut i = 0
  while i < s.length() {
    let c = s[i]
    match c {
      '"' => out.push("\\\"")
      '\\' => out.push("\\\\")
      '\n' => out.push("\\n")
      '\r' => out.push("\\r")
      '\t' => out.push("\\t")
      _ => {
        let code = c.to_int()
        if code < 0x20 {
          out.push("\\u" + format_hex4(code))
        } else {
          out.push(c.to_string())
        }
      }
    }
    i = i + 1
  }
  out.join("")
}

///|
fn format_hex4(n : Int32) -> String {
  // 简单的 4 位 16 进制转换，只用于控制字符 (<0x20)
  let hex_chars = "0123456789abcdef"
  let mut s = ""
  let mut v = n
  if v == 0 {
    s = "0"
  } else {
    while v > 0 {
      let d = v % 16
      s = hex_chars[d].to_string() + s
      v = v / 16
    }
  }
  let pad = 4 - s.length()
  let mut out = ""
  let mut i = 0
  while i < pad {
    out = out + "0"
    i = i + 1
  }
  out + s
}
