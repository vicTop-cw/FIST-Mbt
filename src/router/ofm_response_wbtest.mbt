/// ofm_response_wbtest.mbt —— P0.3 白盒锁：OFM chat 响应解析。
///
/// 锁 1/2 用的是 **2026-10-12 实机**从 `{ofm_endpoint}/chat/completions` 抓到的真实回体
/// （上游 bug 恒回 500、无 key 回 401），不是编的形状；锁 3..6 补边界。

///|
/// 真实回体：本机上游 chat 接口恒回 500（`atomcode is not defined`）。
test "ofm_r_1_真实500回体解析为上游故障" {
  let body = "{\"error\":{\"message\":\"atomcode is not defined\",\"type\":\"server_error\",\"param\":null,\"code\":null}}"
  let r = parse_ofm_chat_response(body, 500)
  assert_eq(r.is_error, true)
  assert_eq(r.error_type, "server_error")
  assert_eq(r.error_message, "atomcode is not defined")
  assert_eq(r.content, "")
}

///|
/// 真实回体：无 key 时回 401（`missing or invalid API key`）。
test "ofm_r_2_真实401回体解析为凭据错误" {
  let body = "{\"error\":{\"message\":\"missing or invalid API key\",\"type\":\"invalid_request_error\",\"param\":null,\"code\":null}}"
  let r = parse_ofm_chat_response(body, 401)
  assert_eq(r.is_error, true)
  assert_eq(r.error_type, "invalid_request_error")
  assert_eq(r.error_message, "missing or invalid API key")
}

///|
test "ofm_r_3_空回体判为不可判读错误不猜成功" {
  let r = parse_ofm_chat_response("  ", 200)
  assert_eq(r.is_error, true)
  assert_eq(r.error_type, "empty_body")
}

///|
/// 成功形状（OpenAI 兼容）：`choices[0].message.content`。
test "ofm_r_4_成功形状走 choices0.message.content" {
  let body = "{\"id\":\"x\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"你好\"}}],\"usage\":{\"total_tokens\":3}}"
  let r = parse_ofm_chat_response(body, 200)
  assert_eq(r.is_error, false)
  assert_eq(r.content, "你好")
}

///|
/// 成功形状备选：`choices[0].text`（部分服务走这一键，防御式双读）。
test "ofm_r_5_成功形状回退 choices0.text" {
  let body = "{\"choices\":[{\"index\":0,\"text\":\"Hi there\"}]}"
  let r = parse_ofm_chat_response(body, 200)
  assert_eq(r.is_error, false)
  assert_eq(r.content, "Hi there")
}

///|
/// 成功形状但没正文 → 判「形状不认识」，不返回空成功（防静默丢内容）。
test "ofm_r_6_成功形状缺正文判为错误" {
  let body = "{\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\"}}]}"
  let r = parse_ofm_chat_response(body, 200)
  assert_eq(r.is_error, true)
  assert_eq(r.error_type, "unexpected_shape")
}

///|
/// 非 JSON 回体（网关换过）→ unparseable。
test "ofm_r_7_非JSON回体判为不可解析" {
  let r = parse_ofm_chat_response("<html>502 Bad Gateway</html>", 502)
  assert_eq(r.is_error, true)
  assert_eq(r.error_type, "unparseable")
}
