/// laya_decide_wbtest.mbt —— BUG-14 回归：laya_decide 契约要求顶层恒含 `decision`。
///
/// 背景（活证据见 memory/bugs.md BUG-14）：sidecar（scripts/laya_decide.py）只产出
/// answers/auto_decide/escalate，从不产出 decision；且 src/server/laya_js.mbt 在退出码
/// 非 0 时把 available 覆写为 false 后**仍返回 Ok(...)**，因此 handler 里
/// `Ok(res) => res.stringify()` 的透传路径（4 条返回路径中的 3 条）从不带 decision，
/// 调用方按工具描述取 decision.feature_route 拿到 undefined。
///
/// 这里直接白盒验证补齐逻辑 `laya_ensure_decision`（handler 是 async 且真起子进程，
/// 同步测试无法 await，故守在被修复的那个唯一决策点上——四条路径都归一到它）。

///|
/// 取顶层字符串字段（无则空串）。
fn ld_str(j : Json, key : String) -> String {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
}

///|
/// 取顶层数值字段（无则 -1）。
fn ld_num(j : Json, key : String) -> Double {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(Number(n, ..)) => n
        _ => -1.0
      }
    _ => -1.0
  }
}

///|
/// 顶层布尔字段（缺失/非布尔返回 default）。
fn ld_bool(j : Json, key : String, default : Bool) -> Bool {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(True) => true
        Some(False) => false
        _ => default
      }
    _ => default
  }
}

///|
/// 取内层 decision 对象（无则 None）。
fn ld_decision(j : Json) -> Map[String, Json]? {
  match j {
    Object(m) =>
      match m.get("decision") {
        Some(Object(d)) => Some(d)
        _ => None
      }
    _ => None
  }
}

///|
/// 顶层是否带满足契约的 decision（feature_route 非空 + split_n ∈ [2,6]）。
fn ld_has_decision(j : Json) -> Bool {
  match ld_decision(j) {
    None => false
    Some(d) => {
      let route_ok = match d.get("feature_route") {
        Some(String(s)) => s != ""
        _ => false
      }
      let split_ok = match d.get("split_n") {
        Some(Number(n, ..)) => n >= 2.0 && n <= 6.0
        _ => false
      }
      route_ok && split_ok
    }
  }
}

///|
test "BUG-14：available=true 的 sidecar 原样输出（无 decision）被补齐" {
  // 复刻本机 Laya 已装、退出码 0 的透传形态：只有 answers/auto_decide/escalate/exit_code
  let res = Json::object({
    "available": Json::boolean(true),
    "answers": Json::object({
      "difficulty": Json::object({ "score": Json::number(2.3) }),
    }),
    "auto_decide": Json::boolean(false),
    "escalate": Json::boolean(true),
    "exit_code": Json::number(0.0),
  })
  let fixed = laya_ensure_decision(
    res, "需要把跨模块重构任务拆成子任务并按能力派单", 3,
  )
  assert_true(ld_has_decision(fixed))
  // 原判定不得被修复吞掉
  assert_true(ld_bool(fixed, "available", false))
  assert_eq(ld_num(fixed, "exit_code"), 0.0)
  assert_true(ld_str(fixed, "decision_note").contains("laya_route"))
}

///|
test "BUG-14：退出码非 0（code=143）形态也必须带 decision，且不改 available/exit_code/reason" {
  let res = Json::object({
    "available": Json::boolean(false),
    "reason": Json::string(
      "laya sidecar 退出码非 0（code=143）——视为不可用",
    ),
    "exit_code": Json::number(143.0),
  })
  let fixed = laya_ensure_decision(
    res, "为分布式任务编排系统设计跨命名空间自愈算法", 4,
  )
  assert_true(ld_has_decision(fixed))
  assert_true(not(ld_bool(fixed, "available", true)))
  assert_eq(ld_num(fixed, "exit_code"), 143.0)
  assert_true(ld_str(fixed, "reason").contains("143"))
}

///|
test "BUG-14：sidecar 自带 decision 时原样保留（前向兼容，不被规则式覆盖）" {
  let res = Json::object({
    "available": Json::boolean(true),
    "decision": Json::object({
      "source": Json::string("laya"),
      "feature_route": Json::string("排程路由"),
      "split_n": Json::number(5.0),
    }),
  })
  let fixed = laya_ensure_decision(res, "任意描述", 3)
  // 自带 decision → 不加注、不覆盖
  assert_eq(ld_str(fixed, "decision_note"), "")
  match ld_decision(fixed) {
    None => assert_false(true)
    Some(d) => {
      let dj = Json::object(d)
      assert_eq(ld_str(dj, "source"), "laya")
      assert_eq(ld_str(dj, "feature_route"), "排程路由")
      assert_eq(ld_num(dj, "split_n"), 5.0)
    }
  }
}

///|
test "BUG-14：非对象响应（sidecar 输出脏数据）不 panic，仍给 decision" {
  let res = Json::string("just a string")
  let fixed = laya_ensure_decision(res, "简单任务", 0)
  assert_true(ld_has_decision(fixed))
}

///|
test "BUG-14：decision 的 split_n 受 hint 影响且夹在 [2,6]（不越界）" {
  let res = Json::object({ "available": Json::boolean(false) })
  let lo = laya_ensure_decision(res, "拆解调度演示", -10)
  assert_true(ld_has_decision(lo))
  let hi = laya_ensure_decision(res, "拆解调度演示", 99)
  assert_true(ld_has_decision(hi))
}

///|
test "BUG-14 加固：同输入两次补齐结果一致（确定性，可复现）" {
  let res = Json::object({
    "available": Json::boolean(false),
    "exit_code": Json::number(1.0),
  })
  let a = laya_ensure_decision(
    res, "熔断器与补偿事务的回归验证", 3,
  ).stringify()
  let b = laya_ensure_decision(
    res, "熔断器与补偿事务的回归验证", 3,
  ).stringify()
  assert_eq(a, b)
}
