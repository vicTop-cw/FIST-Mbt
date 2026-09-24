///|
/// native target：无 node 运行时，Laya sidecar 不可用。
/// 签名与 js 版（laya_js.mbt）一致，供共享层按同一名字调用。
/// laya_decide 是**可选**工具：native 下返回 available:false（不报错、不阻断），
/// 调用方照旧走现有规则/LLM。

///|
/// native 下探测：直接返回不可用（不报 Err，让工具降级）。
pub async fn laya_probe_available(
  _cmd : String,
  _args : Array[String],
  _workdir : String,
  _timeout_ms : Int,
) -> Result[Bool, String] {
  Ok(false)
}

///|
/// native 下调用：返回 available:false 的 JSON（不报 Err）。
pub async fn laya_decide_external(
  _cmd : String,
  _args : Array[String],
  _workdir : String,
  _input_json : String,
  _timeout_ms : Int,
) -> Result[Json, String] {
  Ok(
    Json::object({
      "available": Json::boolean(false),
      "reason": Json::string(
        "laya sidecar 需要 node/js 运行时（child_process spawn）；本构建为 native，请在 node 下启动 fist-mbt server",
      ),
    }),
  )
}
