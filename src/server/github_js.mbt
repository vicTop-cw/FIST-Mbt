///|
/// js target：GitHub issue API 的真实 HTTP 调用（node child_process spawn shell 执行 curl）。
///
/// 设计要点：
///   1) 完整 curl 命令字符串（shell_quote 已由 github_sync.mbt 生成）→
///      spawn('sh', ['-c', cmd]) 或 Windows 上 spawn(process.env.ComSpec, ['/c', cmd])；
///   2) 超时 kill + 兜底 resolve（JS 端永不 reject，一切异常进 JSON 字段）；
///   3) 结果 JSON.stringify 为字符串，MoonBit 侧 @json.parse 解包——与 run_check_js/laya_js 惯例一致。
/// 仅 js target 编译（见 moon.pkg targets 配置）。

///|
/// 跨平台 shell 执行：单条 curl 命令。
/// cmd_args 是完整 shell 命令字符串（已带 quotes / env var）。
/// resolve with `{ ok, code, error, stdout, stderr }`. Never rejects.
extern "js" fn js_exec_curl(
  cmd_args : String,
  workdir : String,
  timeout_ms : Int,
) -> @js_async.Promise[String] =
  #| async (cmdArgs, workdir, timeoutMs) => {
  #|   const { spawn } = await import('node:child_process')
  #|   const isWin = process.platform === 'win32'
  #|   const shCmd = isWin ? (process.env.ComSpec || 'cmd.exe') : 'sh'
  #|   const shArgs = isWin ? ['/c', cmdArgs] : ['-c', cmdArgs]
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
  #|       child = spawn(shCmd, shArgs, { cwd: workdir || '.', stdio: ['ignore', 'pipe', 'pipe'] })
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
/// 串行执行多条 curl 命令，返回 batch JSON：
/// `{ results: [{ok, code, stdout, stderr, error}], total: N, succeeded: N }`.
/// 永不 reject：单条失败不阻断后续，全部收集进 results。
extern "js" fn js_exec_batch_curl(
  commands : Array[String],
  workdir : String,
  timeout_ms_each : Int,
) -> @js_async.Promise[String] =
  #| async (cmds, workdir, timeoutMs) => {
  #|   const { spawn } = await import('node:child_process')
  #|   const isWin = process.platform === 'win32'
  #|   const shCmd = isWin ? (process.env.ComSpec || 'cmd.exe') : 'sh'
  #|   const results = []
  #|   let succeeded = 0
  #|   for (const cmdArgs of cmds) {
  #|     const shArgs = isWin ? ['/c', cmdArgs] : ['-c', cmdArgs]
  #|     const r = await new Promise((resolve) => {
  #|       let stdout = ''
  #|       let stderr = ''
  #|       let settled = false
  #|       const finish = (payload) => {
  #|         if (settled) return
  #|         settled = true
  #|         clearTimeout(timer)
  #|         resolve(payload)
  #|       }
  #|       const timer = setTimeout(() => {
  #|         try { child.kill() } catch (e) {}
  #|         finish({ ok: false, code: -1, error: 'timeout after ' + timeoutMs + 'ms', stdout: stdout, stderr: stderr })
  #|       }, timeoutMs)
  #|       let child
  #|       try {
  #|         child = spawn(shCmd, shArgs, { cwd: workdir || '.', stdio: ['ignore', 'pipe', 'pipe'] })
  #|       } catch (err) {
  #|         finish({ ok: false, code: -1, error: String((err && err.message) || err), stdout: '', stderr: '' })
  #|         return
  #|       }
  #|       child.stdout.on('data', (d) => { stdout += d })
  #|       child.stderr.on('data', (d) => { stderr += d })
  #|       child.on('error', (err) => {
  #|         finish({ ok: false, code: -1, error: String((err && err.message) || err), stdout: stdout, stderr: stderr })
  #|       })
  #|       child.on('exit', (code) => {
  #|         const c = code === null ? -1 : code
  #|         finish({ ok: c === 0, code: c, error: c === 0 ? '' : ('exit code ' + c), stdout: stdout, stderr: stderr })
  #|       })
  #|     })
  #|     if (r.ok) succeeded++
  #|     results.push(r)
  #|   }
  #|   return JSON.stringify({ results, total: cmds.length, succeeded })
  #| }

// ===== MoonBit 侧 async 包装函数 =====

///|
/// 解析单条 curl 返回 JSON，提取 GitHub issue number（从 stdout 解析 GitHub API 返回的 JSON 对象里的 `number` 字段）。
/// 成功时返回 Ok({ ok, code, issue_number?, stdout, stderr })；
/// 失败时 ok=false 或 JSON 解析失败时 issue_number=null。
pub async fn github_execute_single(
  curl_command : String,
  workdir : String,
  timeout_ms : Int,
) -> Result[Json, String] {
  let raw = js_exec_curl(curl_command, workdir, timeout_ms).wait() catch {
    _ =>
      return Err(
        "github_execute_single: 子进程调度失败（js 运行时异常）",
      )
  }
  let payload = @json.parse(raw) catch {
    _ => return Err("github_execute_single: 子进程结果 JSON 解析失败")
  }
  let ok = match payload {
    Object(m) =>
      match m.get("ok") {
        Some(True) => true
        Some(False) => false
        _ => false
      }
    _ => false
  }
  let stdout_str = match payload {
    Object(m) =>
      match m.get("stdout") {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
  // 尝试从 stdout 解析 GitHub API 返回的 JSON，提取 issue number
  let mut issue_number : Json = Json::null()
  if ok && !stdout_str.trim().is_empty() {
    let inner = @json.parse(stdout_str.trim().to_owned()) catch {
      _ => Json::null()
    }
    match inner {
      Object(im) =>
        match im.get("number") {
          Some(Number(n, ..)) => issue_number = Json::number(n)
          _ => ()
        }
      _ => ()
    }
  }
  let code = match payload {
    Object(m) =>
      match m.get("code") {
        Some(Number(n, ..)) => n.to_int()
        _ => -1
      }
    _ => -1
  }
  let stderr_str = match payload {
    Object(m) =>
      match m.get("stderr") {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
  let err_str = match payload {
    Object(m) =>
      match m.get("error") {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
  let mm : Map[String, Json] = Map([])
  mm.set("ok", Json::boolean(ok))
  mm.set("code", Json::number(code.to_double()))
  mm.set("issue_number", issue_number)
  mm.set("stdout", Json::string(stdout_str))
  mm.set("stderr", Json::string(stderr_str))
  mm.set("error", Json::string(err_str))
  Ok(Json::object(mm))
}

///|
/// 批量执行 flush curl 命令，返回 batch 结果。
/// 调用方负责把 curl_command 和 bug_id 对齐（plan[i].curl_command 对应 plan[i].bug_id）。
pub async fn github_execute_batch(
  curl_commands : Array[String],
  workdir : String,
  timeout_ms_each : Int,
) -> Result[Json, String] {
  let raw = js_exec_batch_curl(curl_commands, workdir, timeout_ms_each).wait() catch {
    _ =>
      return Err(
        "github_execute_batch: 子进程调度失败（js 运行时异常）",
      )
  }
  let payload = @json.parse(raw) catch {
    _ => return Err("github_execute_batch: batch 结果 JSON 解析失败")
  }
  Ok(payload)
}

///|
/// 便捷包装：close 单条 issue（内部调 github_execute_single）。
pub async fn github_execute_close(
  curl_command : String,
  workdir : String,
  timeout_ms : Int,
) -> Result[Json, String] {
  github_execute_single(curl_command, workdir, timeout_ms)
}

///|
/// 便捷包装：comment 单条 issue（内部调 github_execute_single）。
pub async fn github_execute_comment(
  curl_command : String,
  workdir : String,
  timeout_ms : Int,
) -> Result[Json, String] {
  github_execute_single(curl_command, workdir, timeout_ms)
}
