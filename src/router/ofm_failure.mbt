/// ofm_failure.mbt —— P0.4 lane 失败归因（OFM 外部服务 HTTP 失败分类）
///
/// 纯计算、零 IO、零网络：给定 HTTP 状态码 + OFM/OpenAI 兼容错误体里的 `error.code`
/// 字符串，归出失败种类。**归不出来就 `Unknown`，绝不猜成某一种具体归因**——猜错归因
/// 比不归因更危险（会把凭据问题误当成上游故障，重试一万次还是 401）。
///
/// 语义对齐 OFM/OpenAI 侧错误码 + 通用 HTTP 状态语义：
///   · 401/403          → `InvalidCredential`（Bearer 无效 / 无权访问该端点）
///   · 429              → `RateLimit`（配额/频率）
///   · 5xx              → `UpstreamDown`（上游服务异常，服务端已回响但没办好）
///   · 400..499（其它） → `BadRequest`（调用方请求体问题，不归因上游）
///   · 状态码 ≤0        → `NetworkError`（连接失败/超时/DNS，**没拿到** HTTP 状态）
///   · 3xx / 状态码语义不明 → 退到 `error.code` 文本提示再试一把
///   · 2xx              → `Unknown`（成功不该进失败归因；真进来说明调用方传错）
///
/// 与 `UpstreamDown` 的区分：5xx 是「上游回话了但没办好」，`NetworkError` 是「压根没拿到
/// HTTP 响应」——P1.2 失败升级/重试时这两类值得不同对待（前者可重试、后者先查连通）。

///|
pub enum OfmFailure {
  InvalidCredential
  RateLimit
  UpstreamDown
  NetworkError
  BadRequest
  Unknown
} derive(Eq, Debug)
<<<<<<< HEAD

///|
pub extend OfmFailure with Eq::{not_equal, equal}

///|
pub extend OfmFailure with @moonbitlang/core/debug.Debug::{to_repr}
=======
>>>>>>> 2a0c0ec8 (fix(idiom): 清零 0027 derive(Show) 弃用面 4/5 条（StarVerdict 承重面留档）)

///|
pub extend OfmFailure with Eq::{not_equal, equal}

///|
pub extend OfmFailure with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub fn OfmFailure::label(self : OfmFailure) -> String {
  match self {
    InvalidCredential => "INVALID_CREDENTIAL"
    RateLimit => "RATE_LIMIT"
    UpstreamDown => "UPSTREAM_DOWN"
    NetworkError => "NETWORK_ERROR"
    BadRequest => "BAD_REQUEST"
    Unknown => "UNKNOWN"
  }
}

///|
/// 主入口：以 HTTP 状态码为主判据，`ofm_code` 只作 3xx/语义不明时的二次提示。
pub fn classify_ofm_failure(status : Int32, ofm_code : String) -> OfmFailure {
  if status >= 200 && status < 300 {
    // 成功不是失败；真进来说明调用方把 2xx 误送进归因
    Unknown
  } else if status == 401 || status == 403 {
    InvalidCredential
  } else if status == 429 {
    RateLimit
  } else if status >= 500 {
    UpstreamDown
  } else if status >= 400 {
    BadRequest
  } else if status <= 0 {
    // 没拿到 HTTP 状态（连接失败/超时/DNS）
    NetworkError
  } else {
    // 3xx 或其它语义不明的状态码：退到 error.code 文本
    classify_ofm_failure_by_code(ofm_code)
  }
}

///|
/// 仅凭 `error.code` 文本归因（状态码给不出语义时的兜底）。子串匹配大小写不敏感
/// 之外再 trim，避免服务端带尾随空白的 code 被漏判。
fn classify_ofm_failure_by_code(ofm_code : String) -> OfmFailure {
  let c = ofm_code.trim().to_owned().to_lower()
  if c.contains("invalid_api_key") ||
    c.contains("authentication") ||
    c.contains("permission") ||
    c.contains("forbidden") {
    InvalidCredential
  } else if c.contains("rate_limit") ||
    c.contains("quota") ||
    c.contains("throttl") {
    RateLimit
  } else if c.contains("upstream") ||
    c.contains("server_error") ||
    c.contains("overloaded") ||
    c.contains("unavailable") {
    UpstreamDown
  } else {
    // 无可用线索：留 Unknown，不猜
    Unknown
  }
}
