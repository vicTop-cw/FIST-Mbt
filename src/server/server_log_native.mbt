///|
/// native 目标桩（BUG-538）：落盘日志 IO 不在 native 面实现。
///
/// 为什么：MCP server 的权威运行面是 js（node，项目默认 target）；本仓 native 面
/// 本地必崩 / CI 才绿（AGENTS「native 目标构建环境要求」/ 账本 BUG-527）。
/// 本桩只保住「native 编译不被新模块破坏」，签名与 js 版（server_log_js.mbt）
/// 一致；恒 no-op 恒 false —— native 上日志就是关闭，**不假装成功**。

///|
async fn server_log_append(_path : String, _line : String) -> Bool {
  false
}

///|
/// native 无真实 OS-PID 面（server.mbt 的伪 pid 用 @env.now()，另案），日志里回 "0"。
fn server_log_pid() -> String {
  "0"
}

///|
/// native 无 node process 事件面，崩溃钩子 no-op。
fn server_log_install_crash_hooks(_path : String) -> Unit {
  ()
}
