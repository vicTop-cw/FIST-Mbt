/// omega/gate.mbt — Ω-gate 跑批验证：对 spec 的测试对批量执行断言。
///（移植自 FIST(Python) omega/gate.py。MoonBit 无内置正则，“regex”断言降级为
///  contains/前后缀 匹配，其余 7 种断言原样支持。）
///
/// evaluator 约定：evaluator(input) -> Result[Json, String]
///   Ok(value)  表示执行成功，value 为结果；
///   Err(msg)   表示执行失败，msg 为错误信息（用于 error 路径匹配）。
///
/// expected 断言对象（normal 用例）支持：
///   {"$assert":"approx",  "value":3.14, "epsilon":0.01}  数值容差
///   {"$assert":"regex",   "pattern":"^OK"}               正则降级：contains/前后缀
///   {"$assert":"subset",  "value":[...]}                 实际包含给定集合
///   {"$assert":"superset","value":[...]}                 实际被给定集合包含
///   {"$assert":"type",    "value":"int"}                 类型检查
///   {"$assert":"exists",  "key":"..."}                   key/成员/子串 存在
///   {"$assert":"range",   "min":0, "max":10}             范围检查
///   {"$assert":"eq",      "value":X}                     精确相等
/// 另支持 "field" 键：先提取 actual[field] 再断言。
/// 未含 "$assert" 的 expected 保持精确相等语义（向后兼容）。

fn json_or(v : Json?, default : Json) -> Json {
  match v {
    Some(j) => j
    None => default
  }
}

fn text_of(v : Json) -> String {
  match v {
    String(s) => s
    _ => v.stringify()
  }
}

/// 正则降级匹配：pattern 语义采用简化规则
/// - 以 ^ 开头、$ 结尾（长度>2）→ 精确相等（剥掉锚点）
/// - 以 ^ 开头 → 前缀匹配
/// - 以 $ 结尾 → 后缀匹配
/// - 否则 → 包含匹配（对应 Python re.search 的“存在即匹配”）
pub fn regex_lite(actual : String, pattern : String) -> Bool {
  if pattern.has_prefix("^") && pattern.has_suffix("$") && pattern.length() > 2 {
    return actual == pattern[1:pattern.length() - 1].to_owned()
  }
  if pattern.has_prefix("^") {
    return actual.has_prefix(pattern[1:pattern.length()].to_owned())
  }
  if pattern.has_suffix("$") {
    return actual.has_suffix(pattern[0:pattern.length() - 1].to_owned())
  }
  actual.contains(pattern)
}

fn as_number(v : Json) -> Double? {
  match v {
    Number(n, ..) => Some(n)
    _ => None
  }
}

/// 类型名映射（兼容 Python 版命名）
fn type_names(v : Json) -> Array[String] {
  match v {
    True => ["bool"]
    False => ["bool"]
    Number(_, ..) => ["number", "int", "float"]
    String(_) => ["string", "str"]
    Array(_) => ["array", "list"]
    Object(_) => ["object", "dict"]
    Null => ["null", "none"]
  }
}

fn to_elem_set(v : Json) -> Set[String] {
  let s : Set[String] = Set([])
  match v {
    Array(a) => for x in a { s.add(canonical_json(x)) }
    String(str) => for ch in str { s.add(ch.to_string()) }
    _ => ()
  }
  s
}

/// 按断言类型检查，返回 (passed, detail)。
fn check_assert(actual : Json, expected : Json) -> (Bool, String) {
  let kind = match expected.value("$assert") {
    Some(String(s)) => s
    _ => return (false, "未知断言类型")
  }
  match kind {
    "approx" => {
      let target_n = as_number(json_or(expected.value("value"), Json::null()))
      let actual_n = as_number(actual)
      let eps = match expected.value("epsilon") {
        Some(v) => match as_number(v) {
          Some(e) => e
          None => 0.000000001
        }
        None => 0.000000001
      }
      match (target_n, actual_n) {
        (Some(t), Some(a)) => {
          let diff = if a >= t { a - t } else { t - a }
          let ok = diff <= eps
          (ok, "approx: |\{a} - \{t}| = \{diff} <= \{eps} -> \{ok}")
        }
        _ => (false, "approx: 实际或目标无法转数值")
      }
    }
    "regex" => {
      let pattern = match expected.value("pattern") {
        Some(String(s)) => s
        _ => ""
      }
      let ok = regex_lite(actual.stringify(), pattern)
      (ok, "regex_lite: '\{actual.stringify()}' 匹配 '\{pattern}' -> \{ok}")
    }
    "subset" => {
      // expected ⊆ actual
      let exp = to_elem_set(json_or(expected.value("value"), Json::null()))
      let act = to_elem_set(actual)
      let missing : Array[String] = []
      exp.each(fn(e) {
        if !act.contains(e) {
          missing.push(e)
        }
      })
      let ok = missing.length() == 0
      (ok, "subset: 缺少 [\{missing.join(", ")}] -> \{ok}")
    }
    "superset" => {
      // actual ⊆ expected
      let exp = to_elem_set(json_or(expected.value("value"), Json::null()))
      let act = to_elem_set(actual)
      let extra : Array[String] = []
      act.each(fn(a) {
        if !exp.contains(a) {
          extra.push(a)
        }
      })
      let ok = extra.length() == 0
      (ok, "superset: 多余 [\{extra.join(", ")}] -> \{ok}")
    }
    "type" => {
      let want = match expected.value("value") {
        Some(String(s)) => s
        _ => match expected.value("name") {
          Some(String(s)) => s
          _ => ""
        }
      }
      let names = type_names(actual)
      let ok = names.contains(want.to_lower())
      (ok, "type: 实际 '\{actual.stringify()}' 是 [\{names.join(", ")}], 期望 \{want} -> \{ok}")
    }
    "exists" => {
      let key = match expected.value("key") {
        Some(v) => text_of(v)
        None => match expected.value("value") {
          Some(v) => text_of(v)
          None => ""
        }
      }
      let ok = exists_check(actual, key)
      (ok, "exists: key '\{key}' 存在于 '\{actual.stringify()}' -> \{ok}")
    }
    "range" => {
      let actual_n = as_number(actual)
      let lo = match expected.value("min") {
        Some(v) => as_number(v)
        None => None
      }
      let hi = match expected.value("max") {
        Some(v) => as_number(v)
        None => None
      }
      match actual_n {
        Some(v) => {
          var ok = true
          let detail : Array[String] = []
          match lo {
            Some(l) => {
              ok = ok && v >= l
              detail.push("\{v} >= \{l}")
            }
            None => ()
          }
          match hi {
            Some(h) => {
              ok = ok && v <= h
              detail.push("\{v} <= \{h}")
            }
            None => ()
          }
          (ok, "range: \{detail.join(" 且 ")} -> \{ok}")
        }
        _ => (false, "range: 实际无法转数值")
      }
    }
    "eq" => {
      let target = json_or(expected.value("value"), Json::null())
      let ok = canonical_json(actual) == canonical_json(target)
      (ok, "eq: '\{actual.stringify()}' == '\{target.stringify()}' -> \{ok}")
    }
    _ => (false, "未知断言类型 \{kind}")
  }
}

fn exists_check(actual : Json, key : String) -> Bool {
  match actual {
    Object(m) => m.contains(key)
    Array(a) => a.any(fn(x) { canonical_json(x) == canonical_json(Json::string(key)) })
    String(s) => s.contains(key)
    _ => match actual {
      Null => false
      _ => true
    }
  }
}

/// 检查实际结果是否符合期望（支持 $assert 断言对象，否则精确相等）。
pub fn check_expected(actual : Json, expected : Json) -> (Bool, String) {
  match expected {
    Object(m) if m.contains("$assert") => {
      let field = expected.value("field")
      match field {
        Some(String(f)) => {
          let sub = actual.value(f)
          match sub {
            Some(v) => {
              let (ok, detail) = check_assert(v, expected)
              (ok, "[field=\{f}] \{detail}")
            }
            None => (false, "断言字段缺失: '\{f}'（实际 \{actual.stringify()}）")
          }
        }
        _ => check_assert(actual, expected)
      }
    }
    _ => {
      let ok = canonical_json(actual) == canonical_json(expected)
      (ok, "精确相等: '\{actual.stringify()}' == '\{expected.stringify()}' -> \{ok}")
    }
  }
}

/// 对 spec 的每个测试对跑批，返回结果 JSON 数组。
/// 每个结果: {"index", "type": "normal"/"error", "passed", "detail"}
pub fn run_tests(
  spec : Json,
  evaluator : (Json) -> Result[Json, String],
) -> Array[Json] {
  let expanded = expand_parameters(spec)
  let tests = match expanded.value("tests") {
    Some(Array(a)) => a
    _ => return []
  }
  let results : Array[Json] = []
  for i in 0..<tests.length() {
    let t = tests[i]
    let input = json_or(t.value("input"), Json::null())
    let (ok, value) = match evaluator(input) {
      Ok(v) => (true, v)
      Err(e) => (false, Json::string(e))
    }
    match t.value("error") {
      Some(String(expected_err)) => {
        let value_str = text_of(value)
        let passed = (!ok) && value_str.contains(expected_err)
        results.push(Json::object({
          "index": Json::number(i.to_double()),
          "type": Json::string("error"),
          "passed": jbool(passed),
          "detail": Json::string("期望错误 '\{expected_err}'，实际: \{value_str}"),
        }))
      }
      _ => {
        let exp = json_or(t.value("expected"), Json::null())
        let (passed, detail) = check_expected(value, exp)
        results.push(Json::object({
          "index": Json::number(i.to_double()),
          "type": Json::string("normal"),
          "passed": jbool(passed),
          "detail": Json::string("期望 \{exp.stringify()}，实际: \{value.stringify()}；\{detail}"),
        }))
      }
    }
  }
  results
}

/// 汇总跑批结果：{"total", "passed", "accuracy"}
pub fn summarize(results : Array[Json]) -> Json {
  let mut passed : Int = 0
  for r in results {
    match r.value("passed") {
      Some(True) => passed = passed + 1
      _ => ()
    }
  }
  let total = results.length()
  let acc = if total > 0 {
    (passed.to_double() / total.to_double()) * 100.0
  } else {
    0.0
  }
  Json::object({
    "total": Json::number(total.to_double()),
    "passed": Json::number(passed.to_double()),
    "accuracy": Json::number(acc),
  })
}
