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
  assert_true(!a.is_duplicate("新增并发垃圾回收器", threshold=0.4))
}

///|
/// R138：`tokens` 是 `goal_drift_check` / `evolve_critic` 的**单真源**
/// （AGENTS 明写「复用 @evolve.tokens/jaccard」），但此前**零直接测试** ——
/// 只有 `evolve_is_duplicate_jaccard` 间接用到它。而它的 CJK 逻辑非平凡：
/// 中文按「单字 + 相邻二字组」发词，ASCII 按整词，两者不跨边界拼接。
test "tokens_cjk_single_and_bigram" {
  // 「熔断器」⇒ 单字 熔/断/器 + 二字组 熔断/断器 = 5（去重后仍 5）
  let t = tokens("熔断器")
  assert_eq(t.length(), 5)
  assert_true(t.contains("熔"))
  assert_true(t.contains("断"))
  assert_true(t.contains("器"))
  assert_true(t.contains("熔断"))
  assert_true(t.contains("断器"))
}

///|
/// R138：ASCII 侧必须**小写归一 + 去重**（否则 `Hello`/`hello` 会被当成两个不同词，
/// Jaccard 恒偏低 —— 本仓任务描述里英文术语混用大小写是常态）。
test "tokens_ascii_lowercased_and_deduped" {
  let t = tokens("Hello hello WORLD")
  assert_eq(t.length(), 2)
  assert_true(t.contains("hello"))
  assert_true(t.contains("world"))
}

///|
/// R138：**中英边界不许拼词** —— 「修复 bug」里 `修`/`复` 相邻可成「修复」，
/// 但 `复` 与 `b` 隔着一个空格，绝不能拼出「复bug」（否则英文术语会被中文尾巴污染）。
test "tokens_mixed_cjk_word_boundary" {
  let t = tokens("修复 bug")
  assert_true(t.contains("修"))
  assert_true(t.contains("修复"))
  assert_true(t.contains("bug"))
  assert_true(!t.contains("复bug"))
}

///|
/// R138：`jaccard` 的四个边界 —— 双方皆空必须回 **0.0 而不是 NaN**（`0/0`），
/// 全不相交 0.0、完全相同 1.0、部分重叠落在 (0,1)。
/// 为什么重要：`goal_drift_check` 用 `1 - jaccard` 判漂移；NaN 会让比较**恒 false**
/// ⇒ 漂移永远报不出来（静默失效）。
test "jaccard_edge_cases" {
  let e : Array[String] = []
  assert_eq(jaccard(e, e), 0.0)
  assert_eq(jaccard(tokens("a b"), tokens("c d")), 0.0)
  assert_eq(jaccard(tokens("a b"), tokens("a b")), 1.0)
  let third = jaccard(tokens("a b"), tokens("b c"))
  assert_true(third > 0.33 && third < 0.34)
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

///|
/// R190：`jaccard` 的三条**语义不变量**（R138 只锁了四个边界样本，没锁性质）。
///
/// 为什么要锁：
/// 1. **对称性** —— `jaccard(a,b)` 与 `jaccard(b,a)` 必须相等。实现里 `inter` 只遍历 `in_a` 查 `in_b`，
///    看上去对称，但"只从一个方向数"的写法一旦改成"两边都数"就会**双计**，而现有边界样本抓不到。
/// 2. **重复词折叠（集合语义）** —— `["a","a"]` 与 `["a"]` 必须给 **1.0**：实现用 `Map` 去重。
///    若有人改成"多重集"（数出现次数）会变成 0.5，`goal_drift_check` 的漂移判定随之整体偏移。
/// 3. **值域 [0,1]** —— 下游用 `1 - jaccard` 当漂移度，越界即无意义。
test "jaccard_invariants_symmetry_set_semantics_range" {
  let pairs : Array[(String, String)] = [
    ("a b c", "b c d"),
    ("x", "x y z"),
    ("中文 词 表", "词 表 中文"),
    ("q", "r"),
  ]
  for p in pairs {
    let (x, y) = p
    let ab = jaccard(tokens(x), tokens(y))
    let ba = jaccard(tokens(y), tokens(x))
    // ① 对称性（浮点相等是安全的：同一组整数计数的同一种除法）
    assert_eq(ab, ba, msg="不对称: " + x + " / " + y)
    // ③ 值域
    assert_true(ab >= 0.0 && ab <= 1.0, msg="越界: " + ab.to_string())
  }
  // ② 重复词折叠：集合语义下 ["a","a"] vs ["a"] == 1.0
  assert_eq(jaccard(["a", "a"], ["a"]), 1.0, msg="重复词未折叠（应回 1.0 而非 0.5）")
  assert_eq(jaccard(tokens("a a a"), tokens("a")), 1.0)
}
