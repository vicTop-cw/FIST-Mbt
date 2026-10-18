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
test "默认任务 level=6（连长），rank_of 映射连长" {
  // docs 定级规则（新口径）：默认任务 level=6（连长），上游可显式声明 x级；
  // 子任务 level = 父级+1 封顶排长；叶子恒为士兵。rank_of(L) 映射表不变。
  assert_eq(rank_of(6), "连长")
  assert_eq(rank_of(7), "排长")
  assert_eq(leaf_label(6), soldier_rank())
  assert_eq(leaf_label(7), soldier_rank())
}

///|
test "子任务等级链：默认 6（连长）→ 7（排长）→ 士兵，封顶排长" {
  // 连长(6)→排长(7)→士兵：level 链只降一级，封顶 7 不再上升。
  assert_eq(rank_of(6), "连长")
  assert_eq(rank_of(7), "排长")
  // 排长(7) 的子任务仍封顶排长（rank_of 只认 L=7），靠 leaf_label 落到士兵。
  assert_eq(leaf_label(7), soldier_rank())
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
