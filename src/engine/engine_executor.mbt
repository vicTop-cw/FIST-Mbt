/// engine_executor.mbt —— 执行者能力注册的引擎层持久化（Marketplace 雏形，R31）。
///
/// 把 `executor_register` 的能力标签持久化到 store（双后端 executors 表），
/// 使能力注册跨进程可复现（新 server 进程启动后 `executor_route` 能读到既有注册），
/// 补上 R30 的"进程内内存注册表不持久"短板。路由的纯计算仍在 executor 包（单真源），
/// 本层只做"存/取/清"三件事，server 组合 `exec_reg`（进程内）+ 本持久化。

///|
/// 持久化写入/覆盖一个执行者的能力注册（abilities_json 为 JSON 数组串）。
pub fn FistEngine::executor_save(
  self : FistEngine,
  name~ : String,
  abilities_json~ : String,
  created_at~ : String,
) -> Result[String, String] {
  self.store.executor_save(name~, abilities_json~, created_at~)
}

///|
/// 读取全部已注册执行者 (name, abilities_json, created_at)。
pub fn FistEngine::executor_list(
  self : FistEngine,
) -> Array[(String, String, String)] {
  self.store.executor_list()
}

///|
/// 清空全部执行者能力注册（Marketplace 重置/整洁）。
pub fn FistEngine::executor_clear(self : FistEngine) -> Bool {
  self.store.executor_clear()
}

///|
/// 执行者历史信任分（R80，SwarmHarness 蒸馏）：各 assignee 名下 已完成任务数 / 名下任务总数
/// （分母含打回/执行中/待验收等，防"只认领不交付"）；名下无任务取 0.5 中性。
/// 供 executor_route 历史信任轴（排序键 能力覆盖→信任→负载）。
pub fn FistEngine::executor_trust(self : FistEngine) -> Map[String, Double] {
  let total : Map[String, Int] = Map([])
  let done : Map[String, Int] = Map([])
  for t in self.list_all() {
    match t.assignee {
      Some(a) => {
        let cur = total.get(a).unwrap_or(0)
        total.set(a, cur + 1)
        if t.get_status().is_completed() {
          let d = done.get(a).unwrap_or(0)
          done.set(a, d + 1)
        }
      }
      None => ()
    }
  }
  let out : Map[String, Double] = Map([])
  for (name, _abl, _created) in self.executor_list() {
    let tt = total.get(name).unwrap_or(0)
    let dd = done.get(name).unwrap_or(0)
    let tr = if tt <= 0 { 0.5 } else { dd.to_double() / tt.to_double() }
    out.set(name, tr)
  }
  out
}
