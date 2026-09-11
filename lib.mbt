/// FIST-Mbt 对外门面：向包使用者导出主要公共类型与 server 入口。
/// 实现源码分类位于 src/ 下各子包。

pub type Task = @core.Task
pub type TaskStatus = @core.TaskStatus
pub type SqliteStore = @store.SqliteStore
pub type FistEngine = @engine.FistEngine

pub async fn run_server() -> Unit {
  @server.run_server()
}
