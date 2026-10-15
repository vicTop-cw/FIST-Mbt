///|
/// CAF P2d · 冷启动启发式（新增函数层，不改动 router_caf.mbt）
/// 设计文档：docs/2026-10-15-fist-mbt-caf-p2d-cold-start-design.md
/// 独立文件避免与并发 agent 的 router_caf.mbt WIP 冲突。

///|
/// 统计所有模型的 evidence 总数
fn evidence_total(stats : Array[CafModelStats]) -> Int {
  let mut total = 0
  for s in stats {
    total = total + s.total
  }
  total
}

///|
/// 从数组中删除指定索引元素（返回新数组）
fn remove_at(arr : Array[String], idx : Int) -> Array[String] {
  let mut out : Array[String] = []
  for i in 0..<arr.length() {
    if i != idx {
      out = out + [arr[i]]
    }
  }
  out
}

///|
/// 冷启动启发式：
/// 当记忆不足（stats 为空或 evidence_total < min_evidences）时，
/// 按 default_preference 排序候选（偏好在前的优先，偏好外的保持原序）。
/// 记忆充足时退化为 caf_soft_reorder（纯成功率/成本排序）。
/// preference 为空 → 行为与 caf_soft_reorder 完全一致（零回归）。
///
/// 零回归性质（P2d 验收标准 1）：
///   caf_soft_reorder_with_preference(candidates, [], [], _) == candidates
pub fn caf_soft_reorder_with_preference(
  candidates : Array[String],
  stats : Array[CafModelStats],
  default_preference : Array[String],
  min_evidences : Int,
) -> Array[String] {
  // 记忆充足 → 退化为 caf_soft_reorder
  if stats.length() > 0 && evidence_total(stats) >= min_evidences {
    return caf_soft_reorder(candidates, stats)
  }
  // 记忆不足 → 按偏好排序（偏好在前的优先），偏好外的保持原序
  if default_preference.length() == 0 {
    return candidates
  }
  let mut result : Array[String] = []
  let mut rest : Array[String] = candidates
  for pref in default_preference {
    // 找到 pref 在 rest 里的位置，取出并加入 result
    let mut idx = -1
    for i in 0..<rest.length() {
      if rest[i] == pref {
        idx = i
        break
      }
    }
    if idx >= 0 {
      result = result + [rest[idx]]
      rest = remove_at(rest, idx)
    }
  }
  // 剩下的按原序追加
  for r in rest {
    result = result + [r]
  }
  result
}

///|
/// 接线前置 · context 归一化（trim 首尾空白 + ASCII lowercase）。
///
/// 问题：`caf_feature_hash` 直接对 `context[i].to_int()` 做多项式 hash，**大小写与空白敏感**——
/// `"PYTHON"` / `"python"` / `"  python  "` 三个语义等价串会得到**完全不同**的 hash，
/// 进而落在 `knn_search` 的**不同编辑距离邻域**，导致同一类任务把记忆写进三条不相连的桶，
/// 记忆碎片化、命中率下降。
///
/// 契约：接线时用 `caf_feature_hash(caf_normalize_context(ctx))` 代替 `caf_feature_hash(ctx)`，
/// 使语义等价的输入收敛到同一 hash → 命中同一邻域。
///
/// 零回归性质：输入已归一化时 `caf_normalize_context` 是恒等（幂等）。
/// 空串与纯空白 → 空串（安全，不 panic）。
///
/// 设计文档：docs/2026-10-15-fist-mbt-caf-p2c-wiring-design.md §2.3（接线层归一化）。
pub fn caf_normalize_context(context : String) -> String {
  let len = context.length()
  let mut start = 0
  while start < len && is_ws_byte(context[start].to_int()) {
    start = start + 1
  }
  let mut end = len
  while end > start && is_ws_byte(context[end - 1].to_int()) {
    end = end - 1
  }
  let mut out : String = ""
  let mut i = start
  while i < end {
    out = out + to_lower_byte(context[i].to_int())
    i = i + 1
  }
  out
}

///|
fn is_ws_byte(b : Int) -> Bool {
  b == 32 || b == 9 || b == 10 || b == 13
}

///|
fn to_lower_byte(b : Int) -> String {
  let lc = if b >= 65 && b <= 90 { b + 32 } else { b }
  Char::from_int(lc).to_string()
}
