/// ops_modes.mbt —— 自驱编程 6 种开发模式注册表（R117）
///
/// 纯计算、零依赖。模式是每轮"做什么"的语义约束，
/// 与 round_tick 的"要不要继续"（L1-L4 生命周期判定）正交。
///
/// 单真源：三引擎（watchdog/pipeline/selfdrive）只通过本模块
/// 解析 mode 字符串 → enum → 约束 → 模板路径，不自行硬编码。

// ---------------------------------------------------------------------------
// 6 种模式枚举
// ---------------------------------------------------------------------------

///|
/// 6 种自驱编程开发模式。枚举构造函数公开，供黑盒测试与跨包匹配。
pub enum PipelineMode {
  Advance // 默认：持续开发新功能
  Polish // 打磨：完善已有功能，不加新功能
  Verify // 验证：API 枚举 + 完备性 + 文档自洽
  BugFind // 寻虫：issue_scan + open-code-review + 边界语料
  FixAndMerge // 修复与合并：修 issues + 合并分支
  Tidy // 清整：项目打扫
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
    _ =>
      Err(
        "未知模式: " +
        t +
        ", 可选: advance|polish|verify|bugfind|fix_and_merge|tidy",
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
    _ => ()
  }
  Json::object(m)
}

///|
/// forbidden_tools（某些 mode 显式禁用的工具/任务名；空数组表示无约束）。
fn mode_forbidden_tools(mode_str : String) -> Array[String] {
  match mode_str {
    "polish" => ["publish_new_feature_task", "issue_scan_with_generate_new"]
    "tidy" => ["publish_new_feature_task"]
    _ => []
  }
}

// ---------------------------------------------------------------------------
// all_modes：模式完整描述数组
// ---------------------------------------------------------------------------

///|
/// 6 种完整模式描述数组（供 MCP mode_list 工具直接返回）。
/// 每个元素: { mode, name, description, constraints, template_path, forbidden_tools }。
pub fn all_modes() -> Array[Json] {
  let names = [
    "advance", "polish", "verify", "bugfind", "fix_and_merge", "tidy",
  ]
  let descs = [
    "默认模式：持续推进新功能开发。phase 流转 Creating→Pending→Running→Closed。",
    "打磨模式：完善已有功能、重构、性能调优。禁止发布新功能任务。",
    "验证模式：枚举 API、检查完备性、文档自洽。phase 增加 Enumerate/Verify。",
    "寻虫模式：issue_scan 规则驱动扫描 + 边界语料构造 + open-code-review。",
    "修复与合并模式：从 issue 池拉取、派发修复、PR 合并。需要 GitHub token。",
    "清整模式：项目打扫——清理 dead code、归档过期文件、清理依赖。禁止新增代码。",
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
