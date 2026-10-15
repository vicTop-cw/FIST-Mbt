///|
/// R36：CAF 记忆逐条持久化层的往返契约锁。
/// 钉死 caf_memory_dump / caf_memory_load 的语义：
/// - 往返后 all() 顺序与字段一致（可恢复记忆）
/// - 坏类型降级 + warning（与 RouterConfig::from_json 同口径），绝不 panic
/// - 坏字段单条跳过，正常条不被牵连

///|
fn ptest_mem() -> CafMemory {
  let mem = CafMemory::new(max_size=10)
  mem.push(
    CafRecord::new(
      feature_hash=1,
      model="free-a",
      ok=true,
      cost=0.1,
      ts="2026-10-15T00:00:00Z",
    ),
  )
  mem.push(
    CafRecord::new(
      feature_hash=2,
      model="free-b",
      ok=false,
      cost=0.2,
      ts="2026-10-15T00:00:01Z",
    ),
  )
  mem.push(
    CafRecord::new(
      feature_hash=3,
      model="free-a",
      ok=true,
      cost=0.0,
      ts="2026-10-15T00:00:02Z",
    ),
  )
  mem
}

///|
/// 空记忆往返：dump → load → all() 空、warns 空、max_size 保留。
test "caf_persist_1_空记忆往返" {
  let mem = CafMemory::new(max_size=7)
  let json = caf_memory_dump(mem)
  let (back, warns) = caf_memory_load(json)
  if warns.length() != 0 {
    abort("空记忆往返不应警告，got \{warns.length()}")
  }
  if not(back.all().is_empty()) {
    abort("空记忆往返后应为空，实际 \{back.all().length()}")
  }
}

///|
/// 多条记录往返：all() 顺序与逐字段一致（可完整恢复记忆）。
test "caf_persist_2_多条记录往返" {
  let mem = ptest_mem()
  let orig = mem.all()
  let json = caf_memory_dump(mem)
  let (back, warns) = caf_memory_load(json)
  if warns.length() != 0 {
    abort("正常往返不应警告，got \{warns.length()}")
  }
  let restored = back.all()
  if restored.length() != orig.length() {
    abort(
      "往返后条数应一致，got \{restored.length()} want \{orig.length()}",
    )
  }
  // 逐条比对字段（顺序必须一致）
  let mut i = 0
  while i < orig.length() {
    if restored[i].feature_hash != orig[i].feature_hash {
      abort("feature_hash 顺序不一致 at \{i}")
    }
    if restored[i].model != orig[i].model {
      abort("model 不一致 at \{i}")
    }
    if restored[i].ok != orig[i].ok {
      abort("ok 不一致 at \{i}")
    }
    if restored[i].cost != orig[i].cost {
      abort("cost 不一致 at \{i}")
    }
    if restored[i].ts != orig[i].ts {
      abort("ts 不一致 at \{i}")
    }
    i = i + 1
  }
}

///|
/// records 坏类型（非数组）：降级为空 + warning，不 panic。
test "caf_persist_3_坏类型records降级" {
  let bad : Json = {
    "max_size": Json::number(10.0),
    "records": Json::string("oops"),
  }
  let (back, warns) = caf_memory_load(bad)
  if warns.length() == 0 {
    abort("坏类型 records 应产生 warning，实际 0 条")
  }
  if not(back.all().is_empty()) {
    abort("坏类型 records 应降级为空，实际 \{back.all().length()}")
  }
}

///|
/// 坏字段单条跳过：缺 feature_hash 的记录被跳过，正常条保留 + warning。
test "caf_persist_4_坏字段单条跳过" {
  let bad : Json = {
    "max_size": Json::number(10.0),
    "records": Json::array([
      // 正常条
      Json::object({
        "feature_hash": Json::number(1.0),
        "model": Json::string("free-a"),
        "ok": Json::boolean(true),
        "cost": Json::number(0.1),
        "ts": Json::string("2026-10-15T00:00:00Z"),
      }),
      // 缺 feature_hash → 整条无效
      Json::object({
        "model": Json::string("free-b"),
        "ok": Json::boolean(false),
        "cost": Json::number(0.2),
        "ts": Json::string("2026-10-15T00:00:01Z"),
      }),
    ]),
  }
  let (back, warns) = caf_memory_load(bad)
  if warns.length() == 0 {
    abort("有坏字段应产生 warning，实际 0 条")
  }
  let restored = back.all()
  if restored.length() != 1 {
    abort("应保留 1 条正常记录，实际 \{restored.length()}")
  }
  if restored[0].model != "free-a" {
    abort("正常记录应保留 free-a，实际 \{restored[0].model}")
  }
}
