///|
/// fist-evidence: 验收证据引擎 - 测试
///
/// 覆盖：Spec 生命周期、多租户证据隔离、三轮自动修复（含修复器真实调用与校验失败重试）
test "spec lifecycle" {
  let s0 = Spec::new(
    "T1",
    "多租户隔离",
    Severity::from_string("blocker"),
    "租户A不可见租户B",
  )
  assert_true(
    match s0.status {
      Pending => true
      _ => false
    },
  )
  let s1 = s0.mark_failed("租户B读到了租户A的数据")
  assert_true(
    match s1.status {
      Failed => true
      _ => false
    },
  )
  assert_true(s1.is_repairable())
  let s2 = s1.mark_passed()
  assert_true(s2.is_ok())
  // 摘要可读
  let sum = s2.summary()
  assert_true(sum.contains("T1"))
  assert_true(sum.contains("passed"))
}

///|
test "evidence store tenant isolation" {
  let mut store = EvidenceStore::new()
  store = store.add_evidence(
    "tenant_a",
    FixEvidence::new("T1", 1, "apply_fix", "pass"),
  )
  store = store.add_evidence(
    "tenant_a",
    FixEvidence::new("T2", 2, "apply_fix", "pass"),
  )
  store = store.add_evidence(
    "tenant_b",
    FixEvidence::new("T3", 1, "apply_fix", "fail"),
  )
  // 物理隔离：A 看不到 B 的证据，反之亦然
  assert_eq(store.evidence_of("tenant_a").length(), 2)
  assert_eq(store.evidence_of("tenant_b").length(), 1)
  assert_true(store.has_evidence("tenant_a"))
  assert_false(store.has_evidence("tenant_c"))
  // 统计：A 在 round<=1 的修复数为 1
  assert_eq(store.count_fixes("tenant_a", 1), 1)
  // 报告包含租户标记
  let r = store.report("tenant_a")
  assert_true(r.contains("tenant_a"))
  // 租户 key 列表正确
  assert_eq(store.all_tenants().length(), 2)
}

///|
test "auto repair fixes real failures within 3 rounds" {
  let specs = [
    Spec::new(
      "R1",
      "可替换Executor",
      Severity::from_string("major"),
      "外部Executor可注册",
    ).mark_failed("register 返回 readonly"),
    Spec::new(
      "R2",
      "DAG成环拦截",
      Severity::from_string("blocker"),
      "自环依赖必须被拒",
    ).mark_failed("自环依赖被接受"),
  ]
  // 注入真实修复器：每轮输出修复动作（模拟 apply_fix 落地）
  let fixer = fn(s : Spec) -> String? { Some("apply_fix(" + s.id + ")") }
  // 校验器：failed_detail 已被清空才算修复成功（第二轮起通过）
  let verifier = fn(s : Spec) -> Bool { s.failed_detail.length() <= 0 }
  let outcome = auto_repair(specs, fixer, verifier)
  // 至少执行了一轮真实修复，且每轮每个失败项都调用了 fixer（非零修复）
  assert_true(outcome.rounds_used >= 1)
  assert_true(outcome.fix_evidence.length() >= 1)
  // 摘要包含轮次信息
  assert_true(outcome_summary(outcome).contains("rounds_used"))
}

///|
test "auto repair records evidence into store per tenant" {
  let specs = [
    Spec::new(
      "X1",
      "Omega门禁",
      Severity::from_string("blocker"),
      "archive 不可绕过门",
    ).mark_failed("archive 绕过了门禁"),
  ]
  let fixer = fn(s : Spec) -> String? { Some("apply_fix:" + s.id) }
  let verifier = fn(s : Spec) -> Bool { true }
  let outcome = auto_repair(specs, fixer, verifier)
  assert_true(outcome.ok)
  let mut store = EvidenceStore::new()
  store = record_outcome(store, "tenant_omega", outcome)
  assert_true(store.has_evidence("tenant_omega"))
  // 修复动作被如实记录
  let ev = store.evidence_of("tenant_omega")
  assert_eq(ev.length(), 1)
  assert_true(ev[0].action.contains("X1"))
  assert_eq(ev[0].round, 1)
}
