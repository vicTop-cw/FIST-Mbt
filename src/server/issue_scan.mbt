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
  ]
  r
}

///|
/// 逐行匹配一条规则，返回命中（行号从 1 起）。
fn scan_match_lines(
  content : String,
  rule : ScanRule,
  file : String,
) -> Array[ScanFinding] {
  let out : Array[ScanFinding] = []
  let mut ln = 1
  for line in content.split("\n") {
    let mut hit = false
    for needle in rule.pattern {
      if line.contains(needle) {
        hit = true
        break
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
fn scan_file(path : String, rules : Array[ScanRule]) -> Array[ScanFinding] {
  let content = match mem_read(path) {
    None => return []
    Some(c) => c
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
