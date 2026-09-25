/// engine_dag_mc.mbt —— Monte Carlo 概率式完工预测（R94，Van Slyke 1963 蒸馏）。
///
/// PERT 家族确定性分析（dag_slack，R71）的概率式补充：对每个任务按难度档
/// （[难度梯度 X]）取三点三角分布时长，整网模拟 N 次，得完工时间分布
/// （min/mean/p50/p90/max）+ 按期概率 P(完工 ≤ deadline) + 关键度
/// （任务出现在"最长路径"的频率——谁最可能成为真实瓶颈，含近关键路径）。
/// 确定性可复现（seed + 每样本独立状态）；纯读无副作用。

///|
/// xorshift32 一步（返回 (新状态, [0, 2^31) 的整数)）。Int 为 64 位，用 32 位掩码
/// 保持 js/native 双 target 数值一致。
fn mc_xorshift(state : Int) -> (Int, Int) {
  let mut x = state
  x = (x ^ (x << 13)) & 0xffffffff
  x = (x ^ (x >> 17)) & 0xffffffff
  x = (x ^ (x << 5)) & 0xffffffff
  (x, x & 0x7fffffff)
}

///|
/// 牛顿法平方根（core 无 sqrt；20 次迭代足够收敛，同 R89 sqrt_approx 模式）。
fn mc_sqrt(x : Double) -> Double {
  if x <= 0.0 {
    return 0.0
  }
  let mut g = if x >= 1.0 { x } else { 1.0 }
  for _i = 0; _i < 20; _i = _i + 1 {
    g = (g + x / g) * 0.5
  }
  g
}

///|
/// 三角分布采样（a<m<b）：u∈[0,1) → 时长（向上取整）。返回 (新状态, 时长)。
fn mc_tri_sample(state : Int, a : Int, m : Int, b : Int) -> (Int, Int) {
  let (s2, v) = mc_xorshift(state)
  let denom = (b - a).to_double()
  let u = v.to_double() / 2147483648.0
  let dur = if u < (m - a).to_double() / denom {
    a.to_double() + mc_sqrt(u * denom * (m - a).to_double())
  } else {
    b.to_double() - mc_sqrt((1.0 - u) * denom * (b - m).to_double())
  }
  (s2, dur.ceil().to_int())
}

///|
/// 难度档 → 三点三角分布（易/中/难；缺省档按中）。
fn mc_durations(tier : String) -> (Int, Int, Int) {
  match tier {
    "易" => (2, 3, 5)
    "难" => (5, 8, 14)
    _ => (3, 5, 8)
  }
}

///|
/// 作用域任务集：root_task_id 为空 → 该 ns 全部任务；否则取其子树
/// （id==root 或 parent 链可达 root，传递闭包，天然环保护）。
fn FistEngine::mc_scope_tasks(
  self : FistEngine,
  ns : String,
  root_task_id : String,
) -> Array[@core.Task] {
  let all = self.list_in_ns(ns)
  if root_task_id == "" {
    return all
  }
  let scope : Map[String, Bool] = Map([])
  scope.set(root_task_id, true)
  let mut changed = true
  while changed {
    changed = false
    for t in all {
      let in_parent = match t.parent_id {
        Some(p) => scope.get(p).unwrap_or(false)
        None => false
      }
      if in_parent && not(scope.get(t.get_id()).unwrap_or(false)) {
        scope.set(t.get_id(), true)
        changed = true
      }
    }
  }
  all.filter(fn(t) { scope.get(t.get_id()).unwrap_or(false) })
}

///|
/// 单样本内：以 id 结尾的最长完成时间（沿 depends_on 回溯；memo 化 DFS，含环保护）。
/// dur 为该样本各任务时长。返回 finish(id) = max(finish(dep)) + dur(id)。
fn FistEngine::mc_finish(
  self : FistEngine,
  id : String,
  dur : Map[String, Int],
  memo : Map[String, Int],
  visiting : Map[String, Bool],
) -> Int {
  match memo.get(id) {
    Some(v) => return v
    None => ()
  }
  match visiting.get(id) {
    Some(_) => return dur.get(id).unwrap_or(0)
    None => ()
  }
  visiting.set(id, true)
  let own = dur.get(id).unwrap_or(0)
  let mut best = own
  match self.get_task(id) {
    Some(t) =>
      for d in t.depends_on {
        let f = self.mc_finish(d, dur, memo, visiting)
        if f + own > best {
          best = f + own
        }
      }
    None => ()
  }
  visiting.remove(id)
  memo.set(id, best)
  best
}

///|
/// Monte Carlo 概率式完工预测（R94，Van Slyke 1963 首倡 MCS 求网络完工分布）。
/// 对作用域内每个任务按难度档采样三角分布时长，整网模拟 samples 次，
/// 输出完工时间分布（min/mean/p50/p90/max）+ 按期概率 + 关键度排行。
/// deadline>0 时给出 P(完工 ≤ deadline)；seed 固定则结果可复现。
pub fn FistEngine::dag_mc(
  self : FistEngine,
  ns? : String = "default",
  root_task_id? : String = "",
  deadline? : Int = 0,
  samples? : Int = 1000,
  seed? : Int = 42,
) -> Json {
  let tasks = self.mc_scope_tasks(ns, root_task_id)
  if tasks.is_empty() {
    let im = Map::new()
    im.set("insufficient", Json::boolean(true))
    im.set(
      "note",
      Json::string(
        "作用域内无任务（ns / root_task_id 为空或不存在）——无法预测完工。",
      ),
    )
    return Json::object(im)
  }
  let n = if samples < 10 { 10 } else { samples }
  let makespans : Array[Int] = []
  let critical_hits : Map[String, Int] = Map([])
  for t in tasks {
    critical_hits.set(t.get_id(), 0)
  }
  for s = 0; s < n; s = s + 1 {
    let mut state = seed + s * 7919
    let dur : Map[String, Int] = Map([])
    for t in tasks {
      let tier = extract_difficulty(t.description)
      let (a, m, b) = mc_durations(tier)
      let (s2, d) = mc_tri_sample(state, a, m, b)
      state = s2
      dur.set(t.get_id(), d)
    }
    let memo : Map[String, Int] = Map([])
    let visiting : Map[String, Bool] = Map([])
    let mut ms = 0
    for t in tasks {
      let f = self.mc_finish(t.get_id(), dur, memo, visiting)
      if f > ms {
        ms = f
      }
    }
    makespans.push(ms)
    for t in tasks {
      let f = memo.get(t.get_id()).unwrap_or(0)
      if f == ms {
        critical_hits.set(
          t.get_id(),
          critical_hits.get(t.get_id()).unwrap_or(0) + 1,
        )
      }
    }
  }
  // 统计：排序取分位
  let sorted = makespans.copy()
  sorted.sort()
  let sum = makespans.fold_left(init=0, fn(acc, x) { acc + x })
  let mean = sum.to_double() / n.to_double()
  let p50 = sorted[(n - 1) / 2]
  let p90 = sorted[if n * 9 / 10 >= n { n - 1 } else { n * 9 / 10 }]
  let minv = sorted[0]
  let maxv = sorted[n - 1]
  // 按期概率
  let mut on_time = 0
  for ms in makespans {
    if deadline > 0 && ms <= deadline {
      on_time = on_time + 1
    }
  }
  let p_on_time = if deadline > 0 {
    on_time.to_double() / n.to_double()
  } else {
    0.0
  }
  // 关键度排行（top 10；手写选择排序降序，规避 tuple 比较器 API 差异）
  let crit_arr : Array[(String, Int)] = []
  for t in tasks {
    crit_arr.push((t.get_id(), critical_hits.get(t.get_id()).unwrap_or(0)))
  }
  for i = 0; i < crit_arr.length(); i = i + 1 {
    for j = i + 1; j < crit_arr.length(); j = j + 1 {
      if crit_arr[j].1 > crit_arr[i].1 {
        let tmp = crit_arr[i]
        crit_arr[i] = crit_arr[j]
        crit_arr[j] = tmp
      }
    }
  }
  let crit_json : Array[Json] = []
  let top = if crit_arr.length() > 10 { 10 } else { crit_arr.length() }
  for i = 0; i < top; i = i + 1 {
    let cm = Map::new()
    cm.set("task_id", Json::string(crit_arr[i].0))
    cm.set(
      "critical_freq",
      Json::number(crit_arr[i].1.to_double() / n.to_double()),
    )
    crit_json.push(Json::object(cm))
  }
  // 组装返回
  let mk = Map::new()
  mk.set("min", Json::number(minv.to_double()))
  mk.set("mean", Json::number(mean))
  mk.set("p50", Json::number(p50.to_double()))
  mk.set("p90", Json::number(p90.to_double()))
  mk.set("max", Json::number(maxv.to_double()))
  let sc = Map::new()
  sc.set("ns", Json::string(ns))
  sc.set("root_task_id", Json::string(root_task_id))
  sc.set("tasks", Json::number(tasks.length().to_double()))
  let m = Map::new()
  m.set("scope", Json::object(sc))
  m.set("samples", Json::number(n.to_double()))
  m.set("deadline", Json::number(deadline.to_double()))
  m.set("p_on_time", Json::number(p_on_time))
  m.set("makespan", Json::object(mk))
  m.set("criticality", Json::array(crit_json))
  m.set(
    "note",
    Json::string(
      "Van Slyke 1963 Monte Carlo PERT：整网模拟 N 次得完工分布（克服单关键路径/merge bias）；关键度=任务出现在最长路径的频率，含近关键路径。难度档→三点三角分布时长；seed 固定可复现。",
    ),
  )
  Json::object(m)
}
