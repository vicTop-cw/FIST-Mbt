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
  let r = output_validate(
    d,
    artifacts,
    ov_ext("moon_test", true),
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
    "moon_test": Json::object({
      "ok": Json::boolean(true),
      "code": Json::number(0.0),
      "stderr": Json::string(""),
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
