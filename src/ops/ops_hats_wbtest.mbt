/// ops_hats_wbtest.mbt —— 六顶思维帽注册表白盒测试（R118）
///
/// 覆盖：枚举↔字符串、默认帽集、角色模板非空、禁做事项非空、
/// 输出 schema 字段存在、聚合一致性计算、非法结论拒绝。
/// 白盒：可构造 HatVerdict（黑盒见不到非 pub 字段）。

///|
/// 帽子字符串互转：合法值全通，非法值拒。
test "hats: parse_hat 正/负路径" {
  let ok_ids = ["white", "red", "black", "yellow", "green", "blue"]
  let mut all_ok = true
  for i = 0; i < ok_ids.length(); i = i + 1 {
    match parse_hat(ok_ids[i]) {
      Ok(_) => ()
      Err(_) => all_ok = false
    }
  }
  assert_true(all_ok)
  // trim 合法（前后空白不影响）
  assert_true(match parse_hat(" white ") {
    Ok(Hat::White) => true
    _ => false
  })
  // 大写被拒（与 ops_modes::parse_mode 同约定：大小写敏感）
  assert_true(match parse_hat("WHITE") {
    Err(_) => true
    _ => false
  })
  // 非法值
  assert_true(match parse_hat("pink") {
    Err(_) => true
    _ => false
  })
  assert_true(match parse_hat("") {
    Err(_) => true
    _ => false
  })
}

///|
/// 批量解析：任一非法即整批拒（防半桶结论）。
test "hats: parse_hats 整批拒" {
  match parse_hats(["white", "black"]) {
    Ok(arr) => assert_eq(arr.length(), 2)
    Err(_) => assert_false(true)
  }
  // 混入非法 → 整批 Err
  assert_true(match parse_hats(["white", "pink"]) {
    Err(_) => true
    _ => false
  })
}

fn hat_ids_of(arr : Array[Hat]) -> Array[String] {
  let out : Array[String] = []
  for i = 0; i < arr.length(); i = i + 1 {
    out.push(hat_id(arr[i]))
  }
  out
}

///|
/// 默认帽集 = 3 顶（Hat::White + Hat::Black + Hat::Yellow，D3 默认）。
test "hats: 默认帽集三顶" {
  let d = hat_defaults()
  assert_eq(d.length(), 3)
  let ids = hat_ids_of(d)
  assert_eq(ids[0], "white")
  assert_eq(ids[1], "black")
  assert_eq(ids[2], "yellow")
}

///|
/// 六顶帽子角色指令与禁做事项全部非空（模板真源不能有空洞）。
test "hats: 六帽角色与禁做非空" {
  let hats = [
    Hat::White, Hat::Red, Hat::Black, Hat::Yellow, Hat::Green, Hat::Blue,
  ]
  let mut nonempty = true
  for i = 0; i < hats.length(); i = i + 1 {
    let h = hats[i]
    if hat_role(h).trim().is_empty() {
      nonempty = false
    }
    if hat_forbid(h).trim().is_empty() {
      nonempty = false
    }
    if hat_name_zh(h).trim().is_empty() {
      nonempty = false
    }
    if hat_color(h).trim().is_empty() {
      nonempty = false
    }
    if hat_output_keys(h).length() == 0 {
      nonempty = false
    }
  }
  assert_true(nonempty)
}

///|
/// 帽子角色指令互相不同（防同质化：六帽不许说同一句话）。
test "hats: 六帽角色互不相同" {
  let hats = [
    Hat::White, Hat::Red, Hat::Black, Hat::Yellow, Hat::Green, Hat::Blue,
  ]
  let mut distinct = true
  for i = 0; i < hats.length(); i = i + 1 {
    for j = i + 1; j < hats.length(); j = j + 1 {
      if hat_role(hats[i]) == hat_role(hats[j]) {
        distinct = false
      }
    }
  }
  assert_true(distinct)
}

///|
/// 聚合：一致率达标放行、不达标不放行、空结论不放行、阈值兜底。
test "hats: debate_summary 阈值判定" {
  // 三帽两帽 pass → rate 0.667 >= 0.6 → pass
  let s1 = debate_summary(
    [
      { hat_id: "white", verdict: "pass", evidence: "数据 A" },
      { hat_id: "black", verdict: "pass", evidence: "风险 B" },
      { hat_id: "yellow", verdict: "reject", evidence: "收益 C" },
    ],
    0.6,
  )
  assert_eq(s1.total, 3)
  assert_eq(s1.agree, 2)
  assert_true(s1.pass)
  assert_true(s1.rate > 0.66)

  // 三帽只一帽 pass → rate 0.33 < 0.6 → 不放行
  let s2 = debate_summary(
    [
      { hat_id: "white", verdict: "pass", evidence: "x" },
      { hat_id: "black", verdict: "reject", evidence: "y" },
      { hat_id: "yellow", verdict: "abstain", evidence: "z" },
    ],
    0.6,
  )
  assert_false(s2.pass)
  assert_eq(s2.agree, 1)

  // 空结论 → total 0 → pass=false
  let s3 = debate_summary([], 0.6)
  assert_eq(s3.total, 0)
  assert_false(s3.pass)
  assert_eq(s3.rate, 0.0)

  // threshold 非法 → 回退默认 0.6
  let s4 = debate_summary(
    [{ hat_id: "white", verdict: "pass", evidence: "a" }],
    -1.0,
  )
  assert_eq(s4.threshold, 0.6)

  // 全 pass → rate 1.0
  let s5 = debate_summary(
    [
      { hat_id: "white", verdict: "pass", evidence: "a" },
      { hat_id: "black", verdict: "pass", evidence: "b" },
      { hat_id: "yellow", verdict: "pass", evidence: "c" },
    ],
    0.6,
  )
  assert_eq(s5.agree, 3)
  assert_eq(s5.rate, 1.0)
}

///|
/// 单帽结论校验：evidence 空或 verdict 非法必须拒。
test "hats: valid_verdict 正/负路径" {
  // 合法
  assert_true(match valid_verdict({ hat_id: "white", verdict: "pass", evidence: "e" }) {
    Ok(_) => true
    _ => false
  })
  assert_true(match valid_verdict({ hat_id: "black", verdict: "reject", evidence: "e" }) {
    Ok(_) => true
    _ => false
  })
  assert_true(match valid_verdict({ hat_id: "red", verdict: "abstain", evidence: "e" }) {
    Ok(_) => true
    _ => false
  })
  // evidence 空 → 拒
  assert_true(match valid_verdict({ hat_id: "white", verdict: "pass", evidence: " " }) {
    Err(_) => true
    _ => false
  })
  // verdict 非法 → 拒
  assert_true(match valid_verdict({ hat_id: "white", verdict: "maybe", evidence: "e" }) {
    Err(_) => true
    _ => false
  })
}

///|
test "hats: all_hats() 返回 6 顶且 id 互不相同" {
  let hs = all_hats()
  assert_eq(hs.length(), 6)
  let ids : Array[String] = hs.map(fn(h) { hat_id(h) })
  assert_eq(ids.length(), 6)
  assert_eq(ids[0], "white")
  assert_eq(ids[1], "red")
  assert_eq(ids[2], "black")
  assert_eq(ids[3], "yellow")
  assert_eq(ids[4], "green")
  assert_eq(ids[5], "blue")
  // 两两 id 不同（去重后仍 6 个）
  let seen : Array[String] = []
  for id in ids {
    if not(seen.contains(id)) {
      seen.push(id)
    }
  }
  assert_eq(seen.length(), 6)
}

test "hats: hat_verdict() 构造字段与入参一致" {
  let v = hat_verdict("white", "pass", "数据支撑")
  assert_eq(v.hat_id, "white")
  assert_eq(v.verdict, "pass")
  assert_eq(v.evidence, "数据支撑")
  let v2 = hat_verdict("black", "reject", "")
  assert_eq(v2.hat_id, "black")
  assert_eq(v2.evidence, "")
}
