///|
// BUG-420 白盒锁（server 侧 · C 案「查不到时可诊断」+ A 案只读回落）
//
// 这是 handler 决策面的锁（`ns_misroute_probe_in` / `with_resolved_from`），
// 用**真引擎**（内存后端）摆出「主库有同 ns 任务 + ns 库空」的形状，而不是把文案
// 当纯字符串断言——文案纯函数另有 src/store/multi_store_bug420_wbtest.mbt 的锁。
//
// 三条形状各一格：
//  ① 主库有 + 标签等于请求 ns ⇒ 探针命中，文案指出「任务在主库」
//  ② 主库也没有 ⇒ 不命中（真·ID 写错必须保持原文案，不许伪装成路由错位）
//  ③ 主库有但标签是别的 ns ⇒ 不命中（这时报「路由错位」同样是假诊断）
// 另锁 A 案只读回落的回执标注 `resolved_from=default(main)` 且原字段不丢。

///|
test "bug420_4_probe_shape: 主库有同 ns 任务 + ns 库为空 ⇒ 命中" {
  let main = @engine.FistEngine::new()
  let main_id = match
    main.publish(
      project_dir="/proj/demo",
      description="BUG-420 形状：历史任务的 ns 标签是 bugs，物理行在主库",
      created_by="human_steward",
      now="2026-10-26T00:00:00Z",
      ns="bugs",
    ) {
    Ok(id) => id
    Err(e) => abort("publish 失败: \{e}")
  }
  // ns 专库（另一个引擎＝另一个物理库）：里面**没有**这条任务
  let ns_eng = @engine.FistEngine::new()
  assert_true(ns_eng.get_task(main_id) is None)
  // ① 命中：返回主库那条任务的 ns 标签（文案要引用它）
  match ns_misroute_probe_in(main, main_id, "bugs") {
    Some(ns) => assert_eq(ns, "bugs")
    None =>
      fail(
        "探针没命中：主库有同 ns 任务这一形状必须可诊断",
      )
  }
  // ② 主库也没有 ⇒ 不命中（保持原文案）
  assert_true(ns_misroute_probe_in(main, "Tnotexist", "bugs") is None)
  // ③ 标签不一致 ⇒ 不命中（不许把它说成路由错位）
  assert_true(ns_misroute_probe_in(main, main_id, "other-ns") is None)
  // ④ default / 空 ns 直通主库，无需探测
  assert_true(ns_misroute_probe_in(main, main_id, "default") is None)
  assert_true(ns_misroute_probe_in(main, main_id, "") is None)
}

///|
test "bug420_5_error_text: 查不到时文案指出主库（而不是只说 task not found）" {
  let main = @engine.FistEngine::new()
  let main_id = match
    main.publish(
      project_dir="/proj/demo",
      description="BUG-420 文案锁",
      created_by="human_steward",
      now="2026-10-26T00:00:00Z",
      ns="bugs",
    ) {
    Ok(id) => id
    Err(e) => abort("publish 失败: \{e}")
  }
  let main_ns = match ns_misroute_probe_in(main, main_id, "bugs") {
    Some(ns) => ns
    None => fail("探针没命中")
  }
  let msg = @store.ns_misroute_not_found(main_id, "bugs", main_ns)
  // 三条硬要求：主库点名 / ns 标签点名 / BUG-420 点名（+ 出路）
  assert_true(msg.contains("主库"))
  assert_true(msg.contains("ns 标签=bugs"))
  assert_true(msg.contains("BUG-420"))
  assert_true(msg.contains("去掉 namespace"))
  // 反向自证：不能把「主库也没有」也写成路由错位（那时应保持原文案）
  assert_true(ns_misroute_probe_in(main, "Tnotexist", "bugs") is None)
}

///|
test "bug420_6_a_case_readonly: 只读回落回执带 resolved_from 且原字段不丢" {
  let main = @engine.FistEngine::new()
  let main_id = match
    main.publish(
      project_dir="/proj/demo",
      description="BUG-420 A 案只读回落",
      created_by="human_steward",
      now="2026-10-26T00:00:00Z",
      ns="bugs",
    ) {
    Ok(id) => id
    Err(e) => abort("publish 失败: \{e}")
  }
  match main.get_task(main_id) {
    None => fail("主库取不到任务：A 案回落面根本没跑到")
    Some(t) => {
      let j = with_resolved_from(t.to_json(), "default(main)", "bugs")
      match jget(j, "resolved_from") {
        Some(String(s)) => assert_eq(s, "default(main)")
        _ => fail("回执缺 resolved_from: " + j.stringify())
      }
      match jget(j, "namespace_requested") {
        Some(String(s)) => assert_eq(s, "bugs")
        _ => fail("回执缺 namespace_requested: " + j.stringify())
      }
      // 摊平而非包一层：原任务字段必须仍在（否则调用方得改解析路径）
      match jget(j, "id") {
        Some(String(s)) => assert_eq(s, main_id)
        _ => fail("回执丢了 id: " + j.stringify())
      }
      match jget(j, "namespace") {
        Some(String(s)) => assert_eq(s, "bugs")
        _ => fail("回执丢了 namespace: " + j.stringify())
      }
    }
  }
}

///|
test "bug420_7_archive_text_gate: 只有 not found 才换文案，判据拒绝原样透出" {
  let nf = "task not found: T0r741"
  // ① 没找到 + 探针命中 ⇒ 换成路由错位诊断（并附原错误）
  let hit = bug420_archive_error_text(nf, "T0r741", "bugs", Some("bugs"))
  assert_true(hit.contains("BUG-420"))
  assert_true(hit.contains("主库"))
  assert_true(hit.contains("写路径不回落"))
  assert_true(hit.contains(nf))
  // ② 没找到 + 探针未命中 ⇒ 原样（真·ID 写错不许伪装成路由错位）
  assert_eq(bug420_archive_error_text(nf, "T0r741", "bugs", None), nf)
  // ③ **判据拒绝**（Omega 门）即便探针命中也不许改写：
  //    把「验收没过」说成「数据找不到」比原来的报错更难查
  let omega = "Omega 门禁拦截归档: 成果未通过复验"
  assert_eq(
    bug420_archive_error_text(omega, "T0r741", "bugs", Some("bugs")),
    omega,
  )
  // ④ 状态门拒绝同理
  let state = "仅已完成任务可归档，当前状态: 执行中"
  assert_eq(
    bug420_archive_error_text(state, "T0r741", "bugs", Some("bugs")),
    state,
  )
}
