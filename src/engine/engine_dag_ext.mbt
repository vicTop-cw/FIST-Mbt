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
fn dag_topo_order(self : FistEngine) -> (Array[String], Array[String]) {
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
  let mut ready_ids : Array[String] = ids.filter(fn(id) { indeg.get(id).unwrap_or(0) == 0 })
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
