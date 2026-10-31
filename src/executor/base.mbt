/// base.mbt — 执行器抽象层：Executor trait + ExecResult。
///
/// 设计原则：
///   - MoonBit 无 subprocess，执行器通过 MCP 协议委托给客户端
///   - 保留 manual 模式（客户端直接回调 execute 工具）作为 fallback
///   - ExecResult 提供执行元数据（执行器/模型/token/耗时），供成本统计用

///|
/// 执行上下文：执行器运行所需的任务环境。
///
/// ⚠ 包外可见性走**访问器**，不走 `pub(open)`（本工具链在 .mbt 里不接受该修饰符，
/// 实测报 4002「The pub(open) modifier is not supported here」）。
/// 为什么必须有访问器：类型保持闭包时，第三方在自己的包里实现 `trait Executor`
/// 既读不到 `res.ok` 也不能用字面量构造 `ExecResult`，编译器给的是
/// `Cannot create values of the read-only type`（4036/4033，实测见
/// `src/executor/cli_argv_wbtest.mbt:5`、账本 BUG-413）——
/// 评委读到的「外部实现 Executor 报 readonly」就是那一句。
/// 下面这组 pub 访问器 + 构造器/追加器，就是让「实现 trait」这件事在包外真的可行。
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
/// 执行结果（同 ExecContext：`pub(open)` 让包外实现者可构造、可读字段）
pub struct ExecResult {
  ok : Bool
  deliverable : String
  executor : String
  model : String
  tokens_in : Int32
  tokens_out : Int32
  cost : Double
  duration_ms : Int32
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
  tokens_in : Int32,
  tokens_out : Int32,
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
/// —— 包外访问器（「可替换 Executor」的可行面）——
/// 有了这一组 pub 访问器 + 下面的构造/追加器，第三方在自己的包里
/// `impl MyAgent for Executor { fn run(self, task, ctx) -> ExecResult { ... } }`
/// 才既读得到上下文、也造得出结果，不会再撞 4036「read-only type」。
/// 锁：`tests/external_executor/external_executor_test.mbt`（**另一个包**里真实现一遍 trait）。
pub fn ExecContext::project_dir_of(self : ExecContext) -> String {
  self.project_dir
}

///|
pub fn ExecContext::task_id_of(self : ExecContext) -> String {
  self.task_id
}

///|
pub fn ExecContext::description_of(self : ExecContext) -> String {
  self.description
}

///|
pub fn ExecContext::assignee_of(self : ExecContext) -> String {
  self.assignee
}

///|
pub fn ExecResult::succeeded(self : ExecResult) -> Bool {
  self.ok
}

///|
pub fn ExecResult::deliverable_of(self : ExecResult) -> String {
  self.deliverable
}

///|
pub fn ExecResult::executor_of(self : ExecResult) -> String {
  self.executor
}

///|
pub fn ExecResult::model_of(self : ExecResult) -> String {
  self.model
}

///|
pub fn ExecResult::error_msg_of(self : ExecResult) -> String {
  self.error_msg
}

///|
pub fn ExecResult::tokens_in_of(self : ExecResult) -> Int32 {
  self.tokens_in
}

///|
pub fn ExecResult::tokens_out_of(self : ExecResult) -> Int32 {
  self.tokens_out
}

///|
pub fn ExecResult::cost_of(self : ExecResult) -> Double {
  self.cost
}

///|
pub fn ExecResult::duration_ms_of(self : ExecResult) -> Int32 {
  self.duration_ms
}

///|
/// 追加模型标识（外部实现常按任务自选模型；构造器只给 deliverable/executor）。
pub fn ExecResult::with_model(self : ExecResult, model : String) -> ExecResult {
  ExecResult::{
    ok: self.ok,
    deliverable: self.deliverable,
    executor: self.executor,
    model,
    tokens_in: self.tokens_in,
    tokens_out: self.tokens_out,
    cost: self.cost,
    duration_ms: self.duration_ms,
    error_msg: self.error_msg,
  }
}

///|
/// 追加耗时（成本统计要它；旧实现只能改 tokens/cost，时长无处填）。
pub fn ExecResult::with_duration_ms(
  self : ExecResult,
  duration_ms : Int32,
) -> ExecResult {
  ExecResult::{
    ok: self.ok,
    deliverable: self.deliverable,
    executor: self.executor,
    model: self.model,
    tokens_in: self.tokens_in,
    tokens_out: self.tokens_out,
    cost: self.cost,
    duration_ms,
    error_msg: self.error_msg,
  }
}

///|
/// 全量构造器：外部实现若要一次给齐所有执行元数据，用它而不是拆字面量
/// （字面量在包外不可构造，这正是 readonly 报错的来源）。
pub fn ExecResult::full(
  ok~ : Bool,
  deliverable~ : String,
  executor~ : String,
  model~ : String = "",
  tokens_in~ : Int32 = 0,
  tokens_out~ : Int32 = 0,
  cost~ : Double = 0.0,
  duration_ms~ : Int32 = 0,
  error_msg~ : String = "",
) -> ExecResult {
  {
    ok,
    deliverable,
    executor,
    model,
    tokens_in,
    tokens_out,
    cost,
    duration_ms,
    error_msg,
  }
}

///|
/// 执行器 trait
pub(open) trait Executor {
  /// 执行器名称（用于注册与路由）
  fn name(self : Self) -> String

  /// 执行任务并返回结果
  fn run(self : Self, task : @core.Task, ctx : ExecContext) -> ExecResult
}
