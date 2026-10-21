/// laya_auto_wbtest.mbt —— BUG-231 回归锁：task_plan_deep 的 laya_auto 分支
/// 不再把 Laya 探测失败 / sidecar 调用失败静默吞成 `laya: null`。
///
/// 背景（活证据见 memory/bugs.md BUG-231）：该分支旧写法 `Err(_) => ()` 把失败原因
/// 整条丢弃，laya_info 停在 null，调用方无法区分「本机未安装 Laya」与「装了但调用挂了」；
/// 同族兄弟 handler laya_decide（server.mbt 的 Err 分支）已把 reason 透出，此处遗漏。
/// handler 本身是 async 且真起子进程，同步测试无法 await——沿用 BUG-14/BUG-18 做法，
/// 白盒守在被修复的纯函数 `laya_auto_fail` 上，并对 server.mbt 源码文本加锁
/// （防调用点被改回 `Err(_) => ()`）。

///|
test "BUG-231：laya_auto_fail 恒带 available=false + 可见原因（区分『未装』与『调用挂』）" {
  let j = laya_auto_fail(
    "laya sidecar 调用失败: 子进程结果 JSON 解析失败",
  )
  assert_eq(ld_bool(j, "available", true), false)
  assert_true(ld_str(j, "reason").contains("sidecar 调用失败"))
  assert_true(ld_str(j, "reason").contains("JSON 解析失败"))
  // 空原因也必须成型（结构恒在），不许塌回 null
  let e = laya_auto_fail("")
  assert_eq(ld_bool(e, "available", true), false)
  assert_eq(ld_str(e, "reason"), "")
}

///|
test "BUG-231：laya_auto 分支两类失败都留痕，且不再有裸 Err(_) => ()（源码文本锁）" {
  let src = r2_read_or_abort("src/server/server.mbt")
  // 修复点：探测失败与 sidecar 失败都被写进 laya_info（两个赋值调用点）
  assert_true(r2_count(src, "= laya_auto_fail(") >= 2)
  assert_true(src.contains("Laya 探测失败: "))
  assert_true(src.contains("laya sidecar 调用失败: "))
  // 旧写法残留清零：server.mbt 不再有吞掉 Result 的裸 `Err(_) => ()`
  assert_eq(r2_count(src, "Err(_) => ()"), 0)
}
