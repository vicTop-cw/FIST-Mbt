/// ATGC 双链虚拟机 · 编译（转录+翻译）模块（atgc/transpile.mbt）。
/// 依据 idea.md §5（指令/编译 pragma）、§6（三种模式）、§8（编译伪代码）。
/// 翻译即「密码子→操作」，转录即「读模板链 3'→5' 生成 mRNA」。

///|
/// 编译结果：一次编译的完整信息（供 MCP atgc_compile / atgc_run / atgc_talk 复用）。
pub struct Compiled {
  /// 编译模式文本，如 "B" / "B+A" / "C"
  mode : String
  /// mRNA（模式 B 的转录产物；无则空字符串）
  mrna : String
  /// 归一化后的程序体（有义链）
  body : String
  /// 正向程序的操作文本（空格分隔的操作名）
  ops : String
  /// 反义链副本（反向互补）
  antisense : String
  /// 模式 A 下的反链翻译（按 idea.md §10.7，当前主表并不真正求逆，仅如实罗列）
  backward : String
  /// 模式 C 下的反链程序（5'→3' 独立翻译）
  program2 : String
  /// 是否启用回滚（.ROLLBACK / 模式 A 的快照语义）
  rollback : Bool
  /// 可直接执行的正向程序（Op | Number 装配后）
  program : Array[Inst]
}

///|
/// 单单画操作文本：把程序翻译成空格分隔的操作名序列。
pub fn render_ops(prog : Array[Inst]) -> String {
  let parts : Array[String] = []
  for inst in prog {
    let name = match inst {
      Op(op) => op_name(op)
      Number(v) => "\{v}"
    }
    parts.push(name)
  }
  join(parts, " ")
}

///|
/// 转录：读模板链（即归一化的有义链），T→U 生成 mRNA（idea.md §6.2）。
pub fn transcribe(seq : String) -> String {
  let sb = StringBuilder()
  for c in seq {
    if c == 'T' {
      sb.write_char('U')
    } else {
      sb.write_char(c)
    }
  }
  sb.to_string()
}

///|
/// 解析编译指令区（idea.md §5 / §8 伪代码）：
/// 头部 `ATGTAA` 标记指令区开始，`TAATAATAA` 标记结束；无指令时默认模式 B。
/// 返回 (指令名字数组, 程序体)。
pub fn parse_directives(norm : String) -> (Array[String], String) {
  if !norm.has_prefix("ATGTAA") {
    return (["MODE_B"], norm)
  }
  let end = find_substr(norm, "TAATAATAA")
  if end < 0 {
    // 头部符合但缺少结束标记：防御性退化返回模式 B，整体作程序体
    return (["MODE_B"], norm)
  }
  let region = slice_str(norm, 6, end - 6)
  let body = slice_str(norm, end + 9, norm.length() - (end + 9))
  let dirs : Array[String] = []
  let codons = group_codons(region)
  for cd in codons {
    match cd {
      "TAG" => dirs.push("MODE_B")
      "ATG" => dirs.push("MODE_A")
      "TGA" => dirs.push("MODE_C")
      "CAT" => dirs.push("DUAL")
      "CAA" => dirs.push("ROLLBACK")
      "CAG" => dirs.push("OVERLAP")
      _ => ()
    }
  }
  if dirs.is_empty() {
    dirs.push("MODE_B")
  }
  (dirs, body)
}

///|
/// 主编译入口：归一化 → 解析指令 → 计算三模式编译产物 → 正向可执行程序。
pub fn compile_dna(src : String) -> Compiled {
  let norm = normalize(src)
  let (dirs, body) = parse_directives(norm)

  // 模式计算
  let has_a = dirs.contains("MODE_A")
  let has_b = dirs.contains("MODE_B")
  let has_c = dirs.contains("MODE_C")
  let rollback = dirs.contains("ROLLBACK") || has_a
  let mode_parts : Array[String] = []
  if has_a {
    mode_parts.push("A")
  }
  if has_b {
    mode_parts.push("B")
  }
  if has_c {
    mode_parts.push("C")
  }
  if mode_parts.is_empty() {
    mode_parts.push("B")
  }
  let mode = join(mode_parts, "+")

  // 程序体操作（正向 + 反链）
  let program = to_program(body)
  let ops = render_ops(program)
  let mrna = if has_b { transcribe(body) } else { "" }
  let antisense = match reverse_complement(body) {
    Some(s) => s
    None => ""
  }
  // 模式 A：反链按当前主表如实翻译（§10.7——不伪造逆操作）
  let backward = if has_a { render_ops(to_program(antisense)) } else { "" }
  // 模式 C：反链 5'→3' 独立翻译
  let program2 = if has_c { render_ops(to_program(antisense)) } else { "" }

  { mode, mrna, body, ops, antisense, backward, program2, rollback, program, }
}

///|
/// 以 "+" 连接数组字符串。
fn join(arr : Array[String], sep : String) -> String {
  let sb = StringBuilder()
  for i in 0..<arr.length() {
    if i > 0 {
      sb.write_string(sep)
    }
    sb.write_string(arr[i])
  }
  sb.to_string()
}
