/// ops_heal.mbt —— no_signal 看护恢复（M4 运维：AO watchdog 语义）
///
/// 语义参考 agent-orchestrator 的 `no_signal` watchdog（长时间静默 -> 视作 broken）：
/// 心跳超时（或从未上报）且处于"执行中/已领取/拆分中"的任务，回滚为"已领取"
/// 以便重新认领/重派（claim 状态机天然支持 Pending->Claimed/Claimed->Executing），
/// 并清掉其心跳记录，完成"回滚重派"闭环。原子/已完成/已归档任务不在看护范围。

///|
/// 看护一轮：对心跳超时静默的活跃任务执行回滚，返回被回滚（重派）的任务 id 列表。
///
/// `ns` 为空串（缺省）时扫**全库所有命名空间**——BUG-81 记的就是这条默认的作用域：
/// 多 ns 共用同一个 fist-mbt.db，一次不带 ns 的 heal 会把别的轮次的在途任务一并 reopen，
/// 而 `reopen_task` 不署名 ⇒ 枝干 assignee 被清空。只看护自己那一批就显式传 ns。
pub fn heal_stale_tasks(
  engine : @engine.FistEngine,
  hb : Heartbeat,
  now : String,
  timeout_sec? : Int = 600,
  ns? : String = "",
) -> Result[Array[String], String] {
  let healed : Array[String] = []
  let scoped = if ns.is_empty() {
    engine.list_all()
  } else {
    engine.list_in_ns(ns)
  }
  for t in scoped {
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

///|
/// Phi Accrual 概率式看护一轮（R90，默认关闭零回归）：与 `heal_stale_tasks_from_store`
/// 语义一致（活跃任务判死 -> 回滚为已领取），但「是否 stale」改用**概率怀疑度 φ** 判定：
///   对有心跳间隔历史的活跃任务：elapsed = now - last_seen，intervals = 持久化间隔历史，
///   φ = -log10(P(心跳晚于 elapsed 到达))，φ ≥ phi_threshold（默认 8）判 suspect -> 回滚；
///   从未心跳 -> 沿用 no_signal 语义（判 stale）。
/// 相比固定 timeout：心跳节奏越快、越久没来才值得怀疑——不规则慢心跳不被固定超时误杀。
///
/// BUG-27（本轮改）：**概率建模缺数据时回落到固定 timeout，绝不弃权**。旧实现在
/// 「有心跳记录但没有间隔历史」时返回 false（保守不判），而间隔历史的唯一写入点是
/// heartbeat 的**第二次**上报——执行者发过一次心跳就停摆，恰恰永远没有历史，于是它
/// 永远不会被回滚：φ 把它要防的那类失效恰好判成不需处理，比默认路径更差
/// （实测库里 heartbeats 每任务 1 条、heartbeat_history 0 行，是常态不是边角）。
/// 现在这条走 timeout_sec 兜底，与 heal_stale_tasks_from_store 对同一夹具结论一致；
/// `no_history_ids` 是旁路输出，让 watchdog 如实披露哪些任务是靠兜底救回来的。
pub fn heal_stale_tasks_by_phi(
  engine : @engine.FistEngine,
  now : String,
  phi_threshold? : Int = 8,
  ns? : String = "default",
  timeout_sec? : Int = 600,
  no_history_ids? : Array[String] = [],
) -> Result[Array[String], String] {
  let healed : Array[String] = []
  let now_s = iso_to_secs(now)
  if now_s < 0 {
    return Ok(healed)
  }
  let last_seen_map : Map[String, String] = Map([])
  for row in engine.store_list_heartbeats() {
    let (_agent_id, task_id, last_seen, _status) = row
    if task_id != "" {
      last_seen_map.set(task_id, last_seen)
    }
  }
  for t in engine.list_in_ns(ns) {
    let st = t.get_status().to_string()
    let is_active = st == "执行中" || st == "已领取" || st == "拆分中"
    if !is_active {
      continue
    }
    let stale = match last_seen_map.get(t.get_id()) {
      None => true // 从未心跳过 -> 沿用 no_signal 语义
      Some(ts) => {
        let ts_s = iso_to_secs(ts)
        if ts_s < 0 {
          false
        } else {
          let elapsed = now_s - ts_s
          if elapsed < 0 {
            false // 时钟回拨，保守不判
          } else {
            let intervals = engine.store_list_heartbeat_intervals(t.get_id())
            if intervals.is_empty() {
              // BUG-27：没有可建模的历史 ≠ 任务还活着，按固定 timeout 判
              no_history_ids.push(t.get_id())
              elapsed > timeout_sec
            } else {
              let j = @engine.phi_accrual(
                intervals,
                elapsed,
                threshold=phi_threshold,
              )
              match j.value("verdict") {
                Some(String(v)) =>
                  if v == "rejected" || v == "insufficient" {
                    // BUG-26/27 同族：判不了也要回落 timeout，不许弃权
                    no_history_ids.push(t.get_id())
                    elapsed > timeout_sec
                  } else {
                    v == "suspect"
                  }
                _ => false
              }
            }
          }
        }
      }
    }
    if stale {
      match engine.reopen_task(t.get_id(), now) {
        Ok(_) => {
          ignore(engine.store_delete_heartbeat(task_id=t.get_id()))
          healed.push(t.get_id())
        }
        Err(_) => ()
      }
    }
  }
  Ok(healed)
}
