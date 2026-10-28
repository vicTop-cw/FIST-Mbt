///|
/// evolve_distill_ts_wbtest.mbt —— `distill_ts_part` 的唯一性锁（R149）。
///
/// 与 R148 修的 `lesson_ts_part` 是**同一份逻辑的副本**：同样用 `replace`（只替首次）
/// + 截 16 位（切掉秒的个位）。原注释还写「同一 now 蒸馏**同一目标**会得到同一 id」，
/// 但 id 实际是 `"principle-" + distill_ts_part(now)`，**不含 target** ——
/// 所以真实后果是**同一 10 秒窗口内、不同目标的两次蒸馏 id 相同** ⇒ upsert 后者覆盖前者。

///|
/// 锁 1：**秒级唯一** + 同一时刻幂等。
test "distill_ts_part_seconds_are_distinct" {
  let a = distill_ts_part("2026-10-28T12:34:56Z")
  let b = distill_ts_part("2026-10-28T12:34:59Z")
  let c = distill_ts_part("2026-10-28T12:34:50Z")
  assert_true(a != b)
  assert_true(a != c)
  assert_eq(distill_ts_part("2026-10-28T12:34:56Z"), a)
}

///|
/// 锁 2：**分隔符去干净**（`replace` 只替首次时本格必红：`202610-28T12.34:56Z`）。
test "distill_ts_part_separators_all_removed" {
  let p = distill_ts_part("2026-10-28T12:34:56Z")
  assert_true(!p.contains("-"))
  assert_true(!p.contains(":"))
  assert_true(!p.contains("T"))
  assert_true(p.has_prefix("20261028.12.34.56"))
}

///|
/// 锁 3：短串原样、空串不崩。
test "distill_ts_part_short_input" {
  assert_eq(distill_ts_part(""), "")
  assert_eq(distill_ts_part("2026-10-28"), "20261028")
}
