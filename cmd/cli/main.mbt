/// FIST-Mbt CLI 命令行入口（简化版）
/// 用法：moon run cmd/cli/main
///
/// 直接执行单条命令（当前为 demo 模式，硬编码示例调用）
/// 生产环境应通过 MCP server 的 STDIO/SSE 传输调用

fn main {
  let engine = @engine.FistEngine::new()
  // Demo: publish → plan → claim → execute → submit → verify
  match engine.publish(project_dir="./", description="CLI demo task", created_by="human_steward", now="2026-09-12T00:00:00Z", ns="default") {
    Ok(id) => {
      println("发布成功: \{id}")
      match engine.plan(task_id=id, split_n=3, by="agent", now="2026-09-12T00:00:00Z") {
        Ok(ids) => println("拆分成功: \{ids.length()} 个子任务")
        Err(e) => println("拆分错误: \{e}")
      }
    }
    Err(e) => println("发布错误: \{e}")
  }
  // List all tasks
  let tasks = engine.list_all()
  println("共 \{tasks.length()} 个任务:")
  tasks.each(fn(t) {
    println("  \{t.id} [\{t.status.to_string()}] \{t.description}")
  })
}
