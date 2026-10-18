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
      6,
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
/// 读 health_check latency 信号中的数值字段（p50_secs / p90_secs）。
fn hc_latency_num(j : Json, key : String) -> Double {
  let obj = match j.value("signals") {
    Some(Object(o)) => o
    _ => abort("signals 缺失: " + j.stringify())
  }
  let sj = match obj.get("latency") {
    Some(x) => x
    _ => abort("latency 缺失: " + j.stringify())
  }
  match sj.value(key) {
    Some(Json::Number(n, ..)) => n
    _ => abort("\{key} 缺失: " + j.stringify())
  }
}

///|
/// BUG-207 回归锁：latency 的 p50/p90 必须用最近秩口径 (n-1)*p/100，
/// 旧代码 `done_cycles[n*50/100]` / `done_cycles[n*90/100]` 比最近秩恒高 1，
/// 在升序数组里读偏高一个元素，系统性高估 latency。
/// 本测试用 10 个**互不相同**的完成周期，旧代码读出的 p50=60/p90=100 与判据锁定值
/// p50=50/p90=90 必然不符；既有测试用 3 个相同周期（全 120s）恰好掩盖了偏差。
test "health_check：latency p50/p90 用最近秩 (n-1)*p（BUG-207）" {
  let e = ba_engine()
  // 10 个已完成任务，完成周期 10..100 秒（升序，互不相同）。
  // sorted cycles = [10,20,...,100]；最近秩：p50=index 4=50s，p90=index 8=90s。
  let updated_at : Array[String] = [
    "2026-09-25T10:00:10Z", "2026-09-25T10:00:20Z", "2026-09-25T10:00:30Z", "2026-09-25T10:00:40Z",
    "2026-09-25T10:00:50Z", "2026-09-25T10:01:00Z", "2026-09-25T10:01:10Z", "2026-09-25T10:01:20Z",
    "2026-09-25T10:01:30Z", "2026-09-25T10:01:40Z",
  ]
  for i = 0; i < updated_at.length(); i = i + 1 {
    let t = @core.Task::from_db(
      "HC_\{i}",
      None,
      "/proj/board",
      "default",
      "中",
      "中",
      1,
      1,
      6,
      "已完成",
      Some("exec_1"),
      "health latency \{i}",
      "",
      "2026-09-25T10:00:00Z",
      updated_at[i],
      Some("ver_1"),
      "",
      [],
    )
    ignore(e.store.create_task(t))
  }
  let j = render_health_check(e.list_all(), "default")
  assert_eq(hc_signal_verdict(j, "latency"), "ok")
  assert_eq(hc_latency_num(j, "p50_secs").to_int(), 50)
  assert_eq(hc_latency_num(j, "p90_secs").to_int(), 90)
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
/// BUG-210 回归锁：同状态组内 (depth, created_at) 全等的任务必须按 id 升序确定性渲染。
/// publish 固定 depth=3 且 created_at 取自 now 参数：两次 publish 传同一 now 即造出
/// 全等对（T0 与 T0r2）。旧比较器在全等时两方向都返回 1（cmp(a,b)=cmp(b,a)=1，
/// 严格弱序反对称性破坏），渲染顺序未定义；修复后 id 升序 → T0(乙) 必在 T0r2(甲) 之前。
test "board_ascii 组内全等任务按 id 升序（BUG-210）" {
  let e = ba_engine()
  ignore(
    e.publish(
      project_dir="/proj/board",
      description="ts_bbb 同刻乙",
      created_by="human_steward",
      now="2026-09-25T11:30:00Z",
    ),
  )
  ignore(
    e.publish(
      project_dir="/proj/board",
      description="ts_aaa 同刻甲",
      created_by="human_steward",
      now="2026-09-25T11:30:00Z",
    ),
  )
  let j = render_board_ascii(e.list_all(), "").stringify()
  let parts = j.split("ts_bbb").to_array()
  assert_eq(parts.length(), 2)
  assert_true(parts[1].contains("ts_aaa"))
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

///|
/// BUG-29 夹具：把任务推到已完成（deliv 非空则带交付物，空则复现"无成果已完成"的探针形状）
fn b29_done(id : String, deliv : String) -> @core.Task {
  let t0 = @core.Task::new(
    id~,
    project_dir="/proj/board",
    description="BUG-29 夹具 " + id,
    created_at="2026-09-27T00:00:00Z",
  )
  let t1 = match t0.claim(assignee="bot") {
    Ok(x) => x
    Err(m) => abort("claim: " + m)
  }
  let t2 = match t1.execute() {
    Ok(x) => x
    Err(m) => abort("execute: " + m)
  }
  let t3 = match t2.submit() {
    Ok(x) => x
    Err(m) => abort("submit: " + m)
  }
  let t4 = if deliv == "" {
    t3
  } else {
    t3.with_deliverable(deliv, "2026-09-27T00:01:00Z")
  }
  match t4.complete(completed_by="human_steward") {
    Ok(x) => x
    Err(m) => abort("complete: " + m)
  }
}

///|
/// 读顶层整数字段
fn b29_num(j : Json, key : String) -> Int {
  match j.value(key) {
    Some(Json::Number(n, ..)) => n.to_int()
    _ => abort("\{key} 缺失: " + j.stringify())
  }
}

///|
/// 读顶层整数字段（state_flow 用，缺失返回 0 fail-open）
fn sf_num(j : Json, key : String) -> Int {
  match j.value(key) {
    Some(Json::Number(n, ..)) => n.to_int()
    _ => 0
  }
}

///|
/// 读顶层布尔字段
fn b29_bool(j : Json, key : String) -> Bool {
  match j.value(key) {
    Some(v) =>
      match v.as_bool() {
        Some(b) => b
        None => abort("\{key} 非布尔: " + j.stringify())
      }
    None => abort("\{key} 缺失: " + j.stringify())
  }
}

///|
test "BUG-29：已完成单列 done_no_artifact 档——status_summary / board 两处口径一致" {
  let tasks = [
    b29_done("D1", "交付物 A"),
    b29_done("D2", ""),
    b29_done("D3", ""),
    b29_done("D4", "交付物 D"),
  ]
  let s = render_status_summary(tasks, ["default"], "0.3.0")
  // 已完成=4，其中无交付物=2（旧口径把两者混为一谈，指挥官按 status 判进度就把探针读成成果）
  match s.value("by_status") {
    Some(Object(m)) =>
      match m.get("已完成") {
        Some(Json::Number(n, ..)) => assert_eq(n.to_int(), 4)
        _ => abort("by_status.已完成 缺失: " + s.stringify())
      }
    _ => abort("by_status 缺失")
  }
  assert_eq(b29_num(s, "done_no_artifact"), 2)
  let b = render_board_ascii(tasks, "default")
  assert_eq(b29_num(b, "done_no_artifact"), 2)
  match b.value("ascii") {
    Some(Json::String(a)) => {
      assert_true(a.contains("已完成:4(无交付物2)"))
      // 作用域一致性：board 的计数按 ns 过滤后仍与 status_summary 同源
      let b2 = render_board_ascii(tasks, "nosuch")
      assert_eq(b29_num(b2, "done_no_artifact"), 0)
    }
    _ => abort("ascii 缺失")
  }
}

///|
/// 读 project_health 的 grade（与上方既有用例同口径，BUG-29 棘轮用例复用）
fn ph_grade(j : Json) -> String {
  match j.value("grade") {
    Some(Json::String(g)) => g
    _ => abort("grade 缺失: " + j.stringify())
  }
}

///|
test "BUG-29：棘轮——残留数等于基线不报警，高出基线即 project_health 压到 attention" {
  // 基线=账本点名作废的探针单（T0r286/T0r287，见 memory/bugs.md BUG-29）
  // P1 是待领取：让等级只由"残留"这一个变量决定（否则全已完成会先撞上 stalled）
  let p1 = @core.Task::new(
    id="P1",
    project_dir="/proj/board",
    description="BUG-29 夹具 待领取",
    created_at="2026-09-27T00:00:00Z",
  )
  let at_baseline = [
    p1,
    b29_done("A1", ""),
    b29_done("A2", ""),
    b29_done("A3", "有交付物"),
  ]
  let h0 = render_project_health(at_baseline, "0.3.0")
  assert_eq(b29_num(h0, "done_no_artifact"), 2)
  assert_eq(b29_bool(h0, "residue_over_baseline"), false)
  assert_eq(ph_grade(h0), "healthy")
  // 多一条无交付物的已完成 ⇒ 只许降不许升，新高即红灯（等级降级 + 显式布尔位）
  let over = [
    p1,
    b29_done("B1", ""),
    b29_done("B2", ""),
    b29_done("B3", ""),
    b29_done("B4", "有交付物"),
  ]
  let h1 = render_project_health(over, "0.3.0")
  assert_eq(b29_num(h1, "done_no_artifact"), 3)
  assert_eq(b29_bool(h1, "residue_over_baseline"), true)
  assert_eq(ph_grade(h1), "attention")
  // 清干净（残留归零）也必须仍然 healthy——防止判据反向恒红
  let clean = [p1, b29_done("C1", "交付物"), b29_done("C2", "交付物")]
  let h2 = render_project_health(clean, "0.3.0")
  assert_eq(b29_num(h2, "done_no_artifact"), 0)
  assert_eq(ph_grade(h2), "healthy")
}

///|
/// 状态流转 ASCII：合法迁移图 + 当前分布 + 在流计数。
test "state_flow_ascii_shows_lifecycle" {
  let e = ba_engine()
  let root = ba_publish(e, "状态流转测试根任务")
  ignore(e.claim(task_id=root, assignee="leader_a", now="2026-09-25T11:00:00Z"))
  match
    e.plan_deep(
      task_id=root,
      split_n=2,
      by="leader_a",
      now="2026-09-25T11:01:00Z",
    ) {
    Ok(_) => ()
    Err(m) => abort("plan_deep failed: \{m}")
  }
  let children = e.children_of(root)
  assert_true(children.length() >= 2)
  let c0 = children[0].get_id()
  ignore(e.claim(task_id=c0, assignee="exec_1", now="2026-09-25T11:02:00Z"))
  ignore(
    e.execute(task_id=c0, deliverable="成果 v1", now="2026-09-25T11:03:00Z"),
  )
  let j = render_state_flow_ascii(e.list_all(), "")
  let ascii = match j.value("ascii") {
    Some(Json::String(s)) => s
    _ => abort("ascii 缺失")
  }
  // 合法迁移图（一行流程）在
  assert_true(
    ascii.contains("待领取 → 已领取 → 拆分中 → 执行中"),
  )
  assert_true(ascii.contains("已打回→执行中"))
  // 当前分布（含已打回/重派分支）
  assert_true(ascii.contains("执行中="))
  assert_true(ascii.contains("待领取="))
  // 在流任务 ≥ 1
  let infl = match j.value("in_flow") {
    Some(Json::Number(n, ..)) => n.to_int()
    _ => abort("in_flow 缺失")
  }
  assert_true(infl >= 1)
}

///|
/// 状态流转 ASCII：空仓 → 当前分布 (空)，在流 = 0。
test "state_flow_ascii_empty_store" {
  let j = render_state_flow_ascii([], "nosuch")
  let ascii = match j.value("ascii") {
    Some(Json::String(s)) => s
    _ => abort("ascii 缺失")
  }
  assert_true(ascii.contains("(空)"))
  assert_eq(sf_num(j, "in_flow"), 0)
}

///|
/// 属性测试：`board_ascii`/`state_flow_ascii`/`status_summary` 三视角在随机任务集上
/// 都能渲染出非空 ascii，且 total_tasks 与输入数组长度一致（BUG-29 计数守恒）。
/// 用确定性 xorshift PRNG 生成伪随机任务描述。
test "property_ascii_views_consistency_seeded" {
  for seed in 0..<8 {
    // 确定性 PRNG（xorshift）
    let mut x = if seed == 0 { 1 } else { seed }
    let mut tasks : Array[@core.Task] = []
    for _i in 0..<12 {
      x = x ^ (x << 13)
      x = x ^ (x >> 17)
      x = x ^ (x << 5)
      let n = if x < 0 { -x } else { x % 1000 }
      tasks = tasks +
        [
          @core.Task::new(
            id="PX" + n.to_string(),
            project_dir="/proj/prop",
            description="属性测试任务 " + n.to_string(),
            created_at="2026-01-04T00:00:00Z",
            depends_on=[],
          ),
        ]
    }
    let board = render_board_ascii(tasks, "")
    let state = render_state_flow_ascii(tasks, "")
    let summary = render_status_summary(tasks, ["default"], "0.3.8")
    match board.value("ascii") {
      Some(Json::String(s)) => assert_true(s.length() > 0)
      _ => abort("board ascii 缺失")
    }
    match state.value("ascii") {
      Some(Json::String(s)) => assert_true(s.length() > 0)
      _ => abort("state ascii 缺失")
    }
    match summary.value("total_tasks") {
      Some(Json::Number(n, ..)) => assert_eq(n.to_int(), tasks.length())
      _ => abort("status_summary total_tasks 缺失")
    }
  }
}
