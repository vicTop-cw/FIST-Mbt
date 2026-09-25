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

///|
test "route_pick_with_trust：覆盖 desc → 信任 desc → 负载 asc（R80 历史信任轴）" {
  let reg = @executor.ExecutorRegistry::new()
    .add_ability("ex-A", ["编排", "json"])
    .add_ability("ex-B", ["编排"])
    .add_ability("ex-C", ["json"])
  let load : Map[String, Int] = Map([("ex-A", 3), ("ex-B", 0), ("ex-C", 0)])
  // 同覆盖(1.0)下：ex-A trust 0.9 > ex-B trust 0.3 → ex-A 优先（信任轴压过负载差异）
  let trust : Map[String, Double] = Map([("ex-A", 0.9), ("ex-B", 0.3)])
  let j = reg.route_pick_with_trust("编排", load, trust)
  match j.value("best") {
    Some(Object(m)) =>
      match m.get("name") {
        Some(String(n)) => assert_eq(n, "ex-A")
        _ => abort("best 应有 name: " + j.stringify())
      }
    _ => abort("best 不应为空: " + j.stringify())
  }
  // 每条候选应带 trust 字段；注册表含系统执行者(manual/McpDelegateExecutor)，总数 ≥ 3
  match j.value("candidates") {
    Some(Array(cs)) =>
      if cs.length() < 3 {
        abort(
          "candidates 过少: " +
          cs.length().to_string() +
          " j=" +
          j.stringify(),
        )
      }
    _ => abort("candidates 缺失: " + j.stringify())
  }
  match j.value("basis") {
    Some(String(s)) =>
      if not(s.contains("信任")) {
        abort("basis 内容: " + s)
      }
    _ => abort("basis 缺失: " + j.stringify())
  }
  // 信任相同(均无历史 → 0.5 中性)时回退负载轴：ex-B(0) 优先于 ex-A(3)
  let j2 = reg.route_pick_with_trust("编排", load, Map([]))
  match j2.value("best") {
    Some(Object(m)) =>
      match m.get("name") {
        Some(String(n)) => if n != "ex-B" { abort("j2 best 名称: " + n) }
        _ => abort("j2 best 应有 name: " + j2.stringify())
      }
    _ => abort("j2 best 不应为空: " + j2.stringify())
  }
}

///|
test "auction_pick：能力覆盖>0 方可竞拍；默认出价=覆盖率；无历史 0.5 中性" {
  let reg = @executor.ExecutorRegistry::new()
    .add_ability("ex-A", ["编排", "json"])
    .add_ability("ex-B", ["编排"])
    .add_ability("ex-C", ["json"])
    .add_ability("ex-D", ["java"])
  let load : Map[String, Int] = Map([("ex-A", 2), ("ex-B", 0)])
  let j = reg.auction_pick("编排", load, Map([]), Map([]))
  // 参与竞拍者：ex-A(1.0)、ex-B(1.0)；ex-C(0.0)/ex-D(0.0)/系统执行者(空能力) 被能力门槛挡下
  match j.value("count") {
    Some(Number(n, ..)) =>
      if n != 2.0 {
        abort("count 应为 2: " + j.stringify())
      }
    _ => abort("count 缺失: " + j.stringify())
  }
  // ex-A 出价=覆盖率1.0、无历史→校准 0.5、负载2→折扣 1/3 → score 0.5/3≈0.167
  // ex-B 出价=1.0、校准 0.5、负载0→折扣 1 → score 0.5 → 胜者 ex-B（负载折扣分胜负）
  match j.value("winner") {
    Some(Object(m)) =>
      match m.get("name") {
        Some(String(n)) =>
          if n != "ex-B" {
            abort("auction best 名称: " + n + " j=" + j.stringify())
          }
        _ => abort("winner 应有 name: " + j.stringify())
      }
    _ => abort("winner 不应为空: " + j.stringify())
  }
  match j.value("basis") {
    Some(String(s)) =>
      if not(s.contains("校准")) || not(s.contains("拍卖")) {
        abort("basis 内容: " + s)
      }
    _ => abort("basis 缺失: " + j.stringify())
  }
}

///|
test "auction_pick：胜者诅咒防护——过度自信者被校准折扣击败" {
  let reg = @executor.ExecutorRegistry::new()
    .add_ability("ex-A", ["编排"])
    .add_ability("ex-B", ["编排"])
  // ex-A 出价 0.9 但历史兑现率仅 0.3（过度自信）；ex-B 出价 0.6 兑现率 0.6（言行一致）
  let bid : Map[String, Double] = Map([("ex-A", 0.9), ("ex-B", 0.6)])
  let trust : Map[String, Double] = Map([("ex-A", 0.3), ("ex-B", 0.6)])
  let j = reg.auction_pick("编排", Map([]), trust, bid)
  // ex-A: 校准 1-0.6=0.4 → 0.9×0.4=0.36；ex-B: 校准 1.0 → 0.6×1.0=0.6 → ex-B 胜
  match j.value("winner") {
    Some(Object(m)) =>
      match m.get("name") {
        Some(String(n)) =>
          if n != "ex-B" {
            abort("胜者诅咒未防住, 胜者=" + n + " j=" + j.stringify())
          }
        _ => abort("winner 应有 name: " + j.stringify())
      }
    _ => abort("winner 不应为空: " + j.stringify())
  }
  // ex-A 行应标记 overconfident=true（出价 > 兑现率），证明"过度自信被识别"
  match j.value("bids") {
    Some(Array(cs)) => {
      let mut found = false
      for c in cs {
        match c.value("name") {
          Some(String(n)) =>
            if n == "ex-A" {
              match c.value("overconfident") {
                Some(j) =>
                  match j.as_bool() {
                    Some(b) =>
                      if not(b) {
                        abort("ex-A 应标记 overconfident: " + j.stringify())
                      }
                    None => abort("overconfident 非布尔: " + j.stringify())
                  }
                _ => abort("overconfident 字段缺失: " + j.stringify())
              }
              found = true
            }
          _ => ()
        }
      }
      if not(found) {
        abort("bids 未含 ex-A: " + j.stringify())
      }
    }
    _ => abort("bids 缺失: " + j.stringify())
  }
}

///|
test "auction_pick：负载折扣分胜负 + 空 need 无竞拍者" {
  let reg = @executor.ExecutorRegistry::new()
    .add_ability("ex-A", ["编排"])
    .add_ability("ex-B", ["编排"])
  // 出价/兑现率相同(0.8/0.8，校准=1)：负载 0 的 ex-A(0.8) 胜负载 3 的 ex-B(0.8×0.25=0.2)
  let bid : Map[String, Double] = Map([("ex-A", 0.8), ("ex-B", 0.8)])
  let trust : Map[String, Double] = Map([("ex-A", 0.8), ("ex-B", 0.8)])
  let load : Map[String, Int] = Map([("ex-A", 0), ("ex-B", 3)])
  let j = reg.auction_pick("编排", load, trust, bid)
  match j.value("winner") {
    Some(Object(m)) =>
      match m.get("name") {
        Some(String(n)) =>
          if n != "ex-A" {
            abort("负载折扣未生效, 胜者=" + n + " j=" + j.stringify())
          }
        _ => abort("winner 应有 name: " + j.stringify())
      }
    _ => abort("winner 不应为空: " + j.stringify())
  }
  // 空 need：无能力可覆盖 → 无竞拍者 → winner null、count 0
  let j2 = reg.auction_pick("", Map([]), Map([]), Map([]))
  match j2.value("count") {
    Some(Number(n, ..)) =>
      if n != 0.0 {
        abort("空 need count 应为 0: " + j2.stringify())
      }
    _ => abort("count 缺失: " + j2.stringify())
  }
  match j2.value("winner") {
    Some(Null) => ()
    _ => abort("空 need winner 应为 null: " + j2.stringify())
  }
}
