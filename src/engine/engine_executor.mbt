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
