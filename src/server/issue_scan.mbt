/// issue_scan.mbt —— 规则驱动源码扫描（"找目标项目潜在问题"自驱能力，打磨收尾引入）
///
/// 设计要点：
///   1) 复用 ocr-local 的"规则路由交给 agent 读文件→套规则→产 findings"模式，但把
///      规则内建为纯 MoonBit 代码，**无外部二进制/无绝对路径硬编码**，可直接在
///      MCP / CLI / skill 三形态复用（本文件即 MCP 基座）；
///   2) 规则聚焦 MoonBit 高危可崩溃模式：除零、空数组下标、无保护 unwrap、
///      无保护整除、子串越界、ignore 丢弃错误、潜在整型溢出、空集合单例；
///   3) 输出 findings（rule/severity/file/line/snippet/why/hint），agent 可逐条
///      读文件判定真实缺陷，或直接把命中喂给 report_bug 形成"扫描→上报→修复"闭环；
///   4) 与 bugreport（缺陷账本）、run_check（外部判据）互补，形成静态扫描层。

///|
/// 规则定义：id + 说明 + 匹配模式（按行正则式字符串匹配，命中即给 finding，
/// 是否真实缺陷由 agent 读上下文判定）。
struct ScanRule {
  id : String
  severity : String
  pattern : Array[String]
  why : String
  hint : String
}

///|
/// 一条命中记录。
struct ScanFinding {
  rule : String
  severity : String
  file : String
  line : Int
  code : String
}

///|
/// 文件级上下文预扫描结果（R124 advance：守卫过滤增强）。
/// 三种信息：
///   safe_clamps: Map[变量名, 被钳制的源变量]（`n_safe = if n > 0 { n } else { 1 }` → "n_safe"→"n"）
///   guarded_lines: 乘法前守卫（`v >= INT_SAFE` / `v >= 200_000_000`），行号 Int 集合
///   slice_only: 文件是否已无裸 substring 调用（全用切片 `s[:end]`）
struct ScanCtx {
  safe_clamps : Map[String, String]
  guarded_lines : Map[Int, Bool]
  slice_only : Bool
}

///|
/// 预扫描单文件上下文：提取 _safe 钳制 + 乘法前守卫 + 是否全切片。
/// 钳制形态只认 MoonBit 安全写法（`let X_safe = if Y > 0 { Y } else { 1 }`），
/// 不贪多——拿不准就不写进表（保守过滤）。
fn scan_build_ctx(content : String) -> ScanCtx {
  let clamps : Map[String, String] = Map([])
  let guarded : Map[Int, Bool] = Map([])
  let mut has_substring_call = false
  let mut ln = 1
  for line in content.split("\n") {
    let t = line.trim().to_string()
    // _safe 钳制：识别 `let X_safe = if ... > 0 { ... } else { 1 }`
    if t.has_prefix("let ") &&
      t.contains("_safe") &&
      t.contains("else {") &&
      t.contains("> 0") {
      let cs = t.to_array()
      let n = cs.length()
      let mut j = 4
      while j < n && cs[j] != ' ' {
        j = j + 1
      }
      let clamp_name = String::from_array(cs[4:j])
      // 简化策略：X_safe 出现在除数位置 → 必来自钳制
      clamps.set(clamp_name, clamp_name) // 值占位（能 set 进表就算被钳制）
    }
    if t.contains(">= INT_SAFE") ||
      t.contains(">= 200_000_000") ||
      t.contains(">=200_000_000") {
      guarded.set(ln, true)
    }
    if t.contains("substring(") && not(scan_is_comment_line(line)) {
      has_substring_call = true
    }
    ln = ln + 1
  }
  {
    safe_clamps: clamps,
    guarded_lines: guarded,
    slice_only: not(has_substring_call),
  }
}

///|
/// 内建规则集（10 条，聚焦 MoonBit 可崩溃/语义高危模式；与 ocr-local
/// moonbit-rules.json 关注点一致，但免外部二进制依赖）。
fn scan_rules() -> Array[ScanRule] {
  let r : Array[ScanRule] = [
    {
      id: "div-by-zero",
      severity: "high",
      pattern: ["/ 0", "div 0"],
      why: "字面量除零（整数/浮点）在 MoonBit 为 panic 而非错误值",
      hint: "改用 guard 前置判断或 Result 语义",
    },
    {
      id: "index-out-of-bounds",
      severity: "high",
      pattern: ["rows[0]", "arr[0]", "list[0]", "data[0]", "items[0]"],
      why: "空数组下标越界会 panic；须先判 is_empty()",
      hint: "`if rows.is_empty() { 兜底 } else { rows[0] }`",
    },
    {
      id: "unwrapped-unwrap",
      severity: "medium",
      pattern: [".unwrap()"],
      why: "对 Option/Result 直接 unwrap 在 None/Err 时 panic，须先确认上游非空",
      hint: "改用 match / 先 is_some() 守卫",
    },
    {
      id: "unsafe-get",
      severity: "medium",
      pattern: ["unsafe_get"],
      why: "unsafe_get 越过越界检查，数组长度变化时易出界",
      hint: "改用受控索引或先 length() 校验",
    },
    {
      id: "unprotected-division",
      severity: "medium",
      pattern: [
        "/ total", "/ len", "/ length", "/ count", "/ size", "/ n", "/ win", "/ sum",
      ],
      why: "除数变量可能为 0，须有 total>0 等前置守卫",
      hint: "`if total > 0 { ... } else { 兜底 }`",
    },
    {
      id: "substring-overrun",
      severity: "medium",
      pattern: ["substring("],
      why: "substring 的 end 参数越界会 panic，须保证 end ≤ 长度",
      hint: "先校验 length() 再 substring",
    },
    {
      id: "ignored-error",
      severity: "low",
      pattern: [
        "ignore(execute(", "ignore(write(", "ignore(remove(", "ignore(delete(", "ignore(set(",
        "ignore(close(", "ignore(finalize(", "ignore(run(", "ignore(push(",
      ],
      why: "ignore 丢弃可能失败的调用返回值，错误被静默吞掉",
      hint: "确认该调用确实无失败语义，否则改用 match 捕获",
    },
    {
      id: "string-index",
      severity: "low",
      pattern: ["[0]", "[1]", "[2]"],
      why: "字符串/数组按下标字面量，短集合上可能越界 panic",
      hint: "先 length() 校验或用 get(i) Option 语义",
    },
    {
      id: "possible-overflow",
      severity: "low",
      pattern: ["* 10", "to_int() *"],
      why: "Int 乘法/累加可能溢出（JS 端 Int 为 53 位安全整数）",
      hint: "大数值场景用 Int64/检查语义",
    },
    {
      id: "empty-collection-singleton",
      severity: "low",
      pattern: [".head()", ".first()"],
      why: "空集合取单例元素可能返回默认/越界，须判空",
      hint: "用 get(0) Option 语义或先判空",
    },
    {
      // R12-R7 bugfind（BUG-217/218/219 教训）：`*86400` 是 Int32 溢出重灾区——
      // 一天 86400 秒是大系数，任何天数×86400 超过 24855 天就溢出。
      // 旧 `possible-overflow` 只匹配 `* 10`/`to_int()*`，漏掉了这个家族。
      id: "secs-overflow",
      severity: "medium",
      pattern: ["* 86400", "*86400"],
      why: "Int32 下 days*86400 超过 24855 天（约 68 年）即溢出（绕回不是 panic），timestamp 函数是重灾区（Y2038 问题）",
      hint: "加天数上界守卫（如 if days > 24855 兜底），或改用 Int64",
    },
  ]
  r
}

///|
/// 是否为整行注释（doc 注释 `///` 或行注释 `//`，trim 后判定）。
/// BUG-15 修复①：规则此前对**每一行原文**做子串匹配，doc 注释里的散文
/// （如「0xcbf29ce484222325 / 0x100000001b3」含 "/ 0"、「…返回 None。」含 "/ n"）
/// 被当成代码命中，div-by-zero(unprotected-division) 等档的 high 因此被注释占满。
/// 只跳「整行是注释」的行，行尾注释不在本轮范围内（需要 token 级判定，另开 issue）。
fn scan_is_comment_line(line : StringView) -> Bool {
  let t = line.trim()
  t.starts_with("///") || t.starts_with("//")
}

///|
/// 是否为「规则定义表所在文件」——即扫描器自身。
/// BUG-15 修复②：规则表里的 pattern/hint 字面量（`"/ 0"`、`"rows[0]"`、
/// `".unwrap()"`、`"unsafe_get"`、`"substring("` …）本身就是被搜的字符串，
/// 于是 issue_scan.mbt 一个文件贡献 15 条命中、其中 3 条被判 high。
/// 判定不靠硬编码路径：文件名后缀 + 必须含 `fn scan_rules(` 规则表标记，
/// 避免误伤其它同名文件；该文件里的真实代码此前也只产出误报（dir[0] 已有 is_empty 守卫）。
fn scan_is_rules_table(path : String, content : String) -> Bool {
  path.has_suffix("issue_scan.mbt") && content.contains("fn scan_rules(")
}

///|
/// 从 at 起，cs 是否以 pat 开头（逐字符比，不靠切片：中文按字节下标极易切坏）。
fn scan_matches_at(cs : Array[Char], pat : Array[Char], at : Int) -> Bool {
  let m = pat.length()
  if at < 0 || at + m > cs.length() {
    return false
  }
  let mut k = 0
  while k < m {
    if cs[at + k] != pat[k] {
      return false
    }
    k = k + 1
  }
  true
}

///|
/// 取一行的"可扫代码部分"：字符串字面量**内容整体丢弃**（留一对空引号作壳），
/// 并从第一个不在字面量里的 `//` 处截断行尾注释。
///
/// BUG-15 当年声明"行尾注释不在本轮范围内（需要 token 级判定，另开 issue）"——
/// 这里只需两个状态量（在不在字面量里、上一个字符是不是反斜杠），一趟扫描就够，
/// 不必完整 lexer，所以把那半边的债一起还了：
/// `Json::Null => (d, []) // null = 没给配置` 不再被裸子串 `/ n` 命中。
fn scan_code_part(line : StringView) -> String {
  let cs = line.to_string().to_array()
  let n = cs.length()
  let out : Array[Char] = []
  let mut in_lit = false
  let mut prev_bs = false
  let mut i = 0
  while i < n {
    let c = cs[i]
    if in_lit {
      if c == '\\' {
        prev_bs = !prev_bs
      } else {
        if c == '"' && !prev_bs {
          in_lit = false
          out.push(c)
        }
        prev_bs = false
      }
    } else if c == '"' {
      in_lit = true
      out.push(c)
    } else if c == '/' && i + 1 < n && cs[i + 1] == '/' {
      break
    } else {
      out.push(c)
    }
    i = i + 1
  }
  String::from_array(out)
}

///|
/// needle 是否出现在本行的**代码部分**（字符串字面量内容之外、行尾注释之前）。
/// BUG-72：规则表用裸子串匹配，于是工具描述里的一句文案（`"…substring(start=0…)"`、
/// `"… rows[0] …"`）也被当成代码命中——扫描器把"提到某事"读成"做了某事"，
/// 实测全仓 substring-overrun 17 条里多条是这种噪声（BUG-15 的注释面是同一类的另一半）。
/// 已知局限（一律保守少报，不误报）：多行字符串/未闭合字面量会丢掉行尾余下部分；
/// 插值 `\{a / 0}` 里的代码按字面量内容放过。
fn scan_outside_literal(line : StringView, needle : String) -> Bool {
  let cs = scan_code_part(line).to_array()
  let pat = needle.to_array()
  let n = cs.length()
  if pat.is_empty() || pat.length() > n {
    return false
  }
  let mut i = 0
  while i < n {
    if scan_matches_at(cs, pat, i) {
      return true
    }
    i = i + 1
  }
  false
}

///|
/// 逐行匹配一条规则，返回命中（行号从 1 起）。整行注释跳过（见 scan_is_comment_line）。
fn scan_match_lines(
  content : String,
  rule : ScanRule,
  file : String,
) -> Array[ScanFinding] {
  let out : Array[ScanFinding] = []
  let mut ln = 1
  for line in content.split("\n") {
    let mut hit = false
    if not(scan_is_comment_line(line)) {
      for needle in rule.pattern {
        // BUG-72：只算字面量之外的命中（文案里的 `substring(` 不是调用）
        if scan_outside_literal(line, needle) {
          hit = true
          break
        }
      }
    }
    if hit {
      out.push({
        rule: rule.id,
        severity: rule.severity,
        file,
        line: ln,
        code: line.trim().to_string(),
      })
    }
    ln = ln + 1
  }
  out
}

// ============================================================================
// 守卫感知过滤（2026-10-10 打磨）：原规则只做行级模式匹配，不识别上下文守卫，
// 于是 `if rows.is_empty() { … } else { rows[0] }`、`if s.length() > 8 { s.substring(0,8) }`
// 这类**有守卫**的高危形态也被上报。逐条甄别是 agent 的活，但"明显有守卫"的命中等价于
// 常量时间就能消掉的假阳性——把它们就地过滤，让 issue_scan 的回声更接近真实缺陷面。
// 只对 substring-overrun / unprotected-division / index-out-of-bounds / string-index 四档做
// 守卫过滤；div-by-zero（字面量除零）不参与，`/ 0` 没有"守得住"的上下文。
// ============================================================================

///|
/// 是否为标识符字符（字母/数字/下划线）。MoonBit 标识符允许 ASCII 字母与数字、
/// 下划线；判定不做 unicode 展开，保守（够用即可）。
fn scan_is_ident_char(c : Char) -> Bool {
  let o = c.to_int()
  (o >= 65 && o <= 90) ||
  (o >= 97 && o <= 122) ||
  (o >= 48 && o <= 57) ||
  c == '_'
}

///|
/// 从 code 行里提取被除的变量名（`/ total` → "total"，`/ n` → "n"）；找不到返回 ""。
fn scan_div_var(code : String) -> String {
  let cs = code.to_array()
  let n = cs.length()
  let mut slash = -1
  let mut i = 0
  while i < n {
    if cs[i] == '/' {
      slash = i
    }
    i = i + 1
  }
  if slash < 0 || slash + 1 >= n {
    return ""
  }
  // 跳过 '/=' 或 `//`（不可能是除数场景）
  if slash + 1 < n && cs[slash + 1] == '=' {
    return ""
  }
  if slash + 1 < n && cs[slash + 1] == '/' {
    return ""
  }
  let mut j = slash + 1
  while j < n && cs[j] == ' ' {
    j = j + 1
  }
  let mut k = j
  while k < n && not(scan_is_ident_char(cs[k])) {
    k = k + 1
  }
  // k 之后才是变量（或字面量数字）；变量允许字母/数字/下划线
  let mut e = k
  while e < n && scan_is_ident_char(cs[e]) {
    e = e + 1
  }
  if e > k {
    String::from_array(cs[k:e])
  } else {
    ""
  }
}

///|
/// 从 code 行里提取 substring 的目标（`.substring(` 前的表达式尾部，如 `a.id` / `s`）；
/// 找不到返回 ""。
fn scan_substring_target(code : String) -> String {
  let cs = code.to_array()
  let n = cs.length()
  // 找 "substring" 出现位置
  let pat = "substring".to_array()
  let mut idx = -1
  let mut i = 0
  while i < n - 8 {
    if scan_matches_at(cs, pat, i) {
      idx = i
      break
    }
    i = i + 1
  }
  if idx < 0 {
    return ""
  }
  // 往前找 "(" 前的表达式终点（"xxx.substring(" → xxx）
  let mut j = idx - 1
  if j >= 0 && cs[j] == '.' {
    j = j - 1
  }
  let mut k = j
  while k >= 0 {
    let o = cs[k].to_int()
    let ok = (o >= 65 && o <= 90) ||
      (o >= 97 && o <= 122) ||
      (o >= 48 && o <= 57) ||
      cs[k] == '_'
    if ok {
      k = k - 1
    } else {
      break
    }
  }
  if j > k {
    String::from_array(cs[k + 1:j + 1])
  } else {
    ""
  }
}

///|
/// 在 prev 行里找该 var 是否被 `is_empty()` 守卫（同形 `if var.is_empty()` / `var.is_empty()`）。
fn scan_guard_is_empty(prev : String, vn : String) -> Bool {
  let t = prev.trim().to_string()
  if t.is_empty() {
    return false
  }
  if vn.is_empty() {
    return false
  }
  t.contains(vn + ".is_empty()") ||
  t.contains(vn + ".length() == 0") ||
  t.contains(vn + ".length() <= 0")
}

///|
/// 在 prev 行里找该 var 是否被 `length() > N` / `length() >= N` 守卫。
fn scan_guard_length_above(prev : String, vn : String) -> Bool {
  let t = prev.trim().to_string()
  if t.is_empty() {
    return false
  }
  if vn.is_empty() {
    return false
  }
  t.contains(vn + ".length() >") ||
  t.contains(vn + ".length() >= ") ||
  t.contains(".length() >") ||
  t.contains(".length() >= ")
}

///|
/// 在 prev 行里找 `if total <= 0` / `if total == 0` / `if n <= 0` 这类零值守卫。
/// 不要求变量名匹配（常见于函数入口的总量校验），只认"零值判断 + return/fallback"形状。
fn scan_guard_zero(prev : String) -> Bool {
  let t = prev.trim().to_string()
  if t.is_empty() {
    return false
  }
  t.contains("<= 0") ||
  t.contains("== 0") ||
  t.contains("< 1") ||
  t.contains("is_empty()") ||
  t.contains("<= 0.0") ||
  t.contains("== 0.0")
}

///|
/// 判定一条命中是否被**明显**上下文守卫（5 行内可判，只做保守过滤——拿不准就保留）。
pub fn scan_finding_guarded(
  code : String,
  rule : String,
  prev_lines : Array[String],
  ctx? : ScanCtx = {
    safe_clamps: Map([]),
    guarded_lines: Map([]),
    slice_only: false,
  },
  hit_line? : String = "",
  hit_ln? : Int = 0,
) -> Bool {
  // R124: MoonBit substring 安全通道 — 文件已无裸 substring 调用
  if rule == "substring-overrun" && ctx.slice_only {
    return true
  }
  let vn = if rule == "unprotected-division" {
    scan_div_var(code)
  } else if rule == "substring-overrun" {
    scan_substring_target(code)
  } else {
    ""
  }
  // R124: _safe 钳制识别 — 除数是 X_safe 时，构造行已钳制到 ≥1
  if rule == "unprotected-division" && ctx.safe_clamps.get(vn).is_some() {
    return true
  }
  // R124: possible-overflow 乘法前守卫
  if rule == "possible-overflow" && hit_ln > 0 {
    let mut check = hit_ln - 1
    while check >= hit_ln - 6 && check > 0 {
      if ctx.guarded_lines.get(check).is_some() {
        return true
      }
      check = check - 1
    }
  }
  // 同一行守卫：substring 可能写在 `if s.length() > N { ... substring(...) }` 同一行，
  // prev_lines 不含当前行，须先检查 code 自身。
  if rule == "substring-overrun" {
    let code_t = code.trim().to_string()
    if not(vn.is_empty()) && scan_guard_length_above(code_t, vn) {
      return true
    }
    if code_t.contains("if ") && code_t.contains(".length() >") {
      return true
    }
    if code_t.contains("if ") && code_t.contains(".length() >= ") {
      return true
    }
    // R125: MoonBit substring 安全形态 end=length()-1 / end=length
    if code_t.contains(".length() - 1") || code_t.contains(".length()-1") ||
      code_t.contains("end=.length()") || code_t.contains("end = .length()") {
      return true
    }
  }
  // R125: string-index / index-out-of-bounds 同一行守卫（循环外，prev_lines 空时也能命中）
  if rule == "index-out-of-bounds" || rule == "string-index" {
    if hit_line.contains("is_empty()") ||
      hit_line.contains(".length() >") ||
      hit_line.contains(".length() >= ") ||
      hit_line.contains(".length() ==") {
      return true
    }
    if hit_line.has_prefix("while ") && hit_line.contains(".length()") {
      return true
    }
    if (hit_line.contains("> 0") || hit_line.contains(">= 1")) &&
      (hit_line.has_prefix("if ") || hit_line.contains("{")) {
      return true
    }
  }
  // R125: possible-overflow 同一行 Double 安全形态
  if rule == "possible-overflow" {
    if hit_line.contains(".to_double()") || hit_line.contains("Double") || hit_line.contains("f64") {
      return true
    }
  }
  let n = prev_lines.length()
  let mut i = n - 1
  while i >= 0 {
    let p = prev_lines[i]
    let t = p.trim().to_string()
    i = i - 1
    if t.is_empty() {
      continue
    }
    if rule == "unprotected-division" {
      if scan_guard_zero(t) {
        return true
      }
      if not(vn.is_empty()) && scan_guard_is_empty(t, vn) {
        return true
      }
    } else if rule == "substring-overrun" {
      if not(vn.is_empty()) && scan_guard_length_above(t, vn) {
        return true
      }
      if t.contains("if ") && t.contains(".length() >") {
        return true
      }
      if t.contains("if ") && t.contains(".length() >= ") {
        return true
      }
      if t.starts_with("fn ") {
        return false
      }
    } else if rule == "index-out-of-bounds" || rule == "string-index" {
      if t.contains("is_empty()") {
        return true
      }
      // R125: `if arr.length() > 0` / `if arr.length() >= N` 守卫
      if t.contains(".length() >") || t.contains(".length() >= ") || t.contains(".length() ==") {
        return true
      }
      // R125: `while arr.length() > 0` 循环守卫
      if t.has_prefix("while ") && t.contains(".length()") {
        return true
      }
      // R124: `if n_safe > 0` / `if n >= 1` 同形守卫
      if (t.contains("> 0") || t.contains(">= 1")) &&
        (t.has_prefix("if ") || t.has_prefix("if(")) {
        return true
      }
      if t.starts_with("fn ") {
        return false
      }
      if t.starts_with("fn ") {
        return false
      }
    } else if rule == "possible-overflow" {
      // R124: prev_lines 里 >= INT_SAFE 守卫
      if t.contains(">= INT_SAFE") ||
        t.contains(">= 200_000_000") ||
        t.contains(">=200_000_000") {
        return true
      }
      // R125: Double/f64 乘法不会 Int overflow
      if code.contains(".to_double()") || code.contains("Double") || code.contains("f64") {
        return true
      }
    }
  }
  false
}

///|
/// 对整批 findings 做守卫过滤：返回没被守卫的（即真待判）那些。
fn scan_filter_guarded(
  findings : Array[ScanFinding],
  file_content : Array[String],
) -> Array[ScanFinding] {
  let out : Array[ScanFinding] = []
  for hit in findings {
    let ln = hit.line
    let prev_start = if ln - 6 < 1 { 1 } else { ln - 6 }
    let prev_end = ln - 1
    let prev_lines : Array[String] = []
    if prev_end >= prev_start {
      let mut i = prev_start - 1
      while i <= prev_end - 1 {
        if i >= 0 && i < file_content.length() {
          prev_lines.push(file_content[i])
        }
        i = i + 1
      }
    }
    if scan_finding_guarded(hit.code, hit.rule, prev_lines) {
      continue
    }
    out.push(hit)
  }
  out
}

///|
/// 跳过不应扫描的目录/文件（构建产物、依赖、版本库、数据库、接口快照）。
fn scan_skip(path : String) -> Bool {
  if path.contains("target/") || path.contains("node_modules") {
    return true
  }
  if path.contains(".git/") {
    return true
  }
  if path.has_suffix(".db") || path.has_suffix(".sqlite") {
    return true
  }
  if path.has_suffix(".mbti") || path.has_suffix(".md") {
    return true
  }
  false
}

///|
/// 探测路径是否为目录（可 read_dir 视为目录；文件/不可读返回 false）。
fn scan_detect_dir(p : String) -> Bool {
  let _ = @fs.read_dir(p) catch { _ => return false }
  true
}

///|
/// 是否为测试文件（blackbox `_test.mbt` / whitebox `_wbtest.mbt`）。
/// 测试文件自带断言前置，命中多为安全场景；默认跳过以降噪、聚焦产品代码。
fn scan_is_test_file(p : String) -> Bool {
  p.has_suffix("_test.mbt") || p.has_suffix("_wbtest.mbt")
}

///|
/// 递归收集目录下待扫描文件（目录→递归；文件且 .mbt→收集）。
/// include_tests=false（默认）跳过测试文件。
fn scan_collect(
  dir : String,
  include_tests : Bool,
  out : Array[String],
) -> Unit {
  let names = @fs.read_dir(dir) catch { _ => return }
  for name in names {
    let p = mem_join(dir, name)
    if scan_skip(p) {
      continue
    }
    if scan_detect_dir(p) {
      scan_collect(p, include_tests, out)
    } else if p.has_suffix(".mbt") {
      if include_tests || not(scan_is_test_file(p)) {
        out.push(p)
      }
    }
  }
}

///|
/// 校验扫描目标目录：拒绝空串 / 绝对路径 / 路径穿越（与 bugreport 同款防御）。
fn scan_dir_ok(dir : String) -> Bool {
  if dir.is_empty() {
    return false
  }
  if dir.contains("..") {
    return false
  }
  let c0 = dir[0]
  if c0 == '/' || c0 == '\\' {
    return false
  }
  if dir.length() >= 2 && dir[1] == ':' {
    return false
  }
  true
}

///|
/// 对单个文件执行全部规则扫描（无命中返回空数组）。
/// 规则表所在文件（扫描器自身）整体跳过——它的 pattern 字面量必然命中自己（见 scan_is_rules_table）。
fn scan_file(path : String, rules : Array[ScanRule]) -> Array[ScanFinding] {
  let content = match mem_read(path) {
    None => return []
    Some(c) => c
  }
  if scan_is_rules_table(path, content) {
    return []
  }
  let out : Array[ScanFinding] = []
  for r in rules {
    for f in scan_match_lines(content, r, path) {
      out.push(f)
    }
  }
  out
}

///|
/// 规则驱动源码扫描主入口：递归收集 {dir} 下 .mbt 文件，对每条规则逐行匹配。
/// 返回 {scanned_files, findings, by_severity, by_rule}；findings 可直接喂给
/// report_bug（summary = "\[rule:id\] file:line code"）。
pub fn issue_scan(
  dir : String,
  rules_file : String,
  max_findings : Int,
  include_tests? : Bool = false,
) -> Result[Json, String] {
  if not(scan_dir_ok(dir)) {
    return Err(
      "issue_scan: 非法目录（拒绝绝对路径/穿越/盘符）: " + dir,
    )
  }
  // 外部规则文件（ocr-local moonbit-rules.json 风格）暂不解析，保留参数占位；
  // 内置规则集始终生效。
  let _ = rules_file
  let rules = scan_rules()
  let files : Array[String] = []
  scan_collect(dir, include_tests, files)
  let findings : Array[ScanFinding] = []
  for f in files {
    for hit in scan_file(f, rules) {
      findings.push(hit)
    }
  }
  // 去重：同 (rule, file, line) 只保留一条
  let seen : Map[String, Bool] = Map([])
  let dedup : Array[ScanFinding] = []
  for hit in findings {
    let key = hit.rule + "|" + hit.file + "|" + hit.line.to_string()
    if seen.get(key) is None {
      seen.set(key, true)
      dedup.push(hit)
    }
  }
  // 守卫感知过滤（R124 增强版）：`if is_empty()` / `if length() > N` /
  // `_safe` 钳制 / `>= INT_SAFE` 乘法前守卫 / MoonBit 切片安全通道
  let ctx_cache : Map[String, ScanCtx] = Map([])
  let guarded_filtered : Array[ScanFinding] = []
  for hit in dedup {
    let fc = match mem_read(hit.file) {
      None => continue
      Some(c) => c
    }
    // R124: 文件级 ctx 缓存（每个文件只构建一次）
    let ctx = match ctx_cache.get(hit.file) {
      Some(_) => ctx_cache.get(hit.file).unwrap()
      None => {
        let new_ctx = scan_build_ctx(fc)
        ctx_cache.set(hit.file, new_ctx)
        new_ctx
      }
    }
    let raw_lines = fc.split("\n")
    let fc_lines : Array[String] = []
    for l in raw_lines {
      fc_lines.push(l.to_string())
    }
    let hit_idx = hit.line - 1
    let prev_window : Array[String] = []
    if hit_idx > 0 {
      let mut i = hit_idx - 1
      while i >= 0 {
        let line_str = fc_lines[i]
        if line_str.trim().to_string().has_prefix("fn ") {
          break
        }
        prev_window.push(line_str)
        i = i - 1
        if prev_window.length() >= 10 {
          break
        }
      }
    }
    let hit_line = if hit_idx >= 0 && hit_idx < fc_lines.length() {
      fc_lines[hit_idx]
    } else {
      ""
    }
    if scan_finding_guarded(
        hit.code,
        hit.rule,
        prev_window,
        ctx~,
        hit_line~,
        hit_ln=hit.line,
      ) {
      continue
    }
    guarded_filtered.push(hit)
  }
  let dedup = guarded_filtered
  // 严重度聚合
  let high = dedup.filter(fn(h : ScanFinding) { h.severity == "high" }).length()
  let medium = dedup
    .filter(fn(h : ScanFinding) { h.severity == "medium" })
    .length()
  let low = dedup.filter(fn(h : ScanFinding) { h.severity == "low" }).length()
  // 按规则聚合
  let by_rule : Array[Json] = []
  for r in rules {
    let cnt = dedup.filter(fn(h : ScanFinding) { h.rule == r.id }).length()
    if cnt > 0 {
      by_rule.push(
        Json::object({
          "rule": Json::string(r.id),
          "severity": Json::string(r.severity),
          "count": Json::number(cnt.to_double()),
          "why": Json::string(r.why),
          "hint": Json::string(r.hint),
        }),
      )
    }
  }
  // 限制返回条数（防输出爆炸）
  let limited = if dedup.length() > max_findings {
    dedup[0:max_findings]
  } else {
    dedup
  }
  Ok(
    Json::object({
      "scanned_files": Json::number(files.length().to_double()),
      "total_findings": Json::number(dedup.length().to_double()),
      "truncated": Json::boolean(dedup.length() > max_findings),
      "include_tests": Json::boolean(include_tests),
      "by_severity": Json::object({
        "high": Json::number(high.to_double()),
        "medium": Json::number(medium.to_double()),
        "low": Json::number(low.to_double()),
      }),
      "by_rule": Json::array(by_rule),
      "findings": Json::array(
        limited.map(fn(h : ScanFinding) {
          Json::object({
            "rule": Json::string(h.rule),
            "severity": Json::string(h.severity),
            "file": Json::string(h.file),
            "line": Json::number(h.line.to_double()),
            "code": Json::string(h.code),
          })
        }),
      ),
    }),
  )
}

// ========== DEBUG TESTS (R125 guard filter) ==========
fn _ctx() -> ScanCtx {
  { safe_clamps: Map([]), guarded_lines: Map([]), slice_only: false }
}

test "R125 string-index same-line length() > 0 guard" {
  let hit_line = "let sk = if top.skill_hits.length() > 0 { top.skill_hits[0] } else { \"\" }"
  let code = "top.skill_hits[0]"
  let result = scan_finding_guarded(code, "string-index", [], ctx=_ctx(), hit_line=hit_line, hit_ln=272)
  assert_true(result)
}

test "R125 string-index prev-line while length() guard" {
  let prev = ["while ready_ids.length() > 0 {"]
  let hit_line = "let cur = ready_ids[0]"
  let result = scan_finding_guarded("ready_ids[0]", "string-index", prev, ctx=_ctx(), hit_line=hit_line, hit_ln=273)
  assert_true(result)
}

test "R125 substring-overrun safe end=length()-1" {
  let hit_line = "s.substring(start=0, end=s.length() - 1).to_string()"
  let result = scan_finding_guarded(hit_line, "substring-overrun", [], ctx=_ctx(), hit_line=hit_line, hit_ln=270)
  assert_true(result)
}
