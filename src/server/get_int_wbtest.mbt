/// get_int_wbtest.mbt —— BUG-192（server.mbt get_int 溢出）的白盒锁
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
test "BUG-192：get_int 对超 Int32 域的值回落默认" {
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
test "BUG-192：get_int 缺字段/坏类型回落默认" {
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
