///|
/// native/wasm target 的 stdio 运行：直接复用 colmugx/mcp 原生 StdioTransport。
/// 仅 native+wasm 编译（见 moon.pkg targets 配置）。
/// 错误不得写 stdout（stdio JSON-RPC 协议专用通道）；本 toolchain 无原生 stderr
/// 打印原语，故此处保持静默，日志由上层/运行环境兜底。
async fn run_stdio_target(s1 : @mcp.MCPServer) -> Unit {
  s1.run_stdio() catch {
    _ => ()
  }
}
