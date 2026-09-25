/// ATGC 双链虚拟机 · 运行时执行模块（atgc/vm.mbt）。
/// 依据 idea.md §7.1 / §9：栈机 + 程序计数器；带检查点（快照）回滚的容错执行。
/// 除零、栈下溢、HALT_ERR、占位操作（LOAD/STORE/MOD）均视为错误而不崩溃；
/// 开启回滚时恢复到最后一个 checkpoint 并置 rolled_back=true。

///|
/// 可打印 ASCII 表（32..126），供 OUT_CHAR 输出。
/// 控制字符（<32 或 >126）以 '?' 占位，避免依赖 Char 与字节编码转换。
let ascii_table : String = " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"

///|
/// 代码点 → 单字符字符串（供 OUT_CHAR 拼接到输出）。
fn ascii_char(v : Int) -> String {
  if v < 32 || v > 126 {
    return "?"
  }
  let sb = StringBuilder()
  let mut idx = v - 32
  for c in ascii_table {
    if idx == 0 {
      sb.write_char(c)
      break
    }
    idx = idx - 1
  }
  sb.to_string()
}

///|
/// 运行结果：输出、栈轨迹、最终栈、结果说明与是否回滚。
pub struct RunResult {
  output : String
  stack_history : Array[String]
  final_stack : Array[Int]
  result : String
  rolled_back : Bool
}

///|
/// 栈快照文本（供 history / 快照展示）。
fn stack_str(s : Array[Int]) -> String {
  let parts : Array[String] = []
  for x in s {
    parts.push(x.to_string())
  }
  stack_join(parts, ",")
}

///|
fn stack_join(arr : Array[String], sep : String) -> String {
  let sb = StringBuilder()
  for i in 0..<arr.length() {
    if i > 0 {
      sb.write_string(sep)
    }
    sb.write_string(arr[i])
  }
  "[" + sb.to_string() + "]"
}

///|
/// 执行一步：按当前操作码修改栈/输出/PC。返回 Ok(下一 PC)，其中 -1 表示「成功停机」。
/// 错误以 Err 返回，绝不崩溃。
fn step(
  op : Op,
  stack : Array[Int],
  program : Array[Inst],
  pc : Int,
  out : StringBuilder,
) -> Result[Int, String] {
  match op {
    Start | Nop => Ok(pc + 1)
    Halt | Break => Ok(-1)
    HaltErr => Err("HALT_ERR at \{pc}")
    PushImm(v) => {
      stack.push(v)
      Ok(pc + 1)
    }
    OutNum => {
      if stack.is_empty() {
        return Err("OUT_NUM: 栈空")
      }
      let v = stack.pop().unwrap()
      out.write_string(v.to_string())
      Ok(pc + 1)
    }
    OutChar => {
      if stack.is_empty() {
        return Err("OUT_CHAR: 栈空")
      }
      let v = stack.pop().unwrap()
      out.write_string(ascii_char(v))
      Ok(pc + 1)
    }
    Pop => {
      if stack.is_empty() {
        return Err("POP: 栈空")
      }
      ignore(stack.pop())
      Ok(pc + 1)
    }
    Dup => {
      if stack.is_empty() {
        return Err("DUP: 栈空")
      }
      let top = stack[stack.length() - 1]
      stack.push(top)
      Ok(pc + 1)
    }
    Swap => {
      if stack.length() < 2 {
        return Err("SWAP: 栈不足2")
      }
      let n = stack.length()
      let a = stack[n - 1]
      stack[n - 1] = stack[n - 2]
      stack[n - 2] = a
      Ok(pc + 1)
    }
    Over => {
      if stack.length() < 2 {
        return Err("OVER: 栈不足2")
      }
      let v = stack[stack.length() - 2]
      stack.push(v)
      Ok(pc + 1)
    }
    Rot => {
      if stack.length() < 3 {
        return Err("ROT: 栈不足3")
      }
      // 栈顶三个元素循环左旋：... c b a -> ... a c b（a 上移）
      let n = stack.length()
      let a = stack[n - 1]
      let b = stack[n - 2]
      let c = stack[n - 3]
      stack[n - 3] = a
      stack[n - 2] = c
      stack[n - 1] = b
      Ok(pc + 1)
    }
    Add | Sub | Mul | Div => {
      if stack.length() < 2 {
        return Err("算术: 栈不足2")
      }
      let b = stack.pop().unwrap()
      let a = stack.pop().unwrap()
      let r = match op {
        Add => a + b
        Sub => a - b
        Mul => a * b
        _ => {
          if b == 0 {
            return Err("DIV: 除以零")
          }
          a / b
        }
      }
      stack.push(r)
      Ok(pc + 1)
    }
    Jump => jump_target(program, pc)
    JumpIfZero => {
      if stack.is_empty() {
        return Err("JUMP_IF_ZERO: 栈空")
      }
      let v = stack.pop().unwrap()
      cond_jump(program, pc, v, fn(x : Int) -> Bool { x == 0 })
    }
    JumpIfNeg => {
      if stack.is_empty() {
        return Err("JUMP_IF_NEG: 栈空")
      }
      let v = stack.pop().unwrap()
      cond_jump(program, pc, v, fn(x : Int) -> Bool { x < 0 })
    }
    JumpIfPos => {
      if stack.is_empty() {
        return Err("JUMP_IF_POS: 栈空")
      }
      let v = stack.pop().unwrap()
      cond_jump(program, pc, v, fn(x : Int) -> Bool { x > 0 })
    }
    Call => jump_target(program, pc)
    Return => Ok(pc + 1) // 近似：普通流水式返回（未启用调用返回地址）
    Load | Store | Mod =>
      Err("LOAD/STORE/MOD 为占位操作未实现（idea.md Q2）")
  }
}

///|
/// 无条件跳转：目标为紧随其后的 Number 操作数。
fn jump_target(program : Array[Inst], pc : Int) -> Result[Int, String] {
  if pc + 1 < program.length() {
    match program[pc + 1] {
      Number(t) => Ok(t)
      _ => Err("跳转目标缺失（应紧跟 Number 操作数）")
    }
  } else {
    Err("跳转目标缺失（应紧跟 Number 操作数）")
  }
}

///|
/// 条件跳转：栈顶已取出作为条件值 v；满足 test(v) 则跳到目标，否则跳过操作数（pc+2）。
fn cond_jump(
  program : Array[Inst],
  pc : Int,
  v : Int,
  pred : (Int) -> Bool,
) -> Result[Int, String] {
  if pc + 1 < program.length() {
    match program[pc + 1] {
      Number(t) => if pred(v) { Ok(t) } else { Ok(pc + 2) }
      _ => Err("跳转目标缺失（应紧跟 Number 操作数）")
    }
  } else {
    Err("跳转目标缺失（应紧跟 Number 操作数）")
  }
}

///|
/// 执行整个程序。返回 RunResult；开启 rollback 时出错自动恢复到最后一个 checkpoint。
pub fn run(program : Array[Inst], rollback : Bool) -> RunResult {
  let mut stack : Array[Int] = []
  let mut pc = 0
  let mut out = StringBuilder()
  let history : Array[String] = []
  let mut rolled_back = false
  let checkpoints : Array[(Int, Array[Int], String)] = []
  let mut result = "ok"
  let mut halted = false

  while pc < program.length() && !halted {
    if rollback {
      // 指令边界处的状态快照（idea.md §7.1）
      checkpoints.push((pc, stack.copy(), out.to_string()))
    }
    let outcome = match program[pc] {
      Op(op) => step(op, stack, program, pc, out)
      Number(_) => Err("数据操作数出现在指令语境 pc=\{pc}")
    }
    match outcome {
      Err(msg) =>
        if rollback && checkpoints.length() > 0 {
          let (ck_pc, ck_stack, ck_out) = checkpoints.pop().unwrap()
          pc = ck_pc
          stack = ck_stack
          out = StringBuilder()
          out.write_string(ck_out)
          rolled_back = true
          result = "rolled_back: \{msg}"
          halted = true
        } else {
          result = "err: \{msg}"
          halted = true
        }
      Ok(next) => {
        history.push(stack_str(stack))
        if next < 0 {
          halted = true
        } else {
          pc = next
        }
      }
    }
  }

  let output = out.to_string()
  { output, stack_history: history, final_stack: stack, result, rolled_back, }
}
