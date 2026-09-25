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
