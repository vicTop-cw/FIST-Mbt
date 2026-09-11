/// omega/omega_test.mbt — Ω 三件套（spec/gate/check）单元测试。
/// 覆盖：fnv1a64 对拍、fingerprint 对拍、schema 校验、参数化展开、
/// 8 种断言、错误路径、跑批汇总、五段式回传校验。
/// 对拍基准来自 FIST(Python) omega/spec.py 计算出的已知向量。

fn parse(s : String) -> Json {
  match parse_spec(s) {
    Ok(j) => j
    Err(e) => abort("parse failed: \{e}")
  }
}

test "fnv1a64 与 Python 版对拍一致" {
  assert_eq!(fnv1a64(""), "cbf29ce484222325")
  assert_eq!(fnv1a64("hello"), "a430d84680aabd0b")
  assert_eq!(fnv1a64("abc"), "e71fa2190541574b")
}

test "compute_fingerprint 与 Python json.dumps(sort_keys) 对拍一致" {
  let spec = parse("{\"op\":\"report\",\"version\":\"1.0\",\"definition\":{\"sig\":\"a\"},\"preconditions\":[\"x\"],\"laws\":[\"L\"],\"tests\":[{\"input\":{\"a\":\"1\"},\"expected\":\"ok\"}]}")
  let fp = compute_fingerprint(spec)
  assert_eq!(fp, "fnv1a64:dd1bc62c4d988913")
}

test "validate_schema 缺字段报错" {
  let spec = parse("{\"op\":\"report\",\"version\":\"1.0\"}")
  let errors = validate_schema(spec)
  assert_eq!(errors.length(), 5) // definition/preconditions/laws/tests/fingerprint 缺失
}

test "verify_fingerprint 匹配通过" {
  let spec = parse("{\"op\":\"report\",\"version\":\"1.0\",\"definition\":{\"sig\":\"a\"},\"preconditions\":[\"x\"],\"laws\":[\"L\"],\"tests\":[{\"input\":{\"a\":\"1\"},\"expected\":\"ok\"}],\"fingerprint\":\"fnv1a64:dd1bc62c4d988913\"}")
  match verify_fingerprint(spec) {
    Ok(_) => ()
    Err(m) => abort("应通过: \{m}")
  }
}

test "verify_fingerprint 不匹配报错" {
  let spec = parse("{\"op\":\"report\",\"version\":\"1.0\",\"definition\":{\"sig\":\"a\"},\"preconditions\":[\"x\"],\"laws\":[\"L\"],\"tests\":[{\"input\":{\"a\":\"1\"},\"expected\":\"ok\"}],\"fingerprint\":\"fnv1a64:deadbeef00000000\"}")
  match verify_fingerprint(spec) {
    Err(_) => ()
    Ok(_) => abort("应失败")
  }
}

test "expand_parameters 展开参数化用例" {
  let spec = parse("{\"op\":\"t\",\"version\":\"1.0\",\"tests\":[{\"parameters\":{\"mode\":[\"deferred\",\"immediate\"],\"days\":[1,2]},\"input\":{\"mode\":\"${mode}\",\"days\":\"${days}\"},\"expected\":\"r\"}]}")
  let exp = expand_parameters(spec)
  match exp.value("tests") {
    Some(Array(a)) => {
      assert_eq!(a.length(), 2)
      match a[0].value("input") {
        Some(Object(m)) => {
          let mode = m.get("mode")
          match mode {
            Some(String(s)) => assert_eq!(s, "deferred")
            _ => abort("mode 未展开")
          }
          let days = m.get("days")
          match days {
            Some(Number(n, ..)) => assert_eq!(n, 1.0)
            _ => abort("days 未展开")
          }
        }
        _ => abort("input 缺失")
      }
    }
    _ => abort("tests 缺失")
  }
}

test "expand_parameters 参数长度不一致时退化保留原测试" {
  let spec = parse("{\"op\":\"t\",\"version\":\"1.0\",\"tests\":[{\"parameters\":{\"mode\":[\"a\",\"b\"],\"days\":[1]},\"input\":{\"mode\":\"${mode}\"},\"expected\":\"r\"}]}")
  let exp = expand_parameters(spec)
  match exp.value("tests") {
    Some(Array(a)) => assert_eq!(a.length(), 1)
    _ => abort("tests 缺失")
  }
}

test "gate 精确相等断言" {
  let (ok, detail) = check_expected(Json::string("ok"), Json::string("ok"))
  assert_eq!(ok, true)
  check_string(detail, "精确相等")
}

test "gate approx 数值容差&field 提取" {
  // field 提取：actual 为对象，取 score 字段做 approx
  let expected = parse("{\"$assert\":\"approx\",\"field\":\"score\",\"value\":3.14,\"epsilon\":0.01}")
  let (ok, _) = check_expected(parse("{\"score\":3.141}"), expected)
  assert_eq!(ok, true)
  let (ok2, _) = check_expected(parse("{\"score\":3.2}"), expected)
  assert_eq!(ok2, false)
}

test "gate regex_lite 前中后缀匹配" {
  assert_eq!(regex_lite("OK done", "^OK"), true)
  assert_eq!(regex_lite("done OK", "^OK$"), false)
  assert_eq!(regex_lite("OK", "^OK$"), true)
  assert_eq!(regex_lite("hello world", "lo wo"), true)
  assert_eq!(regex_lite("fail", "OK"), false)
}

test "gate subset / superset 集合包含" {
  let (ok1, _) = check_expected(parse("[1,2,3]"), parse("{\"$assert\":\"subset\",\"value\":[1,2]}"))
  assert_eq!(ok1, true)
  let (ok2, _) = check_expected(parse("[1,2,3]"), parse("{\"$assert\":\"subset\",\"value\":[1,9]}"))
  assert_eq!(ok2, false)
  let (ok3, _) = check_expected(parse("[1,2]"), parse("{\"$assert\":\"superset\",\"value\":[1,2,3]}"))
  assert_eq!(ok3, true)
}

test "gate type 类型检查" {
  let (ok1, _) = check_expected(Json::number(1.0), parse("{\"$assert\":\"type\",\"value\":\"int\"}"))
  assert_eq!(ok1, true)
  let (ok2, _) = check_expected(Json::string("x"), parse("{\"$assert\":\"type\",\"value\":\"int\"}"))
  assert_eq!(ok2, false)
  let (ok3, _) = check_expected(parse("[1]"), parse("{\"$assert\":\"type\",\"value\":\"list\"}"))
  assert_eq!(ok3, true)
}

test "gate exists 存在性检查" {
  let (ok1, _) = check_expected(parse("{\"a\":1}"), parse("{\"$assert\":\"exists\",\"key\":\"a\"}"))
  assert_eq!(ok1, true)
  let (ok2, _) = check_expected(parse("{\"a\":1}"), parse("{\"$assert\":\"exists\",\"key\":\"b\"}"))
  assert_eq!(ok2, false)
  let (ok3, _) = check_expected(Json::string("hello"), parse("{\"$assert\":\"exists\",\"key\":\"ell\"}"))
  assert_eq!(ok3, true)
}

test "gate range 范围检查" {
  let (ok1, _) = check_expected(Json::number(5.0), parse("{\"$assert\":\"range\",\"min\":0,\"max\":10}"))
  assert_eq!(ok1, true)
  let (ok2, _) = check_expected(Json::number(15.0), parse("{\"$assert\":\"range\",\"min\":0,\"max\":10}"))
  assert_eq!(ok2, false)
}

test "gate run_tests 跑批 normal + error 路径" {
  let spec = parse("{\"op\":\"t\",\"version\":\"1.0\",\"tests\":[{\"input\":{\"x\":1},\"expected\":{\"$assert\":\"eq\",\"value\":1}},{\"input\":{\"x\":2},\"error\":\"boom\"}]}")
  let results = run_tests(spec, fn(input : Json) -> Result[Json, String] {
    match input.value("x") {
      Some(Number(n, ..)) if n == 1.0 => Ok(Json::number(1.0))
      _ => Err("boom: something failed")
    }
  })
  assert_eq!(results.length(), 2)
  let r0 = results[0]
  match r0.value("passed") {
    Some(True) => ()
    _ => abort("r0 passed 缺失")
  }
  let r1 = results[1]
  match r1.value("type") {
    Some(String(s)) => assert_eq!(s, "error")
    _ => abort("r1 type 缺失")
  }
  match r1.value("passed") {
    Some(True) => () // 期望 error 且错误信息包含 bom
    _ => abort("r1 passed 缺失")
  }
}

test "gate summarize 汇总准确率" {
  let results = Array::make(4, Json::object({
    "passed": @json.to_json(true),
  }))
  results[1] = Json::object({"passed": @json.to_json(false)})
  results[2] = Json::object({"passed": @json.to_json(true)})
  results[3] = Json::object({"passed": @json.to_json(true)})
  let s = summarize(results)
  match s.value("accuracy") {
    Some(Number(n, ..)) => assert_eq!(n, 75.0)
    _ => abort("accuracy 缺失")
  }
  match s.value("passed") {
    Some(Number(n, ..)) => assert_eq!(n, 3.0)
    _ => abort("passed 缺失")
  }
}

test "check_report_format 五段式校验" {
  let ok_text = "结论：完成\n证据：x\n分析：y\n缺口与风险：z\n建议入档位置：w"
  let results = check_report_format(ok_text)
  assert_eq!(results.length(), 5)
  for r in results {
    match r.value("passed") {
      Some(True) => ()
      _ => abort("passed 缺失")
    }
  }
  let bad = check_report_format("只有结论")
  match bad[1].value("passed") {
    Some(False) => ()
    _ => abort("passed 缺失")
  }
  let empty = check_report_format("   ")
  assert_eq!(empty.length(), 1)
}

fn check_string(text : String, sub : String) -> Unit {
  if !text.contains(sub) {
    abort("detail 缺 '\{sub}': \{text}")
  }
}
