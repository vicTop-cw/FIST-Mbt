/// ofm_chat.mbt —— P0.3 前置：OFM OpenAI 兼容 chat 请求体构建（纯计算，零 IO 零网络）
///
/// 只把「要问什么」结构化成 OpenAI 兼容请求体 JSON 字符串。请求形状是**规范确定的**
/// （model + messages + 可选参数），无「实读校正」风险。
///
/// **响应解析刻意留到 P0.3 拿到真实样例后再定稿**（沿用计划 v2 的「实读校正」教训：
/// 盲写解析器是最容易返工的一层——真实 OFM 可能走 `choices[].message.content` 也可能走
/// `choices[].text`，凭空定死就是给自己埋雷）。
///
/// **fail-closed 校验**（与 `router_config.from_json` 同族纪律，绝不静默回落）：
///   · model trim 后为空 → `Err`
///   · messages 为空数组 → `Err`（空提问没意义，别发给上游烧钱）
///   · role 不在 {system, user, assistant} → `Err`（**不猜**未知角色）
///   · 任一 content trim 后为空 → `Err`
///
/// 可选参数纪律：`temperature`/`max_tokens` 为 `None` 时**不写进 JSON**（缺省让服务端用默认），
/// 绝不为了省字段写出 `null`（不少服务端把显式 null 当「非法值」打回）。

///|
pub struct OfmChatMessage {
  role : String // "system" | "user" | "assistant"
  content : String
} derive(Show, Eq, Debug)

///|
pub struct OfmChatRequest {
  model : String
  messages : Array[OfmChatMessage]
  temperature : Double? // None = 不传该字段
  max_tokens : Int?
} derive(Show, Eq, Debug)

///|
/// 把请求结构化成 OpenAI 兼容的 chat/completions 请求体 JSON 字符串。
pub fn build_ofm_chat_request_json(
  req : OfmChatRequest,
) -> Result[String, String] {
  let model = req.model.trim().to_owned()
  if model.is_empty() {
    return Err("model 为空")
  }
  if req.messages.is_empty() {
    return Err("messages 为空")
  }
  let msgs : Array[Json] = []
  for m in req.messages {
    let role = m.role.trim().to_owned()
    if !(role == "system" || role == "user" || role == "assistant") {
      return Err("不认识的 role：\{role}")
    }
    let content = m.content.trim().to_owned()
    if content.is_empty() {
      return Err("content 为空（role=\{role}）")
    }
    msgs.push(
      Json::object({
        "role": Json::string(role),
        "content": Json::string(content),
      }),
    )
  }
  let body = { "model": Json::string(model), "messages": Json::array(msgs) }
  match req.temperature {
    Some(t) => body.set("temperature", Json::number(t))
    None => ()
  }
  match req.max_tokens {
    Some(n) => body.set("max_tokens", Json::number(n.to_double()))
    None => ()
  }
  Ok(Json::object(body).stringify())
}

///|
/// 便捷入口（供 `src/server` 的 OFM 通道用，省去跨包构造非 pub 字段）：一条 user 提问
/// → 完整请求体 JSON。`temperature`/`max_tokens` 走 None（不写字段），fail-closed 照旧。
pub fn build_ofm_chat_request_json_simple(
  model : String,
  prompt : String,
) -> Result[String, String] {
  build_ofm_chat_request_json({
    model,
    messages: [{ role: "user", content: prompt, }],
    temperature: None,
    max_tokens: None,
  })
}
