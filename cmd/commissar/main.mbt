///|
/// FIST-Mbt 政委引导提醒监控 CLI（js 目标，事件驱动）。
///
/// 用法：
///   moon run cmd/commissar -- watch <project_dir> [db_path]
///       政委常驻：监听 .commissar/events/ 信号目录，事件到达立即处理（R1-R4）
///   moon run cmd/commissar -- tick  <project_dir> [db_path]
///       一次性提醒检查（R2/R3 全量扫描 + R4 心跳汇报）
///   moon run cmd/commissar -- send  <project_dir> <kind> <target> <text>
///       发送政委信号（kind: guidance|stale|pending|heartbeat）
///
/// db_path 默认 <project_dir>/fist-mbt.db；打开失败回退内存引擎。
extern "js" fn ffi_argv_at(i : Int32) -> String =
  #| (i) => {
  #|   const a = (typeof process !== "undefined" && process.argv) ? process.argv.slice(2) : [];
  #|   return (i < a.length) ? a[i] : "";
  #| }

///|
extern "js" fn ffi_now_iso() -> String =
  #| () => new Date().toISOString()

///|
extern "js" fn ffi_now_ms() -> Int64 =
  #| () => BigInt(Date.now())

///|
extern "js" fn ffi_exit(code : Int32) -> Unit =
  #| (code) => { process.exit(code); }

///|
fn main {
  let mode = ffi_argv_at(0)
  if mode == "" {
    println(
      "用法: commissar <watch|tick|send> <project_dir> [db_path] [kind target text]",
    )
    ffi_exit(1)
  }
  let project_dir = ffi_argv_at(1)
  if project_dir == "" {
    println("缺少 project_dir")
    ffi_exit(1)
  }
  if mode == "send" {
    let kind = ffi_argv_at(2)
    let target = ffi_argv_at(3)
    let text = ffi_argv_at(4)
    if kind == "" || text == "" {
      println(
        "send 用法: commissar send <project_dir> <kind> <target> <text>",
      )
      ffi_exit(1)
    }
    @ops.commissar_send(
      project_dir,
      @ops.CommissarSignal::new(kind~, target~, text~),
      ffi_now_ms(),
    )
  } else if mode == "tick" || mode == "watch" {
    let db_path = ffi_argv_at(2)
    let engine = open_engine(project_dir, db_path)
    if mode == "tick" {
      let r = @ops.commissar_tick(engine, now=ffi_now_iso(), project_dir~)
      println(Json::stringify(r))
    } else {
      @ops.commissar_watch(engine, project_dir~, now=ffi_now_iso())
    }
  } else {
    println("未知模式: \{mode}，仅支持 watch / tick / send")
    ffi_exit(1)
  }
}

///|
fn open_engine(
  project_dir : String,
  db_path_arg : String,
) -> @engine.FistEngine {
  let db_path = if db_path_arg == "" {
    if project_dir == "." {
      "fist-mbt.db"
    } else {
      project_dir + "/fist-mbt.db"
    }
  } else {
    db_path_arg
  }
  match @engine.FistEngine::open_sqlite(db_path) {
    Some(e) => e
    None => {
      println(
        "commissar: 打开 \{db_path} 失败，回退内存引擎（只读扫描将为空）",
      )
      @engine.FistEngine::new()
    }
  }
}
