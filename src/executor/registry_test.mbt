/// registry_test.mbt —— 执行者能力路由（Marketplace 雏形，R30）测试。
/// 覆盖：need 标签切分 / 能力覆盖率 / 路由排序（覆盖 desc → 负载 asc → 名称 asc）/ 注册与查询。

///|
test "split_need_tags：逗号/顿号/空格分隔，去空" {
  assert_eq(@executor.split_need_tags("编排,json、yaml ").length(), 3)
  assert_eq(@executor.split_need_tags("编排"), ["编排"])
  assert_eq(@executor.split_need_tags("  ").length(), 0)
}

///|
test "ability_coverage：全命中 1.0 / 部分 / 无 / 空 need=0" {
  assert_eq(
    @executor.ability_coverage(["编排", "json"], ["编排", "json"]),
    1.0,
  )
  assert_eq(@executor.ability_coverage(["编排", "json"], ["编排"]), 1.0)
  assert_eq(@executor.ability_coverage(["json"], ["编排", "json"]), 0.5)
  assert_eq(@executor.ability_coverage(["java"], ["编排"]), 0.0)
  assert_eq(@executor.ability_coverage(["编排"], []), 0.0)
}

///|
test "route_pick：按 覆盖 desc → 负载 asc → 名称 asc 排序" {
  let reg = @executor.ExecutorRegistry::new()
    .add_ability("ex-A", ["编排", "json"])
    .add_ability("ex-B", ["编排"])
    .add_ability("ex-C", ["json"])
  let load : Map[String, Int] = Map([("ex-A", 3), ("ex-B", 0), ("ex-C", 0)])
  let j = reg.route_pick("编排", load)
  // 覆盖率最高的是 ex-A(1.0) 与 ex-B(1.0)；同覆盖下负载小的 ex-B(0) 在 ex-A(3) 前
  match j.value("best") {
    Some(Object(m)) =>
      match m.get("name") {
        Some(String(n)) => assert_eq(n, "ex-B")
        _ => abort("best 应有 name: " + j.stringify())
      }
    _ => abort("best 不应为空: " + j.stringify())
  }
}

///|
test "check_name_order：同覆盖同负载按名称字母序" {
  let reg = @executor.ExecutorRegistry::new()
  ignore(reg.add_ability("zxc", ["编排"]))
  ignore(reg.add_ability("abc", ["编排"]))
  let load : Map[String, Int] = Map([])
  let j = reg.route_pick("编排", load)
  match j.value("best") {
    Some(Object(m)) =>
      match m.get("name") {
        Some(String(n)) => assert_eq(n, "abc")
        _ => abort("best 应有 name: " + j.stringify())
      }
    _ => abort("best 不应为空: " + j.stringify())
  }
}
