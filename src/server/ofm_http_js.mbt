/// ofm_http_js.mbt —— js target：OFM chat completion 的真实 HTTP 调用（node 24 全局 `fetch`）。
///
/// 与 GitHub 通道（`js_exec_curl` spawn curl）不同的地方：这里**不用 shell**，直接 fetch，
/// 密钥在 JS 侧读 `process.env.FIST_OFM_KEY` 塞进 `Authorization` 头 ⇒
/// 命令字符串/argv/日志里**永远不出现密钥本体**，跨平台（Windows cmd 不展开 `$VAR`）也不受影响。
/// 永不 reject：一切异常进 JSON 字段（与 github_js/laya_js 惯例一致）。

///|
/// 单次 POST chat completion。resolve with `{ ok, status, body, error }`（JSON 字符串）。
/// `status=0` 表示没拿到 HTTP 响应（网络/超时/DNS）——与「拿到响应但非 2xx」刻意区分，
/// 交给 `classify_ofm_failure` 归因（status<=0 → NetworkError）。
extern "js" fn js_ofm_chat_fetch(
  url : String,
  body : String,
  timeout_ms : Int32,
) -> @js_async.Promise[String] =
  #| async (url, body, timeoutMs) => {
  #|   const key = process.env.FIST_OFM_KEY || ''
  #|   const ctrl = new AbortController()
  #|   const timer = setTimeout(() => { try { ctrl.abort() } catch (e) {} }, timeoutMs)
  #|   try {
  #|     const resp = await fetch(url, {
  #|       method: 'POST',
  #|       headers: {
  #|         'Content-Type': 'application/json',
  #|         'Authorization': 'Bearer ' + key,
  #|       },
  #|       body: body,
  #|       signal: ctrl.signal,
  #|     })
  #|     const text = await resp.text()
  #|     const ok = resp.status >= 200 && resp.status < 300
  #|     return JSON.stringify({ ok: ok, status: resp.status, body: text, error: '' })
  #|   } catch (e) {
  #|     const msg = String((e && e.message) || e)
  #|     return JSON.stringify({ ok: false, status: 0, body: '', error: msg })
  #|   } finally {
  #|     clearTimeout(timer)
  #|   }
  #| }

///|
/// MoonBit 侧 async 包装：调 `js_ofm_chat_fetch`，返回 `{ok, status, body, error}` JSON。
pub async fn ofm_chat_http(
  url : String,
  body : String,
  timeout_ms : Int32,
) -> Result[Json, String] {
  let raw = js_ofm_chat_fetch(url, body, timeout_ms).wait() catch {
    _ => return Err("ofm_chat_http: fetch 调度失败（js 运行时异常）")
  }
  let payload = @json.parse(raw) catch {
    _ => return Err("ofm_chat_http: fetch 结果 JSON 解析失败")
  }
  Ok(payload)
}
