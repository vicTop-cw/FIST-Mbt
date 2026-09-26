/// output_validate.mbt —— 产出物验证（"报告不是证据，只有交付产物的实际状态才能证明工作发生了"）
///
/// 五层证据梯（复用验证责任转移）：
///   L1 示意层（最弱）：agent 报告字符串——默认不信，仅参考
///   L2 动作层：tool 成功消息（如 run 返回 ok）——仍可假
///   L3 测试层：run_check 退出码 0 / moon test 通过——比自述强
///   L4 产物状态层（核心增强）：到交付产物实际机上查——文件存在？非空？期望 invariant 成立？
///   L5 外部接受层（最强）：omega 复验 / 验收方通过——最终门
///
/// 本文件实现 L4（产物状态层硬门）：按 artifacts 描述的每个产物做确定性检查，
/// verdict=pass 当且仅当所有 artifact 检查通过；任一失败即 fail。
/// 命令执行（L3）不在本文件，由调用方先跑 run_check 再把结果喂过来（enforce 闭环）。
///
/// 不新造 fork/exec 轮子，仅做文件系统确定性检查——好测、纯、无外部依赖。

///|
/// 单条产物检查结果。
priv struct OutputCheck {
  artifact : String
  ok : Bool
  detail : String
}

///|
/// artifact 路径合法性校验：拒绝空串 / 纯穿越 / 绝对路径 / 盘符。
/// 与 issue_scan 的 scan_dir_ok 同源防御。
fn validate_artifact_path(p : String) -> Bool {
  if p.is_empty() {
    return false
  }
  if p.contains("..") {
    return false
  }
  let c0 = p[0]
  if c0 == '/' || c0 == '\\' {
    return false
  }
  if p.length() >= 2 && p[1] == ':' {
    return false
  }
  true
}

///|
/// artifact 规格（纯数据，用于内部传递）。
priv struct ArtifactSpec {
  path : String
  check_key : String
  contains : String
  not_contains : String
  min_chars : Int
}

///|
/// 解析一个 artifact JSON 对象，返回 ArtifactSpec。
/// 支持两类：
///   { path: "xxx.mbt" }                    → file artifact
///   { path: "xxx.mbt", contains: "YYY" }  → file + invariant=contains
///   { path: "xxx.mbt", not_contains: "Z"} → file + invariant=not_contains
///   { path: "xxx.mbt", min_chars: 100 }   → file + invariant=size
///   { check_key: "moon_test" }              → external artifact（外部 run_check 结果）
/// 非法对象返回 None。
fn parse_artifact(a : Json) -> ArtifactSpec? {
  match a {
    Object(m) =>
      Some(ArtifactSpec::{
        path: match m.get("path") {
          Some(String(s)) => s
          _ => ""
        },
        check_key: match m.get("check_key") {
          Some(String(s)) => s
          _ => ""
        },
        contains: match m.get("contains") {
          Some(String(s)) => s
          _ => ""
        },
        not_contains: match m.get("not_contains") {
          Some(String(s)) => s
          _ => ""
        },
        min_chars: match m.get("min_chars") {
          Some(Number(n, ..)) => n.to_int()
          _ => 0
        },
      })
    _ => None
  }
}

///|
/// 对单个 file artifact 执行检查（存在性→非空→invariant，短路返回）。
fn check_file_artifact(
  project_dir : String,
  spec : ArtifactSpec,
) -> OutputCheck {
  let full = if project_dir.is_empty() {
    spec.path
  } else {
    mem_join(project_dir, spec.path)
  }
  // 1) 路径合法性
  if !validate_artifact_path(spec.path) {
    return {
      artifact: spec.path,
      ok: false,
      detail: "路径非法（拒绝空串/穿越/绝对路径）",
    }
  }
  // 2) 文件存在
  if !@fs.path_exists(full) {
    return {
      artifact: spec.path,
      ok: false,
      detail: "文件不存在: \{full}",
    }
  }
  // 3) 读取内容
  let content = match mem_read(full) {
    None =>
      return {
        artifact: spec.path,
        ok: false,
        detail: "文件可读但读取失败（编码/权限）",
      }
    Some(s) => s
  }
  // 4) 非空
  if content.is_empty() {
    return { artifact: spec.path, ok: false, detail: "文件为空", }
  }
  // 5) min_chars 下限
  if spec.min_chars > 0 && content.length() < spec.min_chars {
    return {
      artifact: spec.path,
      ok: false,
      detail: "文件字符数不足: 当前 \{content.length()} < 下限 \{spec.min_chars}",
    }
  }
  // 6) contains invariant
  if !spec.contains.is_empty() {
    if !content.contains(spec.contains) {
      return {
        artifact: spec.path,
        ok: false,
        detail: "文件缺少必需字符串: \"\{spec.contains}\"",
      }
    }
  }
  // 7) not_contains invariant
  if !spec.not_contains.is_empty() {
    if content.contains(spec.not_contains) {
      return {
        artifact: spec.path,
        ok: false,
        detail: "文件含禁止字符串: \"\{spec.not_contains}\"",
      }
    }
  }
  {
    artifact: spec.path,
    ok: true,
    detail: "OK（存在/非空/invariant 全部通过）",
  }
}

///|
/// 对 external artifact（check_key 引用外部已跑的 run_check 结果）做检查。
/// external_results 形如 { "moon_test": { ok: true, code: 0, ... }, ... }。
fn check_external_artifact(
  spec : ArtifactSpec,
  external_results : Map[String, Json],
) -> OutputCheck {
  let key = spec.check_key
  if key.is_empty() {
    return {
      artifact: "external:" + key,
      ok: false,
      detail: "check_key 为空",
    }
  }
  match external_results.get(key) {
    None =>
      return {
        artifact: "external:" + key,
        ok: false,
        detail: "外部结果缺失: key=\"\{key}\" 未在 external_results 中找到（调用方应先跑 run_check 把结果传入）",
      }
    Some(Json::Object(m)) => {
      let ok_val = match m.get("ok") {
        Some(True) => true
        Some(False) => false
        Some(String(s)) => s == "passed" || s == "ok" || s == "true"
        _ => false
      }
      match ok_val {
        true =>
          {
            artifact: "external:" + key,
            ok: true,
            detail: "OK（外部检查 passed）",
          }
        false => {
          let stderr = match m.get("stderr") {
            Some(String(s)) =>
              if s.length() > 200 {
                s.substring(start=0, end=200) + "..."
              } else {
                s
              }
            _ => ""
          }
          {
            artifact: "external:" + key,
            ok: false,
            detail: "外部检查 failed（stderr 片段: \{stderr}）",
          }
        }
      }
    }
    Some(other) => {
      // 非 object：尝试看是不是 boolean
      let val = match other {
        True => true
        False => false
        String(s) => s == "passed" || s == "ok" || s == "true"
        _ => false
      }
      match val {
        true =>
          {
            artifact: "external:" + key,
            ok: true,
            detail: "OK（外部检查 passed）",
          }
        false =>
          {
            artifact: "external:" + key,
            ok: false,
            detail: "外部检查 failed",
          }
      }
    }
  }
}

///|
/// 解析 external_results JSON：{ "key1": {...}, "key2": {...} } → Map。
/// 解析失败返回空 Map（不会 abort）。
fn parse_external_results(raw : Json) -> Map[String, Json] {
  let m : Map[String, Json] = Map([])
  match raw {
    Object(obj) =>
      for (k, v) in obj {
        m.set(k, v)
      }
    _ => ()
  }
  m
}

///|
/// 主入口：output_validate 产出物验证。
///
/// 参数：
///   project_dir       项目根目录（空串时 artifacts 用绝对路径，慎用）
///   artifacts         检查项数组（见 parse_artifact 规格）
///   external_results  外部 run_check 结果字典（可选 Json，用于 check_key 类 artifact）
///   evidence          agent 报告字符串（示意层，弱证据，仅当所有 artifact 都通过时才参考）
///   require_evidence  是否要求 evidence 非空（默认 false）
///
/// 返回：
///   Ok(Json) 含 verdict/passed/failed/checks/evidence_layer/note
///   Err(String) 参数错误
pub fn output_validate(
  project_dir : String,
  artifacts : Array[Json],
  external_results : Json,
  evidence : String,
  require_evidence? : Bool = false,
) -> Result[Json, String] {
  // 1) 基本校验
  if artifacts.length() == 0 {
    return Err(
      "output_validate: artifacts 为空——至少声明一条要验证的交付产物",
    )
  }
  let ext_map = parse_external_results(external_results)

  // 2) 逐条检查
  let checks : Array[OutputCheck] = []
  let mut any_failed = false
  let mut parsed_count = 0
  for a in artifacts {
    match parse_artifact(a) {
      None => {
        checks.push({
          artifact: "<invalid>",
          ok: false,
          detail: "artifact 格式非法（缺 path 或 check_key）",
        })
        any_failed = true
      }
      Some(spec) => {
        parsed_count = parsed_count + 1
        let c = if !spec.path.is_empty() {
          check_file_artifact(project_dir, spec)
        } else {
          check_external_artifact(spec, ext_map)
        }
        checks.push(c)
        if !c.ok {
          any_failed = true
        }
      }
    }
  }

  // 3) 示意层 evidence（仅当硬门全过时才考虑）
  let (evidence_layer, verdict, evidence_note) = if any_failed {
    ("l4-hard-failed", "fail", "")
  } else if require_evidence && evidence.is_empty() {
    (
      "l4-pass-but-l1-missing", "fail", "硬门全过，但 evidence 为空且 require_evidence=true——标记 fail（报告不是证据，但至少要有）",
    )
  } else {
    ("l4-pass", "pass", "")
  }

  // 4) 构造 checks JSON 数组
  let checks_json = checks.map(fn(c : OutputCheck) {
    Json::object({
      "artifact": Json::string(c.artifact),
      "ok": Json::boolean(c.ok),
      "detail": Json::string(c.detail),
    })
  })
  let passed_count = checks.filter(fn(c : OutputCheck) { c.ok }).length()
  let failed_count = checks.length() - passed_count

  // 5) 汇总 note
  let note : String = if !evidence_note.is_empty() {
    evidence_note
  } else if verdict == "pass" {
    "全部 " +
    passed_count.to_string() +
    " 条产物检查通过（证据层: " +
    evidence_layer +
    "）"
  } else {
    failed_count.to_string() +
    "/" +
    checks.length().to_string() +
    " 条产物检查失败（证据层: " +
    evidence_layer +
    "）"
  }

  Ok(
    Json::object({
      "verdict": Json::string(verdict),
      "checks": Json::array(checks_json),
      "passed": Json::number(passed_count.to_double()),
      "failed": Json::number(failed_count.to_double()),
      "evidence_layer": Json::string(evidence_layer),
      "evidence": Json::string(evidence),
      "note": Json::string(note),
      "parsed_artifacts": Json::number(parsed_count.to_double()),
    }),
  )
}
