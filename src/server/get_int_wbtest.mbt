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
