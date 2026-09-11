/// ops_heal.mbt —— no_signal 看护恢复（M4 运维：AO watchdog 语义）
///
/// 语义参考 agent-orchestrator 的 `no_signal` watchdog（长时间静默 -> 视作 broken）：
/// 心跳超时（或从未上报）且处于"执行中/已领取/拆分中"的任务，回滚为"已领取"
/// 以便重新认领/重派（claim 状态机天然支持 Pending->Claimed/Claimed->Executing），
/// 并清掉其心跳记录，完成"回滚重派"闭环。原子/已完成/已归档任务不在看护范围。

/// 看护一轮：扫描引擎全部任务，对心跳超时静默的活跃任务执行回滚。
/// 返回本轮被回滚（重派）的任务 id 列表。
pub fn heal_stale_tasks(
  engine : @engine.FistEngine,
  hb : Heartbeat,
  now : String,
  timeout_sec~ : Int = 600,
) -> Result[Array[String], String] {
  let healed : Array[String] = []
  for t in engine.list_all() {
    let st = t.get_status()
    let stale = (st.to_string() == "执行中" || st.to_string() == "已领取" || st.to_string() == "拆分中") &&
      hb.is_stale(t.get_id(), now, timeout_sec=timeout_sec)
    if stale {
      // 回滚为已领取（reopen_task 内部更新 updated_at）
      match engine.reopen_task(t.get_id(), now) {
        Ok(_) => {
          hb.clear(t.get_id())
          healed.push(t.get_id())
        }
        Err(e) => return Err(e)
      }
    }
  }
  Ok(healed)
}