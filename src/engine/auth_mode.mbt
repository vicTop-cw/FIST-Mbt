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
// ## 为什么默认 `off`
//
//   决策单：首次上线默认 `off`，观察一周后 flip 到 `soft`。
//   `off` 的行为必须与修前**逐字相同**，否则「上线开关」这件事本身就有回归风险。
// ============================================================================

///|
/// 认证模式（三档）。
///
/// `derive(Eq, Debug)`：让测试能 `assert_eq(auth_mode(), Off)` 并打印差值。
pub enum AuthMode {
  /// 只关「对无钥匙者也降权」这层；有钥匙不传仍降权（= 修前行为）
  Off
  /// 无钥匙也降权（owner 批准的策略 B）
  Soft
  /// 一律拒绝（未启用，前置条件见 BUG-470 决策单）
  Strict
} derive(Eq, Debug)

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
///   · 空串 / 未设 ⇒ `Off`（默认值）
///   · **其它任何值** ⇒ `Off` + **warning**（见 `auth_mode_warning`）
///
/// ⚠️ **非法值回退 `Off` 而不是 `Strict`**：写错一个字母不该让现网停摆。
///   fail-closed 在这里是**错的方向** —— 因为本开关的「严」档会让 56 个调用方失败，
///   而「回退默认」只是维持现状。**配置写错 ≠ 环境不安全。**
pub fn auth_mode_parse(raw : String) -> AuthMode {
  match normalize_mode_str(raw) {
    "" => Off
    "off" => Off
    "soft" => Soft
    "strict" => Strict
    // 非法值 ⇒ 回退默认（不 panic、不取最严）
    _ => Off
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
    "\" 不是合法值（期望 off / soft / strict）⇒ **已回退 off（维持现状）**。" +
    "配置写错不会让现网停摆，但请修正，否则你以为开了 B 其实没开。"
  }
}

///|
/// 规范化：去两端空白 + 转小写（`FIST_AUTH_MODE=OFF` 与 `off` 等价）。
fn normalize_mode_str(raw : String) -> String {
  // `trim()` 返回 StringView ⇒ 先转 String 再 to_lower()
  let t : String = raw.trim().to_string()
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
    // 缓存**规范化后的合法值**（非法值也缓存为 "off"，避免每次调用都重复判定）
    let n = normalize_mode_str(raw)
    auth_mode_slot[0] = if n == "off" || n == "soft" || n == "strict" {
      n
    } else {
      "off"
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
/// 仅在**进程启动时调一次**，拿到「配置有问题」的 warning（无问题则空串）。
///
/// 两类问题都返回非空：
///   1. **非法值**（如 `garbage`）⇒ 已回退 `off`
///   2. **`strict` 尚未真正生效**（见下）
///
/// ⚠️ 为什么 `strict` 也要告警：本版只做到「返回专用 `challenge_missing` 标签 + 降权」，
///   **各门的消费者还没据此硬拒** ⇒ 实际效果接近 `soft`。
///   若有人设 `strict` 以为「现在严格了」，那是**比不设更危险**的状态（以为自己安全了）。
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
    return "FIST_AUTH_MODE=strict 已设置，但**本版 strict 尚未真正拒绝**：" +
      "目前只把 role_source 标成 challenge_missing 并降权到 Executor，" +
      "各门的消费者（rsv_set / rsv_try_set / locks_try_acquire / claim）还没据此硬拒 ⇒ " +
      "**实际效果接近 soft**。不要以为已经严格了（见 BUG-470 R1）。"
  }
  ""
}
