///|
/// js target 的自建 stdio MCP server 循环。
///
/// colmugx/mcp 在 js target 下 StdioTransport 是 abort 占位（见
/// transport/unimplemented_js.mbt），导致 fist-mbt 无法以标准 MCP stdio
/// 协议在 node 下作为 server 启动。此处不依赖其 transport，直接：
///   1. Readable.toWeb(process.stdin) → @js_async.ReadableStream::from_js；
///   2. 逐行 read_until("\n") 得到 JSON-RPC 消息；
///   3. notification（有 method 无 id）按协议弃响应；
///   4. 其余调用公开 handle_request 得到响应字符串，写 process.stdout。
///
/// 仅 js target 编译（见 moon.pkg targets 配置）。

///|
/// Convert Node `process.stdin` to a web ReadableStream.
extern "js" fn js_stdin_web() -> @js_async.Promise[@js_async.JsReadableStream] =
  #| async () => {
  #|   const { Readable } = await import('node:stream')
  #|   return Readable.toWeb(globalThis.process.stdin)
  #| }

///|
/// Awaitable stdout write (flush-aware for pipe backpressure).
extern "js" fn js_stdout_write(s : String) -> @js_async.Promise[Unit] =
  #| async (s) => {
  #|   await new Promise((resolve) => globalThis.process.stdout.write(s + "\n", resolve))
  #| }

///|
/// A JSON-RPC message with a `method` but no `id` is a notification; the
/// receiver MUST NOT respond to it. Feeds the request path, which would
/// otherwise reject it for the missing `id`.
fn is_notification_message(message : String) -> Bool {
  let json = @json.parse(message) catch { _ => return false }
  if json is Object(obj) {
    obj.get("id") is None && obj.get("method") is Some(String(_))
  } else {
    false
  }
}

///|
async fn run_stdio_target(s1 : @mcp.MCPServer) -> Unit {
  let stdin_web = js_stdin_web().wait() catch {
    _ => {
      println("fist-mbt: cannot bridge process.stdin")
      return
    }
  }
  let rs = @js_async.ReadableStream::from_js(stdin_web)
  let reader : &@io.Reader = rs
  while true {
    let line_opt = reader.read_until("\n") catch {
      _ => break
    }
    match line_opt {
      None => break
      Some(line) => {
        let msg = line.trim().to_string()
        if msg.is_empty() {
          continue
        }
        if is_notification_message(msg) {
          continue
        }
        let resp = s1.handle_request(msg)
        if resp.is_empty() {
          continue
        }
        js_stdout_write(resp).wait() catch {
          _ => return
        }
      }
    }
  }
}
