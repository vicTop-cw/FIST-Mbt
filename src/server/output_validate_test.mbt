/// output_validate_test.mbt —— 产出物验证测试
///
/// 约定：每个用例使用独立 temp 目录，用例间互不污染、可重复运行。
/// 验收标准覆盖设计文档 5 条：产物缺失/空/invariant 通过/弱证据 fail/external artifact。

///|
/// 准备用例目录。
fn ov_dir(name : String) -> String {
  @fs.create_dir("temp") catch {
    _ => ()
  }
  let d = "temp/" + name
  @fs.create_dir(d) catch {
    _ => ()
  }
  d
}

///|
/// 写一个简单文本文件（自动确保父目录存在）。
fn ov_write(d : String, name : String, body : String) -> Unit {
  // 自动确保父目录存在（name 含 "/" 时）
  if name.contains("/") || name.contains("\\") {
    let parts = name.split("/")
    let mut cur = d
    for p in parts[0:parts.length() - 1] {
      cur = cur + "/" + p.to_string()
      @fs.create_dir(cur) catch {
        _ => ()
      }
    }
  }
  @fs.write_string_to_file(d + "/" + name, body, encoding="utf8") catch {
    _ => ()
  }
}

///|
/// 构造 artifacts 数组（内联 Json::object）。
fn ov_artifacts(paths : Array[String]) -> Array[Json] {
  paths.map(fn(p : String) { Json::object({ "path": Json::string(p) }) })
}

///|
/// 构造 external_results Json（模拟 run_check 结果）。
fn ov_ext(key : String, ok : Bool) -> Json {
  let inner : Map[String, Json] = Map([])
  inner.set("ok", Json::boolean(ok))
  inner.set("code", Json::number(if ok { 0.0 } else { 1.0 }))
  inner.set("stderr", Json::string(if ok { "" } else { "boom!" }))
  let outer : Map[String, Json] = Map([])
  outer.set(key, Json::object(inner))
  Json::object(outer)
}

///|
/// 解析 output_validate 返回 verdict。
fn ov_verdict(j : Result[Json, String]) -> String {
  match j {
    Ok(x) =>
      match x {
        Json::Object(m) =>
          match m.get("verdict") {
            Some(Json::String(s)) => s
            _ => ""
          }
        _ => ""
      }
    Err(_) => ""
  }
}

///|
/// 测试 1：产物缺失 → fail
test "ov_1_missing_file_fail" {
  let d = ov_dir("ov_c1")
  let r = output_validate(
    d,
    ov_artifacts(["nonexistent.mbt"]),
    Json::object({}),
    "",
    require_evidence=false,
  )
  assert_true(r.is_ok())
  assert_eq(ov_verdict(r), "fail")
}

///|
/// 测试 2：产物为空 → fail
test "ov_2_empty_file_fail" {
  let d = ov_dir("ov_c2")
  ov_write(d, "empty.txt", "")
  let r = output_validate(
    d,
    ov_artifacts(["empty.txt"]),
    Json::object({}),
    "",
    require_evidence=false,
  )
  assert_true(r.is_ok())
  assert_eq(ov_verdict(r), "fail")
}

///|
/// 测试 3：产物存在 + invariant 通过（contains + not_contains + min_chars）→ pass
test "ov_3_file_with_invariants_pass" {
  let d = ov_dir("ov_c3")
  ov_write(
    d, "main.mbt", "fn main() -> Int { 42 }\n// no hardcoded paths here\n",
  )
  let artifacts : Array[Json] = [
    Json::object({
      "path": Json::string("main.mbt"),
      "contains": Json::string("fn main"),
      "not_contains": Json::string("C:\\absolute"),
      "min_chars": Json::number(10.0),
    }),
  ]
  let r = output_validate(
    d,
    artifacts,
    Json::object({}),
    "",
    require_evidence=false,
  )
  assert_true(r.is_ok())
  assert_eq(ov_verdict(r), "pass")
}

///|
/// 测试 4：产物存在但 invariant 不成立（缺 contains 字符串）→ fail
test "ov_4_invariant_mismatch_fail" {
  let d = ov_dir("ov_c4")
  ov_write(d, "main.mbt", "fn helper() -> Int { 0 }\n")
  let artifacts : Array[Json] = [
    Json::object({
      "path": Json::string("main.mbt"),
      "contains": Json::string("fn main"),
    }),
  ]
  let r = output_validate(
    d,
    artifacts,
    Json::object({}),
    "",
    require_evidence=false,
  )
  assert_true(r.is_ok())
  assert_eq(ov_verdict(r), "fail")
}

///|
/// 测试 5：弱证据（仅 evidence 报告）+ require_evidence=true + 硬门全过 → fail（l4-pass-but-l1-missing）
test "ov_5_evidence_required_but_empty_fail" {
  let d = ov_dir("ov_c5")
  ov_write(d, "out.txt", "actual content here, not empty\n")
  let r = output_validate(
    d,
    ov_artifacts(["out.txt"]),
    Json::object({}),
    "",
    require_evidence=true,
  )
  assert_true(r.is_ok())
  // 硬门全过但 evidence 空 + require_evidence=true → fail
  assert_eq(ov_verdict(r), "fail")
}

///|
/// 测试 6：硬门全过 + evidence 非空 → pass（报告不是证据，但至少要有）
test "ov_6_evidence_provided_pass" {
  let d = ov_dir("ov_c6")
  ov_write(d, "out.txt", "done\n")
  let r = output_validate(
    d,
    ov_artifacts(["out.txt"]),
    Json::object({}),
    "agent 报告：已完成 out.txt 交付",
    require_evidence=true,
  )
  assert_true(r.is_ok())
  assert_eq(ov_verdict(r), "pass")
}

///|
/// 测试 7：external artifact（check_key）—— ok=true 且在 external_results 中 → pass
test "ov_7_external_artifact_ok" {
  let d = ov_dir("ov_c7")
  ov_write(d, "main.mbt", "fn main() {}\n")
  let artifacts : Array[Json] = [
    Json::object({ "path": Json::string("main.mbt") }),
    Json::object({ "check_key": Json::string("moon_test") }),
  ]
  // BUG-142：moon_test 需带汇总行（进程可能崩溃仍 exit 0，只给 ok=true 不算判绿）
  let r = output_validate(
    d,
    artifacts,
    ov_ext_stdout(
      "moon_test", true, "Total tests: 645, passed: 645, failed: 0.",
    ),
    "",
    require_evidence=false,
  )
  assert_true(r.is_ok())
  assert_eq(ov_verdict(r), "pass")
}

///|
/// 测试 8：external artifact —— ok=false → fail
test "ov_8_external_artifact_fail" {
  let d = ov_dir("ov_c8")
  ov_write(d, "main.mbt", "fn main() {}\n")
  let artifacts : Array[Json] = [
    Json::object({ "path": Json::string("main.mbt") }),
    Json::object({ "check_key": Json::string("moon_test") }),
  ]
  let r = output_validate(
    d,
    artifacts,
    ov_ext("moon_test", false),
    "",
    require_evidence=false,
  )
  assert_true(r.is_ok())
  assert_eq(ov_verdict(r), "fail")
}

///|
/// 测试 9：external artifact —— check_key 不在 external_results → fail
test "ov_9_external_missing_fail" {
  let d = ov_dir("ov_c9")
  ov_write(d, "main.mbt", "fn main() {}\n")
  let artifacts : Array[Json] = [
    Json::object({ "path": Json::string("main.mbt") }),
    Json::object({ "check_key": Json::string("moon_test") }),
  ]
  // 传空 Json：external_results 没有 moon_test
  let r = output_validate(
    d,
    artifacts,
    Json::object({}),
    "",
    require_evidence=false,
  )
  assert_true(r.is_ok())
  assert_eq(ov_verdict(r), "fail")
}

///|
/// 测试 10：artifact 数组为空 → Err（参数校验）
test "ov_10_empty_artifacts_error" {
  let r = output_validate(
    "temp",
    [],
    Json::object({}),
    "",
    require_evidence=false,
  )
  assert_true(r.is_err())
}

///|
/// 测试 11：路径非法（穿越/绝对路径）→ fail（不是 Err，会被标记 artifact 失败）
test "ov_11_illegal_path_fail" {
  let d = ov_dir("ov_c11")
  let artifacts : Array[Json] = [
    Json::object({ "path": Json::string("../escape.mbt") }),
    Json::object({ "path": Json::string("C:/hardcode.mbt") }),
  ]
  let r = output_validate(
    d,
    artifacts,
    Json::object({}),
    "",
    require_evidence=false,
  )
  assert_true(r.is_ok())
  assert_eq(ov_verdict(r), "fail")
}

///|
/// 测试 12：混合 file + external + 多产物全过 → pass
test "ov_12_mixed_all_pass" {
  let d = ov_dir("ov_c12")
  ov_write(d, "README.md", "# FIST\nDone.\n")
  ov_write(d, "main.mbt", "pub fn main() {}\n// production code\n")
  let artifacts : Array[Json] = [
    Json::object({
      "path": Json::string("README.md"),
      "contains": Json::string("FIST"),
    }),
    Json::object({
      "path": Json::string("main.mbt"),
      "contains": Json::string("pub fn main"),
      "not_contains": Json::string("panic!"),
    }),
    Json::object({ "check_key": Json::string("moon_test") }),
    Json::object({ "check_key": Json::string("issue_scan") }),
  ]
  let ext = Json::object({
    // BUG-142：moon_test 需带 stdout 汇总行
    "moon_test": Json::object({
      "ok": Json::boolean(true),
      "code": Json::number(0.0),
      "stderr": Json::string(""),
      "stdout": Json::string("Total tests: 645, passed: 645, failed: 0."),
    }),
    "issue_scan": Json::object({
      "ok": Json::boolean(true),
      "code": Json::number(0.0),
      "stderr": Json::string(""),
    }),
  })
  let r = output_validate(
    d,
    artifacts,
    ext,
    "已完成 README + main + moon_test + issue_scan",
    require_evidence=false,
  )
  assert_true(r.is_ok())
  assert_eq(ov_verdict(r), "pass")
}

///|
/// 构造带 stdout 的 external_results（模拟 run_check 有输出）。
fn ov_ext_stdout(key : String, ok : Bool, stdout : String) -> Json {
  let inner : Map[String, Json] = Map([])
  inner.set("ok", Json::boolean(ok))
  inner.set("code", Json::number(if ok { 0.0 } else { 1.0 }))
  inner.set("stderr", Json::string(""))
  inner.set("stdout", Json::string(stdout))
  let outer : Map[String, Json] = Map([])
  outer.set(key, Json::object(inner))
  Json::object(outer)
}

///|
/// 测试 13（BUG-143 / P1「Did it work?」）：ok=true 但 stdout 缺必需串 → fail
/// 场景：moon test SIGABRT 仍 exit 0（BUG-142），stdout 没有 "failed: 0"，
///      但 ok=true —— 旧实现只看 ok 会假 pass。
test "ov_13_external_ok_but_stdout_missing_contains_fail" {
  let d = ov_dir("ov_c13")
  ov_write(d, "main.mbt", "fn main() {}\n")
  let artifacts : Array[Json] = [
    Json::object({ "path": Json::string("main.mbt") }),
    Json::object({
      "check_key": Json::string("moon_test"),
      "contains": Json::string("failed: 0"),
    }),
  ]
  // ok=true 但 stdout 没有 "failed: 0"（模拟崩溃却 exit 0）
  let r = output_validate(
    d,
    artifacts,
    ov_ext_stdout("moon_test", true, "Total tests: 645, passed: 645"),
    "",
    require_evidence=false,
  )
  assert_true(r.is_ok())
  assert_eq(ov_verdict(r), "fail")
}

///|
/// 测试 14（BUG-143）：ok=true 但 stdout 含禁止串 → fail
/// 场景：stdout 残留 "SIGABRT" / "core dumped"，进程却 exit 0。
test "ov_14_external_ok_but_stdout_has_not_contains_fail" {
  let d = ov_dir("ov_c14")
  ov_write(d, "main.mbt", "fn main() {}\n")
  let artifacts : Array[Json] = [
    Json::object({ "path": Json::string("main.mbt") }),
    Json::object({
      "check_key": Json::string("moon_test"),
      "not_contains": Json::string("SIGABRT"),
    }),
  ]
  let r = output_validate(
    d,
    artifacts,
    ov_ext_stdout(
      "moon_test", true, "The test executable exited with signal: 6 (SIGABRT)\nTotal tests: 645, passed: 645, failed: 0.",
    ),
    "",
    require_evidence=false,
  )
  assert_true(r.is_ok())
  assert_eq(ov_verdict(r), "fail")
}

///|
/// 测试 15（BUG-143）：ok=true + stdout 满足 contains → pass（正样本）
test "ov_15_external_ok_and_stdout_satisfies_contains_pass" {
  let d = ov_dir("ov_c15")
  ov_write(d, "main.mbt", "fn main() {}\n")
  let artifacts : Array[Json] = [
    Json::object({ "path": Json::string("main.mbt") }),
    Json::object({
      "check_key": Json::string("moon_test"),
      "contains": Json::string("failed: 0"),
    }),
  ]
  let r = output_validate(
    d,
    artifacts,
    ov_ext_stdout(
      "moon_test", true, "Total tests: 645, passed: 645, failed: 0.",
    ),
    "",
    require_evidence=false,
  )
  assert_true(r.is_ok())
  assert_eq(ov_verdict(r), "pass")
}

///|
/// 测试 16（BUG-143）：ok=true + stdout 不满足 not_contains → pass（正样本）
test "ov_16_external_ok_and_stdout_no_forbidden_pass" {
  let d = ov_dir("ov_c16")
  ov_write(d, "main.mbt", "fn main() {}\n")
  let artifacts : Array[Json] = [
    Json::object({ "path": Json::string("main.mbt") }),
    Json::object({
      "check_key": Json::string("moon_test"),
      "not_contains": Json::string("SIGABRT"),
    }),
  ]
  let r = output_validate(
    d,
    artifacts,
    ov_ext_stdout(
      "moon_test", true, "Total tests: 645, passed: 645, failed: 0.",
    ),
    "",
    require_evidence=false,
  )
  assert_true(r.is_ok())
  assert_eq(ov_verdict(r), "pass")
}

///|
/// 测试 17（BUG-142 自动 gate）：ok=true + stdout 汇总 failed=0 且调用方未声明 contains → pass
/// 场景：调用方只传 check_key="moon_test"，不给任何 contains/not_contains——
/// 系统应**自动**解析汇总行确认 failed=0（BUG-142：不能只信 exit 0）。
test "ov_17_moon_auto_gate_failed0_pass" {
  let d = ov_dir("ov_c17")
  ov_write(d, "main.mbt", "fn main() {}\n")
  let artifacts : Array[Json] = [
    Json::object({ "path": Json::string("main.mbt") }),
    Json::object({ "check_key": Json::string("moon_test") }),
  ]
  let r = output_validate(
    d,
    artifacts,
    ov_ext_stdout(
      "moon_test", true, "Total tests: 645, passed: 645, failed: 0.",
    ),
    "",
    require_evidence=false,
  )
  assert_true(r.is_ok())
  assert_eq(ov_verdict(r), "pass")
}

///|
/// 测试 18（BUG-142 自动 gate）：ok=true + stdout 汇总 failed>0 → fail（无需显式 contains）
test "ov_18_moon_auto_gate_failed_gt0_fail" {
  let d = ov_dir("ov_c18")
  ov_write(d, "main.mbt", "fn main() {}\n")
  let artifacts : Array[Json] = [
    Json::object({ "path": Json::string("main.mbt") }),
    Json::object({ "check_key": Json::string("moon_test") }),
  ]
  let r = output_validate(
    d,
    artifacts,
    ov_ext_stdout(
      "moon_test", true, "Total tests: 645, passed: 643, failed: 2.",
    ),
    "",
    require_evidence=false,
  )
  assert_true(r.is_ok())
  assert_eq(ov_verdict(r), "fail")
}

///|
/// 测试 19（BUG-142 自动 gate）：ok=true + stdout 缺汇总行 → fail
/// 场景：进程 exit 0 但 stdout 为空或没有 Total tests（SIGABRT 可能整块吞掉 stdout）。
test "ov_19_moon_auto_gate_no_summary_fail" {
  let d = ov_dir("ov_c19")
  ov_write(d, "main.mbt", "fn main() {}\n")
  let artifacts : Array[Json] = [
    Json::object({ "path": Json::string("main.mbt") }),
    Json::object({ "check_key": Json::string("moon_test") }),
  ]
  let r = output_validate(
    d,
    artifacts,
    ov_ext_stdout("moon_test", true, "Building...\nCompiling..."),
    "",
    require_evidence=false,
  )
  assert_true(r.is_ok())
  assert_eq(ov_verdict(r), "fail")
}

///|
/// 测试 20（BUG-142 自动 gate）：key 非 moon_test 时不做自动解析（回归：不误伤其它外部检查）
test "ov_20_non_moon_key_no_auto_gate" {
  let d = ov_dir("ov_c20")
  ov_write(d, "main.mbt", "fn main() {}\n")
  let artifacts : Array[Json] = [
    Json::object({ "path": Json::string("main.mbt") }),
    Json::object({ "check_key": Json::string("linter_check") }),
  ]
  // stdout 里有 Total tests 但 key 不匹配，不应触发自动 gate
  let r = output_validate(
    d,
    artifacts,
    ov_ext_stdout(
      "linter_check", true, "Total tests: 645, passed: 643, failed: 2.",
    ),
    "",
    require_evidence=false,
  )
  assert_true(r.is_ok())
  assert_eq(ov_verdict(r), "pass")
}

///|
/// 测试 21（BUG-209 键名+值型双向防御）：min_chars 传字符串、contains 传数字
/// 都是「类型错」——键名合法但值型不符，必须 fail，不得静默降级成空 invariant。
test "ov_21_invariant_wrong_type_fail" {
  let d = ov_dir("ov_c21")
  ov_write(d, "main.mbt", "fn main() -> Int { 42 }\n")
  // min_chars 应为 Number，传 String → spec_err 应拒绝
  let a1 : Array[Json] = [
    Json::object({
      "path": Json::string("main.mbt"),
      "min_chars": Json::string("100"),
    }),
  ]
  let r1 = output_validate(d, a1, Json::object({}), "", require_evidence=false)
  assert_true(r1.is_ok())
  assert_eq(ov_verdict(r1), "fail")
  // contains 应为 String，传 Number → spec_err 应拒绝
  let a2 : Array[Json] = [
    Json::object({
      "path": Json::string("main.mbt"),
      "contains": Json::number(42.0),
    }),
  ]
  let r2 = output_validate(d, a2, Json::object({}), "", require_evidence=false)
  assert_true(r2.is_ok())
  assert_eq(ov_verdict(r2), "fail")
  // not_contains 应为 String，传 Number → spec_err 应拒绝
  let a3 : Array[Json] = [
    Json::object({
      "path": Json::string("main.mbt"),
      "not_contains": Json::number(7.0),
    }),
  ]
  let r3 = output_validate(d, a3, Json::object({}), "", require_evidence=false)
  assert_true(r3.is_ok())
  assert_eq(ov_verdict(r3), "fail")
}

///|
/// 测试 22（BUG-211 假绿另一入口）：`Total tests: 0, passed: 0, failed: 0.`
/// 是「一个测试都没跑」的空套件——旧实现只查 failed>0，把 total=0 当全绿。
/// 空包/构建漏收集/汇总被截断在 0 之前，都可能喂出这一行。
test "ov_22_moon_test_total_zero_fail" {
  let d = ov_dir("ov_c22")
  ov_write(d, "main.mbt", "fn main() {}\n")
  let artifacts : Array[Json] = [
    Json::object({ "check_key": Json::string("moon_test") }),
  ]
  // ok=true、exit 0、汇总行 failed=0 —— 但 total=0，等于没跑测试
  let r = output_validate(
    d,
    artifacts,
    ov_ext_stdout("moon_test", true, "Total tests: 0, passed: 0, failed: 0."),
    "",
    require_evidence=false,
  )
  assert_true(r.is_ok())
  assert_eq(ov_verdict(r), "fail")
}
