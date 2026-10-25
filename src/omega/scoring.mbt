/// omega/scoring.mbt — Ω-spec 质量评分（P0：coverage / fingerprint_ok / schema_ok /
/// accuracy 分项 + 0..100 综合分），打通自进化闭环。
///
/// 输入：一条 Ω-spec JSON（见 spec.mbt 的格式注释）+ 可选的跑批结果（total / passed）。
/// 输出：ScoreResult（分项 + 综合分 + 判定 pass/fail），可 to_json。
///
/// 权重（总分 = 各分项 × 权重，满分 100）：
///   coverage      × 30   laws 中被 tests 至少覆盖 1 次的比例
///   fingerprint   × 30   fingerprint 校验通过（1 或 0）
///   schema        × 20   schema 校验通过（1 或 0）
///   accuracy      × 20   total==0 视为 0；否则 passed/total×100
///
/// 与既有 API 分工：
///   - spec.mbt 的 verify_fingerprint / validate_schema 负责**布尔判定**；
///   - 本模块做**分项评分 + 加权汇总**，输出连续分供自进化采样使用。

///|
/// 单条 spec 的评分结果。
struct ScoreResult {
  coverage : Double
  fingerprint_ok : Bool
  schema_ok : Bool
  accuracy : Double
  score : Double
  pass : Bool
}

///|
/// 把 ScoreResult 序列化成 Json（与 omega_verify 回执同形状）。
pub fn score_to_json(s : ScoreResult) -> Json {
  Json::object({
    "coverage": Json::number(s.coverage),
    "fingerprint_ok": Json::boolean(s.fingerprint_ok),
    "schema_ok": Json::boolean(s.schema_ok),
    "accuracy": Json::number(s.accuracy),
    "score": Json::number(s.score),
    "pass": Json::boolean(s.pass),
  })
}

///|
/// 计算 coverage：被 tests 至少覆盖 1 次的 laws 比例（0.0..1.0）。
/// laws 为空时返回 1.0（无法律可覆盖，视为完全覆盖）。
/// BUG-218：空 law 与单字符 law 不进分母也不计覆盖——`contains("")` 恒 true、
/// 单字符 law 在任意含该字母的 test 里都被误判为覆盖（实测 "a" 配 `{"name":"test1"}` 得 1.0）。
pub fn calc_coverage(laws : Array[String], tests : Json) -> Double {
  if laws.is_empty() {
    return 1.0
  }
  let test_arr : Array[Json] = match tests {
    Array(a) => a
    _ => []
  }
  let mut covered = 0
  let mut countable = 0
  for law in laws {
    if law.length() < 2 {
      // BUG-218：长度 < 2 的 law 无法用 substring 可靠判定覆盖（空串恒真 / 单字符误匹配），跳过。
      continue
    }
    countable = countable + 1
    for t in test_arr {
      let tstr = Json::stringify(t)
      if tstr.contains(law) {
        covered = covered + 1
        break
      }
    }
  }
  if countable <= 0 {
    // 全部 laws 都因过短被跳过：无可判定覆盖的 law，按"无法律可覆盖"处理（与 laws 空同语义）。
    1.0
  } else {
    covered.to_double() / countable.to_double()
  }
}

///|
/// 主评分入口。参数：
///   spec_json   已 parse 的 Ω-spec Json（缺字段会得 schema_ok=false）
///   total       跑批样本总数（0 表示未跑）
///   passed      跑批通过数
pub fn spec_scoring(spec : Json, total : Int32, passed : Int32) -> ScoreResult {
  // 从 spec 里取字段（缺省给空值）
  let laws : Array[String] = match jget(spec, "laws") {
    Some(Array(arr)) => {
      let out : Array[String] = []
      for a in arr {
        match a {
          String(s) => out.push(s)
          _ => ()
        }
      }
      out
    }
    _ => []
  }
  let tests : Json = match jget(spec, "tests") {
    Some(t) => t
    None => Json::null()
  }
  // fingerprint 校验：verify_fingerprint 返回 Ok(_) 即通过
  let fp_ok = match verify_fingerprint(spec) {
    Ok(_) => true
    Err(_) => false
  }
  // schema 校验：validate_schema 返回空数组即通过
  let schema_errs = validate_schema(spec)
  let schema_ok = schema_errs.is_empty()
  // coverage
  let coverage = calc_coverage(laws, tests)
  // accuracy
  let accuracy = if total <= 0 {
    0.0
  } else {
    passed.to_double() / total.to_double() * 100.0
  }
  // 加权
  let score = coverage * 30.0 +
    (if fp_ok { 30.0 } else { 0.0 }) +
    (if schema_ok { 20.0 } else { 0.0 }) +
    accuracy / 100.0 * 20.0
  // pass 门槛：accuracy 必须 100% 且 score >= 70（其余分项决定是否满分）
  let pass = accuracy >= 100.0 && score >= 70.0
  { coverage, fingerprint_ok: fp_ok, schema_ok, accuracy, score, pass, }
}

///|
/// 便捷入口：直接接 spec JSON 字符串。
pub fn spec_scoring_str(
  spec_str : String,
  total : Int32,
  passed : Int32,
) -> Json {
  let j : Json = @json.parse(spec_str) catch {
    _ =>
      return score_to_json({
        coverage: 0.0,
        fingerprint_ok: false,
        schema_ok: false,
        accuracy: 0.0,
        score: 0.0,
        pass: false,
      })
  }
  score_to_json(spec_scoring(j, total, passed))
}
