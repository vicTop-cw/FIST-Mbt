/// engine_phi.mbt —— Phi Accrual 概率式故障检测（R89，Hayashibara et al. 2004 经典算法落地）。
///
/// 把看护语义升级：watchdog/heal 的"固定 timeout"升级为"按心跳间隔历史分布算怀疑度 φ"——
/// φ = -log10(P(心跳晚于 elapsed 到达))，P 由窗口内心跳间隔的均值 μ 与标准差 σ 建模：
///   - σ≈0：回退指数分布（P_after = e^(-elapsed/μ)）；
///   - 正态建模：z=(elapsed-μ)/σ，|z|≥3 用尾部渐近展开保精度（erf 近似在深尾部误差放大）。
/// φ ≥ threshold（默认 8，原论文口径）判 "suspect"（疑似宕机），否则 "healthy"；
/// 无间隔历史返回 "insufficient"，取值域外（负 elapsed / 非正间隔）返回 "rejected" 且不出结论。
/// 纯计算、无副作用、可复现。

///|
/// 牛顿法平方根（core 无 sqrt；20 次迭代足够收敛）。
fn sqrt_approx(x : Double) -> Double {
  if x <= 0.0 {
    return 0.0
  }
  let mut g = if x >= 1.0 { x } else { 1.0 }
  for _i = 0; _i < 20; _i = _i + 1 {
    g = (g + x / g) * 0.5
  }
  g
}

///|
/// 误差函数 erf（Abramowitz & Stegun 7.1.26 近似，|误差|<1.5e-7，x≥0 用）。
fn erf_approx(x : Double) -> Double {
  let p = 0.3275911
  let a1 = 0.254829592
  let a2 = -0.284496736
  let a3 = 1.421413741
  let a4 = -1.453152027
  let a5 = 1.061405429
  let t = 1.0 / (1.0 + p * x)
  let poly = ((((a5 * t + a4) * t + a3) * t + a2) * t + a1) * t
  1.0 - poly * @math.exp(-x * x)
}

///|
/// 标准正态右尾 Q(z) = P(Z > z) = Φ(-z)，z ≥ 0。
/// |z| < 3 走 erf（误差 1.5e-7 可忽略）；|z| ≥ 3 用渐近展开（erf 近似在深尾部会放大误差，
/// 渐近式相对误差在 z≥4 时 < 1e-3，φ 精度足够）。sqrt(2π)=2.5066282746310002。
fn normal_tail_q(z : Double) -> Double {
  if z < 0.0 {
    // 对称性（防御；调用方保证 z≥0）
    return 1.0 - normal_tail_q(-z)
  }
  if z >= 3.0 {
    let z2 = z * z
    let base = @math.exp(-z2 * 0.5) / (z * 2.5066282746310002)
    base * (1.0 - 1.0 / z2 + 3.0 / (z2 * z2))
  } else {
    // Φ(-z) = 0.5 * (1 - erf(z/√2))，√2 = 1.4142135623730951
    0.5 * (1.0 - erf_approx(z / 1.4142135623730951))
  }
}

///|
/// JSON 秒数 → Int 的**安全**转换（BUG-26 的上溢落点）：`Double::to_int()` 对超出 Int 域的
/// 值（如实测的 1e300）**饱和**成 2147483647，随后仍被当成均值继续算 φ；带小数的值被截断、
/// 非数字元素被整条丢掉。这里把这三类失真一律收成 None，让调用面在转换**之前**拒绝。
pub fn phi_coerce_seconds(v : Double) -> Int? {
  let int_max_d = 2147483647.0
  // v != v 抓 NaN；±inf 与 1e300 由范围比较抓（NaN 不参与大小比较，所以两条都要）。
  if v != v || v < -int_max_d || v > int_max_d {
    None
  } else {
    let n = v.to_int()
    if n.to_double() == v {
      Some(n)
    } else {
      None
    }
  }
}

///|
/// 取值域校验（BUG-26）：φ 的建模输入一旦失真（负 elapsed、非正间隔），输出仍是格式完好的
/// healthy/suspect——看起来是结论，实际是溢出后的算术。把「不可建模」提到结论之前。
/// 返回拒绝原因（空串=通过）。间隔的**上溢**发生在 JSON→Int 的转换点，由调用面拦。
pub fn phi_domain_error(intervals : Array[Int], elapsed : Int) -> String {
  if elapsed < 0 {
    return "elapsed 为负（\{elapsed.to_string()}s）：时钟回拨或心跳尚未到达，无 elapsed 可建模"
  }
  let mut bad = 0
  for iv in intervals {
    if iv <= 0 {
      bad = bad + 1
    }
  }
  if bad > 0 {
    return "intervals 含 \{bad.to_string()} 个非正间隔：φ 按间隔建模，0/负秒数不是观测值"
  }
  ""
}

///|
/// Phi Accrual 主计算：给定心跳间隔历史 intervals（秒）与自上次心跳起的 elapsed（秒），
/// 返回 { verdict: rejected|insufficient|healthy|suspect, phi, mean, stddev, window, threshold, note, basis }。
/// threshold 默认 8（原论文口径）；窗口默认取最近全部传入间隔（≤1000 条）。
/// 取值域外返回 `rejected` 且**不出结论**——以前这类输入带着饱和后的均值照样回 healthy，
/// 看护据此不 heal，任务永久卡在已领取。
pub fn phi_accrual(
  intervals : Array[Int],
  elapsed : Int,
  threshold? : Int = 8,
) -> Json {
  let dom = phi_domain_error(intervals, elapsed)
  if dom != "" {
    return Json::object({
      "verdict": Json::string("rejected"),
      "phi": Json::number(0.0),
      "window": Json::number(intervals.length().to_double()),
      "threshold": Json::number(threshold.to_double()),
      "note": Json::string(dom),
      "basis": Json::string(
        "取值域门（BUG-26）：判活结论要求 elapsed≥0 且每个间隔为正整数秒",
      ),
    })
  }
  let win = intervals.length()
  if win <= 0 {
    return Json::object({
      "verdict": Json::string("insufficient"),
      "phi": Json::number(0.0),
      "note": Json::string(
        "无心跳间隔历史，无法建模分布（请先上报至少一次间隔）",
      ),
      "basis": Json::string(
        "Phi Accrual（Hayashibara 2004）：φ=-log10(P(心跳晚于 elapsed 到达))",
      ),
    })
  }
  // 窗口均值 μ
  let mut sum = 0.0
  for iv in intervals {
    sum = sum + iv.to_double()
  }
  let mu = sum / win.to_double()
  // 样本方差（Bessel 校正，n>1）→ σ
  let mut sq = 0.0
  for iv in intervals {
    let d = iv.to_double() - mu
    sq = sq + d * d
  }
  let variance = if win <= 1 { 0.0 } else { sq / (win - 1).to_double() }
  let sigma = sqrt_approx(variance)
  let elapsed_d = elapsed.to_double()
  let (phi, note) = if sigma <= 0.000000001 {
    // σ≈0：指数分布回退 P_after = e^(-elapsed/μ)，φ = elapsed/μ × log10(e)
    if mu <= 0.0 {
      (0.0, "窗口均值非正，无法建模（间隔须为正）")
    } else {
      let phi_e = elapsed_d / mu * 0.4342944819032518
      (phi_e, "σ≈0，指数分布回退")
    }
  } else {
    // 正态建模：z=(elapsed-μ)/σ；elapsed<μ（比均值更频繁）→ Q 接近 1，φ≈0
    let z = (elapsed_d - mu) / sigma
    let q = if z >= 0.0 { normal_tail_q(z) } else { 1.0 - normal_tail_q(-z) }
    let phi_n = if q <= 0.0 {
      999.0 // 尾部下溢（极端超时）→ 饱和高怀疑
    } else {
      let mut v = -@math.log10(q)
      if v < 0.0 {
        v = 0.0
      }
      v
    }
    (
      phi_n,
      "正态建模（均值 μ=" +
      mu.to_string() +
      "s，σ=" +
      sigma.to_string() +
      "s）",
    )
  }
  let verdict = if phi >= threshold.to_double() { "suspect" } else { "healthy" }
  Json::object({
    "verdict": Json::string(verdict),
    "phi": Json::number(phi),
    "mean": Json::number(mu),
    "stddev": Json::number(sigma),
    "window": Json::number(win.to_double()),
    "threshold": Json::number(threshold.to_double()),
    "note": Json::string(note),
    "basis": Json::string(
      "Phi Accrual（Hayashibara 2004）：φ=-log10(P(心跳晚于 elapsed 到达))；φ≥threshold 判 suspect（R89）",
    ),
  })
}
