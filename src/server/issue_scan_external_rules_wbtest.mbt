///|
/// issue_scan_external_rules_wbtest.mbt —— 档 2 白盒测试：外部规则文件解析/合并
/// （2026-10-13 ocr-local 融入 bugfind：rules_file 从占位变真实能力）
///
/// 覆盖六面：
///   1. 合法 JSON 解析出规则（id/severity/needle）
///   2. 非法 JSON / 缺字段 → Err
///   3. 合并同名外部覆盖内建（id 唯一、severity 取外部）
///   4. 路径防御（../、盘符、空 → Err）
///   5. 空 rules_file 走内建零回归
///   6. 真实文件加载（写 temp JSON 再读回）
fn ext_cnt_id(rs : Array[ScanRule], id : String) -> Int {
  rs.filter(fn(r : ScanRule) { r.id == id }).length()
}

///|
test "ext_rules_1_valid_parse" {
  let j = "{\"rules\":[{\"name\":\"a-rule\",\"severity\":\"error\",\"pattern\":\"foo\\\\\\\\(\",\"why\":\"w\",\"description\":\"d\"}]}"
  let r = scan_parse_external_rules(j)
  assert_true(r.is_ok())
  let rs = r.unwrap()
  assert_eq(rs.length(), 1)
  assert_eq(rs[0].id, "a-rule")
  assert_eq(rs[0].severity, "error")
  assert_true(rs[0].pattern.length() >= 1)
}

///|
test "ext_rules_2_bad_json_err" {
  assert_true(scan_parse_external_rules("{not json").is_err())
  assert_true(scan_parse_external_rules("[]").is_err())
  assert_true(scan_parse_external_rules("{\"no_rules\":1}").is_err())
  assert_true(scan_parse_external_rules("").is_err())
}

///|
test "ext_rules_3_merge_external_overrides" {
  let builtin : Array[ScanRule] = [
    { id: "x", severity: "low", pattern: ["x"], why: "b", hint: "h", },
    { id: "y", severity: "low", pattern: ["y"], why: "b", hint: "h", },
  ]
  let external : Array[ScanRule] = [
    { id: "x", severity: "high", pattern: ["X"], why: "e", hint: "he", },
    { id: "z", severity: "medium", pattern: ["Z"], why: "e", hint: "he", },
  ]
  let merged = scan_merge_rules(builtin, external)
  // 同名 x 被外部覆盖（id 唯一，severity 取外部 high）；y 保留内建；z 追加
  assert_eq(merged.length(), 3)
  assert_eq(ext_cnt_id(merged, "x"), 1)
  assert_eq(ext_cnt_id(merged, "y"), 1)
  assert_eq(ext_cnt_id(merged, "z"), 1)
  let xr = merged.filter(fn(r : ScanRule) { r.id == "x" })[0]
  assert_eq(xr.severity, "high")
  assert_eq(xr.pattern[0], "X")
}

///|
test "ext_rules_4_load_bad_path_err" {
  assert_true(scan_load_external_rules("../evil.json").is_err())
  assert_true(scan_load_external_rules("C:/x.json").is_err())
  assert_true(scan_load_external_rules("").is_err())
  assert_true(scan_load_external_rules("no_such_dir/rules.json").is_err())
}

///|
test "ext_rules_5_issue_scan_empty_rules_no_regression" {
  // 空 rules_file 走内建，与改造前行为一致：合法目录返回 Ok（不 Err）
  let r = issue_scan("temp", "", 50)
  assert_true(r.is_ok())
}

///|
test "ext_rules_6_load_real_file" {
  let p = "temp/ext_rules_real_probe.json"
  let body = "{\"rules\":[{\"name\":\"probe-r\",\"severity\":\"error\",\"pattern\":\"probe\\\\\\\\(\",\"why\":\"w\",\"description\":\"d\"}]}"
  @fs.write_string_to_file(p, body, encoding="utf8") catch {
    _ => return
  }
  let r = scan_load_external_rules(p)
  assert_true(r.is_ok())
  let rs = r.unwrap()
  assert_eq(rs.length(), 1)
  assert_eq(rs[0].id, "probe-r")
  assert_eq(rs[0].severity, "error")
}
