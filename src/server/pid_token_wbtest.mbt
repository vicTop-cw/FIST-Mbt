/// pid_token_wbtest.mbt —— BUG-401「current_pid_token 契约与实现不符」的白盒锁
///
/// 真源：src/server/server.mbt 的 `current_pid_token()`。注释声称「进程启动即固定一次，
/// 生命周期内不变」，原实现却每次调用重取 `@env.now()`——秒级漂移，`pid_bound=1` 时
/// 误报「ACL 绑定旧进程实例（pid 已换）」把合法写操作拒掉。修法：首次调用固化缓存。
///
/// 说明：原实现同秒内两次调用碰巧相等，单次调用测试会假绿；这里直接读缓存容器状态，
/// 断言「首次调用填了缓存 + 之后复用同一值」，确定性可复现。

///|
test "BUG-401 pid_token 首次调用固化缓存" {
  let before = cached_pid_token[0]
  let v = current_pid_token()
  let after = cached_pid_token[0]
  match before {
    Some(prev) =>
      // 测试面复用同一进程，缓存可能已被前面的测试固化；此时只验值一致。
      if v != prev {
        fail("缓存已固化但返回值不一致: \{v} != \{prev}")
      }
    None => {
      // 2026-10-24：`Option::is_some()` 已弃用，改用模式匹配（原写法还让 abort 串里的
      // `after` 走 Show ⇒ 两条 deprecated 警告，纯噪声）。
      match after {
        Some(v2) =>
          if v != v2 {
            fail("返回值与固化值不一致: \{v} != \{v2}")
          }
        None => fail("首次调用未固化缓存（before=None）: v=\{v}")
      }
      if v < 0 {
        fail("pid_token 非负: \{v}")
      }
    }
  }
}

///|
test "BUG-401 pid_token 后续调用复用同一值" {
  let a = current_pid_token()
  let b = current_pid_token()
  let c = current_pid_token()
  if a != b || b != c {
    fail(
      "同进程 pid_token 不稳定: \{a} \{b} \{c}（应进程内固化）",
    )
  }
  match cached_pid_token[0] {
    Some(v) => if a != v { fail("返回值与缓存不一致: \{a} != \{v}") }
    None => fail("缓存未固化: \{a}")
  }
}
