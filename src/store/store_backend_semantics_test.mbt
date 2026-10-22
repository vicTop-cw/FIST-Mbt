/// store_backend_semantics_test.mbt —— 双后端**同语义**锁（Phase C 独立清零批 A）
///
/// 覆盖两条只在"两个后端对照"下才暴露的缺陷：
///   BUG-85：`Store::list_tasks` 声明"列出全部任务"，内存后端过去按 default_ns 过滤、
///            SQLite 后端不过滤；`list_tasks_in("")` 的默认 ns 回退也只有一边有。
///   BUG-79：SQLite 的 `rsv_release` 把"语句跑成功"当"删到了行"（绑定层不给 changes()），
///            非持有者调用也回 true —— 内存后端的单测永远绿，抓不到生产后端的行为。
///
/// 口径：同一份夹具在两个后端上各跑一遍，断言逐条相同（绿不能跨后端抵扣）。

///|
/// 取一份干净的后端：内存桩 / SQLite（每次先 clear，保证可重复执行）。
fn bsem_backend(kind : String) -> @store.StoreBackend {
  if kind == "mem" {
    @store.StoreBackend::memory()
  } else {
    let db = "temp/store_backend_semantics.db"
    match @store.SqliteStore::open(db) {
      None => abort("sqlite open failed: " + db)
      Some(s) => {
        ignore(s.clear())
        @store.StoreBackend::sqlite(s)
      }
    }
  }
}

///|
/// BUG-85：list_tasks = 全量（跨 ns）；list_tasks_in 按 ns，空串回退 default。
test "BUG-85：list_tasks / list_tasks_in 在两后端上语义逐条相同" {
  for kind in ["mem", "sqlite"] {
    let b = bsem_backend(kind)
    ignore(
      b.create_task(
        @core.Task::new(
          id="B85A",
          project_dir="/proj/demo",
          description="落在 alpha 的任务",
          created_at="2026-09-27T00:00:00Z",
          ns="alpha",
        ),
      ),
    )
    ignore(
      b.create_task(
        @core.Task::new(
          id="B85B",
          project_dir="/proj/demo",
          description="落在 default 的任务",
          created_at="2026-09-27T00:00:01Z",
          ns="default",
        ),
      ),
    )
    // 声明是"列出全部任务"⇒ 两条都得在（内存后端过去这里只回 default 那一条）
    assert_eq(b.list_tasks().length(), 2)
    assert_eq(b.list_tasks_in("alpha").length(), 1)
    // 空串回退 default：两后端必须给同一条（SQLite 过去按 ns='' 查，恒 0 行）
    assert_eq(b.list_tasks_in("").length(), 1)
    assert_eq(b.list_tasks_in("no-such-ns").length(), 0)
  }
}

///|
/// BUG-79：预订释放必须校持有者，且"删 0 行"不得算成功。
test "BUG-79：rsv_release 两后端同语义（非持有者 false、删空 false）" {
  for kind in ["mem", "sqlite"] {
    let b = bsem_backend(kind)
    ignore(
      b.rsv_set(
        scope="src/b79.mbt",
        agent="owner",
        ttl_until="2026-09-27T12:00:00Z",
        created_at="2026-09-27T11:00:00Z",
      ),
    )
    // 非持有者：必须 false，且预订仍在（SQLite 过去回 true ⇒ 两 agent 同改一份作用域）
    assert_false(b.rsv_release("src/b79.mbt", "intruder"))
    match b.rsv_get("src/b79.mbt") {
      Some((o, _, _)) => assert_eq(o, "owner")
      None => abort("非持有者释放不该让预订消失（" + kind + "）")
    }
    // 持有者：true 且真的删掉
    assert_true(b.rsv_release("src/b79.mbt", "owner"))
    assert_true(b.rsv_get("src/b79.mbt") is None)
    // 幂等反向对照：重复释放（作用域已不存在）必须 false，
    // 这条钉住"DELETE 跑成功 ≠ 删到行"——缺它则 BUG-79 的修法可以退化成恒 true
    assert_false(b.rsv_release("src/b79.mbt", "owner"))
  }
}
