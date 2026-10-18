///|
/// display/rank_test.mbt —— 军衔体系展示层测试。
/// 真源：docs/2026-10-12-fist-mbt-web-dashboard-plan.md §8.1「军衔体系（完整 *长 总表）」。

///|
test "rank_of 全档位映射（L=0 → 司令 … L=7 → 排长）" {
  let expect = [
    "司令", "军长", "师长", "旅长", "团长", "营长", "连长", "排长",
  ]
  for i = 0; i < officer_levels(); i = i + 1 {
    assert_eq(rank_of(i), expect[i])
  }
}

///|
test "rank_of 越界回退士兵（L<0 与 L>=8）" {
  assert_eq(rank_of(-1), soldier_rank())
  assert_eq(rank_of(8), soldier_rank())
  assert_eq(rank_of(99), soldier_rank())
}

///|
test "role_label 协议角色映射" {
  assert_eq(role_label("HumanSteward", 0), marshal_rank())
  assert_eq(role_label("Reminder", 3), commissar_rank())
  assert_eq(role_label("Executor", 1), soldier_rank())
  assert_eq(role_label("Leader", 0), "司令")
  assert_eq(role_label("Leader", 3), "旅长")
  assert_eq(role_label("Leader", 7), "排长")
  // 未知角色泄漏为士兵（防未登记角色泄漏军衔）。
  assert_eq(role_label("Searcher", 0), soldier_rank())
  assert_eq(role_label("Verifier", 2), soldier_rank())
  assert_eq(role_label("Recorder", 5), soldier_rank())
}

///|
test "leaf_label 叶子恒为士兵（无论层级）" {
  assert_eq(leaf_label(0), soldier_rank())
  assert_eq(leaf_label(3), soldier_rank())
  assert_eq(leaf_label(7), soldier_rank())
  assert_eq(leaf_label(99), soldier_rank())
}

///|
test "is_officer 边界" {
  assert_eq(is_officer(0), true)
  assert_eq(is_officer(7), true)
  assert_eq(is_officer(-1), false)
  assert_eq(is_officer(8), false)
  assert_eq(is_officer(99), false)
}

///|
test "officer_table 长度与档位数一致" {
  assert_eq(officer_table().length(), officer_levels())
}

///|
test "root depth=3 实际生效 4 档（司令→军长→师长→士兵）" {
  // docs 定级规则：默认 root depth=3 → L=0 司令, L=1 军长, L=2 师长, 叶子=士兵。
  assert_eq(rank_of(0), "司令")
  assert_eq(rank_of(1), "军长")
  assert_eq(rank_of(2), "师长")
  assert_eq(leaf_label(3), soldier_rank())
  // 旅长及以下（L>=3）在当前默认 depth 下是占位档，但 rank_of 已定义好。
  assert_eq(rank_of(3), "旅长")
  assert_eq(rank_of(4), "团长")
  assert_eq(rank_of(5), "营长")
  assert_eq(rank_of(6), "连长")
  assert_eq(rank_of(7), "排长")
}

///|
test "rank_of 幂等（同一层级两次调用给同一军衔）" {
  for i = 0; i < officer_levels(); i = i + 1 {
    assert_eq(rank_of(i), rank_of(i))
  }
}

///|
test "officer_table 完整含 8 档军衔名" {
  let tbl = officer_table()
  assert_eq(tbl[0], "司令")
  assert_eq(tbl[7], "排长")
}
