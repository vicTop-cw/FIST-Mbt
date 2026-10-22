/// mcp_delegate.mbt — MCP 委托执行器。
///
/// 核心思路：MoonBit 无 subprocess，把执行请求的上下文（任务 id/项目目录/描述/
/// assignee/委托说明）内联打包，随返回结果一并交付客户端；客户端执行完毕后
/// 回调 execute 工具写回交付物。
///
/// 本执行器仅负责生成上下文包并返回"已委托"状态，实际执行由外部客户端完成。
/// 不写任何文件（不落盘 task_context.json）——上下文随返回值交付。

///|
/// MCP 委托执行器（单例结构体）
pub struct McpDelegateExecutor {
  name : String
}

///|
/// 默认构造：名为 "McpDelegateExecutor"
pub fn McpDelegateExecutor::new() -> McpDelegateExecutor {
  { name: "McpDelegateExecutor", }
}

///|
/// 命名构造（供自定义场景）
pub fn McpDelegateExecutor::with_name(n : String) -> McpDelegateExecutor {
  { name: n, }
}

///|
/// 生成执行上下文 JSON（对齐 mavis_executor 格式，内联返回、不写盘）
/// _task 当前未参与序列化（字段信息均来自 ctx），保留参数以维持调用形态。
fn McpDelegateExecutor::make_context(
  self : McpDelegateExecutor,
  _task : @core.Task,
  ctx : ExecContext,
) -> Json {
  Json::object({
    "executor": Json::string(self.name),
    "task_id": Json::string(ctx.task_id),
    "project_dir": Json::string(ctx.project_dir),
    "description": Json::string(ctx.description),
    "assignee": Json::string(ctx.assignee),
    "instruction": Json::string(
      "请执行以下任务，完成后调用 fist-mbt 的 execute 工具写回交付物。",
    ),
  })
}

///|
/// 实现 Executor trait
impl Executor for McpDelegateExecutor with fn name(self) -> String {
  self.name
}

///|
/// 实现 Executor trait — run 方法。
/// 由于无法真正派发子进程，返回"已委托"结果，客户端需自行回调 execute。
impl Executor for McpDelegateExecutor with fn run(
  self,
  task : @core.Task,
  ctx : ExecContext,
) -> ExecResult {
  let context = self.make_context(task, ctx)
  let deliverable = "已生成执行上下文，等待客户端执行。task_context: \{context.stringify()}"
  ExecResult::ok(deliverable, self.name)
}

///|
/// 便捷函数：直接委托（供 engine 调用）
pub fn delegate_execute(task : @core.Task, ctx : ExecContext) -> ExecResult {
  let ex = McpDelegateExecutor::new()
  ex.run(task, ctx)
}
