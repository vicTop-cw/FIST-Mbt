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
  // project_dir 是合法**绝对**根时不得误杀：MCP 客户端真实传 `E:/proj/AI/rx-mbt`
  // 这类绝对路径，判成 NoProjectDir 会让门本身变成瘫痪开关。此时照样按白名单裁决。
  assert_true(
    wg_is_allow(write_gate("E:/proj/AI/rx-mbt", "memory/target.md")),
  )
  assert_true(wg_is_allow(write_gate("C:/abs", "memory/target.md")))
  assert_true(wg_is_allow(write_gate("/abs", "memory/target.md")))
  assert_true(wg_is_allow(write_gate("\\abs", "memory/target.md")))
  assert_true(wg_is_allow(write_gate("a/../b", "memory/target.md")))
  // 即便 project_dir 是绝对路径，越界的**目标路径**照样 Reject（门钉在 rel 上）
  assert_true(
    wg_reject_contains(
      write_gate("E:/proj/AI/rx-mbt", "src/foo.mbt"),
      "越界",
    ),
  )
  assert_true(
    wg_reject_contains(
      write_gate("E:/proj/AI/rx-mbt", "C:/temp/x.md"),
      "越界",
    ),
  )
  assert_true(
    wg_reject_contains(
      write_gate("E:/proj/AI/rx-mbt", "../escape.md"),
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

///|
/// 便利：ns 写门返回 Err 且文案含关键字。
fn nwg_err(ns : String, needle : String) -> Bool {
  match ns_write_gate(ns) {
    Err(e) => e.contains(needle)
    Ok(_) => false
  }
}

///|
/// ns 写门锁 1：default / 空 ns 一律拒绝（污染源），且指路"先 store_open"。
test "nwg_1_default_and_empty_rejected" {
  assert_true(nwg_err("default", "拒绝写入 default"))
  assert_true(nwg_err("", "拒绝写入 default"))
  assert_true(nwg_err("", "store_open"))
}

///|
/// ns 写门锁 2：合法项目 ns 允许写入（字母数字 / 下划线 / 连字符）。
test "nwg_2_legal_ns_allowed" {
  assert_true(ns_write_gate("fist-mbt-refactor") is Ok(_))
  assert_true(ns_write_gate("cron-auto") is Ok(_))
  assert_true(ns_write_gate("tnr_polish") is Ok(_))
  assert_true(ns_write_gate("T0r3alpha9") is Ok(_))
}

///|
/// ns 写门锁 3：非法 ns 拒绝（空格 / 路径穿越 / 盘符 / 前导分隔符 / 点号）。
/// 与 `MultiStore::safe_ns` 同族口径：只放字母数字与 _ -。
test "nwg_3_illegal_ns_rejected" {
  assert_true(nwg_err("../evil", "非法命名空间"))
  assert_true(nwg_err("C:default", "非法命名空间"))
  assert_true(nwg_err("/abs/path", "非法命名空间"))
  assert_true(nwg_err("my ns", "非法命名空间"))
  assert_true(nwg_err("T0r3.alpha9", "非法命名空间"))
}

///|
/// BUG-389 锁 1：旧位置存量库检测——目录/文件不存在时 false，真有 `<ns>.db` 才 true。
/// 复现路径：BUG-78 改默认 data_dir 但没迁存量库，cwd 根留 `<ns>.db`，重启后落新空库
/// → 任务"凭空消失"。此锁钉住 legacy_store_exists_in 的检测逻辑，防回归到静默开空库。
test "lsm_1_legacy_store_detected" {
  // 目录不存在 → false（is_file raise IOError 被 catch 成 false）
  assert_false(legacy_store_exists_in("temp/bug389-nonexistent-dir", "alpha"))
  // 目录存在但无 <ns>.db → false
  @fs.create_dir("temp/bug389-test") catch {
    _ => ()
  }
  assert_false(legacy_store_exists_in("temp/bug389-test", "alpha"))
  // 写 <ns>.db → true（存量库被识别）
  @fs.write_string_to_file("temp/bug389-test/alpha.db", "") catch {
    _ => ()
  }
  assert_true(legacy_store_exists_in("temp/bug389-test", "alpha"))
  // 别的 ns 仍 false（不误判）
  assert_false(legacy_store_exists_in("temp/bug389-test", "beta"))
  // 清理
  @fs.remove_file("temp/bug389-test/alpha.db") catch {
    _ => ()
  }
}

///|
/// BUG-389 锁 2：便捷版 `legacy_store_exists` 在无存量库的 ns 上返回 false（不会误开旧库）。
/// 测试只在 temp/ 做文件存在性探测，不落 cwd 根，避免污染仓库根。
test "lsm_2_no_legacy_false" {
  assert_false(legacy_store_exists("this-ns-has-no-legacy-db-xyz"))
}
