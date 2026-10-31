///|
/// evidence_acc_fix_test.mbt — 评委拒收项「自动修复三轮」的轮次预算锁。
/// 钉的是 `auto_repair(max_rounds=)` **真被消费**：以前 max_rounds 一路传到
/// batch_verify_fix 就没人读了（账本 BUG-354 出路 c 自述过「无轮次可迭代」），
/// 传 0 / 传 999 得到的都是同一个数 ⇒ 那个参数是装饰。

///|
/// 永不收敛的夹具：fixer 每轮都动手，verifier 每轮都不放行 ⇒ rounds_used 恰等于预算。
fn acc_never_fixed(n : Int32) -> @evidence.RepairOutcome {
  let specs = [
    @evidence.Spec::new(
      "S1",
      "坏指纹",
      @evidence.Severity::from_string("major"),
      "必须被修好",
    ).mark_failed("fingerprint 不匹配"),
  ]
  let fixer = fn(_s : @evidence.Spec) -> String? { Some("apply_fix[S1]") }
  let verifier = fn(_s : @evidence.Spec) -> Bool { false }
  @evidence.auto_repair(specs, fixer, verifier, max_rounds=n)
}

///|
test "I2/max_rounds 是真预算：0/1/3/999 各按夹紧后的轮数停下" {
  // 夹紧口径：下限 1（传 0 不许一轮都不跑，那样「修过了」这件事根本没法自证）、上限 10
  assert_eq(acc_never_fixed(0).rounds_used, 1)
  assert_eq(acc_never_fixed(1).rounds_used, 1)
  assert_eq(acc_never_fixed(3).rounds_used, 3)
  assert_eq(acc_never_fixed(999).rounds_used, 10)
  // 默认值仍是三轮（不传 = 既有语义零回归）
  let d = {
    let specs = [
      @evidence.Spec::new(
        "S1",
        "坏指纹",
        @evidence.Severity::from_string("major"),
        "必须被修好",
      ).mark_failed("fingerprint 不匹配"),
    ]
    @evidence.auto_repair(
      specs,
      fn(_s : @evidence.Spec) -> String? { Some("x") },
      fn(_s : @evidence.Spec) -> Bool { false },
    )
  }
  assert_eq(d.rounds_used, 3)
}

///|
test "I2/第一轮修不好的东西：预算 1 停在第 1 轮，预算 3 才走到第 2 轮修好" {
  // 这一格钉的是「下一轮在上一轮之上继续」而不是「同一招重放三次」：
  // fixer 第 1 次拒绝（修不动），第 2 次才动手 ⇒ 只有预算 ≥2 才可能收敛。
  let mk = fn() -> Array[@evidence.Spec] {
    [
      @evidence.Spec::new(
        "S2",
        "两轮才修好",
        @evidence.Severity::from_string("major"),
        "必须被修好",
      ).mark_failed("struct_missing"),
    ]
  }
  let slot = [0]
  let fixer = fn(_s : @evidence.Spec) -> String? {
    slot[0] = slot[0] + 1
    if slot[0] >= 2 {
      Some("apply_fix 第 2 轮落地")
    } else {
      None
    }
  }
  let verifier = fn(_s : @evidence.Spec) -> Bool { true }
  let r1 = @evidence.auto_repair(mk(), fixer, verifier, max_rounds=1)
  assert_eq(r1.rounds_used, 1)
  assert_true(!r1.ok)
  let slot2 = [0]
  let fixer2 = fn(_s : @evidence.Spec) -> String? {
    slot2[0] = slot2[0] + 1
    if slot2[0] >= 2 {
      Some("apply_fix 第 2 轮落地")
    } else {
      None
    }
  }
  let r3 = @evidence.auto_repair(mk(), fixer2, verifier, max_rounds=3)
  assert_eq(r3.rounds_used, 2)
  assert_true(r3.ok)
}
