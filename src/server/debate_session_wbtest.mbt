/// debate_session_wbtest.mbt —— BUG-455 第二批：`debate` 族的 **session 管理**此前零覆盖。
///
/// **为什么这批是"真零覆盖"（区别于上一批的假阳性）**：
/// `src/ops/ops_hats_wbtest.mbt` 有 9 格，但测的全是**纯函数**
/// （`parse_hat` / `parse_hats` / `hats` 角色 / `debate_summary` / `valid_verdict` / `hat_verdict`）。
/// 而 `debate_convene` / `debate_register` / `debate_verdict` 三个工具的**核心逻辑是 session 管理**，
/// 它住在 `src/server/server.mbt`：`DebateSession` / `DebateRegistry` / `debate_sessions`(模块级) /
/// `debate_next_session_id()` / `split_hat_items()` —— **这些一行测试都没有**。
///
/// 覆盖：`debate_next_session_id` 的**格式 + 单调性**、`split_hat_items` 的**三种分隔符**、
/// `DebateRegistry` 的**空表 + 插入可见**。

///|
/// 锁 1：`debate_next_session_id` 的**格式**必须是 `debate-<8位日期>-<3位序号>`。
///
/// 为什么不钉具体日期：`debate_day_key()` 走 `@env.now()`（时间相关），钉死日期会让
/// 本格**过一天就红**。钉的是**形状**：前缀 `debate-`、日期 8 位纯数字、序号 3 位纯数字。
test "debate455_next_session_id_shape" {
  let id = debate_next_session_id()
  assert_true(id.has_prefix("debate-"))
  let chars = id.to_array()
  // "debate-" 是 7 个字符，后面必须恰好 12 个（8 位日期 + '-' + 3 位序号）
  assert_eq(chars.length(), 19)
  // 日期 8 位纯数字
  for i = 7; i < 15; i = i + 1 {
    let c = chars[i]
    assert_true(c >= '0' && c <= '9')
  }
  assert_eq(chars[15], '-')
  // 序号 3 位纯数字
  for i = 16; i < 19; i = i + 1 {
    let c = chars[i]
    assert_true(c >= '0' && c <= '9')
  }
}

///|
/// 锁 2：同一进程内连续调用，**序号必须递增**（不是恒定 `-001`）。
///
/// 这条钉住「`n = 数同前缀 key 的个数 + 1`」这个实现：
/// 若有人把 `n = n + 1` 写成 `n = 1`（或忘记 +1），本格立即红。
/// **用 `debate_sessions.sessions` 的真实状态**验证，不 mock。
test "debate455_next_session_id_monotonic" {
  let before = debate_sessions.sessions.length()
  let a = debate_next_session_id()
  // 模拟 convene：把 a 真正写进注册表（否则下一次还是同一个序号）
  debate_sessions.sessions.set(a, DebateSession::{
    threshold: 0.6,
    verdicts: [],
    created_at: "",
  })
  let b = debate_next_session_id()
  assert_eq(debate_sessions.sessions.length(), before + 1)
  assert_true(a != b) // 序号必须变
  // 收尾：删掉本格插入的 key，不污染其它格
  debate_sessions.sessions.remove(a)
  assert_eq(debate_sessions.sessions.length(), before)
}

///|
/// 锁 3：`split_hat_items` 必须认**三种**分隔符（英文逗号 / 中文顿号 / 中文逗号），
/// 且**空段忽略、逐段 trim**。
///
/// 这是 `debate_convene` 的 `hats` 参数解析面：用户写 `"white,black、yellow，green"`
/// 必须切出 4 段。若只认英文逗号，三种混写会切错。
test "debate455_split_hat_items_three_separators" {
  assert_eq(split_hat_items("white,black、yellow，green").length(), 4)
  assert_eq(split_hat_items(",white,,black,").length(), 2)
  assert_eq(split_hat_items("").length(), 0)
  assert_eq(split_hat_items("、、，").length(), 0)
  let got = split_hat_items(" white , black ")
  assert_eq(got.length(), 2)
  assert_eq(got[0], "white")
  assert_eq(got[1], "black")
}

///|
/// 锁 4：`DebateRegistry::new()` 是**空表**，且插入后**可见、可删**。
///
/// 钉住「不落库」这个诚实承诺的一半：进程内表就是普通 `Map`，
/// 没有隐藏的持久化副作用。若有人给 `new()` 塞了预置 session（比如为了"演示好看"），
/// 本格会红。
test "debate455_registry_starts_empty_and_mutates" {
  let r = DebateRegistry::new()
  assert_eq(r.sessions.length(), 0)
  r.sessions.set("debate-20260101-001", DebateSession::{
    threshold: 0.6,
    verdicts: [],
    created_at: "2026-01-01T00:00:00Z",
  })
  assert_eq(r.sessions.length(), 1)
  assert_true(r.sessions.contains("debate-20260101-001"))
  r.sessions.remove("debate-20260101-001")
  assert_eq(r.sessions.length(), 0)
}
