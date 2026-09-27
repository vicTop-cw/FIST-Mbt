///|
/// native target：GitCode HTTP 执行层 stub。
/// 纯计算层（github_gitcode.mbt）在所有 target 上都能跑（零网络零 token），
/// 但真正的 HTTP 执行需要 js/node 运行时（curl / child_process spawn）。
/// 这里照 github_native.mbt 口径：native 上不存在 spawn shell 能力，返回明确 Err。

///|
/// stub：native 上不存在执行 curl 命令的能力。
pub async fn gitcode_execute_single(
  _curl_command : String,
  _workdir : String,
  _timeout_ms : Int,
) -> Result[Json, String] {
  Err(
    "gitcode_execute_single 需要 js/node 运行时（curl）；本构建为 native，请在 node 下启动 fist-mbt server",
  )
}

///|
/// stub：native 上不存在批量执行 shell 的能力。
pub async fn gitcode_execute_batch(
  _curl_commands : Array[String],
  _workdir : String,
  _timeout_ms_each : Int,
) -> Result[Json, String] {
  Err(
    "gitcode_execute_batch 需要 js/node 运行时；本构建为 native，请在 node 下启动 fist-mbt server",
  )
}
