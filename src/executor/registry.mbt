/// registry.mbt — 执行器注册表（单例模式）。
///
/// 管理执行器实例的注册与查找。默认注册 McpDelegateExecutor。
/// 支持自定义执行器（通过 register 动态添加）。

///|
/// 注册表结构体（简化版：用名称 -> 名称映射，实际执行器通过名称构造）
pub struct ExecutorRegistry {
  executors : Map[String, String]
}

///|
/// 全局注册表（使用 Once 懒初始化）
fn ExecutorRegistry::new() -> ExecutorRegistry {
  let m : Map[String, String] = Map([])
  // 默认注册 McpDelegateExecutor
  m.set("McpDelegateExecutor", "McpDelegateExecutor")
  m.set("manual", "manual")
  { executors: m, }
}

///|
/// 注册执行器
pub fn ExecutorRegistry::register(
  self : ExecutorRegistry,
  name : String,
) -> ExecutorRegistry {
  let m = self.executors
  m.set(name, name)
  { executors: m, }
}

///|
/// 检查执行器是否已注册
pub fn ExecutorRegistry::has(self : ExecutorRegistry, name : String) -> Bool {
  self.executors.get(name) is Some(_)
}

///|
/// 列出所有已注册执行器
pub fn ExecutorRegistry::list(self : ExecutorRegistry) -> Array[String] {
  let names : Array[String] = []
  for k in self.executors.keys() {
    names.push(k)
  }
  names
}

///|
/// 获取执行器（返回名称，实际构造由调用方完成）
pub fn ExecutorRegistry::get(self : ExecutorRegistry, name : String) -> String? {
  self.executors.get(name)
}

///|
/// 便捷函数：判断是否为合法执行器名称
pub fn is_valid_executor(name : String) -> Bool {
  name == "McpDelegateExecutor" || name == "manual"
}
