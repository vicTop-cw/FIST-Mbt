/// get_int_wbtest.mbt —— BUG-194（server.mbt get_int 溢出）的白盒锁
///
/// 真源：src/server/server.mbt 的 `get_int`（被 42 个 MCP 工具的参数解析共用）。
/// 病灶：`Double::to_int()` 对超 Int32 域的值**饱和**（BUG-26 实测 1e300 → Int max），
/// 让 timeout_ms / phi_threshold / stale_secs 这类参数静默变成天量值
/// （`timeout_ms=2147483647` 永不超时、`phi_threshold` 永不判 suspect）。
/// 修法：越界/NaN 一律回落默认。

///|
fn gi_int(v : Double) -> Json {
  Json::object({ "k": Json::number(v) })
}

///|
test "BUG-194：get_int 对超 Int32 域的值回落默认" {
  // 1e300 级别（饱和为 Int max 的旧形状）
  assert_eq(get_int(gi_int(2147483647.0), "k", default=3), 3)
  assert_eq(get_int(gi_int(99999999999.0), "k", default=3), 3)
  // 负向越界
  assert_eq(get_int(gi_int(-2147483648.0), "k", default=3), 3)
  // NaN
  let nan_j = Json::object({ "k": Json::number(0.0 / 0.0) })
  assert_eq(get_int(nan_j, "k", default=3), 3)
  // 合法值仍正常读取
  assert_eq(get_int(gi_int(42.0), "k", default=3), 42)
  assert_eq(get_int(gi_int(0.0), "k", default=3), 0)
  assert_eq(get_int(gi_int(-5.0), "k", default=3), -5)
}

///|
test "BUG-194：get_int 缺字段/坏类型回落默认" {
  assert_eq(get_int(Json::object({}), "k", default=3), 3)
  assert_eq(
    get_int(Json::object({ "k": Json::string("x") }), "k", default=3),
    3,
  )
  assert_eq(get_int(Json::object({ "k": Json::null() }), "k", default=3), 3)
  assert_eq(get_int(Json::string("not object"), "k", default=3), 3)
}

///|
/// BUG-195：loop_create 曾内联 3 个 `.to_int()`（max_rounds / baseline_test_count /
/// baseline_open_bug_count），绕过 get_int 守卫；现改用 get_int 覆盖默认值。
/// 这里锁非 3 默认值（5 / 0）在越界/NaN 下也回落正确默认，不静默变成 Int max。
test "BUG-195：get_int 非 3 默认值（5/0）在越界时回落正确默认" {
  // max_rounds 默认 5：越界回落 5，不饱和为 Int max（1e300 不可写，用 1e11）
  assert_eq(get_int(gi_int(99999999999.0), "k", default=5), 5)
  assert_eq(get_int(gi_int(-99999999999.0), "k", default=5), 5)
  // baseline_* 默认 0
  assert_eq(get_int(gi_int(99999999999.0), "k", default=0), 0)
  assert_eq(get_int(gi_int(-99999999999.0), "k", default=0), 0)
  // NaN（0.0/0.0 是合法 NaN 源，编译不报错）
  let nan_j = Json::object({ "k": Json::number(0.0 / 0.0) })
  assert_eq(get_int(nan_j, "k", default=5), 5)
  // 缺字段/坏类型
  assert_eq(get_int(Json::object({}), "k", default=5), 5)
  assert_eq(get_int(Json::object({}), "k", default=0), 0)
  // 合法值仍按新默认读取
  assert_eq(get_int(gi_int(9.0), "k", default=5), 9)
}

///|
fn gs_str(s : String) -> Json {
  Json::object({ "k": Json::string(s) })
}

///|
/// BUG-590 ①格：客户端 `--raw` 把参数整体字符串化（`split_n="3"`）时，旧 `get_int`
/// 只认 `Number` ⇒ 静默回落默认值（拆分数被悄悄改成 3）。修后接受十进制字符串，
/// 但**域守卫与坏值语义不变**：非数字/空串/小数/越界一律回落默认（不猜）。
test "BUG-590：get_int 接受字符串形态整数，域守卫不变" {
  assert_eq(get_int(gs_str("3"), "k", default=3), 3)
  assert_eq(get_int(gs_str("5"), "k", default=3), 5)
  assert_eq(get_int(gs_str(" 42 "), "k", default=3), 42)
  assert_eq(get_int(gs_str("+7"), "k", default=3), 7)
  assert_eq(get_int(gs_str("-5"), "k", default=3), -5)
  assert_eq(get_int(gs_str("0"), "k", default=3), 0)
  assert_eq(get_int(gs_str(""), "k", default=3), 3)
  assert_eq(get_int(gs_str("abc"), "k", default=3), 3)
  assert_eq(get_int(gs_str("3.5"), "k", default=3), 3)
  assert_eq(get_int(gs_str("-"), "k", default=3), 3)
  assert_eq(get_int(gs_str("3000000000"), "k", default=3), 3)
  assert_eq(get_int(gs_str("9223372036854775808"), "k", default=3), 3)
  // 原生 Number 路径零回归
  assert_eq(get_int(gi_int(9.0), "k", default=3), 9)
}

///|
/// BUG-590 ②格：`reinject_context="true"` 这类字符串化布尔旧实现被静默当 false。
/// 修后识别常见字面量（大小写不敏感），**无法识别的串仍回落默认**（不猜）。
test "BUG-590：get_bool 接受字符串形态布尔，未知串回落默认" {
  for t in ["true", "TRUE", " True ", "1", "yes", "ON"] {
    assert_true(get_bool(gs_str(t), "k", default=false))
  }
  for f in ["false", "FALSE", "0", "no", "Off"] {
    assert_false(get_bool(gs_str(f), "k", default=true))
  }
  assert_true(get_bool(gs_str("maybe"), "k", default=true))
  assert_false(get_bool(gs_str("maybe"), "k", default=false))
  // 原生布尔零回归
  assert_true(
    get_bool(Json::object({ "k": Json::boolean(true) }), "k", default=false),
  )
  assert_false(
    get_bool(Json::object({ "k": Json::boolean(false) }), "k", default=true),
  )
}
