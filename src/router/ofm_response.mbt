/// ofm_response.mbt —— OFM chat completion 响应解析（纯计算，零 IO）。
///
/// 与 `ofm_chat.mbt` 的 `build_ofm_chat_request_json` 互补：那边 fail-closed 造请求，
/// 这边把 `{ofm_endpoint}/chat/completions` 的**回体**解成可判读结构。
///
/// 实读校正（2026-10-12 实机）：本机 OFM 上游 `/v1/chat/completions` 因上游 bug 恒回
/// **HTTP 500** `{"error":{"message":"atomcode is not defined","type":"server_error",
/// "param":null,"code":null}}`（无 key 时同路径回 **401**
/// `{"error":{"message":"missing or invalid API key","type":"invalid_request_error",...}}`）
/// ⇒ 本解析器对**错误形状**（`{"error":{message,type}}`）是用真实回体定稿的；
/// 成功形状按 OpenAI 兼容惯例**防御式**双读（`choices[0].message.content` 与
/// `choices[0].text`），上游恢复后如实测对不上再修——不留「盲写」的雷。

///|
/// 解析结果：HTTP 状态 + 是否错误 + 错误信息/类型 + 成功正文 + 原始回体。
pub struct OfmChatResponse {
  http_status : Int
  is_error : Bool
  error_message : String
  error_type : String
  content : String
  raw : String
} derive(Show, Eq, Debug)

///|
pub extend OfmChatResponse with Eq::{not_equal, equal}

///|
pub extend OfmChatResponse with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend OfmChatResponse with Show::{to_string, output}

///|
/// 从回体 + HTTP 状态构造解析结果。`body` 为空 → 视为不可判读错误（不猜成功）。
pub fn parse_ofm_chat_response(
  body : String,
  http_status : Int,
) -> OfmChatResponse {
  let body_trim = body.trim().to_owned()
  if body_trim.is_empty() {
    return {
      http_status,
      is_error: true,
      error_message: "OFM 回体为空（无法判读）",
      error_type: "empty_body",
      content: "",
      raw: body,
    }
  }
  let parsed = @json.parse(body_trim) catch { _ => Json::null() }
  match parsed {
    Json::Object(m) =>
      // 优先判错误形状：`{"error":{"message","type",...}}`
      match m.get("error") {
        Some(Json::Object(em)) =>
          {
            http_status,
            is_error: true,
            error_message: str_or(em, "message", ""),
            error_type: str_or(em, "type", ""),
            content: "",
            raw: body,
          }
        Some(_) =>
          // error 字段存在但形状不对（不是对象）→ 仍视为错误，但类型标不认识的形状
          {
            http_status,
            is_error: true,
            error_message: "OFM 回体 error 字段形状非对象",
            error_type: "bad_error_shape",
            content: "",
            raw: body,
          }
        None => parse_ofm_success(parsed, body, http_status)
      }
    Json::Null =>
      // 解析失败：@json.parse 抛错
      {
        http_status,
        is_error: true,
        error_message: "OFM 回体不是合法 JSON（可能被网关换过）",
        error_type: "unparseable",
        content: "",
        raw: body,
      }
    _ =>
      {
        http_status,
        is_error: true,
        error_message: "OFM 回体顶层不是 JSON 对象",
        error_type: "unexpected_shape",
        content: "",
        raw: body,
      }
  }
}

///|
/// 成功形状（OpenAI 兼容）防御式双读：`choices[0].message.content` → `choices[0].text` →
/// `choices[0].content`。都取不到 → 判为「形状不认识的错误」，不猜、不返回空成功。
fn parse_ofm_success(
  parsed : Json,
  body : String,
  http_status : Int,
) -> OfmChatResponse {
  let content = extract_ofm_content(parsed)
  if content.is_empty() {
    return {
      http_status,
      is_error: true,
      error_message: "OFM 成功回体缺少可判读正文（choices[0].message.content / .text 均无）",
      error_type: "unexpected_shape",
      content: "",
      raw: body,
    }
  }
  {
    http_status,
    is_error: false,
    error_message: "",
    error_type: "",
    content,
    raw: body,
  }
}

///|
/// 从 OpenAI 兼容回体里提取正文，按优先级试三种键。找不到回空串。
fn extract_ofm_content(j : Json) -> String {
  match j {
    Json::Object(m) =>
      match m.get("choices") {
        Some(Json::Array(arr)) => {
          if arr.is_empty() {
            return ""
          }
          let c0 = arr[0]
          match c0 {
            Json::Object(cm) => {
              // 1) choices[0].message.content
              let from_message = match cm.get("message") {
                Some(Json::Object(msg)) => str_or(msg, "content", "")
                _ => ""
              }
              if !from_message.is_empty() {
                return from_message
              }
              // 2) choices[0].text（部分服务走这一键）
              let from_text = str_or(cm, "text", "")
              if !from_text.is_empty() {
                return from_text
              }
              // 3) choices[0].content
              str_or(cm, "content", "")
            }
            _ => ""
          }
        }
        _ => ""
      }
    _ => ""
  }
}

///|
/// 读 Json 对象的字符串字段，缺省 `dflt`。
fn str_or(m : Map[String, Json], key : String, dflt : String) -> String {
  match m.get(key) {
    Some(Json::String(s)) => s
    _ => dflt
  }
}
