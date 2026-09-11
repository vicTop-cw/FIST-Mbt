/// omega/spec.mbt — Ω-spec JSON 解析、schema 校验与 fingerprint 计算。
///（移植自 FIST(Python) omega/spec.py，MoonBit 原生实现，无第三方运行时依赖）
///
/// spec JSON 格式：
/// {
///   "op": "task_report",
///   "version": "1.0",
///   "definition": {"signature": "...", "note": "..."},
///   "preconditions": ["..."],
///   "laws": ["L1"],
///   "tests": [{"input": {...}, "expected": {...}}, {"input": {...}, "error": "..."}],
///   "fingerprint": "fnv1a64:xxxxxxxx"
/// }

/// FIST(Python) spec.py 的 REQUIRED_FIELDS：op/version/definition/preconditions/laws/tests/fingerprint
let required_fields : Array[String] = [
  "op", "version", "definition", "preconditions", "laws", "tests", "fingerprint",
]

/// FNV-1a 64 位哈希，返回 16 位小写十六进制字符串。
/// 哈希常量与 tnr / FIST(Python) 完全一致（0xcbf29ce484222325 / 0x100000001b3）。
/// 布尔 -> Json（core json 该版本布尔为无参构造子 True/False）
fn jbool(b : Bool) -> Json {
  if b { @json.to_json(true) } else { @json.to_json(false) }
}
pub fn fnv1a64(data : String) -> String {
  // String 内部为 UTF-16，需按 UTF-8 字节计算才能与 Python(bytes==UTF-8) 对拍
  let bytes = @utf8.encode(data)
  let mut h : UInt64 = 0xcbf29ce484222325
  for b in bytes {
    h = (h ^ b.to_uint64()) * 0x100000001b3
  }
  // 从低位到高位收集 16 个 nibble
  let nibbles : Array[Int] = []
  for _ in 0..<16 {
    nibbles.push((h & 0x0f).to_int())
    h = h >> 4
  }
  let mut out = ""
  for i in 0..<nibbles.length() {
    out = out + hex_char(nibbles[nibbles.length() - 1 - i])
  }
  out
}

fn hex_char(v : Int) -> String {
  let hex = "0123456789abcdef"
  hex[v:v + 1].to_owned()
}

/// 字典序比较（逐 code unit，短前缀在前），对齐 Python sort_keys / strcmp 语义。
/// 注意：MoonBit String 默认 Compare 为 shortlex（先比长度），不可用于 canonical 排序。
fn lex_compare(a : String, b : String) -> Int {
  let la = a.length()
  let lb = b.length()
  let n = if la < lb { la } else { lb }
  let mut i = 0
  while i < n {
    let ca = a.unsafe_get(i).to_int()
    let cb = b.unsafe_get(i).to_int()
    if ca != cb {
      return if ca < cb { -1 } else { 1 }
    }
    i = i + 1
  }
  if la < lb { -1 } else if la > lb { 1 } else { 0 }
}

/// 规范 JSON 序列化：对象键按字典序排序，用于 fingerprint 计算。
/// （与 Python json.dumps(..., sort_keys=True, ensure_ascii=False) 语义对齐；
///  非 ASCII 采用原始 UTF-8 输出。ASCII 场景与 Python 版逐字节一致。）
/// 与 Python `json.dumps(..., sort_keys=True)` 默认分隔符保持一致：
/// 键值间 ": "，元素间 ", "（canonical 对拍的前提）。
pub fn canonical_json(j : Json) -> String {
  match j {
    Object(m) => {
      let keys = m.keys().to_array()
      keys.sort_by(lex_compare)
      let parts = keys.map(fn(k) {
        Json::string(k).stringify() + ": " + canonical_json(m.get(k).unwrap_or(Json::null()))
      })
      "{" + parts.join(", ") + "}"
    }
    Array(a) => "[" + a.map(canonical_json).join(", ") + "]"
    String(s) => Json::string(s).stringify()
    Number(n, ..) => Json::number(n).stringify()
    True => "true"
    False => "false"
    Null => "null"
  }
}

fn number_text(n : Double) -> String {
  Json::number(n).stringify()
}

/// 计算 fingerprint：对除 fingerprint 外的内容做规范序列化后 fnv1a64。
pub fn compute_fingerprint(spec : Json) -> String {
  let m = match spec {
    Object(m) => m
    _ => return "fnv1a64:"
  }
  let nm : Map[String, Json] = Map([])
  for k, v in m.iter2() {
    if k != "fingerprint" {
      nm.set(k, v)
    }
  }
  "fnv1a64:" + fnv1a64(canonical_json(Json::object(nm)))
}

/// 校验 fingerprint 是否与内容匹配。
pub fn verify_fingerprint(spec : Json) -> Result[Unit, String] {
  let fp = match spec.value("fingerprint") {
    Some(String(s)) => s
    _ => return Err("缺少 fingerprint 字段")
  }
  let expected = compute_fingerprint(spec)
  if fp != expected {
    return Err("fingerprint 不匹配: 期望 \{expected}, 实际 \{fp}")
  }
  Ok(())
}

/// 从字符串解析 JSON。
pub fn parse_spec(s : String) -> Result[Json, String] {
  try {
    Ok(@json.parse(s))
  } catch {
    e => Err("JSON 解析失败: \{e}")
  }
}

/// 校验必填字段与结构，返回错误列表（空 = 通过）。
pub fn validate_schema(spec : Json) -> Array[String] {
  let errors : Array[String] = []
  if not (spec is Object(_)) {
    errors.push("spec 必须是 JSON 对象")
    return errors
  }
  for field in required_fields {
    if spec.value(field) is None {
      errors.push("缺少必填字段: \{field}")
    }
  }
  match spec.value("tests") {
    Some(Array(tests)) => {
      for i in 0..<tests.length() {
        let t = tests[i]
        if not (t is Object(_)) {
          errors.push("tests[\{i}] 必须是对象")
          continue
        }
        if t.value("input") is None {
          errors.push("tests[\{i}] 缺少 input")
        }
        let has_exp = not (t.value("expected") is None)
        let has_err = not (t.value("error") is None)
        if !has_exp && !has_err {
          errors.push("tests[\{i}] 缺少 expected 或 error")
        }
      }
    }
    Some(_) => errors.push("tests 必须是列表")
    None => ()
  }
  errors
}

/// 校验单个 spec 字符串，返回校验结果 JSON。
/// 成功：{"ok": true, "op", "version", "fingerprint", "expanded_tests"}
/// 失败：{"ok": false, "errors": [...]}
pub fn validate_spec_json(s : String) -> Result[Json, String] {
  let spec = match parse_spec(s) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let errors = validate_schema(spec)
  if errors.length() > 0 {
    return Ok(Json::object({
      "ok": @json.to_json(false),
      "errors": Json::array(errors.map(fn(e) { Json::string(e) })),
    }))
  }
  match verify_fingerprint(spec) {
    Err(msg) =>
      Ok(Json::object({
        "ok": @json.to_json(false),
        "errors": Json::array([Json::string(msg)]),
      }))
    Ok(_) => {
      let op = match spec.value("op") {
        Some(String(s)) => s
        _ => ""
      }
      let ver = match spec.value("version") {
        Some(String(s)) => s
        _ => ""
      }
      let expanded = expand_parameters(spec)
      let expanded_n = match expanded.value("tests") {
        Some(Array(a)) => a.length()
        _ => 0
      }
      Ok(Json::object({
        "ok": @json.to_json(true),
        "op": Json::string(op),
        "version": Json::string(ver),
        "fingerprint": Json::string(compute_fingerprint(spec)),
        "expanded_tests": Json::number(expanded_n.to_double()),
      }))
    }
  }
}

/// spec 校验 + 指纹 + 参数化预览的完整入口（omega_validate 工具内部复用）
pub fn validate_full(s : String) -> Json {
  match validate_spec_json(s) {
    Ok(j) => j
    Err(e) => Json::object({
      "ok": @json.to_json(false),
      "errors": Json::array([Json::string(e)]),
    })
  }
}

/// —— 参数化测试展开（一对多生成用例）——
///
/// test 含 "parameters" 字段时按笛卡尔序生成多例：
///   "parameters": {"mode": ["deferred", "immediate"], "days": [1, 2]}
/// input / expected / error 中可用 ${name} 占位符引用参数值。
/// 所有参数列表长度必须一致，否则退化保留原测试。

fn expand_value(v : Json, params : Map[String, Json]) -> Json {
  match v {
    String(s) =>
      if s.has_prefix("${") && s.has_suffix("}") && s.length() > 3 {
        let inner = s[2:s.length() - 1].to_owned()
        match params.get(inner) {
          // 整个字符串恰好是单个占位符：返回参数原生值（保持类型敏感）
          Some(pv) => if pv is String(_) {
            Json::string(replace_placeholders(s, params))
          } else {
            pv
          }
          None => Json::string(replace_placeholders(s, params))
        }
      } else {
        Json::string(replace_placeholders(s, params))
      }
    Object(m) => {
      let nm : Map[String, Json] = Map([])
      for k, v2 in m.iter2() {
        nm.set(k, expand_value(v2, params))
      }
      Json::object(nm)
    }
    Array(a) => Json::array(a.map(fn(x) { expand_value(x, params) }))
    _ => v
  }
}

fn is_placeholder_open(c : Char) -> Bool {
  c == '$'
}
fn is_brace_open(c : Char) -> Bool {
  c == '{'
}
fn is_brace_close(c : Char) -> Bool {
  c == '}'
}

fn replace_placeholders(s : String, params : Map[String, Json]) -> String {
  let mut out = ""
  let mut i = 0
  let n = s.length()
  while i < n {
    if is_placeholder_open(Int::unsafe_to_char(s[i].to_int())) && i + 2 < n &&
      is_brace_open(Int::unsafe_to_char(s[i + 1].to_int())) {
      let end = find_close(s, i + 2)
      if end >= 0 {
        let name = s[i + 2:end].to_owned()
        match params.get(name) {
          Some(pv) => {
            out = out + json_literal_text(pv)
            i = end + 1
            continue
          }
          None => ()
        }
      }
    }
    out = out + s[i:i + 1].to_owned()
    i = i + 1
  }
  out
}

/// 找到从 start 开始的第一个 '}'，返回其索引；找不到返回 -1
fn find_close(s : String, start : Int) -> Int {
  for i in start..<s.length() {
    if is_brace_close(Int::unsafe_to_char(s[i].to_int())) {
      return i
    }
  }
  -1
}

/// 将 Json 值转为文本（占位符嵌入时使用）
fn json_literal_text(v : Json) -> String {
  match v {
    String(s) => s
    True => "true"
    False => "false"
    Null => "null"
    Number(n, ..) => number_text(n)
    _ => v.stringify()
  }
}

/// 展开参数化测试，返回新 spec。无参数化时返回原 spec 引用。
pub fn expand_parameters(spec : Json) -> Json {
  let tests = match spec.value("tests") {
    Some(Array(a)) => a
    _ => return spec
  }
  let expanded : Array[Json] = []
  let mut need_replace : Bool = false
  for t in tests {
    match t.value("parameters") {
      Some(Object(pm)) if pm.length() > 0 => {
        let entries = collect_param_entries(pm)
        let counts : Array[Int] = entries.map(fn(e) { e.1.length() })
        let mut has_zero = false
        let mut uniform = true
        if counts.length() > 0 {
          let c0 = counts[0]
          for c in counts {
            if c == 0 {
              has_zero = true
            }
            if c != c0 {
              uniform = false
            }
          }
        }
        if !uniform || has_zero {
          // 参数长度不一致：退化保留原测试
          expanded.push(t)
        } else {
          let n = counts[0]
          let base = strip_parameters(t)
          for idx in 0..<n {
            let combo : Map[String, Json] = Map([])
            for pair in entries {
              let (name, vals) = pair
              combo.set(name, vals[idx])
            }
            expanded.push(expand_value(base, combo))
          }
          need_replace = true
        }
      }
      _ => expanded.push(t)
    }
  }
  if !need_replace {
    return spec
  }
  let m : Map[String, Json] = Map([])
  for k, v in (match spec { Object(x) => x; _ => return spec }).iter2() {
    m.set(k, v)
  }
  m.set("tests", Json::array(expanded))
  Json::object(m)
}

fn collect_param_entries(pm : Map[String, Json]) -> Array[(String, Array[Json])] {
  let entries : Array[(String, Array[Json])] = []
  for name, values in pm.iter2() {
    let vals : Array[Json] = match values {
      Object(vm) => {
        match vm.get("values") {
          Some(Array(a)) => a
          _ => [values]
        }
      }
      Array(a) => a
      _ => [values]
    }
    entries.push((name, vals))
  }
  entries
}

fn strip_parameters(t : Json) -> Json {
  let m : Map[String, Json] = Map([])
  for k, v in (match t { Object(x) => x; _ => return t }).iter2() {
    if k != "parameters" {
      m.set(k, v)
    }
  }
  Json::object(m)
}
