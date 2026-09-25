// Whitebox tests run within the package scope.
// Use them to validate internal helpers or invariants.
// Keep them focused; public behavior belongs in `_test.mbt`.

///|
test "sync_db_lessons 让 DB 中的 [lesson] 教训对 inject 与 dead_ends 进程内可见" {
  let db = "temp/sync_db_lessons_wbtest.db"
  match @store.SqliteStore::open(db) {
    None => abort("open sync db failed")
    Some(store) => {
      // 模拟一条 Omega 打回自动落库的 [lesson]（仅落 DB，不经内存 Archive）
      ignore(
        store.evolve_upsert(
          id="omega-lesson-synctest",
          parent_id="",
          goal="[lesson] omega.spec_rejected",
          note="验收标准不量化",
          code="按审核意见重写语料",
          score=0.5,
          parts_json="{}",
          created_at="2026-09-25T09:00:00Z",
        ),
      )
      let arc = @evolve.Archive::new("sync-test")
      // 同步 DB → 内存档案库
      let n1 = sync_db_lessons(arc, Some(store))
      assert_eq(n1, 1)
      assert_eq(@evolve.Archive::len(arc), 1)
      // inject：按类目命中教训（供 plan/claim 检索"踩过的坑"）
      let inj = lookup_injected_assets_in(arc, "omega.spec_rejected").stringify()
      assert_true(inj.contains("验收标准不量化"))
      // dead_ends："此路不通"地图应如实反映教训
      let dead = @evolve.Archive::dead_ends(arc, limit=8)
      assert_true(dead.length() >= 1)
      assert_true(dead[0].contains("[lesson]"))
      // 幂等：重复同步不重复计数
      assert_eq(sync_db_lessons(arc, Some(store)), 0)
    }
  }
}
