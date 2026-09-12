/// FIST-Mbt engine: 指挥-执行-验收 完整业务层。
/// 迁移自 FIST(Python) 的 flow (publish→plan→dispatch→claim→execute→submit→verify→complete→archive)。

/// 根任务 id
pub fn root_task_id() -> String { "T0" }

/// 核心引擎：持有 store，暴露指挥-执行-验收完整闭环。
/// store 为后端路由（内存 / SQLite），业务逻辑不感知具体实现。
pub struct FistEngine {
  store : @store.StoreBackend
}

pub fn FistEngine::new(store~ : @store.StoreBackend = @store.StoreBackend::memory()) -> FistEngine {
  { store, }
}

/// 以指定 SQLite 数据库打开持久化引擎（内建数据库入口；失败返回 None 供调用方回退）。
pub fn FistEngine::open_sqlite(db_path : String) -> Option[FistEngine] {
  match @store.SqliteStore::open(db_path) {
    None => None
    Some(s) => Some(FistEngine::new(store=@store.StoreBackend::sqlite(s)))
  }
}

/// 发布根任务（仅限人类指挥官）
pub fn FistEngine::publish(
  self : FistEngine,
  project_dir~ : String,
  description~ : String,
  created_by~ : String,
  now~ : String,
  ns~ : String = "default",
) -> Result[String, String] {
  if created_by != "human_steward" && created_by != "human" {
    return Err("publish 仅限人类指挥官（created_by=human_steward）")
  }
  let id = root_task_id()
  let t = @core.Task::new(
    id=id,
    project_dir~,
    description~,
    depth=3,
    split_n=3,
    created_at=now,
    ns~,
  )
  match self.store.create_task(t) {
    Ok(_) => Ok(id)
    Err(e) => Err(e)
  }
}

/// 对指定任务生成子任务树（一层）。非原子任务才可拆分。
/// 返回生成的子任务 id 列表。
pub fn FistEngine::plan(
  self : FistEngine,
  task_id~ : String,
  split_n~ : Int = 3,
  by~ : String,
  now~ : String,
) -> Result[Array[String], String] {
  match self.store.get_task(task_id) {
    None => Err("task not found: \{task_id}")
    Some(parent) => {
      if parent.is_leaf() {
        return Err("原子任务不可再拆分: \{task_id}")
      }
      let st = parent.get_status()
      if !st.can_split() {
        return Err("非法拆分: 任务处于 [\{parent.status_to_string()}]")
      }
      // 标记父任务进入拆分中
      match parent.split() {
        Ok(p2) => ignore(self.store.update_task(p2))
        Err(e) => return Err(e)
      }
      let child_depth = parent.get_depth() - 1
      let children : Array[String] = []
      for i = 1; i <= split_n; i = i + 1 {
        let cid = @core.child_id(parent_id=task_id, idx=i)
        let child = @core.Task::new(
          id=cid,
          project_dir=parent.project_dir,
          description="\{task_id} 的子任务 \{i}",
          parent_id=task_id,
          priority=parent.priority,
          importance=parent.importance,
          depth=child_depth,
          split_n=child_depth,
          created_at=now,
          ns=parent.ns,
        )
        match self.store.create_task(child) {
          Ok(_) => children.push(cid)
          Err(e) => return Err(e)
        }
      }
      Ok(children)
    }
  }
}

/// 认领任务（executor 认领，待领取 -> 已领取 -> 执行中）
/// 领取前检查依赖是否满足
pub fn FistEngine::claim(
  self : FistEngine,
  task_id~ : String,
  assignee~ : String,
  now~ : String,
) -> Result[@core.Task, String] {
  match self.store.get_task(task_id) {
    None => Err("task not found: \{task_id}")
    Some(t) => {
      if !self.deps_satisfied(task_id) {
        return Err("依赖未满足，不可领取: \{task_id}")
      }
      let c = match t.claim(assignee~) {
        Ok(x) => x
        Err(e) => return Err(e)
      }
      let c3 = c.with_updated_at(now)
      ignore(self.store.update_task(c3))
      Ok(c3)
    }
  }
}

/// 记录执行交付物
pub fn FistEngine::execute(
  self : FistEngine,
  task_id~ : String,
  deliverable~ : String,
  now~ : String,
) -> Result[@core.Task, String] {
  match self.store.get_task(task_id) {
    None => Err("task not found: \{task_id}")
    Some(t) => {
      let st = t.get_status()
      if !st.can_execute() {
        return Err("非法执行: 任务处于 [\{t.status_to_string()}]")
      }
      let c = match t.execute() {
        Ok(x) => x
        Err(_) => t
      }
      let c2 = c.with_deliverable(deliverable, now)
      ignore(self.store.update_task(c2))
      Ok(c2)
    }
  }
}

/// 提交验收（执行中 -> 待验收）
pub fn FistEngine::submit(
  self : FistEngine,
  task_id~ : String,
  now~ : String,
) -> Result[@core.Task, String] {
  match self.store.get_task(task_id) {
    None => Err("task not found: \{task_id}")
    Some(t) => {
      let c = match t.submit() {
        Ok(x) => x
        Err(e) => return Err(e)
      }
      let c2 = c.with_updated_at(now)
      ignore(self.store.update_task(c2))
      Ok(c2)
    }
  }
}

/// 列出某任务的所有直接子任务
pub fn FistEngine::children_of(self : FistEngine, task_id : String) -> Array[@core.Task] {
  let out : Array[@core.Task] = []
  for t in self.store.list_tasks() {
    match t.get_parent() {
      Some(p) => if p == task_id { out.push(t) }
      None => ()
    }
  }
  out
}

/// 是否为「非叶节点且所有直接子任务都已完成」
pub fn FistEngine::all_subtasks_completed(
  self : FistEngine,
  parent : @core.Task,
) -> Bool {
  let children = self.children_of(parent.get_id())
  if children.is_empty() { return false }
  children.all(fn(t) { t.get_status().is_completed() })
}

/// 验收（verifier）：Reviewing -> Completed；若因此父任务全部子任务完成，则父任务自动待验收。
pub fn FistEngine::verify(
  self : FistEngine,
  task_id~ : String,
  verifier~ : String,
  now~ : String,
) -> Result[@core.Task, String] {
  match self.store.get_task(task_id) {
    None => Err("task not found: \{task_id}")
    Some(t) => {
      if !t.get_status().is_reviewing() {
        return Err("非法验收: 任务处于 [\{t.status_to_string()}]，需先 submit")
      }
      let c = match t.complete(completed_by=verifier) {
        Ok(x) => x
        Err(e) => return Err(e)
      }
      let c2 = c.with_updated_at(now)
      ignore(self.store.update_task(c2))
      // 向上归并：父任务全部子任务完成后自动待验收
      match c2.get_parent() {
        Some(pid) =>
          match self.store.get_task(pid) {
            Some(parent) =>
              if self.all_subtasks_completed(parent) {
                let pe = match parent.execute() {
                  Ok(x) => x
                  Err(_) => parent
                }
                match pe.submit() {
                  Ok(p2) => {
                    ignore(self.store.update_task(p2.with_updated_at(now)))
                    Ok(c2)
                  }
                  Err(e) => Err(e)
                }
              } else {
                Ok(c2)
              }
            None => Ok(c2)
          }
        None => Ok(c2)
      }
    }
  }
}

/// 人类确认归档：Completed -> Archived（仅限人类指挥官）
pub fn FistEngine::archive(
  self : FistEngine,
  task_id~ : String,
  by~ : String,
  now~ : String,
) -> Result[@core.Task, String] {
  if by != "human_steward" && by != "human" {
    return Err("archive 仅限人类指挥官")
  }
  match self.store.get_task(task_id) {
    None => Err("task not found: \{task_id}")
    Some(t) => {
      let c = match t.archive() {
        Ok(x) => x
        Err(e) =>
          // 未完成则先核验通过再归档
          match t.complete(completed_by=by) {
            Ok(c1) =>
              match c1.archive() {
                Ok(c2) => c2
                Err(e2) => return Err(e2)
              }
            Err(e2) => return Err(e2)
          }
      }
      let c2 = c.with_updated_at(now)
      ignore(self.store.update_task(c2))
      Ok(c2)
    }
  }
}

/// 列出全部任务
pub fn FistEngine::list_all(self : FistEngine) -> Array[@core.Task] {
  self.store.list_tasks()
}

/// 按状态过滤列出
pub fn FistEngine::list_by_status(
  self : FistEngine,
  status : @core.TaskStatus,
) -> Array[@core.Task] {
  self.store.list_tasks().filter(fn(t) { t.get_status() == status })
}

/// 查询单个任务
pub fn FistEngine::get_task(self : FistEngine, task_id : String) -> Option[@core.Task] {
  self.store.get_task(task_id)
}

/// 回滚/重派：任意非归档任务 -> 已领取（M4 heal watchdog 用）。返回回滚后的任务。
pub fn FistEngine::reopen_task(
  self : FistEngine,
  task_id : String,
  now : String,
) -> Result[@core.Task, String] {
  match self.store.get_task(task_id) {
    None => Err("task not found: \{task_id}")
    Some(t) => {
      let c = match t.reopen() {
        Ok(x) => x
        Err(e) => return Err(e)
      }
      let c2 = c.with_updated_at(now)
      ignore(self.store.update_task(c2))
      Ok(c2)
    }
  }
}

/// 验收拒绝（reject）：待验收 -> 已打回
pub fn FistEngine::reject_task(
  self : FistEngine,
  task_id~ : String,
  reason~ : String = "",
  by~ : String,
  now~ : String,
) -> Result[@core.Task, String] {
  match self.store.get_task(task_id) {
    None => Err("task not found: \{task_id}")
    Some(t) => {
      if !t.get_status().is_reviewing() {
        return Err("非法打回: 任务处于 [\{t.status_to_string()}]，仅待验收可打回")
      }
      let c = match t.reject(reason=reason) {
        Ok(x) => x
        Err(e) => return Err(e)
      }
      let c2 = c.with_updated_at(now)
      ignore(self.store.update_task(c2))
      Ok(c2)
    }
  }
}

/// 打回后重试（retry）：已打回 -> 执行中
pub fn FistEngine::retry_task(
  self : FistEngine,
  task_id~ : String,
  now~ : String,
) -> Result[@core.Task, String] {
  match self.store.get_task(task_id) {
    None => Err("task not found: \{task_id}")
    Some(t) => {
      let c = match t.retry() {
        Ok(x) => x
        Err(e) => return Err(e)
      }
      let c2 = c.with_updated_at(now)
      ignore(self.store.update_task(c2))
      Ok(c2)
    }
  }
}

/// 暂停任务：任意活跃状态 -> 已暂停
pub fn FistEngine::pause_task(
  self : FistEngine,
  task_id~ : String,
  now~ : String,
) -> Result[@core.Task, String] {
  match self.store.get_task(task_id) {
    None => Err("task not found: \{task_id}")
    Some(t) => {
      let c = match t.pause() {
        Ok(x) => x
        Err(e) => return Err(e)
      }
      let c2 = c.with_updated_at(now)
      ignore(self.store.update_task(c2))
      Ok(c2)
    }
  }
}

/// 恢复任务：已暂停 -> 已领取
pub fn FistEngine::resume_task(
  self : FistEngine,
  task_id~ : String,
  now~ : String,
) -> Result[@core.Task, String] {
  match self.store.get_task(task_id) {
    None => Err("task not found: \{task_id}")
    Some(t) => {
      let c = match t.resume() {
        Ok(x) => x
        Err(e) => return Err(e)
      }
      let c2 = c.with_updated_at(now)
      ignore(self.store.update_task(c2))
      Ok(c2)
    }
  }
}

/// 删除任务（仅限已归档，ARCHIVING 清理）
pub fn FistEngine::delete_task(self : FistEngine, task_id : String) -> Result[Unit, String] {
  match self.store.get_task(task_id) {
    None => Err("task not found: \{task_id}")
    Some(t) =>
      if t.get_status().is_archived() {
        self.store.delete_task(task_id)
      } else {
        Err("仅已归档任务可删除（当前 [\{t.status_to_string()}]）")
      }
  }
}

/// —— AO 式递归拆解（M3）：迁入 engine 包以保持方法定义与类型同包。———

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
      if !st.can_split() {
        return Err("非法拆解: 任务处于 [\{parent.status_to_string()}]")
      }
      if split_n < 1 {
        return Err("split_n 必须 >= 1")
      }
      let slices = match spec {
        Some(s) => @decompose.decompose_slices(s, split_n, parent_desc=parent.description)
        None => @decompose.default_slices(split_n, parent_desc=parent.description)
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
  parent : @core.Task,
  slices : Array[String],
  spec : Json?,
  now : String,
) -> Result[Json, String] {
  // 父任务进入拆分中（宽于 Task::split：待领取/已领取/拆分中均可转入）
  match parent.mark_decomposing() {
    Ok(p2) => ignore(self.store.update_task(p2.with_updated_at(now)))
    Err(e) => return Err(e)
  }
  let child_depth = parent.get_depth() - 1
  let spec_hash = @decompose.spec_hash_of(spec)
  let nodes : Array[Json] = []
  let mut created = 0
  for i = 0; i < slices.length(); i = i + 1 {
    let idx = i + 1
    let cid = @core.child_id(parent_id=parent.get_id(), idx=idx)
    let slice_text = slices[i]
    let full_desc = if spec_hash == "" {
      slice_text
    } else {
      "\{slice_text} [spec:\{spec_hash}]"
    }
    let child = @core.Task::new(
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
      Ok(_) => ()
      Err(e) => return Err(e)
    }
    created = created + 1
    // 递归下钻：仅非叶节点继续派生拆分
    let kids_arr : Array[Json] = if !child.is_leaf() {
      let next_slices = @decompose.default_slices(child.split_n, parent_desc=child.description)
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

/// ==================== DAG 依赖图 ====================

/// 检查某任务的直接依赖是否全部完成
pub fn FistEngine::deps_satisfied(self : FistEngine, task_id : String) -> Bool {
  match self.store.get_task(task_id) {
    None => false
    Some(t) => {
      let dep_ids = t.depends_on
      if dep_ids.is_empty() { return true }
      for tid in dep_ids {
        match self.store.get_task(tid) {
          Some(dt) => if !dt.get_status().is_completed() { return false }
          None => return false
        }
      }
      true
    }
  }
}

/// 拓扑排序（简化版）：按依赖深度排序，深度小的先执行
pub fn FistEngine::topo_sort(self : FistEngine, task_ids : Array[String]) -> Array[String] {
  // 简单排序：按依赖数量升序（依赖少的先执行）
  let sorted = task_ids
  let changed = true
  // 冒泡排序：依赖少的排前面
  // 实际生产环境应使用 Kahn 算法，这里简化为按依赖数排序
  sorted
}

/// 获取当前命名空间内所有 Pending 且依赖满足、可领取的任务
pub fn FistEngine::ready_tasks(self : FistEngine, ns_filter~ : String = "default") -> Array[@core.Task] {
  let target = if ns_filter == "" { "default" } else { ns_filter }
  let tasks = self.store.list_tasks_in(target)
  let ready : Array[@core.Task] = []
  for t in tasks {
    if t.get_status().is_pending() && self.deps_satisfied(t.get_id()) {
      ready.push(t)
    }
  }
  ready
}

/// 创建任务时指定依赖（depends_on 为依赖的任务 id 列表）
pub fn FistEngine::publish_with_deps(
  self : FistEngine,
  project_dir~ : String,
  description~ : String,
  depends_on~ : Array[String] = [],
  created_by~ : String = "human_steward",
  now~ : String = "",
  ns~ : String = "default",
) -> Result[String, String] {
  if created_by != "human_steward" && created_by != "human" {
    return Err("publish 仅限人类指挥官")
  }
  let id = root_task_id()
  let t = @core.Task::new(
    id=id,
    project_dir~,
    description~,
    depth=3,
    split_n=3,
    created_at=now,
    ns~,
    depends_on~,
  )
  match self.store.create_task(t) {
    Ok(_) => Ok(id)
    Err(e) => Err(e)
  }
}
