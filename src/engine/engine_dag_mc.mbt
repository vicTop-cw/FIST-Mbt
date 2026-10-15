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
///
/// R12-R5 性能：`deps` 参数传入预计算的 `Map[String, Array[String]]`，
/// 避免在 5000 样本 × N 任务下每次递归都调用 `self.get_task(id)`（SqliteStore
/// 下是 DB 查询）。`mc_scope_tasks` 已把作用域任务载入内存，`depends_on`
/// 在该次调用内不变，故只构建一次。
fn FistEngine::mc_finish(
  self : FistEngine,
  id : String,
  dur : Map[String, Int],
  memo : Map[String, Int],
  visiting : Map[String, Bool],
  deps : Map[String, Array[String]],
) -> Int {
  match memo.get(id) {
    Some(v) => return v
    None => ()
  }
  match visiting.get(id) {
    // BUG-204：环命中返回 -1 哨兵（采样 dur 恒 >= 0，故 f + own <= own <= best，
    // 环路径不参与 max）——旧实现返回节点自身 dur，A→B→A 会让 A 被累加 2 次。
    // 不用 Int.MIN_VALUE：与 own 相加会溢出。
    Some(_) => return -1
    None => ()
  }
  visiting.set(id, true)
  let own = dur.get(id).unwrap_or(0)
  let mut best = own
  match deps.get(id) {
    Some(arr) =>
      for d in arr {
        let f = self.mc_finish(d, dur, memo, visiting, deps)
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
/// 从 id 起的最长链长度（含 own，**看后继**）：own + max over succ(id) of mc_suffix_from(succ)。
/// mc_finish 只算前驱，单独用它判「在最长路径上」会漏掉最长路径的**中间节点**
/// （BUG-203：线性链 A→B 只有 B 被判关键，A 明明在唯一最长路径上却 critical_freq=0）。
/// 关键度判据必须前向+后向相加减 own == makespan，故补这个后向 pass。
fn mc_suffix_from(
  id : String,
  dur : Map[String, Int],
  memo_suf : Map[String, Int],
  visiting : Map[String, Bool],
  succ : Map[String, Array[String]],
) -> Int {
  match memo_suf.get(id) {
    Some(v) => return v
    None => ()
  }
  match visiting.get(id) {
    // 环命中返回 -1 哨兵（与 mc_finish 的 BUG-204 同口径），环路径不参与 max。
    Some(_) => return -1
    None => ()
  }
  visiting.set(id, true)
  let own = dur.get(id).unwrap_or(0)
  let mut best = own
  match succ.get(id) {
    Some(arr) =>
      for s in arr {
        let f = mc_suffix_from(s, dur, memo_suf, visiting, succ)
        if f + own > best {
          best = f + own
        }
      }
    None => ()
  }
  visiting.remove(id)
  memo_suf.set(id, best)
  best
}

///|
/// Monte Carlo 概率式完工预测（R94，Van Slyke 1963 首倡 MCS 求网络完工分布）。
/// 对作用域内每个任务按难度档采样三角分布时长，整网模拟 samples 次，
/// 输出完工时间分布（min/mean/p50/p90/max）+ 按期概率 + 关键度排行。
/// deadline>0 时给出 P(完工 ≤ deadline)；seed 固定则结果可复现。
/// 空作用域返回 { insufficient:true, note }，无 p_on_time/makespan/criticality
/// （无法预测，不伪造——BUG-182 文档契约）。
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
  // BUG-24：只有下界钳制的 samples 会让单次 MCP 调用无限膨胀（实测 samples=200000
  // 阻塞 >100s，而客户端超时 30s ——调用方看到的是"无响应"而不是结果）。
  // 上界 5000 是按 p90 收敛够用 + 落在 30s 预算内定的；被钳制时如实回显，不假装跑满。
  let n_requested = if samples < 10 { 10 } else { samples }
  let mc_cap = 5000
  let n = if n_requested > mc_cap { mc_cap } else { n_requested }
  let makespans : Array[Int] = []
  let critical_hits : Map[String, Int] = Map([])
  for t in tasks {
    critical_hits.set(t.get_id(), 0)
  }
  // R12-R3 性能：`extract_difficulty` 与 `mc_durations` 与样本无关，提前算一次。
  // 旧代码把它放在 `for s` 内，导致 5000 样本 × N 任务的**重复难度解析**——
  // 每个任务每样本都做一遍正则/字符串扫描。预计算后每样本只做一次三角形采样。
  // 用 `(t.get_id(), a, m, b)` 三元组数组，避免 Map 的 String 哈希开销。
  let tier_cache : Array[(String, Int, Int, Int)] = []
  for t in tasks {
    let tier = extract_difficulty(t.description)
    let (a, m, b) = mc_durations(tier)
    tier_cache.push((t.get_id(), a, m, b))
  }
  // R12-R5 性能：把 depends_on 预计算成 `Map[String, Array[String]]`，样本循环外只建一次。
  // 旧代码在 `mc_finish` 递归里每次调 `self.get_task(id)`——SqliteStore 下是 DB 查询，
  // 5000 样本 × N 任务 = 最多 100 万次 DB 读。预计算后每样本零 DB 访问。
  let deps : Map[String, Array[String]] = Map([])
  for t in tasks {
    deps.set(t.get_id(), t.depends_on)
  }
  // BUG-203：后继关系由 deps 反解（t 是 d 的前驱 ⇔ d 是 t 的后继），供后向 pass 用。
  let succ : Map[String, Array[String]] = Map([])
  for t in tasks {
    succ.set(t.get_id(), [])
  }
  for (_tid, arr) in deps {
    for d in arr {
      let cur = succ.get(d).unwrap_or([])
      let ns = Array::make(cur.length() + 1, "")
      for i = 0; i < cur.length(); i = i + 1 {
        ns[i] = cur[i]
      }
      ns[cur.length()] = _tid
      succ.set(d, ns)
    }
  }
  for s = 0; s < n; s = s + 1 {
    let mut state = seed + s * 7919
    let dur : Map[String, Int] = Map([])
    for (tid, a, m, b) in tier_cache {
      let (s2, d) = mc_tri_sample(state, a, m, b)
      state = s2
      dur.set(tid, d)
    }
    let memo : Map[String, Int] = Map([])
    let visiting : Map[String, Bool] = Map([])
    let mut ms = 0
    for t in tasks {
      let f = self.mc_finish(t.get_id(), dur, memo, visiting, deps)
      if f > ms {
        ms = f
      }
    }
    makespans.push(ms)
    // BUG-203 判据：t 在最长路径上 ⇔ 前向 finish + 后向 suffix - own == makespan。
    // 只判 `finish == ms` 会漏掉最长路径的中间节点（前驱），把关键度系统性错报。
    let memo_suf : Map[String, Int] = Map([])
    let visiting_suf : Map[String, Bool] = Map([])
    for t in tasks {
      ignore(mc_suffix_from(t.get_id(), dur, memo_suf, visiting_suf, succ))
    }
    for t in tasks {
      let f = memo.get(t.get_id()).unwrap_or(0)
      let sf = memo_suf.get(t.get_id()).unwrap_or(0)
      let own = dur.get(t.get_id()).unwrap_or(0)
      if ms > 0 && f >= 0 && sf >= 0 && f + sf - own == ms {
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
  let sum = makespans.fold(init=0, fn(acc, x) { acc + x })
  // R1 bugfind（BUG-142 家族）：静态扫描发现 unprotected-division——`n` 虽经钳制 >=10，
  // 但判据要能被确定性地证明非零，不靠「调用点总是传入合法值」的约定。
  let n_safe = if n > 0 { n } else { 1 }
  let mean = sum.to_double() / n_safe.to_double()
  let idx50 = if n_safe - 1 < 0 { 0 } else { (n_safe - 1) / 2 }
  let idx90 = if n_safe * 9 / 10 >= n_safe {
    if n_safe - 1 < 0 {
      0
    } else {
      n_safe - 1
    }
  } else {
    n_safe * 9 / 10
  }
  let p50 = sorted[idx50]
  let p90 = sorted[idx90]
  let minv = if n_safe > 0 { sorted[0] } else { 0 }
  let maxv = if n_safe > 0 { sorted[n_safe - 1] } else { 0 }
  // 按期概率
  let mut on_time = 0
  for ms in makespans {
    if deadline > 0 && ms <= deadline {
      on_time = on_time + 1
    }
  }
  let p_on_time = if deadline > 0 && n_safe > 0 {
    on_time.to_double() / n_safe.to_double()
  } else {
    0.0
  }
  // 关键度排行（top 10；手写选择排序降序，规避 tuple 比较器 API 差异）
  let crit_arr : Array[(String, Int)] = []
  for t in tasks {
    crit_arr.push((t.get_id(), critical_hits.get(t.get_id()).unwrap_or(0)))
  }
  // R12-R9 性能：旧实现对**全量 N 个任务**做完整选择排序（O(N²)）。
  // 但下游只用 top 10（crit_json 只 push 前 10 名），所以只需**部分选择**：
  // 每轮只把当前最大值移到前段，k=top_k 次即止，O(k×N)。
  let top_k = if crit_arr.length() > 10 { 10 } else { crit_arr.length() }
  for i = 0; i < top_k; i = i + 1 {
    let mut best_idx = i
    for j = i + 1; j < crit_arr.length(); j = j + 1 {
      if crit_arr[j].1 > crit_arr[best_idx].1 {
        best_idx = j
      }
    }
    if best_idx != i {
      let tmp = crit_arr[i]
      crit_arr[i] = crit_arr[best_idx]
      crit_arr[best_idx] = tmp
    }
  }
  let crit_json : Array[Json] = []
  for i = 0; i < top_k; i = i + 1 {
    let cm = Map::new()
    cm.set("task_id", Json::string(crit_arr[i].0))
    cm.set(
      "critical_freq",
      Json::number(crit_arr[i].1.to_double() / n_safe.to_double()),
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
  // BUG-24：如实回显"要了多少 / 实际跑了多少 / 为什么"，调用方不用读源码就能知道被钳制
  m.set("samples_requested", Json::number(n_requested.to_double()))
  m.set("samples_capped", Json::boolean(n != n_requested))
  if n != n_requested {
    m.set(
      "cap_note",
      Json::string(
        "samples 被钳制到 \{n}（上限 5000）：本工具跑在 MCP 同步调用里，客户端超时 30s，" +
        "跑满 \{n_requested} 会让调用方只看到「无响应」。要多样本请分批换 seed 自行聚合。",
      ),
    )
  }
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
