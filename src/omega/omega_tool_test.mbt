///|
/// omega_tool_test.mbt — omega_verify + omega_verify_fix 工具测试。
/// 覆盖：根因分类、修复策略、批量验证一票否决、修复循环。

// —— JSON 辅助：从结果 Json 中提取 ok / errors 字段 ——

fn result_ok(r : Json) -> Bool {
  match r.value("ok") {
    Some(True) => true
    _ => false
  }
}

///|
fn result_errors(r : Json) -> Array[Json] {
  match r.value("errors") {
    Some(Array(a)) => a
    _ => []
  }
}

// —— 根因分类测试 ——

///|
test "classify_root_cause struct_missing" {
  let c = classify_root_cause("缺少必填字段: op")
  assert_eq(c, ROOT_CAUSE_STRUCT_MISSING)
}

///|
test "classify_root_cause fp_mismatch" {
  let c = classify_root_cause("fingerprint 不匹配: 期望 xxx, 实际 yyy")
  assert_eq(c, ROOT_CAUSE_FP_MISMATCH)
}

///|
test "classify_root_cause format_deviation" {
  let c = classify_root_cause("精确相等: 'a' == 'b' -> false")
  assert_eq(c, ROOT_CAUSE_FORMAT_DEVIATION)
}

///|
test "classify_root_cause semantic_error" {
  let c = classify_root_cause("期望 42，实际 43；something else")
  assert_eq(c, ROOT_CAUSE_SEMANTIC_ERROR)
}

///|
test "classify_root_cause unknown" {
  let c = classify_root_cause("something completely different")
  assert_eq(c, ROOT_CAUSE_UNKNOWN)
}

// —— 修复策略测试 ——

///|
test "fix_struct_missing fills missing fields" {
  let spec = parse("{\"op\":\"t\",\"version\":\"1.0\"}")
  let fixed = fix_struct_missing(spec)
  // 所有必填字段都应存在
  let required = [
    "op", "version", "definition", "preconditions", "laws", "tests", "fingerprint",
  ]
  for field in required {
    match fixed.value(field) {
      Some(_) => ()
      None => abort("必填字段 \{field} 未被填充")
    }
  }
}

///|
test "fix_fp_mismatch recomputes fingerprint" {
  // 先构造一个 spec，指纹已知
  let spec_str = "{\"op\":\"report\",\"version\":\"1.0\",\"definition\":{\"sig\":\"a\"},\"preconditions\":[\"x\"],\"laws\":[\"L\"],\"tests\":[{\"input\":{\"a\":\"1\"},\"expected\":\"ok\"}],\"fingerprint\":\"fnv1a64:wrong0000000000\"}"
  let spec = parse(spec_str)
  let fixed = fix_fp_mismatch(spec)
  match fixed.value("fingerprint") {
    Some(String(s)) => assert_eq(s, "fnv1a64:dd1bc62c4d988913")
    _ => abort("fingerprint 未被修复")
  }
}

///|
test "fix_semantic_error marks human review" {
  let spec = parse("{\"op\":\"t\",\"tests\":[]}")
  let fixed = fix_semantic_error(spec)
  match fixed.value("_needs_human_review") {
    Some(True) => ()
    _ => abort("应标记 needs_human_review")
  }
}

///|
test "apply_fix dispatches to correct strategy" {
  let spec = parse("{\"op\":\"t\"}")
  let fixed = apply_fix(spec, ROOT_CAUSE_STRUCT_MISSING)
  // 应填充缺失字段
  match fixed.value("tests") {
    Some(_) => ()
    _ => abort("结构缺失修复未生效")
  }
}

// —— verify_single_spec 测试 ——

///|
test "verify_single_spec valid spec passes" {
  let content = "{\"op\":\"report\",\"version\":\"1.0\",\"definition\":{\"sig\":\"a\"},\"preconditions\":[\"x\"],\"laws\":[\"L\"],\"tests\":[{\"input\":{\"a\":\"1\"},\"expected\":\"ok\"}],\"fingerprint\":\"fnv1a64:dd1bc62c4d988913\"}"
  let r = verify_single_spec("test.json", content)
  assert_eq(result_ok(r), true)
  assert_eq(result_errors(r).length(), 0)
}

///|
test "verify_single_spec missing fields fails" {
  let content = "{\"op\":\"t\"}"
  let r = verify_single_spec("bad.json", content)
  assert_eq(result_ok(r), false)
  assert_eq(result_errors(r).length() > 0, true)
}

///|
test "verify_single_spec bad json fails" {
  let r = verify_single_spec("bad.json", "not json {{{")
  assert_eq(result_ok(r), false)
  assert_eq(result_errors(r).length(), 1)
}

// —— batch_verify 测试 ——

///|
test "batch_verify all passing returns 100pct no veto" {
  let specs = [
    (
      "a.json", "{\"op\":\"report\",\"version\":\"1.0\",\"definition\":{\"sig\":\"a\"},\"preconditions\":[\"x\"],\"laws\":[\"L\"],\"tests\":[{\"input\":{\"a\":\"1\"},\"expected\":\"ok\"}],\"fingerprint\":\"fnv1a64:dd1bc62c4d988913\"}",
    ),
    (
      "b.json", "{\"op\":\"report\",\"version\":\"1.0\",\"definition\":{\"sig\":\"a\"},\"preconditions\":[\"x\"],\"laws\":[\"L\"],\"tests\":[{\"input\":{\"a\":\"1\"},\"expected\":\"ok\"}],\"fingerprint\":\"fnv1a64:dd1bc62c4d988913\"}",
    ),
  ]
  let result = batch_verify(specs)
  match result.value("accuracy") {
    Some(Number(n, ..)) => assert_eq(n, 100.0)
    _ => abort("accuracy 缺失")
  }
  match result.value("veto") {
    Some(False) => ()
    _ => abort("不应一票否决")
  }
}

///|
test "batch_verify one failing triggers veto" {
  let specs = [
    (
      "a.json", "{\"op\":\"report\",\"version\":\"1.0\",\"definition\":{\"sig\":\"a\"},\"preconditions\":[\"x\"],\"laws\":[\"L\"],\"tests\":[{\"input\":{\"a\":\"1\"},\"expected\":\"ok\"}],\"fingerprint\":\"fnv1a64:dd1bc62c4d988913\"}",
    ),
    ("bad.json", "{\"op\":\"t\"}"),
  ]
  let result = batch_verify(specs)
  match result.value("accuracy") {
    Some(Number(n, ..)) => assert_eq(n, 50.0)
    _ => abort("accuracy 缺失")
  }
  match result.value("veto") {
    Some(True) => ()
    _ => abort("应一票否决")
  }
  match result.value("failed") {
    Some(Number(n, ..)) => assert_eq(n, 1.0)
    _ => abort("failed 计数缺失")
  }
}

///|
test "batch_verify empty corpus returns 0 accuracy" {
  let specs : Array[(String, String)] = []
  let result = batch_verify(specs)
  match result.value("total") {
    Some(Number(n, ..)) => assert_eq(n, 0.0)
    _ => abort("total 缺失")
  }
}

// —— batch_verify_fix 测试 ——

///|
test "batch_verify_fix empty failed returns 100pct" {
  let failed : Array[Json] = []
  let result = batch_verify_fix(failed)
  match result.value("final_accuracy") {
    Some(Number(n, ..)) => assert_eq(n, 100.0)
    _ => abort("final_accuracy 缺失")
  }
}

///|
test "batch_verify_fix semantic cause triggers human review" {
  let failed = [
    Json::object({
      "file_name": Json::string("bad.json"),
      "ok": Json::boolean(false),
      "errors": Json::array([Json::string("期望 42，实际 43")]),
    }),
  ]
  let result = batch_verify_fix(failed)
  match result.value("needs_human_review") {
    Some(Array(a)) => assert_eq(a.length(), 1)
    _ => abort("needs_human_review 缺失")
  }
}

///|
test "batch_verify_fix respects max_rounds" {
  let failed = [
    Json::object({
      "file_name": Json::string("bad.json"),
      "ok": Json::boolean(false),
      "errors": Json::array([Json::string("期望 xxx，实际 yyy")]),
    }),
  ]
  let result = batch_verify_fix(failed, max_rounds=2)
  match result.value("total_rounds") {
    Some(Number(n, ..)) => if n > 2.0 { abort("超出 max_rounds") }
    _ => ()
  }
}

// —— 常量访问辅助 ——

///|
test "root cause constants accessible" {
  assert_eq(ROOT_CAUSE_STRUCT_MISSING, "struct_missing")
  assert_eq(ROOT_CAUSE_FP_MISMATCH, "fp_mismatch")
  assert_eq(ROOT_CAUSE_FORMAT_DEVIATION, "format_deviation")
  assert_eq(ROOT_CAUSE_SEMANTIC_ERROR, "semantic_error")
  assert_eq(ROOT_CAUSE_UNKNOWN, "unknown")
}
