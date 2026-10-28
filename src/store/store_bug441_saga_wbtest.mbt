// ============================================================================
// BUG-441 Saga 三方法内存后端的锁（Lane AZ）
//
// 病灶：`StoreBackend` 的三个 saga 方法在内存后端全是占位：
//   write_saga_action      Mem(_) => Ok(())    ← 静默丢弃
//   list_saga_actions      Mem(_) => []        ← 恒空
//   mark_saga_actions_done Mem(_) => Ok(())    ← 静默无操作
// ⇒ **补偿序列静默为空**：saga_rollback 永远"没有待补偿步骤"、saga_repair 永远找不到切片。
//
// ⚠️ 这比 BUG-439（熔断器）更隐蔽：熔断器 state 恒 closed 还算有点异常，
// 而「没有待补偿步骤」在**任何正常系统里都合法** —— 空列表不是错误信号。
// ⇒ 所以锁必须证明「能累积」，不能只证明「不报错」。
//
// 判例-30 防护：断言的是**运行时返回值**，不是源码字符串。
// ============================================================================

///|
/// 【锁 1】内存后端 `write_saga_action` 后 `list_saga_actions` **能读回**（此前恒空）。
///
/// 变异（改回 `Mem(_) => []`）⇒ 本格红。
test "bug441_mem_saga_write_then_list_roundtrip" {
  let b = StoreBackend::memory()
  // 空 Log
  assert_eq(b.list_saga_actions("ns1", "root-1").length(), 0)
  // 写三步
  ignore(
    b.write_saga_action(
      ns="ns1",
      root_task_id="root-1",
      step="s1",
      compensation="undo-1",
      created_at="t1",
    ),
  )
  ignore(
    b.write_saga_action(
      ns="ns1",
      root_task_id="root-1",
      step="s2",
      compensation="undo-2",
      created_at="t2",
    ),
  )
  ignore(
    b.write_saga_action(
      ns="ns1",
      root_task_id="root-1",
      step="s3",
      compensation="undo-3",
      created_at="t3",
    ),
  )
  // ★ 必须读回 3 条（修前恒 0）
  let rows = b.list_saga_actions("ns1", "root-1")
  assert_eq(rows.length(), 3)
  // 前向顺序（登记顺序）
  assert_eq(rows[0].1, "s1")
  assert_eq(rows[1].1, "s2")
  assert_eq(rows[2].1, "s3")
  // 内容与状态
  assert_eq(rows[0].3, "undo-1")
  assert_eq(rows[0].4, "pending")
}

///|
/// 【锁 2】内存后端 `mark_saga_actions_done` 后，列表里对应项 status 变 `done`
/// （此前 no-op ⇒ mark 了但列表不变，rollback 会**重复补偿**）。
test "bug441_mem_saga_mark_done_is_visible" {
  let b = StoreBackend::memory()
  ignore(
    b.write_saga_action(
      ns="ns1",
      root_task_id="root-2",
      step="a",
      compensation="u-a",
      created_at="t",
    ),
  )
  ignore(
    b.write_saga_action(
      ns="ns1",
      root_task_id="root-2",
      step="b",
      compensation="u-b",
      created_at="t",
    ),
  )
  let rows0 = b.list_saga_actions("ns1", "root-2")
  assert_eq(rows0.length(), 2)
  let id_a = rows0[0].0
  // 标记第一条 done
  ignore(b.mark_saga_actions_done(ns="ns1", root_task_id="root-2", ids=[id_a]))
  let rows1 = b.list_saga_actions("ns1", "root-2")
  assert_eq(rows1.length(), 2) // 行数不变（不是删除，是改状态）
  assert_eq(rows1[0].4, "done") // ★ 第一条 done
  assert_eq(rows1[1].4, "pending") // 第二条仍 pending
  // 幂等：再 mark 一次不炸
  ignore(b.mark_saga_actions_done(ns="ns1", root_task_id="root-2", ids=[id_a]))
  assert_eq(b.list_saga_actions("ns1", "root-2")[0].4, "done")
}

///|
/// 【锁 3】同 `(ns, root_task_id, step)` **重复登记是就地更新**，不新增行、不改 id。
///
/// 与 SQLite 的 `ON CONFLICT(ns, root_task_id, step) DO UPDATE` 同口径。
/// 若实现成「每次 push」⇒ 行数会变成 2、id 会变 ⇒ 本格红。
test "bug441_mem_saga_write_is_idempotent_by_step" {
  let b = StoreBackend::memory()
  ignore(
    b.write_saga_action(
      ns="ns1",
      root_task_id="root-3",
      step="dup",
      compensation="v1",
      created_at="t1",
    ),
  )
  let id_first = b.list_saga_actions("ns1", "root-3")[0].0
  // 同 step 再写一次（补偿描述改了）
  ignore(
    b.write_saga_action(
      ns="ns1",
      root_task_id="root-3",
      step="dup",
      compensation="v2",
      created_at="t2",
    ),
  )
  let rows = b.list_saga_actions("ns1", "root-3")
  assert_eq(rows.length(), 1) // ★ 不新增行
  assert_eq(rows[0].0, id_first) // ★ id 不变
  assert_eq(rows[0].3, "v2") // 内容更新
}

///|
/// 【锁 4】不同 `(ns, root_task_id)` **不串味**（复合键正确性）。
test "bug441_mem_saga_keys_are_isolated" {
  let b = StoreBackend::memory()
  ignore(
    b.write_saga_action(
      ns="ns1",
      root_task_id="r",
      step="x",
      compensation="u",
      created_at="t",
    ),
  )
  // 不同 root
  assert_eq(b.list_saga_actions("ns1", "other").length(), 0)
  // 不同 ns（同名 root）
  assert_eq(b.list_saga_actions("ns2", "r").length(), 0)
  // 原样还在
  assert_eq(b.list_saga_actions("ns1", "r").length(), 1)
}

///|
/// 【锁 5】内存版与 SQLite 版 `list_saga_actions` **读回同形状**（五元组逐字段语义一致）。
///
/// 注意：`id` 的具体数值可能不同（内存版自增、SQLite AUTOINCREMENT），
/// 所以**只比 (step, task_id, compensation, status)** 四个语义字段 ——
/// 这正是「高精度」的取舍：不把「id 数值不同」误报成漂移。
test "bug441_mem_and_sql_saga_same_shape" {
  let mem = StoreBackend::memory()
  let sql = match SqliteStore::open(":memory:") {
    Some(s) => StoreBackend::sqlite(s)
    None => abort("sqlite open 失败：本格没跑到被测面")
  }
  for b in [mem, sql] {
    ignore(
      b.write_saga_action(
        root_task_id="R",
        step="p1",
        task_id="T1",
        compensation="c1",
        created_at="t",
      ),
    )
    ignore(
      b.write_saga_action(
        root_task_id="R",
        step="p2",
        task_id="T2",
        compensation="c2",
        created_at="t",
      ),
    )
  }
  let m = mem.list_saga_actions("default", "R")
  let s = sql.list_saga_actions("default", "R")
  assert_eq(m.length(), s.length())
  assert_eq(m.length(), 2)
  let mut i = 0
  while i < m.length() {
    // 只比语义四字段（id 数值可以不同）
    assert_eq(m[i].1, s[i].1) // step
    assert_eq(m[i].2, s[i].2) // task_id
    assert_eq(m[i].3, s[i].3) // compensation
    assert_eq(m[i].4, s[i].4) // status
    i = i + 1
  }
}
