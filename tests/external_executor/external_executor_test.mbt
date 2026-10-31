/// tests/external_executor/external_executor_test.mbt —
/// 验收项「可替换 Executor」的**包外**证据。
///
/// 为什么单独开一个包：评委的话是「外部实现 Executor 报 readonly」。
/// 只有在**不是 src/executor 自己**的包里实现一遍 trait，才测得到外部实现者
/// 到底撞不撞墙——同包内的测试读得到私有字段、写得了字面量，天然测不出这件事
/// （判例-33「服务本体 ≠ 服务接入」、判例-29「机制格 ≠ 实现路径格」同族）。
///
/// 本包因此钉四件事：
///   ① 在自己的包里 `impl @executor.Executor for <自己的类型>` 编译得过；
///   ② 读上下文走**访问器**（闭包类型的裸字段在包外读不到，就是那句 read-only）；
///   ③ 造结果走**构造器/追加器**（包外写不了 `ExecResult::{...}` 字面量）；
///   ④ 同一个调用点能派发**两个不同**实现 ⇒ 抽象层是真的，不是只挂个名字。

///|
/// 假想实现一：远程沙箱（没有本地进程，只回一份「已在沙箱跑完」的元数据）。
struct RemoteSandboxAgent {
  label : String
}

///|
fn RemoteSandboxAgent::new() -> RemoteSandboxAgent {
  { label: "remote-sandbox", }
}

///|
impl @executor.Executor for RemoteSandboxAgent with fn name(self) -> String {
  self.label
}

///|
impl @executor.Executor for RemoteSandboxAgent with fn run(
  self,
  task : @core.Task,
  ctx : @executor.ExecContext,
) -> @executor.ExecResult {
  // ② 读上下文一律走访问器：ctx.task_id 在包外是读不到的
  let tid = ctx.task_id_of() + "/" + task.get_id()
  // ③ 造结果一律走构造器：ExecResult::{...} 字面量在包外不可构造
  @executor.ExecResult::full(
    ok=true,
    deliverable="沙箱已执行 " + tid,
    executor=self.label,
    model="sandbox-llm-1",
    tokens_in=11,
    tokens_out=22,
    cost=0.25,
    duration_ms=1700,
  )
}

///|
/// 假想实现二：第三方 CLI Agent（走本地进程，元数据另一套）。
struct ThirdPartyCliAgent {
  label : String
}

///|
fn ThirdPartyCliAgent::new() -> ThirdPartyCliAgent {
  { label: "third-party-cli", }
}

///|
impl @executor.Executor for ThirdPartyCliAgent with fn name(self) -> String {
  self.label
}

///|
impl @executor.Executor for ThirdPartyCliAgent with fn run(
  self,
  _task : @core.Task,
  ctx : @executor.ExecContext,
) -> @executor.ExecResult {
  // 只给必填项，其余用追加器补齐 —— 外部实现者不必知道内部字段布局
  @executor.ExecResult::ok(
    "CLI 已按提示词执行，工作目录 " + ctx.project_dir_of(),
    self.label,
  )
  .with_model("local-model-x")
  .with_duration_ms(30)
}

///|
/// 「一个调用点、两个实现」的写法：trait 方法用完全限定名 `@executor.Executor::run`
/// 取，实参换类型就行 —— 调用方代码不需要知道实现者是谁。
/// （不用 `Executor[_]` 偏特形写法：本工具链报 4099「trait 不是类型」+ 4041 偏特形
/// 不允许出现在顶层声明里。）

///|
fn acc_task() -> @core.Task {
  @core.Task::new(
    id="T-EXT",
    project_dir="/proj/ext",
    description="外部实现者要做的任务",
    created_at="2026-10-31T00:00:00Z",
  )
}

///|
test "I3/包外实现 Executor：读上下文、造结果、跑通同一条 trait 面" {
  let ctx = @executor.ExecContext::new(
    "/proj/ext", "T-EXT", "把 x 改成 y", "assignee-ext",
  )
  // ② 访问器在包外可用（这行编译不过 = 外部实现者撞的就是 readonly）
  assert_eq(ctx.task_id_of(), "T-EXT")
  assert_eq(ctx.project_dir_of(), "/proj/ext")
  assert_eq(ctx.description_of(), "把 x 改成 y")
  assert_eq(ctx.assignee_of(), "assignee-ext")
  let r = @executor.Executor::run(RemoteSandboxAgent::new(), acc_task(), ctx)
  assert_true(r.succeeded())
  assert_true(
    r.deliverable_of().contains("沙箱已执行"),
    msg=r.deliverable_of(),
  )
  assert_eq(r.model_of(), "sandbox-llm-1")
  assert_eq(r.duration_ms_of(), 1700)
  assert_eq(r.tokens_in_of(), 11)
  assert_eq(r.tokens_out_of(), 22)
  assert_eq(r.cost_of(), 0.25)
  assert_eq(r.error_msg_of(), "")
  // 结果可序列化 ⇒ 与内置执行器共用同一条成本/回执面
  assert_true(r.to_json().stringify().contains("sandbox-llm-1"))
}

///|
test "I3/同一调用点派发第二个实现（替换的是实现，不是调用方代码）" {
  let ctx = @executor.ExecContext::new(
    "/proj/other", "T-EXT2", "另一个任务", "assignee-2",
  )
  let r = @executor.Executor::run(ThirdPartyCliAgent::new(), acc_task(), ctx)
  assert_true(r.succeeded())
  assert_eq(r.executor_of(), "third-party-cli")
  assert_eq(r.model_of(), "local-model-x")
  assert_eq(r.duration_ms_of(), 30)
  // 未显式给的元数据必须还是默认值，不能是脏的
  assert_eq(r.tokens_in_of(), 0)
  assert_eq(r.cost_of(), 0.0)
  assert_true(
    r.deliverable_of().contains("/proj/other"),
    msg=r.deliverable_of(),
  )
}

///|
test "I3/失败结果也能在包外构造并带着原因（成本面与回执面同源）" {
  let f = @executor.ExecResult::fail(
    "沙箱不可达：NOT_EXECUTABLE", "remote-sandbox",
  )
  assert_true(!f.succeeded())
  assert_true(f.error_msg_of().contains("NOT_EXECUTABLE"))
  assert_eq(f.deliverable_of(), "")
}
