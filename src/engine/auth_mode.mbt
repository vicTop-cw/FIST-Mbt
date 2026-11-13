// ============================================================================
// BUG-470：认证模式开关（`FIST_AUTH_MODE`）—— **单一真源**
//
// owner 已批准「策略 B（默认降权）」。本文件提供三档开关，并把「默认值」
// 从「代码里的隐式行为」变成「一个显式的、可回滚的配置项」。
//
// ## 三档语义（**`off` 的定义容易误解，先读这段**）
//
// | 值 | 对「有公钥但不出示」 | 对「无公钥且不出示」 |
// |---|---|---|
// | `off`    | **降权**（S3 第九段，本开关之前就有）| **自报**（放行，原样）|
// | `soft`   | **降权** | **降权** ← **本开关新增的这层** |
// | `strict` | **拒绝** | **拒绝** |
//
// ⚠️ **`off` 不是「完全关闭认证」** —— S3 第九段的软强制降权（有钥匙不传 ⇒ 降权）
//   **在 `off` 下仍然生效**。`off` 关的只是「**对无钥匙者也降权**」这一层。
//   为什么这样定义：那一层是 BUG-430 第九段已经上线并锁住的行为，
//   把它放进开关里意味着「关开关 = 回退一个已交付的特性」—— 那不是开关，是倒车。
//   本开关的职责是「**是否把要求扩展到无钥匙者**」。
//
// ## 为什么读一次就缓存（不热切）
//
//   热切要处理「一个请求跨切换点」的语义漂移（这个请求算旧模式还是新模式？），
//   而重启成本只有几秒（`serve-launcher.cjs` 冷启 2-4 秒）。
//   **用简单换正确** —— 这也是决策单里写明的选择。
//
// ## 默认值变迁（flip 已执行）
//
//   决策单：首次上线默认 `off`，观察一周后 flip 到 `soft`。
//   · 2026-10-28 首次上线：默认 `off`（`off` 的行为与修前**逐字相同**，
//     否则「上线开关」这件事本身就有回归风险）；
//   · **2026-11-13 flip：默认 `soft`**（owner 指令执行；无公钥者一律按 Executor 算）。
//     回滚 = 启动器 `DEFAULT_AUTH_MODE` 改回 `'off'` 或显式传 `FIST_AUTH_MODE=off`。
// ============================================================================

///|
/// 认证模式（三档）。
///
/// `derive(Eq, Debug)`：让测试能 `assert_eq(auth_mode(), Off)` 并打印差值。
#derive(Eq, Debug)
pub enum AuthMode {
  /// 只关「对无钥匙者也降权」这层；有钥匙不传仍降权（= 修前行为）
  Off
  /// 无钥匙也降权（owner 批准的策略 B）
  Soft
  /// 一律拒绝（未启用，前置条件见 BUG-470 决策单）
  Strict
}

///|
/// **显式 extend（BUG-478 清理 warn）**：编译器 `implicit_impl_as_method` 要求把
/// `derive(Eq, Debug)` 生成的 impl 方法**显式声明**为普通方法，否则将被移除。
/// 不写这两行时 `AuthMode` 的 `.equal()` / `.to_string()`（Debug 路径）会在未来版本失效。
pub extend AuthMode with Eq::{not_equal, equal}

///|
pub extend AuthMode with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// 转回 `FIST_AUTH_MODE` 的**取值字符串**（小写，与 env 里人配的字面量一致）。
///
/// ⚠️ 为什么不用 `Debug`：`Debug` 给的是 `Off`/`Soft`/`Strict`（大写），
///   与人配的 `off`/`soft`/`strict` **不一致** ⇒ 人读启动日志会以为配错了。
pub fn AuthMode::to_string(self : AuthMode) -> String {
  match self {
    Off => "off"
    Soft => "soft"
    Strict => "strict"
  }
}

///|
/// 解析 `FIST_AUTH_MODE` 的原始字符串（**纯函数，唯一判定面**）。
///
/// 取值（大小写不敏感、两端空白忽略）：
///   · `"off"`    ⇒ `Off`
///   · `"soft"`   ⇒ `Soft`
///   · `"strict"` ⇒ `Strict`
///   · 空串 / 未设 / **其它任何值** ⇒ `Soft`（**当前默认**，2026-11-13 flip）
///
/// ## 默认值变迁（BUG-470 决策单第二阶段，owner 指令执行）
///
///   · 2026-10-28 首次上线：默认 `off`（与修前逐字零回归，先观察一周）
///   · 2026-11-13 **flip**：默认 `soft`（无公钥者也按 Executor 算——策略 B 生效）
///
/// ⚠️ **非法值回退默认 `Soft` 而不是 `Strict`**：写错一个字母不该让现网停摆。
///   fail-closed 在这里是**错的方向** —— 因为本开关的「严」档会让 56 个调用方失败，
///   而「回退默认」只是维持默认现状。**配置写错 ≠ 环境不安全。**
pub fn auth_mode_parse(raw : String) -> AuthMode {
  match normalize_mode_str(raw) {
    "off" => Off
    "soft" => Soft
    "strict" => Strict
    // 空（未设）/ 非法 ⇒ 回退**默认值**（不 panic、不取最严）
    _ => Soft
  }
}

///|
/// 非法值时的 warning 文案；合法值 / 未设时返回空串（调用方据此决定是否打日志）。
///
/// 为什么要单独一个函数：`auth_mode_parse` 必须保持**纯**（可测、无副作用），
/// 而「要不要警告」是另一个判断（判例-29：判定面与渲染面分开）。
pub fn auth_mode_warning(raw : String) -> String {
  let n = normalize_mode_str(raw)
  if n == "" || n == "off" || n == "soft" || n == "strict" {
    ""
  } else {
    "FIST_AUTH_MODE=\"" +
    raw +
    "\" 不是合法值（期望 off / soft / strict）⇒ **已回退 soft（当前默认）**。" +
    "配置写错不会让现网停摆，但请修正——回退的是默认档，不是你以为设的那档。"
  }
}

///|
/// 规范化：去两端空白 + 转小写（`FIST_AUTH_MODE=OFF` 与 `off` 等价）。
fn normalize_mode_str(raw : String) -> String {
  // `trim()` 返回 StringView ⇒ 先转 String 再 to_lower()
  let t : String = raw.trim().to_owned()
  t.to_lower()
}

///|
/// 进程级缓存（首次读取后不再读 env —— 见文件头「为什么不做热切」）。
///
/// ⚠️ MoonBit **不支持顶层 `let mut`**（实测 `Error [4074]`）⇒ 用一个单元素数组当可变槽。
/// 这是本仓已有的同族手法（`s3_pending_nonces` / `s3_challenge_counter` 都是顶层可变容器）。
let auth_mode_slot : Array[String] = [""]

///|
/// **唯一**的 env 读取点（单一真源，判例-29）。
///
/// 首次调用读 `FIST_AUTH_MODE` 并缓存；之后直接返回缓存。
/// 任何其它地方要问「当前是什么模式」都必须调 `auth_mode()`，**不得直接读 env**。
pub fn auth_mode() -> AuthMode {
  if auth_mode_slot[0] == "" {
    let raw = match @env.get_env_var("FIST_AUTH_MODE") {
      Some(v) => v
      None => ""
    }
    // 缓存**规范化后的合法值**（未设/非法也缓存为 "soft"=当前默认，避免每次调用都重复判定）
    let n = normalize_mode_str(raw)
    auth_mode_slot[0] = if n == "off" || n == "soft" || n == "strict" {
      n
    } else {
      "soft"
    }
  }
  auth_mode_parse(auth_mode_slot[0])
}

///|
/// 测试专用：重置缓存（让同一进程内能切换模式跑多格测试）。
///
/// ⚠️ 生产代码**不要调** —— 它会让「读一次就定」的保证失效。
pub fn auth_mode_reset_cache_for_test() -> Unit {
  auth_mode_slot[0] = ""
}

///|
/// 测试专用：**直接钉住缓存值**（不碰进程 env —— 避免 env 污染同进程后续格，判例-31）。
///
/// 用途：flip（2026-11-13）后默认= `soft`；要驱动 `off` / `strict` 语义的测试格
/// 在**开头**调 `auth_mode_pin_cache_for_test("off")` 钉住，即可复现 flip 前的默认行为。
///
/// ⚠️ 两条纪律：
///   · 只传合法值（"off" / "soft" / "strict"），传别的等于非法值回退语义；
///   · 任何**依赖未设默认**的测试格，开头必须先 `auth_mode_reset_cache_for_test()`，
///     因为前一格可能把缓存钉在了别的档上。
/// ⚠️ 生产代码**不要调** —— 它绕过「读一次 env」的单一真源保证。
pub fn auth_mode_pin_cache_for_test(raw : String) -> Unit {
  auth_mode_slot[0] = normalize_mode_str(raw)
}

///|
/// 仅在**进程启动时调一次**，拿到「配置有问题」的 warning（无问题则空串）。
///
/// 两类情况都返回非空：
///   1. **非法值**（如 `garbage`）⇒ 已回退 `off`
///   2. **`strict` 已设置** ⇒ 报出它**真实的生效范围**（见下）
///
/// ## 第 2 条为什么还留着：BUG-470 R1 的措辞已被 BUG-476 推翻
///
/// 本分支初版写的是「strict 只降权、效果接近 soft」——那是 BUG-470 落地时的真实状态，
/// 也是当轮台账里单开的 BUG-476。BUG-476 已把 `challenge_missing` 接到**门层硬拒**：
/// 判定面是单一真源 `strict_challenge_denial`（`engine_rsv.mbt`），接线 4 处——
///   · `rsv_set` / `rsv_try_set`（`reserve_scope` 两道门）⇒ 直接 `Err`
///   · `locks_try_acquire`（`lock_acquire`）⇒ `granted=false` + `action=strict_challenge_missing`
///     （该函数返回 `LockAcquireOutcome`，不能 `Err`，见其注释）
///   · `claim`（`server.mbt` 的 handler 层）⇒ `ToolError`
/// 锁：`engine_bug476_strict_wbtest.mbt` S1~S6（S6 是接线**计数**格，删掉任一处必红）。
///
/// ⚠️ 这一条**仍然要在启动时喊一声**，因为生效范围有界，而两个方向的误解都真实存在：
///   · `soft` 是当前默认（2026-11-13 flip）；`off` / `strict` 都需显式设置；
///   · strict 只覆盖上面那 4 处 —— `execute` / `verify` / `submit` / `archive` 走的是
///     无挑战门的路径（那是 BUG-430c），**设了 strict 不等于全链路都要认证**。
///   本文案的职责就是说清「哪几道门真拒、哪几道不拒」：既不许再说「一条都不拒」，
///   也不许反过来说成「已经全面严格」—— 两个方向都是**自述滞后现状**
///   （`AI-DEVELOPMENT-STANDARD.md` §4.1；AGENTS.md：每次启动都在撒谎的自述比没有更糟）。
pub fn auth_mode_startup_warning() -> String {
  let raw = match @env.get_env_var("FIST_AUTH_MODE") {
    Some(v) => v
    None => ""
  }
  let w = auth_mode_warning(raw)
  if w != "" {
    return w
  }
  if normalize_mode_str(raw) == "strict" {
    return "FIST_AUTH_MODE=strict 已生效，但**生效范围有界**（BUG-476）：" +
      "硬拒的门 = reserve_scope（rsv_set / rsv_try_set）、lock_acquire（locks_try_acquire）、" +
      "claim —— 这四处无 challenge 一律**拒绝**，不是降权。" +
      "范围之外：execute / verify / submit / archive 走无挑战门的路径（BUG-430c）⇒ " +
      "设了 strict 不等于全链路都要认证。要放宽请把 FIST_AUTH_MODE 设为 soft 或 off。"
  }
  ""
}
