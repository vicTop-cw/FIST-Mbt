///|
/// evolve_summary_line_wbtest.mbt —— evolve_summary_line score 钳制回归（R12-R4，BUG-216）。
/// 病灶：`(a.score * 1000.0).to_int()` 在 score > 2.1e6 或 NaN 时 panic。
/// 修复：显式 clamp 到 [0, 2_000_000]，NaN 或负值回退 0。
/// 需要 wbtest：`evolve_summary_line` 是包内私有 fn，黑盒拿不到。
fn art(score : Double) -> Artifact {
  {
    id: "a-1234",
    parent_id: None,
    goal: "测试",
    note: "测试",
    code: "",
    score,
    parts: Map([]),
    children: 0,
    created_at: "2026-10-11T00:00:00Z",
  }
}

///|
test "evolve_summary_line: 正常 score" {
  let line = evolve_summary_line(art(0.5))
  assert_true(line.contains("score=0.5"))
}

///|
test "evolve_summary_line: 极大 score 不 panic" {
  // 旧实现：score=3000000 → *1000=3e9 > 2^31 → panic
  let line = evolve_summary_line(art(3_000_000.0))
  // 新实现：clamp 到 2_000_000 → *1000=2e9 < 2^31 → 安全
  assert_true(line.contains("score="))
}

///|
test "evolve_summary_line: NaN score 不 panic" {
  // 用 0.0/0.0 产生 NaN（避免依赖 @double 包导入）
  let nan_val = 0.0 / 0.0
  let line = evolve_summary_line(art(nan_val))
  // NaN 回退 0
  assert_true(line.contains("score=0"))
}

///|
test "evolve_summary_line: 负 score 回退 0" {
  let line = evolve_summary_line(art(-1.0))
  assert_true(line.contains("score=0"))
}

///|
test "evolve_summary_line: 恰好阈值附近不 panic" {
  let line = evolve_summary_line(art(2_000_000.0))
  assert_true(line.contains("score="))
}
