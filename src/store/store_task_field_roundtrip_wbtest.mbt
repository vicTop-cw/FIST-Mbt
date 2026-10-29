///|
/// store_task_field_roundtrip_wbtest.mbt —— `Task` 落库的**全字段往返**不变量（R191）。
///
/// 为什么补：`src/store` 已有 23 个测试文件，但**唯一的往返锁**（R475 `dc_01`）只盯 `created_by`
/// 一个字段。而 R148 实测过同类事故的形状 —— `from_db` 的**位置参数接错**（列序与参数序不符），
/// 那种错误**不会报错、单字段测试也不会红**，只是某些字段静默变成默认值。
///
/// 本格把**每一个可变字段都设成非默认值**，写进 SQLite 再读回，逐字段比对：
/// 谁没落库 / 谁被错位覆盖，都会在这里红。

///|
test "task_all_fields_round_trip_through_sqlite" {
  let db = dc_unique_db("task_all_fields_rt")
  match SqliteStore::open(db) {
    None => fail("open task roundtrip db failed")
    Some(store) => {
      let backend = StoreBackend::sqlite(store)
      let t = @core.Task::new(
        id="T-rt-all-1",
        project_dir="temp/rt-proj",
        description="全字段往返：含中文、含 \"引号\"、含逗号,与换行符\n第二行",
        priority="高",
        importance="高",
        depth=5,
        split_n=7,
        level=4,
        parent_id="T-parent-9",
        assignee="agent-rt",
        cleanup_mode="immediate",
        created_at="2026-10-29T12:34:56Z",
        ns="rt-wbtest",
        depends_on=["T-dep-a", "T-dep-b"],
        omega_required=true,
        created_by="human_steward",
      )
      match backend.create_task(t) {
        Ok(_) => ()
        Err(e) => fail("create_task failed: " + e)
      }
      match backend.get_task("T-rt-all-1") {
        None => fail("读不回来 —— 落库失败")
        Some(b) => {
          assert_eq(b.id, "T-rt-all-1")
          assert_eq(b.project_dir, "temp/rt-proj")
          assert_eq(b.ns, "rt-wbtest")
          assert_eq(b.priority, "高")
          assert_eq(b.importance, "高")
          assert_eq(b.depth, 5)
          assert_eq(b.split_n, 7)
          assert_eq(b.level, 4)
          assert_eq(b.parent_id, Some("T-parent-9"))
          assert_eq(b.assignee, Some("agent-rt"))
          assert_eq(b.cleanup_mode, "immediate")
          assert_eq(b.created_at, "2026-10-29T12:34:56Z")
          assert_eq(b.created_by, "human_steward")
          assert_eq(b.omega_required, true)
          assert_eq(b.depends_on.length(), 2)
          // description 含中文/引号/逗号/换行 ⇒ 逐字往返（防止存储面转义吃掉）
          assert_eq(
            b.description,
            "全字段往返：含中文、含 \"引号\"、含逗号,与换行符\n第二行",
          )
        }
      }
    }
  }
}
