///|
/// BUG-538：落盘日志 IO 薄壳（js target · node:fs）。
///
///   1) appendFileSync 追加（文件不存在则建）；父目录不存在先递归建 ——
///      FIST_DB_PATH 可能指深层目录，store 的补建发生在首次 open，而启动日志
///      可能先于它落地，这里自建、不依赖顺序；
///   2) 一切异常 catch ⇒ false 静默：日志写不进（磁盘/权限）绝不能打死 server
///      （BUG-538 硬约束 3）；
///   3) 只写文件，绝不碰 stdout/stderr（stdio 纯净性，scripts/check_mcp_stdio_purity.py）。
/// 仅 js target 编译（见 moon.pkg targets 配置）。

///|
extern "js" fn js_server_log_append(
  path : String,
  line : String,
) -> @js_async.Promise[Bool] =
  #| async (path, line) => {
  #|   try {
  #|     const fs = await import('node:fs')
  #|     const sep = Math.max(path.lastIndexOf('/'), path.lastIndexOf('\\'))
  #|     if (sep > 0) fs.mkdirSync(path.slice(0, sep), { recursive: true })
  #|     fs.appendFileSync(path, line)
  #|     return true
  #|   } catch (e) {
  #|     return false
  #|   }
  #| }

///|
/// 追加一行到日志文件。永不抛：调度异常也折成 false。
async fn server_log_append(path : String, line : String) -> Bool {
  js_server_log_append(path, line).wait() catch {
    _ => false
  }
}

///|
extern "js" fn js_server_log_pid() -> String =
  #| () => String(globalThis.process.pid)

///|
/// 当前进程 pid（真实 OS-PID；native 桩回 "0"，见 server_log_native.mbt）。
fn server_log_pid() -> String {
  js_server_log_pid()
}

///|
/// 安装 node 层崩溃钩子（BUG-538：只加记录，**不改现有退出行为**）。
///
///   · uncaughtException：写日志后 `process.exit(1)` —— node 默认对未捕获异常就是
///     「打印堆栈到 stderr + 退出码 1」；注册 handler 本身会接管默认崩溃路径，
///     所以必须显式 exit(1) 才是「按现状语义」。原 stderr 打印本就被宿主吞掉
///     （BUG-538 的根因面），现在同样的信息落盘、退出码不变。
///   · unhandledRejection：同上（node ≥15 默认未处理 rejection 即崩溃，退出码 1）。
///   · exit：进程正常退出路径（stdio 循环 stdin 关闭 / 显式退出）记一次。
///     exit 钩子必须是同步写（appendFileSync），node 不等它异步完成。
extern "js" fn js_server_log_install_hooks(
  path : String,
) -> @js_async.Promise[Unit] =
  #| async (path) => {
  #|   try {
  #|     const fs = await import('node:fs')
  #|     const write = (msg) => {
  #|       try {
  #|         const sep = Math.max(path.lastIndexOf('/'), path.lastIndexOf('\\'))
  #|         if (sep > 0) fs.mkdirSync(path.slice(0, sep), { recursive: true })
  #|         fs.appendFileSync(path, msg)
  #|       } catch (e) {}
  #|     }
  #|     const ts = () => new Date().toISOString()
  #|     process.on('exit', (code) => {
  #|       write(ts() + ' [fist-mbt] server.exit code=' + String(code) + '\n')
  #|     })
  #|     process.on('uncaughtException', (err) => {
  #|       write(ts() + ' [fist-mbt] crash.uncaughtException ' + String((err && err.stack) || err) + '\n')
  #|       try { process.exit(1) } catch (e) {}
  #|     })
  #|     process.on('unhandledRejection', (reason) => {
  #|       write(ts() + ' [fist-mbt] crash.unhandledRejection ' + String((reason && (reason.stack || reason)) || reason) + '\n')
  #|       try { process.exit(1) } catch (e) {}
  #|     })
  #|   } catch (e) {}
  #| }

///|
/// 安装崩溃钩子。永不抛。
async fn server_log_install_crash_hooks(path : String) -> Unit {
  js_server_log_install_hooks(path).wait() catch {
    _ => ()
  }
}

///|
/// BUG-538 心跳定时器（js · node setInterval）：每 interval_ms 一行 `heartbeat`。
///
///   · 行构造走 MoonBit 闭包 line_of ⇒ 复用 server_log_line + now_default
///     （与其它事件**同一收口**，行形状不在 JS 侧抄第二份）；
///   · append 与 js_server_log_append / 崩溃钩子同一原语（mkdir + appendFileSync，
///     全程 try/catch 静默降级）—— 异步的 server_log_write 无法从同步 timer
///     回调里 await，故 IO 原语在此薄壳内同形复刻（与崩溃钩子的 write 同一先例）；
///   · 进程生命周期面：run_server 装一次、不接 stop（timer 随进程死亡消亡，
///     这正是心跳的目的 —— 进程死了它自然停）；tick 上限只作 FFI 内的自清
///     保险（句柄活着会让 node 事件循环永不排空，测试运行器挂死实测），
///     生产传天文数字等效于无限；
///   · 只写文件，绝不碰 stdout/stderr（stdio 纯净性）。
extern "js" fn js_server_log_heartbeat_start(
  interval_ms : Int32,
  max_ticks : Int32,
  path : String,
  line_of : () -> String,
) -> Unit =
  #| (interval_ms, max_ticks, path, line_of) => {
  #|   try {
  #|     let n = 0
  #|     const t = setInterval(async () => {
  #|       n = n + 1
  #|       if (n > max_ticks) { clearInterval(t); return }
  #|       try {
  #|         const fs = await import('node:fs')
  #|         const sep = Math.max(path.lastIndexOf('/'), path.lastIndexOf('\\'))
  #|         if (sep > 0) fs.mkdirSync(path.slice(0, sep), { recursive: true })
  #|         fs.appendFileSync(path, line_of())
  #|       } catch (e) {}
  #|     }, interval_ms)
  #|   } catch (e) {}
  #| }

///|
/// 按注入间隔启动心跳。path==""（= FIST_SERVER_LOG=off）或 interval_ms<=0
/// ⇒ 不装定时器，零开销零文件（off 门在 MoonBit 层，不靠 JS 兜）。
fn server_log_heartbeat_start_with(
  path : String,
  interval_ms : Int32,
  max_ticks : Int32,
) -> Unit {
  if path == "" || interval_ms <= 0 || max_ticks <= 0 {
    return
  }
  js_server_log_heartbeat_start(interval_ms, max_ticks, path, fn() {
    server_log_line(
      now_default(),
      "heartbeat",
      server_log_heartbeat_detail(server_log_pid()),
    )
  })
}

///|
/// 按常量间隔启动心跳（run_server 接线入口；仅 slog_path != "" 时被调）。
fn server_log_heartbeat_start(path : String) -> Unit {
  server_log_heartbeat_start_with(
    path,
    SERVER_LOG_HEARTBEAT_MS,
    SERVER_LOG_HEARTBEAT_TICKS_MAX,
  )
}
