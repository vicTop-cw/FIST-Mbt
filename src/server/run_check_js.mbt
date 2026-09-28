///|
/// js target：run_check 外部判据命令的真实执行（node child_process spawn）。
///
/// 设计要点：
///   1) spawn(cmd, args, { cwd, stdio: ['ignore','pipe','pipe'] })——不继承 stdin；
///   2) 超时 kill + 兜底 resolve（JS 端永不 reject，一切异常都进 JSON 字段）；
///   3) 结果 JSON.stringify 为字符串，MoonBit 侧 @json.parse 解包——与
///      stdio_js.mbt 的 JSON 桥接惯例一致。
/// 仅 js target 编译（见 moon.pkg targets 配置）。

///|
/// Spawn `cmd args...` in `workdir`, resolve with a JSON string:
/// `{ ok, code, error, stdout, stderr, stdout_capped, stderr_capped }`.
/// `ok` is true iff exit code == 0.
/// Never rejects: spawn error / timeout / signal kill all resolve with ok=false.
///
/// BUG-91：`stdout += d` 过去**不设上限**——2026-09-28 用安装版跑全工具巡回到第 30 个
/// （`run_check cmd=python args=[]`，Windows 的 python 在无 tty 时把 _pyrepl 回溯刷个没完）
/// 把 server 进程堆吃到 4 GB ⇒ `FATAL ERROR: Ineffective mark-compacts near heap limit`
/// ⇒ 整个 MCP 会话死掉，巡回后半截 94 个工具其实一次都没打到（上一版把它们全记成 broken）。
/// 一个"任意客户端可调"的工具能一条命令打死服务面，这就是白名单之外缺的那一层：**输出上限**。
/// 每流各留末 1 MiB（判据回执只回末 2000 字符，1 MiB 是给 specs 表复核用的余量），
/// 并如实带 `stdout_capped`/`stderr_capped` 旗——截断必须可见，不能伪装成完整。
extern "js" fn js_run_command(
  cmd : String,
  args : Array[String],
  workdir : String,
  timeout_ms : Int,
) -> @js_async.Promise[String] =
  #| async (cmd, args, workdir, timeoutMs) => {
  #|   const { spawn } = await import('node:child_process')
  #|   return new Promise((resolve) => {
  #|     const MAX_BYTES = 1048576
  #|     let stdout = ''
  #|     let stderr = ''
  #|     let stdoutCapped = false
  #|     let stderrCapped = false
  #|     // 只保尾巴：反复 slice 会把 O(n) 变成 O(n/chunk)，1 MiB 上限下可接受
  #|     const push = (prev, chunk, capped) => {
  #|       let s = prev + chunk.toString('utf8')
  #|       if (s.length > MAX_BYTES) { s = s.slice(s.length - MAX_BYTES); return [s, true] }
  #|       return [s, capped]
  #|     }
  #|     const settledRef = { v: false }
  #|     const finish = (payload) => {
  #|       if (settledRef.v) return
  #|       settledRef.v = true
  #|       clearTimeout(timer)
  #|       resolve(JSON.stringify(payload))
  #|     }
  #|     const snapshot = (ok, code, error) => ({
  #|       ok, code, error,
  #|       stdout, stderr,
  #|       stdout_capped: stdoutCapped,
  #|       stderr_capped: stderrCapped,
  #|     })
  #|     const timer = setTimeout(() => {
  #|       try { child.kill() } catch (e) {}
  #|       finish(snapshot(false, -1, 'timeout after ' + timeoutMs + 'ms'))
  #|     }, timeoutMs)
  #|     let child
  #|     try {
  #|       child = spawn(cmd, args, { cwd: workdir || '.', stdio: ['ignore', 'pipe', 'pipe'] })
  #|     } catch (err) {
  #|       finish({ ok: false, code: -1, error: String((err && err.message) || err), stdout: '', stderr: '', stdout_capped: false, stderr_capped: false })
  #|       return
  #|     }
  #|     child.stdout.on('data', (d) => { const r = push(stdout, d, stdoutCapped); stdout = r[0]; stdoutCapped = r[1] })
  #|     child.stderr.on('data', (d) => { const r = push(stderr, d, stderrCapped); stderr = r[0]; stderrCapped = r[1] })
  #|     child.on('error', (err) => {
  #|       finish(snapshot(false, -1, String((err && err.message) || err)))
  #|     })
  #|     child.on('exit', (code) => {
  #|       const c = code === null ? -1 : code
  #|       finish(snapshot(c === 0, c, c === 0 ? '' : ('exit code ' + c)))
  #|     })
  #|   })
  #| }

///|
/// 真实执行外部命令并返回结果 JSON（ok/code/error/stdout/stderr）。
/// 签名与 native 桩（run_check_native.mbt）一致，供共享层按同一名字调用。
/// 永不 abort：调度失败、结果解析失败均以 Err 返回。
pub async fn run_check_external(
  cmd : String,
  args : Array[String],
  workdir : String,
  timeout_ms : Int,
) -> Result[Json, String] {
  let raw = js_run_command(cmd, args, workdir, timeout_ms).wait() catch {
    _ => return Err("run_check: 子进程调度失败（js 运行时异常）")
  }
  let parsed = @json.parse(raw) catch {
    _ => return Err("run_check: 子进程结果 JSON 解析失败")
  }
  Ok(parsed)
}
