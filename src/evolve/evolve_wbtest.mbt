/// evolve_test.mbt —— DGM 档案库核心算法测试
///
/// 覆盖四类能力：
///   1) add/best/len（基本档案库操作）
///   2) sample_parent：空库 None；单点返回；多点心 high 的更可能被选中
///   3) is_duplicate：Jaccard 查重（相似 goal 判重、独立 goal 不判重）
///   4) novelty：最像则低、全新则高
///   5) lineage 谱系回溯
///
/// 使用纯内存 Archive（不依赖 sqlite），随机源注入固定值保证可重复。

///|
/// 造一个产物。
fn mk_artifact(
  id : String,
  parent : String?,
  goal : String,
  note : String,
  score : Double,
  created : String,
) -> Artifact {
  {
    id,
    parent_id: parent,
    goal,
    note,
    code: "code-" + id,
    score,
    parts: Map([("simple", score)]),
    children: 0,
    created_at: created,
  }
}

///|
/// 确定性随机源（固定常量，保证采样可复现）。
fn fixed_rand(v : Double) -> () -> Double {
  fn() { v }
}

///|
test "evolve_add_best_len" {
  let a = Archive::new("mem")
  assert_true(a.is_empty())
  a.add(mk_artifact("a1", None, "目标A", "设计A", 0.9, "t1"))
  a.add(mk_artifact("a2", None, "目标B", "设计B", 0.5, "t2"))
  assert_eq(a.len(), 2)
  let b = a.best().unwrap()
  assert_eq(b.id, "a1")
  assert_eq(b.score, 0.9)
}

///|
test "evolve_sample_empty_and_single" {
  let a = Archive::new("mem")
  // 空库 None
  match a.sample_parent(rand=fixed_rand(0.5)) {
    None => ()
    Some(_) => abort("空库应返回 None")
  }
  // 单点返回该点
  a.add(mk_artifact("s1", None, "G", "N", 0.5, "t"))
  let picked = a.sample_parent(rand=fixed_rand(0.99)).unwrap()
  assert_eq(picked.id, "s1")
}

///|
test "evolve_sample_high_score_preferred" {
  let a = Archive::new("mem")
  // 两个点，高分 0.99 权重占比主导；中间 rand 应命中高分
  a.add(mk_artifact("lo", None, "低分", "n", 0.01, "t1"))
  a.add(mk_artifact("hi", None, "高分", "n", 0.99, "t2"))
  // rand=0.5（中间）：hi 权重 ~0.71 >> lo ~0.024，命中几乎必为 hi
  let picked = a.sample_parent(rand=fixed_rand(0.5)).unwrap()
  assert_eq(picked.id, "hi")
  // rand 靠近右端同样命中 hi
  let picked2 = a.sample_parent(rand=fixed_rand(0.999)).unwrap()
  assert_eq(picked2.id, "hi")
}

///|
test "evolve_is_duplicate_jaccard" {
  let a = Archive::new("mem")
  a.add(
    mk_artifact(
      "d1",
      None,
      "修复列表推导式嵌套作用域泄漏 bug",
      "借鉴闭包捕获",
      0.8,
      "t1",
    ),
  )
  // 几乎相同 -> 判重
  assert_true(
    a.is_duplicate("修复列表推导嵌套作用域泄漏 bug", threshold=0.4),
  )
  // 完全不同 -> 不判重
  assert_true(not(a.is_duplicate("新增并发垃圾回收器", threshold=0.4)))
}

///|
test "evolve_novelty_and_lineage" {
  let a = Archive::new("mem")
  a.add(
    mk_artifact(
      "p1",
      None,
      "设计 A",
      "专注解析器前端与词法分析",
      0.6,
      "t1",
    ),
  )
  a.add(
    mk_artifact(
      "c1",
      Some("p1"),
      "设计 A 的改进",
      "专注解析器前端与词法分析的深化",
      0.8,
      "t2",
    ),
  )
  // novel 全新主题 -> 高新颖
  let novel = a.novelty("完全不同的区块链共识协议设计")
  assert_true(novel >= 0.5)
  // 低新：极相似 note -> 低新颖
  let low = a.novelty("专注解析器前端词法分析")
  assert_true(low < novel)
  // lineage：c1 沿 parent 回溯到 p1
  let chain = a.lineage("c1", depth=4)
  assert_eq(chain.length(), 2)
  assert_eq(chain[0].0, "c1")
  assert_eq(chain[1].0, "p1")
}
