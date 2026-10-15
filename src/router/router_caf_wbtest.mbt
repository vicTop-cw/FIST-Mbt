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
