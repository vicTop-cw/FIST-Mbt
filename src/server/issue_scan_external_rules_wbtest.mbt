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
fn ext_cnt_id(rs : Array[ScanRule], id : String) -> Int32 {
  rs.filter(fn(r : ScanRule) { r.id == id }).length()
}

///|
test "ext_rules_1_valid_parse" {
  let j = "{\"rules\":[{\"name\":\"a-rule\",\"severity\":\"error\",\"pattern\":\"foo\\\\\\\\(\",\"why\":\"w\",\"description\":\"d\"}]}"
  let r = scan_parse_external_rules(j)
  assert_true(r is Ok(_))
  let rs = r.unwrap()
  assert_eq(rs.length(), 1)
  assert_eq(rs[0].id, "a-rule")
  assert_eq(rs[0].severity, "error")
  assert_true(rs[0].pattern.length() >= 1)
}

///|
test "ext_rules_2_bad_json_err" {
  assert_true(scan_parse_external_rules("{not json") is Err(_))
  assert_true(scan_parse_external_rules("[]") is Err(_))
  assert_true(scan_parse_external_rules("{\"no_rules\":1}") is Err(_))
  assert_true(scan_parse_external_rules("") is Err(_))
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
  assert_true(scan_load_external_rules("../evil.json") is Err(_))
  assert_true(scan_load_external_rules("C:/x.json") is Err(_))
  assert_true(scan_load_external_rules("") is Err(_))
  assert_true(scan_load_external_rules("no_such_dir/rules.json") is Err(_))
}

///|
test "ext_rules_5_issue_scan_empty_rules_no_regression" {
  // 空 rules_file 走内建，与改造前行为一致：合法目录返回 Ok（不 Err）
  let r = issue_scan("temp", "", 50)
  assert_true(r is Ok(_))
}

///|
test "ext_rules_6_load_real_file" {
  let p = "temp/ext_rules_real_probe.json"
  let body = "{\"rules\":[{\"name\":\"probe-r\",\"severity\":\"error\",\"pattern\":\"probe\\\\\\\\(\",\"why\":\"w\",\"description\":\"d\"}]}"
  @fs.write_string_to_file(p, body, encoding="utf8") catch {
    _ => return
  }
  let r = scan_load_external_rules(p)
  assert_true(r is Ok(_))
  let rs = r.unwrap()
  assert_eq(rs.length(), 1)
  assert_eq(rs[0].id, "probe-r")
  assert_eq(rs[0].severity, "error")
}

///|
<<<<<<< HEAD
/// BUG-347：外部 regex pattern 的 `::` 命名空间限定必须保留进 needle。
/// 旧实现只认 alnum，把 `Json::string\(` 退化成裸 `string`（`Json::` 整段丢弃），
/// 任何含 `string` 的行都命中 ⇒ 假阳。锁四条：命名空间保留、`\s` 不污染、fixture 类零回归。
test "ext_rules_7_needle_preserves_namespace" {
  // 命名空间保留：不是旧实现的裸 "string"
  assert_eq(scan_regex_to_needle("Json::string\\("), "Json::string")
  // 带 `\s*` 也不被 `\s` 的 `s` 重新起算（旧实现这里同样产出裸 "string"）
  assert_eq(scan_regex_to_needle("Json::string\\s*\\("), "Json::string")
  // 单冒号 `:` 不是命名空间，仍当分隔：`a:bcd` 最长片段是 "bcd"（若误当命名空间会是 "a::bcd" 形，这里 a 与 bcd 断开）
  assert_eq(scan_regex_to_needle("a:bcd\\("), "bcd")
  // fixture 类零回归：纯词 + 转义括号
  assert_eq(scan_regex_to_needle("ignore\\s*\\(\\s*\\w+"), "ignore")
<<<<<<< HEAD
  assert_eq(scan_regex_to_needle("probe\\("), "probe")
=======
=======
test "ext_rules_7_qualified_needle_keeps_namespace" {
  // BUG-347：`ident::ident` 是同一个限定名，`::` 不得把片段断开后只取最长段
  assert_eq(scan_regex_to_needle("Json::string("), "Json::string")
  assert_eq(scan_regex_to_needle("Json::string\\("), "Json::string")
  assert_eq(scan_regex_to_needle("Foo::string("), "Foo::string")
  assert_eq(scan_regex_to_needle("Json::value"), "Json::value")
  assert_eq(scan_regex_to_needle("@pkg.Json::string\\("), "Json::string")
  // 无 :: 的规则零回归：仍取最长纯字母数字段
  assert_eq(scan_regex_to_needle("ignore\\s*\\(\\s*\\w+"), "ignore")
>>>>>>> 1104bb05 (fix: 外部规则 pattern 保留 :: 命名空间（BUG-347 / T0r38）)
  assert_eq(scan_regex_to_needle("string("), "string")
  // :: 右侧不是标识符时不并入同一段（`Json::(string)` 回落到括号内字面量）
  assert_eq(scan_regex_to_needle("Json::(string)"), "string")
}


///|
test "ext_rules_8_namespace_not_dropped_in_matching" {
  // BUG-347 端到端同形：外部规则 `Json::string(` 只命中真正的 Json::string( 行，
  // 不得命中 formula_to_string( / j.to_string()（旧实现 needle 降级为 "string"）。
<<<<<<< HEAD
  // BUG-346 起该规则只认实参里的拼接/插值，夹具用 `x + y` 才符合规则语义。
  let json = "{\"rules\":[{\"name\":\"moonbit-json-injection\",\"severity\":\"high\",\"pattern\":\"Json::string(\",\"why\":\"w\",\"description\":\"d\"}]}"
  let r = scan_parse_external_rules(json)
  assert_true(r is Ok(_))
  let content = "let a = Json::string(x + y)\nlet b = formula_to_string(f)\nlet c = j.to_string()\n"
=======
  let json = "{\"rules\":[{\"name\":\"moonbit-json-injection\",\"severity\":\"high\",\"pattern\":\"Json::string(\",\"why\":\"w\",\"description\":\"d\"}]}"
  let r = scan_parse_external_rules(json)
  assert_true(r is Ok(_))
  let content = "let a = Json::string(x)\nlet b = formula_to_string(f)\nlet c = j.to_string()\n"
>>>>>>> 1104bb05 (fix: 外部规则 pattern 保留 :: 命名空间（BUG-347 / T0r38）)
  let hits = scan_match_lines(content, r.unwrap(), "sample.mbt")
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].line, 1)
  // 换一个命名空间必须 0 命中：旧实现 Foo:: 与 Json:: 命中行号逐字相同
  let json_foo = "{\"rules\":[{\"name\":\"moonbit-json-injection\",\"severity\":\"high\",\"pattern\":\"Foo::string(\",\"why\":\"w\",\"description\":\"d\"}]}"
  let r2 = scan_parse_external_rules(json_foo)
  assert_true(r2 is Ok(_))
  let hits2 = scan_match_lines(content, r2.unwrap(), "sample.mbt")
  assert_eq(hits2.length(), 0)
<<<<<<< HEAD
>>>>>>> 92218ec5 (fix(issue_scan): json-injection 只认实参拼接/插值，安全构造器不再假阳（BUG-346 / T0r47）)
=======
>>>>>>> 1104bb05 (fix: 外部规则 pattern 保留 :: 命名空间（BUG-347 / T0r38）)
}
