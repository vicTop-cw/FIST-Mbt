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
/// 已支持的外部执行器（注册表；`executor_run` 工具按此校验）。
/// `aider` / `atomcode` 走本地 CLI spawn；`ofm` 走 HTTP 通道（`executor_run_impl` 分流，
/// 不经 `build_command`）——CLI spawn 保留，HTTP 是**并存第二通道**。
pub fn external_executors() -> Array[String] {
  ["aider", "atomcode", "ofm"]
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
  edit_format~ : String = "whole",
  map_tokens~ : Int32 = 0,
  encoding~ : String = "gbk",
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
/// atomcode argv（不含可执行文件名）：-p <prompt> [-C <project_dir>] [-y] [--model <model>]
/// workdir~ 为空时不下发 -C（由 spawn 的 cwd 决定），避免把空串当路径传下去。
///
/// BUG-238（2026-10-16）：model~ 为**空**时**省略 --model**，atomcode 走自己
/// config.toml 的 default_model（如 longcat/LongCat-2.0）。为什么允许空：
/// FIST `model_route` 的模型池名（ling-3.1-flash-free 等）与 atomcode provider
/// 命名空间（longcat/deepseek/Kimi）**两套名字不通**，把 FIST 池名直接塞
/// `--model` 会让 atomcode 恒吃 `HTTP 400 Unsupported model`。server 层在
/// 未配置模型映射时应传空串走执行器默认档；显式传非空模型名仍原样下发
/// （命名空间正确性由调用方自担）。aider 不同：空模型 = 绕过路由决策，
/// 维持拒绝不变（见 aider_argv）。
pub fn atomcode_argv(
  prompt~ : String,
  model~ : String,
  workdir~ : String = "",
  auto_yes~ : Bool = true,
) -> Result[Array[String], String] {
  if !prompt_ok(prompt) {
    return Err("atomcode: -p 提示词不能为空或含 NUL 字符")
  }
  let mut args : Array[String] = ["-p", prompt]
  if workdir.length() > 0 {
    args = args + ["-C", workdir]
  }
  if auto_yes {
    args = args + ["-y"]
  }
  if model.trim().length() > 0 {
    args = args + ["--model", model]
  }
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
  workdir~ : String = "",
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
    "ofm" =>
      Err(
        "ofm 走 HTTP 通道（POST {ofm_endpoint}/chat/completions），不经 build_command；" +
        "由 executor_run_impl 分流到 ofm_execute_http，这里不造 argv",
      )
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

///|
/// CLI 通道（aider / atomcode / 受限自定义执行器这类本地 spawn）的失败归因档。
/// 与 ofm 通道的 `OfmFailure` 同族：**归不出来就 `Unknown`，绝不猜**。
///
/// 立项理由（2026-10-23 实测）：spawn 原语 `run_check_external` 对「进程没起来 / 跑满超时 /
/// 被信号杀」**一律以 ok=false 落地、永不 reject**，而调用面此前把这三类一起说成
/// 「可执行文件不可用」。跑满一单 atomcode 任务后回执是
/// `ok=false / exit_code=-1 / error_tail="timeout after 900000ms"` + 「不可用」提示——
/// 而进程活着、产物与 diff 都在盘上。「没等到」与「没装」的处置完全相反
/// （前者先验产物再决定要不要重派，后者去修环境），把前者报成后者会让人重派一单已经干完的活。
pub enum CliFailure {
  NotExecutable
  Timeout
  NonZeroExit
  SignalKilled
  DispatchFailed
  Unknown
} derive(Eq, Debug)

///|
pub extend CliFailure with Eq::{not_equal, equal}

///|
pub extend CliFailure with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// 回执里 `failure_kind` 的稳定标签面（调用方可据此分支，不靠自然语言提示）。
pub fn CliFailure::label(self : CliFailure) -> String {
  match self {
    NotExecutable => "NOT_EXECUTABLE"
    Timeout => "TIMEOUT"
    NonZeroExit => "NONZERO_EXIT"
    SignalKilled => "SIGNAL_KILLED"
    DispatchFailed => "DISPATCH_FAILED"
    Unknown => "UNKNOWN"
  }
}

///|
/// 按 spawn 原语回执的 `error` 文本归因。文本形状是原语自己拼的、固定四类：
///   · `timeout after <ms>ms` → `Timeout`（看门狗杀的，进程起来过）
///   · `exit code <n>`        → `NonZeroExit`；`n == -1` 是 node 把 `code=null`
///                              （信号终止/崩溃）折出来的哨兵 → `SignalKilled`
///   · `spawn <bin> ENOENT` 一类（node `err.message`）→ `NotExecutable`
///   · `run_check_external` 自己的两条 Err（调度失败 / 结果解析失败）→ `DispatchFailed`
///     ——这一类坏的是**我们这一侧**，不是外部执行器
/// 顺序即判据：先认「尺子自己坏了」，再认超时，再认起不来，最后才看退出码。
pub fn classify_cli_failure(error : String) -> CliFailure {
  let e = error.trim()
  if e.contains("子进程调度失败") ||
    e.contains("结果 JSON 解析失败") {
    DispatchFailed
  } else if e.contains("timeout after") {
    Timeout
  } else if e.contains("ENOENT") || e.contains("EACCES") || e.contains("spawn") {
    NotExecutable
  } else if e == "exit code -1" {
    SignalKilled
  } else if e.contains("exit code") {
    NonZeroExit
  } else {
    // 拿不到线索就留档，不替调用方编一个原因
    Unknown
  }
}

///|
/// 按归因档给出**可处置**的提示。只有 `NotExecutable` 才配说「可执行文件不可用」
/// （那正是 `executor_missing_hint` 的原有职责，原样复用不改字）。
pub fn cli_failure_hint(name : String, kind : CliFailure) -> String {
  match kind {
    NotExecutable => executor_missing_hint(name)
    Timeout =>
      "外部执行器 '" +
      name +
      "' 起来了，但在超时预算内没退出——这是时长预算问题，不是执行器没装。" +
      "进程很可能已经写出产物：先按文件系统验证（output_validate / 直接读工作树与 diff）" +
      "再决定要不要重派，别把「没等到」当成「没干成」。确需重跑请提高 timeout_ms，" +
      "或把任务拆小到单轮能跑完。"
    NonZeroExit =>
      "外部执行器 '" +
      name +
      "' 起来了、退出码非 0：按 error/stderr 定位业务原因。" +
      "二进制显然在 PATH 里（否则拿不到退出码），不要按「不可执行」处置；" +
      "产物面仍以文件系统为准。"
    SignalKilled =>
      "外部执行器 '" +
      name +
      "' 被信号终止或崩溃（node 给 code=null，这里折成 -1）：优先怀疑崩溃/内存，" +
      "不是执行器缺失；带 stderr 立案，产物面以文件系统为准。"
    DispatchFailed =>
      "MoonBit 侧没能调度子进程或没能解析其结果 JSON——坏的是这一侧，不是外部执行器。" +
      "请把本回执连同 error 原文一起立案，不要照「安装执行器」的提示处置。"
    Unknown =>
      "外部执行器 '" +
      name +
      "' 失败但归不出类：把 error 原文带上再判。宁可留 Unknown，也不猜一个归因把处置带偏。"
  }
}
