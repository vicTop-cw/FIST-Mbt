/// ATGC 双链虚拟机 · 叙事对话模块（atgc/talk.mbt）。
/// 依据 idea.md §11/§12 的叙事框架：DNA → 转录 → mRNA → 翻译 → 蛋白质/酶执行。
/// 同时提供供 MCP 工具使用的 JSON 字符串接口（atgc_compile / atgc_run / atgc_talk）。

///|
/// 输入合法性校验：仅允许 A/T/G/C/U（大小写均可）与空白（空格/制表/换行/回车），
/// 以及 `;;` 注释分隔符。其余字符一律拒绝（不崩溃，返回错误）。
pub fn valid_input(seq : String) -> Bool {
  for c in seq {
    let ok = match c {
      'A' | 'a' | 'T' | 't' | 'G' | 'g' | 'C' | 'c' | 'U' | 'u' => true
      ' ' | '\t' | '\n' | '\r' => true
      ';' => true
      _ => false
    }
    if !ok {
      return false
    }
  }
  true
}

///|
/// 从源码一次完成 编译 → 运行，返回运行时结果。
pub fn run_dna(src : String) -> RunResult {
  let cld = compile_dna(src)
  run(cld.program, cld.rollback)
}

///|
/// 开关：把一个字符串安全地包装成 JSON 字符串字面量（最小转义）。
fn jstr(s : String) -> String {
  let sb = StringBuilder()
  sb.write_string("\"")
  for c in s {
    if c == '"' {
      sb.write_string("\\\"")
    } else if c == '\\' {
      sb.write_string("\\\\")
    } else {
      sb.write_char(c)
    }
  }
  sb.write_string("\"")
  sb.to_string()
}

///|
/// 字符串数组 → JSON 数组字符串。
fn jstrs(arr : Array[String]) -> String {
  let parts : Array[String] = []
  for s in arr {
    parts.push(jstr(s))
  }
  "[" + str_join(parts, ",") + "]"
}

///|
fn str_join(arr : Array[String], sep : String) -> String {
  let sb = StringBuilder()
  for i in 0..<arr.length() {
    if i > 0 {
      sb.write_string(sep)
    }
    sb.write_string(arr[i])
  }
  sb.to_string()
}

///|
/// int 数组 → JSON 数组字符串。
fn jints(arr : Array[Int]) -> String {
  let parts : Array[String] = []
  for x in arr {
    parts.push(x.to_string())
  }
  "[" + str_join(parts, ",") + "]"
}

///|
/// MCP: atgc_compile —— 编译并返回转录产物、操作列表与模式（JSON 字符串）。
pub fn atgc_compile(seq : String) -> Result[String, String] {
  if !valid_input(seq) {
    return Err("无效输入：仅允许 [ATGCU] 碱基与空白/注释")
  }
  let cld = compile_dna(seq)
  let transcription = if cld.mrna != "" { cld.mrna } else { cld.antisense }
  Ok(
    "{\"transcription\":" +
    jstr(transcription) +
    ",\"ops\":" +
    jstr(cld.ops) +
    ",\"mode\":" +
    jstr(cld.mode) +
    ",\"antisense\":" +
    jstr(cld.antisense) +
    ",\"rollback\":" +
    (if cld.rollback { "true" } else { "false" }) +
    "}",
  )
}

///|
/// MCP: atgc_run —— 执行并返回 { output, stack_history, result, rolled_back }（JSON）。
pub fn atgc_run(seq : String) -> Result[String, String] {
  if !valid_input(seq) {
    return Err("无效输入：仅允许 [ATGCU] 碱基与空白/注释")
  }
  let r = run_dna(seq)
  Ok(
    "{\"output\":" +
    jstr(r.output) +
    ",\"stack_history\":" +
    jstrs(r.stack_history) +
    ",\"final_stack\":" +
    jints(r.final_stack) +
    ",\"result\":" +
    jstr(r.result) +
    ",\"rolled_back\":" +
    (if r.rolled_back { "true" } else { "false" }) +
    "}",
  )
}

///|
/// 无序列时的双链虚拟机简介。
pub fn atgc_intro() -> String {
  let sb = StringBuilder()
  sb.write_string(
    "ATGC 双链虚拟机：底层四进制 DNA 编程语言。四种碱基 A/T/G/C 映射 0/1/2/3，",
  )
  sb.write_string(
    "三个碱基一组的密码子共 64 种，对应 64 个操作码；编译即转录+mRNA 翻译成蛋白质，",
  )
  sb.write_string(
    "运行即酶催化。双链均可执行：有义链跑正向程序，反义链可作为逆程序、模板链或独立程序。",
  )
  sb.write_string(
    "提供三种编译模式（A/B/C）、.ROLLBACK 快照回滚与 .DUAL/.OVERLAP 组合指令。",
  )
  sb.to_string()
}

///|
/// 把 DNA 程序讲成一个生物故事：转录 → mRNA → 翻译 → 蛋白质/酶执行，并给出最终数值输出。
pub fn atgc_explain(seq : String) -> String {
  if !valid_input(seq) {
    return "无法解读：输入含非法字符（仅允许 [ATGCU] 碱基与空白/注释）。"
  }
  let cld = compile_dna(seq)
  let r = run(cld.program, cld.rollback)
  let sb = StringBuilder()
  sb.write_string("🧬 DNA 故事（模式 " + cld.mode + "）\n")
  sb.write_string("· 有义链 DNA：" + cld.body + "\n")
  if cld.mrna != "" {
    sb.write_string("· 反义链模板已转录成 mRNA：" + cld.mrna + "\n")
  }
  sb.write_string(
    "· 核糖体翻译（密码子→操作）：" + cld.ops + "\n",
  )
  sb.write_string(
    "· 酶执行（栈轨迹）：" + str_join(r.stack_history, " → ") + "\n",
  )
  sb.write_string(
    "· 输出：" +
    (if r.output == "" { "（空）" } else { r.output }) +
    "\n",
  )
  sb.write_string(
    "· 结果：" +
    r.result +
    (if r.rolled_back { "（已触发回滚）" } else { "" }) +
    "\n",
  )
  if r.output != "" {
    sb.write_string("· 最终数值输出：→ " + r.output + "\n")
  } else if r.final_stack.length() > 0 {
    let top = r.final_stack[r.final_stack.length() - 1].to_string()
    sb.write_string("· 栈顶（未输出）数值：" + top + "\n")
  }
  sb.to_string()
}

///|
/// MCP: atgc_talk —— 叙事对话。给出序列（非空）则讲生物故事并回答自由问题；
/// 序列为空则返回双链虚拟机简介。
pub fn atgc_talk(seq : String, question : String) -> String {
  if seq.trim().to_string() == "" {
    atgc_intro()
  } else {
    let base = atgc_explain(seq)
    let q = question.trim().to_string()
    if q == "" {
      base
    } else {
      let sb = StringBuilder()
      sb.write_string(base)
      sb.write_string("\n")
      sb.write_string("📌 关于你的问题「")
      sb.write_string(q)
      sb.write_string(
        "」：程序经由「有义链→转录→mRNA→核糖体翻译→酶逐条执行」的流水线处理，关键看程序的转录方向、操作序列与栈轨迹。",
      )
      sb.to_string()
    }
  }
}
