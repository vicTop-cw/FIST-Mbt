/// ops_heartbeat.mbt —— 活动信号/心跳看护（M4 运维：AO ActivityState / no_signal watchdog）
///
/// 语义参考 agent-orchestrator 的 activity lifecycle：
///   pre-execution -> active（执行前上报） -> submit（提交后 idle）
/// 单进程 MCP server 场景，进程内登记即可；心跳超时触发 heal 回滚重派（见 ops_heal.mbt）。
/// 持久化说明：心跳为易失活动态，不落 SQLite（重启即重新派发，符合 watchdog 语义）。

/// 心跳登记表：task_id -> (signal, last_seen)。
pub struct Heartbeat {
  signals : Map[String, String]
  last_seen : Map[String, String]
}

pub fn Heartbeat::new() -> Heartbeat {
  { signals: Map([]), last_seen: Map([]) }
}

/// 上报心跳：登记任务信号（pre-execution / active / submit）与时间戳。
pub fn Heartbeat::beat(
  self : Heartbeat,
  task_id : String,
  signal~ : String = "active",
  now~ : String,
) -> Unit {
  self.signals.set(task_id, signal)
  self.last_seen.set(task_id, now)
}

/// 查询某任务最近一次心跳信号；无记录返回空串。
pub fn Heartbeat::signal_of(self : Heartbeat, task_id : String) -> String {
  match self.signals.get(task_id) {
    Some(s) => s
    None => ""
  }
}

/// 查询某任务最近心跳时间；无记录返回空串。
pub fn Heartbeat::last_seen_of(self : Heartbeat, task_id : String) -> String {
  match self.last_seen.get(task_id) {
    Some(s) => s
    None => ""
  }
}

/// 清除某任务的心跳记录（heal 回滚后调用）。
pub fn Heartbeat::clear(self : Heartbeat, task_id : String) -> Unit {
  self.signals.remove(task_id)
  self.last_seen.remove(task_id)
}

/// 是否"超时静默"（no_signal）：
///   - 无任何心跳记录 -> 视作从未活动（stale，交由 watchdog 处理）；
///   - 有记录但距上次心跳超过 timeout_sec -> stale。
/// 时间戳解析失败时保守返回 false（不误伤）。
pub fn Heartbeat::is_stale(
  self : Heartbeat,
  task_id : String,
  now : String,
  timeout_sec~ : Int = 600,
) -> Bool {
  let now_s = iso_to_secs(now)
  if now_s < 0 {
    return false
  }
  match self.last_seen.get(task_id) {
    None => true
    Some(ts) => {
      let ts_s = iso_to_secs(ts)
      if ts_s < 0 { false } else { now_s - ts_s > timeout_sec }
    }
  }
}