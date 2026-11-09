/// engine/engine_circuit_bug583_wbtest.mbt —— BUG-583 前置行为锁（解锁后续修复用，非修复本身）
///
/// ## 缺陷形态（修复前的当前行为，本文件逐字钉住）
///
/// `src/server/mcpcf_embed.mbt:267` 与 `:360` 把裸 Unix 毫秒秒化后 `.to_int()` 截断，
/// 喂给 `FistEngine::circuit_fail/circuit_succeed/circuit_status(now_secs : Int32)`。
/// 2038-01-19T03:14:07Z 之后该秒数超出 Int32 上界 ⇒ **绕回成负值**。
/// 坏的不是算术，是 `src/engine/engine_circuit.mbt` 里两枚**正性哨兵**：
/// - `:136` `opened_at > 0 &&` ⇒ 负 opened_at ⇒ 恢复门恒假 ⇒ **Open 永不变 Half-Open**；
/// - `:170` `rec > 0 && last_ts > 0 && …` ⇒ 负 last_ts ⇒ stale 复位恒假 ⇒ **探测丢失后复位失效**
///   （BUG-34 的半开节流退化成永久快速失败）。
///
/// ## 为什么锁在引擎层（车道 H 现读结论）
///
/// mcpcf 的时钟不可注入：`tool_circuit`/`tool_watchdog` 内部直接 `@env.now()`，
/// `set_engine` 只注入**引擎**、不注入**时钟** ⇒ 在 mcpcf 调用层写不出 2039 那一档
/// （要写得先动产品码，突破本车道「只加测试不改行为」边界）。而两枚哨兵都在引擎层，
/// 引擎层的 `now_secs` 是**入参**、想喂什么喂什么 ⇒ 引擎层是「等价且可达」的那一层。
/// 哨兵判定与调用方是谁无关（mcpcf/主 MCP 路径共用同一 `engine_circuit.mbt`），
/// 故这一档锁对 mcpcf 面同样有效；mcpcf 调用层自身的可达性另见
/// `src/server/mcpcf_embed_bug583_wbtest.mbt`。
///
/// ## 修复后必须被【故意改写】的格（不许悄悄改绿）
///
/// 下列格钉的是**缺陷行为**。任何修复方向（BUG-583 方向①换时基 / ②域拒绝 / ③Int64 化）
/// 落地后这些格必然红 —— 那时**由修复者逐格改写**成修复后的期望行为，并在 FIXED 段写明
/// 「哪几格被改写、改成了什么」。看到红就顺手删格 = 把行为基线一起删了，禁止。
/// 每格注释给出「修复后该断言应该变成什么」，对照表：
///   bug583_01_truncation……            修复后仍应红？否：截断算术本身不变（那是调用方的事），
///                                     若走方向①/③则这条**保留**，作为「Int32 域会绕回」的事实依据。
///   bug583_02_negative_opened_stuck…  ⇒ 期望改成 `state == "half_open"`（方向③）
///                                     或 `allow_call == true` 的显式 fail-open（方向②拒绝档）。
///   bug583_04_negative_last_ts_no…    ⇒ 期望改成 stale 复位生效（`allow_call == true`）。
///   bug583_06_receipt…（卡 Open 零线索）⇒ 期望回执带异常线索（域拒绝文案或 persist 侧报错）。
///   bug583_07_sqlite_negative…        ⇒ 方向③下 `cb_get` 元组变 Int64，本格需随签名改写。
///
/// ## 变异对照（判例-29/30 硬要求；真跑读数见回传与 memory/2026-11-09.md）
///
/// 两发都打**代码行**（非注释；`opened_at > 0` / `last_ts > 0` 在全文各只出现 1 次，
/// 变异前用 `grep -n` 定位、变异后 `sha256sum` 对回原文件确认逐字还原）：
///   · M1 把 `engine_circuit.mbt:136` 的 `opened_at > 0` 改成修复形状 `opened_at != 0`
///     ⇒ `bug583_02` / `bug583_06` / `bug583_07`（SQLite 后端那一档）三格红，
///     合法域对照格 `bug583_01/03/04/05` 与 mcpcf 调用层 4 格全绿
///     ⇒ 红面精确落在「负 opened_at 被放行到半开」这一行，不在合法域。
///   · M2 把 `engine_circuit.mbt:170` 的 `last_ts > 0` 改成修复形状 `last_ts != 0`
///     ⇒ 只有 `bug583_04` 一格红（stale 复位生效、探测被放行）
///     ⇒ 证明格 4 真在看第 170 行，而不是跟着 M1 那行一起红（两枚哨兵各有自己的格）。

///|
/// Int32 上界秒（2038-01-19T03:14:07Z）：Int32 域内最后一个合法 Unix 秒。
let b583_int32_max_secs : Int32 = 2147483647

///|
/// 2026-01-01T00:00:00Z 的 Unix 秒（合法 Int32 正域，对照格基准）。
let b583_unix_2026 : Int32 = 1767225600

///|
/// 2039-01-01T00:00:00Z 的 Unix 秒经 mcpcf 那一句 `.to_int()` 截断后的值。
/// 账本 BUG-583 探针同值：`trunc(2177452800000L / 1000L) = -2117514496`。
let b583_unix_2039_truncated : Int32 = -2117514496

///|
/// mcpcf 调用点的时基算式（测试侧副本，来源 `src/server/mcpcf_embed.mbt:267`/`:360` 逐字同形）：
/// `(@env.now().reinterpret_as_int64() / 1000L).to_int()`。
/// 这里把它参数化成「给定毫秒 → 喂进引擎的那个 Int32」，因为产品码读的是墙钟、
/// 测试无法把墙钟搬到 2039（见文件头「为什么锁在引擎层」）。
/// ⚠ 这是**故意**留的第二份算式：产品码那两行一改（换时基/Int64/域拒绝），本函数就会
///   与产品码不再同形 ⇒ 靠 `src/server/mcpcf_embed_bug583_wbtest.mbt` 的时基形状格发红，
///   不允许「改了产品码而测试还在描述旧算式」静默通过。
fn b583_mcpcf_secs_from_ms(ms : Int64) -> Int32 {
  (ms / 1000L).to_int()
}

///|
/// 熔断回执取字段（照 `engine_circuit_test.mbt` 的拆包样式，名字前缀 b583_ 避免同包漂移）。
fn b583_str_field(j : Json, key : String) -> String {
  match jget(j, key) {
    Some(Json::String(s)) => s
    _ => abort("\{key} 缺失: " + j.stringify())
  }
}

///|
fn b583_int_field(j : Json, key : String) -> Int32 {
  match jget(j, key) {
    Some(Json::Number(n, ..)) => n.to_int()
    _ => abort("\{key} 缺失: " + j.stringify())
  }
}

///|
fn b583_allow(j : Json) -> Bool {
  match jget(j, "allow_call") {
    Some(Json::True) => true
    Some(Json::False) => false
    _ => abort("allow_call 缺失: " + j.stringify())
  }
}

///|
/// 直接读库里的熔断行（`(state, failures, w, thr, rec, opened_at, last_fail_ts)`）。
fn b583_row(
  e : FistEngine,
  circuit : String,
) -> (String, Int32, Int32, Int32, Int32, Int32, Int32) {
  match e.store.cb_get("default", circuit) {
    Some(r) => r
    None => abort("熔断行不存在: " + circuit)
  }
}

///|
/// 干净 SQLite 引擎（BUG-455：沙箱库统一落 `.fist-mbt/tmp/`，不落仓库根）。
fn b583_sqlite_engine(db_name : String) -> FistEngine {
  let db_path = ".fist-mbt/tmp/" + db_name
  match @store.SqliteStore::open(db_path) {
    Some(s) => ignore(s.clear())
    None => abort("sqlite open failed: " + db_path)
  }
  match FistEngine::open_sqlite(db_path) {
    None => abort("engine open failed: " + db_path)
    Some(e) => e
  }
}

///|
/// 【格 1｜纯算术，无库】2038 边界一秒一格跨进负域 ⇒ 缺陷起点，与状态机无关。
/// 意图：把「Unix 纪元秒 → Int32」的绕回点钉成数字，后续所有格都以此为前提。
/// 修复后这一格**保留**（无论换时基还是 Int64 化，「Int32 装不下 2038 后的纪元秒」都是事实；
/// 只有当产品码不再把纪元秒截成 Int32 时，本格的**存在理由**才消失，届时改写为
/// 「mcpcf 侧算式必须落在 Int64/ops 基」的形状断言，而不是删掉）。
test "bug583_01_truncation_unix_secs_to_int32_wraps_negative_after_2038" {
  // Int32 上界那一秒仍合法（2038-01-19T03:14:07Z）
  assert_eq(b583_mcpcf_secs_from_ms(2147483647000L), b583_int32_max_secs)
  assert_true(b583_int32_max_secs > 0)
  // 下一秒 ⇒ 绕回 Int32 负域（缺陷起点；不是「读不到时间」而是「读到一个负数」）
  assert_eq(b583_mcpcf_secs_from_ms(2147483648000L), -2147483648)
  // 2026（今天）仍在正域：对照，证明本格不是恒真断言
  assert_eq(b583_mcpcf_secs_from_ms(1767225600000L), b583_unix_2026)
  assert_true(b583_mcpcf_secs_from_ms(1767225600000L) > 0)
  // 2039-01-01：账本探针同值，且正是 mcpcf 会喂进 now_secs~ 的那个数
  assert_eq(b583_mcpcf_secs_from_ms(2177452800000L), b583_unix_2039_truncated)
  assert_true(
    b583_unix_2039_truncated < 0,
    msg="2039 纪元秒截断后必须是负值，否则 BUG-583 的正性哨兵前提不成立",
  )
}

///|
/// 【格 2｜恢复门不可达｜缺陷行为】臂 B：两端同为 2039 后截断负值。
/// 减法同余正确（差恰好 30），坏在 `engine_circuit.mbt:136` 的 `opened_at > 0` ⇒
/// Open 永远进不了 Half-Open，熔断永久卡死。
/// 修复后期望（方向③Int64 化）：`state == "half_open"` 且 `allow_call == true`；
/// 修复后期望（方向②域拒绝）：回执显式报错/降级，**不得**是本格现在这个「静默 open」。
test "bug583_02_negative_opened_at_makes_half_open_unreachable" {
  let e = FistEngine::new()
  // threshold=1 一次失败即 Open；opened_at 落进负域
  ignore(
    e.circuit_fail(
      circuit="b583-armB",
      now_secs=b583_unix_2039_truncated,
      threshold=1,
    ),
  )
  let (st, _, _, _, _, opened, last_ts) = b583_row(e, "b583-armB")
  assert_eq(st, "open")
  assert_true(
    opened < 0,
    msg="开路时刻应已被截断成负值（前提），实得 " +
      opened.to_string(),
  )
  assert_true(last_ts < 0)
  // 过满一个恢复窗（recovery 默认 30）：减法形本身是对的
  let probe_at = b583_unix_2039_truncated + 30
  assert_eq(
    probe_at - b583_unix_2039_truncated,
    30,
    msg="减法在同余下仍正确 ⇒ 缺陷只可能来自正性哨兵，不是算术（账本臂 B 结论）",
  )
  let s = e.circuit_status(circuit="b583-armB", now_secs=probe_at)
  // ← 当前（缺陷）行为：门恒假，仍 open、仍快速失败
  assert_eq(
    b583_str_field(s, "state"),
    "open",
    msg="BUG-583 复现：opened_at<0 时恢复门 `engine_circuit.mbt:136` 恒假，Open 不可退出",
  )
  assert_eq(b583_allow(s), false)
  // 再连查 10 个恢复窗：不是「晚一点就恢复」，是**永久**卡住
  for i = 1; i <= 10; i = i + 1 {
    let later = e.circuit_status(
      circuit="b583-armB",
      now_secs=b583_unix_2039_truncated + i * 30,
    )
    assert_eq(
      b583_str_field(later, "state"),
      "open",
      msg="第 \{i} 个恢复窗仍卡 Open（永久卡死而非延迟恢复）",
    )
    assert_eq(b583_allow(later), false)
  }
  // 且行从未被修复：opened_at 一直是那个负数
  let (_, _, _, _, _, opened_after, _) = b583_row(e, "b583-armB")
  assert_eq(opened_after, b583_unix_2039_truncated)
}

///|
/// 【格 3｜合法域对照｜防恒真】同一状态机、同一算式，`opened_at` 落在合法正域时必须能恢复。
/// 意图：证明格 2 的红面来自「值为负」，不是「测试写法本身让半开不可达」。
/// 修复后这一格**必须继续为绿**（零回归面）；若它红了，说明修复动了合法域。
test "bug583_03_control_positive_domain_half_open_still_reachable" {
  let e = FistEngine::new()
  ignore(e.circuit_fail(circuit="b583-ok-gate", now_secs=2000, threshold=1))
  let s1 = e.circuit_status(circuit="b583-ok-gate", now_secs=2010)
  assert_eq(b583_str_field(s1, "state"), "open")
  assert_eq(b583_allow(s1), false)
  // 2000 + recovery(30) = 2030 ⇒ opened_at>0 ⇒ 门可达
  let s2 = e.circuit_status(circuit="b583-ok-gate", now_secs=2030)
  assert_eq(
    b583_str_field(s2, "state"),
    "half_open",
    msg="合法正域对照格：opened_at>0 时恢复门可达；它红了就说明修复越界改了合法域",
  )
  assert_eq(b583_allow(s2), true)
  // 真实纪元秒（2026）同样可达：把「合成小数字」与「真时基」两种正域都盖住
  let e2 = FistEngine::new()
  ignore(
    e2.circuit_fail(
      circuit="b583-ok-epoch",
      now_secs=b583_unix_2026,
      threshold=1,
    ),
  )
  let s3 = e2.circuit_status(
    circuit="b583-ok-epoch",
    now_secs=b583_unix_2026 + 30,
  )
  assert_eq(b583_str_field(s3, "state"), "half_open")
  assert_eq(b583_allow(s3), true)
}

///|
/// 【格 4｜stale 复位不可达｜缺陷行为】臂 A 的下游半：门是「减法安全」那一档（格 4 先复述），
/// 但状态机把 `last_fail_ts` 写成了当次的负 `now_secs` ⇒ 行被两种时基污染，
/// 此后 `engine_circuit.mbt:170` 的 `last_ts > 0` 恒假 ⇒ BUG-34 的探测丢失复位永久失效
/// （半开态锁死在快速失败，正是 BUG-34 当年要避免的形状）。
/// 修复后期望：最后一组断言从 `allow_call == false` 改成 `== true`（丢失复位重新生效）。
test "bug583_04_negative_last_ts_disables_stale_probe_reset" {
  // 前提：跨时基减法同余正确（账本臂 A「减法形安全，勿报」）—— 这里把它钉成数字，
  // 防止后来者「顺手把减法也一起改」而没人知道那一档本来是对的。
  assert_eq(
    b583_unix_2039_truncated - b583_unix_2026,
    410227200,
    msg="双回绕同余应还原真实 elapsed（13 年秒数）；变了就说明 Int32 减法语义漂移",
  )
  let e = FistEngine::new()
  // 开路发生在合法正域（opened_at=2026 纪元秒，>0 ⇒ 门可达）
  ignore(
    e.circuit_fail(circuit="b583-armA", now_secs=b583_unix_2026, threshold=1),
  )
  // 时钟跨过 2038 后的第一次查询：门开、转半开，并把 last_fail_ts 写成**负**的 now
  let s1 = e.circuit_status(
    circuit="b583-armA",
    now_secs=b583_unix_2039_truncated,
  )
  assert_eq(b583_str_field(s1, "state"), "half_open")
  assert_eq(b583_allow(s1), true)
  assert_eq(b583_int_field(s1, "probes_granted"), 1)
  let (_, _, _, _, _, opened_poisoned, last_ts_poisoned) = b583_row(
    e, "b583-armA",
  )
  assert_eq(
    opened_poisoned,
    b583_unix_2026,
    msg="opened_at 仍是正域原值（半开迁移不改写它）",
  )
  assert_eq(
    last_ts_poisoned,
    b583_unix_2039_truncated,
    msg="同一行已同时住着两种时基：opened_at 正 / last_fail_ts 负",
  )
  // 探测丢失（拿到配额后既不 succeed 也不 fail）+ 过两个恢复窗 ⇒ BUG-34 该复位
  let s2 = e.circuit_status(
    circuit="b583-armA",
    now_secs=b583_unix_2039_truncated + 60,
  )
  assert_eq(b583_str_field(s2, "state"), "half_open")
  assert_eq(
    b583_allow(s2),
    false,
    msg="BUG-583 复现：last_ts<0 ⇒ `engine_circuit.mbt:170` 的 stale 恒假 ⇒ 配额永不重置",
  )
  assert_eq(b583_int_field(s2, "probes_granted"), 1)
  // 再等 10 个恢复窗仍然锁死（永久，不是延迟）
  for i = 3; i <= 12; i = i + 1 {
    let s = e.circuit_status(
      circuit="b583-armA",
      now_secs=b583_unix_2039_truncated + i * 30,
    )
    assert_eq(
      b583_allow(s),
      false,
      msg="第 \{i} 窗仍不复位（探测丢失后永久锁死）",
    )
  }
}

///|
/// 【格 5｜合法域对照｜防恒真】与格 4 同一写法，两端都留在正域 ⇒ 探测丢失能复位（BUG-34 原语义）。
/// 修复后这一格**必须继续为绿**（它是「修复不许破坏的东西」那一半）。
test "bug583_05_control_positive_domain_stale_probe_reset_works" {
  let e = FistEngine::new()
  ignore(
    e.circuit_fail(
      circuit="b583-ok-stale",
      now_secs=b583_unix_2026,
      threshold=1,
    ),
  )
  let s1 = e.circuit_status(
    circuit="b583-ok-stale",
    now_secs=b583_unix_2026 + 30,
  )
  assert_eq(b583_str_field(s1, "state"), "half_open")
  assert_eq(b583_allow(s1), true)
  assert_eq(b583_int_field(s1, "probes_granted"), 1)
  // 第二次查询立刻再来：配额未用尽 ⇒ 拒绝（节流本身正确）
  let s2 = e.circuit_status(
    circuit="b583-ok-stale",
    now_secs=b583_unix_2026 + 31,
  )
  assert_eq(b583_allow(s2), false)
  // 过一整个恢复窗（≥30s）无任何上报 ⇒ stale 复位生效，重新放行一次探测
  let s3 = e.circuit_status(
    circuit="b583-ok-stale",
    now_secs=b583_unix_2026 + 91,
  )
  assert_eq(
    b583_str_field(s3, "state"),
    "half_open",
    msg="合法域对照格：BUG-34 的探测丢失复位必须生效；红了说明修复越界改坏了节流",
  )
  assert_eq(b583_allow(s3), true)
  assert_eq(b583_int_field(s3, "probes_granted"), 1)
}

///|
/// 【格 6｜卡 Open 态的可读性｜缺陷行为】用户/调用方在回执层面看到什么？
/// 一张**看起来完全正常**的 Open 回执：`state="open"`、`allow_call=false`、
/// `opened_at` 是负数（既不是 0「从未开过路」也不是可解释的时刻），
/// 且没有任何错误留痕（无 `persist_error`、note 是标准文案）⇒ 「永久卡死」这件事
/// 在调用面**不可见**。这条锁的是「修复必须让这一档变得可见或可恢复」，
/// 而不是「修完还留一张静默的假正常回执」。
/// 修复后期望：要么 `state` 变 half_open（方向③），要么回执新增域异常线索字段
/// （方向②）—— 两种都会让本格的某条断言变红，属预期，需改写。
test "bug583_06_stuck_open_receipt_is_silent_about_the_wrap" {
  let e = FistEngine::new()
  ignore(
    e.circuit_fail(
      circuit="b583-receipt",
      now_secs=b583_unix_2039_truncated,
      threshold=1,
    ),
  )
  let s = e.circuit_status(
    circuit="b583-receipt",
    now_secs=b583_unix_2039_truncated + 30,
  )
  assert_eq(b583_str_field(s, "state"), "open")
  assert_eq(b583_allow(s), false)
  // 负 opened_at 原样出现在回执里（既不归零也不报错）
  assert_eq(b583_int_field(s, "opened_at"), b583_unix_2039_truncated)
  assert_true(
    b583_int_field(s, "opened_at") < 0,
    msg="回执把绕回后的负时刻直接交给调用方（BUG-583 的可见面）",
  )
  // 半开配额字段在 open 态恒 0：调用方读不出「本应半开」
  assert_eq(b583_int_field(s, "probes_granted"), 0)
  assert_eq(b583_int_field(s, "recovery_secs"), 30)
  // 零线索：没有写盘错误留痕，note 仍是标准三态文案
  assert_eq(jget(s, "persist_error") is None, true)
  assert_true(
    b583_str_field(s, "note").contains("熔断器三态"),
    msg="note 面当前不含任何「时间戳越界/已绕回」提示",
  )
}

///|
/// 【格 7｜存储层不净化负值｜缺陷行为】同一档缺陷在 SQLite 后端逐字复现（mcpcf 真用的就是
/// SQLite 优先那条路）。意图：证明「负」不是内存后端专属形状、也不会在落库时被洗成正数 ⇒
/// 只改存储层（或加库列宽）不够，修复必须动引擎哨兵或调用方时基。
/// 修复后期望：方向③会把 `cb_get`/`cb_save` 的时间列变 Int64 ⇒ 本格的 7 元组签名与断言值
/// 都要随之改写（`opened_at` 变成正的 2177452800）；方向①/②则本格的「负值往返」仍成立。
test "bug583_07_sqlite_roundtrip_keeps_negative_time_columns" {
  let e = b583_sqlite_engine("b583_cb_roundtrip.db")
  ignore(
    e.circuit_fail(
      ns="b583-ns",
      circuit="neg",
      now_secs=b583_unix_2039_truncated,
      threshold=1,
    ),
  )
  let row = match e.store.cb_get("b583-ns", "neg") {
    Some(r) => r
    None => abort("SQLite 后端没读到熔断行（后端未生效？）")
  }
  let (st, _, _, _, _, opened, last_ts) = row
  assert_eq(st, "open")
  assert_eq(
    opened,
    b583_unix_2039_truncated,
    msg="负 opened_at 必须原样往返：库不净化 ⇒ 哨兵只能在引擎侧修",
  )
  assert_eq(last_ts, b583_unix_2039_truncated)
  // 合法域对照（同一张表、同一列）：正纪元秒也原样往返 ⇒ 不是「整列都读不回来」
  ignore(
    e.circuit_fail(
      ns="b583-ns",
      circuit="pos",
      now_secs=b583_unix_2026,
      threshold=1,
    ),
  )
  let row2 = match e.store.cb_get("b583-ns", "pos") {
    Some(r) => r
    None => abort("SQLite 后端没读到正域熔断行")
  }
  let (st2, _, _, _, _, opened2, last_ts2) = row2
  assert_eq(st2, "open")
  assert_eq(opened2, b583_unix_2026)
  assert_true(last_ts2 > 0)
  // 负域行为在 SQLite 上同样不可退出半开（与内存后端格 2 同结论，跨后端一致）
  let s = e.circuit_status(
    ns="b583-ns",
    circuit="neg",
    now_secs=b583_unix_2039_truncated + 30,
  )
  assert_eq(
    b583_str_field(s, "state"),
    "open",
    msg="SQLite 后端同样卡 Open ⇒ 缺陷不在后端选择上",
  )
  assert_eq(b583_allow(s), false)
}
