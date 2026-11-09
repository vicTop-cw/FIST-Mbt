/// server/mcpcf_embed_bug583_wbtest.mbt —— BUG-583 前置行为锁 · mcpcf 调用层
///
/// ## 这一份存在的理由：mcpcf 面此前**零测试覆盖**
///
/// 账本 BUG-583「覆盖缺口」点名：`grep` 全仓除生产文件外无人引用 `mcpcf_*` ⇒ 修复没有
/// 行为基线可对照。本文件把 mcpcf 的熔断调用面（`tool_circuit` / `tool_watchdog`，
/// 即 `mcpcf_embed.mbt:267`/`:360` 那两行算式的**唯一两个消费者**）第一次打到调用面。
///
/// ## 为什么「2038 那一档」不能锁在这一层（可测性缺口，交统帅记流程债）
///
/// mcpcf 的时钟不可注入：`tool_circuit`/`tool_watchdog` 的 `now_secs` 是内部
/// `(@env.now().reinterpret_as_int64() / 1000L).to_int()` 现算的，参数面只有
/// `circuit` / `action` / `ns` 三个键 ⇒ **传不进一个假时钟**。`set_engine`（`:19`）
/// 只注入引擎、不注入时间。于是：
///   · 要在这层锁出 2039 档，必须先给 mcpcf 加一个时钟入参（＝改产品码），
///     越出本车道「advance 模式：只加测试、不改行为」的边界 ⇒ 不做；
///   · 改而用 `bug583_04` 这一格把「注入不进去」这件事本身钉成断言
///     （传 `now_secs` 键 ⇒ 被静默丢弃，落库的仍是墙钟截断值）。将来若有人为可测性
///     加了时钟入参，这一格会红 ⇒ 提醒他同步改写，而不是留一条与产品码脱节的假锁。
///   · 2038 档的行为基线因此落在引擎层：见 `src/engine/engine_circuit_bug583_wbtest.mbt`
///     （两枚正性哨兵 `engine_circuit.mbt:136`/`:170` 都在引擎层，调用方是谁不影响判定）。
///
/// ## 行为诚实性（每格钉的是**当前**行为）
///
/// `bug583_02` 的时间域带（1.7e9 ≤ opened_at ≤ Int32 上界）是**刻意的定时发信器**：
/// 2038-01-19T03:14:07Z 之后 mcpcf 真喂进负值 ⇒ 这一格必然红。
/// 届时刻**不许删格、不许改绿**：按 BUG-583 修复方向（①换时基 / ②域拒绝 / ③Int64 化）
/// 把它改写成修复后的期望形状，并在 FIXED 段写明改成了什么。
///
/// ## 变异对照（判例-29/30；真跑读数见回传与 memory/2026-11-09.md）
///
///   · 本文件的红面由**引擎层那两行**驱动：把 `engine_circuit.mbt:136` 的 `opened_at > 0`
///     改成 `opened_at != 0` ⇒ 引擎层 `bug583_02`/`bug583_06`/`bug583_07` 必红，而本文件
///     全部 4 格**必须保持绿** ⇒ 证明两文件各管各的档，mcpcf 面没有把引擎层的红面遮掉
///     （今天墙钟仍在正域，mcpcf 面本来就够不到绕回档 —— 这正是格 4 钉住的缺口）。
///   · 把 `mcpcf_embed.mbt:267` 的截断算式换成 `@ops.iso_to_secs(now_utc())`（修复方向①）
///     ⇒ 本文件 `bug583_02` 必红（ops 基 2024 起算，实得 90252645 对 oracle 1794233445）；
///     `bug583_03` 同时必红：`:267` 写 ops 基、`:360` 仍读 Unix 基 ⇒ watchdog 把 opened_at
///     看成「远在 1972 年」立刻跳半开 —— 这就是账本 WARNING 的「两种时基同库同表 ⇒ half-open
///     随机」形状被本锁自己抓出来的实证。⚠ 只变异 `:267` 不动 `:360` 是有意的：
///     两行必须同批收，谁漏一行这一格就红给谁看。
///   · `bug583_01` 在方向①变异下**保持绿**属预期：它钉的是「holder 注入生效 + 入口形状」，
///     与时基无关（所以修复时不需要改写它，需要改写的是格 2/格 3 的时间语义断言）。

///|
/// 取 mcpcf 工具回执首块文本（`ok_text`/`err_text`/`ToolResult::text` 都走 Text 块）。
fn b583_mcpcf_text(r : @mcp.ToolResult) -> String {
  match r.content[0] {
    @mcp_types.ContentBlock::Text(s, ..) => s
    _ =>
      abort(
        "mcpcf 回执首块不是 Text 块（入口形状变了，需同步改写本辅助）",
      )
  }
}

///|
/// 解析回执 JSON 文本。解析不出来＝回执形状变了，直接 abort 让格红（不静默放行）。
fn b583_mcpcf_json(r : @mcp.ToolResult) -> Json {
  let text = b583_mcpcf_text(r)
  @mcp.parse_json(text) catch {
    _ => abort("mcpcf 回执不是合法 JSON: " + text)
  }
}

///|
/// mcpcf 调用点 `:267`/`:360` 那句算式的**测试侧独立复算**（同一形状，用途是行为锚点）。
fn b583_wall_clock_secs() -> Int32 {
  (@env.now().reinterpret_as_int64() / 1000L).to_int()
}

///|
fn b583_field(j : Json, key : String) -> Json {
  match jget(j, key) {
    Some(v) => v
    None => abort("回执缺字段 " + key + ": " + j.stringify())
  }
}

///|
/// 熔断回执里的 Int32 字段（`cb_json` 用 `Json::number` 写入）。
fn b583_int_field(j : Json, key : String) -> Int32 {
  match b583_field(j, key) {
    Json::Number(n, ..) => n.to_int()
    _ => abort(key + " 不是数字: " + j.stringify())
  }
}

///|
fn b583_str_field(j : Json, key : String) -> String {
  match b583_field(j, key) {
    Json::String(s) => s
    _ => abort(key + " 不是字符串: " + j.stringify())
  }
}

///|
fn b583_bool_field(j : Json, key : String) -> Bool {
  match b583_field(j, key) {
    Json::True => true
    Json::False => false
    _ => abort(key + " 不是布尔: " + j.stringify())
  }
}

///|
/// 造 mcpcf 工具入参（只放该工具真正读取的键；未知键由调用方**故意**塞进来时用 `extra`）。
fn b583_args(circuit : String, action : String) -> Json {
  Json::object({
    "circuit": Json::string(circuit),
    "action": Json::string(action),
  })
}

///|
/// 注入一个**内存后端**引擎到 mcpcf 的模块级 holder ⇒ 这一格之后 mcpcf 的所有工具
/// 都跑在这份引擎上，不会去开 `%LOCALAPPDATA%\mcpconftest\data\mcpconftest-ops.db`
/// （`ensure_engine()` 见 holder 已有值就直接用）。测试结束务必 `reset_engine()` 还原。
fn b583_sandbox_engine() -> @engine.FistEngine {
  let e = @engine.FistEngine::new()
  set_engine(e)
  e
}

///|
/// 【格 1｜可达性 + 注入真的有效】调用面第一次打到 mcpcf 的熔断工具。
/// 意图：证明「先 `set_engine` 再调工具」这条路能让 mcpcf 用**我给的**引擎，
/// 且状态在调用面连续可见（2 次直连 fail + 1 次工具 fail ⇒ 第 3 次必须触发 Open）。
/// 这一步同时是「零落盘」的前提：没有它，任何 mcpcf 测试都会往 %LOCALAPPDATA% 写库。
/// 修复后本性格继续为绿（它钉的是入口形状，不是时间语义）。
test "bug583_01_mcpcf_circuit_surface_reachable_via_holder_injection" {
  let e = b583_sandbox_engine()
  let circuit = "b583-mcpcf-reach"
  // 直连引擎打 2 次失败（默认 threshold=3、window=60、recovery=30）。
  // 时点必须贴着墙钟取（比 now 早 20s / 10s）：否则 mcpcf 那一次 fail 的 `now - last_ts > 60`
  // 会把窗口计数复位成 1，格 1 就测不到「两路共用同一份状态」了。
  let base = b583_wall_clock_secs()
  ignore(e.circuit_fail(circuit~, now_secs=base - 20))
  ignore(e.circuit_fail(circuit~, now_secs=base - 10))
  // 第 3 次走 mcpcf 工具面：若它用的是另一份引擎（自举的 SQLite 库），这里只会数到 1
  let r = tool_circuit(b583_args(circuit, "fail"))
  let j = b583_mcpcf_json(r)
  assert_eq(b583_str_field(j, "circuit"), circuit)
  assert_eq(
    b583_int_field(j, "failures"),
    3,
    msg="mcpcf 工具没跑在注入的引擎上（计数没接上）⇒ holder 注入路径变了，需同步改写本锁",
  )
  assert_eq(b583_str_field(j, "state"), "open")
  assert_eq(b583_bool_field(j, "allow_call"), false)
  assert_eq(b583_int_field(j, "threshold"), 3)
  assert_eq(b583_int_field(j, "recovery_secs"), 30)
  // 空 circuit 必须被入口拒掉（回执形状是 ERROR 串，不是引擎调用）
  let bad = tool_circuit(b583_args("", "fail"))
  assert_true(
    b583_mcpcf_text(bad).contains("circuit requires circuit name"),
    msg="mcpcf.circuit 的空参拒绝面消失（入口校验搬家）",
  )
  reset_engine()
  assert_true(
    get_engine() is None,
    msg="reset_engine 不清 holder ⇒ 沙箱引擎会泄漏给同包后续测试",
  )
}

///|
/// 【格 2｜时基形状锁：mcpcf 喂的是 Unix 纪元秒（Int32 截断），不是 ops_ts 的 2024 基】
/// 当前（缺陷）行为：`opened_at` 落进引擎的是**裸 Unix 纪元秒截成 Int32**。
/// 两条断言分工：
///   (a) 与调用点算式的独立复算一致（±5s 容差）⇒ 证明「这一行算式确实在跑」；
///   (b) 值落在 Unix 正域带 [1.7e9, Int32 上界] ⇒ **定时发信器**：2038-01-19 后必红
///       （届时刻不许删格，按 BUG-583 方向①/②/③改写期望形状）。
/// 修复方向对照：
///   · 方向①（mcpcf 边界换 `@ops.iso_to_secs` 基）⇒ (b) 立刻红（ops 基量级 ≈6e7），
///     (a) 也红（不再是墙钟纪元秒）⇒ 两处都是预期，改写为「值落在 ops 基声明域」。
///   · 方向③（引擎 Int64 化）⇒ (a) 仍应成立且容差语义变精确，(b) 上界断言随签名改写。
test "bug583_02_mcpcf_feeds_raw_unix_epoch_seconds_into_int32" {
  ignore(b583_sandbox_engine())
  let circuit = "b583-mcpcf-timebase"
  // 三次工具面 fail ⇒ 第 3 次进 Open，opened_at = 那一次的 now_secs（即 :267 的算式结果）
  ignore(tool_circuit(b583_args(circuit, "fail")))
  ignore(tool_circuit(b583_args(circuit, "fail")))
  let j = b583_mcpcf_json(tool_circuit(b583_args(circuit, "fail")))
  assert_eq(b583_str_field(j, "state"), "open")
  let opened = b583_int_field(j, "opened_at")
  // (a) 与调用点算式同值（±5s：三次调用之间墙钟会走 0~几秒）
  //     这一行是 `mcpcf_embed.mbt:267` 的**测试侧副本**，用途是行为锚点：
  //     产品码那两行一改，(a)(b) 就与它一起变红 ⇒ 时基搬家不可能静默发生。
  let oracle = b583_wall_clock_secs()
  assert_true(
    opened >= oracle - 5 && opened <= oracle + 5,
    msg="opened_at 不是 :267 那句 Unix 秒算式的结果（实得 " +
      opened.to_string() +
      "，oracle " +
      oracle.to_string() +
      "）⇒ 时基已搬家，需同步改写本格",
  )
  // (b) Unix 正域带：把「不是 ops 基」与「还没绕回」两件事同时钉住
  assert_true(
    opened >= 1700000000,
    msg="BUG-583 定时发信器：opened_at 应仍是可表示的正 Unix 纪元秒；2038-01-19T03:14:07Z 后本条必红（截断绕负）⇒ 不许删格，按修复方向改写期望值",
  )
  assert_true(
    opened <= 2147483647,
    msg="opened_at 必须落在 Int32 域内（越界即绕回负域，正是 BUG-583 的前提）",
  )
  // 对照：主 MCP 路径用的 ops_ts 基（2024-01-01 起算）量级远小于 Unix 纪元秒
  // ⇒ 两条路径**今日确实两种时基**（车道 G 隔离结论的机器可读那一半）
  let ops_base = @ops.iso_to_secs("2026-01-01T00:00:00Z")
  assert_true(
    ops_base > 0 && ops_base < 1700000000,
    msg="ops 基应与 Unix 纪元秒量级不同（实得 " +
      ops_base.to_string() +
      "）；相同则两基已收敛，本格需改写成单一时基形状",
  )
  reset_engine()
}

///|
/// 【格 3｜mcpcf.watchdog 走 :360 那一行；卡 Open 在调用面读得到但读不出原因】
/// 意图：`tool_watchdog` 是 `:360` 那行截断算式的另一个消费者（且只调 `circuit_status`）。
/// 这一格钉住两件事：① 那一行确实可达、回执里 `circuit` 对象可读；② 与 `mcpcf.circuit`
/// 的 status 走同一份状态 ⇒ 两个入口共享同一枚哨兵，修一个不够。
/// 修复后本性格继续为绿（形状面），但格 2 那类时间域断言需随之改写。
test "bug583_03_watchdog_reads_the_same_breaker_state_as_circuit_tool" {
  ignore(b583_sandbox_engine())
  let circuit = "b583-mcpcf-watchdog"
  ignore(tool_circuit(b583_args(circuit, "fail")))
  ignore(tool_circuit(b583_args(circuit, "fail")))
  let after_open = b583_mcpcf_json(tool_circuit(b583_args(circuit, "fail")))
  assert_eq(b583_str_field(after_open, "state"), "open")
  let opened = b583_int_field(after_open, "opened_at")
  // watchdog（:360）读同一熔断器：状态、allow_call、opened_at 必须与 circuit（:267）一致
  let wd = b583_mcpcf_json(
    tool_watchdog(Json::object({ "circuit": Json::string(circuit) })),
  )
  assert_eq(b583_bool_field(wd, "ok"), true)
  let inner = b583_field(wd, "circuit")
  assert_eq(b583_str_field(inner, "state"), "open")
  assert_eq(b583_bool_field(inner, "allow_call"), false)
  assert_eq(
    b583_int_field(inner, "opened_at"),
    opened,
    msg="两个入口读到不同的 opened_at ⇒ 时基/存储路径分叉，BUG-583 的「两基同库」风险复活",
  )
  // 后端自述：注入的是内存引擎（⇒ 这一格没碰 %LOCALAPPDATA%）
  assert_eq(b583_str_field(wd, "backend"), "memory")
  // 未到期（recovery=30，墙钟几乎同一秒）⇒ 仍 open 是**正确**行为，不是缺陷；
  // 缺陷只在 opened_at 为负时把「到期」也吃掉（那一档见引擎层 bug583_02）
  let not_due = b583_mcpcf_json(tool_circuit(b583_args(circuit, "status")))
  assert_eq(b583_str_field(not_due, "state"), "open")
  reset_engine()
}

///|
/// 【格 4｜可测性缺口本身被钉住】mcpcf 的参数面没有时钟入参 ⇒ 假时钟传不进去。
/// 意图：把「这一层锁不到 2038 档」从口头结论变成一条会过期的断言。
/// 现在传 `now_secs=-2117514496` 被**静默丢弃**，落库的仍是墙钟截断值（正域）。
/// 将来若有人为可测性给 mcpcf 加了时钟入参（BUG-583 修复的必要前置之一），
/// 这一格会红 ⇒ 他必须把本格改写成「注入生效」的期望形状，而不是留下一条假锁。
test "bug583_04_mcpcf_has_no_clock_injection_point_so_2038_is_unreachable_here" {
  ignore(b583_sandbox_engine())
  let circuit = "b583-mcpcf-noclock"
  let neg_2039 : Int32 = -2117514496
  // 三次都带着「假时钟」调用：期望它被忽略（当前行为），落库仍是墙钟
  let fake = Json::object({
    "circuit": Json::string(circuit),
    "action": Json::string("fail"),
    "now_secs": Json::number(neg_2039.to_double()),
  })
  ignore(tool_circuit(fake))
  ignore(tool_circuit(fake))
  let opened_via_fake = b583_mcpcf_json(tool_circuit(fake))
  assert_eq(b583_str_field(opened_via_fake, "state"), "open")
  let opened = b583_int_field(opened_via_fake, "opened_at")
  assert_true(
    opened != neg_2039,
    msg="传入的 now_secs 竟然生效了 ⇒ mcpcf 已有时钟注入点，本格需改写为「注入生效 + 2038 档可在这一层锁」的形状（并回看引擎层是否重复覆盖）",
  )
  assert_true(
    opened > 0,
    msg="时钟注入点已存在但落库的不是注入值 ⇒ 注入只对部分入口生效，需把 :267 与 :360 两行一起收（BUG-583 的两处同形）",
  )
  reset_engine()
}
