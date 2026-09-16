/// ops_heal.mbt —— no_signal 看护恢复（M4 运维：AO watchdog 语义）
///
/// 语义参考 agent-orchestrator 的 `no_signal` watchdog（长时间静默 -> 视作 broken）：
/// 心跳超时（或从未上报）且处于"执行中/已领取/拆分中"的任务，回滚为"已领取"
/// 以便重新认领/重派（claim 状态机天然支持 Pending->Claimed/Claimed->Executing），
/// 并清掉其心跳记录，完成"回滚重派"闭环。原子/已完成/已归档任务不在看护范围。

///|
/// 看护一轮：扫描引擎全部任务，对心跳超时静默的活跃任务执行回滚。
/// 返回本轮被回滚（重派）的任务 id 列表。
pub fn heal_stale_tasks(
  engine : @engine.FistEngine,
  hb : Heartbeat,
  now : String,
  timeout_sec? : Int = 600,
) -> Result[Array[String], String] {
  let healed : Array[String] = []
  for t in engine.list_all() {
    let st = t.get_status()
    let stale = (
        st.to_string() == "执行中" ||
        st.to_string() == "已领取" ||
        st.to_string() == "拆分中"
      ) &&
      hb.is_stale(t.get_id(), now, timeout_sec~)
    if stale {
      // 回滚为已领取（reopen_task 内部更新 updated_at）
      match engine.reopen_task(t.get_id(), now) {
        Ok(_) => {
          hb.clear(t.get_id())
          // SQLite 持久化删除（失败仅忽略）
          ignore(engine.store_delete_heartbeat(task_id=t.get_id()))
          healed.push(t.get_id())
        }
        Err(e) => return Err(e)
      }
    }
  }
  Ok(healed)
}

///|
/// 跨进程看护一轮（**读 SQLite 心跳版**，供 watchdog_tick 调用）：
/// 与 `heal_stale_tasks` 语义一致（活跃任务心跳超时 / 无记录 -> 回滚为已领取），
/// 但「是否超时」以**持久化心跳表**为准，因此 MCP 进程重启（cron 每次起新进程）
/// 后仍能正确判断任务是否真的挂了，不会把仍在执行的任务误判为 stale。
///
/// - `ns` 为空串时按默认命名空间处理（与 store 语义一致）；
/// - `now` 或心跳时间戳无法解析时保守判定为「不 stale」（不误伤）；
/// - 所有 store 写失败均忽略，保证本函数幂等、可被任意频率安全调用。
pub fn heal_stale_tasks_from_store(
  engine : @engine.FistEngine,
  now : String,
  timeout_sec? : Int = 600,
  ns? : String = "default",
) -> Result[Array[String], String] {
  let healed : Array[String] = []
  let now_s = iso_to_secs(now)
  if now_s < 0 {
    return Ok(healed)
  }
  // 1. 读持久化心跳表，按 task_id 建 last_seen 索引
  let last_seen_map : Map[String, String] = Map([])
  for row in engine.store_list_heartbeats() {
    let (_agent_id, task_id, last_seen, _status) = row
    if task_id != "" {
      last_seen_map.set(task_id, last_seen)
    }
  }
  // 2. 扫描指定命名空间的任务，对超时静默的活跃任务回滚重派
  for t in engine.list_in_ns(ns) {
    let st = t.get_status().to_string()
    let is_active = st == "执行中" || st == "已领取" || st == "拆分中"
    if !is_active {
      continue
    }
    let stale = match last_seen_map.get(t.get_id()) {
      None => true // 从未心跳过 -> 视为 no_signal
      Some(ts) => {
        let ts_s = iso_to_secs(ts)
        if ts_s < 0 {
          false
        } else {
          now_s - ts_s > timeout_sec
        }
      }
    }
    if stale {
      match engine.reopen_task(t.get_id(), now) {
        Ok(_) => {
          // 清理持久化心跳（失败仅忽略）
          ignore(engine.store_delete_heartbeat(task_id=t.get_id()))
          healed.push(t.get_id())
        }
        Err(_) => ()
      }
    }
  }
  Ok(healed)
}
