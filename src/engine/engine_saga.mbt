/// engine_saga.mbt —— Saga 补偿事务编排（R92，Garcia-Molina & Salem 1987 "Sagas" 蒸馏落地）。
///
/// 多步骤任务链（父子 / DAG）执行到一半失败时，不再"卡死等人工清场"或"整树重来"：
/// 每个前向步骤成功即登记"可补偿动作"到 durable action log（saga_log 表，append-only），
/// 失败时按 LIFO（严格倒序）取出补偿序列执行。补偿是"业务逆转"（新事务），
/// 非数据库 ROLLBACK；补偿幂等契约：补偿执行后标记 done，重试 / 重跑安全。
/// 与看护族（heal / phi_accrual）互补：看护发现失败 → Saga 负责优雅收尾。

///|
/// 登记一个 Saga 补偿步骤（幂等：同 (ns, root_task_id, step) 重登记会把 status
/// 重置为 pending 并刷新 compensation——重试安全，不改 LIFO 位置）。
pub fn FistEngine::saga_register(
  self : FistEngine,
  ns? : String = "default",
  root_task_id~ : String,
  step~ : String,
  task_id? : String = "",
  compensation~ : String,
  now~ : String,
) -> Result[Json, String] {
  match
    self.store_write_saga_action(
      ns~,
      root_task_id~,
      step~,
      task_id~,
      compensation~,
      created_at=now,
    ) {
    Err(m) => Err(m)
    Ok(_) => {
      let m = Map::new()
      m.set("root_task_id", Json::string(root_task_id))
      m.set("step", Json::string(step))
      m.set("task_id", Json::string(task_id))
      m.set("compensation", Json::string(compensation))
      m.set("status", Json::string("pending"))
      m.set("registered", Json::boolean(true))
      Ok(Json::object(m))
    }
  }
}

///|
/// 按 LIFO（严格倒序）返回某根任务待补偿步骤序列；mark=true（默认）返回后一并标记
/// done（幂等：重复调用返回空 pending，防重复回滚；mark=false 仅预览不消费）。
/// 补偿是"业务逆转"动作描述，调用方（agent/指挥官）按序列顺序执行真实补偿。
pub fn FistEngine::saga_rollback(
  self : FistEngine,
  ns? : String = "default",
  root_task_id : String,
  mark? : Bool = true,
) -> Result[Json, String] {
  let rows = self.store_list_saga_actions(ns, root_task_id)
  // 只取待补偿（pending）步骤；rows 为前向顺序（id ASC）
  let pending : Array[(Int, String, String, String, String)] = []
  for r in rows {
    if r.4 == "pending" {
      pending.push(r)
    }
  }
  // LIFO：倒序（id 大 → 小）
  let lifo : Array[(Int, String, String, String, String)] = []
  for i = pending.length() - 1; i >= 0; i = i - 1 {
    lifo.push(pending[i])
  }
  let ids = lifo.map(fn(t) { t.0 })
  let marked_n = if mark && not(ids.is_empty()) {
    match self.store_mark_saga_actions_done(ns~, root_task_id~, ids~) {
      Ok(_) => ids.length()
      Err(_) => 0
    }
  } else {
    0
  }
  let steps : Array[Json] = []
  for t in lifo {
    let sm = Map::new()
    sm.set("id", Json::number(t.0.to_double()))
    sm.set("step", Json::string(t.1))
    sm.set("task_id", Json::string(t.2))
    sm.set("compensation", Json::string(t.3))
    sm.set("status", Json::string(t.4))
    steps.push(Json::object(sm))
  }
  let m = Map::new()
  m.set("root_task_id", Json::string(root_task_id))
  m.set("lifo", Json::boolean(true))
  m.set("pending_count", Json::number(lifo.length().to_double()))
  m.set("pending", Json::array(steps))
  m.set("marked_done", Json::number(marked_n.to_double()))
  m.set(
    "note",
    Json::string(
      "补偿是业务逆转动作（非 DB ROLLBACK），请按 pending 顺序（LIFO）执行真实补偿；已标记 done 的步骤重复调用将不再出现（幂等）。",
    ),
  )
  Ok(Json::object(m))
}
