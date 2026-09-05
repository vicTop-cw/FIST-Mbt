/// FIST-Mbt engine: 指挥-执行-验收 完整业务层。
/// 迁移自 FIST(Python) 的 flow (publish→plan→dispatch→claim→execute→submit→verify→complete→archive)。

/// 根任务 id
pub fn root_task_id() -> String { "T0" }

/// 核心引擎：持有 store，暴露指挥-执行-验收完整闭环。
pub struct FistEngine {
  store : MemoryStore
}

pub fn FistEngine::new(store~ : MemoryStore = MemoryStore::new()) -> FistEngine {
  { store, }
}

/// 发布根任务（仅限人类指挥官）
pub fn FistEngine::publish(
  self : FistEngine,
  project_dir~ : String,
  description~ : String,
  created_by~ : String,
  now~ : String,
) -> Result[String, String] {
  if created_by != "human_steward" && created_by != "human" {
    return Err("publish 仅限人类指挥官（created_by=human_steward）")
  }
  let id = root_task_id()
  let t = Task::new(
    id=id,
    project_dir~,
    description~,
    depth=3,
    split_n=3,
    created_at=now,
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
      if st != Claimed && st != Pending && st != Splitting {
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
        let cid = child_id(parent_id=task_id, idx=i)
        let child = Task::new(
          id=cid,
          project_dir=parent.project_dir,
          description="\{task_id} 的子任务 \{i}",
          parent_id=task_id,
          priority=parent.priority,
          importance=parent.importance,
          depth=child_depth,
          split_n=child_depth,
          created_at=now,
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
pub fn FistEngine::claim(
  self : FistEngine,
  task_id~ : String,
  assignee~ : String,
  now~ : String,
) -> Result[Task, String] {
  match self.store.get_task(task_id) {
    None => Err("task not found: \{task_id}")
    Some(t) => {
      let c = match t.claim(assignee~) {
        Ok(x) => x
        Err(e) => return Err(e)
      }
      // claim 后立即进入执行中（FIST：claim 即开始）
      let c2 = match c.execute() {
        Ok(x) => x
        Err(_) => c
      }
      let c3 = { ..c2, updated_at: now, }
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
) -> Result[Task, String] {
  match self.store.get_task(task_id) {
    None => Err("task not found: \{task_id}")
    Some(t) => {
      let st = t.get_status()
      if st != Executing && st != Splitting && st != Claimed {
        return Err("非法执行: 任务处于 [\{t.status_to_string()}]")
      }
      let c = match t.execute() {
        Ok(x) => x
        Err(_) => t
      }
      let c2 = { ..c, deliverable, updated_at: now, }
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
) -> Result[Task, String] {
  match self.store.get_task(task_id) {
    None => Err("task not found: \{task_id}")
    Some(t) => {
      let c = match t.submit() {
        Ok(x) => x
        Err(e) => return Err(e)
      }
      let c2 = { ..c, updated_at: now, }
      ignore(self.store.update_task(c2))
      Ok(c2)
    }
  }
}

/// 列出某任务的所有直接子任务
pub fn FistEngine::children_of(self : FistEngine, task_id : String) -> Array[Task] {
  let out : Array[Task] = []
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
  parent : Task,
) -> Bool {
  let children = self.children_of(parent.get_id())
  if children.is_empty() { return false }
  children.all(fn(t) { t.get_status() == Completed })
}

/// 验收（verifier）：Reviewing -> Completed；若因此父任务全部子任务完成，则父任务自动待验收。
pub fn FistEngine::verify(
  self : FistEngine,
  task_id~ : String,
  verifier~ : String,
  now~ : String,
) -> Result[Task, String] {
  match self.store.get_task(task_id) {
    None => Err("task not found: \{task_id}")
    Some(t) => {
      if t.get_status() != Reviewing {
        return Err("非法验收: 任务处于 [\{t.status_to_string()}]，需先 submit")
      }
      let c = match t.complete(completed_by=verifier) {
        Ok(x) => x
        Err(e) => return Err(e)
      }
      let c2 = { ..c, updated_at: now, }
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
                    ignore(self.store.update_task({ ..p2, updated_at: now, }))
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
) -> Result[Task, String] {
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
      let c2 = { ..c, updated_at: now, }
      ignore(self.store.update_task(c2))
      Ok(c2)
    }
  }
}

/// 列出全部任务
pub fn FistEngine::list_all(self : FistEngine) -> Array[Task] {
  self.store.list_tasks()
}

/// 按状态过滤列出
pub fn FistEngine::list_by_status(
  self : FistEngine,
  status : TaskStatus,
) -> Array[Task] {
  self.store.list_tasks().filter(fn(t) { t.get_status() == status })
}

/// 查询单个任务
pub fn FistEngine::get_task(self : FistEngine, task_id : String) -> Option[Task] {
  self.store.get_task(task_id)
}

/// 删除任务（仅限已归档，ARCHIVING 清理）
pub fn FistEngine::delete_task(self : FistEngine, task_id : String) -> Result[Unit, String] {
  match self.store.get_task(task_id) {
    None => Err("task not found: \{task_id}")
    Some(t) =>
      if t.get_status() == Archived {
        self.store.delete_task(task_id)
      } else {
        Err("仅已归档任务可删除（当前 [\{t.status_to_string()}]）")
      }
  }
}
