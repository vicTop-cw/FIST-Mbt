///|
/// native target：agent 服务的文件系统面 —— **如实报未实现**，不静默回 OK。
///
/// 为什么必须给这一臂：`moon.pkg` 的 `supported_targets = "js+native"`，
/// 缺臂会让 native 编译直接断（`user_arg` / `cli_exit` 都是这个先例）。
/// 而**沉默回 Ok 是 R7 明令禁止的假绿**：native 下跑 `agent serve` 若回 0，
/// 人会把「这条腿根本没写」读成「worker 起来了」。所以这里一律 Err 并说明出路。
///
/// 签名与 `agent_js.mbt` 逐一对齐（同包内唯一一组 IO 接口的两个 target 实现）。
///
/// 仅 native/llvm target 编译（见 cmd/cli/moon.pkg targets 配置）。

///|
pub fn agent_io_mkdir(_dir : String) -> Result[Unit, String] {
  agent_native_unsupported()
}

///|
pub fn agent_io_write_exclusive(
  _path : String,
  _content : String,
) -> Result[Unit, String] {
  agent_native_unsupported()
}

///|
pub fn agent_io_read(_path : String) -> Result[String, String] {
  Err(agent_native_unsupported())
}

///|
pub fn agent_io_append(
  _path : String,
  _content : String,
) -> Result[Unit, String] {
  agent_native_unsupported()
}

///|
pub fn agent_io_remove(_path : String) -> Result[Unit, String] {
  agent_native_unsupported()
}

///|
pub fn agent_io_stat_mtime(_path : String) -> Double {
  -1.0
}

///|
pub fn agent_io_sleep(_ms : Double) -> Unit {
  // 不做静默空转：把「本腿不支持」变成可观测信号
  ignore(agent_native_unsupported())
}

///|
pub fn agent_io_now_ms() -> Double {
  -1.0
}

///|
pub fn agent_io_now_iso() -> String {
  ""
}

///|
pub fn agent_io_pid() -> Int32 {
  0
}

///|
fn[T] agent_native_unsupported() -> T {
  abort(
    "agent: native 目标暂未实现文件系统面（请用 js 目标：node cli.js agent …）",
  )
}
