/// self_search_test.mbt —— 调研先行 / 自搜索模块测试
///
/// 覆盖：analyze 清洗与字段、判重、可移植性启发式、distill 去重+过滤+排序、
/// run_external_search 成功(mock注入) / 失败(未注入) 路径。
/// 全部确定性断言，无盘符/绝对路径，外部搜索用注入的 mock 验证。

///|
/// analyze 基础字段：trim 空白、机制触发可移植词，portable 应被启发式置 true。
test "self_search_analyze_fields" {
  let c = analyze_candidate(
    "  wrapper-lib  ", "  可移植封装库", "crate", "  exposes a reusable wrapper  ",
  )
  assert_eq(c.name, "wrapper-lib")
  assert_eq(c.title, "可移植封装库")
  assert_eq(c.source, "crate")
  assert_eq(c.mechanism, "exposes a reusable wrapper")
  assert_true(c.portable)
}

///|
/// analyze 清洗：机制过短 / 无动作词 -> 不可移植；portable 应为 false。
test "self_search_analyze_nonportable" {
  let c = analyze_candidate("tiny", "短描述", "blogs", "hi")
  assert_eq(c.name, "tiny")
  assert_eq(c.mechanism, "hi")
  assert_true(not(c.portable))
}

///|
/// 判重：name+source 均同视为重复；任一分量不同则不重复。
test "self_search_is_duplicate" {
  let a = analyze_candidate("lib", "x", "crate", "portable wrapper")
  let b = analyze_candidate("lib", "x", "crate", "portable wrapper")
  let c = analyze_candidate("lib", "x", "gh", "portable wrapper")
  let d = analyze_candidate("other", "x", "crate", "portable wrapper")
  assert_true(is_duplicate_candidate(a, b))
  assert_true(not(is_duplicate_candidate(a, c)))
  assert_true(not(is_duplicate_candidate(a, d)))
}

///|
/// 可移植性：含中文动作词（移植/复用）应判定可移植。
test "self_search_portability_words" {
  let c_new = analyze_candidate(
    "eng", "", "paper", "把该机制移植到本项目并复用其封装",
  )
  assert_true(assess_portability(c_new))
  let low = analyze_candidate(
    "eng2", "", "paper", "describes the threading model only",
  )
  assert_true(not(assess_portability(low)))
}

///|
/// 可移植性边界：长度恰好触发词应判可移植；过短/空原样不可移植。
test "self_search_portability_length" {
  let empty = analyze_candidate("e", "", "tmp", "")
  assert_true(not(assess_portability(empty)))
  let short = analyze_candidate("s", "", "tmp", "abc")
  assert_true(not(assess_portability(short)))
  let word4 = analyze_candidate("w", "", "tmp", "wrap")
  assert_true(assess_portability(word4))
}

///|
/// distill：去重同键、过滤不可移植、按 source 升序，且稳定。
test "self_search_distill_ordering" {
  let b = analyze_candidate("beta", "b", "gh", "porting a reusable mechanism")
  let a = analyze_candidate("alpha", "a", "crate", "adapt the wrapper")
  let dup = analyze_candidate("alpha", "a", "crate", "adapt the wrapper")
  let no = analyze_candidate("bad", "", "tmp", "xx")
  let out = distill_candidates([b, a, dup, no])
  assert_eq(out.length(), 2)
  assert_true(out[0].source < out[1].source)
}

///|
/// run_external_search 成功路径（mock 注入执行器）。
test "self_search_external_ok" {
  let r = run_external_search(
    "mock-search",
    ["k"],
    runner=Some(fn(cmd, _args) { Ok("mock-hit:" + cmd) }),
  )
  assert_eq(r, Ok("mock-hit:mock-search"))
}

///|
/// run_external_search 失败路径：未注入执行器 -> Err（不硬编码、不静默通过）。
test "self_search_external_not_injected" {
  let r = run_external_search("gh-search", [])
  match r {
    Err(_) => ()
    Ok(_) => assert_true(false)
  }
}
