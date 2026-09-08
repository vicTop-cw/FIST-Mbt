/// omega/check.mbt — Ω-check 项目结构验证与回传格式校验。
///（移植自 FIST(Python) omega/check.py）
///
/// 验证维度：
/// 1. 结构验证：必填项（README.md / CHANGELOG.md / reports/）是否存在；
/// 2. 回传格式验证：任务回传是否符合五段式（结论/证据/分析/缺口与风险/建议入档位置）。

/// PROJECT-SPEC/01 必填项
let required_items : Array[String] = ["README.md", "CHANGELOG.md", "reports"]

/// FIST-SKILL 子代理回传强制五段式
let required_report_sections : Array[String] = [
  "结论", "证据", "分析", "缺口与风险", "建议入档位置",
]

/// 检查项目标准结构，返回结果 JSON 数组。
/// 每条: {"item", "passed", "detail"}
pub fn check_structure(project_dir : String) -> Array[Json] {
  let results : Array[Json] = []
  let dir_ok = @fs.path_exists(project_dir)
  if !dir_ok {
    results.push(Json::object({
      "item": Json::string("project_dir"),
      "passed": @json.to_json(false),
      "detail": Json::string("目录不存在: \{project_dir}"),
    }))
    return results
  }
  for item in required_items {
    let path = if project_dir.has_suffix("/") || project_dir.has_suffix("\\") {
      project_dir + item
    } else {
      project_dir + "\\" + item
    }
    let exists = @fs.path_exists(path)
    results.push(Json::object({
      "item": Json::string("必填项: \{item}"),
      "passed": jbool(exists),
      "detail": Json::string(if exists { "存在" } else { "缺失" }),
    }))
  }
  results
}

/// 检查回传文本是否符合五段式，返回结果 JSON 数组。
/// 每条: {"item", "passed", "detail"}
pub fn check_report_format(text : String) -> Array[Json] {
  let results : Array[Json] = []
  if text.trim().is_empty() {
    results.push(Json::object({
      "item": Json::string("回传文本"),
      "passed": @json.to_json(false),
      "detail": Json::string("回传为空"),
    }))
    return results
  }
  for section in required_report_sections {
    let found = text.contains(section)
    results.push(Json::object({
      "item": Json::string("回传段: \{section}"),
      "passed": jbool(found),
      "detail": Json::string(if found { "包含" } else { "缺失" }),
    }))
  }
  results
}
