///|
/// BUG-188 回归：CafMemory::new(max_size<=0) 收敛到 1，push 不再越界 panic。
test "caf_memory_max_size_zero_clamped" {
  let mem = CafMemory::new(max_size=0)
  if mem.max_size != 1 {
    fail("max_size=0 应收敛到 1，实收 " + mem.max_size.to_string())
  }
  let rec = CafRecord::new(
    feature_hash=1,
    model="m",
    ok=true,
    cost=0.5,
    ts="2026-10-15T15:00:00",
  )
  CafMemory::push(mem, rec)
  let all = CafMemory::all(mem)
  if all.length() != 1 {
    fail("push 后应有 1 条记录，实收 " + all.length().to_string())
  }
}

///|
/// BUG-188 回归：负数 max_size 同样收敛。
test "caf_memory_max_size_negative_clamped" {
  let mem = CafMemory::new(max_size=-5)
  if mem.max_size != 1 {
    fail("max_size=-5 应收敛到 1，实收 " + mem.max_size.to_string())
  }
}
