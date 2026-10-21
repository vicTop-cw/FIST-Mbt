// docs_gate_test.mbt —— 「文档即实现」验收门禁（docs_check 可选开关）测试。
//
// 覆盖：
//   1) docs_check 默认关闭时 verify 行为与现状完全一致（不校验文档，正常通过）
//   2) docs_check=true 且无 README/CHANGELOG/reports → verify 返回 Err（含 item 明细）
//   3) docs_check=true 且项目结构齐全 + 交付物回传五段式 → verify 通过
//
// 用纯内存 FistEngine，不依赖共享 fist-mbt.db。

///|
fn dg_engine() -> @engine.FistEngine {
  @engine.FistEngine::new()
}

///|
/// 造一个到「待验收」的任务：publish → execute → submit。
fn dg_make_reviewing(
  e : @engine.FistEngine,
  project_dir : String,
  deliverable : String,
) -> String {
  let id = match
    e.publish(
      project_dir~,
      description="文档门禁测试任务",
      created_by="human_steward",
      now="2026-09-20T09:00:00Z",
    ) {
    Ok(x) => x
    Err(m) => abort("publish failed: \{m}")
  }
  ignore(e.claim(task_id=id, assignee="exec", now="2026-09-20T09:01:00Z"))
  match
    e.execute_with_meta(
      task_id=id,
      deliverable~,
      now="2026-09-20T09:02:00Z",
      executor="exec",
    ) {
    Ok(_) => ()
    Err(m) => abort("execute failed: \{m}")
  }
  match e.submit(task_id=id, now="2026-09-20T09:03:00Z") {
    Ok(_) => ()
    Err(m) => abort("submit failed: \{m}")
  }
  id
}

///|
fn dg_make_temp_dir(name : String, with_docs? : Bool = false) -> String {
  @fs.create_dir("temp") catch {
    _ => ()
  }
  let d = "temp/" + name
  @fs.create_dir(d) catch {
    _ => ()
  }
  if with_docs {
    // 造出 README.md / CHANGELOG.md / reports/，模拟「文档即实现」齐全的项目
    @fs.write_string_to_file(d + "/README.md", "# demo", encoding="utf8") catch {
      _ => ()
    }
    @fs.write_string_to_file(d + "/CHANGELOG.md", "## 0.1", encoding="utf8") catch {
      _ => ()
    }
    @fs.create_dir(d + "/reports") catch {
      _ => ()
    }
  }
  d
}

///|
test "docs_gate_default_off_pass" {
  // docs_check 未传（默认 false）：不校验文档，正常验收通过
  let e = dg_engine()
  let d = dg_make_temp_dir("dg_c1", with_docs=false)
  let id = dg_make_reviewing(
    e, d, "交付物内容：结论 / 证据 / 分析 / 缺口与风险 / 建议入档位置",
  )
  let _ = e.verify(task_id=id, verifier="verifier", now="2026-09-20T09:04:00Z")
  assert_eq(e.get_task(id).unwrap().get_status().to_string(), "已完成")
}

///|
test "docs_gate_enabled_missing_docs_rejected" {
  // docs_check=true 但项目无 README/CHANGELOG/reports → 打回
  let e = dg_engine()
  let d = dg_make_temp_dir("dg_c2", with_docs=false)
  let id = dg_make_reviewing(
    e, d, "交付物内容：结论 / 证据 / 分析 / 缺口与风险 / 建议入档位置",
  )
  match
    e.verify(
      task_id=id,
      verifier="verifier",
      now="2026-09-20T09:04:00Z",
      docs_check=true,
    ) {
    Err(msg) => {
      assert_true(msg.contains("文档一致性门禁"))
      assert_true(msg.contains("README"))
    }
    Ok(_) => abort("应因缺文档而被打回")
  }
}

///|
test "docs_gate_enabled_ok_with_docs_and_sections" {
  // docs_check=true 且 README/CHANGELOG/reports 齐全 + 回传含五段式 → 通过
  let e = dg_engine()
  let d = dg_make_temp_dir("dg_c3", with_docs=true)
  let id = dg_make_reviewing(
    e, d, "结论：通过\n证据：见测试\n分析：已核对\n缺口与风险：无\n建议入档位置：docs/",
  )
  let _ = e.verify(
    task_id=id,
    verifier="verifier",
    now="2026-09-20T09:04:00Z",
    docs_check=true,
  )
  assert_eq(e.get_task(id).unwrap().get_status().to_string(), "已完成")
}
