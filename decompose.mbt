/// decompose.mbt —— AO orchestrator 式递归任务拆解器（M3：AO 式拆解）
///
/// 语义参考 agent-orchestrator（backend/internal/skillassets/using-ao/commands）：
///   1. orchestrator：持久规划 agent，把 plan 拆成 focused tasks
///      —— 映射为 FistEngine::plan_deep 递归拆解器；
///   2. project add：注册仓库 + 配置 worker/orchestrator rules
///      —— 联动：根任务 project_dir 落库，拆出的子任务继承 project_dir，
///         供执行者 claim / execute（即 AO spawn 派发 worker）；
///   3. spawn：派发 worker —— 拆出的子任务挂 parent_id/depth，由执行者 claim；
///   4. review：按 omega spec 验收 —— 每条拆解依据带 spec_hash
///         （取 spec.fingerprint 作验收基准，供后续 omega_verify 对照）。
///
/// 结构定位（拳长那套分层递归）：根任务 depth=K，每拆一层减 1，
/// is_leaf = depth<=1 即停止；任一层可被下一层拳长继续递归拆分。
/// 全过程写 StoreBackend（SQLite 内建数据库），重启后经 get_task 即可恢复完整子树
/// （M3 验收标准）。

/// 从 omega spec JSON 提取切割依据（slices）。
/// 规则：
///   - spec 为对象且 laws 为非空字符串数组 → 以 laws 为准（AO "break into focused
///     tasks"：每条 law 一个聚焦子任务，等价于把 plan 拆成可执行单元）；
///   - 否则 → 退化为按 split_n 生成通用拆解条目。
/// 返回切片描述数组。
pub fn decompose_slices(spec : Json, split_n : Int, parent_desc~ : String) -> Array[String] {
  match spec {
    Object(_) =>
      match spec.value("laws") {
        Some(Array(laws)) => {
          let out : Array[String] = []
          for l in laws {
            match l {
              String(s) if s.trim() != "" => out.push(s)
              _ => ()
            }
          }
          if out.is_empty() {
            default_slices(split_n, parent_desc=parent_desc)
          } else {
            out
          }
        }
        _ => default_slices(split_n, parent_desc=parent_desc)
      }
    _ => default_slices(split_n, parent_desc=parent_desc)
  }
}

/// 无 spec.laws 时的通用切分条目（描述逐层递进派生）。
fn default_slices(split_n : Int, parent_desc~ : String) -> Array[String] {
  let out : Array[String] = []
  for i = 1; i <= split_n; i = i + 1 {
    out.push("\{parent_desc} - 子任务单元 \{i}")
  }
  out
}

/// 取 spec 的 fingerprint 作为验收基准 spec_hash；无 spec / 无 fingerprint 为空串。
fn spec_hash_of(spec : Json?) -> String {
  match spec {
    Some(s) =>
      match s.value("fingerprint") {
        Some(String(f)) => f
        _ => ""
      }
    None => ""
  }
}

/// 内部迁移：将父任务标记为拆分中。
/// AO 拳长可在任务未认领（待领取）时直接拆解，故宽于 Task::split（仅限已领取）；
/// 已完成/已归档等终态仍拒绝（由 plan_deep 前置校验拦截并给出可读错误）。
fn Task::mark_decomposing(self : Task) -> Result[Task, String] {
  match self.status {
    Pending | Claimed | Splitting => Ok({ ..self, status: Splitting })
    _ => Err("非法拆解: 任务处于 [\{self.status.to_string()}]")
  }
}

/// AO 式递归拆解入口：对指定任务拆出整棵子任务树并写库。
///
/// 入参：
///   task_id   要拆解的根/拳节任务 id（非原子任务才可拆）；
///   split_n   每层默认拆分数（无 spec.laws 时生效，默认 3）；
///   by        执行拆解的拳长身份（仅记录）；
///   spec      可选 omega spec JSON（laws 作切割依据，fingerprint 作验收基准）；
///   now       时间戳。
///
/// 返回：{ "root", "by", "created", "tree" }，tree 为多层子树结构；
/// 任一子节点非叶时将继续递归（depth 递减，is_leaf=depth<=1 停止）。
pub fn FistEngine::plan_deep(
  self : FistEngine,
  task_id~ : String,
  split_n~ : Int = 3,
  by~ : String,
  spec~ : Json? = None,
  now~ : String,
) -> Result[Json, String] {
  match self.store.get_task(task_id) {
    None => Err("task not found: \{task_id}")
    Some(parent) => {
      if parent.is_leaf() {
        return Err("原子任务不可再拆分: \{task_id}")
      }
      let st = parent.get_status()
      if st != Claimed && st != Pending && st != Splitting {
        return Err("非法拆解: 任务处于 [\{parent.status_to_string()}]")
      }
      if split_n < 1 {
        return Err("split_n 必须 >= 1")
      }
      let slices = match spec {
        Some(s) => decompose_slices(s, split_n, parent_desc=parent.description)
        None => default_slices(split_n, parent_desc=parent.description)
      }
      match self.decompose_rec(
        parent,
        slices,
        spec,
        now,
      ) {
        Err(e) => Err(e)
        Ok(tree) =>
          Ok(Json::object({
            "root": Json::string(task_id),
            "by": Json::string(by),
            "split_n": Json::number(split_n.to_double()),
            "tree": tree,
          }))
      }
    }
  }
}

/// 递归拆解单层并下钻（私有，同包可见）。
/// 返回该层子树 meta：{ "task_id", "created", "children": [...] }。
fn FistEngine::decompose_rec(
  self : FistEngine,
  parent : Task,
  slices : Array[String],
  spec : Json?,
  now : String,
) -> Result[Json, String] {
  // 父任务进入拆分中（宽于 Task::split：待领取/已领取/拆分中均可转入）
  match parent.mark_decomposing() {
    Ok(p2) => ignore(self.store.update_task({ ..p2, updated_at: now, }))
    Err(e) => return Err(e)
  }
  let child_depth = parent.get_depth() - 1
  let spec_hash = spec_hash_of(spec)
  let nodes : Array[Json] = []
  let mut created = 0
  for i = 0; i < slices.length(); i = i + 1 {
    let idx = i + 1
    let cid = child_id(parent_id=parent.get_id(), idx=idx)
    let slice_text = slices[i]
    let full_desc = if spec_hash == "" {
      slice_text
    } else {
      "\{slice_text} [spec:\{spec_hash}]"
    }
    let child = Task::new(
      id=cid,
      project_dir=parent.project_dir,
      description=full_desc,
      parent_id=parent.get_id(),
      priority=parent.priority,
      importance=parent.importance,
      depth=child_depth,
      split_n=if child_depth > 1 { child_depth } else { 1 },
      created_at=now,
    )
    match self.store.create_task(child) {
      Ok(_) => () // 已入 created 计数
      Err(e) => return Err(e)
    }
    created = created + 1
    // 递归下钻：仅非叶节点继续派生拆分（下一层用通用切分细化描述）
    let kids_arr : Array[Json] = if not(child.is_leaf()) {
      let next_slices = default_slices(child.split_n, parent_desc=child.description)
      match self.decompose_rec(child, next_slices, spec, now) {
        Ok(subtree) =>
          match subtree.value("children") {
            Some(Array(a)) => a
            _ => []
          }
        Err(e) => return Err(e)
      }
    } else {
      []
    }
    let node_m : Map[String, Json] = Map([
      ("id", Json::string(cid)),
      ("depth", Json::number(child_depth.to_double())),
      ("leaf", Json::boolean(child.is_leaf())),
      ("spec_hash", Json::string(spec_hash)),
      ("children", Json::array(kids_arr)),
    ])
    nodes.push(Json::object(node_m))
  }
  Ok(Json::object({
    "task_id": Json::string(parent.get_id()),
    "created": Json::number(created.to_double()),
    "children": Json::array(nodes),
  }))
}
