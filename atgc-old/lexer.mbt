/// ATGC 双链虚拟机 · 词法模块（atgc/lexer.mbt）。
/// 依据 idea.md §2.4：大小写不敏感、规范输出大写；3 碱基一组；
/// 注释以 `;;` 起始至行尾；语境二分——PUSH_IMM/LOAD/STORE 后的密码子切数据语境；
/// mRNA 层 U 与 T 等价，输入统一归并为 T。

///|
/// 归一化：大写化、U→T、剔除空白与 `;;` 注释，仅保留 A/T/G/C。
/// 非法字符被静默剔除（上游 MCP 工具已做严格校验，这里偏宽松以免破坏拼读）。
pub fn normalize(src : String) -> String {
  let sb = StringBuilder()
  let mut in_comment = false
  for c in src {
    if in_comment {
      // 注释持续到行尾
      if c == '\n' {
        in_comment = false
      }
      continue
    }
    match c {
      ';' => in_comment = true
      'A' | 'a' => sb.write_char('A')
      'T' | 't' => sb.write_char('T')
      'G' | 'g' => sb.write_char('G')
      'C' | 'c' => sb.write_char('C')
      'U' | 'u' => sb.write_char('T') // mRNA：U ≡ T
      _ => () // 空白（空格/制表/回车）及非法字符跳过
    }
  }
  sb.to_string()
}

///|
/// 按每 3 个碱基一组切分密码子；尾部不足 3 的缀余被忽略（阅读框按三碱基对齐）。
pub fn group_codons(seq : String) -> Array[String] {
  let out : Array[String] = []
  let mut cur = StringBuilder()
  let mut count = 0
  for c in seq {
    cur.write_char(c)
    count = count + 1
    if count == 3 {
      out.push(cur.to_string())
      cur = StringBuilder()
      count = 0
    }
  }
  out
}

///|
/// 词法分组 + 语境标注：把密码子列表解码为 `(Op | Number)` 指令流。
/// 规则：默认指令语境（密码子→Op）；若上一个已产生的 Op 是数据前缀
/// （PUSH_IMM/LOAD/STORE），则当前密码子切数据语境，按其四进制值入流（§2.4）。
pub fn lex_stream(codons : Array[String]) -> Array[Inst] {
  let out : Array[Inst] = []
  let mut prev_data_prefix = false
  for codon in codons {
    if prev_data_prefix {
      // 数据语境：密码子按四进制 0..63 解释
      match quaternary_of(codon) {
        Some(v) => out.push(Number(v))
        None => out.push(Number(0))
      }
      prev_data_prefix = false
      continue
    }
    let op = decode(codon)
    let data_next = is_data_prefix(op)
    out.push(Op(op))
    prev_data_prefix = data_next
  }
  out
}

///|
/// 装配：把 `(Op | Number)` 流合并为执行程序——`PUSH_IMM` + 后续 `Number`
/// 合并为带 payload 的 `PushImm(v)`（字节码以元素为粒度，vm 逐元素推进，
/// 无需游标跳过，见 vm.mbt）。
pub fn assemble(stream : Array[Inst]) -> Array[Inst] {
  let out : Array[Inst] = []
  let mut i = 0
  while i < stream.length() {
    let inst = stream[i]
    match inst {
      Op(PushImm(_)) => {
        // 尝试取下一个 Number 作为立即数
        if i + 1 < stream.length() {
          match stream[i + 1] {
            Number(v) => {
              out.push(Op(PushImm(v)))
              i = i + 2
              continue
            }
            _ => ()
          }
        }
        out.push(Op(PushImm(0)))
        i = i + 1
      }
      _ => {
        out.push(inst)
        i = i + 1
      }
    }
  }
  out
}

///|
/// 从原始源码一次到位得到可执行程序（归一化 → 分组 → 语境解码 → 装配）。
pub fn to_program(src : String) -> Array[Inst] {
  let seq = normalize(src)
  assemble(lex_stream(group_codons(seq)))
}
