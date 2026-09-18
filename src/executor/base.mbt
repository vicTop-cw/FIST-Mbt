/// base.mbt — 执行器抽象层：Executor trait + ExecResult。
///
/// 设计原则：
///   - MoonBit 无 subprocess，执行器通过 MCP 协议委托给客户端
///   - 保留 manual 模式（客户端直接回调 execute 工具）作为 fallback
///   - ExecResult 提供执行元数据（执行器/模型/token/耗时），供成本统计用

///|
/// 执行上下文：执行器运行所需的任务环境
pub struct ExecContext {
  project_dir : String
  task_id : String
  description : String
  assignee : String
}

///|
pub fn ExecContext::new(
  project_dir : String,
  task_id : String,
  description : String,
  assignee : String,
) -> ExecContext {
  { project_dir, task_id, description, assignee, }
}

///|
/// 执行结果
pub struct ExecResult {
  ok : Bool
  deliverable : String
  executor : String
  model : String
  tokens_in : Int
  tokens_out : Int
  cost : Double
  duration_ms : Int
  error_msg : String
}

///|
pub fn ExecResult::ok(deliverable : String, executor : String) -> ExecResult {
  {
    ok: true,
    deliverable,
    executor,
    model: "",
    tokens_in: 0,
    tokens_out: 0,
    cost: 0.0,
    duration_ms: 0,
    error_msg: "",
  }
}

///|
pub fn ExecResult::fail(error_msg : String, executor : String) -> ExecResult {
  {
    ok: false,
    deliverable: "",
    executor,
    model: "",
    tokens_in: 0,
    tokens_out: 0,
    cost: 0.0,
    duration_ms: 0,
    error_msg,
  }
}

///|
pub fn ExecResult::with_tokens(
  self : ExecResult,
  tokens_in : Int,
  tokens_out : Int,
  cost : Double,
) -> ExecResult {
  ExecResult::{
    ok: self.ok,
    deliverable: self.deliverable,
    executor: self.executor,
    model: self.model,
    tokens_in,
    tokens_out,
    cost,
    duration_ms: self.duration_ms,
    error_msg: self.error_msg,
  }
}

///|
pub fn ExecResult::to_json(self : ExecResult) -> Json {
  Json::object({
    "ok": Json::boolean(self.ok),
    "deliverable": Json::string(self.deliverable),
    "executor": Json::string(self.executor),
    "model": Json::string(self.model),
    "tokens_in": Json::number(self.tokens_in.to_double()),
    "tokens_out": Json::number(self.tokens_out.to_double()),
    "cost": Json::number(self.cost),
    "duration_ms": Json::number(self.duration_ms.to_double()),
    "error_msg": Json::string(self.error_msg),
  })
}

///|
/// 执行器 trait
pub trait Executor {
  /// 执行器名称（用于注册与路由）
  fn name(self : Self) -> String

  /// 执行任务并返回结果
  fn run(self : Self, task : @core.Task, ctx : ExecContext) -> ExecResult
}
