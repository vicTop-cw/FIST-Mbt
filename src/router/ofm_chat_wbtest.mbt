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
  assert_eq(build_ofm_chat_request_json(req).is_err(), true)
  let req2 = ofm_c_req("   ", "user", "hi")
  assert_eq(build_ofm_chat_request_json(req2).is_err(), true)
}

///|
test "ofm_c_3_messages 空即 Err" {
  let req = { model: "m", messages: [], temperature: None, max_tokens: None, }
  assert_eq(build_ofm_chat_request_json(req).is_err(), true)
}

///|
test "ofm_c_4_role 不认即 Err_不猜" {
  for role in ["tool", "function", "unknown"] {
    let req = ofm_c_req("m", role, "hi")
    assert_eq(build_ofm_chat_request_json(req).is_err(), true)
  }
  // 合法三种都要过
  for role in ["system", "user", "assistant"] {
    let req = ofm_c_req("m", role, "hi")
    assert_eq(build_ofm_chat_request_json(req).is_ok(), true)
  }
}

///|
test "ofm_c_5_content 空即 Err" {
  let req = ofm_c_req("m", "user", "")
  assert_eq(build_ofm_chat_request_json(req).is_err(), true)
  let req2 = ofm_c_req("m", "user", "   ")
  assert_eq(build_ofm_chat_request_json(req2).is_err(), true)
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
      if not(s.contains("response_format")) {
        abort("请求体应恒带 response_format：\{s}")
      }
      if not(s.contains("json_object")) {
        abort("response_format.type 应为 json_object：\{s}")
      }
    }
    Err(e) => abort("不应 Err：\{e}")
  }
}
