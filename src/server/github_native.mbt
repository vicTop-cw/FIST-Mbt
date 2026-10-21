///|
/// native target：无 node 运行时，GitHub curl 执行层返回明确错误。
/// 签名与 js 版（github_js.mbt）一致，供 server.mbt 按同一名字调用。
/// 不 abort、不假装成功——闸门宁可挡住，也不放行一个"没人真跑过"的同步。

///|
/// stub：native 上不存在 child_process spawn shell 的能力。
pub async fn github_execute_single(
  _curl_command : String,
  _workdir : String,
  _timeout_ms : Int,
) -> Result[Json, String] {
  Err(
    "github_execute_single 需要 js/node 运行时（child_process spawn curl）；本构建为 native，请在 node 下启动 fist-mbt server",
  )
}

///|
/// stub：native 上不存在批量执行 shell 的能力。
pub async fn github_execute_batch(
  _curl_commands : Array[String],
  _workdir : String,
  _timeout_ms_each : Int,
) -> Result[Json, String] {
  Err(
    "github_execute_batch 需要 js/node 运行时；本构建为 native，请在 node 下启动 fist-mbt server",
  )
}

///|
/// stub
pub async fn github_execute_close(
  _curl_command : String,
  _workdir : String,
  _timeout_ms : Int,
) -> Result[Json, String] {
  Err("github_execute_close 需要 js/node 运行时")
}

///|
/// stub
pub async fn github_execute_comment(
  _curl_command : String,
  _workdir : String,
  _timeout_ms : Int,
) -> Result[Json, String] {
  Err("github_execute_comment 需要 js/node 运行时")
}
