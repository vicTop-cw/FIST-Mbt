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
  line : Int32
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
  guarded_lines : Map[Int32, Bool]
  slice_only : Bool
}

///|
/// 预扫描单文件上下文：提取 _safe 钳制 + 乘法前守卫 + 是否全切片。
/// 钳制形态只认 MoonBit 安全写法（`let X_safe = if Y > 0 { Y } else { 1 }`），
/// 不贪多——拿不准就不写进表（保守过滤）。
fn scan_build_ctx(content : String) -> ScanCtx {
  let clamps : Map[String, String] = Map([])
  let guarded : Map[Int32, Bool] = Map([])
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
      why: "仅显式 Int32 时 days*86400 超过 24855 天（约 68 年）即溢出（Y2038 问题，绕回不是 panic）；MoonBit 默认 Int 在 JS 为 53 位安全整数（~9e15）、native 为 64 位（~9.2e18），需 days>1e11 才溢出，正常代码不可能，故仅对显式 Int32 报警",
      hint: "显式 Int32 的 secs 计算须加天数上界守卫（如 if days > 24855 兜底）或改用 Int64；默认 Int 无需处理",
    },
    // ===== 档 1：ocr-local moonbit-rules.json 的 20 条规则融合（2026-10-13 ocr-local 融入 bugfind）=====
    // 内建自 ocr-local 的 MoonBit 规则集（E:\IDEProjects\AI\ocr-local\rules\moonbit-rules.json 的
    // name/severity/pattern 投影）。pattern 取其稳定字面量 needle（子串匹配，免 regex 依赖）；
    // 语义与外部文件一致，同名外部规则可通过 rules_file 覆盖内建（见 scan_merge_rules）。
    {
      id: "moonbit-result-discard",
      severity: "low",
      pattern: ["ignore("],
      why: "ignore() 丢弃 Result 返回值，错误被静默吞掉（ocr-local moonbit-result-discard；与内建 ignored-error 家族重叠）",
      hint: "改用 match 捕获或确认调用无失败语义",
    },
    {
      id: "moonbit-map-set-no-rebind",
      severity: "low",
      pattern: ["= .set(", "<- .set("],
      // BUG-156：旧 why「Map.set() 返回新 Map」是**事实错误**——MoonBit 核心 Map 是可变 map，
      // .set() 原地变更并返回 Unit（实证锁：src/executor/map_probe_test.mbt）。丢弃返回值是正常用法，
      // 绑定 Unit 才是作者误当函数式 API 的可疑信号。本规则是 ocr-local 启发式提示，非确定性缺陷检测器。
      why: "MoonBit 核心 `Map` 是可变 map，`.set()` 原地变更并返回 `Unit`（实证：`src/executor/map_probe_test.mbt` 丢弃返回值后仍读到值）；本规则是 ocr-local 启发式，只在调用点疑似期待函数式语义时提示，需读上下文确认（BUG-156）",
      hint: "`.set()` 返回值是 `Unit`；正常用法是忽略返回值（原地变更）。若返回值被绑定/使用，说明作者可能误当函数式 API——改用 `m.set(k, v)` 语句式调用",
    },
    {
      id: "moonbit-noop-assignment",
      severity: "low",
      pattern: [": self."],
      why: "字段自赋值无效果（ocr-local moonbit-noop-assignment）",
      hint: "确认更新源字段而非自身赋值",
    },
    {
      id: "moonbit-string-interpolation-escape",
      severity: "low",
      pattern: ["\\{"],
      why: "字符串插值反斜杠转义错误（ocr-local moonbit-string-interpolation-escape）",
      hint: "插值用 `{expr}` 不加反斜杠",
    },
    {
      id: "moonbit-array-index-bounds",
      severity: "low",
      pattern: ["[i]", "[idx]", "[index]", "[k]"],
      why: "数组变量下标无越界守卫（ocr-local moonbit-array-index-bounds；与内建 index-out-of-bounds 家族重叠）",
      hint: "用 get(i) Option 语义或先 length() 校验",
    },
    {
      id: "moonbit-race-condition",
      severity: "low",
      pattern: ["await"],
      why: "可变共享态跨 async 边界，并发交错可能损坏状态（ocr-local moonbit-race-condition；await 使用点提示性）",
      hint: "用原子/锁或避免跨边界共享可变态",
    },
    {
      id: "moonbit-unsafe-unwrap",
      severity: "low",
      pattern: ["unsafe_get("],
      why: "unsafe_get 越过越界检查，越界 panic（ocr-local moonbit-unsafe-unwrap）",
      hint: "改用 get() Option 语义",
    },
    {
      id: "moonbit-async-main",
      severity: "low",
      pattern: ["fn main() : Future"],
      why: "async main 返回 Future 无人 poll，异步体永不执行（ocr-local moonbit-async-main）",
      hint: "配置运行时 poll 或改用同步入口",
    },
    {
      id: "moonbit-private-field-leak",
      severity: "low",
      pattern: ["password", "secret", "token"],
      why: "敏感字段可能被公开导出（ocr-local moonbit-private-field-leak）",
      hint: "敏感字段保持私有或加密存储",
    },
    {
      id: "moonbit-path-traversal",
      severity: "low",
      pattern: ["@fs.open(", "@fs.write(", "@fs.read("],
      why: "文件路径由拼接构造，可穿越目录（ocr-local moonbit-path-traversal）",
      hint: "用 @fs.join_path 校验 ../ 穿越",
    },
    {
      id: "moonbit-json-injection",
      severity: "low",
      pattern: ["Json::string("],
      why: "JSON 字符串由拼接构造，可破坏 JSON 结构（ocr-local moonbit-json-injection）",
      hint: "用 Json::object 构造或转义特殊字符",
    },
    {
      id: "moonbit-divide-by-zero",
      severity: "low",
      pattern: ["/ 0"],
      why: "变量除零 panic（ocr-local moonbit-divide-by-zero，与内建 div-by-zero 家族重叠）",
      hint: "先判除数 != 0",
    },
    {
      id: "moonbit-floating-point-equality",
      severity: "low",
      pattern: ["== 0.", "== 1.", "== 2.", "== 3."],
      why: "浮点相等比较因精度不可靠（ocr-local moonbit-floating-point-equality）",
      hint: "用 (x - target).abs() < epsilon",
    },
    {
      id: "moonbit-long-function",
      severity: "info",
      pattern: ["fn "],
      why: "超长函数难测难维护（ocr-local moonbit-long-function；子串近似 fn 定义行，行数精确判定见 OCR 双轨）",
      hint: "按职责拆分长函数",
    },
    {
      id: "moonbit-resource-leak",
      severity: "low",
      pattern: ["::open("],
      why: "资源打开未关闭，泄漏（ocr-local moonbit-resource-leak）",
      hint: "用 using 块或显式 close",
    },
    {
      id: "moonbit-integer-overflow",
      severity: "low",
      pattern: ["* 100000", "* 1000000", "* 10000000"],
      why: "大数乘法可能溢出（ocr-local moonbit-integer-overflow）",
      hint: "用 Int64 或检查语义",
    },
    {
      id: "moonbit-dead-code",
      severity: "low",
      pattern: ["abort("],
      why: "abort 之后代码不可达（ocr-local moonbit-dead-code）",
      hint: "确认 abort 之后无必要代码",
    },
    {
      id: "moonbit-empty-match",
      severity: "low",
      pattern: ["_ => ()"],
      why: "catch-all 匹配空转，隐藏逻辑错误（ocr-local moonbit-empty-match）",
      hint: "逐变体处理而非 catch-all 吞掉",
    },
    {
      id: "moonbit-match-exhaustive",
      severity: "low",
      pattern: ["match "],
      why: "match 可能非穷尽，运行时对未处理变体 panic（ocr-local moonbit-match-exhaustive；穷尽性需编译期保证，子串提示性）",
      hint: "补全所有枚举变体分支",
    },
    {
      id: "moonbit-shared-mutable",
      severity: "low",
      pattern: ["let mut "],
      why: "可变局部派生自字段，变更不回写（ocr-local moonbit-shared-mutable）",
      hint: "直接改字段或重绑定回写",
    },
    {
      id: "moonbit-overly-broad-catch",
      severity: "low",
      pattern: ["catch {"],
      why: "catch-all 捕获吞掉错误，错误被静默（ocr-local moonbit-overly-broad-catch）",
      hint: "按错误类型分分支处理",
    },
    {
      id: "moonbit-unused-variable",
      severity: "info",
      pattern: ["let "],
      why: "未使用变量（ocr-local 清洁代码族；子串近似 let 声明点，实际使用性需人工/编译器复核）",
      hint: "删除未使用变量",
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
  t.has_prefix("///") || t.has_prefix("//")
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
fn scan_matches_at(cs : Array[Char], pat : Array[Char], at : Int32) -> Bool {
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
  // BUG-162 优化：旧实现把代码部分和 needle 各转成 `Array[Char]`，再手工做 O(n×m)
  // 逐位置前缀比对——扫全 src/ 时是几十万次分配 + 字符级循环。
  // 这里语义就是"代码部分（已丢弃字面量内容与行尾注释）里是否出现 needle"，
  // 与 `String::contains` 完全等价，直接用内建快速子串搜索，免掉两次数组分配。
  scan_code_part(line).contains(needle)
}

///|
/// 逐行匹配一条规则，返回命中（行号从 1 起）。整行注释跳过（见 scan_is_comment_line）。

///|
/// 逐行匹配全部规则，返回命中（行号从 1 起）。整行注释跳过（见 scan_is_comment_line）。
/// 输出按规则在规则表中的顺序分组，与旧「规则外循环」次序一致。
/// BUG-162 优化：每行只做一次 `to_owned` + 一次 `code_part`（字面量感知的代码区）计算，
/// 全规则共享，把旧实现里随规则数线性放大的重复 `split`/字面量扫描归并到一次。
fn scan_match_lines(
  content : String,
  rules : Array[ScanRule],
  file : String,
) -> Array[ScanFinding] {
  // BUG-162 优化：`split` 返回一次性 `Iter`，先物化成数组（length() 会耗尽 Iter）。
  // 整行注释判定只做一次（旧实现里每条规则对每行都重判一遍 trim+has_prefix）。
  let lines = content.split("\n").to_array()
  let n = lines.length()
  let is_comment : Array[Bool] = Array::make(n, false)
  let code : Array[String] = Array::make(n, "")
  let mut ci = 0
  while ci < n {
    is_comment[ci] = scan_is_comment_line(lines[ci])
    ci = ci + 1
  }
  let out : Array[ScanFinding] = []
  // 规则外层 × 行内层，保持规则主序输出（与旧实现次序一致）
  let mut r = 0
  while r < rules.length() {
    let rule = rules[r]
    let mut l = 0
    while l < n {
      if not(is_comment[l]) {
        let ls = lines[l]
        let mut hit = false
        for needle in rule.pattern {
          // 代码区是整行的一个子串 ⇒ 整行连裸子串都不含 needle，代码区必然也不含。
          // 用 `StringView` 的快速子串搜索（flat slice，远快于 `String` 的 rope 搜索）；
          // 绝大多数 (行, needle) 在此直接短路，不进入字面量感知扫描、也不做任何分配。
          if ls.contains(needle) {
            if code[l].length() == 0 {
              code[l] = scan_code_part(ls)
            }
            if code[l].contains(needle) {
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
            line: l + 1,
            code: ls.trim().to_owned(),
          })
        }
      }
      l = l + 1
    }
    r = r + 1
  }
  out
}

// ============================================================================
// 守卫感知过滤（2026-10-10 打磨）：原规则只做行级模式匹配，不识别上下文守卫，
// 于是 `if rows.is_empty() { … } else { rows[0] }`、`if s.length() > 8 { s[0:8].to_string() }`
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
/// BUG-164 盲区 B 辅助：提取 `substring(start=N, ...)` 的 start 整数值；找不到返回 -1。
fn scan_substring_start(code : String) -> Int32 {
  match code.find("start=") {
    None => -1
    Some(idx) => {
      let pos = idx + 6
      if pos >= code.length() {
        return -1
      }
      if code[pos] < '0' || code[pos] > '9' {
        return -1
      }
      // BUG-188：同族 5 处解析器（sd_parse_int / ov_parse_int / bugreport.mbt:204 /
      // store_sqlite_executions.mbt:202 / supervisor_tools.mbt:456）都有 int_safe 上界
      // 守卫，本函数漏网。被扫描源码含 `substring(start=<长数字>, ...)` 时
      // `acc = acc * 10 + d` 溢出 Int（JS 静默乱数 / native panic），按解析失败返回 -1。
      let int_safe : Int32 = 200_000_000
      let mut acc : Int32 = 0
      let mut j = pos
      while j < code.length() && code[j] >= '0' && code[j] <= '9' {
        if acc >= int_safe {
          return -1
        }
        acc = acc * 10 + (code[j].to_int() - 48)
        j = j + 1
      }
      acc
    }
  }
}

///|
/// BUG-164 盲区 B 辅助：提取 `end~`（简写，end 变量名即 end）或 `end=<var>` 的 end 变量名；找不到返回 ""。
fn scan_substring_end_var(code : String) -> String {
  match code.find("end~") {
    Some(_) => "end"
    None =>
      match code.find("end=") {
        None => ""
        Some(idx) => {
          let pos = idx + 4
          if pos >= code.length() {
            return ""
          }
          let mut j = pos
          let start = pos
          // 变量名首字符须为字母或下划线；`end=5` 这类字面整数不算变量名。
          if j >= code.length() {
            return ""
          }
          let o0 = code[j].to_int()
          let first_ok = (o0 >= 65 && o0 <= 90) ||
            (o0 >= 97 && o0 <= 122) ||
            code[j] == '_'
          if not(first_ok) {
            return ""
          }
          while j < code.length() {
            let o = code[j].to_int()
            let ok = (o >= 65 && o <= 90) ||
              (o >= 97 && o <= 122) ||
              (o >= 48 && o <= 57) ||
              code[j] == '_'
            if ok {
              j = j + 1
            } else {
              break
            }
          }
          if j > start {
            code.substring(start~, end=j).to_string()
          } else {
            ""
          }
        }
      }
  }
}

///|
/// BUG-164 盲区 B/C：substring 的 `end` 常来自局部变量（如 `match s.find("]") { Some(end) => ... }`），
/// 守卫写在**上一行**。识别两种形态，把该类假阳性过滤掉：
///   B 形态：`if <end_var> > N` / `if <end_var> >= N`（N = start 参数）
///   C 形态：`<end_var> <= <target>.length()`（end 被目标长度上界约束）
/// 只认 `if ` 前缀 + 变量名精确匹配，避免误伤无关比较。
fn scan_guard_substring_end_var(
  prev : String,
  code : String,
  vn : String,
) -> Bool {
  let t = prev.trim().to_string()
  if t.is_empty() {
    return false
  }
  // 守卫形态：`if ...` / `} else if ...`（engine_triage.mbt:46 是 else-if 分支）
  let is_cond = t.has_prefix("if ") ||
    t.has_prefix("if(") ||
    t.contains(" else if ") ||
    t.contains("else if ")
  if not(is_cond) {
    return false
  }
  let start_n = scan_substring_start(code)
  if start_n < 0 {
    return false
  }
  let ev = scan_substring_end_var(code)
  if ev.is_empty() {
    return false
  }
  let ns = start_n.to_string()
  // B 形态：`if end > 3` / `if end >= 3`——只认 start≥1（start=0 时 `end>0` 不构成上界，见反向锁）
  // 该形态用于 `find()` 绑定的 end 变量（天然有界），`end > start` 才能保证不越界。
  let b_hit = start_n >= 1 &&
    (
      t.contains(ev + " > " + ns) ||
      t.contains(ev + " >" + ns) ||
      t.contains(ev + " >= " + ns) ||
      t.contains(ev + " >=" + ns)
    )
  if b_hit {
    return true
  }
  // C 形态：`max <= s.length()`（engine_triage.mbt:46 `} else if max > 0 && max <= s.length() {`）
  // 该形态在 start=0 时保证 end_var ≥ 0 且 end_var ≤ length，substring 不越界。
  if start_n == 0 && not(vn.is_empty()) {
    let len_ref = vn + ".length()"
    if t.contains(ev + " <= " + len_ref) || t.contains(ev + "<=" + len_ref) {
      return true
    }
  }
  false
}

///|
/// BUG-268 辅助：解析非负整数（与 scan_substring_start 同款 int_safe 上界）；
/// 失败/空/溢出返回 -1。
fn scan_parse_int_opt(s : String) -> Int32 {
  let t = s.trim().to_string()
  if t.is_empty() {
    return -1
  }
  let int_safe : Int32 = 200_000_000
  let mut acc : Int32 = 0
  for c in t {
    if c < '0' || c > '9' {
      return -1
    }
    if acc >= int_safe {
      return -1
    }
    acc = acc * 10 + (c.to_int() - 48)
  }
  acc
}

///|
/// BUG-268 辅助：去掉字符串里的所有空格。刻意不用 `String::replace`——
/// 本仓钉版 moon 的 `replace` 需要 `old~/new~` 标签且返回 `StringView`，直接写
/// `.replace(" ", "")` 会撞 4014/4080/4086 三连编译错；这里显式拼一个 `String`，
/// 语义等价且不受 core 版本漂移影响。
fn scan_nospace(s : String) -> String {
  let mut out = ""
  for c in s {
    if c != ' ' {
      out = out + c.to_string()
    }
  }
  out
}

///|
/// BUG-268 辅助：提取 substring 的 `start=` / `end=` 参数表达式原文
/// （到逗号/右括号前、去首尾空白），如 `start=d` → `d`、`end=d + 1` → `d + 1`；
/// 找不到返回 ""。`end~` 简写按现有约定返回 "end"。
fn scan_substring_arg_expr(code : String, arg : String) -> String {
  let pat = arg + "="
  match code.find(pat) {
    None => ""
    Some(idx) => {
      let pos = idx + pat.length()
      if pos >= code.length() {
        return ""
      }
      let mut j = pos
      let mut depth : Int32 = 0
      while j < code.length() {
        let c = code[j]
        if c == '(' {
          depth = depth + 1
        } else if c == ')' {
          if depth > 0 {
            depth = depth - 1
          } else {
            break
          }
        } else if c == ',' && depth == 0 {
          break
        }
        j = j + 1
      }
      code.substring(start=pos, end=j).to_string().trim().to_string()
    }
  }
}

///|
fn scan_substring_start_expr(code : String) -> String {
  scan_substring_arg_expr(code, "start")
}

///|
fn scan_substring_end_expr(code : String) -> String {
  match code.find("end~") {
    Some(_) => "end"
    None => scan_substring_arg_expr(code, "end")
  }
}

///|
/// BUG-268 形态 A：模运算不变量。`let d = rem % 16` 使 0 ≤ d < 16，
/// `hex.substring(start=d, end=d+1)` 的 end=d+1 ≤ 16 = hex 长度，安全。
/// 要求：prev_lines 内存在 `let <v> = <expr> % <K>`（K 数字字面量），start_expr == v，
/// end_expr 为 v 或 v+1（去空格比对），且目标 vn 的字面量定义长度 ≥ K。
/// 保守：任一步不满足即返回 false，把判定留给下游（拿不准就保留）。
fn scan_guard_mod_invariant(
  prev_lines : Array[String],
  start_expr : String,
  end_expr : String,
  vn : String,
) -> Bool {
  if start_expr.is_empty() || vn.is_empty() {
    return false
  }
  let se = start_expr.trim().to_string()
  let ee = scan_nospace(end_expr.trim().to_string())
  let ee_ok = ee == se || ee == se + "+1"
  if not(ee_ok) {
    return false
  }
  let mut mod_k : Int32 = -1
  let mut found = false
  for p in prev_lines {
    let t = p.trim().to_string()
    if t.is_empty() {
      continue
    }
    let pref = "let " + se + " = "
    if t.has_prefix(pref) {
      let rest = t.substring(start=pref.length(), end=t.length()).to_string()
      match rest.find(" % ") {
        Some(pi) => {
          let ktxt = rest
            .substring(start=pi + 3, end=rest.length())
            .to_string()
            .trim()
            .to_string()
          let kv = scan_parse_int_opt(ktxt)
          if kv >= 0 {
            mod_k = kv
            found = true
            break
          }
        }
        None => ()
      }
    }
  }
  if not(found) || mod_k < 0 {
    return false
  }
  // 目标长度：`let <vn> = "<literal>"` 的字面量长度 ≥ K
  for p in prev_lines {
    let t = p.trim().to_string()
    let pref2 = "let " + vn + " = "
    if t.has_prefix(pref2) {
      let lit = t
        .substring(start=pref2.length(), end=t.length())
        .to_string()
        .trim()
      if lit.length() >= 2 && lit[0] == '"' && lit[lit.length() - 1] == '"' {
        if lit.length() - 2 >= mod_k {
          return true
        }
      }
    }
  }
  false
}

///|
/// BUG-268 形态 B：for 循环有界迭代。`for i in 0..<26` 使 0 ≤ i ≤ 25，
/// `upper.substring(start=i, end=i+1)` 的 end=i+1 ≤ 26 = 目标长度，安全。
/// 要求：prev_lines 内存在 `for <v> in 0..<N`（N 数字字面量），start_expr == v，
/// end_expr 为 v 或 v+1，且目标 vn 字面量长度 ≥ N。
fn scan_guard_for_bounded(
  prev_lines : Array[String],
  start_expr : String,
  end_expr : String,
  vn : String,
) -> Bool {
  if start_expr.is_empty() || vn.is_empty() {
    return false
  }
  let se = start_expr.trim().to_string()
  let ee = scan_nospace(end_expr.trim().to_string())
  let ee_ok = ee == se || ee == se + "+1"
  if not(ee_ok) {
    return false
  }
  let mut bound : Int32 = -1
  let mut found = false
  for p in prev_lines {
    let t = p.trim().to_string()
    let pref = "for " + se + " in 0..<"
    if t.has_prefix(pref) {
      let ktxt = t
        .substring(start=pref.length(), end=t.length())
        .to_string()
        .trim()
        .to_string()
      // BUG-268 补充：`for i in 0..<26 {` 尾部 `{` 会混入字面量导致 parse 失败
      let mut kk = ktxt
      while kk.length() > 0 &&
            (
              kk[kk.length() - 1] == '{' ||
              kk[kk.length() - 1] == '}' ||
              kk[kk.length() - 1] == ' '
            ) {
        kk = kk.substring(start=0, end=kk.length() - 1).to_string()
      }
      let kv = scan_parse_int_opt(kk)
      if kv >= 0 {
        bound = kv
        found = true
        break
      }
    }
  }
  if not(found) || bound < 0 {
    return false
  }
  for p in prev_lines {
    let t = p.trim().to_string()
    let pref2 = "let " + vn + " = "
    if t.has_prefix(pref2) {
      let lit = t
        .substring(start=pref2.length(), end=t.length())
        .to_string()
        .trim()
      if lit.length() >= 2 && lit[0] == '"' && lit[lit.length() - 1] == '"' {
        if lit.length() - 2 >= bound {
          return true
        }
      }
    }
  }
  false
}

///|
/// BUG-268 辅助：判断减数 X 是否在 prev_lines 中被约束为非负且有界。
/// 两种安全来源：① 数字字面量 ≥ 0；② `let <X> = if <A> < 0 { 0 } else { <limit> }`
/// （X = max(limit, 0)，与 if-else 守卫上限同源）。
fn scan_cut_bounded(
  prev_lines : Array[String],
  x : String,
  limit : String,
) -> Bool {
  let xt = x.trim().to_string()
  if xt.is_empty() || limit.is_empty() {
    return false
  }
  let kv = scan_parse_int_opt(xt)
  if kv >= 0 {
    return true
  }
  for p in prev_lines {
    let t = p.trim().to_string()
    let pref = "let " + xt + " = "
    if t.has_prefix(pref) {
      let rhs = t.substring(start=pref.length(), end=t.length()).to_string()
      if rhs.contains("< 0 { 0 }") && rhs.contains(limit) {
        return true
      }
    }
  }
  false
}

///|
/// BUG-268 形态 D：前 N 行多行 if-else 长度守卫。
/// `let n = content.length()` → `if n <= max_chars { ... } else { let cut = if max_chars < 0
/// { 0 } else { max_chars }; substring(start=n - cut, end=n) }`：
/// else 分支中 n > max_chars，cut = max(max_chars, 0) ≤ max_chars < n，
/// start=n-cut ∈ (0, n)、end=n = 长度，安全。
/// 要求：① prev_lines 有 `let <lenv> = <vn>.length()`；
/// ② prev_lines 有 `if <lenv> <= <L> {`（或 `< <L>`）且其后出现 `} else {`；
/// ③ code 的 start/end 表达式为 0 / lenv / lenv-<X>，X 满足 scan_cut_bounded。
fn scan_guard_multi_line_length(
  prev_lines : Array[String],
  code : String,
  vn : String,
) -> Bool {
  if vn.is_empty() {
    return false
  }
  let start_expr = scan_substring_start_expr(code)
  let end_expr = scan_substring_end_expr(code)
  let se = start_expr.trim().to_string()
  let ee = scan_nospace(end_expr.trim().to_string())
  // ① lenv 绑定
  let mut lenv = ""
  for p in prev_lines {
    let t = p.trim().to_string()
    if t.has_prefix("let ") && t.contains(vn + ".length()") {
      match t.find(" = ") {
        Some(ei) => {
          let name = t.substring(start=4, end=ei).to_string().trim().to_string()
          if not(name.is_empty()) {
            lenv = name
            break
          }
        }
        None => ()
      }
    }
  }
  if lenv.is_empty() {
    return false
  }
  // ② if <lenv> <= <L> / < <L>，其后有 } else {
  let mut limit = ""
  let mut if_idx = -1
  for i in 0..<prev_lines.length() {
    let t = prev_lines[i].trim().to_string()
    let pref = "if " + lenv + " <= "
    let pref2 = "if " + lenv + " < "
    if t.has_prefix(pref) {
      limit = t
        .substring(start=pref.length(), end=t.length())
        .to_string()
        .trim()
        .to_string()
      if_idx = i
      break
    }
    if t.has_prefix(pref2) {
      limit = t
        .substring(start=pref2.length(), end=t.length())
        .to_string()
        .trim()
        .to_string()
      if_idx = i
      break
    }
  }
  if if_idx < 0 || limit.is_empty() {
    return false
  }
  // ②′ 修剪 limit 尾部的 `{`：`if n <= max_chars {` → `max_chars`（BUG-268：memory_gc_logic
  // L160 就是这种形状，不修剪会让 scan_cut_bounded 拿 "max_chars {" 去子串比对，恒失败）。
  while limit.length() > 0 && limit[limit.length() - 1] == '{' {
    limit = limit.substring(start=0, end=limit.length() - 1).to_string()
  }
  limit = limit.trim().to_string()
  if limit.is_empty() {
    return false
  }
  // BUG-268 实测：issue_scan 传入的 prev_lines 是"从最近一行往回扫"的近邻窗口，
  // 顺序是**倒序**（`} else {` 在 `if n <= max_chars {` 之前），所以 else 检测不能
  // 只从 if 之后往后找——只要窗口里同时存在 `if <lenv> <= <L>` 与 `} else {` 即可，
  // 与两者相对顺序无关（保守：形状要求强，误豁免风险低）。
  let mut after_else = false
  for p in prev_lines {
    if p.contains("} else {") {
      after_else = true
      break
    }
  }
  if not(after_else) {
    return false
  }
  // ③ start/end 表达式在安全集合内（start/end 归一化空格：`n - cut` ≡ `n-cut`）
  let se_n = scan_nospace(se)
  let mut ee_ok = false
  if ee == lenv {
    ee_ok = true
  } else {
    let pref3 = lenv + "-"
    if ee.has_prefix(pref3) {
      let x = ee.substring(start=pref3.length(), end=ee.length()).to_string()
      if scan_cut_bounded(prev_lines, x, limit) {
        ee_ok = true
      }
    }
  }
  if not(ee_ok) {
    return false
  }
  if se_n == "0" || se_n == lenv {
    return true
  }
  let pref4 = lenv + "-"
  if se_n.has_prefix(pref4) {
    let x = se_n.substring(start=pref4.length(), end=se_n.length()).to_string()
    return scan_cut_bounded(prev_lines, x, limit)
  }
  false
}

///|
/// BUG-268 形态 E：has_suffix 间接长度。
/// `let cut = if names.has_suffix(", ") { 2 } else { 0 }` 使 cut ∈ {0, k}；
/// cut=k>0 时 names 至少含该后缀（长度 ≥ k），`names.substring(start=0,
/// end=names.length() - cut)` 不越界。要求：end_expr 形如 `<vn>.length() - <cut>`，
/// prev_lines 有上述 has_suffix 定义行，且 if 分支值 k ∈ 1..4（保守小值）。
fn scan_guard_has_suffix_cut(
  prev_lines : Array[String],
  code : String,
  vn : String,
) -> Bool {
  if vn.is_empty() {
    return false
  }
  let ee = scan_nospace(scan_substring_end_expr(code).trim().to_string())
  let need = vn + ".length()-"
  if not(ee.has_prefix(need)) {
    return false
  }
  let cutv = ee.substring(start=need.length(), end=ee.length()).to_string()
  if cutv.is_empty() {
    return false
  }
  for p in prev_lines {
    let t = p.trim().to_string()
    let pref = "let " + cutv + " = "
    if t.has_prefix(pref) && t.contains(vn + ".has_suffix(") {
      let body = t.substring(start=pref.length(), end=t.length()).to_string()
      // body: `if <vn>.has_suffix(<lit>) { <k> } else { 0 }`
      match body.find(" { ") {
        Some(oi) => {
          let seg = body.substring(start=oi + 3, end=body.length()).to_string()
          // seg: `<k> } else { 0 }`
          match seg.find(" } else { ") {
            Some(ci) => {
              let ktxt = seg
                .substring(start=0, end=ci)
                .to_string()
                .trim()
                .to_string()
              let kv = scan_parse_int_opt(ktxt)
              if kv >= 1 && kv <= 4 {
                return true
              }
            }
            None => ()
          }
        }
        None => ()
      }
    }
  }
  false
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
/// 在一条行（prev 行或 code 自身）里找除数变量 `vn` 的**直接守卫**形态：
/// `if <vn> > 0` / `if <vn> <= 0` / `if <vn> != 0` / `if <vn> == 0` / `if <vn> >= 1` 等。
/// BUG-152：unprotected-division 的 hint 明写 `` `if total > 0 { ... } else { 兜底 }` ``，
/// 实现须同步认这一形态，否则 hint 承诺了却把真守卫代码报成假阳性。
/// 只认 `vn` 字面量紧跟比较运算符的形状，避免把同函数里无关的 `if` 行误判。
fn scan_guard_div_direct(line : String, vn : String) -> Bool {
  let t = line.trim().to_string()
  if t.is_empty() || vn.is_empty() {
    return false
  }
  t.contains(vn + " > 0") ||
  t.contains(vn + " >0") ||
  t.contains(vn + " > 0.0") ||
  t.contains(vn + " >0.0") ||
  t.contains(vn + " >= 1") ||
  t.contains(vn + " >=1") ||
  t.contains(vn + " >= 1.0") ||
  t.contains(vn + " <= 0") ||
  t.contains(vn + " <=0") ||
  t.contains(vn + " <= 0.0") ||
  t.contains(vn + " <=0.0") ||
  t.contains(vn + " < 1") ||
  t.contains(vn + " <1") ||
  t.contains(vn + " != 0") ||
  t.contains(vn + " !=0") ||
  t.contains(vn + " == 0") ||
  t.contains(vn + " ==0") ||
  t.contains(vn + " == 0.0") ||
  t.contains(vn + " ==0.0")
}

///|
/// BUG-152：secs-overflow 的类型语境判定——该行/上下文是否**显式 Int32**。
/// MoonBit 默认 `Int` 在 JS 目标为 53 位安全整数（~9e15）、native 为 64 位（~9.2e18），
/// `days*86400` 需 days>1e11 才溢出（约 3.3 千年），正常代码不可能；只有显式 `Int32`
/// （32 位，最大 21 亿）才在 days>24855（约 68 年，Y2038 问题）时溢出。故仅显式 Int32
/// 应保留为真阳性，默认 Int / Int64 / Double / f64 一律 suppress。
/// 只查 code 自身 + prev_lines 近几行即可（secs 计算类型由上下文变量决定）。
/// 匹配 `Int32` 用精确子串，避免把默认 `Int` 误判成 Int32 信号。
fn scan_has_int32_signal(s : String) -> Bool {
  s.contains("Int32") ||
  s.contains(".to_int32()") ||
  s.contains("Int32.of") ||
  s.contains("Int32.new") ||
  s.contains("Int32::")
}

///|
/// BUG-152：判定 secs-overflow 命中是否应被 suppress（返回 true = 假阳性，过滤掉）。
/// 顺序：Int64/Double/f64 注解 → 不溢出，suppress；显式 Int32 信号 → 真阳性保留；
/// 两者皆无 → 默认 Int，正常代码不会溢出，suppress。
/// prev_lines 用 `scan_code_part` 去注释后匹配，避免把注释散文里的「Int32」误当类型注解
/// （实测 `ops_ts.mbt` 的 `days*86400` 上下文注释反复提「Int32 上界」，裸子串会误判成真阳性）。
fn scan_secs_suppressed(code : String, prev_lines : Array[String]) -> Bool {
  if code.contains("Int64") || code.contains("Double") || code.contains("f64") {
    return true
  }
  if scan_has_int32_signal(code) {
    return false
  }
  let mut k = prev_lines.length() - 1
  while k >= 0 {
    let p = prev_lines[k]
    k = k - 1
    if p.is_empty() {
      continue
    }
    let cp = scan_code_part(p)
    if cp.contains("Int64") || cp.contains("Double") || cp.contains("f64") {
      return true
    }
    if scan_has_int32_signal(cp) {
      return false
    }
  }
  true
}

///|
/// BUG-164 盲区 A：从 `X.unwrap()` 里取出接收者表达式 X（取 `.unwrap(` 之前最后一个
/// 标识符/点链，如 `pending_advance.unwrap()` → `pending_advance`）。
fn scan_unwrap_receiver(code : String) -> String {
  let pos = code.find(".unwrap(")
  match pos {
    None => ""
    Some(idx) => {
      if idx == 0 {
        return ""
      }
      let mut i = idx - 1
      let mut start = idx
      // 向回收集标识符字符 + 点链（`a.b.unwrap()` 也要能取到 `a.b`）
      while i >= 0 {
        let c = code[i]
        let ok = (c >= 'a' && c <= 'z') ||
          (c >= 'A' && c <= 'Z') ||
          (c >= '0' && c <= '9') ||
          c == '_' ||
          c == '.'
        if not(ok) {
          break
        }
        start = i
        i = i - 1
      }
      let r = code.substring(start~, end=idx).to_string()
      // 跳过末尾多余的点（`.unwrap(` 前的 `.` 归属方法调用）
      if r.has_suffix(".") {
        r.substring(start=0, end=r.length() - 1).to_string()
      } else {
        r
      }
    }
  }
}

///|
/// 判定一条命中是否被**明显**上下文守卫（5 行内可判，只做保守过滤——拿不准就保留）。
pub fn scan_finding_guarded(
  code : String,
  rule : String,
  prev_lines : Array[String],
  ctx~ : ScanCtx = {
    safe_clamps: Map([]),
    guarded_lines: Map([]),
    slice_only: false,
  },
  hit_line~ : String = "",
  hit_ln~ : Int32 = 0,
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
  if rule == "unprotected-division" && ctx.safe_clamps.get(vn) is Some(_) {
    return true
  }
  // BUG-152: unprotected-division 直接守卫识别 — hint `if total > 0 { ... } else { 兜底 }`
  // 守卫常与除法**同一行**（`let acc = if total > 0 { passed / total * 100 } else { 0.0 }`），
  // prev_lines 不含当前行，故先查 code 自身。
  if rule == "unprotected-division" && not(vn.is_empty()) {
    if scan_guard_div_direct(code, vn) {
      return true
    }
  }
  // R124: possible-overflow 乘法前守卫
  if rule == "possible-overflow" && hit_ln > 0 {
    let mut check = hit_ln - 1
    while check >= hit_ln - 6 && check > 0 {
      if ctx.guarded_lines.get(check) is Some(_) {
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
    if code_t.contains(".length() - 1") ||
      code_t.contains(".length()-1") ||
      code_t.contains("end=.length()") ||
      code_t.contains("end = .length()") {
      return true
    }
    // BUG-268：跨行/间接守卫形态（prev_lines 循环外整体识别，保守过滤假阳性）
    if not(vn.is_empty()) {
      let sexpr = scan_substring_start_expr(code)
      let eexpr = scan_substring_end_expr(code)
      // 形态 A：模运算不变量（`let d = rem % 16` + `substring(start=d, end=d+1)`）
      if scan_guard_mod_invariant(prev_lines, sexpr, eexpr, vn) {
        return true
      }
      // 形态 B：for 循环有界迭代（`for i in 0..<26` + `substring(start=i, end=i+1)`）
      if scan_guard_for_bounded(prev_lines, sexpr, eexpr, vn) {
        return true
      }
      // 形态 D：前 N 行多行 if-else 长度守卫（`if n <= max_chars { ... } else { ... }`）
      if scan_guard_multi_line_length(prev_lines, code, vn) {
        return true
      }
      // 形态 E：has_suffix 间接长度（`let cut = if names.has_suffix(...) { 2 } else { 0 }`）
      if scan_guard_has_suffix_cut(prev_lines, code, vn) {
        return true
      }
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
    if hit_line.contains(".to_double()") ||
      hit_line.contains("Double") ||
      hit_line.contains("f64") {
      return true
    }
  }
  // BUG-152: secs-overflow 规则原假设 Int32，对 MoonBit 默认 Int 系统性误报。
  // 类型语境由 code 自身 + prev_lines 决定：显式 Int32 → 真阳性保留（false）；
  // 默认 Int / Int64 / Double / f64 → 不溢出 → suppress（true）。
  if rule == "secs-overflow" {
    return scan_secs_suppressed(code, prev_lines)
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
      // BUG-152: prev 行的直接守卫 `if total > 0 {` / `if total_w <= 0 {`
      if not(vn.is_empty()) && scan_guard_div_direct(t, vn) {
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
      // BUG-164 盲区 B/C：`end` 来自局部变量，守卫是上一行 `if end > N` 或 `<end_var> <= <target>.length()`
      if scan_guard_substring_end_var(t, code, vn) {
        return true
      }
      if t.has_prefix("fn ") {
        return false
      }
    } else if rule == "index-out-of-bounds" || rule == "string-index" {
      if t.contains("is_empty()") {
        return true
      }
      // R125: `if arr.length() > 0` / `if arr.length() >= N` 守卫
      if t.contains(".length() >") ||
        t.contains(".length() >= ") ||
        t.contains(".length() ==") {
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
      if t.has_prefix("fn ") {
        return false
      }
      if t.has_prefix("fn ") {
        return false
      }
    } else if rule == "unwrapped-unwrap" {
      // BUG-164 盲区 A：`X.unwrap()` 的守卫常写在**上一行** `if X.is_some() { ... }`
      // 或 `match X { Some(_) => ... }`，prev_lines 里识别到即豁免。
      let rc = scan_unwrap_receiver(code)
      if not(rc.is_empty()) {
        if t.contains(rc) && (t.contains("is_some()") || t.contains("is_ok()")) {
          return true
        }
      }
    } else if rule == "possible-overflow" {
      // R124: prev_lines 里 >= INT_SAFE 守卫
      if t.contains(">= INT_SAFE") ||
        t.contains(">= 200_000_000") ||
        t.contains(">=200_000_000") {
        return true
      }
      // R125: Double/f64 乘法不会 Int overflow
      if code.contains(".to_double()") ||
        code.contains("Double") ||
        code.contains("f64") {
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
    // BUG-268：近邻窗口由 6 扩到 12，覆盖 `let upper = "..."` 等字面量定义
    // 与 for 循环头相距较远的形态 B 场景（如 mcs_lower 中定义与使用隔 9 行）。
    let prev_start = if ln - 12 < 1 { 1 } else { ln - 12 }
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
/// BUG-222：read_dir 失败（目录不存在/不可读）必须回执 Err，不得静默返回空结果，
/// 否则 issue_scan 会返回 scanned_files=0 的"假干净"结果误导调用方。
fn scan_collect(
  dir : String,
  include_tests : Bool,
  out : Array[String],
) -> Result[Unit, String] {
  let names = @fs.read_dir(dir) catch {
    _ =>
      return Err(
        "issue_scan: 无法读取目录（不存在或不可读）: " + dir,
      )
  }
  for name in names {
    let p = mem_join(dir, name)
    if scan_skip(p) {
      continue
    }
    if scan_detect_dir(p) {
      match scan_collect(p, include_tests, out) {
        Ok(_) => ()
        Err(e) => return Err(e)
      }
    } else if p.has_suffix(".mbt") {
      if include_tests || not(scan_is_test_file(p)) {
        out.push(p)
      }
    }
  }
  Ok(())
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
  for f in scan_match_lines(content, rules, path) {
    out.push(f)
  }
  out
}

///|
/// 从 ocr-local 的 regex pattern 提取稳定字面量 needle（子串近似，免 regex 依赖）。
/// 策略：扫描 pattern，收集连续字母数字片段，取最长者；`\w` `\s` `\d` 等 regex 类跳过。
/// 例：`ignore\s*\(\s*\w+` → "ignore"；`@fs\.(open|write|read)\s*\(` → "open"。
fn scan_regex_to_needle(re : String) -> String {
  let cs = re.to_array()
  let n = cs.length()
  let mut best = ""
  let mut cur = ""
  let mut i = 0
  while i < n {
    let c = cs[i]
    let o = c.to_int()
    let alnum = (o >= 65 && o <= 90) ||
      (o >= 97 && o <= 122) ||
      (o >= 48 && o <= 57)
    if alnum {
      cur = cur + c.to_string()
    } else {
      if cur.length() > best.length() {
        best = cur
      }
      cur = ""
    }
    i = i + 1
  }
  if cur.length() > best.length() {
    best = cur
  }
  best
}

///|
/// 从外部规则 JSON 文本（ocr-local moonbit-rules.json 风格：顶层 `rules` 数组，
/// 每条含 name/severity/pattern/why/description）解析为 ScanRule 表。
/// 非法 JSON / 缺字段 / 解析出 0 条 → Err；pattern 经 scan_regex_to_needle 转 needle。
fn scan_parse_external_rules(
  json_text : String,
) -> Result[Array[ScanRule], String] {
  let parsed : Json = @json.parse(json_text) catch {
    e =>
      return Err("issue_scan: 外部规则 JSON 解析失败: " + e.to_string())
  }
  let arr = match parsed {
    Json::Object(m) =>
      match m.get("rules") {
        None => return Err("issue_scan: 外部规则缺 rules 数组")
        Some(Json::Array(a)) => a
        Some(_) => return Err("issue_scan: rules 不是数组")
      }
    _ => return Err("issue_scan: 外部规则顶层不是 JSON 对象")
  }
  let out : Array[ScanRule] = []
  for r in arr {
    let obj = match r {
      Json::Object(m) => m
      _ => continue
    }
    let name = match obj.get("name") {
      Some(Json::String(s)) => s
      _ => continue
    }
    let sev = match obj.get("severity") {
      Some(Json::String(s)) => s
      _ => "medium"
    }
    let pat = match obj.get("pattern") {
      Some(Json::String(s)) => s
      _ => continue
    }
    let why = match obj.get("why") {
      Some(Json::String(s)) => s
      _ => ""
    }
    let hint = match obj.get("description") {
      Some(Json::String(s)) => s
      _ => ""
    }
    let needle = scan_regex_to_needle(pat)
    if needle.length() < 2 {
      continue
    }
    out.push({ id: name, severity: sev, pattern: [needle], why, hint, })
  }
  if out.is_empty() {
    return Err("issue_scan: 外部规则解析出 0 条可用规则")
  }
  Ok(out)
}

///|
/// 读取并解析外部规则文件。路径先过 scan_dir_ok（拒绝对称/穿越/盘符），
/// 再 mem_read 读内容交给 scan_parse_external_rules。
fn scan_load_external_rules(path : String) -> Result[Array[ScanRule], String] {
  if not(scan_dir_ok(path)) {
    return Err(
      "issue_scan: 非法规则文件路径（拒绝绝对路径/穿越/盘符）: " +
      path,
    )
  }
  let content = match mem_read(path) {
    None => return Err("issue_scan: 无法读取外部规则文件: " + path)
    Some(c) => c
  }
  scan_parse_external_rules(content)
}

///|
/// 内建 + 外部规则合并：同名（id 相同）外部规则覆盖内建，其余外部规则追加。
/// 内建规则若被外部覆盖则不再单独出现（避免同 id 双条）。
fn scan_merge_rules(
  builtin : Array[ScanRule],
  external : Array[ScanRule],
) -> Array[ScanRule] {
  let out : Array[ScanRule] = []
  for b in builtin {
    let dup = external.filter(fn(e : ScanRule) { e.id == b.id })
    if dup.is_empty() {
      out.push(b)
    }
  }
  for e in external {
    out.push(e)
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
  max_findings : Int32,
  include_tests~ : Bool = false,
) -> Result[Json, String] {
  if not(scan_dir_ok(dir)) {
    return Err(
      "issue_scan: 非法目录（拒绝绝对路径/穿越/盘符）: " + dir,
    )
  }
  // 外部规则文件（ocr-local moonbit-rules.json 风格）：非空则真实读取 + 解析 + 合并，
  // 同名外部规则覆盖内建（档 2 ocr-local 融入 bugfind）；空串走内建，行为与改造前完全一致。
  let rules = if rules_file.length() > 0 {
    match scan_load_external_rules(rules_file) {
      Ok(ext) => scan_merge_rules(scan_rules(), ext)
      Err(e) => return Err(e)
    }
  } else {
    scan_rules()
  }
  let files : Array[String] = []
  match scan_collect(dir, include_tests, files) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
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
  // BUG-162 优化：文件级缓存 —— 同一文件的多条命中共享一次读盘 + 一次按行拆分，
  // 否则 json-injection（1334 条）这类高频命中的文件会被反复读盘、反复 split。
  let ctx_cache : Map[String, ScanCtx] = Map([])
  let lines_cache : Map[String, Array[String]] = Map([])
  let fc_cache : Map[String, String] = Map([])
  let guarded_filtered : Array[ScanFinding] = []
  for hit in dedup {
    // BUG-162 优化：只有少数规则会被守卫豁免（substring-overrun / unprotected-division /
    // unwrapped-unwrap / possible-overflow / index-out-of-bounds / string-index / secs-overflow），
    // 其余规则（unused-variable、match-exhaustive、long-function、json-injection 等
    // 占全量 findings 大头）的命中直接透传，免掉 mem_read + split + prev_window 三件套。
    if not(
        hit.rule == "substring-overrun" ||
        hit.rule == "unprotected-division" ||
        hit.rule == "unwrapped-unwrap" ||
        hit.rule == "possible-overflow" ||
        hit.rule == "index-out-of-bounds" ||
        hit.rule == "string-index" ||
        hit.rule == "secs-overflow",
      ) {
      guarded_filtered.push(hit)
      continue
    }
    let fc = match fc_cache.get(hit.file) {
      Some(c) => c
      None =>
        match mem_read(hit.file) {
          None => continue
          Some(c) => {
            fc_cache.set(hit.file, c)
            c
          }
        }
    }
    // R124: 文件级 ctx 缓存（每个文件只构建一次）
    let ctx = match ctx_cache.get(hit.file) {
      Some(c) => c
      None => {
        let new_ctx = scan_build_ctx(fc)
        ctx_cache.set(hit.file, new_ctx)
        new_ctx
      }
    }
    let fc_lines : Array[String] = match lines_cache.get(hit.file) {
      Some(ls) => ls
      None => {
        let ls : Array[String] = []
        for l in fc.split("\n") {
          ls.push(l.to_owned())
        }
        lines_cache.set(hit.file, ls)
        ls
      }
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
  // 严重度聚合（单次遍历，替代旧的三次全量 filter）
  let mut high = 0
  let mut medium = 0
  let mut low = 0
  // 按规则聚合（单次遍历计数，替代旧的逐规则全量 filter）
  let rule_counts : Map[String, Int32] = Map([])
  for h in dedup {
    if h.severity == "high" {
      high = high + 1
    } else if h.severity == "medium" {
      medium = medium + 1
    } else {
      low = low + 1
    }
    rule_counts.set(h.rule, rule_counts.get(h.rule).unwrap_or(0) + 1)
  }
  // 按规则聚合
  let by_rule : Array[Json] = []
  for r in rules {
    let cnt = rule_counts.get(r.id).unwrap_or(0)
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

///|
fn _ctx() -> ScanCtx {
  { safe_clamps: Map([]), guarded_lines: Map([]), slice_only: false, }
}

///|
test "R125 string-index same-line length() > 0 guard" {
  let hit_line = "let sk = if top.skill_hits.length() > 0 { top.skill_hits[0] } else { \"\" }"
  let code = "top.skill_hits[0]"
  let result = scan_finding_guarded(
    code,
    "string-index",
    [],
    ctx=_ctx(),
    hit_line~,
    hit_ln=272,
  )
  assert_true(result)
}

///|
test "R125 string-index prev-line while length() guard" {
  let prev = ["while ready_ids.length() > 0 {"]
  let hit_line = "let cur = ready_ids[0]"
  let result = scan_finding_guarded(
    "ready_ids[0]",
    "string-index",
    prev,
    ctx=_ctx(),
    hit_line~,
    hit_ln=273,
  )
  assert_true(result)
}

///|
test "R125 substring-overrun safe end=length()-1" {
  let hit_line = "s.substring(start=0, end=s.length() - 1).to_string()"
  let result = scan_finding_guarded(
    hit_line,
    "substring-overrun",
    [],
    ctx=_ctx(),
    hit_line~,
    hit_ln=270,
  )
  assert_true(result)
}

///|
test "R125 unprotected-division prev-line if total > 0 direct guard" {
  let prev = ["  let passed = score_sum", "  if total > 0 {"]
  let code = "    let acc = passed / total * 100"
  let result = scan_finding_guarded(
    code,
    "unprotected-division",
    prev,
    ctx=_ctx(),
    hit_line=code,
    hit_ln=346,
  )
  assert_true(result)
}

///|
test "R125 unprotected-division same-line if total_w <= 0 direct guard" {
  let code = "  let share = if total_w <= 0 { 0 } else { budget * w / total_w }"
  let result = scan_finding_guarded(
    code,
    "unprotected-division",
    [],
    ctx=_ctx(),
    hit_line=code,
    hit_ln=862,
  )
  assert_true(result)
}

///|
test "R125 unprotected-division no guard not filtered" {
  let prev = ["  let passed = score_sum", "  let total = count"]
  let code = "    let acc = passed / total * 100"
  let result = scan_finding_guarded(
    code,
    "unprotected-division",
    prev,
    ctx=_ctx(),
    hit_line=code,
    hit_ln=346,
  )
  assert_true(not(result))
}

///|
/// BUG-152: secs-overflow 显式 Int32 是真阳性，guard 应返回 false（不过滤）。
test "BUG-152 secs-overflow explicit Int32 keeps finding" {
  let code = "  let t = (days : Int32) * 86400"
  let result = scan_finding_guarded(
    code,
    "secs-overflow",
    [],
    ctx=_ctx(),
    hit_line=code,
    hit_ln=120,
  )
  assert_true(not(result))
}

///|
/// BUG-152: secs-overflow 含 `.to_int32()` 是真阳性，guard 应返回 false。
test "BUG-152 secs-overflow to_int32 keeps finding" {
  let code = "  let t = days.to_int32() * 86400"
  let result = scan_finding_guarded(
    code,
    "secs-overflow",
    [],
    ctx=_ctx(),
    hit_line=code,
    hit_ln=121,
  )
  assert_true(not(result))
}

///|
/// BUG-152: secs-overflow 默认 Int（无 Int32 注解）是假阳性，guard 应返回 true（suppress）。
test "BUG-152 secs-overflow default Int suppressed" {
  let code = "  let t = days * 86400 + hour * 3600"
  let result = scan_finding_guarded(
    code,
    "secs-overflow",
    [],
    ctx=_ctx(),
    hit_line=code,
    hit_ln=122,
  )
  assert_true(result)
}

///|
/// BUG-152: secs-overflow 含 Int64 注解不会溢出，guard 应返回 true（suppress）。
test "BUG-152 secs-overflow Int64 suppressed" {
  let code = "  let t = (days : Int64) * 86400L + 86400"
  let result = scan_finding_guarded(
    code,
    "secs-overflow",
    [],
    ctx=_ctx(),
    hit_line=code,
    hit_ln=123,
  )
  assert_true(result)
}

///|
/// BUG-152: prev_lines 里「Int32」只出现在注释散文（非类型注解）时不应误判为真阳性。
test "BUG-152 secs-overflow Int32 only in comment suppressed" {
  let prev = [
    "  // 24820*86400 ≈ 2.14e9 < 2^31-1，已越过 Int32 上界", "  if year > 2091 {",
    "    return -1", "  }",
  ]
  let code = "  days * 86400 + hour * 3600 + min * 60 + sec"
  let result = scan_finding_guarded(
    code,
    "secs-overflow",
    prev,
    ctx=_ctx(),
    hit_line=code,
    hit_ln=124,
  )
  assert_true(result)
}
