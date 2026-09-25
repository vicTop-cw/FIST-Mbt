// 执行者能力注册持久化（StoreBackend executor_save/list/clear，R31）双后端测试。
// 覆盖：写/覆盖（幂等）、读回、clear 一并清空（防测试/scratch 残留）。

///|
fn fill_and_verify(b : @store.StoreBackend) -> Unit {
  ignore(
    b.executor_save(
      name="ex-A",
      abilities_json="[\"json\",\"编排\"]",
      created_at="2026-09-25T11:00:00Z",
    ),
  )
  ignore(
    b.executor_save(
      name="ex-B",
      abilities_json="[\"编排\"]",
      created_at="2026-09-25T11:00:00Z",
    ),
  )
  ignore(
    b.executor_save(
      name="ex-A",
      abilities_json="[\"json\",\"编排\",\"deploy\"]",
      created_at="2026-09-25T11:05:00Z",
    ),
  )
}

///|
test "executor 内存后端：save/list/覆盖幂等/clear" {
  let b = @store.StoreBackend::memory()
  assert_eq(b.executor_list().length(), 0)
  fill_and_verify(b)
  // 覆盖幂等：同 name 再写，仍 2 行
  assert_eq(b.executor_list().length(), 2)
  assert_true(b.executor_clear())
  assert_eq(b.executor_list().length(), 0)
}

///|
test "executor SQLite 后端：save/list/覆盖幂等/clear" {
  let db = "temp/executor_store_test.db"
  match @store.SqliteStore::open(db) {
    None => abort("sqlite open failed: \{db}")
    Some(s) => {
      let b = @store.StoreBackend::sqlite(s)
      ignore(b.executor_clear()) // 先清旧
      assert_eq(b.executor_list().length(), 0)
      fill_and_verify(b)
      assert_eq(b.executor_list().length(), 2)
      assert_true(b.executor_clear())
      assert_eq(b.executor_list().length(), 0)
    }
  }
}

///|
test "executor clear()（整库清空）会一并清空注册（双后端）" {
  // 内存
  let mem = @store.StoreBackend::memory()
  ignore(
    mem.executor_save(
      name="mem-ex",
      abilities_json="[]",
      created_at="2026-09-25T11:00:00Z",
    ),
  )
  mem.clear()
  assert_eq(mem.executor_list().length(), 0)
  // SQLite
  let db = "temp/executor_clear_test.db"
  match @store.SqliteStore::open(db) {
    None => abort("sqlite open failed")
    Some(s) => {
      ignore(
        s.executor_save(
          name="sql-ex",
          abilities_json="[]",
          created_at="2026-09-25T11:00:00Z",
        ),
      )
      s.clear()
      assert_eq(s.executor_list().length(), 0)
    }
  }
}
