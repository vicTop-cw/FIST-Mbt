/// decompose_quickcheck_test.mbt —— decompose 纯函数属性测试（R107 · 集成 moonbitlang/core/quickcheck）。
/// 拿来主义支柱：复用既有属性测试库（随机输入验证不变量，替代手写固定断言），
/// 覆盖此前无直接测试的 default_slices / difficulty_label / difficulty_label_from。

///|
/// 难度档序：易(0) < 中(1) < 难(2)；非法档位返回 99 哨兵。
fn diff_order(s : String) -> Int {
  match s {
    "易" => 0
    "中" => 1
    "难" => 2
    _ => 99
  }
}

///|
test "quickcheck: default_slices 数量与内容前缀不变量" {
  @quickcheck.check(
    (p : (Int, String)) => {
      let n = p.0
      let d = p.1
      if n < 1 || n > 100 {
        true // 超出合理拆分域（Int 生成器含全幅大整数），属性放行
      } else {
        let slices = default_slices(n, parent_desc=d)
        if slices.length() != n {
          false
        } else {
          let mut all_prefix = true
          for s in slices {
            if !s.starts_with(d) {
              all_prefix = false
            }
          }
          all_prefix
        }
      }
    },
    count=100,
    max_size=30,
    seed=20260926,
  )
}

///|
test "quickcheck: difficulty_label 三档合法且整段单调（前易后难）" {
  @quickcheck.check(
    (p : (Int, Int)) => {
      let idx = p.0
      let split_n = p.1
      if split_n < 1 || split_n > 100 {
        true // 超出合理拆分域，属性放行（避免大 split_n 的整段扫描）
      } else {
        let l = difficulty_label(idx, split_n)
        if diff_order(l) > 2 {
          false
        } else {
          // 对生成出的 split_n 校验整段难度序列单调不减（含越界 idx 的钳制路径）
          let mut mono = true
          for j = 1; j < split_n; j = j + 1 {
            if diff_order(difficulty_label(j, split_n)) >
              diff_order(difficulty_label(j + 1, split_n)) {
              mono = false
            }
          }
          mono
        }
      }
    },
    count=100,
    max_size=30,
    seed=20260927,
  )
}

///|
test "quickcheck: difficulty_label_from 随难度数值单调不减" {
  @quickcheck.check(
    (p : (Double, Double)) => {
      let d1 = p.0
      let d2 = p.1
      if d1 > d2 {
        true
      } else {
        diff_order(difficulty_label_from(d1)) <= diff_order(difficulty_label_from(d2))
      }
    },
    count=100,
    max_size=0,
    seed=20260928,
  )
}
