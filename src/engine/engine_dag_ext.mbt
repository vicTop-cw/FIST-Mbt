/// FIST-Mbt engine: DAG 扩展模块。
/// 提供：critical_path（最长依赖链）、parallelism（当前可并行度）、dag_ascii（ASCII 依赖图）。
/// 仅依赖既有 FistEngine 能力（list_all / get_task / deps_satisfied），不改原有行为。

/// ==================== 内部工具 ====================

///|
/// 生成 n 层两空格缩进
fn dag_indent(n : Int) -> String {
  let mut s = ""
  for i = 0; i < n; i = i + 1 {
    s = s + "  "
  }
  s
}

///|
/// 用逗号拼接依赖 id 列表
fn dag_join_deps(deps : Array[String]) -> String {
  let mut s = ""
  for i = 0; i < deps.length(); i = i + 1 {
    if i > 0 {
      s = s + ","
    }
    s = s + deps[i]
  }
  s
}

/// ==================== 关键路径 ====================

///|
/// 求以 id 结尾的最长依赖链（沿 depends_on 边回溯；memo 化 DFS，含环保护）。
/// 返回序列按依赖先后排列（最底层依赖在前，id 自身在后）。
fn FistEngine::longest_chain_ending(
  self : FistEngine,
  id : String,
  memo : Map[String, Array[String]],
  visiting : Map[String, Bool],
) -> Array[String] {
  match memo.get(id) {
    Some(c) => return c
    None => ()
  }
  // 环保护：当前 DFS 路径上已出现过则直接返回自身，避免无限递归
  match visiting.get(id) {
    Some(_) => return [id]
    None => ()
  }
  visiting.set(id, true)
  let deps = match self.get_task(id) {
    Some(t) => t.depends_on
    None => []
  }
  let mut best : Array[String] = []
  for d in deps {
    let chain = self.longest_chain_ending(d, memo, visiting)
    if chain.length() > best.length() {
      best = chain
    }
  }
  visiting.remove(id)
  let out = best.copy()
  out.push(id)
  memo.set(id, out)
  out
}

///|
/// 关键路径：全图中按 depends_on 建图后的最长依赖链（任务 id 序列）。
/// 多条等长链取先遇到的一条；空仓库返回空数组。
pub fn FistEngine::critical_path(self : FistEngine) -> Array[String] {
  let memo : Map[String, Array[String]] = Map([])
  let visiting : Map[String, Bool] = Map([])
  let mut best : Array[String] = []
  for t in self.list_all() {
    let chain = self.longest_chain_ending(t.id, memo, visiting)
    if chain.length() > best.length() {
      best = chain
    }
  }
  best
}

/// ==================== 并行度 ====================

///|
/// 当前可并行执行的任务数：状态为待领取且依赖已满足的任务数。
pub fn FistEngine::parallelism(self : FistEngine) -> Int {
  let mut n = 0
  for t in self.list_all() {
    if t.get_status().is_pending() && self.deps_satisfied(t.get_id()) {
      n = n + 1
    }
  }
  n
}

/// ==================== ASCII 依赖图 ====================

///|
/// 计算任务在 DAG 中的层级（缩进深度）：
/// 取「parent_id 父链深度」与「depends_on 依赖链深度」的较大者。
/// 父/依赖不在本命名空间内则不计入；环保护下返回 0。
fn FistEngine::dag_level(
  self : FistEngine,
  id : String,
  members : Map[String, Bool],
  memo : Map[String, Int],
  visiting : Map[String, Bool],
) -> Int {
  match memo.get(id) {
    Some(l) => return l
    None => ()
  }
  match visiting.get(id) {
    Some(_) => return 0
    None => ()
  }
  visiting.set(id, true)
  let mut level = 0
  match self.get_task(id) {
    Some(t) => {
      // 子任务按 parent_id 归组：父任务存在则至少缩进一层
      match t.parent_id {
        Some(p) =>
          if members.contains(p) && p != id {
            let pl = self.dag_level(p, members, memo, visiting)
            if pl + 1 > level {
              level = pl + 1
            }
          }
        None => ()
      }
      // depends_on 同样加深层级（依赖必须先完成，视觉上位于上层）
      for d in t.depends_on {
        if d != id && members.contains(d) {
          let dl = self.dag_level(d, members, memo, visiting)
          if dl + 1 > level {
            level = dl + 1
          }
        }
      }
    }
    None => ()
  }
  visiting.remove(id)
  memo.set(id, level)
  level
}

///|
/// ASCII 树/缩进图：展示某命名空间下的任务依赖结构。
/// 层级由 parent_id（子任务归组）与 depends_on（依赖深度）共同决定，
/// 同层任务按 id 字典序稳定输出；跨命名空间的父/依赖不计入缩进。
/// 每行格式：<缩进><id> [<状态>]（有依赖时追加 " (依赖: a,b)"），行尾换行。
pub fn FistEngine::dag_ascii(self : FistEngine, ns~ : String) -> String {
  let target = if ns == "" { "default" } else { ns }
  let tasks = self.store.list_tasks_in(target)
  let members : Map[String, Bool] = Map([])
  for t in tasks {
    members.set(t.id, true)
  }
  let memo : Map[String, Int] = Map([])
  let visiting : Map[String, Bool] = Map([])
  let levels : Map[String, Int] = Map([])
  for t in tasks {
    levels.set(t.id, self.dag_level(t.id, members, memo, visiting))
  }
  let sorted = tasks.copy()
  sorted.sort_by(fn(a, b) {
    let la = match levels.get(a.id) {
      Some(l) => l
      None => 0
    }
    let lb = match levels.get(b.id) {
      Some(l) => l
      None => 0
    }
    if la != lb {
      la - lb
    } else {
      a.id.compare(b.id)
    }
  })
  let mut out = ""
  for t in sorted {
    let lvl = match levels.get(t.id) {
      Some(l) => l
      None => 0
    }
    let mut line = dag_indent(lvl) + t.id + " [" + t.status_to_string() + "]"
    if t.depends_on.length() > 0 {
      line = line + " (依赖: " + dag_join_deps(t.depends_on) + ")"
    }
    out = out + line + "\n"
  }
  out
}

///|
/// 显式给任务追加一条前置依赖（构建 DAG 依赖边，不只靠 plan_deep 隐式父子）。
/// 校验：task 与 dep 均存在、非同一任务、且不会形成直接自环；去重追加并落库。
/// 返回追加后的任务 JSON。失败返回 Err（含人语原因）。
pub fn FistEngine::dag_depend(
  self : FistEngine,
  task_id~ : String,
  dep_id~ : String,
  now~ : String,
) -> Result[@core.Task, String] {
  let task = match self.store.get_task(task_id) {
    None => return Err("task not found: \{task_id}")
    Some(t) => t
  }
  if dep_id == task_id {
    return Err("不能依赖自身: \{task_id}")
  }
  let _dep = match self.store.get_task(dep_id) {
    None => return Err("依赖任务 \{dep_id} 不存在")
    Some(d) => d
  }
  // 已存在则幂等返回现任务
  if task.depends_on.contains(dep_id) {
    return Ok(task)
  }
  let c = task.with_depends_on(dep_id, now)
  match self.store.update_task(c) {
    Ok(_) => Ok(c)
    Err(e) => Err("依赖落库失败: \{e}")
  }
}

/// ==================== 瓶颈与松弛分析（PERT/CPM，R71） ====================

///|
/// 拓扑序（依赖先于被依赖；带环保护——成环任务归入 cycle，不阻塞计算）。
fn FistEngine::dag_topo_order(
  self : FistEngine,
) -> (Array[String], Array[String]) {
  let ids : Array[String] = []
  for t in self.list_all() {
    ids.push(t.get_id())
  }
  let indeg : Map[String, Int] = Map([])
  let deps_of : Map[String, Array[String]] = Map([])
  for id in ids {
    indeg.set(id, 0)
    deps_of.set(id, [])
  }
  // 建前置→后继边：任务 t 依赖 d（d 是 t 的前置）→ 边 d→t；indeg[t]++（t 的前置数）
  for t in self.list_all() {
    for d in t.depends_on {
      deps_of.set(d, deps_of.get(d).unwrap_or([]) + [t.get_id()])
      let cur = indeg.get(t.get_id()).unwrap_or(0)
      indeg.set(t.get_id(), cur + 1)
    }
  }
  let order : Array[String] = []
  let mut ready_ids : Array[String] = ids.filter(fn(id) {
    indeg.get(id).unwrap_or(0) == 0
  })
  while ready_ids.length() > 0 {
    let cur = ready_ids[0]
    // 移除队首（保持顺序）
    let rest : Array[String] = []
    for i = 1; i < ready_ids.length(); i = i + 1 {
      rest.push(ready_ids[i])
    }
    ready_ids = rest
    order.push(cur)
    // cur 的后继（以 cur 为前置的任务）：前置完成 -> 后继入度-1
    for nxt in deps_of.get(cur).unwrap_or([]) {
      let nd = indeg.get(nxt).unwrap_or(0)
      indeg.set(nxt, nd - 1)
      if indeg.get(nxt).unwrap_or(0) == 0 {
        ready_ids = ready_ids + [nxt]
      }
    }
  }
  let cycle = ids.filter(fn(id) { indeg.get(id).unwrap_or(0) > 0 })
  (order, cycle)
}

///|
/// 瓶颈与松弛分析（PERT/CPM 硬核调度能力，R71）：对每个任务计算
///   earliest（依赖全部就绪的最早开始步数）、latest（不拖慢总工期的最晚开始步数）、
///   slack（latest-earliest；0=关键路径上，>0=可灵活并行安排）。
/// 返回 { critical:[关键路径任务id], slack_map:{id:{earliest,latest,slack}}, makespan, cycle:[成环任务] }。
/// ——"找出谁在关键路径上、谁有松弛可并行"，直接支撑排程优化（不是视图叠加）。
pub fn FistEngine::dag_slack_analysis(self : FistEngine) -> Json {
  let (order, cycle) = self.dag_topo_order()
  let ids : Array[String] = []
  for t in self.list_all() {
    ids.push(t.get_id())
  }
  // earliest: 前向——依赖全就绪的最早开始
  let earliest : Map[String, Int] = Map([])
  for id in ids {
    earliest.set(id, 0)
  }
  for id in order {
    match self.get_task(id) {
      Some(t) =>
        for d in t.depends_on {
          let de = earliest.get(d).unwrap_or(0)
          let ce = earliest.get(id).unwrap_or(0)
          if de + 1 > ce {
            earliest.set(id, de + 1)
          }
        }
      None => ()
    }
  }
  // makespan: 全图最长 earliest（总工期）
  let mut makespan = 0
  for id in ids {
    let e = earliest.get(id).unwrap_or(0)
    if e > makespan {
      makespan = e
    }
  }
  // latest: 反向——不拖慢总工期的最晚开始
  let latest : Map[String, Int] = Map([])
  for id in ids {
    latest.set(id, makespan)
  }
  let rev : Map[String, Array[String]] = Map([])
  for id in ids {
    rev.set(id, [])
  }
  for t in self.list_all() {
    for d in t.depends_on {
      rev.set(d, rev.get(d).unwrap_or([]) + [t.get_id()])
    }
  }
  for i = order.length() - 1; i >= 0; i = i - 1 {
    let id = order[i]
    let mut lt = makespan
    for nxt in rev.get(id).unwrap_or([]) {
      let ln = latest.get(nxt).unwrap_or(0)
      if ln - 1 < lt {
        lt = ln - 1
      }
    }
    if lt < 0 {
      lt = 0
    }
    latest.set(id, lt)
  }
  // slack = latest - earliest；0 → 关键路径
  let slack_map : Map[String, Json] = Map([])
  let critical : Array[String] = []
  for id in ids {
    let e = earliest.get(id).unwrap_or(0)
    let l = latest.get(id).unwrap_or(0)
    let slack = l - e
    if slack == 0 {
      critical.push(id)
    }
    slack_map.set(
      id,
      Json::object({
        "earliest": Json::number(e.to_double()),
        "latest": Json::number(l.to_double()),
        "slack": Json::number(slack.to_double()),
      }),
    )
  }
  critical.sort()
  Json::object({
    "makespan": Json::number(makespan.to_double()),
    "critical": Json::array(critical.map(fn(s) { Json::string(s) })),
    "slack_map": Json::object(slack_map),
    "cycle": Json::array(cycle.map(fn(s) { Json::string(s) })),
  })
}

/// ==================== 排程视图（R74，基于 slack 落成可执行排程） ====================

///|
/// 排程视图（R75 增强）：在 dag_slack_analysis 基础上把任务落成可执行排程——
/// 按 slack 分两层批：critical 批（slack=0，关键路径瓶颈，须串行盯紧）与
/// flexible 批（slack>0，可按最早开始排序并行的弹性任务），每批附 assignee 当前占用，
/// 并对 flexible 批中未认领任务给出「负载感知建议派单」（suggest：活跃负载最低的已注册执行者）。
/// 复用 dag_slack_analysis（不重复算图）。——"谁在瓶颈、谁可并行派单"一目了然，排程优化闭环。
pub fn FistEngine::dag_schedule(self : FistEngine) -> Json {
  let slack = self.dag_slack_analysis()
  let ids : Array[String] = []
  for t in self.list_all() {
    ids.push(t.get_id())
  }
  // 负载感知：统计各已注册执行者名下活跃（未完成未归档）任务数
  let reg_names : Array[String] = []
  for (name, _abl, _created) in self.executor_list() {
    reg_names.push(name)
  }
  let load : Map[String, Int] = Map([])
  for n in reg_names {
    load.set(n, 0)
  }
  for t in self.list_all() {
    match t.assignee {
      Some(a) =>
        if load.contains(a) {
          let done = t.get_status().is_completed() ||
            t.get_status().to_string() == "已归档"
          if not(done) {
            load.set(a, load.get(a).unwrap_or(0) + 1)
          }
        }
      None => ()
    }
  }
  // 从 slack.slack_map 取每个任务的 slack 与 earliest
  let critical_batch : Array[Json] = []
  let flexible_batch : Array[Json] = []
  for id in ids {
    let mut sl = -1
    let mut ea = -1
    match slack.value("slack_map") {
      Some(Object(sm)) =>
        match sm.get(id) {
          Some(Object(o)) => {
            sl = match o.get("slack") {
              Some(Number(n, ..)) => n.to_int()
              _ => -1
            }
            ea = match o.get("earliest") {
              Some(Number(n, ..)) => n.to_int()
              _ => -1
            }
          }
          _ => ()
        }
      _ => ()
    }
    let assignee = match self.get_task(id) {
      Some(t) =>
        match t.assignee {
          Some(a) => a
          None => ""
        }
      None => ""
    }
    let row = Json::object({
      "task_id": Json::string(id),
      "earliest": Json::number(ea.to_double()),
      "slack": Json::number(sl.to_double()),
      "assignee": Json::string(assignee),
    })
    if sl == 0 {
      critical_batch.push(row)
    } else if sl > 0 {
      flexible_batch.push(row)
    }
  }
  // 弹性批按最早开始排序（可并行窗口）
  flexible_batch.sort_by(fn(a : Json, b : Json) -> Int {
    let ae = match a.value("earliest") {
      Some(Number(n, ..)) => n
      _ => 0.0
    }
    let be = match b.value("earliest") {
      Some(Number(n, ..)) => n
      _ => 0.0
    }
    if ae < be {
      -1
    } else if ae > be {
      1
    } else {
      0
    }
  })
  // R75 负载感知：flexible 批中未认领任务建议派给活跃负载最低的已注册执行者
  let flexible_adv : Array[Json] = flexible_batch.map(fn(row) {
    let asg = match row.value("assignee") {
      Some(Json::String(s)) => s
      _ => ""
    }
    if asg != "" {
      return row
    }
    // 已注册执行者中选负载最低者（无注册则不建议）
    let mut best = ""
    let mut best_load = 2147483647
    for n in reg_names {
      let l = load.get(n).unwrap_or(0)
      if l < best_load {
        best_load = l
        best = n
      }
    }
    let m = match row {
      Object(o) => o
      _ => Map([])
    }
    m.set("suggest", Json::string(if best != "" { best } else { "" }))
    Json::object(m)
  })
  Json::object({
    "basis": Json::string("PERT/CPM slack（基于 dag_slack_analysis）"),
    "critical_batch": Json::array(critical_batch),
    "flexible_batch": Json::array(flexible_adv),
    "note": Json::string(
      "critical_batch=关键路径瓶颈(须串行盯紧)；flexible_batch=有松弛可按最早开始并行的任务，未认领项附 suggest=活跃负载最低的已注册执行者(R75 负载感知)",
    ),
  })
}

/// ==================== 成本路由（R77，STAR 式依赖图成本路由） ====================

///|
/// 依赖图成本路由（R77，STAR 蒸馏简化版）：在 dag_schedule 排程视图之上补「成本」维度——
/// 对 flexible（slack>0）批中未认领任务，按拓扑序贪心给出建议执行者：在「能力覆盖的
/// 已注册执行者」里选 执行成本 + 切换成本 之和最小者。
///   - 执行成本：难度档映射（易/中/难 → 1/2/3，复用 extract_difficulty 单一来源）；
///   - 能力约束：任务所需能力 = 描述命中的最长已注册能力标签（复用 auto_want），
///     未命中标签的执行者被排除（want 空则全命中）；
///   - 切换成本：任务依赖链上已路由执行者若与候选不同则 +1（STAR 的上下文切换税）；
///   - 成本相等时取活跃负载最低者（与 R75 一致）。
/// 纯计算、无副作用（只给建议不 claim）。——排程优化闭环最终形态：
/// critical_path→slack→schedule→suggest→cost_route。
pub fn FistEngine::dag_cost_route(self : FistEngine) -> Json {
  let slack = self.dag_slack_analysis()
  let (order, _cycle) = self.dag_topo_order()
  // 执行者注册表：候选顺序按注册顺序（executor_list 稳定）
  let reg_names : Array[String] = []
  let reg_abl : Map[String, Array[String]] = Map([])
  for (name, abl, _created) in self.executor_list() {
    reg_names.push(name)
    reg_abl.set(name, parse_abilities(abl))
  }
  let load = self.executor_loads(reg_names)
  // 已路由执行者记录（切换成本基准）：已认领任务先登记为固定占用
  let routed : Map[String, String] = Map([])
  for t in self.list_all() {
    match t.assignee {
      Some(a) => routed.set(t.get_id(), a)
      None => ()
    }
  }
  let rows : Array[Json] = []
  let mut total_cost = 0
  for id in order {
    // 只处理 slack>0（flexible）且未认领的任务
    let mut sl = -1
    match slack.value("slack_map") {
      Some(Object(sm)) =>
        match sm.get(id) {
          Some(Object(o)) =>
            match o.get("slack") {
              Some(Number(n, ..)) => sl = n.to_int()
              _ => ()
            }
          _ => ()
        }
      _ => ()
    }
    if sl <= 0 {
      continue
    }
    if routed.contains(id) {
      continue
    }
    let desc = match self.get_task(id) {
      Some(t) => t.description
      None => ""
    }
    if desc == "" {
      continue
    }
    // 任务所需能力：描述命中的最长已注册能力标签（无注册标签则空 = 全命中）
    let want = self.auto_want(desc)
    // 难度 → 执行成本（易/中/难 → 1/2/3，无难度标记按 1）
    let lab = triage_label_of(desc)
    let est = if lab == "难" { 3 } else if lab == "中" { 2 } else { 1 }
    // 依赖任务的执行者（切换成本基准）
    let deps_asg : Array[String] = []
    match self.get_task(id) {
      Some(t) =>
        for d in t.depends_on {
          match routed.get(d) {
            Some(a) => deps_asg.push(a)
            None => ()
          }
        }
      None => ()
    }
    // 候选执行者：能力覆盖 want（want 空 → 全部）；选 执行成本+切换成本 最小，相等取负载最低
    let mut best = ""
    let mut best_total = 2147483647
    let mut best_switch = 0
    for n in reg_names {
      let abl = reg_abl.get(n).unwrap_or([])
      if want != "" && not(abl.contains(want)) {
        continue
      }
      let sw = if deps_asg.length() > 0 && not(deps_asg.contains(n)) {
        1
      } else {
        0
      }
      let ttl = est + sw
      if ttl < best_total {
        best_total = ttl
        best = n
        best_switch = sw
      } else if ttl == best_total {
        let bl = load.get(best).unwrap_or(0)
        let nl = load.get(n).unwrap_or(0)
        if nl < bl {
          best = n
          best_switch = sw
        }
      }
    }
    if best == "" {
      continue
    }
    routed.set(id, best)
    total_cost = total_cost + best_total
    rows.push(
      Json::object({
        "task_id": Json::string(id),
        "assignee": Json::string(best),
        "est_cost": Json::number(est.to_double()),
        "switch_cost": Json::number(best_switch.to_double()),
        "total": Json::number(best_total.to_double()),
      }),
    )
  }
  Json::object({
    "basis": Json::string(
      "STAR 式依赖图成本路由：执行成本(难度档易/中/难→1/2/3)+切换税(依赖执行者不同则+1)，能力约束过滤，拓扑贪心",
    ),
    "cost_route": Json::array(rows),
    "total_est_cost": Json::number(total_cost.to_double()),
    "note": Json::string(
      "仅对 slack>0 未认领任务给出建议执行者(纯读不 claim)；无注册执行者或能力不匹配项跳过",
    ),
  })
}

/// ==================== 预算按依赖图阶段切分（R81，ZEBRA 水填充蒸馏简化版） ====================

///|
/// 预算按依赖图阶段切分（R81，ZEBRA 背包水填充蒸馏简化版）：给定总预算，
/// 按任务 DAG 阶段（slack 分析的 earliest 层级 0..makespan）切分——每阶段基础份额 =
/// 该阶段任务数 × 难度权重（难3/中2/易1，复用难度档单一来源；无难度标记按 1），
/// 总权重归一化后乘总预算（向下取整，余数补给最大权重阶段）。
/// 返回 { stages:[{level, tasks, difficulty_sum, share}], total_budget, makespan, note }。
/// ——"预算在依赖图上按阶段切分：瓶颈阶段(关键路径层)占额可见，超支先预警"，机制设计叙事。
pub fn FistEngine::budget_split_by_dag(self : FistEngine, budget : Int) -> Json {
  let slack = self.dag_slack_analysis()
  // 每任务 earliest 作为阶段
  let level_of : Map[String, Int] = Map([])
  match slack.value("slack_map") {
    Some(Object(sm)) =>
      for id in sm.keys() {
        match sm.get(id) {
          Some(Object(o)) =>
            match o.get("earliest") {
              Some(Number(n, ..)) => level_of.set(id, n.to_int())
              _ => ()
            }
          _ => ()
        }
      }
    _ => ()
  }
  // 阶段聚合：难度权重（难3/中2/易1，无难度 1）+ 任务数
  let stage_weight : Map[Int, Int] = Map([])
  let stage_count : Map[Int, Int] = Map([])
  for t in self.list_all() {
    let lv = level_of.get(t.get_id()).unwrap_or(0)
    let lab = triage_label_of(t.description)
    let w = if lab == "难" { 3 } else if lab == "中" { 2 } else { 1 }
    stage_weight.set(lv, stage_weight.get(lv).unwrap_or(0) + w)
    stage_count.set(lv, stage_count.get(lv).unwrap_or(0) + 1)
  }
  let mut total_w = 0
  let mut max_lv = 0
  let mut max_w = 0
  for lv in stage_weight.keys() {
    let w = stage_weight.get(lv).unwrap_or(0)
    total_w = total_w + w
    if w > max_w {
      max_w = w
      max_lv = lv
    }
  }
  // 归一化切分：向下取整，余数补给最大权重阶段
  let mut used = 0
  let shares : Map[Int, Int] = Map([])
  for lv in stage_weight.keys() {
    let w = stage_weight.get(lv).unwrap_or(0)
    let share = if total_w <= 0 { 0 } else { budget * w / total_w }
    shares.set(lv, share)
    used = used + share
  }
  if total_w > 0 && used < budget {
    let cur = shares.get(max_lv).unwrap_or(0)
    shares.set(max_lv, cur + (budget - used))
  }
  // 输出阶段行（按层级升序）
  let stages : Array[Json] = []
  let lvs : Array[Int] = stage_weight.keys().to_array()
  lvs.sort()
  for lv in lvs {
    stages.push(
      Json::object({
        "level": Json::number(lv.to_double()),
        "tasks": Json::number(stage_count.get(lv).unwrap_or(0).to_double()),
        "difficulty_sum": Json::number(
          stage_weight.get(lv).unwrap_or(0).to_double(),
        ),
        "share": Json::number(shares.get(lv).unwrap_or(0).to_double()),
      }),
    )
  }
  let mut makespan = 0
  match slack.value("makespan") {
    Some(Number(n, ..)) => makespan = n.to_int()
    _ => ()
  }
  Json::object({
    "stages": Json::array(stages),
    "total_budget": Json::number(budget.to_double()),
    "makespan": Json::number(makespan.to_double()),
    "note": Json::string(
      "阶段=slack 分析的 earliest 层级；份额=阶段难度权重占总量比例×总预算(余数补最大权重阶段)——瓶颈阶段占额可见，超支先预警",
    ),
  })
}
