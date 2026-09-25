/// atgc_run.mbt —— ATGC 极简入口（自驱+Omega 强验证交付物「run」叶）。
/// 验证语料(Omega spec content)：run_dna 把归一化后的 ATGC 源码按每 3 碱基一个密码子
/// 译为指令；PushImm 之后紧跟的密码子按数据语境(四进制 0..63)作立即数；§2.4 语境二分；
/// 极小子集用密码子：ATG=Start、TAA=Halt、AAA/AAG=OutNum、CAT/CAC=PushImm、ATT=Add、
/// CCT/CCC/CCA/CCG=Sub。示例 run_dna("ATGCATAAGATTCATAAGATTAA") 输出 "3"(1+2)，result="ok"。

///|
/// 3 碱基密码子 -> 操作码（极小子集）。未知返回 Unknown(codon)。
fn decode(codon : String) -> Op {
  if codon == "ATG" {
    Op::Start
  } else if codon == "TAA" {
    Op::Halt
  } else if codon == "TGA" {
    Op::Break
  } else if codon == "AAA" || codon == "AAG" {
    Op::OutNum
  } else if codon == "CAT" || codon == "CAC" {
    Op::PushImm(0) // 占位：立即数由紧随数据语境重写
  } else if codon == "ATT" {
    Op::Add
  } else if codon == "CCT" || codon == "CCC" || codon == "CCA" || codon == "CCG" {
    Op::Sub
  } else {
    Op::Unknown(codon)
  }
}

///|
/// 3 碱基 -> 四进制数值(0..63)：每位 base_to_int 依 A=0,T=1,G=2,C=3。
fn codon_value(codon : String) -> Int {
  let mut v = 0
  for c in codon {
    match base_to_int(c) {
      None => return -1
      Some(n) => v = v * 4 + n
    }
  }
  v
}

///|
/// 词法+语境装配：归一化 -> 按 3 碱基切密码子 -> 依 PushImm 之后紧跟的密码子进数据语境。
fn assemble(seq : String) -> Array[Inst] {
  let n = normalize(seq)
  let codons : Array[String] = []
  for i = 0; i + 3 <= n.length(); i = i + 3 {
    codons.push(n.substring(start=i, end=i + 3))
  }
  let program : Array[Inst] = []
  let mut i = 0
  while i < codons.length() {
    let op = decode(codons[i])
    match op {
      Op::PushImm(_) =>
        if i + 1 < codons.length() {
          program.push(Op(Op::PushImm(codon_value(codons[i + 1]))))
          i = i + 2
        } else {
          program.push(Op(Op::PushImm(0)))
          i = i + 1
        }
      _ => {
        program.push(Op(op))
        i = i + 1
      }
    }
  }
  program
}

///|
/// 极简入口：源码 -> 执行 -> 返回一行文本（output + result）。
pub fn run_dna(seq : String) -> Result[String, String] {
  if not(valid_input(seq)) {
    return Err("run_dna: 非法输入（仅允许 ATGCU 与空白/注释）")
  }
  let r = run(assemble(normalize(seq)))
  if r.result != "ok" {
    Err("run_dna: \{r.result}")
  } else {
    Ok("output=\"\{r.output}\" result=\"ok\"")
  }
}
