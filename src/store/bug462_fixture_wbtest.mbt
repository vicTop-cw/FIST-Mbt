///|
/// BUG-462 自锁：唯一化生成器必须真的每次产出不同路径。
///
/// 辅助函数本体在 `bug462_fixtures.mbt`（**普通 .mbt 而非 _wbtest**）——
/// 因为它要同时被本包的黑盒测试（`*_test.mbt`，只看 `pub`）与白盒测试（`*_wbtest.mbt`）调用。
/// 放在 `_wbtest.mbt` 里黑盒测试就看不见（实测：`bug462_unique_db is unbound`）。

// ══════════════════════════════════════════════════════════════════════════
// 自锁：生成器必须真的每次不同
// ══════════════════════════════════════════════════════════════════════════

///|
/// 【B462-U1】同一 tag 连续取两次 ⇒ **路径必须不同**（否则「唯一化」是假的）。
///
/// 这是本文件最重要的锁：如果 `@env.rand` 拿不到熵、或将来有人把 token 简化成
/// 只含 now（同毫秒两次调用会撞），这一格立刻红。
test "b462_u1_unique_db_is_actually_unique" {
  let a = bug462_unique_db("same_tag")
  let b = bug462_unique_db("same_tag")
  if a == b {
    abort(
      "BUG-462 变异：两次取到同一路径 " +
      a +
      " —— 唯一性来源（@env.rand）失效了",
    )
  }
}

///|
/// 【B462-U2】路径必须落在 `temp/` 下且以 `.db` 结尾（**不往仓库根/产品数据目录泄漏**）。
test "b462_u2_unique_db_stays_under_temp" {
  let p = bug462_unique_db("loose/tag with spaces")
  assert_true(p.has_prefix("temp/"))
  assert_true(p.has_suffix(".db"))
  // 分隔符必须被消毒（否则 `temp/loose/tag...` 会落到子目录）
  if p.contains("loose/tag") {
    abort("BUG-462：tag 里的 `/` 没被消毒 — 路径 = " + p)
  }
}

///|
/// 【B462-U3】不同 tag ⇒ 路径当然不同（前缀可读性仍然保留）。
test "b462_u3_different_tags_differ" {
  let a = bug462_unique_db("alpha")
  let b = bug462_unique_db("beta")
  assert_true(a != b)
  assert_true(a.contains("alpha"))
  assert_true(b.contains("beta"))
}
