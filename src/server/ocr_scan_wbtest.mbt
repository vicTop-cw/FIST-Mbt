///|
/// ocr_scan_wbtest.mbt —— ocr_scan 工具白盒测试（纯计算层，不 spawn 真实进程）
///
/// 覆盖：子命令白名单 / argv 形状（scan/files/delegate/rules）/ 非法入参 Err /
/// project_dir 防御 / stdout JSON files 解析。IO 层（探测 + spawn）在 MCP 冒烟里验证。

///|
test "ocr_subcmds_whitelist" {
  let s = ocr_subcmds()
  assert_eq(s.length(), 4)
  assert_true(s.contains("scan"))
  assert_true(s.contains("files"))
  assert_true(s.contains("delegate"))
  assert_true(s.contains("rules"))
  assert_true(is_ocr_subcmd("scan"))
  assert_true(is_ocr_subcmd("files"))
  assert_true(is_ocr_subcmd("delegate"))
  assert_true(is_ocr_subcmd("rules"))
  assert_false(is_ocr_subcmd("review"))
  assert_false(is_ocr_subcmd(""))
}

///|
test "ocr_build_args_scan_shape" {
  let a = match ocr_build_args(project_dir="src", subcmd="files") {
    Ok(v) => v
    Err(e) => abort("unexpected Err: " + e)
  }
  assert_eq(a.length(), 6)
  assert_eq(a[0], "scan")
  assert_eq(a[1], "--repo")
  assert_eq(a[2], "src")
  assert_eq(a[3], "--preview")
  assert_eq(a[4], "--format")
  assert_eq(a[5], "json")
  // 带 path 与 rules_file
  let b = match
    ocr_build_args(
      project_dir=".",
      subcmd="scan",
      path="server/ocr_scan.mbt",
      rules_file="rules/moonbit-rules.json",
    ) {
    Ok(v) => v
    Err(e) => abort("unexpected Err: " + e)
  }
  assert_eq(b.length(), 10)
  assert_eq(b[6], "--path")
  assert_eq(b[7], "server/ocr_scan.mbt")
  assert_eq(b[8], "--rule")
  assert_eq(b[9], "rules/moonbit-rules.json")
}

///|
test "ocr_build_args_delegate_shape" {
  let a = match
    ocr_build_args(
      project_dir="src",
      subcmd="delegate",
      path="server/ocr_scan.mbt, server/issue_scan.mbt",
    ) {
    Ok(v) => v
    Err(e) => abort("unexpected Err: " + e)
  }
  // delegate rule --repo src server/ocr_scan.mbt server/issue_scan.mbt
  assert_eq(a.length(), 6)
  assert_eq(a[0], "delegate")
  assert_eq(a[1], "rule")
  assert_eq(a[2], "--repo")
  assert_eq(a[3], "src")
  assert_eq(a[4], "server/ocr_scan.mbt")
  assert_eq(a[5], "server/issue_scan.mbt")
}

///|
test "ocr_build_args_rules_shape" {
  let a = match
    ocr_build_args(
      project_dir="src",
      subcmd="rules",
      path="server/ocr_scan.mbt",
    ) {
    Ok(v) => v
    Err(e) => abort("unexpected Err: " + e)
  }
  assert_eq(a.length(), 3)
  assert_eq(a[0], "rules")
  assert_eq(a[1], "check")
  assert_eq(a[2], "server/ocr_scan.mbt")
}

///|
test "ocr_build_args_bad_input_err" {
  // 未知子命令
  let r1 = ocr_build_args(project_dir="src", subcmd="review")
  assert_true(r1 is Err(_))
  // delegate 缺 path
  let r2 = ocr_build_args(project_dir="src", subcmd="delegate")
  assert_true(r2 is Err(_))
  // rules 缺 path
  let r3 = ocr_build_args(project_dir="src", subcmd="rules")
  assert_true(r3 is Err(_))
}

///|
test "ocr_dir_ok_defense" {
  assert_true(ocr_dir_ok("."))
  assert_true(ocr_dir_ok("src"))
  assert_true(ocr_dir_ok("src/server"))
  assert_false(ocr_dir_ok(""))
  assert_false(ocr_dir_ok("../etc"))
  assert_false(ocr_dir_ok("/abs/path"))
  assert_false(ocr_dir_ok("C:/windows"))
  assert_false(ocr_dir_ok("\\server\\share"))
}

///|
test "ocr_extract_files_parse" {
  let j = "{\"files\":[{\"path\":\"core/core_principle.mbt\",\"status\":\"scan\"},{\"path\":\"server/ocr_scan.mbt\",\"status\":\"scan\"}]}"
  let files = ocr_extract_files(j)
  assert_eq(files.length(), 2)
  assert_eq(files[0], "core/core_principle.mbt")
  assert_eq(files[1], "server/ocr_scan.mbt")
  // 非法 JSON → 空数组（不报错）
  assert_eq(ocr_extract_files("not json").length(), 0)
  // 无 files 键 → 空数组
  assert_eq(ocr_extract_files("{\"other\":1}").length(), 0)
}

///|
test "ocr_plan_bad_project_dir" {
  // 非法 project_dir 直接失败（不发进程）；ocr_scan_impl 的 async spawn 面由 MCP 冒烟验证
  let j = ocr_plan("../etc", subcmd="files", dry_run=true)
  let m = match j {
    Json::Object(mm) => mm
    _ => abort("not object")
  }
  assert_eq(m.get("ok"), Some(Json::boolean(false)))
  assert_eq(m.get("ocr_available"), Some(Json::boolean(false)))
  let err = match m.get("error") {
    Some(Json::String(s)) => s
    _ => abort("no error")
  }
  assert_true(err.contains("project_dir"))
}

///|
test "ocr_plan_bad_subcmd" {
  let j = ocr_plan(".", subcmd="review", dry_run=true)
  let m = match j {
    Json::Object(mm) => mm
    _ => abort("not object")
  }
  assert_eq(m.get("ok"), Some(Json::boolean(false)))
  assert_eq(m.get("ocr_available"), Some(Json::boolean(false)))
}

///|
test "ocr_plan_dry_run_argv" {
  let j = ocr_plan("src", subcmd="files", dry_run=true)
  let m = match j {
    Json::Object(mm) => mm
    _ => abort("not object")
  }
  assert_eq(m.get("ok"), Some(Json::boolean(true)))
  assert_eq(m.get("dry_run"), Some(Json::boolean(true)))
  assert_eq(m.get("exit_code"), Some(Json::number(0.0)))
  let args = match m.get("args") {
    Some(Json::Array(a)) => a
    _ => abort("no args")
  }
  assert_eq(args.length(), 6)
  let first = match args[0] {
    Json::String(s) => s
    _ => abort("args[0] not string")
  }
  assert_eq(first, "scan")
}

///|
test "ocr_fake_green_check_mbt_excluded" {
  // BUG-165：scan 对 .mbt 假绿——reviewable_count=0 且 excluded>0 + exclude_reason
  let s = "{\"files\":[{\"path\":\"src/server/server.mbt\",\"status\":\"scan\",\"insertions\":7337,\"deletions\":0,\"will_review\":false,\"exclude_reason\":\"unsupported_ext\"}],\"total_insertions\":0,\"total_deletions\":0,\"total_files\":1,\"reviewable_count\":0,\"excluded_count\":1}"
  let (reviewed, notice) = ocr_fake_green_check(s)
  assert_false(reviewed)
  assert_true(notice.contains("unsupported_ext"))
  assert_true(notice.contains("1"))
  assert_true(notice.contains("未真正执行"))
}

///|
test "ocr_fake_green_check_py_reviewed" {
  // .py 正常：reviewable_count=1 → 不判假绿
  let s = "{\"files\":[{\"path\":\"scripts/mcp_smoke.py\",\"status\":\"scan\",\"insertions\":221,\"deletions\":0,\"will_review\":true}],\"total_insertions\":221,\"total_deletions\":0,\"total_files\":1,\"reviewable_count\":1,\"excluded_count\":0}"
  let (reviewed, notice) = ocr_fake_green_check(s)
  assert_true(reviewed)
  assert_eq(notice, "")
}

///|
test "ocr_fake_green_check_bad_shape_passthrough" {
  // 非 scan/files JSON 形状（如 delegate 的 markdown）、空输出、非法 JSON → 不判定，保守通过
  let (r1, n1) = ocr_fake_green_check("")
  assert_true(r1)
  assert_eq(n1, "")
  let (r2, n2) = ocr_fake_green_check("not json at all")
  assert_true(r2)
  assert_eq(n2, "")
  let (r3, n3) = ocr_fake_green_check(
    "### Rule Group 1\n\n#### Correctness\nIs the logic correct?",
  )
  assert_true(r3)
  assert_eq(n3, "")
}

///|
test "ocr_fake_green_check_empty_dir_no_fp" {
  // reviewable=0 但 excluded=0（空目录）→ 不判假绿，避免误报
  let s = "{\"files\":[],\"total_files\":0,\"reviewable_count\":0,\"excluded_count\":0}"
  let (reviewed, notice) = ocr_fake_green_check(s)
  assert_true(reviewed)
  assert_eq(notice, "")
}

///|
test "BUG-327 部分2 ocr_gate_state 三态：二进制缺=unavailable" {
  let (g, n) = ocr_gate_state(false, true)
  assert_eq(g, "unavailable")
  assert_true(n.contains("ocr_available=false"))
  let (g2, _) = ocr_gate_state(false, false)
  assert_eq(g2, "unavailable")
}

///|
/// T0r588 改判：MoonBit 目标不再恒 degraded。
/// 旧口径（"白名单不收 .mbt ⇒ require_ocr 恒不可满足"）已被 P0 诊断推翻：
/// OCR 内嵌白名单确实改不动，但 --rule 的 include glob 优先级更高、能短路放行，
/// ocr_scan 会自动注入 ⇒ 机制可达，gate 允许 satisfied。
/// 注意：satisfied 只代表"机制可达"，不代表"这一发真审了"——后者看回执证据。
test "T0r588 ocr_gate_state：MoonBit 目标按机制可达判 satisfied，但把最终判据推给回执" {
  let (g, n) = ocr_gate_state(true, true)
  assert_eq(g, "satisfied")
  assert_true(n.contains("include"))
  // 必须明确"gate ≠ 这一发真审了"，否则又把伪能力请回来
  assert_true(n.contains("ok/ocr_reviewed"))
}

///|
test "BUG-327 部分2 ocr_gate_state 三态：非 MoonBit 目标才 satisfied" {
  let (g, n) = ocr_gate_state(true, false)
  assert_eq(g, "satisfied")
  assert_true(n.contains("ok/reviewed"))
}

///|
/// T0r588：本仓回执不得伪满足——`mbt_reviewable` 必须与二进制可用性同源
/// （机制可达 = 有二进制可注规则），gate 只允许 satisfied(二进制在) / unavailable，
/// 且必须给出 mbt_admission 说明走的是哪条放行通道。
test "T0r588 ocr_capability_json：mbt_reviewable 跟随二进制可用性，gate 不伪满足" {
  let j = ocr_capability_json(".")
  let m = match j {
    Json::Object(mm) => mm
    _ => abort("capability 不是对象")
  }
  assert_eq(m.get("moonbit_target"), Some(Json::boolean(true)))
  let avail = m.get("available") == Some(Json::boolean(true))
  // 同源断言：可用 ⇒ 可审；不可用 ⇒ 不可审（绝不出现"没二进制却宣称可审"）
  assert_eq(m.get("mbt_reviewable"), Some(Json::boolean(avail)))
  assert_eq(
    m.get("mbt_admission"),
    Some(Json::string(if avail { "rule-include" } else { "none" })),
  )
  let g = match m.get("gate") {
    Some(Json::String(s)) => s
    _ => abort("gate 缺失")
  }
  assert_true(g == "satisfied" || g == "unavailable")
  assert_true(m.get("note") is Some(_))
}

///|
/// T0r588 锁 1：放行规则正文形状。
/// `include` 必须是 **/*.mbt（放行 .mbt），`rules` 必须为空数组——
/// 后者是硬约束：custom 层若带 per-path 规则，composedResolver.Resolve 会在
/// 第一层命中并**盖掉** system 评审规则（静默降质），故放行规则只许带 filter。
test "T0r588 ocr_mbt_include_rule_json 形状：include **/*.mbt 且 rules 为空" {
  let s = ocr_mbt_include_rule_json()
  let j = @json.parse(s) catch { _ => abort("放行规则不是合法 JSON") }
  let m = match j {
    Json::Object(mm) => mm
    _ => abort("放行规则不是对象")
  }
  let inc = match m.get("include") {
    Some(Json::Array(a)) => a
    _ => abort("缺 include")
  }
  assert_eq(inc.length(), 1)
  let pat = match inc[0] {
    Json::String(p) => p
    _ => abort("include 元素不是字符串")
  }
  assert_eq(pat, "**/*.mbt")
  let rules = match m.get("rules") {
    Some(Json::Array(a)) => a
    _ => abort("缺 rules")
  }
  assert_eq(rules.length(), 0)
}

///|
/// T0r588 锁 2：目标是否点名 .mbt（逗号列表 / 前后空格 / 目录 / 其他扩展名）。
test "T0r588 ocr_path_has_mbt 判定" {
  assert_true(ocr_path_has_mbt("src/server/ocr_scan.mbt"))
  assert_true(ocr_path_has_mbt("a/b.mbt, c/d.py"))
  assert_true(ocr_path_has_mbt(" src/x.mbt "))
  assert_false(ocr_path_has_mbt("src/server"))
  assert_false(ocr_path_has_mbt("scripts/issue_scan.py"))
  assert_false(ocr_path_has_mbt(""))
}

///|
/// T0r588 锁 3：注入决策。核心是"绝不抢用户自己的 custom 层"——
/// --rule 只有一格，注入会顶掉用户的规则文件。
test "T0r588 ocr_needs_mbt_include 决策：显式 rules_file 优先" {
  assert_false(ocr_needs_mbt_include("src/x.mbt", "my-rules.json", true))
  assert_true(ocr_needs_mbt_include("src/x.mbt", "", false))
  assert_true(ocr_needs_mbt_include("src/server", "", true))
  // 零回归格：非 MoonBit 且非 .mbt ⇒ 不注入，argv 与旧行为逐字一致
  assert_false(ocr_needs_mbt_include("src", "", false))
}

///|
/// T0r588 锁 4（**变异对照**）：证据制复核。
/// 第一格就是本任务的变异格——把实现改回旧的一刀切「目标带 .mbt 即 false」，
/// 这一格必红（真审查已可达时旧实现会谎报不可达）。其余格钉住 fail-closed 半边。
test "T0r588 ocr_reviewed_final 证据制：真进了选择面才算审过" {
  // 变异对照：真审了（total_files>=1）必须判 reviewed=true
  let (r1, n1) = ocr_reviewed_final(true, "src/server/ocr_scan.mbt", 1)
  assert_true(r1)
  assert_eq(n1, "")
  // 静默丢弃（BUG-327b 形态）⇒ fail-closed
  let (r2, n2) = ocr_reviewed_final(true, "src/server/ocr_scan.mbt", 0)
  assert_false(r2)
  assert_true(n2.contains("total_files"))
  // 回执无该键（版本差异）⇒ 保守 fail-closed，不猜
  let (r3, _) = ocr_reviewed_final(true, "src/server/ocr_scan.mbt", -1)
  assert_false(r3)
  // 非 .mbt 目标不受本判据影响
  let (r4, n4) = ocr_reviewed_final(true, "scripts/issue_scan.py", 0)
  assert_true(r4)
  assert_eq(n4, "")
  // 上游已判假绿时原样 false（不得被这里洗白）
  let (r5, _) = ocr_reviewed_final(false, "src/server/ocr_scan.mbt", 1)
  assert_false(r5)
}

///|
/// T0r588 锁 5：证据读数必须能区分「0 份」与「这个版本不给这个键」。
/// 混同这两者会让证据制判据在旧版本上假绿。
test "T0r588 ocr_stdout_int 区分 0 与键缺失" {
  let s = "{\"total_files\":3,\"reviewable_count\":0}"
  assert_eq(ocr_stdout_int(s, "total_files"), 3)
  assert_eq(ocr_stdout_int(s, "reviewable_count"), 0)
  assert_eq(ocr_stdout_int("{\"other\":1}", "total_files"), -1)
  assert_eq(ocr_stdout_int("not json", "total_files"), -1)
  assert_eq(ocr_stdout_int("", "total_files"), -1)
}

///|
/// T0r588 锁 6：修法提示只在"确实没审成"时出现，且必须给出可执行动作。
test "T0r588 ocr_mbt_remedy 只在没审成时给修法" {
  assert_eq(ocr_mbt_remedy("src/x.mbt", true), "")
  let h = ocr_mbt_remedy("src/x.mbt", false)
  assert_true(h.contains("include"))
  assert_true(h.contains("**/*.mbt"))
  assert_eq(ocr_mbt_remedy("scripts/a.py", false), "")
}

///|
/// T0r588 锁 7（**接线格**，判例-3：改名不是接线）：
/// 光有纯函数还不算修好——必须证明 argv 里真的带上了 `--rule <放行规则>`，
/// 且那份文件**真在盘上、内容真是放行规则**（不是空文件 / 只写进回执字段）。
test "T0r588 ocr_plan 真把放行规则接进 argv 并落盘" {
  let j = ocr_plan(
    ".",
    subcmd="files",
    path="src/server/ocr_scan.mbt",
    dry_run=true,
  )
  let m = match j {
    Json::Object(mm) => mm
    _ => abort("回执不是对象")
  }
  assert_eq(m.get("ok"), Some(Json::boolean(true)))
  assert_eq(m.get("mbt_include"), Some(Json::boolean(true)))
  let rule_path = match m.get("mbt_include_rule") {
    Some(Json::String(s)) => s
    _ => abort("缺 mbt_include_rule")
  }
  assert_true(rule_path.length() > 0)
  assert_true(@fs.path_exists(rule_path))
  let strs = match m.get("args") {
    Some(Json::Array(a)) =>
      a.map(fn(v) {
        match v {
          Json::String(s) => s
          _ => ""
        }
      })
    _ => abort("缺 args")
  }
  assert_true(strs.contains("--rule"))
  assert_true(strs.contains(rule_path))
  // 落盘内容自证：不是空壳
  let body = @fs.read_file_to_string(rule_path, encoding="utf8") catch {
    _ => abort("读不回放行规则：落盘格没跑到被测面")
  }
  assert_true(body.contains("**/*.mbt"))
}

///|
/// T0r588 锁 8（零回归）：非 MoonBit / 未点名 .mbt 的目标**不注入**，
/// argv 长度与旧行为逐字一致（6 项），避免把普通项目的扫描面悄悄改掉。
test "T0r588 ocr_plan 非 .mbt 目标零回归：不注入、argv 不变" {
  let j = ocr_plan("src", subcmd="files", dry_run=true)
  let m = match j {
    Json::Object(mm) => mm
    _ => abort("回执不是对象")
  }
  assert_eq(m.get("mbt_include"), Some(Json::boolean(false)))
  assert_eq(m.get("mbt_include_rule"), Some(Json::string("")))
  let args = match m.get("args") {
    Some(Json::Array(a)) => a
    _ => abort("缺 args")
  }
  assert_eq(args.length(), 6)
}

///|
/// T0r588 锁 9：用户给了 rules_file ⇒ 走用户的规则文件，不注入、不顶替。
test "T0r588 显式 rules_file 时不注入，argv 用用户的规则" {
  let j = ocr_plan(
    ".",
    subcmd="files",
    path="src/server/ocr_scan.mbt",
    rules_file="my-rules.json",
    dry_run=true,
  )
  let m = match j {
    Json::Object(mm) => mm
    _ => abort("回执不是对象")
  }
  assert_eq(m.get("mbt_include"), Some(Json::boolean(false)))
  let strs = match m.get("args") {
    Some(Json::Array(a)) =>
      a.map(fn(v) {
        match v {
          Json::String(s) => s
          _ => ""
        }
      })
    _ => abort("缺 args")
  }
  assert_true(strs.contains("--rule"))
  assert_true(strs.contains("my-rules.json"))
}

///|
/// T0r588 锁 10（踩坑锁）：放行规则路径不得混拼分隔符。
/// 实现起初用 `String::replace(old="\\", new="/")`，而它只换**第一处**
/// （实测回执给出 `C:/Users\victo\AppData\Local\Temp/...json`），换成
/// `replace_all` 才干净。这一格钉住"路径里不出现反斜杠"，防回退。
test "T0r588 放行规则路径无混拼反斜杠" {
  let j = ocr_plan(".", subcmd="files", path="src/x.mbt", dry_run=true)
  let m = match j {
    Json::Object(mm) => mm
    _ => abort("回执不是对象")
  }
  let rule_path = match m.get("mbt_include_rule") {
    Some(Json::String(s)) => s
    _ => abort("缺 mbt_include_rule")
  }
  assert_true(rule_path.length() > 0)
  assert_false(rule_path.contains("\\"))
}

///|
/// T0r588 锁 11：`rules` 子命令不做扩展名过滤 ⇒ 不该为它落盘放行规则
/// （少一次无用的临时文件写；也让"注入了没有"这件事只在真需要时发生）。
test "T0r588 rules 子命令不注入放行规则" {
  let j = ocr_plan(
    ".",
    subcmd="rules",
    path="src/server/ocr_scan.mbt",
    dry_run=true,
  )
  let m = match j {
    Json::Object(mm) => mm
    _ => abort("回执不是对象")
  }
  assert_eq(m.get("mbt_include"), Some(Json::boolean(false)))
  assert_eq(m.get("mbt_include_rule"), Some(Json::string("")))
}
