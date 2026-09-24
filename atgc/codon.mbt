/// ATGC 双链虚拟机 · 密码子指令模块（atgc/codon.mbt）。
/// 依据设计文档 idea.md §3 的 64 密码子指令表：每个密码子解析为一个 `Op`。
/// PUSH_IMM 携带立即数 payload（数据语境，§2.4）；指令流统一为 `(Op | Number)` 结构。
/// LOAD/STORE/MOD 在本模块中按 idea.md Q2 保留为占位（尚未绑定具体密码子）。

///|
/// 操作码枚举（§3 主表）。`PushImm(Int)` 的 payload 为落入数据语境后的立即数 0..63。
pub enum Op {
  /// 起始密码子：启动程序、确定阅读框
  Start
  /// 终止（成功）：返回 0
  Halt
  /// 终止（错误）：返回非零
  HaltErr
  /// 跳出当前循环
  Break
  /// 栈顶弹出并以数字输出
  OutNum
  /// 栈顶弹出并以字符输出
  OutChar
  /// 把下一个碱基作为立即数入栈
  PushImm(Int)
  /// 弹出栈顶
  Pop
  /// 复制栈顶
  Dup
  /// 交换栈顶两元素
  Swap
  /// 复制栈顶第二个元素
  Over
  /// 旋转栈顶三元素
  Rot
  /// 调用子程序
  Call
  /// 从子程序返回
  Return
  /// 无条件跳转
  Jump
  /// 栈顶为 0 则跳转
  JumpIfZero
  /// 栈顶为负则跳转
  JumpIfNeg
  /// 栈顶为正则跳转
  JumpIfPos
  /// 空操作
  Nop
  /// 加法
  Add
  /// 减法
  Sub
  /// 乘法
  Mul
  /// 除法
  Div
  /// 从内存加载（占位，idea.md Q2 未分配密码子）
  Load
  /// 存入内存（占位，idea.md Q2 未分配密码子）
  Store
  /// 取模（占位，idea.md Q2：与 START 双义悬而未决）
  Mod
}

///|
/// 指令流元素：`Op` 为操作码；`Number` 为数据语境下的立即数/跳转目标。
/// 二者共同构成 `(Op | Number)` 的指令列表（§2.4 语境二分）。
pub enum Inst {
  Op(Op)
  Number(Int)
}

///|
/// 密码子 → 操作码（§3 主表，DNA 大写层）。数据语境的取值由词法层另行解释（见 lexer.mbt）。
/// 未识别的密码子返回 `Nop`（防御；合法 64 密码子均已覆盖）。
pub fn decode(codon : String) -> Op {
  match codon {
    // 起始：Met
    "ATG" => Start
    // 终止：Stop
    "TAA" => Halt
    "TAG" => HaltErr
    "TGA" => Break
    // 带电正 · Lys → OUT_NUM
    "AAA" => OutNum
    "AAG" => OutNum
    // 带电正 · Arg → OUT_CHAR
    "AGA" => OutChar
    "AGG" => OutChar
    "CGT" => OutChar
    "CGC" => OutChar
    "CGA" => OutChar
    "CGG" => OutChar
    // 带电正 · His → PUSH_IMM
    "CAT" => PushImm(0)
    "CAC" => PushImm(0)
    // 带电负 · Asp → POP
    "GAT" => Pop
    "GAC" => Pop
    // 带电负 · Glu → DUP
    "GAA" => Dup
    "GAG" => Dup
    // 极性不电 · Ser → CALL
    "TCT" => Call
    "TCC" => Call
    "TCA" => Call
    "TCG" => Call
    "AGT" => Call
    "AGC" => Call
    // 极性不电 · Thr → RETURN
    "ACT" => Return
    "ACC" => Return
    "ACA" => Return
    "ACG" => Return
    // 极性不电 · Cys → JUMP
    "TGT" => Jump
    "TGC" => Jump
    // 极性不电 · Tyr → JUMP_IF_ZERO
    "TAT" => JumpIfZero
    "TAC" => JumpIfZero
    // 极性不电 · Asn → JUMP_IF_NEG
    "AAT" => JumpIfNeg
    "AAC" => JumpIfNeg
    // 极性不电 · Gln → JUMP_IF_POS
    "CAA" => JumpIfPos
    "CAG" => JumpIfPos
    // 非极性 · Gly → NOP
    "GGT" => Nop
    "GGC" => Nop
    "GGA" => Nop
    "GGG" => Nop
    // 非极性 · Ala → SWAP
    "GCT" => Swap
    "GCC" => Swap
    "GCA" => Swap
    "GCG" => Swap
    // 非极性 · Val → OVER
    "GTT" => Over
    "GTC" => Over
    "GTA" => Over
    "GTG" => Over
    // 非极性 · Leu → ROT
    "TTA" => Rot
    "TTG" => Rot
    "CTT" => Rot
    "CTC" => Rot
    "CTA" => Rot
    "CTG" => Rot
    // 非极性 · Ile → ADD
    "ATT" => Add
    "ATC" => Add
    "ATA" => Add
    // 非极性 · Pro → SUB
    "CCT" => Sub
    "CCC" => Sub
    "CCA" => Sub
    "CCG" => Sub
    // 非极性 · Phe → MUL
    "TTT" => Mul
    "TTC" => Mul
    // 非极性 · Trp → DIV
    "TGG" => Div
    _ => Nop
  }
}

///|
/// 操作码 → 文本名（用于打印/叙述）。PushImm 带立即数。
pub fn op_name(op : Op) -> String {
  match op {
    Start => "START"
    Halt => "HALT"
    HaltErr => "HALT_ERR"
    Break => "BREAK"
    OutNum => "OUT_NUM"
    OutChar => "OUT_CHAR"
    PushImm(v) => "PUSH_IMM \{v}"
    Pop => "POP"
    Dup => "DUP"
    Swap => "SWAP"
    Over => "OVER"
    Rot => "ROT"
    Call => "CALL"
    Return => "RETURN"
    Jump => "JUMP"
    JumpIfZero => "JUMP_IF_ZERO"
    JumpIfNeg => "JUMP_IF_NEG"
    JumpIfPos => "JUMP_IF_POS"
    Nop => "NOP"
    Add => "ADD"
    Sub => "SUB"
    Mul => "MUL"
    Div => "DIV"
    Load => "LOAD"
    Store => "STORE"
    Mod => "MOD"
  }
}

///|
/// 该操作在实际宿主中是否为「数据语境」前缀操作：其后密码子按数据（立即数/地址）解释。
/// 目前仅 PUSH_IMM（以及占位的 LOAD/STORE）触发数据语境（idea.md §2.4）。
pub fn is_data_prefix(op : Op) -> Bool {
  match op {
    PushImm(_) => true
    Load => true
    Store => true
    _ => false
  }
}

///|
/// 全部 64 个密码子（按四进制 0..63 展开为 AAC 顺序）。
fn all_codons() -> Array[String] {
  let out : Array[String] = []
  for v in 0..<64 {
    out.push(int_to_codon(v))
  }
  out
}

///|
/// rc 互补对（idea.md §4.4）：64 密码子恰好划分成 32 对 {c, rc(c)}，无自反。
/// 每对为 `(c, rc(c))`，经 seen 去重保证每对只出现一次（顺序无意义）。
pub fn rc_pairs() -> Array[(String, String)] {
  let seen : Array[String] = []
  let pairs : Array[(String, String)] = []
  for c in all_codons() {
    if array_contains_str(seen, c) {
      continue
    }
    match reverse_complement(c) {
      Some(rc) => {
        seen.push(c)
        seen.push(rc)
        pairs.push((c, rc))
      }
      None => ()
    }
  }
  pairs
}

///|
/// 数组包含判断（小规模线性查找，用于 rc 去重，避免额外依赖 set 包）。
fn array_contains_str(arr : Array[String], s : String) -> Bool {
  for x in arr {
    if x == s {
      return true
    }
  }
  false
}
