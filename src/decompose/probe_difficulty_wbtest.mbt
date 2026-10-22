///|
/// BUG-172 回归：split_n=4 时 "难" 档不可达（原 third*2=4 与 pos 上限重合）。
/// 修正后 split_n>=3 的三档（易/中/难）都应各自可达。
test "difficulty_label_all_tiers_reachable" {
  for split_n in 3..<=6 {
    let mut has_easy = false
    let mut has_mid = false
    let mut has_hard = false
    for idx in 1..<=split_n {
      let l = difficulty_label(idx, split_n)
      match l {
        "易" => has_easy = true
        "中" => has_mid = true
        "难" => has_hard = true
        _ => ()
      }
    }
    if !has_easy || !has_mid || !has_hard {
      fail(
        "split_n=\{split_n} 应产出三档(易/中/难)，实收 easy=\{has_easy} mid=\{has_mid} hard=\{has_hard}",
      )
    }
  }
}

///|
/// BUG-172 回归：整段仍单调不减（前易后难），档位序只升不降。
/// 档序复刻黑盒测试 decompose_quickcheck_test.mbt 的 diff_order（whitebox 不可见）。
fn local_diff_order(s : String) -> Int32 {
  match s {
    "易" => 0
    "中" => 1
    "难" => 2
    _ => 99
  }
}

///|
test "difficulty_label_monotonic" {
  for split_n in 1..<=6 {
    for j = 1; j < split_n; j = j + 1 {
      if local_diff_order(difficulty_label(j, split_n)) >
        local_diff_order(difficulty_label(j + 1, split_n)) {
        fail("split_n=\{split_n} idx=\{j} 难度下降")
      }
    }
  }
}
