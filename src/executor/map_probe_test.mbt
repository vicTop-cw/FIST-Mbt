///|
test "probe: Map.set 是否原地修改(丢弃返回值后能否读到)" {
  let m : Map[String, String] = Map([])
  m.set("McpDelegateExecutor", "McpDelegateExecutor")
  m.set("manual", "manual")
  // 若 set 返回新 Map(不可变), 上面的返回值被丢弃 → 这里读到 None,
  // 则 registry 的怀疑成立(真 bug); 若 set 是原地(->Unit), 这里读到 Some → 假阳性。
  assert_eq(m.get("McpDelegateExecutor"), Some("McpDelegateExecutor"))
  assert_eq(m.get("manual"), Some("manual"))
  assert_eq(m.keys().length(), 2)
}

///|
test "probe: Map.remove 是否原地(丢弃返回值后 in_task 收缩)" {
  let m : Map[String, Int] = Map([])
  m.set("a", 1)
  m.set("b", 2)
  m.remove("a")
  assert_eq(m.get("a"), None)
  assert_eq(m.keys().length(), 1)
}
