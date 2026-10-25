/// FIST-Mbt engine: 指挥-执行-验收 完整业务层。
/// 迁移自 FIST(Python) 的 flow (publish→plan→dispatch→claim→execute→submit→verify→complete→archive)。

///|
/// 根任务 id
pub fn root_task_id() -> String {
  "T0"
}

///|
/// 核心引擎：持有 store，暴露指挥-执行-验收完整闭环。
/// store 为后端路由（内存 / SQLite），业务逻辑不感知具体实现。
pub struct FistEngine {
  store : @store.StoreBackend
  registry : @executor.ExecutorRegistry
}

///|
pub fn FistEngine::new(
  store~ : @store.StoreBackend = @store.StoreBackend::memory(),
  registry~ : @executor.ExecutorRegistry = @executor.ExecutorRegistry::new(),
) -> FistEngine {
  { store, registry, }
}

///|
/// 以指定 SQLite 数据库打开持久化引擎（内建数据库入口；失败返回 None 供调用方回退）。
pub fn FistEngine::open_sqlite(db_path : String) -> FistEngine? {
  match @store.SqliteStore::open(db_path) {
    None => None
    Some(s) => Some(FistEngine::new(store=@store.StoreBackend::sqlite(s)))
  }
}

///|
/// 发布根任务（仅限人类指挥官）
pub fn FistEngine::publish(
  self : FistEngine,
  project_dir~ : String,
  description~ : String,
  created_by~ : String,
  now~ : String,
  ns~ : String = "default",
  level~ : Int32 = 6,
) -> Result[String, String] {
  if created_by != "human_steward" && created_by != "human" {
    return Err("publish 仅限人类指挥官（created_by=human_steward）")
  }
  // 根任务 id 全局唯一：T0 被占用时顺延 T0r2/T0r3（避免第二根主键冲突）
  let id = self.first_free_root_id()
  let t = @core.Task::new(
    id~,
    project_dir~,
    description~,
    depth=3,
    split_n=3,
    level~,
    created_at=now,
    ns~,
  )
  match self.store.create_task(t) {
    Ok(_) => Ok(id)
    Err(e) => Err(e)
  }
}

///|
/// `plan` 的第二道门（`Task::split` 只收 [已领取]）拒绝时的出路文案。
/// 第一道门 `can_split` 比它宽（待领取/已领取/拆分中/已打回都放行），所以
/// 待领取/拆分中/已打回三态都会走到这里；只报"要求状态"不报"怎么到达"，
/// 调用方就会照文案去 claim 一个已打回的任务（claim 只收待领取），永远走不出来。
fn split_remedy(task_id : String, st : @core.TaskStatus) -> String {
  if st.is_pending() {
    "先 claim(task_id=\{task_id}, assignee=...) 使任务进入 [已领取]，再 plan"
  } else if st.is_splitting() {
    "子树已存在：get(task_id=\{task_id}) 看已有子任务后直接领取叶子，需要更深层级用 task_plan_deep"
  } else if st.is_rejected() {
    "已打回不可直接拆：先 retry(task_id=\{task_id}) 回到活跃态，或由指挥官改描述后重新发布"
  } else {
    "get(task_id=\{task_id}) 查当前态，按生命周期 claim → plan 推进"
  }
}

///|
/// 对指定任务生成子任务树（一层）。非原子任务才可拆分。
/// 返回生成的子任务 id 列表。
///
/// **参数 `by`（BUG-354 出路 c）**：拆解者身份。本函数体内**不消费**它——任务面
/// 没有「谁拆解的」落点，审计面靠 `instrumented_tool` 的 `call_log` 记原始入参
/// （跨进程可查）。保留形参是为契约稳定（`plan` 是 pub 接口 + MCP 入参 schema
/// 的一部分，删它会收缩对外契约）。要真正消费需动 store schema（加历史字段），
/// 属行为变更，未在本轮做。
pub fn FistEngine::plan(
  self : FistEngine,
  task_id~ : String,
  split_n~ : Int32 = 3,
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
      if split_n < 1 {
        return Err("split_n 必须 >= 1")
      }
      // 标记父任务进入拆分中
      match parent.split() {
        Ok(p2) =>
          match self.store.update_task(p2) {
            Ok(_) => ()
            Err(e) => return Err("拆分状态落库失败: \{e}")
          }
        Err(e) => return Err(e + "。出路：" + split_remedy(task_id, st))
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
          // 军衔继承降一级：连长(6)→排长(7)→士兵（封顶 7）。军衔与 depth 严格分离。
          level=@core.child_level(parent.get_level()),
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

///|
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
      // ===== P0-2: Claim 硬门 — 军衔门 =====
      let task_level = t.get_level()
      let arank = estimate_rank(assignee)
      let arank_s = arank.to_string()
      let tlevel_s = task_level.to_string()
      let tname = level_to_rank(task_level)
      if !rank_can_claim(arank, task_level) {
        return Err(
          "RANK_GATE: assignee \{assignee} (rank=\{arank_s}) cannot claim task level=\{tlevel_s} (task_rank=\{tname}). 需要更高军衔或让 human_steward/leader 认领后分派。",
        )
      }
      // ===== End P0-2 Gate 1 =====

      // ===== P0-2 Gate 2: 能力门 — assignee abilities 覆盖任务 need =====
      // 从任务 description 抽 "需要:" / "need:" / "requires:" 关键词
      // 降级：assignee 未注册 abilities → 跳过 gate 不阻塞（零回归）
      let abs = self.registry.abilities_of(assignee)
      if abs.length() > 0 {
        let desc = t.get_description()
        let needs = extract_needs(desc)
        if needs.length() > 0 {
          let missing = needs.filter(fn(n : String) { !abs.contains(n) })
          if missing.length() > 0 {
            let missing_s = missing.join(", ")
            let abs_s = abs.join(", ")
            return Err(
              "ABILITY_GATE: assignee \{assignee} abilities (\{abs_s}) missing required: \{missing_s}. 任务需要能力标签不匹配。",
            )
          }
        }
      }
      // ===== End Gate 2 =====

      if !self.deps_satisfied(task_id) {
        return Err("依赖未满足，不可领取: \{task_id}")
      }
      let c = match t.claim(assignee~) {
        Ok(x) => x
        Err(e) => return Err(e)
      }
      let c3 = c.with_updated_at(now)
      match self.store.update_task_if_status(c3, "待领取") {
        Ok(_) => ()
        Err(e) => return Err("认领落库失败: \{e}")
      }
      Ok(c3)
    }
  }
}

///|
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
      // Omega 强验证开关（默认关闭）：开启时须先有「已通过」语料才可进入执行
      match self.omega_execute_gate(task_id) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      let st = t.get_status()
      if !st.can_execute() {
        // BUG-2：被拒时必须给"当前状态 → 可用出路"，否则调用方只能新建任务绕开旧账
        return Err(
          "非法执行: 任务处于 [\{t.status_to_string()}]。出路：\{@core.Task::execute_exit_hint(st)}",
        )
      }
      // 预执行审计门禁（P2 BACKLOG）：can_execute 通过后、execute 迁移前插入。
      // 拦「空交付物」（BUG-29 done_no_artifact 防线）。
      match self.audit_execute_gate(task_id, deliverable) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      let c = match t.execute() {
        Ok(x) => x
        Err(e) => return Err("执行失败: \{e}")
      }
      let c2 = c.with_deliverable(deliverable, now)
      match self.store.update_task(c2) {
        Ok(_) => ()
        Err(e) => return Err("执行落库失败: \{e}")
      }
      Ok(c2)
    }
  }
}

///|
/// 记录执行交付物 + 执行元数据（executor/model/tokens/cost/duration）。
/// 元数据写入 executions 表（供成本统计使用）；task 本身状态照常流转。
pub fn FistEngine::execute_with_meta(
  self : FistEngine,
  task_id~ : String,
  deliverable~ : String,
  now~ : String,
  executor~ : String = "manual",
  model~ : String = "",
  tokens_in~ : Int32 = 0,
  tokens_out~ : Int32 = 0,
  cost~ : Double = 0.0,
  duration_ms~ : Int32 = 0,
  rate_limited~ : Bool = false,
  failure_reason~ : String = "",
) -> Result[@core.Task, String] {
  // 0. 预执行审计门禁必须真正前置（BUG-176）：gate 在 record_execution 之前。
  // 否则空 deliverable 时 execute 的 gate 拒绝返回 Err，但 executions 已写入一行
  // 幽灵元数据，cost_stats 会 double-count。空交付物直接返回 Err，不落任何元数据。
  match self.audit_execute_gate(task_id, deliverable) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  // 1. 主任务状态流转（先执行，成功后才写元数据，避免幽灵记录）
  match self.execute(task_id~, deliverable~, now~) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  // 2. 写入执行元数据（execute 成功后才落盘，失败不阻塞主流程）
  ignore(
    self.store.record_execution(
      task_id~,
      executor~,
      model~,
      tokens_in~,
      tokens_out~,
      cost~,
      duration_ms~,
      rate_limited~,
      failure_reason~,
      created_at=now,
    ),
  )
  Ok(
    self.store
    .get_task(task_id)
    .unwrap_or(
      @core.Task::new(
        id=task_id,
        project_dir="",
        description="",
        created_at=now,
      ),
    ),
  )
}

///|
/// 成本聚合统计：委托给 store 后端（SQLite 从 executions 表聚合，内存返回零值）。
pub fn FistEngine::cost_stats(self : FistEngine) -> Json {
  self.store.cost_stats()
}

///|
/// 写入心跳记录（委托给 store 后端）。
pub fn FistEngine::store_write_heartbeat(
  self : FistEngine,
  agent_id~ : String,
  task_id~ : String,
  last_seen~ : String,
  status~ : String,
) -> Result[Unit, String] {
  self.store.write_heartbeat(agent_id~, task_id~, last_seen~, status~)
}

///|
/// 删除心跳记录（委托给 store 后端）。
pub fn FistEngine::store_delete_heartbeat(
  self : FistEngine,
  task_id~ : String,
) -> Result[Unit, String] {
  self.store.delete_heartbeat(task_id)
}

///|
/// 列出全部心跳记录（供启动时加载）。
pub fn FistEngine::store_list_heartbeats(
  self : FistEngine,
) -> Array[(String, String, String, String)] {
  self.store.list_all_heartbeats()
}

///|
/// 读单个任务的持久化心跳 last_seen（BUG-119：跨进程真相的唯一读取点；无记录返回空串）。
pub fn FistEngine::store_read_heartbeat_last_seen(
  self : FistEngine,
  task_id : String,
) -> String {
  let (_agent_id, last_seen, _status) = self.store.read_heartbeat(task_id)
  last_seen
}

///|
/// 心跳后端自述 `"sqlite"` / `"memory"`（BUG-119：落库与否必须让调用面看得见）。
pub fn FistEngine::heartbeat_backend(self : FistEngine) -> String {
  self.store.backend_name()
}

///|
/// 追加心跳间隔历史（R90，Phi Accrual 判活数据源；委托给 store 后端）。
pub fn FistEngine::store_write_heartbeat_interval(
  self : FistEngine,
  task_id~ : String,
  interval_sec~ : Int32,
  ts~ : String,
) -> Result[Unit, String] {
  self.store.write_heartbeat_interval(task_id~, interval_sec~, ts~)
}

///|
/// 读取心跳间隔历史（R90，时间序旧→新；委托给 store 后端）。
pub fn FistEngine::store_list_heartbeat_intervals(
  self : FistEngine,
  task_id : String,
) -> Array[Int32] {
  self.store.list_heartbeat_intervals(task_id)
}

///|
/// 注册 agent（进程级指纹身份；仅 SQLite 后端可用，内存后端 Err）。
/// agent_id 由调用方（server 层）以 fnv1a64 指纹计算，store 保持哈希无关。
pub fn FistEngine::agents_register(
  self : FistEngine,
  agent_id~ : String,
  agent_type~ : String,
  role~ : String,
  soldier~ : String,
  pubkey_fp~ : String,
  pid~ : Int32,
  now~ : String,
) -> Result[Unit, String] {
  match self.store.sqlite_store() {
    None => Err("agent registry 仅 SQLite 后端可用")
    Some(s) =>
      s.agents_register(
        agent_id~,
        agent_type~,
        role~,
        soldier~,
        pubkey_fp~,
        pid~,
        now~,
      )
  }
}

///|
/// 读单个 agent 的持久化身份（无记录 None；仅 SQLite 后端）。
pub fn FistEngine::agents_get(
  self : FistEngine,
  agent_id : String,
) -> @store.AgentRecord? {
  match self.store.sqlite_store() {
    None => None
    Some(s) => s.agents_get(agent_id)
  }
}

///|
/// 换绑进程实例（server 启动时调用；仅 SQLite 后端）。
pub fn FistEngine::agents_set_pid(
  self : FistEngine,
  agent_id~ : String,
  pid~ : Int32,
) -> Result[Unit, String] {
  match self.store.sqlite_store() {
    None => Err("agent registry 仅 SQLite 后端可用")
    Some(s) => s.agents_set_pid(agent_id~, pid~)
  }
}

///|
/// 确保默认 ACL（fail-closed 底线；仅 SQLite 后端）。
pub fn FistEngine::agents_acl_ensure(
  self : FistEngine,
  agent_id~ : String,
  ns~ : String,
  now~ : String,
) -> Result[Unit, String] {
  match self.store.sqlite_store() {
    None => Err("agent ACL 仅 SQLite 后端可用")
    Some(s) => s.agents_acl_ensure(agent_id~, ns~, now~)
  }
}

///|
/// ACL 检查（调用前先 ensure；仅 SQLite 后端）。
pub fn FistEngine::agents_acl_check(
  self : FistEngine,
  agent_id~ : String,
  ns~ : String,
  write~ : Bool,
  current_pid~ : Int32,
) -> Result[Unit, String] {
  match self.store.sqlite_store() {
    None => Err("agent ACL 仅 SQLite 后端可用")
    Some(s) => s.agents_acl_check(agent_id~, ns~, write~, current_pid~)
  }
}

///|
/// 授权/收权（仅 SQLite 后端）。
pub fn FistEngine::agents_acl_grant(
  self : FistEngine,
  agent_id~ : String,
  ns~ : String,
  can_read~ : Bool,
  can_write~ : Bool,
  pid_bound~ : Bool,
  now~ : String,
  by~ : String,
) -> Result[Unit, String] {
  match self.store.sqlite_store() {
    None => Err("agent ACL 仅 SQLite 后端可用")
    Some(s) =>
      s.agents_acl_grant(
        agent_id~,
        ns~,
        can_read~,
        can_write~,
        pid_bound~,
        now~,
        by~,
      )
  }
}

///|
/// 陈旧 agent 扫描（仅 SQLite 后端；内存后端返回空）。
pub fn FistEngine::agents_stale_check(
  self : FistEngine,
  cutoff : String,
) -> Array[@store.AgentRecord] {
  match self.store.sqlite_store() {
    None => []
    Some(s) => s.agents_stale_check(cutoff)
  }
}

///|
/// 登记 Saga 补偿步骤（R92，durable action log；委托给 store 后端）。
pub fn FistEngine::store_write_saga_action(
  self : FistEngine,
  ns~ : String = "default",
  root_task_id~ : String,
  step~ : String,
  task_id~ : String = "",
  compensation~ : String,
  created_at~ : String,
) -> Result[Unit, String] {
  self.store.write_saga_action(
    ns~,
    root_task_id~,
    step~,
    task_id~,
    compensation~,
    created_at~,
  )
}

///|
/// 列出某根任务的 Saga 补偿步骤（R92；前向顺序）。
pub fn FistEngine::store_list_saga_actions(
  self : FistEngine,
  ns : String,
  root_task_id : String,
) -> Array[(Int32, String, String, String, String)] {
  self.store.list_saga_actions(ns, root_task_id)
}

///|
/// 把指定 Saga 补偿步骤标记 done（R92；幂等）。
pub fn FistEngine::store_mark_saga_actions_done(
  self : FistEngine,
  ns~ : String = "default",
  root_task_id~ : String,
  ids~ : Array[Int32],
) -> Result[Unit, String] {
  self.store.mark_saga_actions_done(ns~, root_task_id~, ids~)
}

///|
/// 写入一条调用日志（委托给 store 后端；best-effort，调用方应忽略错误）。
pub fn FistEngine::store_write_call_log(
  self : FistEngine,
  ts~ : String,
  tool~ : String,
  caller~ : String,
  ns~ : String,
  params_json~ : String,
  result_json~ : String,
  ok~ : Bool,
  runtime_ms~ : Int32,
  seq~ : Int32,
) -> Result[Unit, String] {
  self.store.write_call_log(
    ts~,
    tool~,
    caller~,
    ns~,
    params_json~,
    result_json~,
    ok~,
    runtime_ms~,
    seq~,
  )
}

///|
/// 读取最近 N 条调用日志（委托给 store 后端，新的在前）。
pub fn FistEngine::store_recent_call_logs(
  self : FistEngine,
  limit~ : Int32 = 50,
) -> Array[Json] {
  self.store.recent_call_logs(limit~)
}

///|
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
      match self.store.update_task(c2) {
        Ok(_) => ()
        Err(e) => return Err("提交落库失败: \{e}")
      }
      Ok(c2)
    }
  }
}

///|
/// 列出某任务的所有直接子任务
pub fn FistEngine::children_of(
  self : FistEngine,
  task_id : String,
) -> Array[@core.Task] {
  let out : Array[@core.Task] = []
  for t in self.store.list_tasks() {
    match t.get_parent() {
      Some(p) => if p == task_id { out.push(t) }
      None => ()
    }
  }
  out
}

///|
/// R12-R8 性能：`children_of` 每查一个父任务都 `list_tasks()`（全库遍历），
/// 在 `subtree_ids`/`plan_exec_order` 这类"按子树递归遍历"里是 **O(N×M)**
/// （N=子树大小，M=全库任务数）——与 R7 的 `deps_satisfied` N×(1+D) 同款病灶。
/// 这里**一次 `list_tasks()` 建出 parent→children 索引**，之后每次查都是 O(1) Map。
/// 遍历型调用方（`subtree_ids` 等）先用它取索引，再在索引上递归。
/// pub 以便 `engine_dag_ext` / `server` 复用。
pub fn FistEngine::children_index(
  self : FistEngine,
) -> Map[String, Array[String]] {
  let idx : Map[String, Array[String]] = Map([])
  for t in self.store.list_tasks() {
    match t.get_parent() {
      Some(p) => {
        let cur = idx.get(p).unwrap_or([]).copy()
        cur.push(t.get_id())
        idx.set(p, cur)
      }
      None => ()
    }
  }
  idx
}

///|
/// 是否为「非叶节点且所有直接子任务都已完成」
pub fn FistEngine::all_subtasks_completed(
  self : FistEngine,
  parent : @core.Task,
) -> Bool {
  let children = self.children_of(parent.get_id())
  if children.is_empty() {
    return false
  }
  children.all(fn(t) { t.get_status().is_completed() })
}

///|
/// 验收（verifier）：Reviewing -> Completed；若因此父任务全部子任务完成，则父任务自动待验收。
pub fn FistEngine::verify(
  self : FistEngine,
  task_id~ : String,
  verifier~ : String,
  now~ : String,
  docs_check~ : Bool = false,
) -> Result[@core.Task, String] {
  match self.store.get_task(task_id) {
    None => Err("task not found: \{task_id}")
    Some(_t) => {
      // Omega 强验证开关（默认关闭）：开启时须先有「已通过」成果复验才可验收
      match self.omega_verify_gate(task_id) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      // 外部判据闸门（默认关闭）：[gate:required] 任务须有服务端真实执行过的、
      // 新鲜通过的 check 记录（run_check 落库），防"自写自测恒绿"
      match self.gate_verify_gate(task_id) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      // 「文档即实现」门禁（默认关闭）：仅 docs_check=true 时校验 README/CHANGELOG/reports
      // 存在性与交付物回传五段式；不达标返回 Err(明细) 打回。
      if docs_check {
        match self.docs_verify_gate(task_id) {
          Err(e) => return Err(e)
          Ok(_) => ()
        }
      }
      let t = match self.store.get_task(task_id) {
        Some(x) => x
        None => return Err("task not found: \{task_id}")
      }
      if !t.get_status().is_reviewing() {
        return Err(
          "非法验收: 任务处于 [\{t.status_to_string()}]，需先 submit",
        )
      }
      let c = match t.complete(completed_by=verifier) {
        Ok(x) => x
        Err(e) => return Err(e)
      }
      let c2 = c.with_updated_at(now)
      match self.store.update_task(c2) {
        Ok(_) => ()
        Err(e) => return Err("验收落库失败: \{e}")
      }
      // 向上归并：父任务全部子任务完成后自动待验收
      match c2.get_parent() {
        Some(pid) =>
          match self.store.get_task(pid) {
            Some(parent) =>
              if self.all_subtasks_completed(parent) {
                let original_status = parent.get_status().to_string()
                let pe = match parent.execute() {
                  Ok(x) => x
                  Err(_) => parent
                }
                // BUG-59：自动提升的父节点若交付物为空，Omega 成果复验门禁会把它锁死——
                // 「待验收」不许 execute，于是 verify 与 omega_result_verify 互相拒绝，
                // 唯一出路只剩人工 reject→retry。父节点的"成果"本就是子任务交付之合，
                // 所以提升时直接继承（有则不覆盖，零回归）。
                let pe = if pe.deliverable == "" {
                  let kids = self.children_of(pe.get_id())
                  let merged = if kids.is_empty() {
                    "（子任务均已完成，无文字交付物）"
                  } else {
                    kids
                    .map(fn(t) { "[\{t.get_id()}] \{t.deliverable}" })
                    .join("\n")
                  }
                  pe.with_deliverable(merged, now)
                } else {
                  pe
                }
                match pe.submit() {
                  Ok(p2) => {
                    match
                      self.store.update_task_if_status(
                        p2.with_updated_at(now),
                        original_status,
                      ) {
                      Ok(_) => ()
                      Err(e) => return Err("父任务归并落库失败: \{e}")
                    }
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

///|
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
      if !t.get_status().is_completed() {
        return Err(
          "仅已完成任务可归档，当前状态: \{t.status_to_string()}",
        )
      }
      // Omega 门（验收项：archive 不得绕过验收门）：强验证任务必须先过成果复验门，
      // 归档即"了账"，未通过 Omega 门就是假了账（纵深防御，与 archive_force 同门）。
      if omega_enabled(t) {
        match self.omega_verify_gate(task_id) {
          Err(e) => return Err("Omega 门禁拦截归档: \{e}")
          Ok(_) => ()
        }
      }
      let c = match t.archive() {
        Ok(x) => x
        Err(e) => return Err(e)
      }
      let c2 = c.with_updated_at(now)
      match self.store.update_task(c2) {
        Ok(_) => ()
        Err(e) => return Err("归档落库失败: \{e}")
      }
      Ok(c2)
    }
  }
}

///|
/// 列出全部任务
pub fn FistEngine::list_all(self : FistEngine) -> Array[@core.Task] {
  self.store.list_tasks()
}

///|
/// 按状态过滤列出
pub fn FistEngine::list_by_status(
  self : FistEngine,
  status : @core.TaskStatus,
) -> Array[@core.Task] {
  self.store.list_tasks().filter(fn(t) { t.get_status() == status })
}

///|
/// 查询单个任务
pub fn FistEngine::get_task(self : FistEngine, task_id : String) -> @core.Task? {
  self.store.get_task(task_id)
}

///|
/// 按命名空间列出任务（ns 为空串时回退默认命名空间）。
/// 供 watchdog 等运维编排按 ns 扫描使用。
pub fn FistEngine::list_in_ns(
  self : FistEngine,
  ns : String,
) -> Array[@core.Task] {
  let target = if ns == "" { "default" } else { ns }
  self.store.list_tasks_in(target)
}

///|
/// 自动续轮标记前缀：已完成但尚未续轮的根任务，其 deliverable 不带该前缀。
pub fn advance_mark_prefix() -> String {
  "__advanced__:"
}

///|
/// 生成下一轮根任务 id（T0 -> T0r2 -> T0r3 ...），保证与既有任务不冲突。
fn FistEngine::next_round_id(self : FistEngine) -> String {
  let base = root_task_id()
  let mut round = 1
  let mut candidate = "\{base}r\{round + 1}"
  let mut taken = true
  while taken {
    match self.store.get_task(candidate) {
      Some(_) => {
        round = round + 1
        // 探测上限：防止 id 空间被异常填满时无限循环（并发撞车由存储层唯一约束兜底）
        if round >= 100000 {
          return candidate
        }
        candidate = "\{base}r\{round + 1}"
      }
      None => taken = false
    }
  }
  candidate
}

///|
/// 生成全局第一个空闲的**根任务** id：T0 空闲则用 T0，否则顺延 T0r2、T0r3 ...
///
/// 与 next_round_id() 的区别：后者用于「已在推进的轮次」续接（T0 -> T0r2），
/// 永不返回 T0；本函数用于冷启动发布首任务，必须优先占用 T0，
/// 仅当 T0 已被别的命名空间占用时才顺延（多 namespace 共用同一 id 空间）。
fn FistEngine::first_free_root_id(self : FistEngine) -> String {
  let base = root_task_id()
  match self.store.get_task(base) {
    None => base
    Some(_) => self.next_round_id()
  }
}

///|
/// 自动续轮（仅供定时任务看门狗 watchdog_tick 调用，见 ops_watchdog.mbt）。
///
/// 语义：把已完成的上一轮**根任务**标记为已续轮并归档，同时发布下一轮根任务。
/// 安全边界（watchdog 计划文档第 0 节）：
///   - 仅允许作用于非 default 命名空间，避免干扰人工指挥流程；
///   - 上一轮必须是「已完成」的根任务。
///
/// 返回新根任务 id（T0r2、T0r3 ...）。
pub fn FistEngine::publish_next_round(
  self : FistEngine,
  ns~ : String,
  description~ : String,
  created_by~ : String,
  prev_task_id~ : String,
  now~ : String,
  level~ : Int32 = 6,
) -> Result[String, String] {
  if ns == "" || ns == "default" {
    return Err(
      "自动续轮仅限定时任务命名空间（namespace 不得为空或 default）",
    )
  }
  // 续轮发起者仅作审计用途（Task 无 created_by 字段），非法值不阻断。
  ignore(created_by)
  let prev = match self.store.get_task(prev_task_id) {
    None => return Err("task not found: \{prev_task_id}")
    Some(t) => t
  }
  if prev.ns != ns {
    return Err("上一轮任务不属于命名空间 [\{ns}]")
  }
  match prev.get_parent() {
    Some(_) => return Err("自动续轮仅针对根任务: \{prev_task_id}")
    None => ()
  }
  if !prev.get_status().is_completed() {
    return Err("上一轮任务尚未完成: [\{prev.status_to_string()}]")
  }
  let new_id = self.next_round_id()
  let next = @core.Task::new(
    id=new_id,
    project_dir=prev.project_dir,
    description~,
    depth=3,
    split_n=3,
    level~,
    created_at=now,
    ns~,
  )
  match self.store.create_task(next) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  // 标记旧根任务已续轮（保留原交付物信息），随后归档
  let marked = prev.with_deliverable(
    "\{advance_mark_prefix()}\{new_id} | \{prev.deliverable}",
    now,
  )
  match marked.archive() {
    Ok(a) =>
      match self.store.update_task(a.with_updated_at(now)) {
        Ok(_) => ()
        Err(e) => return Err("续轮归档落库失败: \{e}")
      }
    Err(e) => return Err(e)
  }
  Ok(new_id)
}

///|
/// 冷启动发布（无上一轮根任务时创建首个任务）。
/// 仅用于 cron-auto 等自动化命名空间，语义等同「人类指挥官发布首轮」
/// 但审计日志标记为 watchdog 自动发布。
///
/// **参数 `created_by`（BUG-354 出路 c）**：本函数体内**不消费**它——上面这句
/// 「审计日志标记为 watchdog 自动发布」是**设计意图**，当前实现并未把
/// `created_by` 写进任何审计字段（该语义只靠调用方自己传值，无落点）。保留形参
/// 理由同 `plan`：删它会收缩 pub 契约；要真正消费需在 store 层加标记字段。
///
/// 安全边界：
///   - 仅允许作用于非 default 命名空间；
///   - 该命名空间必须为空（已有任务时拒绝，避免重复发布）。
pub fn FistEngine::cold_publish(
  self : FistEngine,
  ns~ : String,
  description~ : String,
  created_by~ : String,
  project_dir~ : String,
  now~ : String,
  level~ : Int32 = 6,
) -> Result[String, String] {
  if ns == "" || ns == "default" {
    return Err(
      "冷启动发布仅限定时任务命名空间（namespace 不得为空或 default）",
    )
  }
  // 检查该 ns 是否已有任务，避免重复发布
  if !self.list_in_ns(ns).is_empty() {
    return Err(
      "命名空间已存在任务，请使用 publish_next_round 续轮",
    )
  }
  // ID 必须全局唯一：root_task_id() 恒为 "T0"，多 namespace 冷启动会撞主键；
  // 用 first_free_root_id() 全局探测第一个空闲 id（优先 T0，占用后顺延 T0r2 ...）
  let id = self.first_free_root_id()
  let t = @core.Task::new(
    id~,
    project_dir~,
    description~,
    depth=3,
    split_n=3,
    level~,
    created_at=now,
    ns~,
  )
  match self.store.create_task(t) {
    Ok(_) => Ok(id)
    Err(e) => Err(e)
  }
}

///|
/// 并行追加独立根任务：连续发布多条互不依赖的根任务（自驱式编程「审视 -> 自我派活」用）。
///
/// 与 cold_publish（要求 ns 为空）和 publish_next_round（要求前轮已完成并续轮归档）不同，
/// 本方法允许命名空间已有任务，直接以唯一 id（T0 / T0r2 / T0r3 ...）追加为新的独立根任务，
/// 不续轮、不归档、不要求前轮状态，专用于同一审视报告的多条 Next Tasks 并行落地。
pub fn FistEngine::publish_parallel(
  self : FistEngine,
  ns~ : String,
  description~ : String,
  created_by~ : String,
  project_dir~ : String,
  now~ : String,
  level~ : Int32 = 6,
) -> Result[String, String] {
  if ns == "" || ns == "default" {
    return Err(
      "并行发布仅限定时任务/自驱命名空间（namespace 不得为空或 default）",
    )
  }
  // 续轮发起者仅作审计用途（Task 无 created_by 字段），非法值不阻断。
  ignore(created_by)
  let id = self.first_free_root_id()
  let t = @core.Task::new(
    id~,
    project_dir~,
    description~,
    depth=3,
    split_n=3,
    level~,
    created_at=now,
    ns~,
  )
  match self.store.create_task(t) {
    Ok(_) => Ok(id)
    Err(e) => Err(e)
  }
}

///|
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
      match self.store.update_task(c2) {
        Ok(_) => ()
        Err(e) => return Err("重开落库失败: \{e}")
      }
      Ok(c2)
    }
  }
}

///|
/// 验收拒绝（reject）：待验收 -> 已打回
///
/// **参数 `by`（BUG-354 出路 c）**：驳回者身份。本函数体内**不消费**它——「谁驳回的」
/// 在任务状态面没有落点（`reason` 会落库，`by` 不会）。审计面靠 `call_log` 的原始
/// 入参。保留形参理由同 `plan`：它是 pub 接口 + MCP 入参 schema 的一部分，删它会
/// 收缩对外契约；要真正消费需动 store schema，属行为变更。
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
        return Err(
          "非法打回: 任务处于 [\{t.status_to_string()}]，仅待验收可打回",
        )
      }
      let c = match t.reject(reason~) {
        Ok(x) => x
        Err(e) => return Err(e)
      }
      let c2 = c.with_updated_at(now)
      match self.store.update_task(c2) {
        Ok(_) => ()
        Err(e) => return Err("拒绝落库失败: \{e}")
      }
      Ok(c2)
    }
  }
}

///|
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
      match self.store.update_task(c2) {
        Ok(_) => ()
        Err(e) => return Err("重试落库失败: \{e}")
      }
      Ok(c2)
    }
  }
}

///|
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
      match self.store.update_task(c2) {
        Ok(_) => ()
        Err(e) => return Err("暂停落库失败: \{e}")
      }
      Ok(c2)
    }
  }
}

///|
/// 恢复任务：已暂停 -> 已领取
pub fn FistEngine::resume_task(
  self : FistEngine,
  task_id~ : String,
  now~ : String,
) -> Result[@core.Task, String] {
  match self.store.get_task(task_id) {
    None => Err("task not found: \{task_id}")
    Some(t) => {
      let c = match t.resume_task() {
        Ok(x) => x
        Err(e) => return Err(e)
      }
      let c2 = c.with_updated_at(now)
      match self.store.update_task(c2) {
        Ok(_) => ()
        Err(e) => return Err("恢复落库失败: \{e}")
      }
      Ok(c2)
    }
  }
}

///|
/// 删除任务（仅限已归档，ARCHIVING 清理）
pub fn FistEngine::delete_task(
  self : FistEngine,
  task_id : String,
) -> Result[Unit, String] {
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

///|
/// AO 式递归拆解入口：对指定任务拆出整棵子任务树并写库。
///
/// 入参：
///   task_id   要拆解的根/拳节任务 id（非原子任务才可拆）；
///   split_n   每层默认拆分数（无 spec.laws 时生效，默认 3）；
///   by        执行拆解的拳长身份（仅记录）；
///   spec      可选 omega spec JSON（laws 作切割依据，fingerprint 作验收基准）；
///   now       时间戳。
///   reinject_context  是否把「父计划 + 剩余兄弟」回注进每条子任务描述（R63，ReCAP 借鉴；
///                      默认 false 零回归）——让原子片知道自己"为什么做、旁边还有谁"，防上下文漂移。
///   boundary_probe    是否为「spec 没写的域外行为」补一个 owner（R115+，atgc-merge 归因报告
///                      机理 1「递归拆解损失全局视角」+ 机理 2「验收锚定 + 弱语料」）：
///                      true 时本层末尾追加一条「边界审视叶」（全局输入域 owner），
///                      并给其余每条叶挂「边界四问」提示。默认 false 零回归。
///
/// 返回：{ "root", "by", "created", "tree" }，tree 为多层子树结构；
/// 任一子节点非叶时将继续递归（depth 递减，is_leaf=depth<=1 停止）。
pub fn FistEngine::plan_deep(
  self : FistEngine,
  task_id~ : String,
  split_n~ : Int32 = 3,
  by~ : String,
  spec~ : Json? = None,
  now~ : String,
  omega_strong_verify~ : Bool = false,
  gradient~ : Bool = false,
  calibrate~ : Array[Double]? = None,
  gradient_dag~ : Bool = false,
  reinject_context~ : Bool = false,
  boundary_probe~ : Bool = false,
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
      // 对「本身已被拆解过一次」的任务再拆（如二次 plan_deep 下钻/重拆）时，
      // 父描述里自带的引擎标注不得再当切割底稿（R113）。
      let parent_desc = strip_plan_annotations(parent.description)
      let slices = match spec {
        Some(s) => @decompose.decompose_slices(s, split_n, parent_desc~)
        None => @decompose.default_slices(split_n, parent_desc~)
      }
      match
        self.decompose_rec(
          parent, slices, spec, now, omega_strong_verify, gradient, calibrate, gradient_dag,
          reinject_context, boundary_probe,
        ) {
        Err(e) => Err(e)
        Ok(tree) =>
          Ok(
            Json::object({
              "root": Json::string(task_id),
              "by": Json::string(by),
              "split_n": Json::number(split_n.to_double()),
              "tree": tree,
            }),
          )
      }
    }
  }
}

///|
/// 递归拆解单层并下钻（私有，同包可见）。
/// 返回该层子树 meta：{ "task_id", "created", "children": [...] }。
fn FistEngine::decompose_rec(
  self : FistEngine,
  parent : @core.Task,
  slices : Array[String],
  spec : Json?,
  now : String,
  omega_strong_verify : Bool,
  gradient : Bool,
  calibrate : Array[Double]?,
  gradient_dag : Bool,
  reinject_context : Bool,
  boundary_probe : Bool,
) -> Result[Json, String] {
  // 父任务进入拆分中（宽于 Task::split：待领取/已领取/拆分中均可转入）
  match parent.mark_decomposing() {
    Ok(p2) =>
      match self.store.update_task(p2.with_updated_at(now)) {
        Ok(_) => ()
        Err(e) => return Err("递归拆分状态落库失败: \{e}")
      }
    Err(e) => return Err(e)
  }
  // 边界审视叶（默认关闭零回归）：给"spec 没写的域外行为"一个可领取、可验收的归属，
  // 补掉递归拆解后被压缩掉的全局视角（atgc-merge 归因报告机理 1）。
  // biz_slices = 调用方看得见的业务片数：这一片是引擎追加的元叶，不在调用方的切片计数里。
  // 旧实现只拿撑大后的 slices.length() 比 calibrate 长度，一开 boundary_probe，
  // 按切片给的校准数组就长度不符而整段静默失效（R113 实测：calibrate=[4,2,1] 全部回落位置档）。
  let biz_slices = slices.length()
  let slices = if boundary_probe {
    slices + [boundary_probe_slice()]
  } else {
    slices
  }
  let child_depth = parent.get_depth() - 1
  let spec_hash = @decompose.spec_hash_of(spec)
  let nodes : Array[Json] = []
  let mut created = 0
  // LADDER 真实 DAG 化：gradient_dag 开启时，本层切片按"由易到难"连成前驱链，
  // 使"先完成更简单变体再逆推本体"成为真实可领取门禁（依赖前驱完成后本片才可认领），
  // 而非仅 description 里的提示文本。默认关闭零回归。
  let mut prev_cid : String? = None
  for i = 0; i < slices.length(); i = i + 1 {
    let idx = i + 1
    let cid = @core.child_id(parent_id=parent.get_id(), idx~)
    // 切割底稿不得带上一层的引擎标注：R113 实测 gradient+reinject 全开时，
    // 已标注的文本被当作下一层的 parent_desc 再喂，标注按层叠乘（2 层树叶子 1996B / 根 12B），
    // 同一叶内还会并存两个互相矛盾的梯度档。
    let slice_text = strip_plan_annotations(slices[i])
    let base_desc = if spec_hash == "" {
      omega_clean_slice(slice_text)
    } else {
      "\{omega_clean_slice(slice_text)} [spec:\{spec_hash}]"
    }
    // LADDER 信号（默认关闭零回归）：开启时为该切片标注难度梯度 + 更简单变体提示，
    // 让递归拆解产出"由易到难/可验证最小片"的梯度，而非扁平同难单元。
    let n_slices = slices.length()
    let grad_suffix = if gradient {
      // 难度校准（可选）：调用方按切片给真实/投影难度(0..5)，长度须与切片一致才生效；
      // 否则回退到位置三分档（由易到难）。默认缺省=纯位置档，零回归。
      let calibrated = match calibrate {
        Some(arr) if arr.length() == biz_slices && idx <= biz_slices =>
          Some(arr[idx - 1])
        Some(arr) if arr.length() == n_slices => Some(arr[idx - 1])
        _ => None
      }
      let lvl = match calibrated {
        Some(d) => @decompose.difficulty_label_from(d)
        None => @decompose.difficulty_label(idx, n_slices)
      }
      let calib_note = match calibrated {
        Some(d) => " d=\{d.to_string()}"
        None => ""
      }
      let hint = @decompose.simpler_variant_hint(omega_clean_slice(slice_text))
      " [难度梯度 \{idx}/\{n_slices}:\{lvl}\{calib_note}] \{hint}"
    } else {
      ""
    }
    // Omega 强验证开关（默认关闭）：开启时为本层子任务打标记，使其受门禁约束。
    //
    // F3 修正（2026-10-24，在线缺陷）：判据**不是**本次 plan_deep 的入参，而是
    // 「本次入参为真」**或**「父任务已开着 Omega」。旧写法只看入参 ⇒ 父任务开着
    // `[omega:required]`、调用方调 plan_deep 时**不传** omega_strong_verify 时，
    // 整棵子树的 omega_required 全落 false ⇒ omega_spec_create / omega_spec_review /
    // omega_result_verify 对整棵子树直接放行（门禁在「拆分」这一步静默失效）。
    // 复现读数（δ bugfind 编码）：PHk2L2P1 = 父开着 / 拆 2 个子任务 / 2 个丢失门禁。
    //
    // 「父是否开着」只走**单一真源** `omega_enabled(parent)`（元数据列 get_omega_required()
    // 取或 description 里的 [omega:required] 文本），本文件不复制那套判法——
    // 复制一份就是第 5 种判法，下一颗漂移雷。
    // 递归下钻天然成立：上一层的 child 就是下一层的 parent，开关沿链逐层传导。
    //
    // F2 留痕（不在本单实现）：`||` 是**单调 OR** —— 一旦子任务被标上 omega_required，
    // 后续任何一次 plan_deep（哪怕入参 false、哪怕父被改成 false）都不会把它清回去，
    // 全仓也**没有** omega_required=false 的赋值点 ⇒ 误开只能手工改库。
    // 这是**有意的**：门禁开关是「加严」方向，可自动加严、不可自动放松——自动放松会让
    // 一次参数笔误把一整棵子树的验收门禁悄悄关掉，而那正是本条缺陷的形状。
    // 「显式关闭入口」（谁有权关、关了留什么痕）属 advance 面，不在 fix_and_merge 范围。
    let omega_on = omega_strong_verify || omega_enabled(parent)
    let full_desc = if omega_on {
      base_desc + grad_suffix + " " + omega_mark()
    } else {
      base_desc + grad_suffix
    }
    // ReCAP 借鉴·父计划回注（默认关闭零回归）：在子任务描述里带上「它归属于哪个父计划 +
    // 还剩余几个兄弟」，让拆出的原子片知道自己"为什么做、旁边还有谁"——防上下文漂移。
    // 子任务拿到父计划 = 真正"知其所以然"，而非孤立切片。
    let reinjected = if reinject_context {
      full_desc +
      " | [父计划: \{strip_plan_annotations(parent.description)} · 剩余兄弟: \{n_slices - idx}]"
    } else {
      full_desc
    }
    // 边界四问（默认关闭零回归）：把"spec 之外也要想"变成每条叶的显式义务，
    // 而不是等裁判发现某条边界无人负责（atgc-merge 归因报告机理 2/3）。
    let child_full = if boundary_probe && slice_text != boundary_probe_slice() {
      reinjected + boundary_probe_hint()
    } else {
      reinjected
    }
    // LADDER 真实 DAG：开启 gradient_dag 时，给非首切片挂上前一兄弟切片作依赖
    let dag_dep : Array[String] = if gradient && gradient_dag {
      match prev_cid {
        Some(p) => [p]
        None => []
      }
    } else {
      []
    }
    let child = @core.Task::new(
      id=cid,
      project_dir=parent.project_dir,
      ns=parent.ns,
      description=child_full,
      parent_id=parent.get_id(),
      priority=parent.priority,
      importance=parent.importance,
      depth=child_depth,
      split_n=if child_depth > 1 { child_depth } else { 1 },
      // 军衔继承降一级：连长(6)→排长(7)→士兵（封顶 7）。军衔与 depth 严格分离。
      level=@core.child_level(parent.get_level()),
      created_at=now,
      depends_on=dag_dep,
      // BUG-389 方向②：把 Omega 门禁判据写进不可覆盖的元数据列 omega_required，
      // 不依赖 description 里的 [omega:required] 文本（upsert 覆盖描述不再丢开关）。
      // F3：继承父任务的开关（omega_on 见上文），别再只看本次入参。
      omega_required=omega_on,
    )
    match self.store.create_task(child) {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
    created = created + 1
    if gradient && gradient_dag {
      prev_cid = Some(cid)
    }
    // 递归下钻：仅非叶节点继续派生拆分
    let kids_arr : Array[Json] = if !child.is_leaf() {
      // 下钻底稿只取任务本体：child.description 带着本层的梯度/回注/边界/强验证标注，
      // 原样再喂会让标注按层叠乘（R113）。
      let next_slices = @decompose.default_slices(
        child.split_n,
        parent_desc=strip_plan_annotations(child.description),
      )
      match
        self.decompose_rec(
          child, next_slices, spec, now, omega_strong_verify, gradient, calibrate,
          gradient_dag, reinject_context, boundary_probe,
        ) {
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
      ("depends_on", Json::array(dag_dep.map(fn(s) { Json::string(s) }))),
      ("children", Json::array(kids_arr)),
    ])
    nodes.push(Json::object(node_m))
  }
  Ok(
    Json::object({
      "task_id": Json::string(parent.get_id()),
      "created": Json::number(created.to_double()),
      "children": Json::array(nodes),
    }),
  )
}

/// ==================== DAG 依赖图 ====================

///|
/// 检查某任务的直接依赖是否全部完成
pub fn FistEngine::deps_satisfied(self : FistEngine, task_id : String) -> Bool {
  match self.store.get_task(task_id) {
    None => false
    Some(t) => {
      let dep_ids = t.depends_on
      if dep_ids.is_empty() {
        return true
      }
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

///|
/// 拓扑排序（Kahn 算法）：task A 在 depends_on 中的任务之后执行（依赖先输出）。
/// 仅按 task_ids 集合内的依赖建图；集合外的依赖视为已满足（不影响本集合内排序）。
/// 稳定：同批 indegree=0 的节点按 task_ids 原序输出；环残留节点按原序追加尾部。
pub fn FistEngine::topo_sort(
  self : FistEngine,
  task_ids : Array[String],
) -> Array[String] {
  let in_task : Map[String, Bool] = Map([])
  for id in task_ids {
    in_task.set(id, true)
  }
  // indegree: 任务在 task_ids 内尚未满足的依赖数；dependents[d] = 依赖 d 的任务列表
  let indeg : Map[String, Int32] = Map([])
  let dependents : Map[String, Array[String]] = Map([])
  for id in task_ids {
    indeg.set(id, 0)
    dependents.set(id, [])
  }
  for id in task_ids {
    match self.get_task(id) {
      Some(t) =>
        for d in t.depends_on {
          if in_task.contains(d) && d != id {
            indeg.set(id, indeg.get(id).unwrap_or(0) + 1)
            let arr = dependents.get(d).unwrap_or([]).copy()
            arr.push(id)
            dependents.set(d, arr)
          }
        }
      None => ()
    }
  }
  let remaining : Map[String, Bool] = Map([])
  for id in task_ids {
    remaining.set(id, true)
  }
  let out : Array[String] = []
  while true {
    let ready : Array[String] = []
    for id in task_ids {
      if remaining.contains(id) && indeg.get(id).unwrap_or(0) == 0 {
        ready.push(id)
      }
    }
    if ready.is_empty() {
      break
    }
    for id in ready {
      remaining.remove(id)
      out.push(id)
      match dependents.get(id) {
        Some(list) =>
          for dep in list {
            if remaining.contains(dep) {
              indeg.set(dep, indeg.get(dep).unwrap_or(0) - 1)
            }
          }
        None => ()
      }
    }
  }
  // 环保护：成环剩余节点按原序追加尾部，保证全量输出
  for id in task_ids {
    if remaining.contains(id) {
      out.push(id)
    }
  }
  out
}

///|
/// 在 Char 数组中寻找任一子串起始下标（找不到返回 -1）。
fn find_sub_chars(hay : Array[Char], needle : Array[Char]) -> Int32 {
  if needle.length() == 0 {
    return 0
  }
  let mut i = 0
  while i + needle.length() <= hay.length() {
    let mut j = 0
    while j < needle.length() && hay[i + j] == needle[j] {
      j = j + 1
    }
    if j == needle.length() {
      return i
    }
    i = i + 1
  }
  -1
}

///|
/// 从任务描述中抽取 LADDER 难度档（`[难度梯度 idx/n:档]` 中档位子串），无则返回空串。
pub fn extract_difficulty(desc : String) -> String {
  let tag = "[难度梯度 "
  let cs = desc.to_array()
  let p = find_sub_chars(cs, tag.to_array())
  if p < 0 {
    return ""
  }
  // 定位 tag 后的 ':' 与最终 ']'，取出中间档位文本
  let mut colon = -1
  let mut i = p + tag.length()
  while i < cs.length() {
    if cs[i] == ':' {
      colon = i
      break
    }
    i = i + 1
  }
  if colon < 0 {
    return ""
  }
  let mut out = ""
  let mut j = colon + 1
  while j < cs.length() && cs[j] != ']' {
    out = out + cs[j].to_string()
    j = j + 1
  }
  out
}

///|
/// 生成整棵拆解子树的「执行计划」视图：收集根任务全部后代（BFS），按 DAG
/// `depends_on` 拓扑排序，输出一张扁平、按依赖可安全执行的清单（每条含
/// id/depth/难度档/依赖/状态）。供 agent 拆解后拿到即可照单执行——"一张计划、
/// 一目了然"，而非再全库去翻。纯读、无副作用。
pub fn FistEngine::plan_exec_order(self : FistEngine, root_id : String) -> Json {
  // R12-R8 性能：旧实现每层每节点调 `children_of`（每次全库 list_tasks）。
  // 这里一次建索引，BFS 里全部 O(1) Map 查。
  let cidx = self.children_index()
  let all_ids : Array[String] = []
  let mut frontier : Array[String] = cidx.get(root_id).unwrap_or([])
  while !frontier.is_empty() {
    let next : Array[String] = []
    for id in frontier {
      all_ids.push(id)
      for kid in cidx.get(id).unwrap_or([]) {
        next.push(kid)
      }
    }
    frontier = next
  }
  // 拓扑序执行（依赖先完成），体现"先易后逆推"的顺序保证
  let order = self.topo_sort(all_ids)
  let plan : Array[Json] = []
  for id in order {
    match self.get_task(id) {
      Some(t) =>
        plan.push(
          Json::object({
            "id": Json::string(t.get_id()),
            "depth": Json::number(t.get_depth().to_double()),
            "difficulty": Json::string(extract_difficulty(t.description)),
            "depends_on": Json::array(
              t.depends_on.map(fn(s) { Json::string(s) }),
            ),
            "status": Json::string(t.get_status().to_string()),
          }),
        )
      None => ()
    }
  }
  Json::object({
    "task_id": Json::string(root_id),
    "count": Json::number(plan.length().to_double()),
    "order": Json::array(plan),
  })
}

///|
/// 获取当前命名空间内所有 Pending 且依赖满足、可领取的任务
pub fn FistEngine::ready_tasks(
  self : FistEngine,
  ns_filter~ : String = "default",
) -> Array[@core.Task] {
  let target = if ns_filter == "" { "default" } else { ns_filter }
  let tasks = self.store.list_tasks_in(target)
  // R12-R7 性能：`deps_satisfied` 对每个任务及其每个依赖都调 `store.get_task`
  // （SqliteStore 下是 DB 读）。对 N 任务 × D 依赖，旧代码是 N×(1+D) 次 DB 读。
  // 这里**一次遍历**建出 `completed` 映射（id → 是否已完成），
  // 之后依赖满足判断全部走内存 Map。
  let completed : Map[String, Bool] = Map([])
  for t in tasks {
    completed.set(t.get_id(), t.get_status().is_completed())
  }
  let ready : Array[@core.Task] = []
  for t in tasks {
    if t.get_status().is_pending() && deps_ready_memo(t.depends_on, completed) {
      ready.push(t)
    }
  }
  ready
}

///|
/// 判断 `dep_ids` 是否全部在 `completed` 映射中为已完成。
/// 供 `ready_tasks` / `parallelism` 在 O(1) Map 查询下做依赖判断
/// （替代逐条 `store.get_task`）。pub 以便 `engine_dag_ext` 复用。
pub fn deps_ready_memo(
  dep_ids : Array[String],
  completed : Map[String, Bool],
) -> Bool {
  for tid in dep_ids {
    let done = match completed.get(tid) {
      Some(b) => b
      None => false
    }
    if !done {
      return false
    }
  }
  true
}

///|
/// 创建任务时指定依赖（depends_on 为依赖的任务 id 列表）
pub fn FistEngine::publish_with_deps(
  self : FistEngine,
  project_dir~ : String,
  description~ : String,
  depends_on~ : Array[String] = [],
  created_by~ : String = "human_steward",
  now~ : String = "",
  ns~ : String = "default",
  level~ : Int32 = 6,
) -> Result[String, String] {
  if created_by != "human_steward" && created_by != "human" {
    return Err("publish 仅限人类指挥官")
  }
  for dep in depends_on {
    match self.store.get_task(dep) {
      None => return Err("依赖任务不存在: \{dep}")
      Some(_) => ()
    }
  }
  // 根任务 id 全局唯一：T0 被占用时顺延 T0r2/T0r3
  let id = self.first_free_root_id()
  let t = @core.Task::new(
    id~,
    project_dir~,
    description~,
    depth=3,
    split_n=3,
    level~,
    created_at=now,
    ns~,
    depends_on~,
  )
  match self.store.create_task(t) {
    Ok(_) => Ok(id)
    Err(e) => Err(e)
  }
}

///|
fn estimate_rank(assignee : String) -> Int32 {
  if assignee == "human_steward" || assignee == "human" {
    0
  } else if assignee.has_prefix("leader") || assignee.has_prefix("polish-lead") {
    6
  } else if assignee.has_prefix("atomcode") || assignee.has_prefix("aider") {
    4
  } else {
    5
  }
}

///|
fn rank_can_claim(arank : Int32, tlevel : Int32) -> Bool {
  arank == 0 || arank <= tlevel
}

///|
fn level_to_rank(lvl : Int32) -> String {
  match lvl {
    0 => "司令"
    1 => "军长"
    2 => "师长"
    3 => "旅长"
    4 => "团长"
    5 => "营长"
    6 => "连长"
    7 => "排长"
    _ => "士兵"
  }
}

///|
/// 从任务 description 抽取所需能力关键词。
/// 识别：需要: / need: / requires: / 能力:
/// 每行一个标签，逗号/顿号分隔。
fn extract_needs(desc : String) -> Array[String] {
  // 极简版：识别 "需要:" / "need:" / "requires:" / "能力:" 开头的行
  let result : Array[String] = []
  let lines = desc.split("\n").to_array()
  for line in lines {
    let sv = line.trim()
    let has_need = sv.has_prefix("需要:") ||
      sv.has_prefix("需要：") ||
      sv.has_prefix("need:") ||
      sv.has_prefix("requires:") ||
      sv.has_prefix("能力:") ||
      sv.has_prefix("能力：")
    if has_need {
      let s = sv.to_owned()
      let after = if sv.has_prefix("需要:") {
        s["需要:".length():].trim()
      } else if sv.has_prefix("需要：") {
        s["需要：".length():].trim()
      } else if sv.has_prefix("need:") {
        s["need:".length():].trim()
      } else if sv.has_prefix("requires:") {
        s.substring(start="requires:".length()).trim()
      } else if sv.has_prefix("能力:") {
        s.substring(start="能力:".length()).trim()
      } else if sv.has_prefix("能力：") {
        s.substring(start="能力：".length()).trim()
      } else {
        ""
      }
      if after.length() > 0 {
        // 分隔符：ASCII 逗号 / 顿号「、」/ 全角逗号「，」——docstring 承诺"逗号/顿号分隔"，
        // 而原实现只 split 了 ASCII 逗号 ⇒ 写成「需要: python、json」时整串被当成单个标签，
        // 能力门会把它和 abilities 比对失败，**把合格执行者误拒**（本轮实测发现）。
        let parts = after.split(",")
        for p_sv in parts {
          for q_sv in p_sv.split("、") {
            for r_sv in q_sv.split("，") {
              let tag = r_sv.trim().to_owned()
              if tag.length() > 0 {
                result.push(tag)
              }
            }
          }
        }
      }
    }
  }
  result
}
