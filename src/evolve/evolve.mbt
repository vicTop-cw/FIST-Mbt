/// evolve.mbt —— DGM 档案库核心（域无关实现）
///
/// 移植自 dna_forge/archive.py（原 Python，见评估文档），用 MoonBit 重写核心机制，
/// 去掉 DNA 领域绑定（SEED/TASK_BANK/编码层），只保留通用的档案库算法：
///
///   - Artifact：档案库中的一个产物（= 语言/代码/设计的一个版本）
///   - Archive：保留【所有】通过门槛的产物（含低分，故意不淘汰）+ 谱系
///   - sample_parent：加权采样（性能加权 × 子代越少越该探索，等价 p ∝ s·h）
///   - is_duplicate：粗粒度查重（防 agent 无限重做同一事）
///   - novelty：相对档案库的新颖度（防收敛到单一路线）
///   - lineage：谱系回溯（垫脚石链，最优 agent 常经过性能下降的中间节点）
///
/// 评分采用注入式函数（域无关，可对接 Omega gate / run_check），绝不让 LLM 自评。

///|
/// 档案库中的一个产物。
pub struct Artifact {
  id : String
  parent_id : String?
  goal : String // 这一轮想解决的问题
  note : String // 设计意图（检索 key / novelty 用）
  code : String // 实现
  score : Double // 可计算评分 [0,1]
  parts : Map[String, Double] // 评分分项明细（域选择）
  children : Int // 已产生的可用子代数（采样新颖性）
  created_at : String // 时间戳
}

///|
/// 档案库（进程内 Map 存储，持久化由调用方决定）。
pub struct Archive {
  items : Map[String, Artifact]
  path : String
}

///|
/// 新建档案库。
pub fn Archive::new(path : String) -> Archive {
  { items: Map([]), path, }
}

///|
/// 产物总数。
pub fn Archive::len(self : Archive) -> Int {
  self.items.size()
}

///|
/// 是否为空档案库。
pub fn Archive::is_empty(self : Archive) -> Bool {
  self.items.is_empty()
}

///|
/// 按 id 取产物。
pub fn Archive::get(self : Archive, id : String) -> Artifact? {
  self.items.get(id)
}

///|
/// 全部产物（值数组）。
pub fn Archive::all(self : Archive) -> Array[Artifact] {
  let out : Array[Artifact] = []
  for (_, a) in self.items {
    out.push(a)
  }
  out
}

///|
/// 添加产物。若 parent 已在库中，累加其 children 计数。
/// 重复添加同一 id（覆盖已有记录）时不再重复累加父节点 children，避免计数虚高。
pub fn Archive::add(self : Archive, a : Artifact) -> Unit {
  // 先查重：若 id 已存在则视为更新既有记录，不重复增加父节点子代数
  let is_new = self.items.get(a.id) is None
  if is_new {
    match a.parent_id {
      Some(pid) =>
        match self.items.get(pid) {
          Some(p) => {
            let bumped = Artifact::with_children(p, p.children + 1)
            self.items.set(pid, bumped)
          }
          None => ()
        }
      None => ()
    }
  }
  self.items.set(a.id, a)
}

///|
/// 返回 children 字段更新后的副本（MoonBit struct 不可变，用于累加子代数）。
pub fn Artifact::with_children(a : Artifact, n : Int) -> Artifact {
  {
    id: a.id,
    parent_id: a.parent_id,
    goal: a.goal,
    note: a.note,
    code: a.code,
    score: a.score,
    parts: a.parts,
    children: n,
    created_at: a.created_at,
  }
}

///|
/// 构造一个产物（供外部包创建后加入档案库）。
pub fn Artifact::create(
  id~ : String,
  parent_id~ : String?,
  goal~ : String,
  note~ : String,
  code~ : String,
  score~ : Double,
  parts~ : Map[String, Double],
  created_at~ : String,
) -> Artifact {
  { id, parent_id, goal, note, code, score, parts, children: 0, created_at, }
}

// ---------------------------------------------------------------------------
// 采样（等价 DGM p ∝ s_i · h_i）
//   性能权重 s（父代分数，越高越可能被选作父代，但非垄断）
//   新颖性权重 h = 1/(1+children)（子代越少越该被探索）
// 所有产物保留非零权重 —— 任何路径都不会被永久封死。
// ---------------------------------------------------------------------------

///|
/// 加权滚轮采样：p_i ∝ s_i · h_i，返回选中产物（空库 None）。
/// rand 注入 `() -> Double`（[0,1) 均匀），保证可测试。
pub fn Archive::sample_parent(
  self : Archive,
  lam? : Double = 8.0,
  a0? : Double = 0.4,
  rand~ : () -> Double,
) -> Artifact? {
  let cands = self.all()
  if cands.is_empty() {
    return None
  }
  let weights : Array[Double] = []
  for a in cands {
    // 性能分量：用 saturating 映射 `score / (score + a0)` -> [0,1)，单调且无需 exp。
    // score 越大 -> 权重越高；score=0 时权重为 0（该产物仅靠 novelty 分量也不会为零，
    // 但为保留“零分也有非零概率”，下限 0.01）。
    let s_raw = if a.score > 0.0 { a.score / (a.score + a0) } else { 0.0 }
    let s = s_raw.max(0.001)
    let h = 1.0 / (1.0 + a.children.to_double())
    weights.push(s * h)
  }
  let total = weights.fold_left(init=0.0, fn(acc, w) { acc + w })
  if total <= 0.0 {
    return Some(cands[0])
  }
  // 轮盘选择：r 在 [0,total)；r -= 权重，命中即返回。
  // 用 r < 0（不含等号）保证 rand 返回 0（贴在左端）时不会错误命中第一个元素之前。
  let mut r = rand() * total
  for i = 0; i < cands.length(); i = i + 1 {
    r = r - weights[i]
    if r < 0.0 {
      return Some(cands[i])
    }
  }
  Some(cands[cands.length() - 1])
}

///|
/// 最高分产物（空库 None）。
pub fn Archive::best(self : Archive) -> Artifact? {
  if self.is_empty() {
    return None
  }
  let mut b = self.all()[0]
  for a in self.all() {
    if a.score > b.score {
      b = a
    }
  }
  Some(b)
}

// ---------------------------------------------------------------------------
// 查重与新颖性（粗粒度 token 重合，Voyager 必修课）
// ---------------------------------------------------------------------------

///|
/// 切词单真源（BUG-25 标定后重写）：ASCII 词 + CJK 单字 + CJK 相邻二字组，去重。
///
/// 旧口径是"可见字符集"——对中文等价于逐字拆散，`熔断器三态` 与 `三态熔断器` 同分，
/// 而真正的病灶是**改写型子任务**：子任务合法地换一套词（"依赖图恒空"→"增量编译链修复"），
/// 字符集重合因此趋 0，绝对阈值下 15/15 全判漂移（实测见 scripts/calibrate_goal_drift.py）。
/// 新口径加 ASCII 词与 CJK 二字组，让"同词/同词组"才计分：
/// 全量父子对（1222 条）假阳性 16.9%→1.9%，随机错配对照仍 81.3% 判可疑。
/// 口径必须与 scripts/calibrate_goal_drift.py 逐字对齐——数字不是抄来的，是那条命令跑出来的。
pub fn tokens(s : String) -> Array[String] {
  let seen : Map[String, Bool] = Map([])
  let out : Array[String] = []
  let chars = s.to_lower().to_array()
  let n = chars.length()
  let mut i = 0
  while i < n {
    let c = chars[i]
    if is_cjk(c) {
      // CJK 段：先扫到段边界，再发单字与相邻二字组（"熔断器"→ 熔/断/器/熔断/断器）
      let mut j = i
      while j < n && is_cjk(chars[j]) {
        j = j + 1
      }
      let mut k = i
      while k < j {
        tok_add(seen, out, chars[k].to_string())
        if k + 1 < j {
          tok_add(seen, out, chars[k].to_string() + chars[k + 1].to_string())
        }
        k = k + 1
      }
      i = j
    } else if is_word_char(c) {
      let mut j = i
      let mut w = ""
      while j < n && is_word_char(chars[j]) {
        w = w + chars[j].to_string()
        j = j + 1
      }
      tok_add(seen, out, w)
      i = j
    } else {
      i = i + 1
    }
  }
  out
}

///|
/// 去重后入表（Map/Array 是可变值类型，无需 mut 绑定；见 cb_json 同形写法）。
fn tok_add(seen : Map[String, Bool], out : Array[String], k : String) -> Unit {
  if k != "" && seen.get(k).is_none() {
    seen.set(k, true)
    out.push(k)
  }
}

///|
/// CJK 统一表意文字（含扩展 A）——"按字成词"的前提只对这些字符成立。
fn is_cjk(c : Char) -> Bool {
  let cp = c.to_int()
  (cp >= 0x4e00 && cp <= 0x9fff) || (cp >= 0x3400 && cp <= 0x4dbf)
}

///|
/// ASCII 词字符：字母/数字/下划线/连字符（与标定脚本的 `[a-z0-9_-]+` 同集）。
fn is_word_char(c : Char) -> Bool {
  let cp = c.to_int()
  let alpha = cp >= 'a'.to_int() && cp <= 'z'.to_int()
  let digit = cp >= '0'.to_int() && cp <= '9'.to_int()
  alpha || digit || cp == '_'.to_int() || cp == '-'.to_int()
}

///|
/// 可见字符去重集（旧 `tokens` 口径，保留给**兄弟冗余**用）。
/// 兄弟重复的典型形状是"词序换位"（`数据采集模块` ↔ `采集数据模块`），
/// 二字组口径会把它们放行（jaccard 0.556），字符集恰好对词序不敏感（1.0）；
/// 实测这个分量在真实非模板家族上不额外增加误报（两种口径同为 34.8%，见标定脚本）。
pub fn unigrams(s : String) -> Array[String] {
  let seen : Map[String, Bool] = Map([])
  let out : Array[String] = []
  for c in s.to_lower() {
    let ch = c.to_string()
    if ch.trim() != "" && seen.get(ch).is_none() {
      seen.set(ch, true)
      out.push(ch)
    }
  }
  out
}

///|
/// 覆盖率 |a∩b| / |a|——**非对称**，a 是基准（根目标），b 是待测文本。
/// Jaccard 用并集做分母，长文本天然被稀释：子任务多写 200 字模板就"更像漂移"，
/// 那是长度惩罚不是目标偏离。coverage 只问"根目标里的词还在不在"，多写不罚。
pub fn coverage(a : Array[String], b : Array[String]) -> Double {
  if a.is_empty() {
    return 0.0
  }
  let in_b : Map[String, Bool] = Map([])
  for w in b {
    in_b.set(w, true)
  }
  let mut inter = 0
  // a 已由 tokens 去重，这里不再二次去重（重复元素会把分母外的分子抬高）
  for w in a {
    if in_b.contains(w) {
      inter = inter + 1
    }
  }
  inter.to_double() / a.length().to_double()
}

///|
/// 两个 token 数组的 Jaccard 相似度 |a∩b| / |a∪b|。
pub fn jaccard(a : Array[String], b : Array[String]) -> Double {
  if a.is_empty() && b.is_empty() {
    return 0.0
  }
  let in_a : Map[String, Bool] = Map([])
  for w in a {
    in_a.set(w, true)
  }
  let in_b : Map[String, Bool] = Map([])
  for w in b {
    in_b.set(w, true)
  }
  let mut inter = 0
  for (w, _) in in_a {
    if in_b.contains(w) {
      inter = inter + 1
    }
  }
  let union = in_a.size() + in_b.size() - inter
  if union == 0 {
    0.0
  } else {
    inter.to_double() / union.to_double()
  }
}

///|
/// 查重：某个 goal 是否与库中已有产物高度相似（Jaccard >= threshold）。
pub fn Archive::is_duplicate(
  self : Archive,
  goal : String,
  threshold? : Double = 0.88,
) -> Bool {
  let g = tokens(goal)
  if g.is_empty() {
    return false
  }
  for (_, a) in self.items {
    let t = tokens(a.goal)
    if not(t.is_empty()) {
      if jaccard(g, t) >= threshold {
        return true
      }
    }
  }
  false
}

///|
/// 新颖性：1 - 与库中 note 的最大 Jaccard 重合。值越高越没见过。
pub fn Archive::novelty(self : Archive, note : String) -> Double {
  let n = tokens(note)
  if n.is_empty() || self.is_empty() {
    return 1.0
  }
  let mut max_sim = 0.0
  for (_, a) in self.items {
    let t = tokens(a.note)
    if not(t.is_empty()) {
      let j = jaccard(n, t)
      if j > max_sim {
        max_sim = j
      }
    }
  }
  (1.0 - max_sim).clamp(min=0.0, max=1.0)
}

// ---------------------------------------------------------------------------
// 摘要 / 低分地图 / 谱系
// ---------------------------------------------------------------------------

///|
/// 摘要（高分优先）：给课程生成器看的 top-N。
pub fn Archive::summaries(self : Archive, limit? : Int = 12) -> Array[String] {
  let sorted = self.all()
  sorted.sort_by(fn(a, b) {
    if a.score != b.score {
      if a.score > b.score {
        -1
      } else {
        1
      }
    } else {
      b.created_at.compare(a.created_at)
    }
  })
  let n = if sorted.length() < limit { sorted.length() } else { limit }
  let out : Array[String] = []
  for i = 0; i < n; i = i + 1 {
    out.push(evolve_summary_line(sorted[i]))
  }
  out
}

///|
/// 低分产物（“此路不通”地图）：喂回给课程生成器绕开。
pub fn Archive::dead_ends(self : Archive, limit? : Int = 8) -> Array[String] {
  let sorted = self.all()
  sorted.sort_by(fn(a, b) {
    if a.score != b.score {
      if a.score < b.score {
        -1
      } else {
        1
      }
    } else {
      0
    }
  })
  let n = if sorted.length() < limit { sorted.length() } else { limit }
  let out : Array[String] = []
  for i = 0; i < n; i = i + 1 {
    out.push(evolve_summary_line(sorted[i]))
  }
  out
}

///|
/// 单行摘要（id 前 8 位 + score + goal）。
fn evolve_summary_line(a : Artifact) -> String {
  let short = if a.id.length() > 8 {
    a.id.substring(start=0, end=8)
  } else {
    a.id
  }
  let sc = (a.score * 1000.0).to_int().to_double() / 1000.0
  "[\{short} score=\{sc} ] \{a.goal}"
}

///|
/// 从某产物沿 parent 链回溯谱系（最多 depth 层），返回 (id, score, goal) 数组。
pub fn Archive::lineage(
  self : Archive,
  from : String,
  depth? : Int = 12,
) -> Array[(String, Double, String)] {
  let out : Array[(String, Double, String)] = []
  let mut cur : String? = Some(from)
  let mut d = 0
  while d < depth {
    match cur {
      None => break
      Some(id) =>
        match self.get(id) {
          Some(a) => {
            out.push((a.id, a.score, a.goal))
            cur = a.parent_id
            d = d + 1
          }
          None => break
        }
    }
  }
  out
}

///|
/// 产出 JSON（供 MCP / 展示）。
pub fn Artifact::to_json(self : Artifact) -> Json {
  let m : Map[String, Json] = Map([])
  m.set("id", Json::string(self.id))
  m.set(
    "parent_id",
    match self.parent_id {
      Some(p) => Json::string(p)
      None => Json::null()
    },
  )
  m.set("goal", Json::string(self.goal))
  m.set("note", Json::string(self.note))
  m.set("code", Json::string(self.code))
  m.set("score", Json::number(self.score))
  m.set("children", Json::number(self.children.to_double()))
  m.set("created_at", Json::string(self.created_at))
  let pm : Map[String, Json] = Map([])
  for (k, v) in self.parts {
    pm.set(k, Json::number(v))
  }
  m.set("parts", Json::object(pm))
  Json::object(m)
}

///|
/// 从 JSON 反序列化 Artifact。
pub fn Artifact::from_json(j : Json) -> Artifact {
  let obj = match j {
    Object(m) => m
    _ => Map([])
  }
  let str = fn(k : String) -> String {
    match obj.get(k) {
      Some(String(s)) => s
      _ => ""
    }
  }
  let score = match obj.get("score") {
    Some(Number(n, ..)) => n
    _ => 0.0
  }
  let parent = match obj.get("parent_id") {
    Some(String(p)) => if p == "" { None } else { Some(p) }
    Some(Null) => None
    _ => None
  }
  // 反序列化 children（采样新颖性权重），缺失回退 0
  let children = match obj.get("children") {
    Some(Number(n, ..)) => n.to_int()
    _ => 0
  }
  // 反序列化 parts（评分分项），缺失回退空 Map
  let parts : Map[String, Double] = Map([])
  match obj.get("parts") {
    Some(Object(pm)) =>
      for (k, v) in pm.iter2() {
        match v {
          Number(n, ..) => parts.set(k, n)
          _ => ()
        }
      }
    _ => ()
  }
  {
    id: str("id"),
    parent_id: parent,
    goal: str("goal"),
    note: str("note"),
    code: str("code"),
    score,
    parts,
    children,
    created_at: str("created_at"),
  }
}
