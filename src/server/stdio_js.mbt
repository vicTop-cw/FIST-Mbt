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
/// Write a diagnostic line to stderr.
extern "js" fn js_eprintline(s : String) =
  #| (s) => {
  #|   try {
  #|     globalThis.process.stderr.write(s + "\n")
  #|   } catch (_e) {}
  #| }

///|
/// Awaitable stdout write (flush-aware for pipe backpressure).
extern "js" fn js_stdout_write(s : String) -> @js_async.Promise[Unit] =
  #| async (s) => {
  #|   await new Promise((resolve) => globalThis.process.stdout.write(s + "\n", resolve))
  #| }

///|
/// A JSON-RPC message with a method but no id is a notification.
fn is_notification_message(message : String) -> Bool {
  let json = @json.parse(message) catch { _ => return false }
  match json {
    Object(obj) => obj.get("id") == None && obj.get("method") is Some(String(_))
    _ => false
  }
}

// ─────────────────────────────────────────────────────────────────────────
// BUG-161: MCP 2026-07-28 兼容层
// colmugx/mcp@0.17.4 移除 initialize, 强制 params._meta 三元组。
// 旧客户端 (2024-11-05) 会 -32601/32602。此处包一层 stdio 协议预处理。
// ─────────────────────────────────────────────────────────────────────────

///|
const MCP_PROTOCOL_VERSION : String = "2026-07-28"

///|
const MCP_META_PV : String = "io.modelcontextprotocol/protocolVersion"

///|
const MCP_META_CAPS : String = "io.modelcontextprotocol/clientCapabilities"

///|
const MCP_META_INFO : String = "io.modelcontextprotocol/clientInfo"

///|
const MCP_META_SERVER_INFO : String = "io.modelcontextprotocol/serverInfo"

///|
fn make_client_info_map(name : String, version : String) -> Map[String, Json] {
  let m : Map[String, Json] = Map([])
  m.set("name", Json::string(name))
  m.set("version", Json::string(version))
  m
}

///|
fn copy_map_fields(src : Map[String, Json], dst : Map[String, Json]) -> Unit {
  for (k, v) in src {
    dst.set(k, v)
  }
  ()
}

///|
fn copy_json_object_fields(obj : Json, dst : Map[String, Json]) -> Unit {
  match obj {
    Json::Object(pobj) => copy_map_fields(pobj, dst)
    _ => ()
  }
}

///|
fn build_standard_meta() -> Map[String, Json] {
  let m : Map[String, Json] = Map([])
  m.set(MCP_META_PV, Json::string(MCP_PROTOCOL_VERSION))
  m.set(MCP_META_CAPS, Json::object(Map([])))
  m.set(
    MCP_META_INFO,
    Json::object(make_client_info_map("legacy-client", "0.0.0")),
  )
  m
}

///|
fn ensure_full_meta_map(params : Json) -> Map[String, Json] {
  let new_params : Map[String, Json] = Map([])
  copy_json_object_fields(params, new_params)
  let old_meta_opt = new_params.get("_meta")
  let full_meta : Map[String, Json] = match old_meta_opt {
    Some(Json::Object(om)) => {
      // 复制旧 _meta，保留 clientInfo 细节
      let m : Map[String, Json] = Map([])
      copy_map_fields(om, m)
      m.set(MCP_META_PV, Json::string(MCP_PROTOCOL_VERSION))
      if m.get(MCP_META_CAPS) == None {
        m.set(MCP_META_CAPS, Json::object(Map([])))
      }
      if m.get(MCP_META_INFO) == None {
        m.set(
          MCP_META_INFO,
          Json::object(make_client_info_map("legacy-client", "0.0.0")),
        )
      }
      m
    }
    _ => build_standard_meta()
  }
  new_params.set("_meta", Json::object(full_meta))
  new_params
}

///|
fn compat_request(message : String) -> (String, Bool, String) {
  let j = @json.parse(message) catch { _ => return (message, false, "") }
  match j {
    Json::Object(obj) => {
      let m : Map[String, Json] = Map([])
      copy_map_fields(obj, m)
      let was_init = match m.get("method") {
        Some(Json::String(meth)) if meth == "initialize" => true
        _ => false
      }
      let orig_pv = match m.get("params") {
        Some(Json::Object(p)) =>
          match p.get("protocolVersion") {
            Some(Json::String(s)) => s
            _ => MCP_PROTOCOL_VERSION
          }
        _ => MCP_PROTOCOL_VERSION
      }
      let params_obj : Json = match m.get("params") {
        Some(p) => Json::object(ensure_full_meta_map(p))
        _ => Json::object(ensure_full_meta_map(Json::object(Map([]))))
      }
      m.set("params", params_obj)
      if was_init {
        m.set("method", Json::string("server/discover"))
      }
      (
        Json::object(m).stringify(),
        was_init,
        if was_init {
          orig_pv
        } else {
          ""
        },
      )
    }
    _ => (message, false, "")
  }
}

///|
fn compat_response(
  response : String,
  was_initialize : Bool,
  orig_pv : String,
) -> String {
  if !was_initialize {
    return response
  }
  let j = @json.parse(response) catch { _ => return response }
  match j {
    Json::Object(obj) => {
      let m : Map[String, Json] = Map([])
      copy_map_fields(obj, m)
      if m.get("error") != None {
        return response
      }
      match m.get("result") {
        Some(Json::Object(r)) => {
          let legacy : Json = build_legacy_init_response(r, orig_pv)
          m.set("result", legacy)
          Json::object(m).stringify()
        }
        _ => response
      }
    }
    _ => response
  }
}

///|
fn build_legacy_init_response(
  discover_result : Map[String, Json],
  orig_pv : String,
) -> Json {
  let server_info_map : Map[String, Json] = match discover_result.get("_meta") {
    Some(Json::Object(meta)) =>
      match meta.get(MCP_META_SERVER_INFO) {
        Some(Json::Object(si)) => si
        _ => Map([])
      }
    _ => Map([])
  }
  let legacy : Map[String, Json] = Map([])
  legacy.set("serverInfo", Json::object(server_info_map))
  legacy.set("protocolVersion", Json::string(orig_pv))
  match discover_result.get("capabilities") {
    Some(c) => legacy.set("capabilities", c)
    _ => legacy.set("capabilities", Json::object(Map([])))
  }
  Json::object(legacy)
}

///|
async fn run_stdio_target(s : @mcp.MCPServer) -> Unit {
  let s1 = try {
    embed_mcpcf_tools(s)
  } catch {
    _ => s
  }
  let stdin_web = js_stdin_web().wait() catch {
    _ => {
      js_eprintline("fist-mbt: cannot bridge process.stdin")
      return
    }
  }
  let rs = @js_async.ReadableStream::from_js(stdin_web)
  let reader : &@io.Reader = rs
  while true {
    let line_opt = reader.read_until("\n") catch { _ => break }
    match line_opt {
      None => break
      Some(line) => {
        let msg = line.trim().to_owned()
        if msg.is_empty() {
          continue
        }
        if is_notification_message(msg) {
          continue
        }
        // BUG-161 compat
        let (compat_msg, was_init, orig_pv) = compat_request(msg)
        let resp = s1.handle_request(compat_msg)
        let final_resp = compat_response(resp, was_init, orig_pv)
        if final_resp.is_empty() {
          continue
        }
        js_stdout_write(final_resp).wait() catch {
          _ => return
        }
      }
    }
  }
}
