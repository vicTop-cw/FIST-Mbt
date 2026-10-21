///|
/// native target：`--upgrade --check` 的远端版本探测 stub。
///
/// 纯计算层（upgrade_core.mbt）在所有 target 上都能跑（零网络），
/// 但真正的 HTTP 探测需要 js/node 运行时（Node 内置 fetch）。
/// 这里照 github_gitcode_native.mbt 口径：native 上不存在 fetch 能力，返回明确 Err——
/// **绝不回落成「已是最新」假绿**（R7）。

///|
/// stub：native 上不存在 fetch 能力。
pub async fn upgrade_fetch_latest(
  _repo : String,
  _base_url : String,
  _timeout_ms : Int32,
) -> Result[String, String] {
  Err(
    "upgrade_fetch_latest 需要 js/node 运行时（Node fetch）；本构建为 native，请在 node 下运行 node fist-mbt.js upgrade --check",
  )
}

///|
/// stub：native 上不存在 node:fs / child_process，阶段 B/C 一律明确拒绝（不假绿）。
pub async fn upgrade_io(
  _op : String,
  _payload_json : String,
) -> Result[Json, String] {
  Err(
    "upgrade 写盘（备份/换入/自检/回滚）需要 js/node 运行时（node:fs + child_process spawn）；本构建为 native，请在 node 下运行 node fist-mbt.js upgrade",
  )
}
