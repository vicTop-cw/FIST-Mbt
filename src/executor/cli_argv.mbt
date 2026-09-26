/// cli_argv.mbt —— aider / atomcode 等外部执行器的命令行构造（纯计算，零 IO）
///
/// 合并自兄弟项目 FIST 的 executor/aider_executor.py 与 executor/atomcode_executor.py，
/// 但**只保留"参数怎么拼"这一层**：真正 spawn 进程在 `src/server`（run_check_external），
/// 因为本包不引 IO 依赖，也为了让参数构造可被单元测试钉住（注入面必须可审）。
///
/// 安全边界：
///   - 产出 argv 数组交给 `spawn(cmd, args)`，**不经过 shell** ⇒ 提示词里的 `;`、`$()`、反引号
///     都只是字面量；本函数额外拒绝空提示词与含 NUL 的输入（会让子进程参数截断）。
///   - 模型名/工作目录来自配置或任务，不硬编码任何密钥；密钥只在进程环境变量里（本仓库不读 .env）。

///|
/// 已支持的外部 CLI 执行器（注册表；`executor_run` 工具按此校验）
pub fn external_executors() -> Array[String] {
  ["aider", "atomcode"]
}

///|
pub fn is_external_executor(name : String) -> Bool {
  external_executors().contains(name)
}

///|
/// 执行器被识别但 CLI 不在 PATH 时的可诊断提示（不得静默成功）
pub fn executor_missing_hint(name : String) -> String {
  "外部执行器 '" +
  name +
  "' 的可执行文件不可用：请确认它已安装并在 server 进程 PATH 中" +
  "（或在配置里给出绝对路径）。本工具不会替你安装依赖，也不会静默返回成功。"
}

///|
/// 参数合法性：非空且不含 NUL（含换行是允许的——argv 不是 shell）
fn prompt_ok(prompt : String) -> Bool {
  let n = prompt.length()
  if n == 0 {
    return false
  }
  for b in prompt.to_array() {
    if b == '\u0000' {
      return false
    }
  }
  true
}

///|
/// aider argv（不含可执行文件名）。与 FIST Python 版 --message/--model/--edit-format whole/
/// --map-tokens 0/--encoding gbk/--yes-always/--no-auto-commits 一致。
/// 返回 Err 表示参数不合法（空提示词/含 NUL），调用方必须如实上报而不是"凑一个能跑的"。
pub fn aider_argv(
  prompt~ : String,
  model~ : String,
  edit_format? : String = "whole",
  map_tokens? : Int = 0,
  encoding? : String = "gbk",
) -> Result[Array[String], String] {
  if !prompt_ok(prompt) {
    return Err("aider: --message 不能为空或含 NUL 字符")
  }
  if model.trim().length() == 0 {
    return Err(
      "aider: --model 不能为空（空模型名会让 aider 走默认档，等于绕过路由决策）",
    )
  }
  if edit_format != "whole" && edit_format != "diff" && edit_format != "udiff" {
    return Err(
      "aider: 非法 edit_format=" +
      edit_format +
      "（只允许 whole/diff/udiff）",
    )
  }
  let mt = if map_tokens < 0 { 0 } else { map_tokens }
  Ok([
    "--message",
    prompt,
    "--model",
    model,
    "--edit-format",
    edit_format,
    "--map-tokens",
    mt.to_string(),
    "--encoding",
    encoding,
    "--yes-always",
    "--no-auto-commits",
  ])
}

///|
/// atomcode argv（不含可执行文件名）：-p <prompt> -C <project_dir> -y --model <model>
/// workdir~ 为空时不下发 -C（由 spawn 的 cwd 决定），避免把空串当路径传下去。
pub fn atomcode_argv(
  prompt~ : String,
  model~ : String,
  workdir? : String = "",
  auto_yes? : Bool = true,
) -> Result[Array[String], String] {
  if !prompt_ok(prompt) {
    return Err("atomcode: -p 提示词不能为空或含 NUL 字符")
  }
  if model.trim().length() == 0 {
    return Err("atomcode: --model 不能为空")
  }
  let mut args : Array[String] = ["-p", prompt]
  if workdir.length() > 0 {
    args = args + ["-C", workdir]
  }
  if auto_yes {
    args = args + ["-y"]
  }
  args = args + ["--model", model]
  Ok(args)
}

///|
/// 把执行器名映射到可执行文件名（与 PATH 中的命令名一致）
pub fn executor_binary(name : String) -> String {
  match name {
    "aider" => "aider"
    "atomcode" => "atomcode"
    _ => name
  }
}

///|
/// 构造完整调用（binary + args）；未知执行器 → Err（不猜测、不降级）
pub fn build_command(
  executor~ : String,
  prompt~ : String,
  model~ : String,
  workdir? : String = "",
) -> Result[(String, Array[String]), String] {
  match executor {
    "aider" =>
      match aider_argv(prompt~, model~) {
        Ok(a) => Ok(("aider", a))
        Err(e) => Err(e)
      }
    "atomcode" =>
      match atomcode_argv(prompt~, model~, workdir~) {
        Ok(a) => Ok(("atomcode", a))
        Err(e) => Err(e)
      }
    _ =>
      Err(
        "未知执行器 '" +
        executor +
        "'。可用：" +
        external_executors().join(", ") +
        "（新增执行器要在 src/executor/cli_argv.mbt 里显式登记 argv 形状）",
      )
  }
}
