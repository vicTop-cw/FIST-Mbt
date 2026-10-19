/// fist-evidence: 验收证据引擎 - Spec 规格定义
///
/// Spec 描述一条可验证的验收标准：持有真实内容（不依赖外部 spec 注入），
/// 修复时用 apply_fix 逐项落地，杜绝"零修复"缺陷。

///|
/// 验收项严重级别
pub enum Severity {
  Blocker
  Major
  Minor
}

///|
/// 从字符串解析严重级别（测试/探针经工厂构造，规避跨包 variant 限制）
pub fn Severity::from_string(s : String) -> Severity {
  match s {
    "blocker" => Blocker
    "major" => Major
    _ => Minor
  }
}

///|
/// 修复轮次上限：验收反馈要求"自动修复三轮"
pub const MAX_FIX_ROUNDS : Int = 3

///|
/// 规格状态
pub enum SpecStatus {
  Pending
  Passed
  Fixed
  Failed
}

///|
/// Spec：一条验收标准
/// 与 omega 的 verify_single_spec 对齐，但本结构自带 spec 原文与修复策略，
/// 供 batch_verify_fix 真实执行修复而非转人工。
pub struct Spec {
  id : String
  title : String
  severity : Severity
  // 期望满足的条件（自然语言/断言描述原文，修复时作为依据）
  expectation : String
  // 实际观察到的失败详情（由 verify 或外部探针填充）
  failed_detail : String
  status : SpecStatus
  fixed_round : Int
}

///|
/// 构造一个待验证 Spec
pub fn Spec::new(
  id : String,
  title : String,
  severity : Severity,
  expectation : String,
) -> Spec {
  {
    id,
    title,
    severity,
    expectation,
    failed_detail: "",
    status: Pending,
    fixed_round: 0,
  }
}

///|
/// 标记为已通过
pub fn Spec::mark_passed(self : Spec) -> Spec {
  {
    id: self.id,
    title: self.title,
    severity: self.severity,
    expectation: self.expectation,
    failed_detail: "",
    status: Passed,
    fixed_round: self.fixed_round,
  }
}

///|
/// 标记为失败并记录失败详情
pub fn Spec::mark_failed(self : Spec, detail : String) -> Spec {
  {
    id: self.id,
    title: self.title,
    severity: self.severity,
    expectation: self.expectation,
    failed_detail: detail,
    status: Failed,
    fixed_round: self.fixed_round,
  }
}

///|
/// 是否通过（Passed 或 Fixed）
pub fn Spec::is_ok(self : Spec) -> Bool {
  match self.status {
    Passed => true
    Fixed => true
    _ => false
  }
}

///|
/// 是否可修复（当前为 Failed）
pub fn Spec::is_repairable(self : Spec) -> Bool {
  match self.status {
    Failed => true
    _ => false
  }
}

///|
/// 状态文本（用于报告/探针输出）
pub fn Spec::status_text(self : Spec) -> String {
  match self.status {
    Pending => "pending"
    Passed => "passed"
    Fixed => "fixed"
    Failed => "failed"
  }
}

///|
/// 单行摘要
pub fn Spec::summary(self : Spec) -> String {
  "spec[id=" +
  self.id +
  "] title=" +
  self.title +
  " status=" +
  self.status_text()
}
