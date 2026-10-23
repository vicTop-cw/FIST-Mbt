///|
/// 子命令词法与退出码（BUG-106 的单一真源）
///
/// 别名只在这里展开一次：`main` 的分发臂与退出码都读同一份判定，
/// 「未知子命令却回 0」这类分裂就没有第二个落点
/// （`fist --version || exit 1` 会把失败读成成功）。
enum Subcmd {
  Serve
  Version
  Demo
  Doctor
  Upgrade
  Help
  NoArgs
  Unknown(String)
} derive(Eq, Debug)

///|
fn parse_subcmd(sub : String) -> Subcmd {
  match sub {
    "serve" => Serve
    "version" | "--version" | "-V" => Version
    "demo" => Demo
    "doctor" => Doctor
    "upgrade" | "--upgrade" => Upgrade
    "help" | "--help" | "-h" => Help
    "" => NoArgs
    other => Unknown(other)
  }
}

///|
/// 用法错（拼错子命令、给了不认识的旗）与运行错分档：2 = 用法错。
const USAGE_ERROR_EXIT_CODE : Int32 = 2

///|
fn exit_code_of(cmd : Subcmd) -> Int32 {
  match cmd {
    Unknown(_) => USAGE_ERROR_EXIT_CODE
    _ => 0
  }
}

///|
/// doctor 的失败计数（BUG-391 的接线点）：⏭️ 跳过不等于失败，但 `❌` 必须能被退出码看见。
/// 单独成函数是为了让这条判决有白盒锁——`run_doctor` 自己要在真引擎上跑，测不到这一格。
fn doctor_failed_count(ok : Int, total : Int, skip : Int) -> Int {
  total - ok - skip
}

///|
/// doctor 体检库的文件名（`FIST_DB_PATH` 未设置时的现状面，逐字不变）。
const DOCTOR_DB_NAME : String = "_fist_doctor_check.db"

///|
/// 路径里最后一个分隔符（`/` 或 `\`）的下标；纯相对名返回 None。
fn last_path_sep(p : String) -> Int? {
  let n = p.length()
  let mut acc : Int? = None
  let mut i = 0
  while i < n {
    let c = p[i]
    if c == '/' || c == '\\' {
      acc = Some(i)
    }
    i = i + 1
  }
  acc
}

///|
/// doctor 第 5 项的库路径（BUG-392 的接线点）。
/// `FIST_DB_PATH` 是运维侧改道针（与 `SqliteStore::new()` 同族），但过去 doctor
/// 把写死的相对名直接交给 `open_sqlite`，绕过了它 —— 135KB 的体检库落在进程 cwd
/// （往往是仓库根），既脏了 `git status`，又是 `check_demo_isolation` 只扫 `Popen`
/// 时看不见的一种形状。设了改道针就跟着它落同一目录，没设则维持旧行为。
fn doctor_db_path(env_value : String?) -> String {
  match env_value {
    Some(p) =>
      if p.is_empty() {
        DOCTOR_DB_NAME
      } else {
        match last_path_sep(p) {
          Some(i) => p[0:i + 1].to_owned() + DOCTOR_DB_NAME
          None => DOCTOR_DB_NAME
        }
      }
    None => DOCTOR_DB_NAME
  }
}

///|
/// 把退出码真的交给宿主运行时。JS 腿是权威门槛（Node），native 腿用 libc `exit`；
/// 其余运行时没有退出码可设，就当场炸出来，绝不静默回 0（那正是 BUG-106 的形态）。
#cfg(target="js")
extern "js" fn js_try_exit(code : Int32) -> Bool =
  #| function(code) {
  #|   if (typeof process !== "undefined" && typeof process.exit === "function") {
  #|     process.exit(code);
  #|     return true;
  #|   }
  #|   return false;
  #| }

///|
#cfg(target="js")
fn cli_exit(code : Int32) -> Unit {
  if !js_try_exit(code) {
    abort("运行时没有 process.exit，无法回显退出码 \{code}")
  }
}

///|
#cfg(any(target="native", target="llvm"))
extern "c" fn native_exit(code : Int32) = "exit"

///|
#cfg(any(target="native", target="llvm"))
fn cli_exit(code : Int32) -> Unit {
  native_exit(code)
}

///|
#cfg(not(any(target="js", target="native", target="llvm")))
fn cli_exit(code : Int32) -> Unit {
  abort("该运行时无法设置退出码，本应回 \{code}")
}
