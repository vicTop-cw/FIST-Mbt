///|
/// native target：无 node 运行时，run_check 返回明确错误。
/// 签名与 js 版（run_check_js.mbt）一致，供共享层按同一名字调用。
/// 不 abort、不假装成功——闸门宁可挡住，也不放行一个"没人真跑过"的验收。
pub async fn run_check_external(
  _cmd : String,
  _args : Array[String],
  _workdir : String,
  _timeout_ms : Int,
) -> Result[Json, String] {
  Err(
    "run_check 需要 js/node 运行时（child_process spawn）；本构建为 native，请在 node 下启动 fist-mbt server",
  )
}
