/// call_log_wbtest.mbt —— 自动调用日志包装（_instrument/_log_call）白盒测试。
///
/// 验证"每次工具调用 auto-log 到 call_log，Ok/Err 两条都在"，且不改变原结果。
/// 由于 handler 为 async 且无法在同步 test 内 await future，这里直接验证包装
/// 调用的核心 `_log_call`：Ok（ok=true）与 Err（ok=false）路径都会被真实落日志，
/// 并可经 engine.store_recent_call_logs 读回。

///|
fn wb_str(j : Json, key : String) -> String {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(String(s)) => s
        _ => "<null>"
      }
    _ => "<null>"
  }
}

///|
fn wb_bool(j : Json, key : String) -> Bool {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(True) => true
        _ => false
      }
    _ => false
  }
}

///|
test "call_log_wrapper_ok_and_err_logged" {
  // Ok 路径：工具 "wbtool_ok"，调用者 created_by=tester
  _log_call(
    "wbtool_ok",
    Json::object(Map([("created_by", Json::string("tester"))])),
    "{\"x\":1}",
    "ok",
    true,
    2,
    1,
  )
  // Err 路径：工具 "wbtool_err"，无 caller/ns（默认空）
  _log_call("wbtool_err", Json::object({}), "{}", "boom info", false, 5, 2)
  let logs = engine.store_recent_call_logs(limit=100)
  let mut ok_seen : Bool = false
  let mut err_seen : Bool = false
  for l in logs {
    if wb_str(l, "tool") == "wbtool_ok" && wb_bool(l, "ok") {
      ok_seen = true
    }
    if wb_str(l, "tool") == "wbtool_err" && not(wb_bool(l, "ok")) {
      err_seen = true
    }
  }
  assert_true(ok_seen)
  assert_true(err_seen)
}
