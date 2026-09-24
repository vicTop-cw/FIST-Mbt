/// ops_pipeline_test.mbt —— 提示词流水线状态机（pipeline_tick）测试
///
/// 覆盖 watchdog_meta_prompt.md 协议的四条硬约束：
///   1) 幂等：同一提示词只发布一次根任务（用例 4）
///   2) 状态一致：状态文件与任务状态双向校验，脏态只报不改（用例 13）
///   3) 报告先行：Closed 必须已有报告（用例 7 / 9）
///   4) 单入口：action 分类齐全（generate / execute / wait / write_report / closed / safe_exit）
///
/// 目录约定：每个用例使用独立目录 temp/pl_cN_xxx，文件一律覆盖式写入，
/// 报告有无在单个用例内恒定，因此用例可重复运行且相互不干扰。

// ---------------------------------------------------------------------------
// 测试辅助
// ---------------------------------------------------------------------------

///|
/// 准备用例目录（不存在则创建，已存在则复用）。
fn pl_dir(name : String) -> String {
  @fs.create_dir("temp") catch {
    _ => ()
  }
  let d = "temp/" + name
  @fs.create_dir(d) catch {
    _ => ()
  }
  let g = d + "/Gen_Prompts"
  @fs.create_dir(g) catch {
    _ => ()
  }
  d
}

///|
/// 落盘一份提示词。
fn pl_prompt(dir : String, name : String, content : String) -> Unit {
  @fs.write_string_to_file(
    dir + "/Gen_Prompts/" + name,
    content,
    encoding="utf8",
  ) catch {
    _ => abort("写提示词失败: " + name)
  }
}

///|
/// 落盘一份报告（报告名与提示词同名）。
fn pl_report(dir : String, name : String, content : String) -> Unit {
  @fs.create_dir(dir + "/Reports") catch {
    _ => ()
  }
  @fs.write_string_to_file(dir + "/Reports/" + name, content, encoding="utf8") catch {
    _ => abort("写报告失败: " + name)
  }
}

///|
/// 覆盖写状态文件。
fn pl_set_state(dir : String, word : String) -> Unit {
  @fs.write_string_to_file(dir + "/currentState.txt", word, encoding="utf8") catch {
    _ => abort("写状态文件失败")
  }
}

///|
/// 任意路径覆盖写。
fn pl_write(path : String, content : String) -> Unit {
  @fs.write_string_to_file(path, content, encoding="utf8") catch {
    _ => abort("写文件失败: " + path)
  }
}

///|
/// 读状态文件原始内容（缺失返回 "<none>"）。
fn pl_raw_state(dir : String) -> String {
  match
    (Some(@fs.read_file_to_string(dir + "/currentState.txt", encoding="utf8")) catch {
      _ => None
    }) {
    Some(s) => s
    None => "<none>"
  }
}

///|
/// 读 JSON 字符串字段（缺失返回 "<null>"）。
fn pl_str(j : Json, key : String) -> String {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(String(s)) => s
        _ => "<null>"
      }
    _ => abort("应返回 JSON 对象")
  }
}

///|
/// 读 JSON 数组字段长度（缺失返回 -1）。
fn pl_arr_len(j : Json, key : String) -> Int {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(Array(a)) => a.length()
        _ => -1
      }
    _ => -1
  }
}

///|
/// 以默认命名空间调用一次 tick（失败直接 abort）。
fn pl_tick(
  e : @engine.FistEngine,
  dir : String,
  now : String,
  timeout_sec? : Int = 2400,
) -> Json {
  match pipeline_tick(e, dir, now, ns="cron-auto", timeout_sec~) {
    Ok(j) => j
    Err(m) => abort("pipeline_tick 失败: " + m)
  }
}

///|
/// 指定提示词名调用一次 tick（失败直接 abort）。
fn pl_tick_named(
  e : @engine.FistEngine,
  dir : String,
  now : String,
  prompt_name : String,
) -> Json {
  match pipeline_tick(e, dir, now, ns="cron-auto", prompt_name~) {
    Ok(j) => j
    Err(m) => abort("pipeline_tick 失败: " + m)
  }
}

///|
/// 该命名空间任务数量。
fn pl_count(e : @engine.FistEngine, ns : String) -> Int {
  e.list_in_ns(ns).length()
}

///|
/// 取命名空间中某提示词标记对应的任务 id（找不到返回 "<none>"）。
fn pl_task_of(
  e : @engine.FistEngine,
  ns : String,
  prompt_name : String,
) -> String {
  let marker = "[prompt:" + prompt_name + "]"
  for t in e.list_in_ns(ns) {
    if t.description.contains(marker) {
      return t.get_id()
    }
  }
  "<none>"
}

// ---------------------------------------------------------------------------
// 用例
// ---------------------------------------------------------------------------

///|
test "pipeline_1_idle_generate" {
  let dir = pl_dir("pl_c1_generate")
  pl_prompt(dir, "20260920.10.00.00.md", "# 提示词1\n做点事")
  let e = wd_sqlite_engine("temp/pl_c1.db")
  let j = pl_tick(e, dir, "2026-09-20T10:05:00+08:00")
  assert_eq(wd_action(j), "generate")
  // 首次运行入口为 absent；重复运行时前次留下的 Creating 同属合法空闲入口（用例需可重复执行）
  let st_in = pl_str(j, "state_in")
  assert_true(st_in == "absent" || st_in == "Creating")
  assert_eq(pl_str(j, "state_out"), "Creating")
  assert_eq(pl_raw_state(dir).trim().to_owned(), "Creating")
  assert_eq(pl_count(e, "cron-auto"), 0)
}

///|
test "pipeline_2_prompt_ready_to_pending" {
  let dir = pl_dir("pl_c2_prompt_ready")
  pl_prompt(dir, "20260920.11.00.00.md", "# 提示词2")
  pl_set_state(dir, "Creating")
  let e = wd_sqlite_engine("temp/pl_c2.db")
  let j = match
    pipeline_tick(
      e,
      dir,
      "2026-09-20T11:05:00+08:00",
      ns="cron-auto",
      phase="prompt_ready",
    ) {
    Ok(x) => x
    Err(m) => abort(m)
  }
  assert_eq(wd_action(j), "prompt_pending")
  assert_eq(pl_str(j, "state_out"), "Pending")
  assert_eq(pl_raw_state(dir).trim().to_owned(), "Pending")
}

///|
test "pipeline_3_pending_publishes_root_task" {
  let dir = pl_dir("pl_c3_pending_publish")
  pl_prompt(dir, "20260920.12.00.00.md", "# 提示词3\n做任务3")
  pl_set_state(dir, "Pending")
  let e = wd_sqlite_engine("temp/pl_c3.db")
  let j = pl_tick(e, dir, "2026-09-20T12:05:00+08:00")
  assert_eq(wd_action(j), "execute")
  assert_eq(pl_str(j, "state_out"), "Running")
  assert_eq(pl_str(j, "task_id"), "T0")
  assert_eq(pl_raw_state(dir).trim().to_owned(), "Running")
  assert_eq(pl_count(e, "cron-auto"), 1)
  assert_true(@fs.path_exists(dir + "/Gen_Prompts/_running.started"))
  assert_eq(pl_task_of(e, "cron-auto", "20260920.12.00.00.md"), "T0")
  // 任务描述应内嵌提示词全文
  assert_true(pl_str(j, "prompt_content").contains("做任务3"))
}

///|
test "pipeline_4_pending_idempotent" {
  let dir = pl_dir("pl_c4_idempotent")
  pl_prompt(dir, "20260920.13.00.00.md", "# 提示词4")
  pl_set_state(dir, "Pending")
  let e = wd_sqlite_engine("temp/pl_c4.db")
  ignore(pl_tick(e, dir, "2026-09-20T13:05:00+08:00"))
  // 模拟外部重复唤醒：状态被再次置回 Pending
  pl_set_state(dir, "Pending")
  let j2 = pl_tick(e, dir, "2026-09-20T13:10:00+08:00")
  assert_eq(wd_action(j2), "execute")
  assert_eq(pl_str(j2, "task_id"), "T0")
  assert_eq(pl_str(j2, "state_out"), "Running")
  // 关键断言：未重复发布
  assert_eq(pl_count(e, "cron-auto"), 1)
}

///|
test "pipeline_5_running_timeout_without_report" {
  let dir = pl_dir("pl_c5_timeout")
  pl_prompt(dir, "20260920.14.00.00.md", "# 提示词5")
  pl_set_state(dir, "Running")
  pl_write(dir + "/Gen_Prompts/_running.started", "2026-09-20T13:00:00+08:00")
  let e = wd_sqlite_engine("temp/pl_c5.db")
  // 间隔 65 分钟 > 40 分钟阈值
  let j = pl_tick(e, dir, "2026-09-20T14:05:00+08:00")
  assert_eq(wd_action(j), "write_report")
  assert_eq(pl_str(j, "state_out"), "Running")
  assert_eq(pl_raw_state(dir).trim().to_owned(), "Running")
}

///|
test "pipeline_6_running_with_report_closes" {
  let dir = pl_dir("pl_c6_closed_by_report")
  pl_prompt(dir, "20260920.15.00.00.md", "# 提示词6")
  pl_report(dir, "20260920.15.00.00.md", "# 报告6")
  pl_set_state(dir, "Running")
  let e = wd_sqlite_engine("temp/pl_c6.db")
  let j = pl_tick(e, dir, "2026-09-20T15:05:00+08:00")
  assert_eq(wd_action(j), "closed")
  assert_eq(pl_str(j, "state_out"), "Closed")
  assert_true(pl_str(j, "report_path").contains("20260920.15.00.00.md"))
  assert_eq(pl_raw_state(dir).trim().to_owned(), "Closed")
}

///|
test "pipeline_7_report_ready_without_report_blocked" {
  let dir = pl_dir("pl_c7_report_ready_missing")
  pl_prompt(dir, "20260920.16.30.00.md", "# 提示词7")
  pl_set_state(dir, "Running")
  let e = wd_sqlite_engine("temp/pl_c7.db")
  let j = match
    pipeline_tick(
      e,
      dir,
      "2026-09-20T16:35:00+08:00",
      ns="cron-auto",
      phase="report_ready",
    ) {
    Ok(x) => x
    Err(m) => abort(m)
  }
  assert_eq(wd_action(j), "write_report")
  assert_eq(pl_str(j, "state_in"), "Running")
  // 报告先行：状态不得被改为 Closed
  assert_eq(pl_raw_state(dir).trim().to_owned(), "Running")
}

///|
test "pipeline_8_report_ready_with_report_closes" {
  let dir = pl_dir("pl_c8_report_ready_ok")
  pl_prompt(dir, "20260920.17.30.00.md", "# 提示词8")
  pl_report(dir, "20260920.17.30.00.md", "# 报告8")
  pl_set_state(dir, "Running")
  let e = wd_sqlite_engine("temp/pl_c8.db")
  let j = match
    pipeline_tick(
      e,
      dir,
      "2026-09-20T17:35:00+08:00",
      ns="cron-auto",
      phase="report_ready",
    ) {
    Ok(x) => x
    Err(m) => abort(m)
  }
  assert_eq(wd_action(j), "closed")
  assert_eq(pl_raw_state(dir).trim().to_owned(), "Closed")
}

///|
test "pipeline_9_closed_without_report_blocks_advance" {
  let dir = pl_dir("pl_c9_closed_no_report")
  pl_prompt(dir, "20260920.18.30.00.md", "# 提示词9")
  pl_set_state(dir, "Closed")
  let e = wd_sqlite_engine("temp/pl_c9.db")
  let j = pl_tick(e, dir, "2026-09-20T18:35:00+08:00")
  assert_eq(wd_action(j), "write_report")
  assert_eq(pl_str(j, "state_out"), "Closed")
  assert_eq(pl_raw_state(dir).trim().to_owned(), "Closed")
}

///|
test "pipeline_10_closed_with_report_generates_next" {
  let dir = pl_dir("pl_c10_closed_has_report")
  pl_prompt(dir, "20260920.19.30.00.md", "# 提示词10")
  pl_report(dir, "20260920.19.30.00.md", "# 报告10")
  pl_set_state(dir, "Closed")
  let e = wd_sqlite_engine("temp/pl_c10.db")
  let j = pl_tick(e, dir, "2026-09-20T19:35:00+08:00")
  assert_eq(wd_action(j), "generate")
  assert_eq(pl_str(j, "state_out"), "Creating")
  assert_true(pl_str(j, "previous_report").contains("20260920.19.30.00.md"))
  assert_eq(pl_raw_state(dir).trim().to_owned(), "Creating")
}

///|
test "pipeline_11_next_round_after_completion" {
  let dir = pl_dir("pl_c11_next_round")
  pl_prompt(dir, "20260920.20.30.00.md", "# 提示词11-a")
  pl_set_state(dir, "Pending")
  let e = wd_sqlite_engine("temp/pl_c11.db")
  let j1 = pl_tick_named(
    e, dir, "2026-09-20T20:30:00+08:00", "20260920.20.30.00.md",
  )
  assert_eq(pl_str(j1, "task_id"), "T0")
  // 报告先行：上一轮报告落盘后才完成任务
  pl_report(dir, "20260920.20.30.00.md", "# 报告11-a")
  wd_to_completed(e)
  // 新提示词落盘 + 再次 Pending -> 发布下一轮根任务
  pl_prompt(dir, "20260920.21.30.00.md", "# 提示词11-b")
  pl_set_state(dir, "Pending")
  let j2 = pl_tick_named(
    e, dir, "2026-09-20T21:30:00+08:00", "20260920.21.30.00.md",
  )
  assert_eq(wd_action(j2), "execute")
  assert_eq(pl_str(j2, "task_id"), "T0r2")
  assert_eq(pl_count(e, "cron-auto"), 2)
  assert_eq(pl_task_of(e, "cron-auto", "20260920.21.30.00.md"), "T0r2")
}

///|
test "pipeline_12_ignores_underscore_files" {
  let dir = pl_dir("pl_c12_underscore")
  pl_prompt(dir, "20260920.22.30.00.md", "# 真提示词12")
  pl_prompt(dir, "_notes.md", "# 辅助文件12")
  pl_set_state(dir, "Pending")
  let e = wd_sqlite_engine("temp/pl_c12.db")
  let j = pl_tick(e, dir, "2026-09-20T22:35:00+08:00")
  assert_eq(wd_action(j), "execute")
  assert_eq(pl_str(j, "prompt_file"), "20260920.22.30.00.md")
  assert_true(pl_str(j, "prompt_content").contains("真提示词12"))
  assert_eq(pl_count(e, "cron-auto"), 1)
}

///|
test "pipeline_13_invalid_state_safe_exit" {
  let dir = pl_dir("pl_c13_invalid")
  pl_prompt(dir, "20260920.23.30.00.md", "# 提示词13")
  pl_set_state(dir, "Oops")
  let e = wd_sqlite_engine("temp/pl_c13.db")
  let j = pl_tick(e, dir, "2026-09-20T23:35:00+08:00")
  assert_eq(wd_action(j), "safe_exit")
  assert_eq(pl_str(j, "state_in"), "invalid")
  // 脏状态只报不改
  assert_eq(pl_raw_state(dir).trim().to_owned(), "Oops")
  assert_eq(pl_count(e, "cron-auto"), 0)
}

///|
test "pipeline_14_default_namespace_rejected" {
  let dir = pl_dir("pl_c14_default")
  pl_prompt(dir, "20260921.00.30.00.md", "# 提示词14")
  pl_set_state(dir, "Pending")
  let e = wd_sqlite_engine("temp/pl_c14.db")
  match pipeline_tick(e, dir, "2026-09-21T00:35:00+08:00", ns="default") {
    Ok(_) => abort("default 命名空间应被拒绝")
    Err(_) => ()
  }
  assert_eq(pl_count(e, "default"), 0)
}

///|
test "pipeline_15_stale_heartbeat_healed" {
  let dir = pl_dir("pl_c15_heal")
  pl_prompt(dir, "20260921.01.30.00.md", "# 提示词15")
  pl_set_state(dir, "Pending")
  let e = wd_sqlite_engine("temp/pl_c15.db")
  let j1 = pl_tick(e, dir, "2026-09-21T01:30:00+08:00")
  assert_eq(pl_str(j1, "task_id"), "T0")
  // T0 置为执行中并写入一条过期心跳（2 小时前）
  ignore(
    e.claim(task_id="T0", assignee="worker-a", now="2026-09-21T01:31:00+08:00"),
  )
  ignore(
    e.execute(task_id="T0", deliverable="d1", now="2026-09-21T01:32:00+08:00"),
  )
  wd_beat(e, "T0", "2026-09-21T01:33:00+08:00", "执行中")
  let j2 = pl_tick(e, dir, "2026-09-21T03:40:00+08:00")
  // 超时心跳被回滚：healed 上报且任务回到「已领取」（与 engine.reopen_task 既定语义一致，待重派）
  assert_true(pl_arr_len(j2, "healed") >= 1)
  let tasks = e.list_in_ns("cron-auto")
  assert_eq(tasks[0].get_status().to_string(), "已领取")
}

///|
test "pipeline_16_backlog_does_not_stack_new_round" {
  let dir = pl_dir("pl_c16_backlog")
  pl_prompt(dir, "20260920.23.30.00.md", "# 提示词16-a")
  pl_set_state(dir, "Pending")
  let e = wd_sqlite_engine("temp/pl_c16.db")
  let j1 = pl_tick_named(
    e, dir, "2026-09-20T23:30:00+08:00", "20260920.23.30.00.md",
  )
  assert_eq(wd_action(j1), "execute")
  assert_eq(pl_str(j1, "task_id"), "T0")
  // 上一轮任务仍在途（待领取）时又来一份新提示词：不得再发布新任务堆积（空转根因防护）
  pl_prompt(dir, "20260920.23.45.00.md", "# 提示词16-b")
  pl_set_state(dir, "Pending")
  let j2 = pl_tick_named(
    e, dir, "2026-09-20T23:45:00+08:00", "20260920.23.45.00.md",
  )
  assert_eq(pl_count(e, "cron-auto"), 1)
  assert_eq(wd_action(j2), "wait")
}
