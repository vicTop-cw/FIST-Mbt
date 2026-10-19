/// issue_scan_adversarial_wbtest.mbt —— Round 5 对抗性守卫锁。
///
/// Round 3 的守卫修复只锁了 lint_14 一种真越界形态。此处把三类新守卫（mod_invariant /
/// find_endvar / multi_line_length）**其它**真越界形态各补反向锁：
/// `assert_false(guarded)` = 该形态不得被守卫误豁免（仍是真阳性）。
/// 证明守卫是精准白名单、不是 catch-all。
///
/// 说明：`substring(start=p, end=n)`（p=find 结果）与 `substring(start=n-n%k, end=n)`
/// 在本守卫族下会被**误报**（守卫比真实安全条件更窄）——但全 src/ 扫描
/// substring-overrun=0，仓库内无此形态，属"理论覆盖缺口"，此处不锁成 TP。

///|
/// A. 模运算守卫不豁免运行时 k：k 为运行时值且可能 > n → start = n - n%k 仍可越界
test "adv_guard_mod_runtime_k_not_exempted" {
  assert_false(
    scan_finding_guarded(
      "s.substring(start = n - n % k, end = n)",
      "substring-overrun",
      ["let n = s.length()", "let k = runtime_k"],
    ),
  )
}

///|
/// B. 模运算守卫不豁免负偏移 (n-x)%k：k>n 时结果 ∈ [0,k-1] 可 > n
test "adv_guard_mod_negative_shift_not_exempted" {
  assert_false(
    scan_finding_guarded(
      "s.substring(start = (n - x) % k, end = n)",
      "substring-overrun",
      ["let n = s.length()"],
    ),
  )
}

///|
/// C. find 结果守卫不豁免"find + 偏移"：p 近末尾时 p+offset 越界
test "adv_guard_find_plus_offset_not_exempted" {
  assert_false(
    scan_finding_guarded(
      "s.substring(start = p + 1, end = p + 3)",
      "substring-overrun",
      ["let p = s.find(" + q() + "]" + q() + ") or { 0 }"],
    ),
  )
}

///|
/// E. 多行长守卫不豁免"长度守卫作用在别的变量 u"（不是被 substring 的 s）
test "adv_guard_wrong_var_length_not_exempted" {
  assert_false(
    scan_finding_guarded(
      "s.substring(start = n - cut, end = n)",
      "substring-overrun",
      [
        "if u.length() < 3 {", "return s", "}", "let cut = 10", "let n = s.length()",
      ],
    ),
  )
}

///|
/// 正控：scan_finding_guarded 不是恒 false——真实守卫形态仍必须被判已守卫。
test "adv_guard_positive_control_still_exempts" {
  assert_true(
    scan_finding_guarded(
      "let desc = ls.substring(start=3, end~).trim().to_string()",
      "substring-overrun",
      ["if end > 3 {"],
    ),
  )
  // 上一行守卫的是别的变量（other），不得误豁免
  assert_false(
    scan_finding_guarded(
      "let desc = ls.substring(start=3, end~).trim().to_string()",
      "substring-overrun",
      ["if other > 3 {"],
    ),
  )
}
