///|
/// ofm_chat_wbtest.mbt —— P0.3 前置白盒锁：`build_ofm_chat_request_json`
///
/// 钉死的硬纪律：
///   1. **fail-closed**：model 空 / messages 空 / role 不认 / content 空 → `Err`，绝不静默回落；
///   2. 可选参数为 `None` 时**不写字段**，绝不写出显式 `null`（不少服务端把显式 null 当非法值打回）；
///   3. 输出是合法 JSON，能被 `@json.parse` 反解回同样字段。
///
/// 与 `cfg_ofm_*` / `ofm_f_*` / `ofm_m_*` 同族续编号，这里起 `ofm_c_*`。
fn ofm_c_req(model : String, role : String, content : String) -> OfmChatRequest {
  {
    model,
    messages: [{ role, content, }],
    temperature: None,
    max_tokens: None,
  }
}

///|
fn ofm_c_parse_body(out : String) -> Map[String, Json] {
  let j = @json.parse(out) catch { _ => abort("非法 JSON：\{out}") }
  match j {
    Json::Object(m) => m
    _ => abort("产出的不是 JSON 对象：\{out}")
  }
}

///|
fn ofm_c_get(m : Map[String, Json], key : String) -> Json {
  match m.get(key) {
    Some(j) => j
    None => abort("缺字段：\{key}")
  }
}

///|
test "ofm_c_1_合法请求产出可反解的 JSON" {
  let req = {
    model: "SenseNova/zen-2",
    messages: [
      { role: "system", content: "你是 FIST 指挥官", },
      { role: "user", content: "帮我拆任务", },
    ],
    temperature: Some(0.5),
    max_tokens: Some(128),
  }
  let out = build_ofm_chat_request_json(req)
  match out {
    Ok(s) => {
      let m = ofm_c_parse_body(s)
      assert_eq(ofm_c_get(m, "model").stringify(), "\"SenseNova/zen-2\"")
      // messages 是数组，长度 2
      match ofm_c_get(m, "messages") {
        Json::Array(a) => assert_eq(a.length(), 2)
        _ => abort("messages 不是数组")
      }
      assert_eq(ofm_c_get(m, "temperature").stringify(), "0.5")
      assert_eq(ofm_c_get(m, "max_tokens").stringify(), "128")
    }
    Err(e) => abort("合法请求不应 Err：\{e}")
  }
}

///|
test "ofm_c_2_model 空即 Err_fail_closed" {
  let req = ofm_c_req("", "user", "hi")
  assert_true(build_ofm_chat_request_json(req) is Err(_))
  let req2 = ofm_c_req("   ", "user", "hi")
  assert_true(build_ofm_chat_request_json(req2) is Err(_))
}

///|
test "ofm_c_3_messages 空即 Err" {
  let req = { model: "m", messages: [], temperature: None, max_tokens: None, }
  assert_true(build_ofm_chat_request_json(req) is Err(_))
}

///|
test "ofm_c_4_role 不认即 Err_不猜" {
  for role in ["tool", "function", "unknown"] {
    let req = ofm_c_req("m", role, "hi")
    assert_true(build_ofm_chat_request_json(req) is Err(_))
  }
  // 合法三种都要过
  for role in ["system", "user", "assistant"] {
    let req = ofm_c_req("m", role, "hi")
    assert_true(build_ofm_chat_request_json(req) is Ok(_))
  }
}

///|
test "ofm_c_5_content 空即 Err" {
  let req = ofm_c_req("m", "user", "")
  assert_true(build_ofm_chat_request_json(req) is Err(_))
  let req2 = ofm_c_req("m", "user", "   ")
  assert_true(build_ofm_chat_request_json(req2) is Err(_))
}

///|
test "ofm_c_6_可选参数 None 不写字段_不写显式 null" {
  let req = ofm_c_req("m", "user", "hi")
  let out = build_ofm_chat_request_json(req)
  match out {
    Ok(s) => {
      let m = ofm_c_parse_body(s)
      if m.contains("temperature") || m.contains("max_tokens") {
        abort("None 的可选参数不应出现在 JSON：\{s}")
      }
      if s.contains("null") {
        abort("不应写出显式 null：\{s}")
      }
    }
    Err(e) => abort("不应 Err：\{e}")
  }
}

///|
test "ofm_c_7_请求恒带 response_format_json_object_防信封被多行 JSON 破坏" {
  let req = ofm_c_req("m", "user", "hi")
  let out = build_ofm_chat_request_json(req)
  match out {
    Ok(s) => {
      if !s.contains("response_format") {
        abort("请求体应恒带 response_format：\{s}")
      }
      if !s.contains("json_object") {
        abort("response_format.type 应为 json_object：\{s}")
      }
    }
    Err(e) => abort("不应 Err：\{e}")
  }
}

///|
/// `ofm_reserve_max_tokens`：从硬上限预留余量，避免回体被 token 天花板截断成半截 JSON。
test "ofm_c_8_max_tokens 余量预留_不越硬上限" {
  // 100 上限留 10 → 90（严格小于硬上限，不给截断留空间）
  assert_eq(ofm_reserve_max_tokens(100, 10).unwrap(), 90)
  // 余量 0 = 满额直传（合法，调用方自己担责）
  assert_eq(ofm_reserve_max_tokens(100, 0).unwrap(), 100)
  // 余量 ≥ 上限 → 下限 1（不能写出 0 或负数）
  assert_eq(ofm_reserve_max_tokens(5, 10).unwrap(), 1)
  assert_eq(ofm_reserve_max_tokens(3, 99).unwrap(), 1)
  // 余量 1 → 恒为 上限-1，绝不等于硬上限
  assert_eq(ofm_reserve_max_tokens(2048, 1).unwrap(), 2047)
  // fail-closed：limit ≤ 0、margin < 0 → Err，不静默回落
  assert_true(ofm_reserve_max_tokens(0, 10) is Err(_))
  assert_true(ofm_reserve_max_tokens(-1, 10) is Err(_))
  assert_true(ofm_reserve_max_tokens(100, -1) is Err(_))
}

///|
/// `should_retry_on_invalid_json`：只在回体不可解析时返回 true。
test "ofm_c_9_非 JSON 回体才触发二次重试" {
  let unparseable = {
    http_status: 200,
    is_error: true,
    error_message: "不是合法 JSON",
    error_type: "unparseable",
    content: "",
    raw: "<html>502</html>",
  }
  assert_eq(should_retry_on_invalid_json(unparseable), true)
  // 其他 error_type 不触发（手动构造新结构体，不用更新语法）
  let empty = {
    http_status: 200,
    is_error: true,
    error_message: "空",
    error_type: "empty_body",
    content: "",
    raw: "",
  }
  assert_eq(should_retry_on_invalid_json(empty), false)
  let bad_shape = {
    http_status: 200,
    is_error: true,
    error_message: "形状错",
    error_type: "bad_error_shape",
    content: "",
    raw: "",
  }
  assert_eq(should_retry_on_invalid_json(bad_shape), false)
  // 成功回体不触发
  let ok = {
    http_status: 200,
    is_error: false,
    error_message: "",
    error_type: "",
    content: "hello",
    raw: "{\"choices\":[]}",
  }
  assert_eq(should_retry_on_invalid_json(ok), false)
}

///|
/// `append_retry_prompt`：在请求体 messages 末尾追加 system 提示。
test "ofm_c_10_追加重试提示到请求体" {
  let req = ofm_c_req("m", "user", "hi")
  let body = build_ofm_chat_request_json(req).unwrap()
  let new_body = append_retry_prompt(body).unwrap()
  // 新请求体仍应可解析
  let parsed = @json.parse(new_body) catch {
    _ => abort("追加后请求体不可解析")
  }
  match parsed {
    Json::Object(m) =>
      match m.get("messages") {
        Some(Json::Array(arr)) => {
          // 原 1 条 + 新 system 提示 = 2 条
          assert_eq(arr.length(), 2)
          // 最后一条是 system 提示
          match arr[1] {
            Json::Object(msg) => {
              let role = match msg.get("role") {
                Some(Json::String(s)) => s
                _ => abort("role 不是字符串")
              }
              assert_eq(role, "system")
              let content = match msg.get("content") {
                Some(Json::String(s)) => s
                _ => abort("content 不是字符串")
              }
              assert_eq(content.contains("合法 JSON"), true)
            }
            _ => abort("最后一条不是对象")
          }
        }
        _ => abort("messages 不是数组")
      }
    _ => abort("不是 JSON 对象")
  }
  // fail-closed：非法输入 → Err
  assert_true(append_retry_prompt("not json") is Err(_))
  assert_true(append_retry_prompt("{\"a\":1}") is Err(_)) // 缺少 messages
}
