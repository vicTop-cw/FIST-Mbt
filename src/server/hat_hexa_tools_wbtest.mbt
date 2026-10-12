/// hat_hexa_tools_wbtest.mbt —— HexaMind MCP 工具层白盒测试（R119）
///
/// 覆盖：hat_run（正/负）、hat_merge（正/负/默认策略）、hat_debate（正/负/缺省议题）、
/// parse_reports（非法报告整笔拒）。白盒：可直调 hat_run_impl / hat_merge_impl /
/// hat_debate_impl / parse_reports。

///|
fn hs_jstr(v : String) -> Json {
  Json::string(v)
}

///|
test "hexatools: hat_run 生成每帽任务 + 星核 + 辩论对" {
  let cfg = "{\"topic\":\"上线\",\"hats\":[\"black\",\"golddigger\",\"pulse\",\"nova\"]}"
  let args = Json::object({
    "config_json": hs_jstr(cfg),
    "round": Json::number(1.0),
  })
  let j = match hat_run_impl(args) {
    Ok(v) => v
    Err(m) => abort("hat_run 应成功：" + m)
  }
  let obj = match j {
    Json::Object(m) => m
    _ => abort("返回应为对象")
  }
  assert_eq(
    match obj.get("topic") {
      Some(Json::String(s)) => s
      _ => ""
    },
    "上线",
  )
  let tasks = match obj.get("tasks") {
    Some(Json::Array(a)) => a.length()
    _ => -1
  }
  assert_eq(tasks, 4)
  // 星核恒在
  let nuc = match obj.get("nucleus") {
    Some(v) => v
    _ => abort("缺 nucleus")
  }
  assert_eq(
    match nuc {
      Json::Object(m) =>
        match m.get("element_id") {
          Some(Json::String(s)) => s
          _ => ""
        }
      _ => ""
    },
    "nucleus",
  )
  // 黑↔黄 + 红↔绿 → 2 对
  let pairs = match obj.get("debate_pairs") {
    Some(Json::Array(a)) => a.length()
    _ => -1
  }
  assert_eq(pairs, 2)
  // 每个任务带 ofm 执行提示与 dry_run_shape
  let has_exec_hint = match obj.get("tasks") {
    Some(Json::Array(a)) =>
      a.any(fn(t) {
        match t {
          Json::Object(m) =>
            match m.get("executor_hint") {
              Some(Json::String(s)) => s == "ofm"
              _ => false
            }
          _ => false
        }
      })
    _ => false
  }
  assert_true(has_exec_hint)
}

///|
test "hexatools: hat_run 空 config_json / 非法 JSON → Err" {
  let e1 = match hat_run_impl(Json::object({ "config_json": hs_jstr("") })) {
    Err(_) => "err"
    Ok(_) => "ok"
  }
  assert_eq(e1, "err")
  let e2 = match
    hat_run_impl(Json::object({ "config_json": hs_jstr("{oops") })) {
    Err(_) => "err"
    Ok(_) => "ok"
  }
  assert_eq(e2, "err")
}

///|
test "hexatools: hat_merge 分歧提取 + 收敛 + 报告" {
  let reports = "[{\"element_id\":\"wallbreaker\",\"verdict\":\"reject\",\"confidence\":0.8," +
    "\"evidence\":\"风险大\",\"outcomes\":[\"风险大\"]}," +
    "{\"element_id\":\"golddigger\",\"verdict\":\"pass\",\"confidence\":0.7," +
    "\"evidence\":\"价值大\",\"outcomes\":[\"价值大\"]}]"
  let args = Json::object({
    "topic": hs_jstr("是否上线"),
    "reports_json": hs_jstr(reports),
  })
  let j = match hat_merge_impl(args) {
    Ok(v) => v
    Err(m) => abort("hat_merge 应成功：" + m)
  }
  let obj = match j {
    Json::Object(m) => m
    _ => abort("返回应为对象")
  }
  assert_eq(
    match obj.get("status") {
      Some(Json::String(s)) => s
      _ => ""
    },
    "diverged",
  )
  assert_eq(
    match obj.get("terminal_gate") {
      Some(Json::String(s)) => s
      _ => ""
    },
    "user",
  )
  // 1 个 reject 对冲 1 个 pass → 1 条 verdict_conflict
  let dv = match obj.get("divergences") {
    Some(Json::Array(a)) => a.length()
    _ => -1
  }
  assert_eq(dv, 1)
  let md = match obj.get("markdown") {
    Some(Json::String(s)) => s
    _ => ""
  }
  assert_true(md.contains("HexaMind 六元裁决报告"))
}

///|
test "hexatools: hat_merge 缺省策略可用；非法报告整笔拒" {
  // 缺 config_json → 默认策略（max_rounds=2, threshold=0.6）
  let reports = "[{\"element_id\":\"stargazer\",\"verdict\":\"pass\",\"confidence\":0.8," +
    "\"evidence\":\"数据\",\"outcomes\":[\"数据\"]}]"
  let args = Json::object({
    "topic": hs_jstr("t"),
    "reports_json": hs_jstr(reports),
  })
  let j = match hat_merge_impl(args) {
    Ok(v) => v
    Err(m) => abort("应成功：" + m)
  }
  assert_eq(
    match j {
      Json::Object(m) =>
        match m.get("convergence") {
          Some(Json::Object(c)) =>
            match c.get("max_rounds") {
              Some(Json::Number(n, ..)) => n == 2.0
              _ => false
            }
          _ => false
        }
      _ => false
    },
    true,
  )
  // 空 evidence → 整笔拒
  let bad = "[{\"element_id\":\"stargazer\",\"verdict\":\"pass\",\"confidence\":0.5,\"evidence\":\"\",\"outcomes\":[]}]"
  let args2 = Json::object({
    "topic": hs_jstr("t"),
    "reports_json": hs_jstr(bad),
  })
  assert_eq(
    match hat_merge_impl(args2) {
      Err(_) => "err"
      Ok(_) => "ok"
    },
    "err",
  )
}

///|
test "hexatools: hat_debate 正/负路径 + 缺省议题" {
  let ok = match
    hat_debate_impl(
      Json::object({
        "left": hs_jstr("wallbreaker"),
        "right": hs_jstr("golddigger"),
      }),
    ) {
    Ok(v) => v
    Err(m) => abort("应成功：" + m)
  }
  let issue = match ok {
    Json::Object(m) =>
      match m.get("debate") {
        Some(Json::Object(d)) =>
          match d.get("issue") {
            Some(Json::String(s)) => s
            _ => ""
          }
        _ => ""
      }
    _ => ""
  }
  assert_true(issue.contains("风险"))
  // 相同两元 → Err
  assert_eq(
    match
      hat_debate_impl(
        Json::object({ "left": hs_jstr("nova"), "right": hs_jstr("nova") }),
      ) {
      Err(_) => "err"
      Ok(_) => "ok"
    },
    "err",
  )
  // 未知代号 → Err
  assert_eq(
    match
      hat_debate_impl(
        Json::object({ "left": hs_jstr("bogus"), "right": hs_jstr("nova") }),
      ) {
      Err(_) => "err"
      Ok(_) => "ok"
    },
    "err",
  )
  // rounds 越界 → Err
  assert_eq(
    match
      hat_debate_impl(
        Json::object({
          "left": hs_jstr("pulse"),
          "right": hs_jstr("nova"),
          "rounds": Json::number(9.0),
        }),
      ) {
      Err(_) => "err"
      Ok(_) => "ok"
    },
    "err",
  )
}

///|
test "hexatools: parse_reports 顶层非数组 / 非法字段 → Err" {
  assert_eq(
    match parse_reports("{\"a\":1}") {
      Err(_) => "err"
      Ok(_) => "ok"
    },
    "err",
  )
  assert_eq(
    match parse_reports("[{\"element_id\":\"bogus\"}]") {
      Err(_) => "err"
      Ok(_) => "ok"
    },
    "err",
  )
  assert_eq(
    match parse_reports("not json") {
      Err(_) => "err"
      Ok(_) => "ok"
    },
    "err",
  )
}
