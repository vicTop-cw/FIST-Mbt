/// bugreport_caller_cwd_wbtest.mbt —— FIST_CALLER_CWD 解析基准的白盒锁
///
/// 目标：CLI 通过 env `FIST_CALLER_CWD` 传入调用方 cwd 时，bug 工具的相对
/// `project_dir` 必须解析到调用方 cwd；env 不存在时逐字维持旧行为（server cwd）。
///
/// 三格：
///   1) env 有效 ⇒ 落点 / 回执都指向 caller cwd（且**不**落在 server cwd）；
///   2) env 不存在 ⇒ 与旧行为一致（server cwd + 相对 project_dir）；
///   3) `..` / 盘符 / 绝对路径仍被拒；env 非绝对路径时按「未设置」处理。
///
/// 全部在 `temp/` 下的唯一临时目录进行，不碰真实 `memory/bugs.md`；
/// 每格退出前还原 env（判例-31：env 污染同进程后续格）。
///
/// ⚠️ 这里同时锁住「派生绝对路径绝不回流 `bug_project_dir_ok`」：
/// 格 1 的 caller cwd 在 Windows 上是 `E:/...`（带盘符），若派生路径被拿去重校验，
/// report_bug 会直接 Err —— 格 1 成功本身就证伪了那条回路。

///|
fn ccw_str(j : Json, key : String) -> String {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(String(s)) => s
        _ => "<null>"
      }
    _ => "<null>"
  }
}

///|
fn ccw_save_env() -> String? {
  @env.get_env_var("FIST_CALLER_CWD")
}

///|
fn ccw_restore_env(old : String?) -> Unit {
  match old {
    None => @env.unset_env_var("FIST_CALLER_CWD")
    Some(v) => @env.set_env_var("FIST_CALLER_CWD", v)
  }
}

///|
/// 取结果，失败时先还原 env 再中断（不让 env 泄漏到后续格）。
fn ccw_unwrap(r : Result[Json, String], old : String?) -> Json {
  match r {
    Ok(j) => j
    Err(m) => {
      ccw_restore_env(old)
      abort("ccw wbtest 失败: " + m)
    }
  }
}

///|
/// server cwd 下的绝对临时目录（唯一 tag，避免格间串扰）。
fn ccw_abs_temp(tag : String) -> String {
  bug_abs_path(bug_server_cwd(), "temp/ccw_" + tag)
}

///|
/// 建好 caller cwd / project / memory 三层目录，返回 bugs.md 绝对路径。
fn ccw_seed_abs(caller : String, proj : String) -> String {
  let p = caller + "/" + proj
  @fs.create_dir("temp") catch {
    _ => ()
  }
  @fs.create_dir(caller) catch {
    _ => ()
  }
  @fs.create_dir(p) catch {
    _ => ()
  }
  @fs.create_dir(p + "/memory") catch {
    _ => ()
  }
  let ledger = p + "/memory/bugs.md"
  @fs.remove_file(ledger) catch {
    _ => ()
  }
  ledger
}

///|
/// 格 1：env 有效 ⇒ report_bug / bug_list / bug_mark_status / bug_fix 全落 caller cwd，
/// 回执 resolved_path 以 caller cwd 为基准；server_cwd 仍回显真实 server cwd。
test "ccw_01_valid_env_redirects_to_caller_cwd" {
  let old = ccw_save_env()
  let real_cwd = bug_server_cwd()
  let caller = ccw_abs_temp("01_valid")
  let proj = "proj_ccw01"
  let ledger = ccw_seed_abs(caller, proj)
  // 同一相对 project_dir 若按 server cwd 解析会落在哪——用来证明「没写错轨」
  let server_side = bug_abs_path(real_cwd, proj) + "/memory/bugs.md"
  @fs.remove_file(server_side) catch {
    _ => ()
  }

  @env.set_env_var("FIST_CALLER_CWD", caller)
  assert_eq(bug_caller_cwd(), caller)
  assert_eq(bug_eff_base(), caller)
  assert_eq(bug_server_cwd(), real_cwd) // 真实 server cwd 不受 env 顶替

  let eng = @engine.FistEngine::new()
  let j = ccw_unwrap(
    report_bug(
      proj,
      "caller cwd 落点验证",
      detail="",
      severity="low",
      ref_call_id="",
      reported_by="wbtest",
      publish_task=false,
      eng,
      now="2026-11-18T00:00:00Z",
    ),
    old,
  )
  // 文件落在 caller cwd，而不是 server cwd
  assert_true(@fs.path_exists(ledger))
  assert_false(@fs.path_exists(server_side))
  // 回执：resolved_path 按 caller 算；server_cwd 仍是真实值；caller_cwd 新增键
  assert_eq(ccw_str(j, "caller_cwd"), caller)
  assert_eq(ccw_str(j, "server_cwd"), real_cwd)
  assert_eq(ccw_str(j, "project_dir"), proj)
  assert_true(ccw_str(j, "resolved_path").has_prefix(caller + "/"))

  // bug_list 与 report_bug 同一把尺
  let lj = ccw_unwrap(bug_list(proj), old)
  assert_eq(ccw_str(lj, "resolved_path"), ccw_str(j, "resolved_path"))
  assert_eq(ccw_str(lj, "server_cwd"), real_cwd)
  assert_eq(ccw_str(lj, "caller_cwd"), caller)

  // 写侧另两条路也走同一落点：bug_mark_status / bug_fix
  let ms = ccw_unwrap(
    bug_mark_status(
      proj,
      "BUG-1",
      "FALSE_POSITIVE",
      evidence="wbtest 验证落点",
      ts="2026-11-18T00:00:01Z",
    ),
    old,
  )
  assert_true(ccw_str(ms, "path") == ledger)
  let _ = ccw_unwrap(
    report_bug(
      proj,
      "第二条供 bug_fix 验证",
      detail="",
      severity="low",
      ref_call_id="",
      reported_by="wbtest",
      publish_task=false,
      eng,
      now="2026-11-18T00:00:02Z",
    ),
    old,
  )
  let fx = ccw_unwrap(
    bug_fix(
      proj,
      ["BUG-2"],
      evidence="回归锁 wbtest",
      ts="2026-11-18T00:00:03Z",
    ),
    old,
  )
  assert_true(ccw_str(fx, "path") == ledger)
  let body = bug_read_text(proj)
  assert_true(body.contains("## BUG-2 [2026-11-18T00:00:02Z] [low] FIXED"))

  // 收尾：清理落点 + 还原 env
  @fs.remove_file(ledger) catch {
    _ => ()
  }
  ccw_restore_env(old)
}

///|
/// 格 2：env 不存在 ⇒ 逐字维持旧行为——相对 `project_dir` 解析到 server cwd，
/// resolved_path 以 server cwd 为基准，caller_cwd 键为空串（键新增、旧键保留）。
test "ccw_02_no_env_keeps_server_cwd_behavior" {
  let old = ccw_save_env()
  @env.unset_env_var("FIST_CALLER_CWD")
  let real_cwd = bug_server_cwd()
  assert_eq(bug_caller_cwd(), "")
  assert_eq(bug_eff_base(), real_cwd)

  let proj = "temp/ccw_02_server/proj"
  @fs.create_dir("temp") catch {
    _ => ()
  }
  @fs.create_dir("temp/ccw_02_server") catch {
    _ => ()
  }
  @fs.create_dir(proj) catch {
    _ => ()
  }
  @fs.create_dir(proj + "/memory") catch {
    _ => ()
  }
  let ledger = bug_abs_path(real_cwd, proj) + "/memory/bugs.md"
  @fs.remove_file(ledger) catch {
    _ => ()
  }

  let eng = @engine.FistEngine::new()
  let j = ccw_unwrap(
    report_bug(
      proj,
      "无 env 的原行为验证",
      detail="",
      severity="low",
      ref_call_id="",
      reported_by="wbtest",
      publish_task=false,
      eng,
      now="2026-11-18T01:00:00Z",
    ),
    old,
  )
  assert_true(@fs.path_exists(ledger))
  assert_eq(ccw_str(j, "caller_cwd"), "")
  assert_eq(ccw_str(j, "server_cwd"), real_cwd)
  assert_eq(ccw_str(j, "resolved_path"), bug_abs_path(real_cwd, proj))
  assert_eq(ccw_str(j, "path"), proj + "/memory/bugs.md")

  let lj = ccw_unwrap(bug_list(proj), old)
  assert_eq(ccw_str(lj, "resolved_path"), bug_abs_path(real_cwd, proj))
  assert_eq(ccw_str(lj, "server_cwd"), real_cwd)
  assert_eq(ccw_str(lj, "caller_cwd"), "")

  @fs.remove_file(ledger) catch {
    _ => ()
  }
  ccw_restore_env(old)
}

///|
/// 格 3：安全校验不放宽——`..` / 盘符 / 绝对路径照旧被拒（env 有效时也拒）；
/// 且 env 值为非绝对路径（含相对路径、盘符相对形态 `C:foo`）时按「未设置」处理。
test "ccw_03_validation_unchanged_and_non_abs_env_ignored" {
  let old = ccw_save_env()
  let caller = ccw_abs_temp("03_validate")
  @fs.create_dir("temp") catch {
    _ => ()
  }
  @fs.create_dir(caller) catch {
    _ => ()
  }
  @env.set_env_var("FIST_CALLER_CWD", caller)

  let eng = @engine.FistEngine::new()
  let bad = [
    "../escape", "a/../b", "C:/abs", "C:rel", "/abs/path", "\\abs\\path",
  ]
  for p in bad {
    let r = report_bug(
      p,
      "非法 project_dir",
      detail="",
      severity="low",
      ref_call_id="",
      reported_by="wbtest",
      publish_task=false,
      eng,
      now="2026-11-18T02:00:00Z",
    )
    assert_true(r is Err(_))
    assert_true(bug_list(p) is Err(_))
  }

  // 非绝对路径的 env 一律忽略 ⇒ 退回 server cwd，行为与格 2 一致
  for non_abs in ["relative/dir", "C:relative_drive", "  "] {
    @env.set_env_var("FIST_CALLER_CWD", non_abs)
    assert_eq(bug_caller_cwd(), "")
    assert_eq(bug_eff_base(), bug_server_cwd())
  }
  // 空串同样忽略
  @env.set_env_var("FIST_CALLER_CWD", "")
  assert_eq(bug_caller_cwd(), "")
  assert_eq(bug_eff_base(), bug_server_cwd())

  ccw_restore_env(old)
}
