/// omega/scoring_test.mbt — scoring.mbt 的白盒测试。
/// P0 要求：≥7 测试，覆盖 coverage / fingerprint_ok / schema_ok / accuracy 分项
/// 与综合分判定。

///|
/// 构造一份合法 spec JSON 文本（可选 laws/tests，便于构造不同形状）。
fn mk_spec(laws : Array[String], tests : Json) -> String {
  let laws_arr = Json::array(laws.map(fn(x) { Json::string(x) }))
  let skeleton = Json::object({
    "op": Json::string("task_report"),
    "version": Json::string("1.0"),
    "definition": Json::object({
      "signature": Json::string("sig"),
      "note": Json::string("n"),
    }),
    "preconditions": Json::array([]),
    "laws": laws_arr,
    "tests": tests,
  })
  let fp = compute_fingerprint(skeleton)
  canonical_json(
    Json::object({
      "op": Json::string("task_report"),
      "version": Json::string("1.0"),
      "definition": Json::object({
        "signature": Json::string("sig"),
        "note": Json::string("n"),
      }),
      "preconditions": Json::array([]),
      "laws": laws_arr,
      "tests": tests,
      "fingerprint": Json::string(fp),
    }),
  )
}

///|
/// coverage 全覆盖（3 条 laws 全部被 tests 引用）→ 1.0
test "scoring_coverage_full" {
  let laws : Array[String] = ["L1", "L2", "L3"]
  let tests = Json::array([
    Json::object({ "name": Json::string("t1"), "uses": Json::string("L1") }),
    Json::object({ "name": Json::string("t2"), "uses": Json::string("L2") }),
    Json::object({ "name": Json::string("t3"), "uses": Json::string("L3") }),
  ])
  let tstr = Json::stringify(tests)
  assert_true(tstr.contains("L1"))
  let c = calc_coverage(laws, tests)
  assert_true(c == 1.0)
}

///|
/// coverage 半覆盖（1/3）→ 0.3333
test "scoring_coverage_partial" {
  let laws : Array[String] = ["L1", "L2", "L3"]
  let tests = Json::array([Json::object({ "uses": Json::string("L1") })])
  let c = calc_coverage(laws, tests)
  assert_true(c < 0.4)
  assert_true(c > 0.3)
}

///|
/// coverage laws 为空 → 1.0（无法律可覆盖）
test "scoring_coverage_empty_laws" {
  let c = calc_coverage([], Json::null())
  assert_true(c == 1.0)
}

///|
/// BUG-218：空 law 与单字符 law 不计覆盖（`contains("")` 恒真 / "a" 在任意含该字母的 test 里误匹配）。
test "scoring_coverage_short_law_skip" {
  let tests = Json::array([Json::object({ "name": Json::string("test1") })])
  // 全短 law：无可判定覆盖 → 1.0（同"无法律可覆盖"语义）
  let c_all_short = calc_coverage(["", "a", "x"], tests)
  assert_true(c_all_short == 1.0)
  // 混合：短 law 被跳过，正常 law 判覆盖
  let c_mixed = calc_coverage(["", "a", "L1"], tests)
  // 分母只算 "L1"（1 条），test 里无 "L1" → 0.0
  assert_true(c_mixed == 0.0)
  // 混合 + 命中
  let c_hit = calc_coverage(["", "a", "test1"], tests)
  // 分母只算 "test1"，test 里含 "test1" → 1.0
  assert_true(c_hit == 1.0)
}

///|
/// 全合格 spec：schema 通过 + fingerprint 通过 + 100% accuracy → score=100, pass=true
test "scoring_perfect" {
  let spec_str = mk_spec(
    ["L1"],
    Json::array([
      Json::object({
        "input": Json::string("x"),
        "expected": Json::string("ok"),
        "uses": Json::string("L1"),
      }),
    ]),
  )
  let j = spec_scoring_str(spec_str, 4, 4)

  let s = match j.value("score") {
    Some(Number(n, ..)) => n
    _ => -1.0
  }
  let pass = match j.value("pass") {
    Some(True) => true
    Some(False) => false
    _ => false
  }
  assert_eq(s, 100.0)
  assert_true(pass)
}

///|
/// fingerprint 被篡改（改了 laws）→ fingerprint_ok=false
test "scoring_bad_fingerprint" {
  let spec_str = mk_spec(
    ["L1"],
    Json::array([
      Json::object({
        "input": Json::string("x"),
        "expected": Json::string("ok"),
        "uses": Json::string("L1"),
      }),
    ]),
  )
  // 篡改：把 laws 里 L1 换成 L2，fingerprint 就失效
  let tampered = spec_str.replace(old="L1", new="L2")
  let j = spec_scoring_str(tampered, 2, 2)
  let fp_ok = match j.value("fingerprint_ok") {
    Some(True) => true
    Some(False) => false
    _ => true // 默认 true，若 false 则是真篡改
  }
  assert_true(not(fp_ok))
}

///|
/// schema 缺字段（无 definition）→ schema_ok=false
test "scoring_bad_schema" {
  let bad = Json::object({
    "op": Json::string("task_report"),
    "version": Json::string("1.0"),
    "laws": Json::array([Json::string("L1")]),
    "tests": Json::array([]),
  })
  let j = spec_scoring_str(Json::stringify(bad), 1, 1)
  let schema_ok = match j.value("schema_ok") {
    Some(True) => true
    Some(False) => false
    _ => true
  }
  assert_true(not(schema_ok))
}

///|
/// accuracy=0%（total=4, passed=0）→ accuracy=0, pass=false
test "scoring_zero_accuracy" {
  let spec_str = mk_spec(
    ["L1"],
    Json::array([
      Json::object({
        "input": Json::string("x"),
        "expected": Json::string("ok"),
        "uses": Json::string("L1"),
      }),
    ]),
  )
  let j = spec_scoring_str(spec_str, 4, 0)
  let acc = match j.value("accuracy") {
    Some(Number(n, ..)) => n
    _ => -1.0
  }
  let pass = match j.value("pass") {
    Some(True) => true
    Some(False) => false
    _ => true
  }
  assert_true(acc == 0.0)
  assert_true(not(pass))
}

///|
/// 非法 JSON 字符串 → fail-closed（score=0, pass=false），不 panic
test "scoring_bad_json_no_panic" {
  let j = spec_scoring_str("not json{", 1, 1)
  let score = match j.value("score") {
    Some(Number(n, ..)) => n
    _ => -1.0
  }
  let pass = match j.value("pass") {
    Some(True) => true
    Some(False) => false
    _ => true
  }
  assert_true(score == 0.0)
  assert_true(not(pass))
}

///|
/// total=0（未跑批）→ accuracy=0，不 panic
test "scoring_no_batch_no_panic" {
  let spec_str = mk_spec(["L1"], Json::array([]))
  let j = spec_scoring_str(spec_str, 0, 0)
  let acc = match j.value("accuracy") {
    Some(Number(n, ..)) => n
    _ => -1.0
  }
  assert_true(acc == 0.0)
}
