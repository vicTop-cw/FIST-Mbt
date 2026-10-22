/// hat_wbtest.mbt —— HexaMind 六元自驱决策 · 白盒测试（R119）
///
/// 覆盖：六元注册表（映射/解析/去重/白名单）、config_json 解析（正/负路径）、
/// 单元报告校验、分歧提取（三类）、收敛判定（三态）、编排计划、最终报告组装。
/// 白盒：可构造 HexaElement / HatReport / Divergence / DebatePair。

// ---------------------------------------------------------------------------
// 小工具
// ---------------------------------------------------------------------------

///|
fn rep(
  element_id : String,
  verdict : String,
  conf : Double,
  outcomes : Array[String],
) -> HatReport {
  hat_report(
    element_id,
    verdict,
    conf,
    "依据：" + element_id + "-" + verdict,
    outcomes,
    "",
  )
}

// ---------------------------------------------------------------------------
// hat_defs
// ---------------------------------------------------------------------------

///|
test "defs: 六元全量 6 顶且 id 唯一" {
  let es = hexa_elements()
  assert_eq(es.length(), 6)
  let ids = es.map(fn(e) { e.id })
  assert_true(ids.contains("stargazer"))
  assert_true(ids.contains("pulse"))
  assert_true(ids.contains("wallbreaker"))
  assert_true(ids.contains("golddigger"))
  assert_true(ids.contains("nova"))
  assert_true(ids.contains("nucleus"))
  // 六元 id 去重
  assert_eq(ids.length(), 6)
}

///|
test "defs: 六元与六顶帽 id 双向映射一致" {
  for e in hexa_elements() {
    assert_eq(hexa_hat_id(e.id), e.hat_id)
    assert_eq(hat_to_hexa(e.hat_id), e.id)
  }
}

///|
test "defs: 未知 id 双向映射返回空串" {
  assert_eq(hexa_hat_id("bogus"), "")
  assert_eq(hat_to_hexa("bogus"), "")
}

///|
test "defs: hexa_for_id 正/负路径" {
  assert_true(
    match hexa_for_id("wallbreaker") {
      Ok(e) => e.lane == "paid_pool" && e.temperature == 0.3
      Err(_) => false
    },
  )
  assert_true(
    match hexa_for_id("nope") {
      Err(_) => true
      Ok(_) => false
    },
  )
}

///|
test "defs: 模型策略分池（探索帽 free_pool，裁决帽 paid_pool）" {
  assert_eq(nova().lane, "free_pool")
  assert_eq(pulse().lane, "free_pool")
  assert_eq(nucleus().lane, "paid_pool")
  assert_eq(wallbreaker().lane, "paid_pool")
}

///|
test "defs: resolve_element_id 接受六元 id 与六顶帽 id" {
  assert_eq(
    match resolve_element_id("stargazer") {
      Ok(id) => id
      Err(_) => ""
    },
    "stargazer",
  )
  assert_eq(
    match resolve_element_id("black") {
      Ok(id) => id
      Err(_) => ""
    },
    "wallbreaker",
  )
  assert_eq(
    match resolve_element_id("bogus") {
      Ok(_) => "ok"
      Err(_) => "err"
    },
    "err",
  )
  assert_eq(
    match resolve_element_id("") {
      Ok(_) => "ok"
      Err(_) => "err"
    },
    "err",
  )
}

///|
test "defs: resolve_elements 去重保序，任一非法整批 Err" {
  assert_eq(
    match resolve_elements(["black", "wallbreaker", "golddigger"]) {
      Ok(a) => a.length()
      Err(_) => -1
    },
    2,
  )
  assert_eq(
    match resolve_elements(["black", "nope"]) {
      Ok(_) => "ok"
      Err(_) => "err"
    },
    "err",
  )
  assert_eq(hexa_defaults().length(), 3)
}

// ---------------------------------------------------------------------------
// hat_config
// ---------------------------------------------------------------------------

///|
test "config: 解析合法 config_json" {
  let cfg = match
    parse_config_json(
      "{\"topic\":\"是否上线\",\"hats\":[\"black\",\"golddigger\",\"white\"]," +
      "\"hat_policy\":{\"max_rounds\":3,\"converge_threshold\":0.7,\"auto_select_hats\":false,\"debate_enabled\":false}}",
    ) {
    Ok(c) => c
    Err(m) => abort("应解析成功：" + m)
  }
  assert_eq(cfg.topic, "是否上线")
  assert_eq(cfg.elements.length(), 3)
  assert_eq(cfg.policy.max_rounds, 3)
  assert_eq(cfg.policy.converge_threshold == 0.7, true)
  assert_eq(cfg.policy.debate_enabled, false)
}

///|
test "config: hats 缺省 + auto_select_hats → 默认三元" {
  let cfg = match parse_config_json("{\"topic\":\"t\"}") {
    Ok(c) => c
    Err(m) => abort("应解析成功：" + m)
  }
  assert_eq(cfg.elements.length(), 3)
  assert_eq(cfg.policy.max_rounds, 2)
  assert_eq(cfg.policy.converge_threshold == 0.6, true)
}

///|
test "config: 空 hats + auto_select=false → Err" {
  assert_true(
    match
      parse_config_json(
        "{\"topic\":\"t\",\"hats\":[],\"hat_policy\":{\"auto_select_hats\":false}}",
      ) {
      Err(_) => true
      Ok(_) => false
    },
  )
}

///|
test "config: 负路径（空/非法 JSON/非对象/空 topic/未知帽/越界参数/少于 2 帽）" {
  assert_eq(
    match parse_config_json("") {
      Err(_) => "err"
      _ => "ok"
    },
    "err",
  )
  assert_eq(
    match parse_config_json("{oops") {
      Err(_) => "err"
      _ => "ok"
    },
    "err",
  )
  assert_eq(
    match parse_config_json("[1,2]") {
      Err(_) => "err"
      _ => "ok"
    },
    "err",
  )
  assert_eq(
    match parse_config_json("{\"hats\":[\"black\"]}") {
      Err(_) => "err"
      _ => "ok"
    },
    "err",
  )
  assert_eq(
    match parse_config_json("{\"topic\":\"t\",\"hats\":[\"bogus\"]}") {
      Err(_) => "err"
      _ => "ok"
    },
    "err",
  )
  assert_eq(
    match
      parse_config_json(
        "{\"topic\":\"t\",\"hats\":[\"black\",\"white\"],\"hat_policy\":{\"max_rounds\":0}}",
      ) {
      Err(m) => if m.contains("max_rounds") { "err" } else { "other" }
      _ => "ok"
    },
    "err",
  )
  assert_eq(
    match
      parse_config_json(
        "{\"topic\":\"t\",\"hats\":[\"black\",\"white\"],\"hat_policy\":{\"converge_threshold\":1.5}}",
      ) {
      Err(m) => if m.contains("converge_threshold") { "err" } else { "other" }
      _ => "ok"
    },
    "err",
  )
  assert_eq(
    match parse_config_json("{\"topic\":\"t\",\"hats\":[\"black\"]}") {
      Err(_) => "err"
      _ => "ok"
    },
    "err",
  )
}

///|
test "config: default_config 三元素齐全" {
  let c = default_config("议题")
  assert_eq(c.topic, "议题")
  assert_eq(c.elements.length(), 3)
}

// ---------------------------------------------------------------------------
// hat_report
// ---------------------------------------------------------------------------

///|
test "report: valid_report 正/负路径" {
  assert_eq(
    match valid_report(rep("stargazer", "pass", 0.5, ["x"])) {
      Ok(_) => "ok"
      _ => "err"
    },
    "ok",
  )
  assert_eq(
    match valid_report(rep("bogus", "pass", 0.5, ["x"])) {
      Err(_) => "err"
      _ => "ok"
    },
    "err",
  )
  assert_eq(
    match valid_report(rep("stargazer", "bogus", 0.5, ["x"])) {
      Err(_) => "err"
      _ => "ok"
    },
    "err",
  )
  assert_eq(
    match valid_report(rep("stargazer", "pass", 1.5, ["x"])) {
      Err(_) => "err"
      _ => "ok"
    },
    "err",
  )
  let empty_ev = hat_report("stargazer", "pass", 0.5, "", [], "")
  assert_eq(
    match valid_report(empty_ev) {
      Err(_) => "err"
      _ => "ok"
    },
    "err",
  )
}

// ---------------------------------------------------------------------------
// hat_divergence
// ---------------------------------------------------------------------------

///|
test "divergence: 结论对冲判定 verdict_conflict（严重度 3）" {
  let rs = [
    rep("wallbreaker", "reject", 0.8, ["风险大"]),
    rep("golddigger", "pass", 0.7, ["价值大"]),
  ]
  let ds = extract_divergences(rs)
  assert_eq(ds.length(), 1)
  assert_eq(ds[0].kind, "verdict_conflict")
  assert_eq(ds[0].severity, 3)
}

///|
test "divergence: 置信度落差 confidence_gap（严重度 2）" {
  let rs = [
    rep("wallbreaker", "pass", 0.9, ["风险可控"]),
    rep("golddigger", "pass", 0.3, ["价值明显"]),
  ]
  let ds = extract_divergences(rs)
  assert_eq(ds.length(), 1)
  assert_eq(ds[0].kind, "confidence_gap")
  assert_eq(ds[0].severity, 2)
}

///|
test "divergence: 论据路径差异 evidence_mismatch（严重度 1）" {
  let rs = [
    rep("wallbreaker", "pass", 0.6, ["风险可控", "有证据"]),
    rep("golddigger", "pass", 0.6, ["收益巨大", "机会多"]),
  ]
  let ds = extract_divergences(rs)
  assert_eq(ds.length(), 1)
  assert_eq(ds[0].kind, "evidence_mismatch")
  assert_eq(ds[0].severity, 1)
}

///|
test "divergence: 完全一致无分歧；abstain 跳过；blocking/count" {
  let same = [
    rep("wallbreaker", "pass", 0.7, ["风险可控"]),
    rep("golddigger", "pass", 0.7, ["风险可控"]),
  ]
  assert_eq(extract_divergences(same).length(), 0)
  // abstain 不参与
  let mixed = [
    rep("wallbreaker", "reject", 0.8, ["风险大"]),
    rep("nova", "abstain", 0.5, ["想法"]),
    rep("golddigger", "pass", 0.7, ["价值大"]),
  ]
  assert_eq(extract_divergences(mixed).length(), 1)
  let ds = extract_divergences(mixed)
  assert_eq(blocking_divergences(ds).length(), 1)
  assert_eq(count_by_kind(ds).get("verdict_conflict"), Some(1))
}

// ---------------------------------------------------------------------------
// hat_converge
// ---------------------------------------------------------------------------

///|
test "converge: converged（rate 达标且无对冲）" {
  let rs = [
    rep("stargazer", "pass", 0.8, ["数据"]),
    rep("wallbreaker", "pass", 0.7, ["风险可控"]),
    rep("golddigger", "pass", 0.75, ["价值"]),
  ]
  let c = converge(rs, default_policy(), 1)
  assert_eq(c.status, "converged")
  assert_eq(c.should_iterate, false)
  assert_eq(c.terminal_gate, "user")
  assert_true(c.next_round_hint().contains("已收敛"))
}

///|
test "converge: partial（rate 达标但有对冲）" {
  let rs = [
    rep("wallbreaker", "reject", 0.8, ["风险大"]),
    rep("stargazer", "pass", 0.7, ["数据"]),
    rep("golddigger", "pass", 0.7, ["价值"]),
    rep("nova", "pass", 0.7, ["想法"]),
  ]
  let c = converge(rs, default_policy(), 1)
  assert_eq(c.status, "partial")
  assert_eq(c.should_iterate, true)
  // 1 个 reject 对冲 3 个 pass → 3 条 verdict_conflict（两两成对，正确语义）
  assert_eq(c.blocking, 3)
}

///|
test "converge: diverged（rate 不达标）且 round 达上限不再迭代" {
  let rs = [
    rep("wallbreaker", "reject", 0.8, ["风险大"]),
    rep("golddigger", "reject", 0.7, ["价值小"]),
  ]
  let c = converge(rs, default_policy(), 2)
  assert_eq(c.status, "diverged")
  assert_eq(c.should_iterate, false)
  assert_true(c.next_round_hint().contains("已达轮次上限"))
}

// ---------------------------------------------------------------------------
// hat_plan
// ---------------------------------------------------------------------------

///|
test "plan: build_plan 每帽一任务 + 星核 + 辩论对" {
  let cfg = match
    parse_config_json(
      "{\"topic\":\"上线\",\"hats\":[\"wallbreaker\",\"golddigger\",\"pulse\",\"nova\"]}",
    ) {
    Ok(c) => c
    Err(m) => abort("应解析成功：" + m)
  }
  let p = build_plan(cfg.topic, cfg)
  // 4 帽任务 + 星核
  assert_eq(p.tasks.length(), 4)
  assert_eq(p.nucleus.element_id, "nucleus")
  // 黑↔黄 + 红↔绿 都在 → 2 对
  assert_eq(p.debate_pairs.length(), 2)
  // 每任务 prompt 含议题与输出契约
  for t in p.tasks {
    assert_true(t.prompt.contains("上线"))
    assert_true(t.prompt.contains("输出契约"))
    assert_eq(t.executor_hint, "ofm")
    assert_true(!t.dry_run_shape.is_empty())
  }
}

///|
test "plan: debate_enabled=false 时无辩论对；default_config 3 任务" {
  let cfg = match
    parse_config_json(
      "{\"topic\":\"上线\",\"hats\":[\"black\",\"yellow\"],\"hat_policy\":{\"debate_enabled\":false}}",
    ) {
    Ok(c) => c
    Err(m) => abort("应解析成功：" + m)
  }
  let p = build_plan(cfg.topic, cfg)
  assert_eq(p.debate_pairs.length(), 0)
  assert_eq(p.tasks.length(), 2)
}

// ---------------------------------------------------------------------------
// hat_report_build
// ---------------------------------------------------------------------------

///|
test "build: 报告组装（含 status / 分歧表 / 终审门），非法报告被剔除" {
  let cfg = default_config("议题")
  let rs = [
    rep("stargazer", "pass", 0.8, ["数据"]),
    rep("wallbreaker", "reject", 0.8, ["风险大"]),
    rep("golddigger", "pass", 0.7, ["价值"]),
    hat_report("stargazer", "pass", 0.5, "", [], ""),
  ]
  let r = build_report(cfg.topic, cfg, rs, 1)
  // 空 evidence 那条被剔除 → 3 条有效
  assert_eq(r.reports.length(), 3)
  assert_true(r.markdown.contains("HexaMind 六元裁决报告"))
  assert_true(r.markdown.contains("部分收敛"))
  assert_true(r.markdown.contains("终审门"))
  assert_eq(r.terminal_gate, "user")
}

///|
test "BUG-205：报告表「帽子」列显示六顶帽 id（hexa_hat_id），不再误填 verdict" {
  let cfg = default_config("议题")
  let rs = [
    rep("stargazer", "pass", 0.8, ["数据"]),
    rep("wallbreaker", "reject", 0.8, ["风险"]),
  ]
  let r = build_report(cfg.topic, cfg, rs, 1)
  // 观星者=stargazer→白帽(white)；破壁者=wallbreaker→黑帽(black)
  assert_true(
    r.markdown.contains("观星者（stargazer） | white | pass"),
    msg="「帽子」列应显示 white",
  )
  assert_true(
    r.markdown.contains("破壁者（wallbreaker） | black | reject"),
    msg="「帽子」列应显示 black",
  )
  // 回归钉：旧实现把 verdict 连写两遍，帽子列 == 判决列
  assert_true(
    !r.markdown.contains("（stargazer） | pass | pass"),
    msg="「帽子」列不得再等于 verdict",
  )
}
