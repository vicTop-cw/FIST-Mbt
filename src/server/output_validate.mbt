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

///|
/// artifact 规格的字面校验（BUG-31）。
/// 病灶：`parse_artifact` 对键**只看认识的**，拼错/臆造的键（如 `contans`、`must_contain`）
/// 被静默忽略，spec 退化成「文件存在 + 非空」的空检查——硬门 verdict 仍是 pass，
/// detail 还写着「invariant 全部通过」，L4 证据梯因此可以自证为真。
/// 返回 ""=合法；否则给可直接回给调用方的原因（含可用键清单，不让人猜）。
fn artifact_spec_errors(a : Json) -> String {
  let allowed : Array[String] = [
    "path", "check_key", "min_chars", "contains", "not_contains",
  ]
  match a {
    Object(m) => {
      let mut unknown = ""
      let mut n_unknown = 0
      for k in m.keys() {
        if !allowed.any(fn(x : String) { x == k }) {
          if n_unknown > 0 {
            unknown = unknown + ", "
          }
          unknown = unknown + k
          n_unknown = n_unknown + 1
        }
      }
      if n_unknown > 0 {
        let why = "含未知键 " +
          unknown +
          "（会被静默忽略=假 pass）。可用键只有 path/check_key/min_chars/contains/not_contains"
        return why
      }
      let has_path = match m.get("path") {
        Some(String(s)) => s != ""
        _ => false
      }
      let has_key = match m.get("check_key") {
        Some(String(s)) => s != ""
        _ => false
      }
      if !has_path && !has_key {
        return "path 与 check_key 至少给一个（都不给=这条什么都不检查，却算通过）"
      }
      if has_path && has_key {
        return "path 与 check_key 二选一，不能同时给（两条检查路径语义不同）"
      }
      // BUG-209：键名合法 ≠ 值型合法。min_chars 必须是 Number、contains/not_contains
      // 必须是 String——否则 parse_artifact 静默降级成默认值（0/""），invariant 变空检查，
      // verdict 仍 pass（与 BUG-31「未知键静默忽略」同族）。这里把值型也立成硬门。
      let mc = match m.get("min_chars") {
        Some(Number(_, ..)) => true
        Some(_) => false
        None => true
      }
      if !mc {
        return "min_chars 必须是数字（Number），不能是字符串/布尔/null——否则会被静默当成 0、不检查字符数"
      }
      let cc = match m.get("contains") {
        Some(String(_)) => true
        Some(_) => false
        None => true
      }
      if !cc {
        return "contains 必须是字符串（String），不能是数字/布尔/null——否则会被静默当成空串、不检查 invariant"
      }
      let nc = match m.get("not_contains") {
        Some(String(_)) => true
        Some(_) => false
        None => true
      }
      if !nc {
        return "not_contains 必须是字符串（String），不能是数字/布尔/null——否则会被静默当成空串、不检查 invariant"
      }
      ""
    }
    _ => "不是 JSON 对象"
  }
}

///|
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
  // BUG-31 建议 2：pass 文案只声明**真正评估过**的不变量，纯存在性检查不得冒充 invariant 通过
  let have_min = spec.min_chars > 0
  let have_c = !spec.contains.is_empty()
  let have_nc = !spec.not_contains.is_empty()
  let pass_detail = if !have_min && !have_c && !have_nc {
    "OK（仅存在性/非空：未声明任何 invariant）"
  } else {
    let mut names = ""
    if have_min {
      names = names + "min_chars, "
    }
    if have_c {
      names = names + "contains, "
    }
    if have_nc {
      names = names + "not_contains, "
    }
    let cut = if names.has_suffix(", ") { 2 } else { 0 }
    let tail = names[0:names.length() - cut].to_owned()
    "OK（存在/非空 + invariant 全部通过: " + tail + "）"
  }
  { artifact: spec.path, ok: true, detail: pass_detail, }
}

///|
/// 对 external artifact 的 **stdout 内容** 应用 spec 声明的 contains/not_contains 不变量。
/// 返回 "" = 通过；否则给可直接回给调用方的失败原因。
/// BUG-143：此前外部检查只看 ok/code，stdout 里的 invariant 被静默忽略——
/// 进程退出 0 不代表产出有效（moon test SIGABRT 仍 exit 0，见 BUG-142）。
fn check_external_invariants(stdout : String, spec : ArtifactSpec) -> String {
  if !spec.contains.is_empty() {
    if !stdout.contains(spec.contains) {
      let shown = if stdout.length() > 120 {
        stdout[0:120].to_owned() + "..."
      } else {
        stdout
      }
      return "stdout 缺少必需字符串 \"\{spec.contains}\"（当前: \"\{shown}\"）"
    }
  }
  if !spec.not_contains.is_empty() {
    if stdout.contains(spec.not_contains) {
      return "stdout 含禁止字符串 \"\{spec.not_contains}\"（进程可能已崩溃却仍退出 0）"
    }
  }
  ""
}

///|
/// 简单解析十进制整数（非负，可含前后空白；解析失败返回 None）。
/// 与 ops_selfdrive 的 sd_parse_int 同型（MoonBit core 未提供 String::parse_int）。
/// R12-R8 bugfind（BUG-221）：**补上 sd_parse_int 已有的 int_safe 上界守卫**——
/// 旧实现缺守卫，长数字串（如 max_findings=999999999999）在
/// `v = v * 10 + d` 上溢出 Int32 而不报错（绕回/精度丢失）。
pub fn ov_parse_int(raw : String) -> Int? {
  // 去掉末尾句号（moon 汇总行末尾 "0." 常见）
  let mut s = raw.trim().to_owned()
  if s.has_suffix(".") {
    s = s[0:s.length() - 1].to_owned()
  }
  if s.is_empty() {
    return None
  }
  let int_safe : Int = 200_000_000
  let mut v = 0
  for c in s {
    if c < '0' || c > '9' {
      return None
    }
    if v >= int_safe {
      return None
    }
    v = v * 10 + (c.to_int() - '0'.to_int())
  }
  Some(v)
}

///|
/// BUG-142（自动 gate）：当 check_key 名含 `moon_test`/`moon test` 时，
/// 自动解析 stdout 的 `Total tests: N, passed: M, failed: K` 汇总行，
/// failed>0 直接 fail——**不需要调用方显式声明 contains**。
/// 实测：`moon test` 进程被信号打死仍 exit 0（SIGABRT），只看退出码是假的绿。
/// 找不到汇总行 → 提示调用方检查 stdout；找到且 failed=0 → 通过。
/// 返回 "" = 通过；否则给可直接回给调用方的失败原因。
fn check_moon_test_summary(stdout : String) -> String {
  let lines = stdout.split("\n")
  let mut found = false
  let mut failed = 0
  let mut total = 0
  for ln in lines {
    let line = ln.trim().to_owned()
    if line.has_prefix("Total tests:") {
      found = true
      // 形如 "Total tests: 645, passed: 645, failed: 0."（末尾可带句号）
      for field in line.split(",") {
        let f = field.trim().to_owned()
        if f.has_prefix("failed:") {
          let v = f[7:].to_owned().trim().to_owned()
          match ov_parse_int(v) {
            Some(n) => failed = n
            None => ()
          }
        } else if f.has_prefix("Total tests:") {
          let v = f[12:].to_owned().trim().to_owned()
          match ov_parse_int(v) {
            Some(n) => total = n
            None => ()
          }
        }
      }
    }
  }
  if !found {
    return "moon test stdout 缺 `Total tests:` 汇总行——无法判绿（BUG-142：进程可能崩溃却仍 exit 0）"
  }
  // BUG-211：`Total tests: 0, passed: 0, failed: 0.` 是「一个测试都没跑」的空套件——
  // failed=0 只看失败数，把 total=0 也当成全绿，是 BUG-142 假绿的又一入口
  // （空包/构建漏收集测试/汇总被截断在 0 之前都可能喂出这一行）。
  if total == 0 {
    return "moon test 汇总行 total=0——没有跑任何测试（passed=0 不算证据），按 BUG-211 判定失败"
  }
  if failed > 0 {
    return "moon test 汇总行 failed=" +
      failed.to_string() +
      "（total=" +
      total.to_string() +
      "）——按 BUG-142 判定失败，不信 exit 0"
  }
  ""
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
      // BUG-143（P1「Did it work?」）：外部检查不能只看 ok/code——
      // 进程可能退出 0 但产出无效（moon test SIGABRT 仍 exit 0，BUG-142）。
      // 若 spec 声明了 contains/not_contains，则必须对 **stdout 实际内容** 做同样校验；
      // 否则这些 invariant 被静默忽略（同 BUG-31 病灶：拼了 key 却没人读它）。
      match ok_val {
        true => {
          // 先对 stdout 应用 invariant（有则硬门；没有则退回只看 ok）
          let stdout = match m.get("stdout") {
            Some(String(s)) => s
            _ => ""
          }
          let inv_err = check_external_invariants(stdout, spec)
          // BUG-142：key 名含 moon_test / moon test 时自动解析汇总行，
          // 不依赖调用方记得声明 contains="failed: 0"。
          let key_low = key.to_lower()
          let moon_err = if key_low.contains("moon_test") ||
            key_low.contains("moon test") {
            check_moon_test_summary(stdout)
          } else {
            ""
          }
          let combined = if inv_err != "" { inv_err } else { moon_err }
          if combined != "" {
            { artifact: "external:" + key, ok: false, detail: combined, }
          } else {
            let extra = if !spec.contains.is_empty() {
              "；stdout contains=\"\{spec.contains}\""
            } else if !spec.not_contains.is_empty() {
              "；stdout not_contains=\"\{spec.not_contains}\""
            } else {
              ""
            }
            {
              artifact: "external:" + key,
              ok: true,
              detail: "OK（外部检查 passed）\{extra}",
            }
          }
        }
        false => {
          let stderr = match m.get("stderr") {
            Some(String(s)) =>
              if s.length() > 200 {
                s[0:200].to_owned() + "..."
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
    let spec_err = artifact_spec_errors(a)
    if spec_err != "" {
      checks.push({
        artifact: "<invalid>",
        ok: false,
        detail: "artifact 规格非法: " + spec_err,
      })
      any_failed = true
      continue
    }
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
