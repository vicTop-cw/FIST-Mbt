/// hat_divergence.mbt —— HexaMind 六元自驱决策 · 分歧提取（纯计算，零 LLM 自评）
///
/// 三类分歧，**程序化提取**，不等任何 LLM 说"我们分歧了"：
///   · verdict_conflict：两元结论直接对冲（pass vs reject，双方都不弃权）——最高严重度 3。
///   · confidence_gap：两元置信度落差 ≥ 0.5，且结论相同——同向但底气差，严重度 2。
///   · evidence_mismatch：两元产出条目词法重合度 < 0.25（各说各话）——严重度 1。
///
/// 词法重合度用 Jaccard（复用 @evolve 同思路），大小写不敏感、按词切分、去重。
/// 纯计算只读；未知六元的报告直接跳过（不崩溃）。

///|
/// 一条分歧。
pub struct Divergence {
  kind : String
  // verdict_conflict | confidence_gap | evidence_mismatch
  left : String
  // 六元代号 A
  right : String
  // 六元代号 B
  detail : String
  // 人类可读说明
  severity : Int
  // 1..3，3 最严重（阻止收敛）
}

///|
/// 从一组报告里提取全部两两分歧（i<j，跳过 abstain，去重保序）。
pub fn extract_divergences(reports : Array[HatReport]) -> Array[Divergence] {
  let out : Array[Divergence] = []
  let n = reports.length()
  for i = 0; i < n; i = i + 1 {
    let a = reports[i]
    if a.verdict == "abstain" {
      continue
    }
    for j = i + 1; j < n; j = j + 1 {
      let b = reports[j]
      if b.verdict == "abstain" {
        continue
      }
      // 1) 结论对冲
      if a.verdict != b.verdict {
        out.push(
          divergence(
            "verdict_conflict",
            a.element_id,
            b.element_id,
            a.element_id +
            "=" +
            a.verdict +
            " 对冲 " +
            b.element_id +
            "=" +
            b.verdict,
            3,
          ),
        )
        continue
      }
      // 2) 置信度落差
      if abs_double(a.confidence - b.confidence) >= 0.5 {
        out.push(
          divergence(
            "confidence_gap",
            a.element_id,
            b.element_id,
            "置信度落差 " +
            a.confidence.to_string() +
            " vs " +
            b.confidence.to_string(),
            2,
          ),
        )
        continue
      }
      // 3) 论据路径差异（各说各话）
      let ov = lexical_overlap(a, b)
      if ov < 0.25 {
        out.push(
          divergence(
            "evidence_mismatch",
            a.element_id,
            b.element_id,
            "论据重合度 " + ov.to_string() + " < 0.25（各说各话）",
            1,
          ),
        )
        continue
      }
      ()
    }
  }
  out
}

///|
/// 构造一条分歧。**跨包构造必需**。
pub fn divergence(
  kind : String,
  left : String,
  right : String,
  detail : String,
  severity : Int,
) -> Divergence {
  { kind, left, right, detail, severity, }
}

///|
/// 只取高严重度（阻止收敛）的分歧：verdict_conflict。
pub fn blocking_divergences(ds : Array[Divergence]) -> Array[Divergence] {
  ds.filter(fn(d) { d.kind == "verdict_conflict" })
}

///|
/// 统计各类分歧数量。
pub fn count_by_kind(ds : Array[Divergence]) -> Map[String, Int] {
  let m : Map[String, Int] = Map([])
  for d in ds {
    let cur = match m.get(d.kind) {
      Some(v) => v
      None => 0
    }
    m.set(d.kind, cur + 1)
  }
  m
}

// ---------------------------------------------------------------------------
// 词法工具
// ---------------------------------------------------------------------------

///|
fn abs_double(v : Double) -> Double {
  if v < 0.0 {
    -v
  } else {
    v
  }
}

///|
/// 两元产出条目的词法重合度（Jaccard，把 outcomes 拼成一段文本再比）。
fn lexical_overlap(a : HatReport, b : HatReport) -> Double {
  let ta = word_set(a.outcomes)
  let tb = word_set(b.outcomes)
  if ta.is_empty() || tb.is_empty() {
    return 0.0
  }
  let mut inter = 0
  for w in ta {
    if tb.contains(w) {
      inter = inter + 1
    }
  }
  let union = ta.length() + tb.length() - inter
  if union == 0 {
    0.0
  } else {
    inter.to_double() / union.to_double()
  }
}

///|
/// 把 outcomes 拼成一段文本，切成小写去重词表。
fn word_set(items : Array[String]) -> Array[String] {
  let out : Array[String] = []
  for s in items {
    for w in s.to_lower().split(" ") {
      let t = w.trim().to_owned()
      if !t.is_empty() && !out.contains(t) {
        out.push(t)
      }
    }
  }
  out
}
