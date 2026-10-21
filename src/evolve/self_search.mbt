/// self_search.mbt —— 调研先行 / 自搜索能力的最小可计算结构（域无关）
///
/// 原则：**凡与目标功能相关的都应先调研**——对外部库/项目/论文「搜索 → 分析 → 评估可移植性后融入」。
/// 本模块把这一方法论固化为纯逻辑的计算步骤：候选清洗、按 (name, source) 判重、
/// 基于可移植动作词的启发式可移植性评估、去重+过滤后有序输出。
///
/// 外部搜索不内置网络：搜索命令由调用方经 `runner` **注入**给 run_external_search，
/// 本模块不硬编码任何盘符/绝对路径。未注入（默认 None）→ 返回 Err「未注入搜索执行器」；
/// 测试用 mock 注入验证成功/失败路径。

///|
/// 搜索候选：一次外部调研产出的「可移植资产」候选。
///
///   - name：候选名（去重键分量一，如库名/论文名）
///   - title：展示标题
///   - source：来源（去重键分量二，如 "crate" / "gh" / "paper" / "blogs"）
///   - mechanism：实现机制/原理描述（供可移植性启发式评估）
///   - portable：是否可移植（assess_portability 输出）
pub struct SearchCandidate {
  name : String
  title : String
  source : String
  mechanism : String
  portable : Bool
}

///|
/// 基础清洗：对五个字段做 trim；portable 依据 mechanism 的启发式（assess_portability）。
/// 去重键 = (trimmed name, trimmed source)。
pub fn analyze_candidate(
  name : String,
  title : String,
  source : String,
  mechanism : String,
) -> SearchCandidate {
  // 先清洗出各字段，再依 mechanism 计算可移植性。结构体固定字段，故构造两份（其一仅用于评估）。
  let pre = SearchCandidate::{
    name: name.trim().to_owned(),
    title: title.trim().to_owned(),
    source: source.trim().to_owned(),
    mechanism: mechanism.trim().to_owned(),
    portable: false,
  }
  SearchCandidate::{
    name: pre.name,
    title: pre.title,
    source: pre.source,
    mechanism: pre.mechanism,
    portable: assess_portability(pre),
  }
}

///|
/// 判重：候选去重键一致（name 与 source 均相等）即视为重复。
pub fn is_duplicate_candidate(a : SearchCandidate, b : SearchCandidate) -> Bool {
  a.name == b.name && a.source == b.source
}

///|
/// 可移植性启发式评估（粗糙但可复现，规则写死在此注释）：
///
///   - mechanism 非空；
///   - 长度合理：长度 ≥ 4（过短视为信息不足，不可移植）；
///   - 含可移植性动作词（大小写不敏感）：port / portable / porting /
///     adapt / wrapper / wrap / reuse / extract / portability / 移植 / 封装 / 复用 /
///     embed / integrate / conforms / compat / decouple；
///
/// 满足全部三条 → true；否则 false。该评估是**计算**而非 LLM 自评，供 distill 过滤硬门槛。
pub fn assess_portability(c : SearchCandidate) -> Bool {
  let m = c.mechanism
  if m.length() < 4 {
    return false
  }
  let words : Array[String] = [
    "port", "portable", "porting", "portability", "adapt", "wrapper", "wrap", "reuse",
    "extract", "embed", "integrate", "conforms", "compat", "decouple", "移植",
    "封装", "复用",
  ]
  for w in words {
    if contains_ci(m, w) {
      return true
    }
  }
  false
}

///|
/// 蒸馏：去重（同 name+source 只留首个）+ 只保留 portable 的 + 按 source 有序输出。
/// 「输出有序」依 source 字符串升序（字典序）排列，稳定（同 source 保持原始先后）。
pub fn distill_candidates(
  cands : Array[SearchCandidate],
) -> Array[SearchCandidate] {
  let unique : Array[SearchCandidate] = []
  for c in cands {
    if !unique.any(fn(u) { is_duplicate_candidate(u, c) }) {
      unique.push(c)
    }
  }
  let portable : Array[SearchCandidate] = []
  for c in unique {
    if c.portable {
      portable.push(c)
    }
  }
  // 插入排序：按 source 升序，稳定。
  for i = 1; i < portable.length(); i = i + 1 {
    let key = portable[i]
    let mut j = i
    while j > 0 && portable[j - 1].source > key.source {
      portable[j] = portable[j - 1]
      j = j - 1
    }
    portable[j] = key
  }
  portable
}

///|
/// 经注入命令执行外部搜索，返回原始文本（成功 Ok / 失败 Err）。
///
/// 不内置网络、不硬编码路径；搜索执行器由调用方通过 **注入参数** `runner` 传入
/// （供上层接入，测试用 mock 注入）。未注入（默认 None）→ Err「未注入搜索执行器」。
pub fn run_external_search(
  cmd : String,
  args : Array[String],
  runner? : ((String, Array[String]) -> Result[String, String])? = None,
) -> Result[String, String] {
  match runner {
    Some(f) => f(cmd, args)
    None => Err("self_search: 未注入搜索执行器，跳过外部搜索")
  }
}

///|
/// 大小写不敏感的包含判断（不依赖具体 core 大小写 API，保证确定性）。
fn contains_ci(hay : String, needle : String) -> Bool {
  if needle.length() == 0 {
    return true
  }
  if hay.length() < needle.length() {
    return false
  }
  let mut start = 0
  while start + needle.length() <= hay.length() {
    if has_match_ci(hay, start, needle) {
      return true
    }
    start = start + 1
  }
  false
}

///|
/// ASCII 大写码点转小写（非大写码点原样返回）。String 索引产出 UInt16 码点。
fn lower_code(c : UInt16) -> UInt16 {
  if c >= 65 && c <= 90 {
    c + 32
  } else {
    c
  }
}

///|
/// 单码点大小写不敏感比较（ASCII 域内有效；中文无大小写，恒等）。
fn char_eq_ci(a : UInt16, b : UInt16) -> Bool {
  lower_code(a) == lower_code(b)
}

///|
/// hay 从 start 起是否与 needle 逐码点（大小写不敏感）匹配。
fn has_match_ci(hay : String, start : Int, needle : String) -> Bool {
  let mut k = 0
  while k < needle.length() {
    if !char_eq_ci(hay[start + k], needle[k]) {
      return false
    }
    k = k + 1
  }
  true
}
