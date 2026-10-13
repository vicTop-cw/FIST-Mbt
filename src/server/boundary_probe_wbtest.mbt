///|
/// 档4 boundary_probe 白盒锁：按规则类型路由 + 不同规则不同集 + confirmed 恒 false（不执行）

///|
test "bp_divide_zero_contains_y0" {
  let j = boundary_probe_by_code("divide-by-zero", "x / y")
  let s = j.stringify()
  assert_true(s.contains("y = 0"))
  assert_true(s.contains("divide"))
  assert_true(s.contains("suggestions"))
}

///|
test "bp_divide_negative_and_extreme" {
  let s = boundary_probe_by_code("divide-by-zero", "x / y").stringify()
  assert_true(s.contains("极大值"))
  assert_true(s.contains("负除数"))
}

///|
test "bp_string_index_contains_empty_and_huge" {
  let s = boundary_probe_by_code("string-index", "s[i]").stringify()
  assert_true(s.contains("空串"))
  assert_true(s.contains("1000000"))
  assert_true(s.contains("负下标"))
}

///|
test "bp_array_index_contains_boundary_index" {
  let s = boundary_probe_by_code("array-index", "a[i]").stringify()
  assert_true(s.contains("off-by-one"))
  assert_true(s.contains("越界"))
}

///|
test "bp_concurrency_contains_interleave" {
  let s = boundary_probe_by_code("race-condition", "x = x + 1").stringify()
  assert_true(s.contains("并发交错"))
  assert_true(s.contains("重入"))
  assert_true(s.contains("屏障"))
}

///|
test "bp_overflow_contains_int_extreme" {
  let s = boundary_probe_by_code("potential-overflow", "a + b").stringify()
  assert_true(s.contains("最大值"))
  assert_true(s.contains("最小值"))
}

///|
test "bp_json_injection_contains_meta_char" {
  let s = boundary_probe_by_code("json-injection", "s").stringify()
  assert_true(s.contains("元字符注入"))
  assert_true(s.contains("引号"))
}

///|
test "bp_path_traversal_contains_dotdot" {
  let s = boundary_probe_by_code("path-traversal", "open(p)").stringify()
  assert_true(s.contains("路径穿越"))
  assert_true(s.contains("绝对路径"))
}

///|
test "bp_unwrap_contains_none" {
  let s = boundary_probe_by_code("unsafe-unwrap", "x.unwrap()").stringify()
  assert_true(s.contains("None"))
  assert_true(s.contains("空集合"))
}

///|
test "bp_empty_match_contains_unknown_tag" {
  let s = boundary_probe_by_code("match-non-exhaustive", "match x { _ => () }").stringify()
  assert_true(s.contains("未知枚举变体"))
  assert_true(s.contains("空输入"))
}

///|
test "bp_unknown_rule_generic_fallback" {
  let s = boundary_probe_by_code("totally-unknown-rule", "code").stringify()
  assert_true(s.contains("通用边界"))
  assert_true(s.contains("非法"))
}

///|
test "bp_confirmed_always_false" {
  let j = boundary_probe_by_code("divide-by-zero", "x / y")
  let s = j.stringify()
  assert_true(s.contains("confirmed"))
  assert_true(s.contains("0"))
  assert_true(s.contains("confirmed_count"))
}

///|
test "bp_total_matches_suggestions" {
  let j = boundary_probe_by_code("divide-by-zero", "x / y")
  // 除零族固定 3 条建议
  assert_true(j.stringify().contains("\"total\":3"))
}

///|
test "bp_note_explicitly_non_executing" {
  let s = boundary_probe_by_code("divide-by-zero", "x / y").stringify()
  assert_true(s.contains("纯计算"))
  assert_true(s.contains("不执行"))
}

///|
test "bp_full_signature_includes_line_file" {
  let j = boundary_probe("divide-by-zero", "x / y", "42", "src/a.mbt")
  let s = j.stringify()
  assert_true(s.contains("\"line\":\"42\""))
  assert_true(s.contains("src/a.mbt"))
}
