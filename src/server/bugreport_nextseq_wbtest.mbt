///|
/// bugreport_nextseq_wbtest.mbt —— `bug_next_seq` 编号分配锁（BUG-370 出路③ 收尾）。
/// 为什么是 wbtest：`bug_next_seq` 是私有 fn，黑盒拿不到。
/// 病灶（BUG-370 ③）：写侧 ID 分配若取「首次空闲 / 上次缓存」，账本里两条同号条目
/// （BUG-183/192 串号事故）之外还会再撞——分配必须取「现有条目最大 BUG-n + 1」。
/// 实现侧 max+1 已在（BUG-217 时代落地），本文件补上账本 ③ 点名的那格白盒锁：
/// 「同一棵账本连报两条不同缺陷 ⇒ 编号必须不同」+ 串号账本 / 乱序账本 / 提及不计数 各一格。
test "bn_01_empty_ledger_starts_at_1" {
  assert_true(bug_next_seq("") == 1)
  assert_true(bug_next_seq("没有任何条目的账本\n") == 1)
}

///|
test "bn_02_single_header_max_plus_1" {
  let ledger = "## BUG-7 [2026-10-21T00:00:00Z] [low] OPEN\n- summary: x\n"
  assert_true(bug_next_seq(ledger) == 8)
}

///|
test "bn_03_max_wins_unordered" {
  // 乱序账本：小号在后也要取最大（首次空闲会提前复用 4）
  let ledger = [
    "## BUG-3 [t] [low] OPEN", "## BUG-41 [t] [low] FIXED", "## BUG-12 [t] [low] OPEN",
    "",
  ].join("\n")
  assert_true(bug_next_seq(ledger) == 42)
}

///|
test "bn_04_duplicate_numbers_still_max_plus_1" {
  // 串号账本（BUG-370 事故形状：同一编号两条不同缺陷）不参与首次空闲，仍取 max+1
  let ledger = [
    "## BUG-183 [t1] [high] FIXED", "## BUG-183 [t2] [high] FIXED", "## BUG-190 [t] [low] OPEN",
    "",
  ].join("\n")
  assert_true(bug_next_seq(ledger) == 191)
}

///|
test "bn_05_mention_and_indent" {
  // 正文提及 BUG-999 不是抬头，不计数；缩进的抬头（trim 后命中前缀）计数
  let ledger = [
    "参考 BUG-999 的教训见 logs", "  ## BUG-5 [t] [low] OPEN", "- 说一句 ## BUG-88 在行中",
    "",
  ].join("\n")
  assert_true(bug_next_seq(ledger) == 6)
}

///|
test "bn_06_consecutive_reports_never_collide" {
  // BUG-370 ③ 点名的那格：同一棵账本连报两条 ⇒ 两次分配必不同，且第二条严格递增
  let ledger0 = "## BUG-100 [t] [low] OPEN\n"
  let s1 = bug_next_seq(ledger0)
  let ledger1 = ledger0 + "## BUG-" + s1.to_string() + " [t] [low] OPEN\n"
  let s2 = bug_next_seq(ledger1)
  assert_true(s1 == 101)
  assert_true(s2 == 102)
  assert_true(s1 != s2)
}

///|
test "bn_07_overflow_sentinel_no_wild_number" {
  // 超长编号串走 bug_parse_int 溢出哨兵（阈值 break），不产出绕回乱数：
  // acc 到 999999999（9 位）后再遇数字位即 ≥2e8 break ⇒ next = 1_000_000_000（仍在 Int32 域内）
  let ledger = "## BUG-999999999999999999999999 [t] [low] OPEN\n"
  assert_true(bug_next_seq(ledger) == 1_000_000_000)
}
