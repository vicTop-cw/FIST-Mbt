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

///|
/// T0r53：longrun 四列 · **create 路径** —— 非默认值必须逐字往返。
///
/// 为什么需要：R191 主格走 `Task::new`，而 longrun 四字段默认全空（""/""/0/[]），
/// 在 sqlite 层**从未被验证过** —— INSERT 绑定位（21..24）若错位一格，字段会静默
/// 互换或落默认值，主格不会红（R148 同类事故形状：位置参数接错不报错）。
/// 本格四列各设**不同**的非默认值再逐字段比对：错位会让相邻字段「值互换」，
/// 逐字段比对当场抓住，而不是等 longrun checkpoint/resume 真跑起来才暴露。
test "task_longrun_fields_round_trip_create" {
  let db = dc_unique_db("task_lr_fields_ct")
  match SqliteStore::open(db) {
    None => fail("open longrun create db failed")
    Some(store) => {
      let backend = StoreBackend::sqlite(store)
      let t = @core.Task::new(
        id="T-lr-ct-1",
        project_dir="temp/lr-proj",
        description="longrun 四列往返（create 路径）",
        ns="lr-wbtest",
        checkpoint_path="temp/lr-proj/.fist-mbt/longrun/T-lr-ct-1.json",
        last_baton="{\"next_step\":\"resume\"}",
        budget_used=42L,
        idempotency_keys=["k-ct-1", "k-ct-2"],
      )
      match backend.create_task(t) {
        Ok(_) => ()
        Err(e) => fail("create_task failed: " + e)
      }
      match backend.get_task("T-lr-ct-1") {
        None => fail("读不回来 —— 落库失败")
        Some(b) => {
          assert_eq(
            b.checkpoint_path,
            "temp/lr-proj/.fist-mbt/longrun/T-lr-ct-1.json",
          )
          assert_eq(b.last_baton, "{\"next_step\":\"resume\"}")
          assert_eq(b.budget_used, 42L)
          assert_eq(b.idempotency_keys.length(), 2)
          assert_eq(b.idempotency_keys[0], "k-ct-1")
          assert_eq(b.idempotency_keys[1], "k-ct-2")
        }
      }
    }
  }
}

///|
/// T0r53：longrun 四列 · **update 路径** —— `update_task` 写回必须逐字往返。
///
/// UPDATE 绑定位（19..22 + WHERE id 占第 23 位）与 INSERT（21..24）**不同**，
/// 本格是这半边唯一的行为锁：若 WHERE id 绑错位（idempotency_keys 槽拿到 id ⇒
/// WHERE id=NULL）⇒ UPDATE 一行不改而 execute 仍报成功 ⇒ 四字段停在创建时的
/// 默认值，逐字段比对必红（store_sqlite.mbt:1249 注释钉的正是这一事故形状，
/// 但测试侧此前没有行为锁）。
/// 写入走 core 的两个唯一出口（`with_longrun_checkpoint` 增量预算 +
/// `idempotency_add` 追加键），顺带钉住「存储面不另立写路径」的口径。
test "task_longrun_fields_round_trip_update" {
  let db = dc_unique_db("task_lr_fields_up")
  match SqliteStore::open(db) {
    None => fail("open longrun update db failed")
    Some(store) => {
      let backend = StoreBackend::sqlite(store)
      let t = @core.Task::new(
        id="T-lr-up-1",
        project_dir="temp/lr-proj",
        description="longrun 四列往返（update 路径）",
        ns="lr-wbtest",
      )
      match backend.create_task(t) {
        Ok(_) => ()
        Err(e) => fail("create_task failed: " + e)
      }
      match backend.get_task("T-lr-up-1") {
        None => fail("读不回来 —— create 失败")
        Some(cur) => {
          let m = cur.with_longrun_checkpoint(
            "temp/lr-proj/.fist-mbt/longrun/T-lr-up-1.json", "{\"next_step\":\"guard\"}",
            42L, "2026-11-28T10:00:00Z",
          )
          let (m2, added) = m.idempotency_add("k-up-1", "2026-11-28T10:00:01Z")
          assert_true(added)
          match backend.update_task(m2) {
            Ok(_) => ()
            Err(e) => fail("update_task failed: " + e)
          }
          match backend.get_task("T-lr-up-1") {
            None => fail("update 后读不回来")
            Some(b) => {
              assert_eq(
                b.checkpoint_path,
                "temp/lr-proj/.fist-mbt/longrun/T-lr-up-1.json",
              )
              assert_eq(b.last_baton, "{\"next_step\":\"guard\"}")
              assert_eq(b.budget_used, 42L)
              assert_eq(b.idempotency_keys.length(), 1)
              assert_eq(b.idempotency_keys[0], "k-up-1")
              // update 路径不得动其他列（WHERE 错位时其他列也不该变——一并钉住）
              assert_eq(
                b.description,
                "longrun 四列往返（update 路径）",
              )
              assert_eq(b.ns, "lr-wbtest")
            }
          }
        }
      }
    }
  }
}
