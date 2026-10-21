/// ofm_http_native.mbt —— native target：无 node 运行时，OFM HTTP 执行层返回明确错误。
/// 与 github_native / laya_native 同族：native 上不存在 `fetch` 能力，绝不静默返回成功。

///|
pub async fn ofm_chat_http(
  _url : String,
  _body : String,
  _timeout_ms : Int32,
) -> Result[Json, String] {
  Err(
    "ofm_chat_http 需要 js/node 运行时（fetch）；本构建为 native，请在 node 下启动 fist-mbt server",
  )
}
