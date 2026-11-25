/// guard_wbtest.mbt —— T0r56 guard 纯裁决的白盒锁。
///
/// 判例-29：机制格 ≠ 实现路径格——`guard_decision` 是双阈值熔断的真源，
/// 这里逐格钉住它的语义（含边界与反例），IO 外壳改坏纯逻辑时这里必须红。

///|
/// 构造任务做幂等键判定的辅助
fn lr_guard_task(id : String) -> @core.Task {
  @core.Task::new(
    id~,
    project_dir=".",
    ns="default",
    description="guard wbtest",
  )
}

///|
test "guard: 预算超限即拦（D2=C 双阈值之一）" {
  // used 11 > limit 10 → 拦
  let (ok, reasons) = guard_decision(11L, 10L, 0, 10, 30, 3)
  if ok {
    abort("预算超限应拦截")
  }
  if reasons.length() != 1 || !reasons[0].contains("预算超限") {
    abort("预算原因缺失：\{reasons}")
  }
  // 边界：恰在阈值上（used == limit）不拦——严格大于才拦
  let (ok_eq, _) = guard_decision(10L, 10L, 0, 10, 30, 3)
  if !ok_eq {
    abort("恰在预算阈值上不应拦截")
  }
}

///|
test "guard: 未设预算（limit<=0）该阈值不参与裁决" {
  let (ok, _) = guard_decision(999999L, 0L, 0, 0, 30, 3)
  if !ok {
    abort("limit=0 表示未设预算，不应拦截")
  }
}

///|
test "guard: 失败比例超阈即拦 + 最小样本门（D2=C 另一阈值）" {
  // 4/10=40% > 30% → 拦
  let (ok, reasons) = guard_decision(0L, 0L, 4, 10, 30, 3)
  if ok {
    abort("失败比例超阈应拦截")
  }
  if reasons.length() != 1 || !reasons[0].contains("失败比例超阈") {
    abort("比例原因缺失：\{reasons}")
  }
  // 边界：3/10=30% 恰在阈值上不拦（严格大于）
  let (ok_eq, _) = guard_decision(0L, 0L, 3, 10, 30, 3)
  if !ok_eq {
    abort("恰在比例阈值上不应拦截")
  }
  // 样本不足：total < min_samples 时比例阈值不启用（防起步即熔断）
  let (ok_few, _) = guard_decision(0L, 0L, 2, 2, 30, 3)
  if !ok_few {
    abort("样本不足时不应按比例拦截")
  }
}

///|
test "guard: 双阈值同爆给两条原因（或关系，任一超限即拦）" {
  let (ok, reasons) = guard_decision(50L, 10L, 9, 10, 30, 3)
  if ok || reasons.length() != 2 {
    abort("双超限应给两条原因：\{reasons}")
  }
}

///|
test "guard: 幂等键任务内去重（D3=A，复用 core 单真源）" {
  let t = lr_guard_task("Tg1")
  let (t1, added1) = t.idempotency_add("step-1", "u1")
  if !added1 {
    abort("新键应登记为新增")
  }
  if !t1.has_idempotency_key("step-1") {
    abort("登记后应能命中")
  }
  let (_, added2) = t1.idempotency_add("step-1", "u2")
  if added2 {
    abort("同任务内重复键不应二次登记（D3=A 去重）")
  }
  // 键的作用域是任务内：另一个任务的同名键不受影响
  let t2 = lr_guard_task("Tg2")
  let (_, added3) = t2.idempotency_add("step-1", "u3")
  if !added3 {
    abort("跨任务同名键应各自独立（D3=A 任务内作用域）")
  }
}

///|
test "guard: failure_ratio_pct 边界（total<=0 返回 0、向下取整）" {
  if failure_ratio_pct(0, 0) != 0 {
    abort("无样本比例应为 0")
  }
  if failure_ratio_pct(1, 3) != 33 {
    abort("向下取整：1/3 应为 33")
  }
}
