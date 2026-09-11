///|
/// native/wasm target 的 stdio 运行：直接复用 colmugx/mcp 原生 StdioTransport。
/// 仅 native+wasm 编译（见 moon.pkg targets 配置）。
async fn run_stdio_target(s1 : @mcp.MCPServer) -> Unit {
  s1.run_stdio() catch {
    e => println("fist-mbt server error: \{e}")
  }
}
