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
    "help" | "--help" | "-h" => Help
    "" => NoArgs
    other => Unknown(other)
  }
}

///|
/// 用法错（拼错子命令、给了不认识的旗）与运行错分档：2 = 用法错。
const USAGE_ERROR_EXIT_CODE : Int = 2

///|
fn exit_code_of(cmd : Subcmd) -> Int {
  match cmd {
    Unknown(_) => USAGE_ERROR_EXIT_CODE
    _ => 0
  }
}

///|
/// 把退出码真的交给宿主运行时。JS 腿是权威门槛（Node），native 腿用 libc `exit`；
/// 其余运行时没有退出码可设，就当场炸出来，绝不静默回 0（那正是 BUG-106 的形态）。
#cfg(target = "js")
extern "js" fn js_try_exit(code : Int) -> Bool =
  #| function(code) {
  #|   if (typeof process !== "undefined" && typeof process.exit === "function") {
  #|     process.exit(code);
  #|     return true;
  #|   }
  #|   return false;
  #| }

///|
#cfg(target = "js")
fn cli_exit(code : Int) -> Unit {
  if !js_try_exit(code) {
    abort("运行时没有 process.exit，无法回显退出码 \{code}")
  }
}

///|
#cfg(any(target = "native", target = "llvm"))
extern "c" fn native_exit(code : Int) = "exit"

///|
#cfg(any(target = "native", target = "llvm"))
fn cli_exit(code : Int) -> Unit {
  native_exit(code)
}

///|
#cfg(not(any(target = "js", target = "native", target = "llvm")))
fn cli_exit(code : Int) -> Unit {
  abort("该运行时无法设置退出码，本应回 \{code}")
}
