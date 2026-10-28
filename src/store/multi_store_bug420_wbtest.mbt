///|
// BUG-420 白盒锁（C 案 · 止血 + 可诊断）
//
// 锁三件：
//  ① **形状**：主库 `fist-mbt.db` 里有带某 ns 标签的任务、而该 ns 的物理库为空
//     —— 用**真 SQLite** 摆一遍（不是把判据喂给纯函数就算数：那样锁不到
//     `ns_task_count` 与 `list_tasks_in` 两个取数面）。
//  ② **不制造恒阳性**：分库已有数据 / 主库无该标签 / ns 是 default 或空 ⇒ 必须回空串。
//  ③ **文案可行动**：查不到的文案必须点名「主库」「ns 标签」「BUG-420」「去掉 namespace」，
//     否则它和原来的 `task not found: X` 一样，只会把调用方引向「ID 写错了」。

///|
/// 清空一个物理库（测试可重复执行；sqlite 文件跨 run 残留会让「本库为 0 条」这一格假红）。
fn bug420_reset(path : String) -> Unit {
  match SqliteStore::open(path) {
    Some(s) => ignore(s.clear())
    None => ()
  }
}

///|
/// 往指定库写一条带 ns 标签的任务（id 由调用方给，避免主键冲突）。
fn bug420_put(store : SqliteStore, id : String, ns : String) -> Unit {
  let t = @core.Task::new(
    id~,
    project_dir="/proj/demo",
    description="BUG-420 shape",
    created_at="2026-10-26T00:00:00Z",
    ns~,
  )
  match store.create_task(t) {
    Ok(_) => ()
    Err(msg) => abort("create_task 失败: \{msg}")
  }
}

///|
test "bug420_1_shape: 主库有 2 条带 ns 标签的任务 + 该 ns 分库为 0 条 ⇒ 出诊断" {
  let main_path = bug462_unique_db("bug420_main_wb")
  bug420_reset(main_path)
  let ms = MultiStore::new(data_dir="temp")
  assert_eq(ms.open(ns="bug420probe", data_dir="temp"), true)
  // 分库也清一次（上次 run 残留不算数）
  match ms.get("bug420probe") {
    Some(s) => ignore(s.clear())
    None => ()
  }
  match SqliteStore::open(main_path) {
    None => fail("sqlite open 失败：判据根本没跑到被测面")
    Some(main) => {
      bug420_put(main, "T9a", "bug420probe")
      bug420_put(main, "T9b", "bug420probe")
      // 两条读数分别来自两个取数面：主库按标签过滤、分库按物理库计数
      let main_n = main.list_tasks_in("bug420probe").length()
      let store_n = ms.ns_task_count("bug420probe")
      assert_eq(main_n, 2)
      assert_eq(store_n, 0)
      let w = ns_routing_warning("bug420probe", main_n, store_n)
      // 文案必须把「几个数 + 为什么 + 两条出路」都说清
      assert_true(w.contains("BUG-420"))
      assert_true(w.contains("2 条"))
      assert_true(w.contains("bug420probe"))
      assert_true(w.contains("按 ns 查询会找不到它们"))
      assert_true(w.contains("不传 namespace"))
      assert_true(w.contains("A 案"))
      // 第三格：分库写进 1 条之后，形状不再是「本库空」⇒ 不许再告警
      match ms.get("bug420probe") {
        Some(s) => {
          bug420_put(s, "T9c", "bug420probe")
          assert_eq(ms.ns_task_count("bug420probe"), 1)
          assert_eq(
            ns_routing_warning(
              "bug420probe",
              main_n,
              ms.ns_task_count("bug420probe"),
            ),
            "",
          )
        }
        None => fail("分库句柄取不到")
      }
    }
  }
}

///|
test "bug420_2_no_false_positive: 合法情形一律不告警（拒绝恒阳性）" {
  // 主库没有该标签
  assert_eq(ns_routing_warning("nobody-label", 0, 0), "")
  // 分库有数据（写入路径正常）
  assert_eq(ns_routing_warning("ok-ns", 5, 3), "")
  // default / 空 ns 本来就走主库，不存在路由错位
  assert_eq(ns_routing_warning("default", 9, 0), "")
  assert_eq(ns_routing_warning("", 9, 0), "")
  // 恰好一边为 0 的另一半形状：主库 0 条 + 分库 0 条 ⇒ 无历史数据，不必告警
  assert_eq(ns_routing_warning("empty-ns", 0, 0), "")
}

///|
test "bug420_3_misroute_text: 查不到的文案点名主库/标签/出路（不是 review 完就完）" {
  let msg = ns_misroute_not_found("T0r741", "bugs", "bugs")
  assert_true(msg.contains("task not found: T0r741"))
  assert_true(msg.contains("主库"))
  assert_true(msg.contains("ns 标签=bugs"))
  assert_true(msg.contains("BUG-420"))
  assert_true(msg.contains("去掉 namespace"))
  assert_true(msg.contains("resolve_from_main=true"))
  // 任务 id 与请求 ns 都必须出现在文案里（否则排障还得再查一次）
  let msg2 = ns_misroute_not_found(
    "T0r636.1.2", "fist-opt-20261016", "fist-opt-20261016",
  )
  assert_true(msg2.contains("T0r636.1.2"))
  assert_true(msg2.contains("fist-opt-20261016"))
}
