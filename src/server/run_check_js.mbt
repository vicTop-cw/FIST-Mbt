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
/// `{ ok, code, error, stdout, stderr }`. `ok` is true iff exit code == 0.
/// Never rejects: spawn error / timeout / signal kill all resolve with ok=false.
extern "js" fn js_run_command(
  cmd : String,
  args : Array[String],
  workdir : String,
  timeout_ms : Int,
) -> @js_async.Promise[String] =
  #| async (cmd, args, workdir, timeoutMs) => {
  #|   const { spawn } = await import('node:child_process')
  #|   return new Promise((resolve) => {
  #|     let stdout = ''
  #|     let stderr = ''
  #|     let settled = false
  #|     const finish = (payload) => {
  #|       if (settled) return
  #|       settled = true
  #|       clearTimeout(timer)
  #|       resolve(JSON.stringify(payload))
  #|     }
  #|     const timer = setTimeout(() => {
  #|       try { child.kill() } catch (e) {}
  #|       finish({ ok: false, code: -1, error: 'timeout after ' + timeoutMs + 'ms', stdout: stdout, stderr: stderr })
  #|     }, timeoutMs)
  #|     let child
  #|     try {
  #|       child = spawn(cmd, args, { cwd: workdir || '.', stdio: ['ignore', 'pipe', 'pipe'] })
  #|     } catch (err) {
  #|       finish({ ok: false, code: -1, error: String((err && err.message) || err), stdout: '', stderr: '' })
  #|       return
  #|     }
  #|     child.stdout.on('data', (d) => { stdout += d })
  #|     child.stderr.on('data', (d) => { stderr += d })
  #|     child.on('error', (err) => {
  #|       finish({ ok: false, code: -1, error: String((err && err.message) || err), stdout: stdout, stderr: stderr })
  #|     })
  #|     child.on('exit', (code) => {
  #|       const c = code === null ? -1 : code
  #|       finish({ ok: c === 0, code: c, error: c === 0 ? '' : ('exit code ' + c), stdout: stdout, stderr: stderr })
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
