/// vm.mbt —— ATGC 极简栈机（自驱+Omega 强验证交付物「vm」叶）。
/// 验证语料(Omega spec content)：操作子集 {Start, PushImm, Add, Sub, OutNum, Halt}；
/// 栈下溢/除零/未知Op 返回 Err 不崩溃；运行结果含 output 与 result(ok/err)。
/// PushImm 的立即数来自紧随其后的数据语境值(0..63, 3 碱基四进制)。

///|
/// 极简操作码（仅依赖 base 子集所需的几个）。
pub enum Op {
  Start
  Halt
  Break
  Add
  Sub
  OutNum
  PushImm(Int32)
  Unknown(String)
}

///|
/// 程序指令：要么操作码，要么立即数。
///
/// **② 预留（Lane DM 2026-10-29 定夺）**：`Num` 当前**无构造点**，但**不是死代码** ——
/// 它是**数据语境**的载体，词法/语法层产出的中间形态。
/// `step` 里 `Num(_) => Err("vm: 数据语境值不应作为指令执行")` 是**防御性断言**
/// （设计者明确想过「Num 不该被当指令执行」，并写下了拒绝），
/// **不是「本该构造却没构造」的缺陷**。
///
/// ⚠️ **不要因为 unused 就删，也不要给它补构造入口** ——
/// 补了反而会让「Num 当指令执行」变成可达路径，那正是这条 `Err` 要挡的。
/// 若将来接入真正的数据段（`idea.md` 的 Q2），届时此处自然会有构造点。
pub enum Inst {
  Op(Op)
  Num(Int32)
}

///|
/// 运行结果。
pub struct RunResult {
  output : String
  result : String
  stack : Array[Int32]
}

///|
/// 运行一条指令，返回 (pc_delta 或停机哨兵 -1, result) 以错误。
fn step(
  inst : Inst,
  stack : Array[Int32],
  out : StringBuilder,
) -> Result[Int32, String] {
  match inst {
    Num(_) => Err("vm: 数据语境值不应作为指令执行")
    Op(Start) | Op(Break) => Ok(1)
    Op(Halt) => Ok(-1)
    Op(Add) => {
      // 极小子集语义：Add 二元（b+a）。
      if stack.length() < 2 {
        return Err("vm: 栈下溢(Add，需要 2 个操作数)")
      }
      let a = stack.unsafe_pop()
      let b = stack.unsafe_pop()
      stack.push(b + a)
      Ok(1)
    }
    Op(Sub) => {
      if stack.length() < 2 {
        return Err("vm: 栈下溢(Sub，需要 2 个操作数)")
      }
      let a = stack.unsafe_pop()
      let b = stack.unsafe_pop()
      stack.push(b - a)
      Ok(1)
    }
    Op(OutNum) => {
      if stack.is_empty() {
        return Err("vm: 栈下溢(OutNum)")
      }
      out.write_string(stack.unsafe_pop().to_string())
      Ok(1)
    }
    Op(PushImm(v)) => {
      stack.push(v)
      Ok(1)
    }
    Op(Unknown(c)) => Err("vm: 未知/未实现操作码 \{c}")
  }
}

///|
/// 执行程序（指令数组），返回 RunResult。
pub fn run(program : Array[Inst]) -> RunResult {
  let mut pc = 0
  let stack : Array[Int32] = []
  let out = StringBuilder()
  let mut result = "ok"
  while pc >= 0 && pc < program.length() {
    match step(program[pc], stack, out) {
      Err(e) => {
        result = e
        break
      }
      Ok(delta) => {
        if delta < 0 {
          break
        }
        pc = pc + delta
      }
    }
  }
  { output: out.to_string(), result, stack, }
}

///|
/// 把运行结果渲染成一行文本（供 execute 交付物 / 测试判读）。
pub fn render_result(r : RunResult) -> String {
  "output=\"\{r.output}\" result=\"{r.result}\" stack_len=\{r.stack.length()}"
}
