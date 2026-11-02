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
