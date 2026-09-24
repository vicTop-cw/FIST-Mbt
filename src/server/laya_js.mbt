///|
/// js target：laya_decide 外部决策的真实执行（node child_process spawn + stdin 喂 JSON）。
///
/// 设计要点：
///   1) spawn(cmd, args, { cwd, stdio: ['pipe','pipe','pipe'] })——可写 stdin 喂 context JSON；
///   2) 超时 kill + 兜底 resolve（JS 端永不 reject，一切异常进 JSON 字段）；
///   3) 结果 JSON.stringify 为字符串，MoonBit 侧 @json.parse 解包——与 run_check_js 惯例一致。
/// 仅 js target 编译（见 moon.pkg targets 配置，与 run_check_js 相同）。
///
/// 语义：laya_decide 是**可选**工具，sidecar 探测不到 Laya 时退出码非 0，
/// MoonBit 层按"不可用"处理并返回 available:false，绝不阻断现网功能。

///|
/// Spawn `cmd args...` in `workdir`, 向 stdin 写 input, resolve with JSON string:
/// `{ ok, code, error, stdout, stderr }`. Never rejects.
extern "js" fn js_run_laya(
  cmd : String,
  args : Array[String],
  workdir : String,
  input : String,
  timeout_ms : Int,
) -> @js_async.Promise[String] =
  #| async (cmd, args, workdir, input, timeoutMs) => {
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
  #|       child = spawn(cmd, args, { cwd: workdir || '.', stdio: ['pipe', 'pipe', 'pipe'] })
  #|     } catch (err) {
  #|       finish({ ok: false, code: -1, error: String((err && err.message) || err), stdout: '', stderr: '' })
  #|       return
  #|     }
  #|     child.stdout.on('data', (d) => { stdout += d })
  #|     child.stderr.on('data', (d) => { stderr += d })
  #|     child.on('error', (err) => {
  #|       finish({ ok: false, code: -1, error: String((err && err.message) || err), stdout: stdout, stderr: stderr })
  #|     })
  #|     // 写 stdin 后关闭，触发 sidecar 处理
  #|     child.stdin.on('error', () => {})
  #|     child.stdin.write(input)
  #|     child.stdin.end()
  #|     child.on('exit', (code) => {
  #|       const c = code === null ? -1 : code
  #|       finish({ ok: c === 0, code: c, error: c === 0 ? '' : ('exit code ' + c), stdout: stdout, stderr: stderr })
  #|     })
  #|   })
  #| }

///|
/// 真实验证 Laya 可用性（sidecar --probe）。返回 available 布尔。
pub async fn laya_probe_available(
  cmd : String,
  args : Array[String],
  workdir : String,
  timeout_ms : Int,
) -> Result[Bool, String] {
  let raw = js_run_laya(cmd, args, workdir, "", timeout_ms).wait() catch {
    _ => return Err("laya probe: 子进程调度失败（js 运行时异常）")
  }
  let parsed = @json.parse(raw) catch {
    _ => return Err("laya probe: 子进程结果 JSON 解析失败")
  }
  let code = match parsed {
    Object(m) =>
      match m.get("code") {
        Some(Number(n, ..)) => n.to_int()
        _ => -1
      }
    _ => -1
  }
  Ok(code == 0)
}

///|
/// 调用 sidecar 做决策；成功时返回 stdout 的 JSON，否则 Err。
/// 不可用不视为错误——调用方据返回的 {available:false} 降级。
pub async fn laya_decide_external(
  cmd : String,
  args : Array[String],
  workdir : String,
  input_json : String,
  timeout_ms : Int,
) -> Result[Json, String] {
  let raw = js_run_laya(cmd, args, workdir, input_json, timeout_ms).wait() catch {
    _ =>
      return Err("laya decide: 子进程调度失败（js 运行时异常）")
  }
  let payload = @json.parse(raw) catch {
    _ => return Err("laya decide: 子进程结果 JSON 解析失败")
  }
  let code = match payload {
    Object(m) =>
      match m.get("code") {
        Some(Number(n, ..)) => n.to_int()
        _ => -1
      }
    _ => -1
  }
  let stdout_str = match payload {
    Object(m) =>
      match m.get("stdout") {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
  // 解析 sidecar stdout 里的 JSON（可能混有 stderr 噪音）
  let trimmed = stdout_str.trim()
  let out : Json = @json.parse(trimmed.to_string()) catch {
    _ =>
      Json::object({
        "available": Json::boolean(false),
        "reason": Json::string("sidecar stdout 非 JSON（见 stderr）"),
      })
  }
  // 覆盖 available：退出码非 0 一律不可用
  let obj = match out {
    Object(m) => m
    _ => Map([])
  }
  obj.set("exit_code", Json::number(code.to_double()))
  if code != 0 {
    obj.set("available", Json::boolean(false))
    obj.set(
      "reason",
      Json::string(
        "laya sidecar 退出码非 0（code=\{code}）——视为不可用",
      ),
    )
  }
  Ok(Json::object(obj))
}
