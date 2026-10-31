///|
/// R225：core_principle（开发规范 7 条的真源）零覆盖契约锁。
/// principles() 被 project_standards 机器投影引用 —— 序号/标题是协议面：
/// 下游按 index 检索、按 title 展示。删条、换序、改号都会以「投影与真源不一致」
/// 的形式在别处爆，而不是在这里 —— 所以在这里钉死形状。

///|
/// 条数、序号连续 1..N、无空标题/空正文。
test "principles 的形状契约：条数与序号连续" {
  let ps = principles()
  assert_true(
    ps.length() >= 7,
    msg="规范条数不得少于既有的 7 条（删条=投影缺规则）",
  )
  for i, p in ps {
    assert_eq(
      p.get_index(),
      i + 1,
      msg="序号必须从 1 连续递增（下游按 index 检索）",
    )
    assert_true(p.get_title().length() > 0, msg="标题不得为空")
    assert_true(p.get_body().length() > 0, msg="正文不得为空")
  }
}

///|
/// JSON 面：字段名/类型是机器投影的解析契约（index 数字、title/body 字符串）。
/// 遍历用 match Json::Array 解构（Json 类型本身无 .length 方法）。
test "principles_json 的字段契约与规模一致" {
  let ps = principles()
  match principles_json() {
    Json::Array(items) => {
      assert_eq(
        items.length(),
        ps.length(),
        msg="JSON 数组与真源条数不一致",
      )
      for i, item in items {
        match item {
          Json::Object(m) => {
            let idx = m.get("index")
            let tit = m.get("title")
            let bod = m.get("body")
            assert_true(idx is Some(_), msg="第 \{i} 条缺 index 字段")
            assert_true(tit is Some(_), msg="第 \{i} 条缺 title 字段")
            assert_true(bod is Some(_), msg="第 \{i} 条缺 body 字段")
          }
          _ => assert_true(false, msg="JSON 数组元素必须是 Object")
        }
      }
    }
    _ => assert_true(false, msg="principles_json 必须返回数组")
  }
}
