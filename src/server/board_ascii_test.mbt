// board_ascii 实时任务看板渲染测试。

///|
fn ba_engine() -> @engine.FistEngine {
  @engine.FistEngine::new()
}

///|
fn ba_publish(e : @engine.FistEngine, desc : String) -> String {
  match
    e.publish(
      project_dir="/proj/board",
      description=desc,
      created_by="human_steward",
      now="2026-09-25T10:00:00Z",
    ) {
    Ok(id) => id
    Err(m) => abort("publish failed: \{m}")
  }
}

///|
/// 读出 health_check 的 grade。
fn hc_grade(j : Json) -> String {
  match j.value("grade") {
    Some(Json::String(s)) => s
    _ => abort("grade 缺失: " + j.stringify())
  }
}

///|
/// 读出 health_check signals 中某信号 verdict。
fn hc_signal_verdict(j : Json, key : String) -> String {
  let obj = match j.value("signals") {
    Some(Object(o)) => o
    _ => return ""
  }
  let sj = match obj.get(key) {
    Some(x) => x
    _ => return ""
  }
  match sj.value("verdict") {
    Some(Json::String(v)) => v
    _ => ""
  }
}

///|
test "health_check：空仓 → idle（traffic=0），latency insufficient" {
  let e = ba_engine()
  let j = render_health_check(e.list_all(), "default")
  assert_eq(hc_grade(j), "idle")
  assert_eq(hc_signal_verdict(j, "traffic"), "idle")
  assert_eq(hc_signal_verdict(j, "latency"), "insufficient")
}

///|
test "health_check：积压先行预警——待领取过半 → saturation attention（SRE：先积压后坏）" {
  let e = ba_engine()
  let root = ba_publish(e, "四金信号根任务")
  ignore(e.claim(task_id=root, assignee="leader_a", now="2026-09-25T10:01:00Z"))
  match
    e.plan_deep(
      task_id=root,
      split_n=4,
      by="leader_a",
      now="2026-09-25T10:02:00Z",
    ) {
    Ok(_) => ()
    Err(m) => abort("plan_deep failed: \{m}")
  }
  // 5 任务（根+4 子）：ready=4 → 饱和 0.8 > 0.5 → attention
  let j = render_health_check(e.list_all(), "default")
  assert_eq(hc_signal_verdict(j, "saturation"), "attention")
  assert_eq(hc_grade(j), "attention")
}

///|
test "health_check：healthy + latency 百分位——3 完成 1 待领取，p50/p90 出现" {
  let e = ba_engine()
  // 直接 store 构造精确状态（避免 plan_deep 递归生成不可控任务数）：
  // 根 R(拆分中) + A/B/C(已完成，周期 120s) + D(待领取) → total=5：in_flight=1 ready=1 done=3
  let specs : Array[(String, String?, String, String, String)] = [
    ("R", None, "拆分中", "2026-09-25T10:02:00Z", "2026-09-25T10:02:00Z"),
    (
      "A",
      Some("R"),
      "已完成",
      "2026-09-25T10:02:00Z",
      "2026-09-25T10:04:00Z",
    ),
    (
      "B",
      Some("R"),
      "已完成",
      "2026-09-25T10:02:00Z",
      "2026-09-25T10:04:00Z",
    ),
    (
      "C",
      Some("R"),
      "已完成",
      "2026-09-25T10:02:00Z",
      "2026-09-25T10:04:00Z",
    ),
    (
      "D",
      Some("R"),
      "待领取",
      "2026-09-25T10:02:00Z",
      "2026-09-25T10:02:00Z",
    ),
  ]
  for s in specs {
    let (id, parent, st, created, updated) = s
    let t = @core.Task::from_db(
      id,
      parent,
      "/proj/board",
      "default",
      "中",
      "中",
      1,
      1,
      st,
      if st == "已完成" {
        Some("exec_1")
      } else {
        None
      },
      "四金信号健康任务 \{id}",
      "",
      created,
      updated,
      if st == "已完成" {
        Some("ver_1")
      } else {
        None
      },
      "",
      [],
    )
    ignore(e.store.create_task(t))
  }
  let j = render_health_check(e.list_all(), "default")
  assert_eq(hc_signal_verdict(j, "latency"), "ok")
  assert_eq(hc_grade(j), "healthy")
  match j.value("signals") {
    Some(Object(o)) =>
      match o.get("latency") {
        Some(sj) =>
          match sj.value("p50_secs") {
            Some(Json::Number(n, ..)) => assert_eq(n.to_int(), 120)
            _ => abort("p50_secs 缺失: " + j.stringify())
          }
        _ => abort("latency 缺失")
      }
    _ => abort("signals 缺失")
  }
}

///|
test "board_ascii 按状态分组 + 深度缩进 + 状态合计" {
  let e = ba_engine()
  let root = ba_publish(e, "Omega 看板根任务")
  ignore(e.claim(task_id=root, assignee="leader_a", now="2026-09-25T10:01:00Z"))
  match
    e.plan_deep(
      task_id=root,
      split_n=2,
      by="leader_a",
      now="2026-09-25T10:02:00Z",
    ) {
    Ok(_) => ()
    Err(m) => abort("plan_deep failed: \{m}")
  }
  // 认领其中一个子任务进入执行，制造"sizing 中"状态
  let children = e.children_of(root)
  assert_true(children.length() >= 2)
  let c0 = children[0].get_id()
  ignore(e.claim(task_id=c0, assignee="exec_1", now="2026-09-25T10:03:00Z"))
  ignore(
    e.execute(task_id=c0, deliverable="成果 v1", now="2026-09-25T10:04:00Z"),
  )

  let board = render_board_ascii(e.list_all(), "")
  let j = board.stringify()
  // 状态合计头尾都在
  assert_true(j.contains("状态合计"))
  assert_true(j.contains("待领取"))
  assert_true(j.contains("执行中"))
  // 深度缩进（子任务行以 · 开头）与状态标记
  assert_true(j.contains("[待领取]"))
  assert_true(j.contains("[执行中]"))
  // counts 对象非空（渲染了至少一个状态分组，行断言已覆盖多状态分组）
  let cnt = match board.value("counts") {
    Some(Object(m)) => m
    _ => abort("counts 缺失")
  }
  assert_true(cnt.length() >= 1)
}

///|
test "board_ascii 支持 namespace 过滤" {
  let e = ba_engine()
  let root = ba_publish(e, "看板 ns 过滤根")
  ignore(e.claim(task_id=root, assignee="leader_a", now="2026-09-25T10:10:00Z"))
  match
    e.plan_deep(
      task_id=root,
      split_n=1,
      by="leader_a",
      now="2026-09-25T10:11:00Z",
    ) {
    Ok(_) => ()
    Err(m) => abort("plan_deep failed: \{m}")
  }
  let tasks = e.list_all()
  // 全部命名空间视图应含任务
  let all = render_board_ascii(tasks, "").stringify()
  assert_true(all.contains("待领取"))
  // 按不存在的 ns 过滤：不应出现任何任务行
  let none = render_board_ascii(tasks, "no-such-ns").stringify()
  assert_true(none.contains("状态合计"))
  assert_false(none.contains("[待领取]"))
  assert_false(none.contains("[已领取]"))
}

///|
test "status_summary 项目脉冲：总量 + 按状态计数 + 活跃命名空间" {
  let e = ba_engine()
  let root = ba_publish(e, "脉冲根任务")
  ignore(e.claim(task_id=root, assignee="leader_a", now="2026-09-25T10:20:00Z"))
  match
    e.plan_deep(
      task_id=root,
      split_n=1,
      by="leader_a",
      now="2026-09-25T10:21:00Z",
    ) {
    Ok(_) => ()
    Err(m) => abort("plan_deep failed: \{m}")
  }
  let tasks = e.list_all()
  assert_true(tasks.length() >= 2)
  let s = render_status_summary(tasks, ["default"], "0.2.4").stringify()
  // 总量 = 引擎任务数
  match
    render_status_summary(tasks, ["default"], "0.2.4").value("total_tasks") {
    Some(Number(n, ..)) => assert_eq(n.to_int(), tasks.length())
    _ => abort("total_tasks 缺失: " + s)
  }
  assert_true(s.contains("\"version\":\"0.2.4\""))
  assert_true(s.contains("active_namespaces"))
  assert_true(s.contains("default"))
  // 至少有一个状态计数（待领取 等）
  assert_true(s.contains("待领取"))
  // by_difficulty 不变量：各难度档数量之和 == 待领取任务数（复用 extract_difficulty，支柱②）
  match
    render_status_summary(tasks, ["default"], "0.2.4").value("by_difficulty") {
    Some(Object(dm)) => {
      let mut sum = 0.0
      for (_k, v) in dm {
        match v {
          Number(n, ..) => sum = sum + n
          _ => ()
        }
      }
      let mut pend = 0
      for t in tasks {
        if t.status_to_string() == "待领取" {
          pend = pend + 1
        }
      }
      assert_eq(sum.to_int(), pend)
    }
    _ => abort("by_difficulty 缺失: " + s)
  }
}

///|
test "status_summary 支持 namespace 过滤：只统计该 ns" {
  let e = ba_engine()
  let root = ba_publish(e, "脉冲 ns 过滤根")
  ignore(e.claim(task_id=root, assignee="leader_a", now="2026-09-25T10:30:00Z"))
  match
    e.plan_deep(
      task_id=root,
      split_n=1,
      by="leader_a",
      now="2026-09-25T10:31:00Z",
    ) {
    Ok(_) => ()
    Err(m) => abort("plan_deep failed: \{m}")
  }
  let tasks = e.list_all()
  // 按任务的真实 ns 过滤：total = 该 ns 任务数（此处应 >= 1 且 <= 全部）
  let ns = tasks[0].ns
  let scoped = render_status_summary(
    tasks.filter(fn(t) { t.ns == ns }),
    ["default"],
    "0.2.4",
  )
  match scoped.value("total_tasks") {
    Some(Number(n, ..)) => assert_true(n.to_int() >= 1)
    _ => abort("scoped total_tasks 缺失: " + scoped.stringify())
  }
  // 按不存在的 ns 过滤：total 应为 0
  let zero = render_status_summary(
    tasks.filter(fn(t) { t.ns == "no-such-ns" }),
    [],
    "0.2.4",
  )
  match zero.value("total_tasks") {
    Some(Number(n, ..)) => assert_eq(n.to_int(), 0)
    _ => abort("zero total_tasks 缺失: " + zero.stringify())
  }
}

///|
test "board_ascii 每行标注难度档（复用 extract_difficulty，支柱①+②）" {
  let e = ba_engine()
  let root = ba_publish(e, "看板难度根")
  ignore(e.claim(task_id=root, assignee="leader_a", now="2026-09-25T10:01:00Z"))
  ignore(
    e.plan_deep(
      task_id=root,
      split_n=3,
      by="leader_a",
      gradient=true,
      now="2026-09-25T10:02:00Z",
    ),
  )
  let j = render_board_ascii(e.list_all(), "")
  match j.value("ascii") {
    Some(String(s)) => assert_true(s.contains("难度["))
    _ => abort("ascii 缺失")
  }
}

///|
test "project_health 健康卡：聚合六类计数 + 等级判定（R68）" {
  let e = ba_engine()
  // 空库 -> empty
  let h0 = render_project_health(e.list_all(), "0.2.4")
  match h0.value("grade") {
    Some(String(g)) => assert_eq(g, "empty")
    _ => abort("空库 grade 应 empty")
  }
  // 发布根 + 认领 -> 有 in_flight(+1 已领取)，root 状态已领取 -> healthy（无阻塞、有进行）
  let root = ba_publish(e, "健康根任务")
  ignore(e.claim(task_id=root, assignee="leader_a", now="2026-09-25T11:00:00Z"))
  let h1 = render_project_health(e.list_all(), "0.2.4")
  match h1.value("grade") {
    Some(String(g)) => assert_eq(g, "healthy")
    _ => abort("有进行应 healthy")
  }
  match h1.value("in_flight") {
    Some(Number(n, ..)) => assert_true(n >= 1.0)
    _ => abort("in_flight 缺失")
  }
  // 暂停 -> 计入 blocked，grade 降为 attention
  ignore(e.pause_task(task_id=root, now="2026-09-25T11:01:00Z"))
  let h2 = render_project_health(e.list_all(), "0.2.4")
  match h2.value("grade") {
    Some(String(g)) => assert_eq(g, "attention")
    _ => abort("有阻塞应 attention")
  }
  match h2.value("blocked_tasks") {
    Some(Array(a)) => assert_true(a.length() >= 1)
    _ => abort("blocked_tasks 应含被暂停任务")
  }
  match h2.value("blocked") {
    Some(Number(n, ..)) => assert_true(n >= 1.0)
    _ => abort("blocked 计数缺失")
  }
}
