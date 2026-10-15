/// router_caf_wbtest.mbt —— C-A-F 记忆层白盒测试

///|
test "caf_record_new" {
  let rec = CafRecord::new(
    feature_hash=42,
    model="test-model",
    ok=true,
    cost=0.5,
    ts="2026-10-15T12:00:00Z",
  )
  assert_eq(rec.feature_hash, 42)
  assert_eq(rec.model, "test-model")
  assert_eq(rec.ok, true)
  assert_eq(rec.cost, 0.5)
  assert_eq(rec.ts, "2026-10-15T12:00:00Z")
}

///|
test "caf_memory_new_empty" {
  let mem = CafMemory::new(max_size=10)
  assert_eq(mem.all().length(), 0)
  assert_eq(mem.count, 0)
}

///|
test "caf_memory_push_and_all" {
  let mem = CafMemory::new(max_size=10)
  let rec1 = CafRecord::new(
    feature_hash=1,
    model="m1",
    ok=true,
    cost=0.1,
    ts="t1",
  )
  let rec2 = CafRecord::new(
    feature_hash=2,
    model="m2",
    ok=false,
    cost=0.2,
    ts="t2",
  )
  mem.push(rec1)
  mem.push(rec2)
  let all = mem.all()
  assert_eq(all.length(), 2)
  assert_eq(mem.count, 2)
}

///|
test "caf_memory_fifo_eviction" {
  let mem = CafMemory::new(max_size=3)
  for i in 0..<5 {
    mem.push(
      CafRecord::new(feature_hash=i, model="m", ok=true, cost=0.0, ts="t"),
    )
  }
  let all = mem.all()
  assert_eq(all.length(), 3) // 只保留最近 3 条
  assert_eq(mem.count, 3)
  // 检查是最新的 3 条（i=2,3,4）
  assert_eq(all[0].feature_hash, 2)
  assert_eq(all[1].feature_hash, 3)
  assert_eq(all[2].feature_hash, 4)
}

///|
test "caf_memory_find" {
  let mem = CafMemory::new(max_size=20)
  mem.push(
    CafRecord::new(feature_hash=1, model="a", ok=true, cost=0.1, ts="t1"),
  )
  mem.push(
    CafRecord::new(feature_hash=2, model="b", ok=true, cost=0.2, ts="t2"),
  )
  mem.push(
    CafRecord::new(feature_hash=1, model="c", ok=false, cost=0.3, ts="t3"),
  )
  let hits = mem.find(feature_hash=1)
  assert_eq(hits.length(), 2)
  assert_eq(hits[0].model, "a")
  assert_eq(hits[1].model, "c")
}

///|
test "caf_stats_empty" {
  assert_eq(caf_stats([]).length(), 0)
}

///|
test "caf_stats_grouping" {
  let records : Array[CafRecord] = [
    CafRecord::new(feature_hash=1, model="m1", ok=true, cost=0.1, ts="t1"),
    CafRecord::new(feature_hash=1, model="m1", ok=true, cost=0.2, ts="t2"),
    CafRecord::new(feature_hash=1, model="m1", ok=false, cost=0.3, ts="t3"),
    CafRecord::new(feature_hash=2, model="m2", ok=true, cost=0.4, ts="t4"),
  ]
  let stats = caf_stats(records)
  assert_eq(stats.length(), 2)
  // m1: 3 total, 2 success, avg_cost=0.2
  // m2: 1 total, 1 success, avg_cost=0.4
  // 按成功率降序：m2 (100%) > m1 (66.7%)
  assert_eq(stats[0].model, "m2")
  assert_eq(stats[0].total, 1)
  assert_eq(stats[0].success, 1)
  assert_eq(stats[1].model, "m1")
  assert_eq(stats[1].total, 3)
  assert_eq(stats[1].success, 2)
  // (0.1 + 0.2 + 0.3) / 3 有浮点误差，用容差比较
  assert_true((stats[1].avg_cost - 0.2).abs() < 0.000000001)
}

///|
/// BUG-173 回归：完全相等（rate + avg_cost 均同）时 sort_by 必须遵守严格弱序，
/// 不崩溃、不无限循环，且用 model 字典序做确定性 tiebreak。
test "caf_stats_equal_rate_equal_cost_tiebreak" {
  let records : Array[CafRecord] = [
    CafRecord::new(feature_hash=1, model="m1", ok=true, cost=0.2, ts="t1"),
    CafRecord::new(feature_hash=1, model="m2", ok=true, cost=0.2, ts="t2"),
    CafRecord::new(feature_hash=1, model="m3", ok=true, cost=0.2, ts="t3"),
  ]
  let stats = caf_stats(records)
  assert_eq(stats.length(), 3)
  // 完全相等 → model 字典序 tiebreak：m1 < m2 < m3
  assert_eq(stats[0].model, "m1")
  assert_eq(stats[1].model, "m2")
  assert_eq(stats[2].model, "m3")
  // 全部 rate=1.0, avg_cost=0.2
  assert_eq(stats[0].success, 1)
  assert_eq(stats[0].total, 1)
  assert_true((stats[0].avg_cost - 0.2).abs() < 0.000000001)
}

///|
/// BUG-173 补充回归：单条记录不崩溃。
test "caf_stats_single_record" {
  let records : Array[CafRecord] = [
    CafRecord::new(feature_hash=1, model="only", ok=false, cost=0.0, ts="t1"),
  ]
  let stats = caf_stats(records)
  assert_eq(stats.length(), 1)
  assert_eq(stats[0].model, "only")
  assert_eq(stats[0].success, 0)
  assert_eq(stats[0].total, 1)
}

///|
/// BUG-174 回归：长字符串（>14 字符，原实现会溢出到 Int64.min_value()）不崩溃，
/// 且返回哈希值恒非负（32 位截断保证）。
test "caf_feature_hash_long_string_no_overflow" {
  // 15 个字符足够触发原始 h*31+c 溢出（31^14 ≈ 1e20 > 2^63）
  let long1 = "aaaaaaaaaaaaaaa" // 15 字符
  let long2 = "zzzzzzzzzzzzzzz" // 15 字符
  let h1 = caf_feature_hash(long1)
  let h2 = caf_feature_hash(long2)
  // 不崩溃即通过；同时验证返回值非负（原 h.abs() 在 min_value() 时 panic）
  assert_true(h1 >= 0)
  assert_true(h2 >= 0)
  // 幂等性仍成立
  assert_eq(h1, caf_feature_hash(long1))
  // 不同内容大概率不同哈希
  assert_true(h1 != h2)
}

///|
/// BUG-174 补充：超长字符串（100 字符）也不崩溃，返回非负。
test "caf_feature_hash_very_long_no_overflow" {
  let mut long = ""
  for _ in 0..<4 {
    long = long + "abcdefghijklmnopqrstuvwxyz"
  } // 104 字符
  let h = caf_feature_hash(long)
  assert_true(h >= 0)
}

///|
/// 环形缓冲回绕测试：push 超过 max_size 后，all() 仍按 FIFO 顺序返回最近记录。
test "caf_memory_wraparound_order" {
  let mem = CafMemory::new(max_size=3)
  mem.push(
    CafRecord::new(feature_hash=0, model="m", ok=true, cost=0.0, ts="t0"),
  )
  mem.push(
    CafRecord::new(feature_hash=1, model="m", ok=true, cost=0.0, ts="t1"),
  )
  mem.push(
    CafRecord::new(feature_hash=2, model="m", ok=true, cost=0.0, ts="t2"),
  )
  // 满 3 条，继续 push 触发回绕
  mem.push(
    CafRecord::new(feature_hash=3, model="m", ok=true, cost=0.0, ts="t3"),
  )
  mem.push(
    CafRecord::new(feature_hash=4, model="m", ok=true, cost=0.0, ts="t4"),
  )
  let all = mem.all()
  assert_eq(all.length(), 3)
  // 回绕后仍按 FIFO：最旧的 t2 在前
  assert_eq(all[0].feature_hash, 2)
  assert_eq(all[1].feature_hash, 3)
  assert_eq(all[2].feature_hash, 4)
}

///|
/// 单元素环形缓冲（max_size=1）：退化边界，push 应覆盖旧值。
test "caf_memory_single_slot" {
  let mem = CafMemory::new(max_size=1)
  mem.push(
    CafRecord::new(feature_hash=1, model="a", ok=true, cost=0.1, ts="t1"),
  )
  mem.push(
    CafRecord::new(feature_hash=2, model="b", ok=false, cost=0.2, ts="t2"),
  )
  let all = mem.all()
  assert_eq(all.length(), 1)
  // 只有最新一条
  assert_eq(all[0].feature_hash, 2)
  assert_eq(all[0].model, "b")
  assert_eq(mem.count, 1)
}

///|
/// 满缓冲覆盖测试：count==max_size 时 push，应覆盖最旧且 count 不增长。
test "caf_memory_full_buffer_eviction" {
  let mem = CafMemory::new(max_size=2)
  mem.push(
    CafRecord::new(feature_hash=1, model="m", ok=true, cost=0.0, ts="t1"),
  )
  mem.push(
    CafRecord::new(feature_hash=2, model="m", ok=true, cost=0.0, ts="t2"),
  )
  // 满缓冲（count=2）
  assert_eq(mem.count, 2)
  mem.push(
    CafRecord::new(feature_hash=3, model="m", ok=true, cost=0.0, ts="t3"),
  )
  // count 不增长
  assert_eq(mem.count, 2)
  let all = mem.all()
  assert_eq(all.length(), 2)
  // 最旧 t1 被覆盖
  assert_eq(all[0].feature_hash, 2)
  assert_eq(all[1].feature_hash, 3)
}

///|
/// P2：编辑距离基础正确性（Levenshtein）
test "caf_edit_distance_basic" {
  // 相同字符串 → 0
  assert_eq(caf_edit_distance("abc", "abc"), 0)
  // 空 vs 非空 → 非空长度
  assert_eq(caf_edit_distance("", "abc"), 3)
  assert_eq(caf_edit_distance("abc", ""), 3)
  // 单字符替换 → 1
  assert_eq(caf_edit_distance("cat", "cut"), 1)
  // 单字符删除 → 1
  assert_eq(caf_edit_distance("kitten", "kitchen"), 2)
}

///|
/// P2：kNN 检索返回 Top-K 且按相似度排序
test "caf_knn_search_topk" {
  let mem = CafMemory::new(max_size=100)
  // 3 条不同 context 的记录
  mem.push(
    CafRecord::new(
      feature_hash=caf_feature_hash("easy python"),
      model="m1",
      ok=true,
      cost=0.1,
      ts="t1",
    ),
  )
  mem.push(
    CafRecord::new(
      feature_hash=caf_feature_hash("hard java"),
      model="m2",
      ok=true,
      cost=0.2,
      ts="t2",
    ),
  )
  mem.push(
    CafRecord::new(
      feature_hash=caf_feature_hash("easy python"),
      model="m3",
      ok=false,
      cost=0.3,
      ts="t3",
    ),
  )
  // 对 easy python 检索，应优先命中 feature_hash 完全相同的两条
  let k1 = mem.knn_search("easy python", 1)
  assert_eq(k1.length(), 1)
  // 完全相等 → 编辑距离 0
  assert_eq(k1[0].feature_hash, caf_feature_hash("easy python"))

  // k=2 时返回两条最近的
  let k2 = mem.knn_search("easy python", 2)
  assert_eq(k2.length(), 2)
}

///|
/// P2：kNN 检索边界——k=0 返回空，k > records 返回全部
test "caf_knn_search_boundary" {
  let mem = CafMemory::new(max_size=10)
  mem.push(
    CafRecord::new(feature_hash=1, model="m", ok=true, cost=0.0, ts="t1"),
  )
  // k=0 → 空
  assert_eq(mem.knn_search("ctx", 0).length(), 0)
  // k 大于 records 数 → 全部
  assert_eq(mem.knn_search("ctx", 99).length(), 1)
  // 空 memory → 空
  let empty = CafMemory::new(max_size=10)
  assert_eq(empty.knn_search("ctx", 5).length(), 0)
}

///|
/// O(count) 优化正确性：count < max_size 时 all() 仍返回全部 count 条，不丢不重。
test "caf_memory_all_sparse_count" {
  let mem = CafMemory::new(max_size=1000)
  mem.push(
    CafRecord::new(feature_hash=1, model="m", ok=true, cost=0.1, ts="t1"),
  )
  mem.push(
    CafRecord::new(feature_hash=2, model="m", ok=true, cost=0.2, ts="t2"),
  )
  mem.push(
    CafRecord::new(feature_hash=3, model="m", ok=true, cost=0.3, ts="t3"),
  )
  // count=3 << max_size=1000，all() 应只返回 3 条，且 FIFO 顺序正确
  let all = mem.all()
  assert_eq(all.length(), 3)
  assert_eq(all[0].feature_hash, 1)
  assert_eq(all[1].feature_hash, 2)
  assert_eq(all[2].feature_hash, 3)
  // find() 同源优化，命中唯一
  assert_eq(mem.find(feature_hash=2).length(), 1)
  assert_eq(mem.find(feature_hash=2)[0].ts, "t2")
}

///|
/// P2：knn_stats 返回 Top-K 邻域按模型的成功率与平均成本统计
test "caf_knn_stats_by_model" {
  let mem = CafMemory::new(max_size=100)
  // 同一 context，两个不同模型，不同成败
  let ctx = "hello world task"
  mem.push(
    CafRecord::new(
      feature_hash=caf_feature_hash(ctx),
      model="m1",
      ok=true,
      cost=0.1,
      ts="t1",
    ),
  )
  mem.push(
    CafRecord::new(
      feature_hash=caf_feature_hash(ctx),
      model="m2",
      ok=false,
      cost=0.2,
      ts="t2",
    ),
  )
  mem.push(
    CafRecord::new(
      feature_hash=caf_feature_hash(ctx),
      model="m1",
      ok=true,
      cost=0.3,
      ts="t3",
    ),
  )
  let stats = mem.knn_stats(ctx, 3)
  assert_eq(stats.length(), 2) // 两个 model
  // m1 成功率 1.0 排在前面
  assert_eq(stats[0].model, "m1")
  assert_eq(stats[0].total, 2)
  assert_eq(stats[0].success, 2)
  assert_eq(stats[1].model, "m2")
  assert_eq(stats[1].success, 0)
}

///|
/// P2：caf_soft_reorder 把邻域内高成功率模型提前，未在邻域的保持稳定序。
test "caf_soft_reorder_prioritizes_high_rate" {
  // 构造 CafModelStats（手动）
  let stats : Array[CafModelStats] = [
    { model: "m2", total: 10, success: 9, avg_cost: 0.2, },
    { model: "m1", total: 10, success: 2, avg_cost: 0.1, },
  ]
  let candidates : Array[String] = ["m1", "m3", "m2"]
  let out = caf_soft_reorder(candidates, stats)
  // m2（成功率 0.9）提前，m3（不在邻域）保持中间
  assert_eq(out[0], "m2")
  assert_eq(out[1], "m1")
  assert_eq(out[2], "m3")
}

///|
/// P2：caf_soft_reorder 零回归基线——空 stats 或空候选原样返回。
test "caf_soft_reorder_empty_baseline" {
  let candidates : Array[String] = ["a", "b", "c"]
  // 空 stats → 原样
  let empty_stats : Array[CafModelStats] = []
  let out1 = caf_soft_reorder(candidates, empty_stats)
  assert_eq(out1[0], "a")
  assert_eq(out1[1], "b")
  assert_eq(out1[2], "c")
  // 空候选 → 原样
  let empty_candidates : Array[String] = []
  let stats = [{ model: "a", total: 1, success: 1, avg_cost: 0.1, }]
  assert_eq(caf_soft_reorder(empty_candidates, stats).length(), 0)
}

///|
test "caf_feature_hash_idempotent" {
  let h1 = caf_feature_hash("hello world")
  let h2 = caf_feature_hash("hello world")
  assert_eq(h1, h2)
}

///|
test "caf_feature_hash_different_inputs" {
  let h1 = caf_feature_hash("easy python")
  let h2 = caf_feature_hash("hard java")
  assert_true(h1 != h2)
}

///|
test "caf_memory_to_json" {
  let mem = CafMemory::new(max_size=5)
  mem.push(
    CafRecord::new(feature_hash=1, model="m1", ok=true, cost=0.1, ts="t1"),
  )
  let j = mem.to_json()
  match j {
    Json::Object(m) => {
      match m.get("total_records") {
        Some(Json::Number(n, ..)) => assert_eq(n.to_int(), 1)
        _ => assert_true(false)
      }
      match m.get("capacity") {
        Some(Json::Number(n, ..)) => assert_eq(n.to_int(), 5)
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
/// P2 端到端集成：push → knn_search → knn_stats → soft_reorder 全流程
/// 模拟一个 CAF 记忆已积累多轮反馈的场景，验证决策融合链路可通。
test "caf_p2_pipeline_integration" {
  let mem = CafMemory::new(max_size=50)
  let ctx = "summarize large document"
  let h = caf_feature_hash(ctx)
  // 三模型积累：m_gpt 高成功率/高成本，m_claude 中成功率/低成本，m_gemini 低成功率
  for i in 0..<3 {
    mem.push(
      CafRecord::new(feature_hash=h, model="m_gpt", ok=true, cost=0.5, ts="t"),
    )
  }
  for i in 0..<5 {
    mem.push(
      CafRecord::new(
        feature_hash=h,
        model="m_claude",
        ok=true,
        cost=0.1,
        ts="t",
      ),
    )
  }
  for i in 0..<4 {
    mem.push(
      CafRecord::new(
        feature_hash=h,
        model="m_gemini",
        ok=false,
        cost=0.05,
        ts="t",
      ),
    )
  }

  // knn_search：全部命中（编辑距离 0）
  let nb = mem.knn_search(ctx, 12)
  assert_eq(nb.length(), 12)

  // knn_stats：按模型聚合
  let stats = mem.knn_stats(ctx, 12)
  assert_eq(stats.length(), 3)
  // m_gpt 与 m_claude 同率(1.0)，成本升序 → m_claude(0.1) 先于 m_gpt(0.5)
  assert_eq(stats[0].model, "m_claude")
  assert_eq(stats[0].total, 5)
  assert_eq(stats[0].success, 5)
  assert_eq(stats[1].model, "m_gpt")
  assert_eq(stats[1].success, 3)
  // m_gemini 成功率 0 应排最后
  assert_eq(stats[2].model, "m_gemini")
  assert_eq(stats[2].success, 0)

  // soft_reorder：给定候选集，高成功率优先，同率时低成本优先
  let candidates : Array[String] = ["m_gemini", "m_gpt", "m_claude"]
  let reordered = caf_soft_reorder(candidates, stats)
  assert_eq(reordered[0], "m_claude") // 同率 1.0 且成本更低 → 第一
  assert_eq(reordered[1], "m_gpt") // 同率 1.0 成本 0.5 → 次位
  assert_eq(reordered[2], "m_gemini") // 成功率 0 → 最后
}

///|
/// 属性测试（随机化寻虫）：不变量验证。
/// 1. all() 长度 <= max_size（环形淘汰不越界）
/// 2. knn_search k=0 → 空；k>count → 返回 count（不越界）
/// 3. caf_soft_reorder 是候选集的置换（元素不变，仅顺序变）
test "caf_property_random_invariants" {
  // 简单 LCG 伪随机（可复现）
  let mut seed = 42
  let max_size = 7
  let mem = CafMemory::new(max_size~)
  let models : Array[String] = ["a", "b", "c"]

  // 随机 push 30 条，远超 max_size 触发 FIFO 淘汰
  for i in 0..<30 {
    seed = (seed * 1103515245 + 12345).land(0x7FFFFFFF)
    let model_idx = seed % 3
    let ok = seed / 3 % 2 == 0
    let hash = seed / 7 % 1000
    let cost = (seed % 100).to_double() / 100.0
    mem.push(
      CafRecord::new(
        feature_hash=hash,
        model=models[model_idx],
        ok~,
        cost~,
        ts=i.to_string(),
      ),
    )
  }

  // 不变量 1: all() 长度 <= max_size
  let all = mem.all()
  assert_true(all.length() <= max_size)
  // 环形淘汰后 count 应等于 max_size（塞满）
  assert_eq(mem.count, max_size)

  // 不变量 2a: k=0 → 空
  assert_eq(mem.knn_search("ctx", 0).length(), 0)
  // 不变量 2b: k>count → 返回 count（不越界）
  let nb = mem.knn_search("test context", 100)
  assert_true(nb.length() <= mem.count)

  // 不变量 3: soft_reorder 是候选集的置换
  let stats = mem.knn_stats("test context", 100)
  let candidates : Array[String] = ["a", "b", "c"]
  let reordered = caf_soft_reorder(candidates, stats)
  assert_eq(reordered.length(), 3)
  let mut found_a = false
  let mut found_b = false
  let mut found_c = false
  for r in reordered {
    if r == "a" {
      found_a = true
    }
    if r == "b" {
      found_b = true
    }
    if r == "c" {
      found_c = true
    }
  }
  assert_true(found_a)
  assert_true(found_b)
  assert_true(found_c)
}
