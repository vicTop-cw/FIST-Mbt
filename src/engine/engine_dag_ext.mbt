/// FIST-Mbt engine: DAG 扩展模块。
/// 提供：critical_path（最长依赖链）、parallelism（当前可并行度）、dag_ascii（ASCII 依赖图）。
/// 仅依赖既有 FistEngine 能力（list_all / get_task / deps_satisfied），不改原有行为。

/// ==================== 内部工具 ====================

/// 生成 n 层两空格缩进
fn dag_indent(n : Int) -> String {
  let mut s = ""
  for i = 0; i < n; i = i + 1 {
    s = s + "  "
  }
  s
}

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
