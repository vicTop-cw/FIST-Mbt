/// server/supervisor_tools_wbtest.mbt —— 超级管家工具白盒锁
///
/// 对应 docs/2026-10-12-fist-mbt-supervisor-tools-plan.md §5/§7。
/// 复用同包 project_standards_wbtest.mbt 的 ps_* 提取器；本文件新增 sup_* 辅助。
/// 引导闭环（inject/list/consume）经由包级 `engine` 与 `supervisor_guidance` 注册表；
/// kill/upsert/tree 走独立的 `FistEngine::new()`（内存后端，彼此隔离）。

///|
/// 新建一个隔离的内存引擎（kill/upsert/tree 用例专用）。
fn sup_engine() -> @engine.FistEngine {
  @engine.FistEngine::new()
}

///|
/// 从 Json 对象取布尔字段，兼容 Json::boolean / Json::True / Json::False 三种落盘形态。
fn jb(j : Json, key : String) -> Bool {
  match j {
    Json::Object(m) =>
      match m.get(key) {
        Some(Json::True) => true
        Some(Json::False) => false
        _ => false
      }
    _ => false
  }
}

///|
/// 取顶层 results 数组（upsert 回执）。
fn sup_results(r : Json) -> Array[Json] {
  match r.value("results") {
    Some(Json::Array(a)) => a
    _ => abort("upsert 回执缺少 results 数组")
  }
}

///|
/// 任一结果项的某字符串字段等于给定值。
fn sup_any_field(results : Array[Json], key : String, val : String) -> Bool {
  for it in results {
    if ps_str(it, key) == val {
      return true
    }
  }
  false
}

///|
/// 任一结果项的 error 字段包含给定子串。
fn sup_any_error_contains(results : Array[Json], sub : String) -> Bool {
  for it in results {
    if ps_str(it, "error").contains(sub) {
      return true
    }
  }
  false
}

///|
/// 取 kill 方案的总 verdict。
fn sup_verdict(j : Json) -> String {
  ps_str(j, "verdict")
}

///|
/// 取 kill 方案的 gates 数组。
fn sup_gates(j : Json) -> Array[Json] {
  match j {
    Json::Object(m) =>
      match m.get("gates") {
        Some(Json::Array(a)) => a
        _ => []
      }
    _ => []
  }
}

///|
/// 在 gates 数组里按名称取某门的 passed。
fn sup_gate_passed(gates : Array[Json], name : String) -> Bool {
  for g in gates {
    if ps_str(g, "gate") == name {
      return jb(g, "passed")
    }
  }
  false
}

///|
/// 构造一个「根(未领取) + 子(已领取,非终态)」场景，返回 (engine, root, child)。
fn sup_leaf_scenario() -> (@engine.FistEngine, String, String) {
  let e = sup_engine()
  let now = "2026-10-14T10:00:00Z"
  let root = match
    e.publish(
      project_dir="pd",
      description="kill-root",
      created_by="human_steward",
      now~,
    ) {
    Ok(id) => id
    Err(x) => abort("publish root 失败: \{x}")
  }
  ignore(
    match e.claim(task_id=root, assignee="agent_a", now~) {
      Ok(_) => ()
      Err(x) => abort("claim root 失败: \{x}")
    },
  )
  let kids = match e.plan(task_id=root, split_n=1, by="human_steward", now~) {
    Ok(ks) => ks
    Err(x) => abort("plan root 失败: \{x}")
  }
  let child = kids[0]
  (e, root, child)
}

///|
/// 把一个子任务从待领取驱动到「已归档」终态（archive 要求 [已完成]，
/// 而 plan 产出的 child 还是 [待领取]，必须先走完整生命周期）。
fn sup_drive_to_archived(
  e : @engine.FistEngine,
  child : String,
  now : String,
) -> Unit {
  ignore(
    match e.claim(task_id=child, assignee="agent_a", now~) {
      Ok(_) => ()
      Err(x) => abort("drive claim 失败: \{x}")
    },
  )
  ignore(
    match
      e.execute(task_id=child, deliverable="真实交付物: 已落地", now~) {
      Ok(_) => ()
      Err(x) => abort("drive execute 失败: \{x}")
    },
  )
  ignore(
    match e.submit(task_id=child, now~) {
      Ok(_) => ()
      Err(x) => abort("drive submit 失败: \{x}")
    },
  )
  ignore(
    match e.verify(task_id=child, verifier="human_steward", now~) {
      Ok(_) => ()
      Err(x) => abort("drive verify 失败: \{x}")
    },
  )
  ignore(
    match e.archive(task_id=child, by="human_steward", now~) {
      Ok(_) => ()
      Err(x) => abort("drive archive 失败: \{x}")
    },
  )
}

///|
/// 仅构造一个未领取的根任务（用于 G3 根保护判定）。
fn sup_root_only() -> (@engine.FistEngine, String) {
  let e = sup_engine()
  let now = "2026-10-14T10:00:00Z"
  let root = match
    e.publish(
      project_dir="pd",
      description="root-only",
      created_by="human_steward",
      now~,
    ) {
    Ok(id) => id
    Err(x) => abort("publish root 失败: \{x}")
  }
  (e, root)
}

///|
/// 引导闭环：inject → list(新在前/默认排除已消费) → consume(幂等) → list(include_consumed 开关)。
test "supervisor_guidance_inject_list_consume 闭环" {
  let target = "wbtest-guidance-closed-loop"
  let i1 = supervisor_guidance_inject(target~, prompt="p1", ns="default")
  let i2 = supervisor_guidance_inject(target~, prompt="p2", ns="default")
  let i3 = supervisor_guidance_inject(target~, prompt="p3", ns="default")
  ps_must(i1 != "" && i2 != "" && i3 != "", "inject 应返回非空 id")

  // 默认列表：仅该 target、排除已消费、新在前
  let lst = supervisor_guidance_list(target~, include_consumed=false)
  ps_must(
    lst.length() == 3,
    "未消费列表应为 3 条，实际 \{lst.length()}",
  )
  let ids = lst.map(fn(g) { g.id })
  ps_must(
    ids.contains(i1) && ids.contains(i2) && ids.contains(i3),
    "列表应包含全部 3 条注入的 id",
  )
  // 降序：首条 created_at >= 末条 created_at（秒级精度允许相等）
  ps_must(
    lst[0].created_at >= lst[lst.length() - 1].created_at,
    "列表应按 created_at 降序",
  )

  // consume 幂等：标记 consumed=true，重复取仍返回 Some
  match supervisor_guidance_consume(id=i2) {
    None => ps_must(false, "consume 应返回 Some")
    Some(g) => ps_must(g.consumed, "consume 后 consumed 应为 true")
  }
  match supervisor_guidance_consume(id=i2) {
    None => ps_must(false, "重复 consume 仍应返回 Some（幂等）")
    Some(g2) => ps_must(g2.consumed, "重复 consume 仍 consumed")
  }

  // include_consumed=false 排除已消费
  let lst2 = supervisor_guidance_list(target~, include_consumed=false)
  ps_must(
    lst2.length() == 2,
    "排除已消费后应剩 2 条，实际 \{lst2.length()}",
  )
  // include_consumed=true 含已消费
  let lst3 = supervisor_guidance_list(target~, include_consumed=true)
  ps_must(
    lst3.length() == 3,
    "包含已消费应为 3 条，实际 \{lst3.length()}",
  )
}

///|
/// kill 六门链：身份门(G1) / 根保护(G3) / 终态(G4) / force+reason 决定 allowed vs only_plan。
test "supervisor_kill_gates 六门链" {
  // —— G1 身份门失败：非 human_steward 且非现任主助理 → blocked ——
  let (e1, _, child1) = sup_leaf_scenario()
  let j1 = e1.supervisor_kill_plan(
    task_id=child1,
    by="random_agent_xyz",
    reason="",
    force=false,
  )
  ps_must(
    sup_verdict(j1) == "blocked",
    "随机 agent 应 blocked，实际 \{sup_verdict(j1)}",
  )
  ps_must(
    sup_gates(j1).length() == 5,
    "gates 应为 5 门，实际 \{sup_gates(j1).length()}",
  )
  ps_must(
    !sup_gate_passed(sup_gates(j1), "G1_identity"),
    "G1 对该 agent 应不通过",
  )

  // —— only_plan：human_steward 但无 reason 无 force → only_plan ——
  let (e2, _, child2) = sup_leaf_scenario()
  let j2 = e2.supervisor_kill_plan(
    task_id=child2,
    by="human_steward",
    reason="",
    force=false,
  )
  ps_must(
    sup_verdict(j2) == "only_plan",
    "无 reason 应 only_plan，实际 \{sup_verdict(j2)}",
  )
  ps_must(
    sup_gate_passed(sup_gates(j2), "G1_identity"),
    "G1 对 human_steward 应通过",
  )

  // —— allowed：human_steward + force + reason → allowed ——
  let (e3, _, child3) = sup_leaf_scenario()
  let j3 = e3.supervisor_kill_plan(
    task_id=child3,
    by="human_steward",
    reason="紧急止损",
    force=true,
  )
  ps_must(
    sup_verdict(j3) == "allowed",
    "force+reason 应 allowed，实际 \{sup_verdict(j3)}",
  )
  ps_must(sup_gate_passed(sup_gates(j3), "G5_force_reason"), "G5 应触发")

  // —— G3 根保护：未领取的根任务，force 也不绕过 → blocked ——
  let (e4, root4) = sup_root_only()
  let j4 = e4.supervisor_kill_plan(
    task_id=root4,
    by="human_steward",
    reason="想杀根",
    force=true,
  )
  ps_must(
    sup_verdict(j4) == "blocked",
    "根任务应 blocked(G3)，实际 \{sup_verdict(j4)}",
  )

  // —— G4 终态：归档后不可杀 → blocked ——
  let (e5, _, child5) = sup_leaf_scenario()
  sup_drive_to_archived(e5, child5, "2026-10-14T10:05:00Z")
  let j5 = e5.supervisor_kill_plan(
    task_id=child5,
    by="human_steward",
    reason="想杀终态",
    force=true,
  )
  ps_must(
    sup_verdict(j5) == "blocked",
    "终态任务应 blocked(G4)，实际 \{sup_verdict(j5)}",
  )
}

///|
/// supervisor_task_upsert 三条路径：created / updated / failed(缺失·非对象·终态拒改)。
test "supervisor_task_upsert 三路径" {
  let e = sup_engine()
  let now = "2026-10-14T10:00:00Z"
  let root = match
    e.publish(
      project_dir="pd",
      description="upsert-root",
      created_by="human_steward",
      now~,
    ) {
    Ok(id) => id
    Err(x) => abort("publish root 失败: \{x}")
  }
  ignore(
    match e.claim(task_id=root, assignee="agent_a", now~) {
      Ok(_) => ()
      Err(x) => abort("claim root 失败: \{x}")
    },
  )
  let kids = match e.plan(task_id=root, split_n=1, by="human_steward", now~) {
    Ok(ks) => ks
    Err(x) => abort("plan root 失败: \{x}")
  }
  let child = kids[0]

  // ① created：无 task_id → 走 publish 追加
  let r1 = e.supervisor_task_upsert(
    project_dir="pd",
    by="human_steward",
    [Json::object({ "description": Json::string("新任务") })],
    now~,
  )
  let res1 = sup_results(r1)
  ps_must(ps_num(r1, "total") == 1.0, "created 用例 total 应为 1")
  ps_must(
    sup_any_field(res1, "action", "created"),
    "无 task_id 应 action=created",
  )

  // ② updated：已有非终态任务 → action=updated
  let r2 = e.supervisor_task_upsert(
    project_dir="pd",
    by="human_steward",
    [
      Json::object({
        "task_id": Json::string(root),
        "description": Json::string("已更新描述"),
      }),
    ],
    now~,
  )
  let res2 = sup_results(r2)
  ps_must(
    sup_any_field(res2, "action", "updated"),
    "已有任务应 action=updated",
  )

  // ③ failed·缺失：task_id 不存在
  let r3 = e.supervisor_task_upsert(
    project_dir="pd",
    by="human_steward",
    [
      Json::object({
        "task_id": Json::string("nope-404"),
        "description": Json::string("x"),
      }),
    ],
    now~,
  )
  let res3 = sup_results(r3)
  ps_must(
    sup_any_error_contains(res3, "task not found"),
    "缺失 task_id 应报 task not found",
  )

  // ③ failed·非对象：item 不是 Json 对象
  let r4 = e.supervisor_task_upsert(
    project_dir="pd",
    by="human_steward",
    [Json::string("我不是对象")],
    now~,
  )
  let res4 = sup_results(r4)
  ps_must(
    sup_any_error_contains(res4, "item 不是对象或缺少 description"),
    "非对象 item 应报 item 不是对象",
  )

  // ③ failed·终态拒改：先驱动 child 到终态再尝试改
  sup_drive_to_archived(e, child, "2026-10-14T10:05:00Z")
  let r5 = e.supervisor_task_upsert(
    project_dir="pd",
    by="human_steward",
    [
      Json::object({
        "task_id": Json::string(child),
        "description": Json::string("想改终态"),
      }),
    ],
    now~,
  )
  let res5 = sup_results(r5)
  ps_must(sup_any_error_contains(res5, "终态任务"), "终态任务应拒改")

  // 顶层计数自洽：r1(created) ok_count=1
  ps_must(
    ps_num(r1, "ok_count") == 1.0,
    "created 用例 ok_count 应为 1，实际 \{ps_num(r1, "ok_count")}",
  )
}

///|
/// supervisor_task_tree 聚合正确性：root + 2 子 → subtree_total=3, subtree_done=0, 2 子。
test "supervisor_task_tree 聚合" {
  let e = sup_engine()
  let now = "2026-10-14T10:00:00Z"
  let root = match
    e.publish(
      project_dir="pd",
      description="tree-root",
      created_by="human_steward",
      now~,
    ) {
    Ok(id) => id
    Err(x) => abort("publish root 失败: \{x}")
  }
  ignore(
    match e.claim(task_id=root, assignee="agent_a", now~) {
      Ok(_) => ()
      Err(x) => abort("claim root 失败: \{x}")
    },
  )
  let kids = match e.plan(task_id=root, split_n=2, by="human_steward", now~) {
    Ok(ks) => ks
    Err(x) => abort("plan root 失败: \{x}")
  }
  ps_must(
    kids.length() == 2,
    "split_n=2 应生成 2 个子任务，实际 \{kids.length()}",
  )

  let tree = match e.supervisor_task_tree(root) {
    Ok(j) => j
    Err(x) => abort("supervisor_task_tree 失败: \{x}")
  }
  // tree = {root_id, tree(node)}
  let node = match tree {
    Json::Object(m) =>
      match m.get("tree") {
        Some(n) => n
        _ => abort("tree 缺少 tree 节点")
      }
    _ => abort("tree 不是对象")
  }
  ps_must(
    ps_num(node, "subtree_total") == 3.0,
    "subtree_total 应为 3，实际 \{ps_num(node, "subtree_total")}",
  )
  ps_must(
    ps_num(node, "subtree_done") == 0.0,
    "subtree_done 应为 0，实际 \{ps_num(node, "subtree_done")}",
  )
  let children = match node {
    Json::Object(m) =>
      match m.get("children") {
        Some(Json::Array(a)) => a
        _ => abort("节点缺少 children 数组")
      }
    _ => abort("node 不是对象")
  }
  ps_must(
    children.length() == 2,
    "root 应有 2 个子节点，实际 \{children.length()}",
  )

  // 不存在的任务返回 Err
  match e.supervisor_task_tree("ghost-task") {
    Ok(_) => ps_must(false, "不存在任务应返回 Err")
    Err(_) => ()
  }
}

///|
/// R114 跨库折叠：total/计数累加、by_namespace 按**物理库**计数，
/// progress 由「已完成+已归档 / 合并 total」重算——各库百分比取平均会把
/// 「一库做完、三库没动」报成「做了一半」（100% 与 0% 平均 = 50%，正确是 25%）。
test "supervisor_status_fold 跨库合并" {
  let a = Json::object({
    "total": Json::number(1.0),
    "by_status": Json::object({ "已完成": Json::number(1.0) }),
    "by_namespace": Json::object({ "ghostA": Json::number(1.0) }),
    "progress_pct": Json::number(100.0),
    "active_count": Json::number(0.0),
    "active": Json::array([]),
  })
  let b = Json::object({
    "total": Json::number(3.0),
    "by_status": Json::object({ "待领取": Json::number(3.0) }),
    "by_namespace": Json::object({ "ghostB": Json::number(3.0) }),
    "progress_pct": Json::number(0.0),
    "active_count": Json::number(1.0),
    "active": Json::array([Json::object({ "id": Json::string("T0") })]),
  })
  let m = supervisor_status_fold([("ghostA", a), ("ghostB", b)])
  ps_must(
    ps_num(m, "total") == 4.0,
    "合并 total 应为 4，实际 \{ps_num(m, "total")}",
  )
  ps_must(
    ps_num(m, "progress_pct") == 25.0,
    "progress 应由计数重算为 25，不能取两库均值，实际 \{ps_num(m, "progress_pct")}",
  )
  let bs = json_field_obj(m, "by_status")
  ps_must(
    json_num_of(bs.get("已完成").unwrap_or(Json::null())) == 1.0 &&
    json_num_of(bs.get("待领取").unwrap_or(Json::null())) == 3.0,
    "by_status 应逐库累加",
  )
  let bn = json_field_obj(m, "by_namespace")
  ps_must(
    json_num_of(bn.get("ghostA").unwrap_or(Json::null())) == 1.0 &&
    json_num_of(bn.get("ghostB").unwrap_or(Json::null())) == 3.0,
    "by_namespace 应按物理库计数（管家顺着这条读数才能把任务取回）",
  )
  let act = json_field_arr(m, "active")
  ps_must(act.length() == 1, "active 应拼接各库活跃项")
  ps_must(
    json_field_str(act[0], "namespace") == "ghostB",
    "active 每条要盖来源库，实际 \{json_field_str(act[0], "namespace")}",
  )
  ps_must(
    ps_num(m, "active_count") == 1.0,
    "active_count 应与拼接后的条数一致",
  )
  let z = supervisor_status_fold([])
  ps_must(
    ps_num(z, "total") == 0.0 && ps_num(z, "progress_pct") == 0.0,
    "空折叠必须报 0，不许凭空给百分比",
  )
}

///|
/// 追加键工具：只加不改语义、同名以管家算出的为准、非对象不得被塞键。
test "supervisor_stamp 追加与覆盖" {
  let s1 = supervisor_stamp(Json::object({ "a": Json::number(1.0) }), {
    "b": Json::string("x"),
  })
  ps_must(json_field_str(s1, "b") == "x", "extra 键必须落进去")
  ps_must(ps_num(s1, "a") == 1.0, "原键不得被改动")
  let s2 = supervisor_stamp(
    Json::object({ "namespace": Json::string("旧值") }),
    { "namespace": Json::string("ghostA") },
  )
  ps_must(
    json_field_str(s2, "namespace") == "ghostA",
    "同名键以寻址结果为准，不能留着上一次的库名",
  )
  let s3 = supervisor_stamp(Json::string("裸串"), { "k": Json::number(1.0) })
  ps_must(
    json_field_str(s3, "k") == "" && json_field_str(s3, "") == "",
    "非对象读数应原样返回，不崩也不塞键",
  )
}

///|
/// 提醒跨库拼接：条数取实条数（不采信各库自报的 reminder_count），阈值回显保留。
test "supervisor_reminder_fold 跨库拼接" {
  let p1 = Json::object({
    "ts": Json::string("2026-10-22T00:00:00Z"),
    "stale_hours": Json::number(24.0),
    "reminder_count": Json::number(9.0),
    "reminders": Json::array([Json::object({ "task_id": Json::string("T0") })]),
  })
  let p2 = Json::object({
    "ts": Json::string("2026-10-22T00:00:00Z"),
    "reminder_count": Json::number(1.0),
    "reminders": Json::array([
      Json::object({ "task_id": Json::string("T1") }),
      Json::object({ "task_id": Json::string("T2") }),
    ]),
  })
  let f = supervisor_reminder_fold([("ghostA", p1), ("ghostB", p2)])
  ps_must(
    ps_num(f, "reminder_count") == 3.0,
    "reminder_count 应为实条数 3（各库自报 9/1 不作数），实际 \{ps_num(f, "reminder_count")}",
  )
  let rs = json_field_arr(f, "reminders")
  ps_must(rs.length() == 3, "reminders 应逐库拼接")
  ps_must(
    json_field_str(rs[0], "namespace") == "ghostA" &&
    json_field_str(rs[2], "namespace") == "ghostB",
    "每条提醒要带来源库",
  )
  ps_must(
    json_field_str(f, "ts") == "2026-10-22T00:00:00Z",
    "ts 这类阈值回显要保留，调用方才知道基准时间",
  )
  ps_must(
    supervisor_reminder_fold([]).stringify() != "",
    "空折叠不得崩溃",
  )
}

///|
/// G2 判读只看 G2 那道门：别的门发红不能冒充「目标不存在」。
test "supervisor_kill_g2_missing 只看 G2" {
  let missing = Json::object({
    "gates": Json::array([
      Json::object({
        "gate": Json::string("G1_identity"),
        "passed": Json::boolean(true),
      }),
      Json::object({
        "gate": Json::string("G2_exists"),
        "passed": Json::boolean(false),
      }),
    ]),
  })
  let present = Json::object({
    "gates": Json::array([
      Json::object({
        "gate": Json::string("G2_exists"),
        "passed": Json::boolean(true),
      }),
      Json::object({
        "gate": Json::string("G3_protected_planner"),
        "passed": Json::boolean(false),
      }),
    ]),
  })
  ps_must(supervisor_kill_g2_missing(missing), "G2 发红应判为未命中")
  ps_must(
    !supervisor_kill_g2_missing(present),
    "G3 拦下不等于目标不存在，不该挂 ns_hint",
  )
  ps_must(
    !supervisor_kill_g2_missing(Json::number(1.0)),
    "非对象读数不得被判成未命中",
  )
}

///|
/// 撞号点名：歧义文案只列真正命中的库，空候选必须显式说「无」而非空串。
test "supervisor_ambiguous_msg 点名命中的每个库" {
  let hits : Array[(String, @engine.FistEngine)] = [
    ("ghostA", sup_engine()),
    ("ghostB", sup_engine()),
  ]
  let msg = supervisor_ambiguous_msg("T0", hits)
  ps_must(
    msg.contains("ghostA") && msg.contains("ghostB"),
    "命中的每个库都要点名，实际 \{msg}",
  )
  ps_must(!msg.contains("default"), "没命中的库不许出现在点名里")
  ps_must(
    msg.contains("namespace"),
    "要给出出路：点名 namespace 重试",
  )
  ps_must(
    supervisor_scanned_names([]) == "（无）",
    "空候选范围要显式报「无」，空串会被读成「没搜」而不是「没搜到」",
  )
}
