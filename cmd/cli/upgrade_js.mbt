///|
/// js target：`--upgrade` 的远端版本探测 + 阶段 B/C 的真实 IO（read/write/spawn）。
///
/// 设计要点（阶段 A）：
///   1) 用 Node 原生 `fetch`（node 18+ 内置），**不依赖 curl**；
///   2) 打 `releases/latest`（= stable 通道），从 `tag_name` 抽版本，去 v 前缀；
///   3) JS 端**永不 reject**：一切异常（网络 / 超时 / 非 2xx / 无 tag）都进 JSON 字段，
///      MoonBit 侧 `@json.parse` 解包——与 github_js / run_check_js 惯例一致；
///   4) **不假绿（R7）**：非 2xx 或拿不到 tag 都回 `ok:false` + 原因。
///
/// 设计要点（阶段 B/C，`upgrade_io`）：
///   5) 一个 dispatcher extern，动作由 `op` 字符串分派，payload/回执都是 JSON 字符串
///      （与 run_check_js / laya_js 的 JSON 桥接同一口径，MoonBit 侧零 FFI 细节）；
///   6) 下载安装器走 **R12/R14 双栈重试**：**只对「拿不到 HTTP 响应的传输层错误」重试/换栈**，
///      404/403/形状错（HTML 页）是确定性结论，直接换源不重试；重试带退避间隔；
///   7) 换入交给 `pwsh -File upgrade_install.ps1`（tracked 真源 `scripts/blackbox/upgrade_install.ps1`，
///      复用 R6/R7/R12 硬化 + BUG-235 的 .bak-* 保留，不重写下载器）；
///   8) 文件占用检测：安装器失败且 stderr 命中占用形状 → 附加「请先停止 fist-mbt serve」提示。
/// 仅 js target 编译（见 cmd/cli/moon.pkg targets 配置）。

///|
/// 私有 extern：取远端最新稳定版 tag（去 v 前缀）。
/// resolve with `{ ok, tag?, error? }`. Never rejects.
extern "js" fn js_fetch_latest(
  repo : String,
  base_url : String,
  timeout_ms : Int32,
) -> @js_async.Promise[String] =
  #| async (repo, baseUrl, timeoutMs) => {
  #|   // BUG-C：base_url 非空时按镜像形状取 tag，空才走 GitHub API。
  #|   const url = (() => {
  #|     const b = String(baseUrl || '').trim()
  #|     if (b) return b.replace(/\/+$/, '') + '/releases/latest'
  #|     return 'https://api.github.com/repos/' + repo + '/releases/latest'
  #|   })()
  #|   const controller = new AbortController()
  #|   const timer = setTimeout(() => controller.abort(), timeoutMs)
  #|   try {
  #|     const res = await fetch(url, {
  #|       headers: {
  #|         'User-Agent': 'fist-mbt-upgrade',
  #|         'Accept': 'application/vnd.github+json',
  #|       },
  #|       signal: controller.signal,
  #|     })
  #|     if (!res.ok) {
  #|       return JSON.stringify({ ok: false, error: 'http_' + res.status })
  #|     }
  #|     const body = await res.json()
  #|     const tag = body && body.tag_name ? String(body.tag_name).replace(/^v/, '') : ''
  #|     if (!tag) {
  #|       return JSON.stringify({ ok: false, error: 'no_tag_in_latest' })
  #|     }
  #|     return JSON.stringify({ ok: true, tag })
  #|   } catch (e) {
  #|     return JSON.stringify({
  #|       ok: false,
  #|       error: String(e && e.message ? e.message : e),
  #|     })
  #|   } finally {
  #|     clearTimeout(timer)
  #|   }
  #| }

///|
/// 公开 wrapper（与 upgrade_native.mbt 同签名）：取远端最新 tag，去 v 前缀。
pub async fn upgrade_fetch_latest(
  repo : String,
  base_url : String,
  timeout_ms : Int32,
) -> Result[String, String] {
  let raw = js_fetch_latest(repo, base_url, timeout_ms).wait() catch {
    _ => return Err("upgrade_fetch_latest: 运行时调度失败")
  }
  let payload = @json.parse(raw) catch {
    _ => return Err("upgrade_fetch_latest: 探测结果 JSON 解析失败")
  }
  match payload {
    Object(m) =>
      match m.get("ok") {
        Some(True) =>
          match m.get("tag") {
            Some(String(t)) =>
              if t.length() > 0 {
                Ok(t)
              } else {
                Err("upgrade_fetch_latest: 远端未回 tag")
              }
            _ => Err("upgrade_fetch_latest: 远端未回 tag")
          }
        _ =>
          match m.get("error") {
            Some(String(e)) =>
              Err("upgrade_fetch_latest: 远端探测失败 \{e}")
            _ =>
              Err("upgrade_fetch_latest: 远端探测失败（未给原因）")
          }
      }
    _ => Err("upgrade_fetch_latest: 远端响应不是 JSON 对象")
  }
}

///|
/// 私有 extern：阶段 B/C 的 IO dispatcher。
/// `op` ∈ { install_dir, read_local, fetch_installer, run_installer, backup, verify,
///         write_version, restore }；`payload_json` 是 JSON 对象字符串（可为 "{}"）。
/// 结果 resolve with `{ ok, ...field... }` 或 `{ ok:false, error }`。Never rejects.
extern "js" fn js_upgrade_io(
  op : String,
  payload_json : String,
) -> @js_async.Promise[String] =
  #| async (op, payloadJson) => {
  #|   const fs = await import('node:fs')
  #|   const path = await import('node:path')
  #|   const os = await import('node:os')
  #|   const { spawn } = await import('node:child_process')
  #|   const payload = payloadJson ? JSON.parse(payloadJson) : {}
  #|   const ok = (extra) => JSON.stringify(Object.assign({ ok: true }, extra || {}))
  #|   const bad = (error) => JSON.stringify({ ok: false, error: String(error) })
  #|   const tail = (s, n) => { s = String(s || ''); return s.length > n ? '...' + s.slice(s.length - n) : s }
  #|   const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
  #|   const runCapture = (cmd, args, timeoutMs) => new Promise((resolve) => {
  #|     let out = ''
  #|     let err = ''
  #|     const settle = (code, error) => resolve({ code, stdout: out, stderr: err, error: error || '' })
  #|     let child
  #|     try {
  #|       child = spawn(cmd, args, { stdio: ['ignore', 'pipe', 'pipe'] })
  #|     } catch (e) {
  #|       settle(-1, String((e && e.message) || e))
  #|       return
  #|     }
  #|     const timer = setTimeout(() => {
  #|       try { child.kill() } catch (e) {}
  #|       settle(-1, 'timeout after ' + timeoutMs + 'ms')
  #|     }, timeoutMs)
  #|     child.stdout.on('data', (d) => { out += d.toString('utf8') })
  #|     child.stderr.on('data', (d) => { err += d.toString('utf8') })
  #|     child.on('error', (e) => { clearTimeout(timer); settle(-1, String((e && e.message) || e)) })
  #|     child.on('exit', (code) => { clearTimeout(timer); settle(code === null ? -1 : code, '') })
  #|   })
  #|   // R6/R7 形状检查：安装器是 .ps1，不查 PK 魔数，但 200 ≠ 拿到文件——HTML 页必须被识破
  #|   const looksLikeHtml = (text) => /^\s*(<!doctype|<html|<head|<meta)/i.test(String(text || '').slice(0, 512))
  #|   // R12/R14：只对「没有 HTTP 响应」的传输层错误重试/换栈；拿到响应就 break
  #|   const fetchOne = async (url, timeoutMs) => {
  #|     const controller = new AbortController()
  #|     const timer = setTimeout(() => controller.abort(), timeoutMs)
  #|     try {
  #|       const res = await fetch(url, { signal: controller.signal, headers: { 'User-Agent': 'fist-mbt-upgrade' } })
  #|       const text = await res.text()
  #|       return { responded: true, status: res.status, text, error: '' }
  #|     } catch (e) {
  #|       return { responded: false, status: 0, text: '', error: String((e && e.message) || e) }
  #|     } finally {
  #|       clearTimeout(timer)
  #|     }
  #|   }
  #|   const installDir = () => {
  #|     if (process.platform === 'win32') {
  #|       return path.join(process.env.LOCALAPPDATA || path.join(os.homedir(), 'AppData', 'Local'), 'FIST-Mbt')
  #|     }
  #|     return path.join(os.homedir(), '.local', 'share', 'fist-mbt')
  #|   }
  #|   try {
  #|     if (op === 'install_dir') {
  #|       const dir = installDir()
  #|       const jsBin = path.join(dir, 'fist-mbt.js')
  #|       return ok({ dir, js_bin: jsBin, js_exists: fs.existsSync(jsBin), version_file: path.join(dir, 'VERSION'), node_major: String(parseInt(String(process.version).replace('v', '').split('.')[0], 10) || 0) })
  #|     }
  #|     if (op === 'read_local') {
  #|       const dir = payload.dir
  #|       const versionFile = path.join(dir, 'VERSION')
  #|       if (fs.existsSync(versionFile)) {
  #|         const v = fs.readFileSync(versionFile, 'utf8').trim()
  #|         if (v) return ok({ version: v, source: 'VERSION' })
  #|       }
  #|       const jsBin = payload.js_bin
  #|       if (jsBin && fs.existsSync(jsBin)) {
  #|         const r = await runCapture(process.execPath, [jsBin, 'version'], 60000)
  #|         if (r.code === 0) {
  #|           const m = /FIST-Mbt v([^\s]+)/.exec(r.stdout)
  #|           if (m) return ok({ version: m[1], source: 'node version' })
  #|         }
  #|       }
  #|       return bad('无法确定已安装版本（无 VERSION 文件，且 `node fist-mbt.js version` 未回出可解析版本）')
  #|     }
  #|     if (op === 'fetch_installer') {
  #|       const version = payload.version || 'unknown'
  #|       const baseUrl = String(payload.base_url || '').replace(/\/+$/, '')
  #|       let urls
  #|       if (baseUrl) {
  #|         urls = [baseUrl + '/scripts/blackbox/upgrade_install.ps1']
  #|       } else {
  #|         urls = [
  #|           'https://raw.githubusercontent.com/vicTop-cw/FIST-Mbt/master/scripts/blackbox/upgrade_install.ps1',
  #|           'https://gitcode.com/VictorTop/Fist-Mbt/-/raw/master/scripts/blackbox/upgrade_install.ps1',
  #|         ]
  #|       }
  #|       const tmpDir = path.join(os.tmpdir(), 'fist-upgrade')
  #|       fs.mkdirSync(tmpDir, { recursive: true })
  #|       const dest = path.join(tmpDir, 'upgrade_install-' + version + '.ps1')
  #|       const errors = []
  #|       for (const url of urls) {
  #|         let r = await fetchOne(url, 15000)
  #|         if (!r.responded) {
  #|           for (const wait of [600, 1200]) {
  #|             await sleep(wait)
  #|             r = await fetchOne(url, 15000)
  #|             if (r.responded) break
  #|           }
  #|         }
  #|         if (!r.responded) {
  #|           errors.push(url + ' 传输层失败: ' + r.error)
  #|           continue
  #|         }
  #|         // 拿到 HTTP 响应就 break（R12）：不再对同一 URL 重试
  #|         if (r.status === 200 && r.text && !looksLikeHtml(r.text)) {
  #|           fs.writeFileSync(dest, r.text, 'utf8')
  #|           return ok({ path: dest, source: url })
  #|         }
  #|         errors.push(url + ' HTTP ' + r.status + (looksLikeHtml(r.text) ? '（返回 HTML 页，不是安装器）' : ''))
  #|       }
  #|       return bad('取不到安装器 upgrade_install.ps1：' + errors.join(' | '))
  #|     }
  #|     if (op === 'run_installer') {
  #|       const args = ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', payload.script, '-Version', payload.version, '-Force']
  #|       if (payload.base_url) args.push('-BaseUrl', payload.base_url)
  #|       if (payload.no_path) args.push('-NoPath')
  #|       const r = await runCapture('pwsh', args, 240000)
  #|       if (r.code === 0) return ok({ code: 0 })
  #|       const merged = tail((r.stderr || '') + '\n' + (r.stdout || ''), 400)
  #|       const busy = /being used by another process|Access is denied|Move-Item.*failed|EBUSY|EPERM|denied/i.test(merged)
  #|       const hint = busy ? '（文件可能被占用——请先停止 fist-mbt serve 再 upgrade）' : ''
  #|       return bad('pwsh 安装器退出 ' + r.code + hint + '：' + merged)
  #|     }
  #|     if (op === 'backup') {
  #|       const jsBin = payload.js_bin
  #|       const bak = path.join(path.dirname(jsBin), payload.bak_name || ('fist-mbt.js.bak-' + payload.local))
  #|       if (!fs.existsSync(jsBin)) return bad('待备份的 fist-mbt.js 不存在：' + jsBin)
  #|       fs.copyFileSync(jsBin, bak)
  #|       return ok({ backup: bak })
  #|     }
  #|     if (op === 'verify') {
  #|       const jsBin = payload.js_bin
  #|       const r = await runCapture(process.execPath, [jsBin, 'version'], 60000)
  #|       if (r.code !== 0) {
  #|         return bad('自检失败：node ' + jsBin + ' version 退出 ' + r.code + '：' + tail(r.stderr || r.stdout, 300))
  #|       }
  #|       const m = /FIST-Mbt v([^\s]+)/.exec(r.stdout)
  #|       if (!m) return bad('自检无法解析版本：' + tail(r.stdout, 200))
  #|       return ok({ version: m[1] })
  #|     }
  #|     if (op === 'write_version') {
  #|       const f = path.join(payload.dir, 'VERSION')
  #|       fs.writeFileSync(f, String(payload.version).trim() + '\n', 'utf8')
  #|       return ok({ path: f })
  #|     }
  #|     if (op === 'restore') {
  #|       const bak = path.join(path.dirname(payload.js_bin), payload.bak_name || ('fist-mbt.js.bak-' + payload.local))
  #|       if (!fs.existsSync(bak)) return bad('备份不存在，无法回滚：' + bak)
  #|       fs.copyFileSync(bak, payload.js_bin)
  #|       return ok({})
  #|     }
  #|     return bad('未知 IO 操作：' + op)
  #|   } catch (e) {
  #|     return bad((e && e.message) || String(e))
  #|   }
  #| }

///|
/// 阶段 B/C IO 的公开 wrapper（与 upgrade_native.mbt 同签名）：把 JS 回执 JSON 解析成 Json。
/// 永不 abort：调度失败、结果 JSON 解析失败均以 Err 返回；上层从 Json 里再取 ok/字段。
pub async fn upgrade_io(
  op : String,
  payload_json : String,
) -> Result[Json, String] {
  let raw = js_upgrade_io(op, payload_json).wait() catch {
    _ => return Err("upgrade_io: 运行时调度失败")
  }
  let parsed = @json.parse(raw) catch {
    _ => return Err("upgrade_io: 结果 JSON 解析失败")
  }
  Ok(parsed)
}
