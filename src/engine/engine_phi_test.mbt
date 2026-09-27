/// engine_phi_test.mbt —— Phi Accrual 概率式故障检测（R89）测试。
/// 覆盖：σ=0 指数回退（固定间隔，elapsed 小=健康 / 大=怀疑）/ 正态建模（z=5 健康 / z=6 怀疑）/
/// 单调性 + 无历史 insufficient。

///|
test "phi_accrual：σ=0 指数回退——固定间隔 5s，elapsed 5s 健康 / 100s 怀疑" {
  // φ = elapsed/μ × log10(e)：elapsed=5 → 0.434 < 8 健康；elapsed=100 → 8.686 > 8 怀疑
  let j1 = @engine.phi_accrual([5, 5, 5], 5)
  match j1.value("verdict") {
    Some(String(v)) => assert_eq(v, "healthy")
    _ => abort("j1 verdict 缺失: " + j1.stringify())
  }
  match j1.value("phi") {
    Some(Number(n, ..)) =>
      if n - 0.434 > 0.01 || n - 0.434 < -0.01 {
        abort("j1 phi 应≈0.434: " + j1.stringify())
      }
    _ => abort("j1 phi 缺失: " + j1.stringify())
  }
  let j2 = @engine.phi_accrual([5, 5, 5], 100)
  match j2.value("verdict") {
    Some(String(v)) => assert_eq(v, "suspect")
    _ => abort("j2 verdict 应为 suspect: " + j2.stringify())
  }
  match j2.value("phi") {
    Some(Number(n, ..)) =>
      if n - 8.686 > 0.01 || n - 8.686 < -0.01 {
        abort("j2 phi 应≈8.686: " + j2.stringify())
      }
    _ => abort("j2 phi 缺失: " + j2.stringify())
  }
}

///|
test "phi_accrual：正态建模——均值 10s σ≈3.54，z=5 健康(φ≈6.5) / z=6 怀疑(φ≈9.0)" {
  // intervals [5,10,15,10,10] → μ=10，样本方差 50/4=12.5，σ≈3.5355
  let ints = [5, 10, 15, 10, 10]
  // elapsed = 10 + 5σ ≈ 27.68 → z=5 → φ≈6.54 < 8 健康
  let j1 = @engine.phi_accrual(ints, 27)
  match j1.value("verdict") {
    Some(String(v)) => assert_eq(v, "healthy")
    _ => abort("j1 verdict 应为 healthy: " + j1.stringify())
  }
  match j1.value("phi") {
    Some(Number(n, ..)) =>
      if n < 5.5 || n > 7.5 {
        abort("j1 phi 应在 5.5..7.5: " + j1.stringify())
      }
    _ => abort("j1 phi 缺失: " + j1.stringify())
  }
  // elapsed = 10 + 6σ ≈ 31.21 → z=6 → φ≈9.0 > 8 怀疑
  let j2 = @engine.phi_accrual(ints, 31)
  match j2.value("verdict") {
    Some(String(v)) => assert_eq(v, "suspect")
    _ => abort("j2 verdict 应为 suspect: " + j2.stringify())
  }
  match j2.value("phi") {
    Some(Number(n, ..)) =>
      if n < 8.5 || n > 10.0 {
        abort("j2 phi 应在 8.5..10.0: " + j2.stringify())
      }
    _ => abort("j2 phi 缺失: " + j2.stringify())
  }
  // mean/stddev 自洽
  match j1.value("mean") {
    Some(Number(n, ..)) =>
      if n - 10.0 > 0.000001 || n - 10.0 < -0.000001 {
        abort("mean 应为 10: " + j1.stringify())
      }
    _ => abort("mean 缺失: " + j1.stringify())
  }
}

///|
test "phi_accrual：单调性——elapsed 越大 φ 越大；无历史 = insufficient" {
  let ints = [5, 10, 15, 10, 10]
  let j1 = @engine.phi_accrual(ints, 15)
  let j2 = @engine.phi_accrual(ints, 25)
  let phi1 = match j1.value("phi") {
    Some(Number(n, ..)) => n
    _ => abort("phi1 缺失: " + j1.stringify())
  }
  let phi2 = match j2.value("phi") {
    Some(Number(n, ..)) => n
    _ => abort("phi2 缺失: " + j2.stringify())
  }
  if not(phi2 > phi1) {
    abort(
      "φ 应随 elapsed 单调增: " +
      phi1.to_string() +
      " vs " +
      phi2.to_string(),
    )
  }
  // 无历史 → insufficient
  let j0 = @engine.phi_accrual([], 10)
  match j0.value("verdict") {
    Some(String(v)) => assert_eq(v, "insufficient")
    _ => abort("j0 verdict 应为 insufficient: " + j0.stringify())
  }
}

///|
/// BUG-26 取值域门：缺数据的输入**不得**产出一条格式完好的结论。
/// 旧实现拿到 elapsed=-1 会算出 φ≈-2e-10 然后判 healthy，拿到 1e300 的间隔会把均值
/// 饱和成 2147483647 继续建模——看护据此"不 heal"，任务永久卡在已领取。
/// 成对：① 违例输入必被判 rejected 且不产 mean/stddev；② 合法输入的旧结论不得变。
test "BUG-26：phi_accrual 取值域外返回 rejected 且不出结论" {
  let j = @engine.phi_accrual([5, 5, 5], -1)
  match j.value("verdict") {
    Some(String(v)) => assert_eq(v, "rejected")
    _ => abort("负 elapsed 未走拒绝路径: " + j.stringify())
  }
  // 拒绝时必须不伪造统计量（有 mean 就等于"用溢出后的算术冒充结论"）
  assert_true(j.value("mean") is None)
  assert_true(j.value("stddev") is None)
  match j.value("note") {
    Some(String(n)) => assert_true(n.contains("elapsed"))
    _ => abort("拒绝原因没点名 elapsed: " + j.stringify())
  }
  // 非正间隔同样要拒（0 不是观测值）
  let j2 = @engine.phi_accrual([5, 0, 5], 100)
  match j2.value("verdict") {
    Some(String(v)) => assert_eq(v, "rejected")
    _ => abort("非正间隔未走拒绝路径: " + j2.stringify())
  }
  // 正向对照：合法输入的判定与 BUG-26 之前逐字一致（这条门不得顺手改坏健康路径）
  let j3 = @engine.phi_accrual([5, 5, 5], 100)
  match j3.value("verdict") {
    Some(String(v)) => assert_eq(v, "suspect")
    _ => abort("合法输入被误拒: " + j3.stringify())
  }
  let j4 = @engine.phi_accrual([5, 5, 5], 5)
  match j4.value("verdict") {
    Some(String(v)) => assert_eq(v, "healthy")
    _ => abort("合法健康输入被误拒: " + j4.stringify())
  }
  // 空历史仍是 insufficient（拒绝门不得把它吞成 rejected）
  let j5 = @engine.phi_accrual([], 100)
  match j5.value("verdict") {
    Some(String(v)) => assert_eq(v, "insufficient")
    _ => abort("空历史应 insufficient: " + j5.stringify())
  }
}

///|
/// BUG-26 的上溢落点在 JSON→Int 的转换：`Double::to_int()` 对 1e300 **饱和**成
/// 2147483647、对 1.5 **截断**成 1。phi_coerce_seconds 把两类都收成 None。
test "BUG-26：phi_coerce_seconds 拒绝饱和/截断，接受合法秒数" {
  // 2^63 作上溢样本：MoonBit 不认 1e300 这类科学字面量，十进制大数等价（都越出 Int 域）
  assert_true(@engine.phi_coerce_seconds(9223372036854775808.0) is None)
  assert_true(@engine.phi_coerce_seconds(-9223372036854775808.0) is None)
  assert_true(@engine.phi_coerce_seconds(1.5) is None)
  assert_true(@engine.phi_coerce_seconds(2147483648.0) is None)
  match @engine.phi_coerce_seconds(2147483647.0) {
    Some(v) => assert_eq(v, 2147483647)
    None => abort("Int 上界本身必须可取")
  }
  match @engine.phi_coerce_seconds(60.0) {
    Some(v) => assert_eq(v, 60)
    None => abort("合法整数秒被误拒")
  }
}
