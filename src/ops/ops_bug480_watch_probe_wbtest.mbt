// ============================================================================
// BUG-480 探针（Lane DN）：`fs.watch` 句柄能否真正释放
//
// **核心判据不是断言，是「进程能退出」** —— 本文件跑完若挂住、
// 不打印 `Total tests:` 汇总行，就是 bug 仍在。
// （Alpha 的 P2 探针修前 121 秒 SIGTERM；修后目标 < 10 秒。）
//
// 病灶（上游 RX-MBT 0.3.0 的 `monitor/watcher_js.mbt`）：
//   `ffi_watch_start` 的 reg key 是 JS **number**（`G.__rxmbt_watch_seq++`），
//   而 `ffi_watch_stop` 的形参 `id : Int64` 进 JS 是 **BigInt**
//   ⇒ `Map.get(id)` 因 `BigInt(0) !== 0` 恒 undefined ⇒ `close()` 永不执行
//   ⇒ 句柄泄漏 ⇒ node 事件循环不空 ⇒ **进程不退出**。
//
// 修法：`patches/rx-mbt-bug480/reapply.sh` 把 `get(id)` 改成 `get(Number(id))`。
// ============================================================================

///|
/// 【BUG-480·锁 1】★ **订阅 + dispose 之后，句柄真的被释放**。
///
/// 这一格**本身不做任何断言**（`dispose()` 无返回值），
/// 它的价值在**能否跑完** —— 若 `fs.watch` 句柄泄漏，node 事件循环不空，
/// 整个测试进程会挂住、**不打印汇总行**，`moon_test_env.py` 会判 rc=2。
///
/// 所以：**本格「通过」的定义是「汇总行出现了」。**
test "dn_01_subscribe_dispose_does_not_leak_watch_handle" {
  // 复用同包已有夹具（`ops_commissar_wbtest.mbt` 的 `dl_tmp_project`）
  let dir = dl_tmp_project("dn_watch")
  let source = @rhop.from_filesystem_with(
    dir,
    @rhop.RhopCipherNone::new(),
    true,
  )
  let seen : Ref[Int32] = Ref(0)
  let sub = source.subscribe(
    @rx.Observer::new(
      fn(_pkt : @rhop.RhopPacket) { seen.val = seen.val + 1 },
      fn(_e : String) { () },
      fn() { () },
    ),
  )
  // ★ 关键：dispose 必须能真正 close 掉 fs.watch 句柄
  sub.dispose()
  // 断言「不崩」即可 —— 真正的判据是进程能走到汇总行（见文件头注释）
  assert_true(true)
}
