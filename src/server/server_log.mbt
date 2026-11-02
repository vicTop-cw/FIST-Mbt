///|
/// BUG-538（工程半）：server 落盘日志 —— 纯函数面（开关解析 / 路径解析 / 行构造）。
///
/// 背景：server 的 stdout/stderr 被宿主连接器吞掉 ⇒ 任何一次进程死亡都永远不可判因
/// （memory/bugs.md BUG-538：2026-11-02 server 进程消失，进程面取证只能证明
/// 「没有可卡死的进程」，死因不可判）。治本出路：关键生命周期事件写
/// `<FIST_DB_PATH 所在目录>/server.log`（追加模式、ISO 时间戳）。
///
/// 铁律（本仓有 scripts/check_mcp_stdio_purity.py 守卫）：
///   · 日志**只写文件**，绝不碰 stdout，也尽量不占 stderr；
///   · 失败不致命：所有 IO 包 try/catch 静默降级 —— 日志写不进（磁盘/权限）
///     绝不能让 server 崩。
///
/// 分层（与 run_check_js/run_check_native、github_js/github_native 同一手法）：
///   · 本文件：纯函数 + 共享入口，两个目标都编译；
///   · server_log_js.mbt（js）：node:fs appendFileSync + process.pid + 崩溃钩子；
///   · server_log_native.mbt（native）：no-op 桩（native 面本地必崩/CI 才绿，
///     BUG-527 现状；桩只保「native 编译不被新模块破坏」，不假装成功）。

///|
/// FIST_SERVER_LOG 开关解析（纯，可测）：trim 后小写 == "off" 视为关闭。
fn server_log_env_off(raw : String?) -> Bool {
  match raw {
    None => false
    Some(v) => {
      // trim() 返回 StringView ⇒ 先转 String 再 to_lower()（与 auth_mode 同一手法）
      let t = v.trim().to_owned()
      t.to_lower() == "off"
    }
  }
}

///|
/// 取路径的目录前缀（**含**末尾分隔符）；无分隔符（裸文件名）回 "" ⇒ 日志落 cwd。
/// 分隔符同时认 '/' 与 '\\'（Windows 反斜杠）。
fn server_log_dir_of(path : String) -> String {
  let mut last_sep = -1
  let mut i = 0
  for ch in path {
    if ch == '/' || ch == '\\' {
      last_sep = i
    }
    i = i + 1
  }
  if last_sep < 0 {
    return ""
  }
  path[:last_sep + 1].to_owned()
}

///|
/// 日志路径解析（纯，可测）：
///   · FIST_SERVER_LOG=off    → ""（关闭；所有写入对空路径都是 no-op）
///   · FIST_SERVER_LOG=<路径>  → 显式路径（原样，trim）
///   · 未设置 / 空串          → <db_path 所在目录>/server.log
///     （db 是裸文件名 ⇒ 落 cwd 的 server.log，与任务书「无 db path 退 cwd」一致）
fn server_log_resolve_path(log_env : String?, db_path : String) -> String {
  if server_log_env_off(log_env) {
    return ""
  }
  match log_env {
    Some(v) => {
      let t = v.trim().to_owned()
      if t != "" {
        return t
      }
    }
    None => ()
  }
  server_log_dir_of(db_path) + "server.log"
}

///|
/// 当前生效日志路径（每次现算：env 读取廉价、日志事件低频，不做缓存换简单）。
/// db 路径复用 store 的单一真源 `SqliteStore::default_db_path()`（FIST_DB_PATH
/// 解析 / 默认值口径不在这里抄第二份）。
fn server_log_path() -> String {
  server_log_resolve_path(
    @env.get_env_var("FIST_SERVER_LOG"),
    @store.SqliteStore::default_db_path(),
  )
}

///|
/// BUG-538 心跳间隔常量（毫秒）：每 60 秒一行 `heartbeat` —— node 的 OOM 硬崩
/// 不经过 uncaughtException ⇒ 崩溃钩子抓不到死亡时刻；心跳让**任何形式**的死亡
/// 都留下「最后还活着」的时间戳，死亡窗口从「未知」收窄到「最后心跳之后」。
/// 间隔写死常量、不给配置面（过度设计防线：没有 FIST_HEARTBEAT_MS env）。
const SERVER_LOG_HEARTBEAT_MS : Int32 = 60_000

///|
/// 心跳 tick 上限：生产语义是「随进程死亡消亡」，不接 stop；但 setInterval
/// 在句柄活着时会让 node 事件循环永不排空（测试运行器挂死实测），所以 FFI
/// 带一个 tick 上限、到点自清。生产给天文数字（60s × 20 亿 ≈ 3800 年，
/// Int32 上限内），等效于无限；测试给小数字拿「到点自停」的确定性。
const SERVER_LOG_HEARTBEAT_TICKS_MAX : Int32 = 2_000_000_000

///|
/// 心跳行 detail（纯，可测）：pid 一并入行 —— server.log 可能被同目录多个
/// server 进程共享，pid 让「最后还活着」的归属可判。
fn server_log_heartbeat_detail(pid : String) -> String {
  "alive pid=" + pid
}

///|
/// 一行日志（纯，可测）：`<ISO> [fist-mbt] <event> <detail>` + 换行。
/// ts_iso 由调用方给（now_default()），本函数不做时钟 IO，保持纯。
fn server_log_line(ts_iso : String, event : String, detail : String) -> String {
  ts_iso + " [fist-mbt] " + event + " " + detail + "\n"
}

///|
/// 换行/回车净化为空格：detail 里的 error 文本可能多行，落盘前压成单行，
/// 保证「一行一事件」的日志形状可 grep。
fn server_log_sanitize(s : String) -> String {
  let sb = StringBuilder()
  for ch in s {
    if ch == '\n' || ch == '\r' {
      sb.write_char(' ')
    } else {
      sb.write_char(ch)
    }
  }
  sb.to_string()
}

///|
/// 截断长文本（args 拼接 / error 摘要）：超长截断并带 `...(capped)` 标记，
/// 防一条超长命令/报错把日志吃满盘；截断面同样过换行净化。
fn server_log_cap(s : String, max_chars : Int32) -> String {
  let clean = server_log_sanitize(s)
  if clean.length() <= max_chars {
    return clean
  }
  clean[:max_chars].to_owned() + "...(capped)"
}

///|
/// 写一条事件到指定路径（共享入口，async：js 薄壳内部要 wait Promise）。
/// path==""（= FIST_SERVER_LOG=off）⇒ no-op 返 false，**零 IO**；
/// IO 失败 ⇒ 静默返 false（不抛、不崩，BUG-538 硬约束 3）。
async fn server_log_write_to(
  path : String,
  event : String,
  detail : String,
) -> Bool {
  if path == "" {
    return false
  }
  server_log_append(path, server_log_line(now_default(), event, detail))
}

///|
/// 按当前生效配置写一条事件（便捷入口：路径现算）。
async fn server_log_write(event : String, detail : String) -> Bool {
  server_log_write_to(server_log_path(), event, detail)
}
