///|
/// js target：agent 服务的文件系统面（唯一真源；native 臂见 `agent_native.mbt`）。
///
/// 为什么不用 `@store.FileLock`：那是**库内的逻辑锁记录**（scope/agent/status，
/// 给权限门读的），没有跨进程排他能力 ⇒ 拿它当单实例锁会得到「两个进程都自称持有」。
/// 这里用 OS 级原子原语 `writeFileSync(..., { flag: 'wx' })`：
/// **创建成功即持锁**，EEXIST 即被别人持有——这才是真正的互斥。
///
/// **全部走同步 API**（`node:fs` 的同步族）：本模块运行在 CLI 单进程里，
/// 轮询本来就是阻塞语义；引入 async 只会把 `.wait()` 的传播链一路推到 dispatch。
/// 仅 js target 编译（见 cmd/cli/moon.pkg targets 配置）。

///|
/// IO dispatcher：`op` ∈ { mkdir, write_x, read, append, remove, stat }。
/// 回执 JSON `{ ok, ... }` / `{ ok:false, error }`，**永不抛异常**
/// （错误一律走回执，由 MoonBit 侧分档，不靠 JS 抛错穿透 extern）。
extern "js" fn js_agent_io(
  op : String,
  path : String,
  content : String,
) -> String =
  #| (op, path, content) => {
  #|   const fs = require('node:fs')
  #|   const bad = (e) => JSON.stringify({ ok: false, error: String((e && e.message) || e) })
  #|   const ok = (extra) => JSON.stringify(Object.assign({ ok: true }, extra || {}))
  #|   try {
  #|     if (op === 'mkdir') {
  #|       fs.mkdirSync(path, { recursive: true })
  #|       return ok({})
  #|     }
  #|     if (op === 'write_x') {
  #|       // 原子独占创建：EEXIST ⇒ 已被别的 worker 持有
  #|       try {
  #|         fs.writeFileSync(path, content, { flag: 'wx' })
  #|         return ok({})
  #|       } catch (e) {
  #|         if (e && e.code !== 'EEXIST') throw e
  #|         let holder = ''
  #|         try { holder = fs.readFileSync(path, 'utf8') } catch (_e) {}
  #|         return JSON.stringify({ ok: false, error: 'lock_exists', holder })
  #|       }
  #|     }
  #|     if (op === 'read') {
  #|       if (!fs.existsSync(path)) return ok({ exists: false, text: '' })
  #|       return ok({ exists: true, text: fs.readFileSync(path, 'utf8') })
  #|     }
  #|     if (op === 'append') {
  #|       const dir = path.slice(0, path.lastIndexOf('/'))
  #|       if (dir) fs.mkdirSync(dir, { recursive: true })
  #|       fs.appendFileSync(path, content, 'utf8')
  #|       return ok({})
  #|     }
  #|     if (op === 'remove') {
  #|       if (fs.existsSync(path)) fs.unlinkSync(path)
  #|       return ok({})
  #|     }
  #|     if (op === 'stat') {
  #|       if (!fs.existsSync(path)) return ok({ exists: false, mtime_ms: 0 })
  #|       const st = fs.statSync(path)
  #|       return ok({ exists: true, mtime_ms: st.mtimeMs })
  #|     }
  #|     return bad(new Error('未知 IO 操作：' + op))
  #|   } catch (e) {
  #|     return bad(e)
  #|   }
  #| }

///|
fn agent_io_call(
  op : String,
  path : String,
  content : String,
) -> Result[Json, String] {
  let raw = js_agent_io(op, path, content)
  Ok(@json.parse(raw) catch { _ => return Err("agent_io: 回执不是 JSON") })
}

///|
fn agent_io_ok(r : Result[Json, String]) -> Result[Unit, String] {
  match r {
    Ok(Object(m)) =>
      match m.get("ok") {
        Some(True) => Ok(())
        Some(False) =>
          match m.get("error") {
            Some(String(e)) => Err(e)
            _ => Err("未知错误")
          }
        _ => Err("回执缺 ok 字段")
      }
    Ok(_) => Err("回执不是对象")
    Err(e) => Err(e)
  }
}

///|
pub fn agent_io_mkdir(dir : String) -> Result[Unit, String] {
  agent_io_ok(agent_io_call("mkdir", dir, ""))
}

///|
/// 原子独占创建。被占用时 Err 文本以 `lock_exists:` 开头（上层据此分档为
/// 「锁冲突」而非普通 IO 错——把两者混同，人就无法判断该等还是该查）。
pub fn agent_io_write_exclusive(
  path : String,
  content : String,
) -> Result[Unit, String] {
  match agent_io_call("write_x", path, content) {
    Ok(Object(m)) =>
      match m.get("ok") {
        Some(True) => Ok(())
        Some(False) =>
          match m.get("error") {
            Some(String(e)) =>
              if e == "lock_exists" {
                let holder = match m.get("holder") {
                  Some(String(h)) => h
                  _ => ""
                }
                Err("lock_exists:\{holder}")
              } else {
                Err(e)
              }
            _ => Err("未知错误")
          }
        _ => Err("回执缺 ok 字段")
      }
    Ok(_) => Err("回执不是对象")
    Err(e) => Err(e)
  }
}

///|
pub fn agent_io_read(path : String) -> Result[String, String] {
  match agent_io_call("read", path, "") {
    Ok(Object(m)) =>
      match m.get("text") {
        Some(String(t)) => Ok(t)
        _ => Err("回执缺 text")
      }
    Ok(_) => Err("回执不是对象")
    Err(e) => Err(e)
  }
}

///|
pub fn agent_io_append(path : String, content : String) -> Result[Unit, String] {
  agent_io_ok(agent_io_call("append", path, content))
}

///|
pub fn agent_io_remove(path : String) -> Result[Unit, String] {
  agent_io_ok(agent_io_call("remove", path, ""))
}

///|
/// 文件 mtime（毫秒）；不存在回 0。stale 判决用它，**不解析锁内容**——
/// 锁里写什么只用于回显持有者，时间以文件系统为准。
pub fn agent_io_stat_mtime(path : String) -> Double {
  match agent_io_call("stat", path, "") {
    Ok(Object(m)) =>
      match m.get("exists") {
        Some(True) =>
          match m.get("mtime_ms") {
            Some(Number(n, ..)) => n
            _ => 0.0
          }
        _ => 0.0
      }
    _ => 0.0
  }
}

///|
/// 同步睡眠。用 `Atomics.wait` 而不是 `setTimeout`：后者要把控制权交回事件循环，
/// 而这里是 CLI 轮询语义（占住进程直到下一轮），异步睡眠会引入不必要的状态机。
pub fn agent_io_sleep(ms : Double) -> Unit {
  js_agent_sleep(ms)
}

///|
extern "js" fn js_agent_sleep(ms : Double) -> Unit =
  #| (ms) => {
  #|   const t = Math.max(0, Number(ms) || 0)
  #|   const sab = new Int32Array(new SharedArrayBuffer(4))
  #|   Atomics.wait(sab, 0, 0, t)
  #| }

///|
/// 当前毫秒时间戳（stale 判决的唯一时间源）。
pub fn agent_io_now_ms() -> Double {
  js_agent_now_ms()
}

///|
extern "js" fn js_agent_now_ms() -> Double =
  #| () => {
  #|   return Date.now()
  #| }

///|
/// 当前时刻的 ISO 文本（state.json / 日志的时间字段）。
pub fn agent_io_now_iso() -> String {
  js_agent_now_iso()
}

///|
extern "js" fn js_agent_now_iso() -> String =
  #| () => {
  #|   return new Date().toISOString()
  #| }

///|
/// 进程号（锁内容的全部信息：`<pid>`）。释放时比对它，避免误删别人的锁。
pub fn agent_io_pid() -> Int32 {
  js_agent_pid()
}

///|
extern "js" fn js_agent_pid() -> Int32 =
  #| () => {
  #|   return Number((globalThis.process && globalThis.process.pid) || 0)
  #| }
