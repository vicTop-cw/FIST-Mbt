/// write_gate_wbtest.mbt —— T0r3「核心写入门禁」白盒锁
///
/// 三态逐一锁死：Allow / Reject / NoProjectDir；另锁 `write_gate_ok` 与
/// `write_gate_audit`（后者锁"越界必落审计"）。
/// 裁决口径：白名单 = `<target>/.fist-mbt/`、`<target>/fist-mbt/`、
/// `<target>/memory/`、`<target>/reports/`、`<target>/plans/`；其余 Reject；
/// project_dir 非法 NoProjectDir（fail-closed）。

///|
/// 便利：三态是否等于 Allow。
fn wg_is_allow(v : WriteVerdict) -> Bool {
  v is Allow
}

///|
/// 便利：三态是否等于 Reject 且 reason 含指定关键字。
fn wg_reject_contains(v : WriteVerdict, needle : String) -> Bool {
  match v {
    Reject(r) => r.contains(needle)
    _ => false
  }
}

///|
/// 便利：三态是否等于 NoProjectDir。
fn wg_is_no_dir(v : WriteVerdict) -> Bool {
  v is NoProjectDir
}

///|
test "wg_1_allow_fist_dotdir_and_artifacts" {
  // 白名单内（目标项目内）→ Allow
  assert_true(
    wg_is_allow(write_gate("temp/wg_p1", ".fist-mbt/data/default.db")),
  )
  assert_true(wg_is_allow(write_gate("temp/wg_p1", ".fist-mbt/locks/lk1")))
  assert_true(wg_is_allow(write_gate("temp/wg_p1", "fist-mbt/reports/r1.md")))
  assert_true(wg_is_allow(write_gate("temp/wg_p1", "memory/target.md")))
  assert_true(wg_is_allow(write_gate("temp/wg_p1", "memory/bugs.md")))
  assert_true(wg_is_allow(write_gate("temp/wg_p1", "memory/links.md")))
  assert_true(wg_is_allow(write_gate("temp/wg_p1", "memory/reviews/r.md")))
  assert_true(wg_is_allow(write_gate("temp/wg_p1", "reports/2026-10-22.md")))
  assert_true(wg_is_allow(write_gate("temp/wg_p1", "plans/plan-a.md")))
  // 反斜杠分隔也允许（Windows 兼容）
  assert_true(wg_is_allow(write_gate("temp/wg_p1", "memory\\target.md")))
}

///|
test "wg_2_reject_out_of_scope_src_absolute_dotdot" {
  // 越界：源码目录
  assert_true(
    wg_reject_contains(write_gate("temp/wg_p1", "src/foo.mbt"), "越界"),
  )
  assert_true(
    wg_reject_contains(
      write_gate("temp/wg_p1", "src/server/write_gate.mbt"),
      "越界",
    ),
  )
  // 越界：绝对路径 / 前导分隔符 / 盘符 / `..`
  assert_true(
    wg_reject_contains(write_gate("temp/wg_p1", "/etc/passwd"), "越界"),
  )
  assert_true(
    wg_reject_contains(write_gate("temp/wg_p1", "\\Windows\\x"), "越界"),
  )
  assert_true(
    wg_reject_contains(write_gate("temp/wg_p1", "C:/temp/x.md"), "越界"),
  )
  assert_true(
    wg_reject_contains(write_gate("temp/wg_p1", "../escape.md"), "越界"),
  )
  assert_true(
    wg_reject_contains(write_gate("temp/wg_p1", "a/../b.md"), "越界"),
  )
  // 白名单外的普通相对路径也拒
  assert_true(
    wg_reject_contains(write_gate("temp/wg_p1", "docs/x.md"), "越界"),
  )
  assert_true(
    wg_reject_contains(write_gate("temp/wg_p1", "logs/app.log"), "越界"),
  )
  // Reject 回执必须带建议白名单
  match write_gate("temp/wg_p1", "src/foo.mbt") {
    Reject(r) => {
      assert_true(r.contains(".fist-mbt/"))
      assert_true(r.contains("fist-mbt/"))
      assert_true(r.contains("memory/"))
    }
    _ => abort("应 Reject")
  }
}

///|
test "wg_3_no_project_dir_fail_closed" {
  // 只有 project_dir 为空才 NoProjectDir（fail-closed：宁拒不放）
  assert_true(wg_is_no_dir(write_gate("", "memory/target.md")))
  // project_dir 是合法**绝对**根时不得误杀：MCP 客户端真实传 `E:/IDEProjects/AI/rx-mbt`
  // 这类绝对路径，判成 NoProjectDir 会让门本身变成瘫痪开关。此时照样按白名单裁决。
  assert_true(
    wg_is_allow(write_gate("E:/IDEProjects/AI/rx-mbt", "memory/target.md")),
  )
  assert_true(wg_is_allow(write_gate("C:/abs", "memory/target.md")))
  assert_true(wg_is_allow(write_gate("/abs", "memory/target.md")))
  assert_true(wg_is_allow(write_gate("\\abs", "memory/target.md")))
  assert_true(wg_is_allow(write_gate("a/../b", "memory/target.md")))
  // 即便 project_dir 是绝对路径，越界的**目标路径**照样 Reject（门钉在 rel 上）
  assert_true(
    wg_reject_contains(
      write_gate("E:/IDEProjects/AI/rx-mbt", "src/foo.mbt"),
      "越界",
    ),
  )
  assert_true(
    wg_reject_contains(
      write_gate("E:/IDEProjects/AI/rx-mbt", "C:/temp/x.md"),
      "越界",
    ),
  )
  assert_true(
    wg_reject_contains(
      write_gate("E:/IDEProjects/AI/rx-mbt", "../escape.md"),
      "越界",
    ),
  )
}

///|
test "wg_4_write_gate_ok_result_shape" {
  assert_true(write_gate_ok("temp/wg_p1", "memory/target.md") is Ok(_))
  assert_true(write_gate_ok("temp/wg_p1", ".fist-mbt/data/x.db") is Ok(_))
  assert_true(write_gate_ok("temp/wg_p1", "src/foo.mbt") is Err(_))
  match write_gate_ok("temp/wg_p1", "src/foo.mbt") {
    Err(e) => assert_true(e.contains("write_gate"))
    _ => abort("应 Err")
  }
  // NoProjectDir 走 Err 分支（fail-closed）
  assert_true(write_gate_ok("", "memory/target.md") is Err(_))
}

///|
test "wg_5_write_gate_audit_records_reject" {
  let al = @ops.AuditLog::new()
  // Allow 不落审计
  assert_true(
    write_gate_audit(
      "temp/wg_p1", "memory/target.md", al, "2026-10-22T10:00:00Z", "selfdrive_append",
    )
    is Ok(_),
  )
  assert_eq(al.entries().length(), 0)
  // Reject 落一条审计
  let r1 = write_gate_audit(
    "temp/wg_p1", "src/foo.mbt", al, "2026-10-22T10:00:01Z", "selfdrive_append",
  )
  assert_true(r1 is Err(_))
  assert_eq(al.entries().length(), 1)
  assert_eq(al.entries()[0].action, "write_gate:reject")
  assert_true(al.entries()[0].detail.contains("src/foo.mbt"))
  // NoProjectDir 也落一条
  let r2 = write_gate_audit(
    "", "memory/target.md", al, "2026-10-22T10:00:02Z", "memory_consolidate",
  )
  assert_true(r2 is Err(_))
  assert_eq(al.entries().length(), 2)
}
