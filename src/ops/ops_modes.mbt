/// ops_modes.mbt —— 自驱编程 7 种开发模式注册表（R117）
///
/// 纯计算、零依赖。模式是每轮"做什么"的语义约束，
/// 与 round_tick 的"要不要继续"（L1-L4 生命周期判定）正交。
///
/// 单真源：三引擎（watchdog/pipeline/selfdrive）只通过本模块
/// 解析 mode 字符串 → enum → 约束 → 模板路径，不自行硬编码。
///
/// 第 7 种 `explore`（探索模式）是**唯一不亲自开发**的模式：它只做
/// "量目标复杂度 → 从其余 6 个单模式里选一个 → 跑它"，适当情况下并行跑
/// 几个模式，前提是它们申报的文件作用域两两不相交（见 explore_plan）。

// ---------------------------------------------------------------------------
// 7 种模式枚举
// ---------------------------------------------------------------------------

///|
/// 7 种自驱编程开发模式。枚举构造函数公开，供黑盒测试与跨包匹配。
pub enum PipelineMode {
  Advance // 默认：持续开发新功能
  Polish // 打磨：完善已有功能，不加新功能
  Verify // 验证：API 枚举 + 完备性 + 文档自洽
  BugFind // 寻虫：issue_scan + open-code-review + 边界语料
  FixAndMerge // 修复与合并：修 issues + 合并分支
  Tidy // 清整：项目打扫
  Explore // 探索：不自已开发，按目标复杂度自选单模式（可不冲突时并行多个）
}

// ---------------------------------------------------------------------------
// 枚举 ↔ 字符串 互转
// ---------------------------------------------------------------------------

///|
/// 默认模式 = Advance
pub fn default_mode() -> PipelineMode {
  Advance
}

///|
/// mode 字符串 → PipelineMode。非法值返回 Err（区分大小写，trim 后匹配）。
pub fn parse_mode(s : String) -> Result[PipelineMode, String] {
  let t = s.trim().to_string()
  match t {
    "advance" => Ok(Advance)
    "polish" => Ok(Polish)
    "verify" => Ok(Verify)
    "bugfind" => Ok(BugFind)
    "fix_and_merge" => Ok(FixAndMerge)
    "tidy" => Ok(Tidy)
    "explore" => Ok(Explore)
    _ =>
      Err(
        "未知模式: " +
        t +
        ", 可选: advance|polish|verify|bugfind|fix_and_merge|tidy|explore",
      )
  }
}

///|
/// 模式简名（用于 [mode:xxx] 标签 / Json 字段）。
pub fn mode_short(m : PipelineMode) -> String {
  match m {
    Advance => "advance"
    Polish => "polish"
    Verify => "verify"
    BugFind => "bugfind"
    FixAndMerge => "fix_and_merge"
    Tidy => "tidy"
    Explore => "explore"
  }
}

///|
/// 模式完整中文名（用于展示）。
fn mode_display_name(mode_str : String) -> String {
  match mode_str {
    "advance" => "持续开发新功能"
    "polish" => "打磨完善（不加新功能）"
    "verify" => "API 枚举与完备性验证"
    "bugfind" => "寻虫：issue_scan + 边界语料"
    "fix_and_merge" => "修复 issues + 合并分支"
    "tidy" => "项目打扫清整"
    "explore" => "探索：按复杂度自选模式"
    _ => "未知模式"
  }
}

// ---------------------------------------------------------------------------
// 模板路径
// ---------------------------------------------------------------------------

///|
/// 模式 → 模板文件相对路径。
/// 仅字符串拼接，不检查路径存在性——由调用方自行决定"不存在时是报错还是降级"。
pub fn mode_template_path(mode : String) -> String {
  "templates/pipeline_mode_" + mode + ".md"
}

// ---------------------------------------------------------------------------
// 模式约束（Json 返回，供 MCP mode_list 工具直接用）
// ---------------------------------------------------------------------------

///|
/// 模式约束（Json 返回）。键固定，值为布尔。未知模式返回空约束 Map。
pub fn mode_constraints(mode : String) -> Json {
  let m : Map[String, Json] = Map([])
  match mode {
    "advance" => {
      m.set("forbid_new_features", Json::boolean(false))
      m.set("require_issue_scan", Json::boolean(false))
      m.set("require_github_token", Json::boolean(false))
    }
    "polish" => {
      m.set("forbid_new_features", Json::boolean(true))
      m.set("require_issue_scan", Json::boolean(false))
      m.set("require_github_token", Json::boolean(false))
    }
    "verify" => {
      m.set("forbid_new_features", Json::boolean(false))
      m.set("require_issue_scan", Json::boolean(false))
      m.set("require_api_enum", Json::boolean(true))
      m.set("require_doc_check", Json::boolean(true))
    }
    "bugfind" => {
      m.set("forbid_new_features", Json::boolean(false))
      m.set("require_issue_scan", Json::boolean(true))
      m.set("require_test_corpus", Json::boolean(true))
      m.set("require_ocr", Json::boolean(true))
    }
    "fix_and_merge" => {
      m.set("forbid_new_features", Json::boolean(false))
      m.set("require_issue_scan", Json::boolean(false))
      m.set("require_github_token", Json::boolean(true))
    }
    "tidy" => {
      m.set("forbid_new_code", Json::boolean(true))
      m.set("require_issue_scan", Json::boolean(false))
      m.set("require_github_token", Json::boolean(false))
    }
    // 探索模式：本身不写代码，所以"禁不禁新功能"取决于它选中的那个模式
    // （选中 advance 就允许，选中 polish/tidy 就不允许）——这里如实给 false，
    // 真正的门槛挂在下面三把专用门上：必须先打分、并行必须申报作用域且互不相交。
    "explore" => {
      m.set("forbid_new_features", Json::boolean(false))
      m.set("require_issue_scan", Json::boolean(false))
      m.set("require_complexity_scoring", Json::boolean(true))
      m.set("allow_parallel_modes", Json::boolean(true))
      m.set("require_disjoint_files", Json::boolean(true))
    }
    _ => ()
  }
  Json::object(m)
}

///|
/// forbidden_tools（某些 mode 显式禁用的工具/任务名；空数组表示无约束）。
fn mode_forbidden_tools(mode_str : String) -> Array[String] {
  match mode_str {
    // BUG-37：旧名单写的是**不存在的工具名**（publish_new_feature_task / issue_scan_with_generate_new
    // 在 server.mbt 注册表里计数为 0），按名单拦截的下游永远匹配不到，红线只剩提示词文字。
    // 换成真实注册名：这三个都能创建根任务，正是"打磨/整理不该扩展功能边界"要挡的入口。
    "polish" => ["publish", "publish_parallel", "dag_publish"]
    "tidy" => ["publish", "publish_parallel", "dag_publish"]
    // explore 返回 []：它的正业就是"选完模式后把该模式的活儿派出去"，
    // 而派发的唯一出口正是 publish/publish_parallel/dag_publish（polish/tidy 禁它们，
    // 是因为那两个模式不该**扩展**功能边界；explore 扩展与否由它选中的模式自己的
    // forbidden_tools 决定——选中 polish 时那三个工具照样在 polish 的名单里被禁）。
    // 这里若照抄禁单，会掐断本模式唯一的产出口，红线变成"什么都不许做"，不自洽。
    "explore" => []
    _ => []
  }
}

// ---------------------------------------------------------------------------
// all_modes：模式完整描述数组
// ---------------------------------------------------------------------------

///|
/// 7 种完整模式描述数组（供 MCP mode_list 工具直接返回）。
/// 每个元素: { mode, name, description, constraints, template_path, forbidden_tools }。
pub fn all_modes() -> Array[Json] {
  let names = [
    "advance", "polish", "verify", "bugfind", "fix_and_merge", "tidy", "explore",
  ]
  let descs = [
    "默认模式：持续推进新功能开发。phase 流转 Creating→Pending→Running→Closed。",
    "打磨模式：完善已有功能、重构、性能调优。禁止发布新功能任务。",
    "验证模式：枚举 API、检查完备性、文档自洽。phase 增加 Enumerate/Verify。",
    "寻虫模式：issue_scan 规则驱动扫描 + 边界语料构造 + open-code-review。",
    "修复与合并模式：从 issue 池拉取、派发修复、PR 合并。需要 GitHub token。",
    "清整模式：项目打扫——清理 dead code、归档过期文件、清理依赖。禁止新增代码。",
    "探索模式：本身不开发——先量目标复杂度（0..5），再从其余 6 个单模式里选一个跑；" +
    "适当情况下可并行几个模式，前提是每个模式申报的文件作用域两两不相交" +
    "（reserve_scope 绑作用域 + conflicts_check 放行），任一重叠即退回单模式串行。",
  ]
  let out : Array[Json] = []
  for i = 0; i < names.length(); i = i + 1 {
    let m : Map[String, Json] = Map([])
    let name = names[i]
    m.set("mode", Json::string(name))
    m.set("name", Json::string(mode_display_name(name)))
    m.set("description", Json::string(descs[i]))
    m.set("constraints", mode_constraints(name))
    m.set("template_path", Json::string(mode_template_path(name)))
    let ft : Array[Json] = mode_forbidden_tools(name).map(fn(s) {
      Json::string(s)
    })
    m.set("forbidden_tools", Json::array(ft))
    out.push(Json::object(m))
  }
  out
}

// ---------------------------------------------------------------------------
// 探索模式（explore）：量复杂度 → 选单模式 → 判并行可行性
// 纯计算：不读库、不看时钟、无随机、无副作用。
// ---------------------------------------------------------------------------

///|
/// 复杂度 0..5 → 单模式（**越界夹紧，不报错**）。档表：
///
/// | 复杂度 | 选中模式 | 为什么是它（按"本轮被允许动多大 footprint"单调递增排）|
/// |---|---|---|
/// | ≤0 | `tidy` | 目标本身没活儿：打扫/归档/清 dead code，禁新增代码 |
/// | 1 | `verify` | 只差"说的和做的是否一致"：只读枚举 API + 文档自洽，零写源码 |
/// | 2 | `bugfind` | 只读但要产出工作队列：边界语料 + issue_scan，把未知风险变实锤 |
/// | 3 | `polish` | 要动已有代码但不扩边界：重构/补强，禁 publish 新功能 |
/// | 4 | `fix_and_merge` | 动代码 + 动分支 + 要外部凭证（GitHub token），不可逆面最大 |
/// | ≥5 | `advance` | 唯一"扩大功能边界"的档：已有功能里长不出答案，才允许加新功能 |
///
/// 与业主给的示意档表（0-1 tidy/verify、2 bugfind、3 polish/fix_and_merge、4+ advance）
/// 的唯一偏离：`fix_and_merge` 从 3 挪到 4、`advance` 独占 5。两条理由：
/// ① fix_and_merge 是 6 个单模式里唯一"要外部 token 且改远端分支"的，压在 4 档才谈得上
///    "按复杂度授权"；② 若 4 档就能选中 advance，则 4/5 两档同解、六档退化成五档可达，
///    fix_and_merge 永远选不到（选择器名义上覆盖 6 个模式，实际只覆盖 5 个）。
/// 要回到示意档表：把下面 `FixAndMerge` 与 `Advance` 两个分支对调即可，其余不动。
pub fn select_mode_by_complexity(complexity : Int) -> PipelineMode {
  if complexity <= 0 {
    Tidy
  } else if complexity == 1 {
    Verify
  } else if complexity == 2 {
    BugFind
  } else if complexity == 3 {
    Polish
  } else if complexity == 4 {
    FixAndMerge
  } else {
    Advance
  }
}

///|
/// LADDER 难度档 → 复杂度整数区间。**区间边界不自立口径**：逐字对应
/// `src/decompose/decompose.mbt` 的 `difficulty_label_from(d)` 两个阈值
/// （易: d<=2.0 / 中: 2.0<d<=3.5 / 难: d>3.5）换算到 0..5 整数档 =
/// 易 0..2、中 3、难 4..5。这里没有 import `@decompose`（src/ops 的 moon.pkg
/// 不依赖 src/decompose，加依赖要改包声明，越出本次边界），改为
/// "档表 + 白盒配对锁"复用同一口径：`ops_modes_wbtest` 里对 0..5 每个整数
/// 都断言"它落在 difficulty_label_from 自己算出的那一档的区间内"，
/// 改任一侧即红。未知档（含空串）→ (0, 5) = 不夹，让信号分原样通过。
pub fn complexity_band_of_tier(tier : String) -> (Int, Int) {
  if tier.contains("易") {
    (0, 2)
  } else if tier.contains("中") {
    (3, 3)
  } else if tier.contains("难") {
    (4, 5)
  } else {
    (0, 5)
  }
}

///|
fn clamp_int(x : Int, lo : Int, hi : Int) -> Int {
  if x < lo {
    lo
  } else if x > hi {
    hi
  } else {
    x
  }
}

///|
fn in_list(xs : Array[String], x : String) -> Bool {
  let mut found = false
  for y in xs {
    if y == x {
      found = true
    }
  }
  found
}

///|
fn join_terms(ts : Array[String]) -> String {
  let mut s = ""
  for t in ts {
    s = if s == "" { t } else { s + "," + t }
  }
  s
}

///|
/// 在已小写化的文本里命中的关键词（保持传入顺序，去重由调用方保证）。
fn keyword_hits(lower : String, keys : Array[String]) -> Array[String] {
  let out : Array[String] = []
  for k in keys {
    if lower.contains(k) {
      out.push(k)
    }
  }
  out
}

///|
/// 复杂度评估明细：返回 (最终复杂度 0..5, 任务自带的 LADDER 声明档, 逐项依据)。
/// 依据数组与分数**同源**——estimate_complexity 与 explore_plan 的 basis 都读它，
/// 不会出现"分数一套说法、basis 另一套说法"。
fn complexity_assess(
  description : String,
  subtask_count : Int,
) -> (Int, String, Array[String]) {
  let chars = description.to_array().length()
  let lower = description.to_lower()
  let reasons : Array[String] = []
  let mut score = 0
  // ① 描述长度（码点，中文不按字节虚高）：写得越长，目标牵连越广
  let len_pts = if chars >= 600 { 2 } else if chars >= 200 { 1 } else { 0 }
  score = score + len_pts
  reasons.push(
    "描述 " + chars.to_string() + " 码点→+" + len_pts.to_string(),
  )
  // ② 已有子任务数：拆得出多片 = 协调与依赖成本已经存在
  let n = if subtask_count < 0 { 0 } else { subtask_count }
  let sub_pts = if n >= 8 { 2 } else if n >= 3 { 1 } else { 0 }
  score = score + sub_pts
  reasons.push("子任务 " + n.to_string() + " 个→+" + sub_pts.to_string())
  // ③ 缺陷词：已有破损摆在那儿，至少要走"发现/修复"链
  let defect = keyword_hits(lower, [
    "bug", "缺陷", "错误", "崩溃", "异常", "panic", "打回", "失败",
  ])
  if defect.length() > 0 {
    score = score + 1
    reasons.push("提及缺陷(" + join_terms(defect) + ")→+1")
  }
  // ④ 测试词：要动语料/回归面，改动有验证成本
  let tsts = keyword_hits(lower, [
    "测试", "test", "用例", "覆盖", "回归",
  ])
  if tsts.length() > 0 {
    score = score + 1
    reasons.push("提及测试(" + join_terms(tsts) + ")→+1")
  }
  // ⑤ 接口词：动的是对外契约，改错会漏到调用方
  let apis = keyword_hits(lower, [
    "api", "接口", "协议", "schema", "endpoint", "工具",
  ])
  if apis.length() > 0 {
    score = score + 1
    reasons.push("提及接口(" + join_terms(apis) + ")→+1")
  }
  // ⑥ 扩边界词：新功能/跨模块/合并——只有 advance 档承接得住
  let scope = keyword_hits(lower, [
    "新功能", "新增", "feature", "跨模块", "多模块", "重构", "迁移",
    "集成", "架构", "合并",
  ])
  if scope.length() > 0 {
    score = score + 1
    reasons.push("提及扩边界(" + join_terms(scope) + ")→+1")
  }
  // ⑦ 文档词：**刻意不加分**——补文档是降档活儿，加分会把"改 README"估成高复杂度；
  //    但也不删这条信号，写进依据让调用方看得见"看过、判定为 0"。
  let docs = keyword_hits(lower, ["文档", "doc", "readme", "注释", "说明"])
  if docs.length() > 0 {
    reasons.push(
      "提及文档(" +
      join_terms(docs) +
      ")→+0（文档不构成复杂度）",
    )
  }
  // ⑧ 复用单一难度口径：任务描述里若带 task_plan_deep 写的 LADDER 档，
  //    它就是**权威难度**（那是拆解器/校准器给的真实难度），把信号分夹进
  //    该档区间；无档位标记时信号分原样生效。
  let tier = @engine.extract_difficulty(description)
  let raw = clamp_int(score, 0, 5)
  let (lo, hi) = complexity_band_of_tier(tier)
  let final_score = clamp_int(raw, lo, hi)
  if tier == "" {
    reasons.push(
      "无 LADDER 难度档标记→按信号分 " +
      final_score.to_string() +
      "/5",
    )
  } else {
    let band = lo.to_string() + ".." + hi.to_string()
    reasons.push(
      "LADDER 档 '" +
      tier +
      "' 限定区间 " +
      band +
      "（信号分 " +
      raw.to_string() +
      "）→最终 " +
      final_score.to_string() +
      "/5",
    )
  }
  (final_score, tier, reasons)
}

///|
/// 目标复杂度估计（0..5）。只用任务自身的信号（描述长度、子任务数、关键词），
/// 并复用 @engine.extract_difficulty 读到的 LADDER 难度档做夹紧（不另立第二套难度口径）。
/// 纯计算、确定性：同一输入恒得同一档。
pub fn estimate_complexity(description : String, subtask_count : Int) -> Int {
  let (score, _, _) = complexity_assess(description, subtask_count)
  score
}

///|
/// 多个文件作用域**两两相交**的文件名（去重）。空数组 = 两两不相交。
/// 按 trim 后的字面路径比对，不做归一化："./a.mbt" 与 "a.mbt" 视作不同作用域——
/// 归一是调用方的责任（reserve_scope 存的也是原样字符串，两边同口径才对得上）。
pub fn file_scope_conflicts(scopes : Array[Array[String]]) -> Array[String] {
  let out : Array[String] = []
  let n = scopes.length()
  for i = 0; i < n; i = i + 1 {
    for j = i + 1; j < n; j = j + 1 {
      for a in scopes[i] {
        let ka = a.trim().to_string()
        if ka != "" && not(in_list(out, ka)) {
          for b in scopes[j] {
            if ka == b.trim().to_string() {
              out.push(ka)
            }
          }
        }
      }
    }
  }
  out
}

///|
/// 作用域是否两两不相交（file_scope_conflicts 的布尔门面）。
pub fn file_scopes_disjoint(scopes : Array[Array[String]]) -> Bool {
  file_scope_conflicts(scopes).length() == 0
}

///|
/// 探索模式的决策输出（纯计算，**绝不调用 store**）：
/// 输入 = 目标描述 + 已知子任务数 + 想并行跑的模式候选 + 每个候选申报的文件作用域
/// + 调用方从 `reserve_scope`/`conflicts_check` 拿到的放行结论。
/// 输出 = { chosen_mode, complexity, basis, parallel_modes, parallel_allowed,
///          conflict_gate, note, declared_tier, scopes_declared, scopes_disjoint,
///          rejected_candidates }。
///
/// 并行放行的四把门（**全部满足**才 allowed=true，否则退回单模式串行——fail-closed）：
/// ① 候选里除选中模式外还有 ≥1 个可用模式（want_parallel）；
/// ② 每个候选都申报了非空文件作用域，且 files 与候选一一对应（scopes_declared）——
///    没申报就等于无法证明不相交，不放行；
/// ③ 作用域两两不相交（file_scope_conflicts 为空）；
/// ④ scopes_cleared=true —— 调用方确认 `reserve_scope` 每个作用域都拿到 reserved/
///    renewed/taken_over、且认领前 `conflicts_check` 都返回 ok。两两不相交只保证
///    "本轮候选之间不打架"，挡不住"别的 agent 早已预订了其中一个文件"，所以这道门
///    不能省。
///
/// 任一门失败：`parallel_modes` **只含 chosen_mode**（把不安全的风扇出面积回收到 1），
/// 失败原因写在 `note` 里；候选里的非法模式名与 `explore` 自身进 `rejected_candidates`
/// （探索模式不能当并行工作单元，否则"选模式的模式"可以无限递归、一个都不开发）。
pub fn explore_plan(
  description : String,
  subtask_count : Int,
  candidate_modes : Array[String],
  files : Array[Array[String]],
  scopes_cleared : Bool,
) -> Json {
  let (score, tier, reasons) = complexity_assess(description, subtask_count)
  let primary_str = mode_short(select_mode_by_complexity(score))
  // 1) 校验候选：非法名剔出、explore 自身剔出、重名去重（files 按候选下标对齐）
  let mut modes : Array[String] = []
  let mut scopes : Array[Array[String]] = []
  let rejected : Array[String] = []
  for i = 0; i < candidate_modes.length(); i = i + 1 {
    let raw_name = candidate_modes[i].trim().to_string()
    match parse_mode(raw_name) {
      Ok(m) => {
        let s = mode_short(m)
        if s == "explore" {
          rejected.push(raw_name + "：explore 不可作为并行工作单元")
        } else if not(in_list(modes, s)) {
          modes.push(s)
          scopes.push(if i < files.length() { files[i] } else { [] })
        }
      }
      Err(_) => rejected.push(raw_name + "：未知模式")
    }
  }
  // 2) 本轮该跑的选中模式必须在集合头部；候选没提到它时补进去，但它的作用域未知
  //    → 门②自动判不过（fail-closed：连"该跑谁的文件范围"都不知道，谈不上并行）
  if modes.length() == 0 {
    modes.push(primary_str)
    scopes.push([])
    reasons.push("无可用候选→只跑 " + primary_str)
  } else if modes[0] != primary_str {
    let m2 : Array[String] = [primary_str]
    let empty_scope : Array[String] = []
    let s2 : Array[Array[String]] = [empty_scope]
    for s in modes {
      m2.push(s)
    }
    for sc in scopes {
      s2.push(sc)
    }
    modes = m2
    scopes = s2
    reasons.push(
      "候选未含选中模式→头部补 " +
      primary_str +
      "（其作用域未申报）",
    )
  }
  // 3) 四把门
  let want_parallel = modes.length() > 1
  let mut declared = scopes.length() == modes.length()
  for sc in scopes {
    if sc.length() == 0 {
      declared = false
    }
  }
  let conflicts = file_scope_conflicts(scopes)
  let disjoint = conflicts.length() == 0
  let allowed = want_parallel && declared && disjoint && scopes_cleared
  let notes : Array[String] = []
  if not(want_parallel) {
    notes.push(
      "单模式即可：候选集里没有一个可与之并行的模式",
    )
  } else {
    if !declared {
      notes.push(
        "拒并行：有候选模式未申报文件作用域（scope 不完整＝无从证明不相交）",
      )
    }
    if !disjoint {
      notes.push("拒并行：文件作用域重叠 " + join_terms(conflicts))
    }
    if !scopes_cleared {
      notes.push(
        "拒并行：未回传 reserve_scope/conflicts_check 放行结论（scopes_cleared=false）",
      )
    }
    if allowed {
      notes.push(
        "放行并行：" +
        modes.length().to_string() +
        " 个模式作用域两两不相交且预订/冲突检测均放行",
      )
    }
  }
  notes.push(
    "任一作用域后来被抢/重叠→按 parallel_modes 顺序退回串行执行",
  )
  let fanout : Array[String] = if allowed { modes } else { [primary_str] }
  let fanout_json : Array[Json] = fanout.map(fn(s) { Json::string(s) })
  let rejected_json : Array[Json] = rejected.map(fn(s) { Json::string(s) })
  let basis_json : Array[Json] = reasons.map(fn(s) { Json::string(s) })
  let obj : Map[String, Json] = Map([])
  obj.set("chosen_mode", Json::string(primary_str))
  obj.set("complexity", Json::number(score.to_double()))
  obj.set(
    "basis",
    Json::string(
      join_terms(reasons) +
      "→复杂度 " +
      score.to_string() +
      "/5→选 " +
      primary_str,
    ),
  )
  obj.set("basis_items", Json::array(basis_json))
  obj.set("parallel_modes", Json::array(fanout_json))
  obj.set("parallel_allowed", Json::boolean(allowed))
  obj.set("conflict_gate", Json::string("reserve_scope/conflicts_check"))
  obj.set("note", Json::string(join_terms(notes)))
  obj.set("declared_tier", Json::string(tier))
  obj.set("scopes_declared", Json::boolean(declared))
  obj.set("scopes_disjoint", Json::boolean(disjoint))
  obj.set("rejected_candidates", Json::array(rejected_json))
  Json::object(obj)
}
