/// FIST-Mbt core: 八角色定义与权限矩阵。
/// 迁移自 FIST(Python) 的角色体系，用强类型把「谁能对谁做什么」编译期固定下来。

/// 八角色
pub enum Role {
  /// 人类指挥官（唯一拥有任务的最终主权）
  HumanSteward
  /// 任务编排/拆分管家的执行代理（对应 executor）
  Leader
  /// 作战信息搜集（searcher）
  Searcher
  /// 资源分配（allocator）
  Allocator
  /// 执行者（executor）
  Executor
  /// 验收者（verifier / omega-verify）
  Verifier
  /// 记录者（recorder / logger）
  Recorder
  /// 观测者（observer）
  Observer
} derive(Eq, Debug)

pub fn Role::to_string(self : Role) -> String {
  match self {
    HumanSteward => "human_steward"
    Leader => "leader"
    Searcher => "searcher"
    Allocator => "allocator"
    Executor => "executor"
    Verifier => "verifier"
    Recorder => "recorder"
    Observer => "observer"
  }
}

pub fn Role::from_string(s : String) -> Option[Role] {
  match s {
    "human_steward" => Some(HumanSteward)
    "leader" => Some(Leader)
    "searcher" => Some(Searcher)
    "allocator" => Some(Allocator)
    "executor" => Some(Executor)
    "verifier" => Some(Verifier)
    "recorder" => Some(Recorder)
    "observer" => Some(Observer)
    _ => None
  }
}

/// 角色职责说明
pub fn Role::description(self : Role) -> String {
  match self {
    HumanSteward => "人类指挥官：发布根任务、验收 ONLY、归档 ONLY，唯一主权"
    Leader => "领队：拆解任务、编排调度、把子任务分配给执行者"
    Searcher => "搜证：信息检索、可行性调研、为任务提供依据"
    Allocator => "资源分配：分配执行者与资源，保证负载可执行"
    Executor => "执行者：认领任务、动手实现、产出交付物"
    Verifier => "验收者：运行验证（omega-verify），必要时调用人类"
    Recorder => "记录者：日志、进度、档案记录（observability）"
    Observer => "观测者：只读看板、审计、权限追踪，不落子"
  }
}

/// —— 权限矩阵：role 是否可以执行 action ——
/// 这是 FIST 「任务主权/权限分离」原则（七条第 5 条衍生）的静态表达。
/// HumanSteward 拥有最高权限（唯一人类，可裁决一切）。

/// 每个任务的完整操作清单
pub enum Action {
  Publish         // 发布根任务
  Dispatch        // 分发/拆分
  Search          // 信息检索
  Allocate        // 分配执行者
  Claim           // 认领任务
  Execute         // 执行任务
  Submit          // 提交验收
  Verify          // 验收
  Complete        // 标记完成（人类 ONLY）
  Archive         // 归档（人类 ONLY）
  Reopen          // 重新打开
  Observe         // 只读查看
  ManageProject   // 项目管理
} derive(Eq, Debug)

/// 权限判定：Can(HumanSteward, 任意) = true；
/// 非人类角色只能做自己职责内的非破坏性动作。
pub fn can(role : Role, action : Action) -> Bool {
  match (role, action) {
    (HumanSteward, _) => true
    (Leader, Publish) => true
    (Leader, Dispatch) => true
    (Leader, Allocate) => true
    (Leader, Claim) => true
    (Leader, Execute) => true
    (Leader, Submit) => true
    (Leader, Observe) => true
    (Leader, ManageProject) => true
    (Searcher, Search) => true
    (Searcher, Observe) => true
    (Allocator, Allocate) => true
    (Allocator, Observe) => true
    (Executor, Claim) => true
    (Executor, Execute) => true
    (Executor, Submit) => true
    (Executor, Observe) => true
    (Verifier, Verify) => true
    (Verifier, Observe) => true
    (Recorder, Observe) => true
    (Observer, Observe) => true
    _ => false
  }
}

/// 权限校验函数（带可读错误消息）
pub fn ensure_can(role : Role, action : Action) -> Result[Unit, String] {
  if can(role, action) {
    Ok(())
  } else {
    Err(
      "权限不足: [\{role.to_string()}] 无权执行 [\{action.to_string()}]",
    )
  }
}

/// Action 可读名（供错误消息）
pub fn Action::to_string(self : Action) -> String {
  match self {
    Publish => "publish"
    Dispatch => "dispatch"
    Search => "search"
    Allocate => "allocate"
    Claim => "claim"
    Execute => "execute"
    Submit => "submit"
    Verify => "verify"
    Complete => "complete"
    Archive => "archive"
    Reopen => "reopen"
    Observe => "observe"
    ManageProject => "manage_project"
  }
}

/// 从字符串解析角色（MCP 参数用）
pub fn role_of(s : String) -> Result[Role, String] {
  match Role::from_string(s) {
    Some(r) => Ok(r)
    None => Err("未知角色: '\{s}'")
  }
}
