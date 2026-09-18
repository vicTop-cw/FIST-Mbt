/// ops_watchdog_test.mbt —— 定时任务看门狗（watchdog_tick）测试
///
/// 对应 reports/2026-09-17-watchdog-cron-plan.md 第 7 节新增用例：
///   A-1 ~ A-4：读 SQLite 心跳的跨进程 heal 判定
///   B-1 ~ B-3：watchdog_tick 的 waiting / idle / blocked 分类
///   C-1 ~ C-2 + 幂等：完成 -> 自动续轮
/// 以及元提示词路径增强用例（单文件 / 目录取最新 / 路径失败不续轮）。

///|
/// 构建干净的 SQLite 引擎（先清库保证用例幂等）。
fn wd_sqlite_engine(db_path : String) -> @engine.FistEngine {
  match @store.SqliteStore::open(db_path) {
    Some(s) => ignore(s.clear())
    None => abort("sqlite open failed: " + db_path)
  }
  match @engine.FistEngine::open_sqlite(db_path) {
    None => abort("engine open failed: " + db_path)
    Some(e) => e
  }
}

///|
/// 在指定命名空间发布根任务 T0。
fn wd_publish(e : @engine.FistEngine, ns : String) -> Unit {
  match
    e.publish(
      project_dir="/watchdog-demo",
      description="定时任务根任务",
      created_by="human_steward",
      now="2026-09-17T00:00:00Z",
      ns~,
    ) {
    Ok(_) => ()
    Err(m) => abort("publish 失败: " + m)
  }
}

///|
/// T0 -> 执行中（claim + execute）。
fn wd_to_executing(e : @engine.FistEngine) -> Unit {
  ignore(e.claim(task_id="T0", assignee="worker-a", now="2026-09-17T00:00:01Z"))
  ignore(e.execute(task_id="T0", deliverable="d1", now="2026-09-17T00:00:02Z"))
}

///|
/// T0 -> 已完成（claim + execute + submit + verify）。
fn wd_to_completed(e : @engine.FistEngine) -> Unit {
  wd_to_executing(e)
  ignore(e.submit(task_id="T0", now="2026-09-17T00:00:03Z"))
  ignore(e.verify(task_id="T0", verifier="human", now="2026-09-17T00:00:04Z"))
}

///|
/// 写入一条心跳（模拟「上一个进程」落库的记录）。
fn wd_beat(
  e : @engine.FistEngine,
  task_id : String,
  last_seen : String,
  status : String,
) -> Unit {
  ignore(
    e.store_write_heartbeat(agent_id="fist-mbt", task_id~, last_seen~, status~),
  )
}

///|
/// 读出 tick JSON 中的 action 字段。
fn wd_action(j : Json) -> String {
  match j {
    Object(m) =>
      match m.get("action") {
        Some(String(s)) => s
        _ => abort("action 字段缺失")
      }
    _ => abort("tick 应返回 JSON 对象")
  }
}

///|
/// 读出整数字段。
fn wd_int(j : Json, key : String) -> Int {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(Number(n, ..)) => n.to_int()
        _ => abort("缺少整数字段: " + key)
      }
    _ => abort("tick 应返回 JSON 对象")
  }
}

///|
/// 读出字符串字段（缺失返回 ""）。
fn wd_str(j : Json, key : String) -> String {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
}

///|
/// 读出字符串数组字段。
fn wd_str_array(j : Json, key : String) -> Array[String] {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(Array(a)) =>
          a.map(fn(x) {
            match x {
              String(s) => s
              _ => ""
            }
          })
        _ => []
      }
    _ => []
  }
}

///|
/// 调用 tick 并断言成功。
fn wd_tick_ok(
  e : @engine.FistEngine,
  now : String,
  ns~ : String,
  next_description? : String = "",
  meta_prompt_path? : String = "",
  cold_start? : Bool = false,
  project_dir? : String = "",
) -> Json {
  match
    watchdog_tick(
      e,
      now,
      timeout_sec=600,
      ns~,
      next_description~,
      meta_prompt_path~,
      cold_start~,
      project_dir~,
    ) {
    Ok(j) => j
    Err(m) => abort("watchdog_tick 失败: " + m)
  }
}

///|
/// 建元提示词测试目录并写入指定文件，返回目录路径。
fn wd_meta_dir(name : String, files : Array[(String, String)]) -> String {
  // 统一落在 temp/ 下（已被 .gitignore 忽略），避免在仓库根目录留下测试垃圾
  let path = "temp/" + name
  @fs.create_dir("temp") catch {
    _ => ()
  }
  @fs.create_dir(path) catch {
    _ => ()
  }
  for pair in files {
    let (file_name, content) = pair
    @fs.write_string_to_file(path + "/" + file_name, content, encoding="utf8") catch {
      _ => abort("写入元提示词测试文件失败: " + file_name)
    }
  }
  path
}

// ---------------------------------------------------------------------------
// A. heal 读 SQLite（跨进程修复）
// ---------------------------------------------------------------------------

///|
test "watchdog A-1: 库中 10 分钟前心跳 -> 跨进程判定 stale 并回滚" {
  let e = wd_sqlite_engine("watchdog_a1.db")
  wd_publish(e, "cron-auto")
  wd_to_executing(e)
  // 心跳仅落库（本进程内存无记录），模拟 MCP 进程重启后的判定
  wd_beat(e, "T0", "2026-09-17T00:00:02Z", "active")
  match
    heal_stale_tasks_from_store(
      e,
      "2026-09-17T00:10:03Z",
      timeout_sec=600,
      ns="cron-auto",
    ) {
    Ok(list) => {
      assert_eq(list.length(), 1)
      assert_eq(list[0], "T0")
    }
    Err(m) => abort("heal 不应失败: " + m)
  }
  match e.get_task("T0") {
    Some(t) => assert_eq(t.get_status().to_string(), "已领取")
    None => abort("T0 应存在")
  }
}

///|
test "watchdog A-2: 心跳新鲜 -> 不回滚" {
  let e = wd_sqlite_engine("watchdog_a2.db")
  wd_publish(e, "cron-auto")
  wd_to_executing(e)
  wd_beat(e, "T0", "2026-09-17T00:00:02Z", "active")
  match
    heal_stale_tasks_from_store(
      e,
      "2026-09-17T00:00:22Z",
      timeout_sec=600,
      ns="cron-auto",
    ) {
    Ok(list) => assert_eq(list.length(), 0)
    Err(m) => abort("heal 不应失败: " + m)
  }
  match e.get_task("T0") {
    Some(t) => assert_eq(t.get_status().to_string(), "执行中")
    None => abort("T0 应存在")
  }
}

///|
test "watchdog A-3: 无任何心跳记录 -> 视为 stale 并回滚" {
  let e = wd_sqlite_engine("watchdog_a3.db")
  wd_publish(e, "cron-auto")
  wd_to_executing(e)
  match
    heal_stale_tasks_from_store(
      e,
      "2026-09-17T00:00:03Z",
      timeout_sec=600,
      ns="cron-auto",
    ) {
    Ok(list) => {
      assert_eq(list.length(), 1)
      assert_eq(list[0], "T0")
    }
    Err(m) => abort("heal 不应失败: " + m)
  }
}

///|
test "watchdog A-4: 非活跃状态（已完成 / 已暂停）超时也不回滚" {
  // 已完成
  let e = wd_sqlite_engine("watchdog_a4a.db")
  wd_publish(e, "cron-auto")
  wd_to_completed(e)
  wd_beat(e, "T0", "2026-09-17T00:00:02Z", "done")
  match
    heal_stale_tasks_from_store(
      e,
      "2026-09-17T09:00:00Z",
      timeout_sec=600,
      ns="cron-auto",
    ) {
    Ok(list) => assert_eq(list.length(), 0)
    Err(m) => abort("heal 不应失败: " + m)
  }
  match e.get_task("T0") {
    Some(t) => assert_eq(t.get_status().to_string(), "已完成")
    None => abort("T0 应存在")
  }
  // 已暂停
  let e2 = wd_sqlite_engine("watchdog_a4b.db")
  wd_publish(e2, "cron-auto")
  wd_to_executing(e2)
  ignore(e2.pause_task(task_id="T0", now="2026-09-17T00:00:05Z"))
  wd_beat(e2, "T0", "2026-09-17T00:00:02Z", "paused")
  match
    heal_stale_tasks_from_store(
      e2,
      "2026-09-17T09:00:00Z",
      timeout_sec=600,
      ns="cron-auto",
    ) {
    Ok(list) => assert_eq(list.length(), 0)
    Err(m) => abort("heal 不应失败: " + m)
  }
  match e2.get_task("T0") {
    Some(t) => assert_eq(t.get_status().to_string(), "已暂停")
    None => abort("T0 应存在")
  }
}

// ---------------------------------------------------------------------------
// B. watchdog_tick 分类：waiting / idle / blocked
// ---------------------------------------------------------------------------

///|
test "watchdog B-1: 心跳新鲜的执行中任务 -> waiting" {
  let e = wd_sqlite_engine("watchdog_b1.db")
  wd_publish(e, "cron-auto")
  wd_to_executing(e)
  wd_beat(e, "T0", "2026-09-17T00:00:02Z", "active")
  let j = wd_tick_ok(e, "2026-09-17T00:00:22Z", ns="cron-auto")
  assert_eq(wd_action(j), "waiting")
  assert_eq(wd_int(j, "active"), 1)
  assert_eq(wd_int(j, "healed"), 0)
}

///|
test "watchdog B-2: 无活跃任务 -> idle" {
  let e = wd_sqlite_engine("watchdog_b2.db")
  let j = wd_tick_ok(e, "2026-09-17T00:00:00Z", ns="cron-auto")
  assert_eq(wd_action(j), "idle")
  assert_eq(wd_int(j, "active"), 0)
  assert_eq(wd_int(j, "healed"), 0)
}

///|
test "watchdog B-3: 已暂停任务计入 blocked、不计 active" {
  let e = wd_sqlite_engine("watchdog_b3.db")
  wd_publish(e, "cron-auto")
  wd_to_executing(e)
  ignore(e.pause_task(task_id="T0", now="2026-09-17T00:00:05Z"))
  let j = wd_tick_ok(e, "2026-09-17T00:00:10Z", ns="cron-auto")
  assert_eq(wd_action(j), "idle")
  assert_eq(wd_int(j, "active"), 0)
  let blocked = wd_str_array(j, "blocked")
  assert_eq(blocked.length(), 1)
  assert_eq(blocked[0], "T0")
}

///|
test "watchdog B-4: 心跳超时的执行中任务 -> restarted 并回滚" {
  let e = wd_sqlite_engine("watchdog_b4.db")
  wd_publish(e, "cron-auto")
  wd_to_executing(e)
  wd_beat(e, "T0", "2026-09-17T00:00:02Z", "active")
  let j = wd_tick_ok(e, "2026-09-17T00:20:00Z", ns="cron-auto")
  assert_eq(wd_action(j), "restarted")
  assert_eq(wd_int(j, "healed"), 1)
  assert_eq(wd_str_array(j, "healed_tasks")[0], "T0")
  match e.get_task("T0") {
    Some(t) => assert_eq(t.get_status().to_string(), "已领取")
    None => abort("T0 应存在")
  }
}

// ---------------------------------------------------------------------------
// C. 完成 -> 自动起下一轮
// ---------------------------------------------------------------------------

///|
test "watchdog C-1: 已完成未续轮 + next_description -> advanced" {
  let e = wd_sqlite_engine("watchdog_c1.db")
  wd_publish(e, "cron-auto")
  wd_to_completed(e)
  let j = wd_tick_ok(
    e,
    "2026-09-17T01:00:00Z",
    ns="cron-auto",
    next_description="下一轮：继续推进",
  )
  assert_eq(wd_action(j), "advanced")
  assert_eq(wd_str(j, "new_task_id"), "T0r2")
  assert_eq(wd_str(j, "previous_task_id"), "T0")
  // 新根任务已发布，继承原 project_dir 与命名空间
  match e.get_task("T0r2") {
    Some(t) => {
      assert_eq(t.get_status().to_string(), "待领取")
      assert_eq(t.description, "下一轮：继续推进")
      assert_eq(t.ns, "cron-auto")
      assert_eq(t.project_dir, "/watchdog-demo")
    }
    None => abort("T0r2 应存在")
  }
  // 旧根任务已归档并带续轮标记
  match e.get_task("T0") {
    Some(t) => {
      assert_eq(t.get_status().to_string(), "已归档")
      assert_true(t.deliverable.contains("__advanced__:T0r2"))
    }
    None => abort("T0 应存在")
  }
}

///|
test "watchdog C-2: 未提供 next_description -> 不续轮" {
  let e = wd_sqlite_engine("watchdog_c2.db")
  wd_publish(e, "cron-auto")
  wd_to_completed(e)
  let j = wd_tick_ok(e, "2026-09-17T01:00:00Z", ns="cron-auto")
  assert_eq(wd_action(j), "idle")
  assert_eq(wd_int(j, "active"), 0)
  assert_eq(e.list_in_ns("cron-auto").length(), 1)
  match e.get_task("T0") {
    Some(t) => assert_eq(t.get_status().to_string(), "已完成")
    None => abort("T0 应存在")
  }
}

///|
test "watchdog C-3 幂等: 连续两次 tick 不重复续轮" {
  let e = wd_sqlite_engine("watchdog_c3.db")
  wd_publish(e, "cron-auto")
  wd_to_completed(e)
  let j1 = wd_tick_ok(
    e,
    "2026-09-17T01:00:00Z",
    ns="cron-auto",
    next_description="下一轮：继续推进",
  )
  assert_eq(wd_action(j1), "advanced")
  let j2 = wd_tick_ok(
    e,
    "2026-09-17T01:01:00Z",
    ns="cron-auto",
    next_description="下一轮：继续推进",
  )
  assert_eq(wd_action(j2), "idle")
  // 仅 T0 + T0r2，未重复发布
  assert_eq(e.list_in_ns("cron-auto").length(), 2)
}

///|
test "watchdog 边界: 未传 / 显式传 default 命名空间均不自动续轮" {
  let e = wd_sqlite_engine("watchdog_ns.db")
  wd_publish(e, "default")
  wd_to_completed(e)
  // 未传 namespace：只汇报状态，绝不自动起新轮
  let j1 = wd_tick_ok(
    e,
    "2026-09-17T01:00:00Z",
    ns="",
    next_description="不应被发布的下一轮",
  )
  assert_eq(wd_action(j1), "idle")
  assert_eq(e.list_in_ns("default").length(), 1)
  // 显式传 default 同样不得续轮（人工流程语义保持不变）
  let j2 = wd_tick_ok(
    e,
    "2026-09-17T01:01:00Z",
    ns="default",
    next_description="同样不应被发布",
  )
  assert_eq(wd_action(j2), "idle")
  assert_eq(e.list_in_ns("default").length(), 1)
  match e.get_task("T0") {
    Some(t) => assert_eq(t.get_status().to_string(), "已完成")
    None => abort("T0 应存在")
  }
}

// ---------------------------------------------------------------------------
// M. 元提示词文档路径增强
// ---------------------------------------------------------------------------

///|
test "watchdog M-1: 元提示词命名规则判定" {
  assert_eq(is_meta_prompt_name("20260917.12.30.45.md"), true)
  assert_eq(is_meta_prompt_name("20260901.10.00.00.md"), true)
  assert_eq(is_meta_prompt_name("_20260917.12.30.45.md"), false)
  assert_eq(is_meta_prompt_name("20260917.12.30.4.md"), false)
  assert_eq(is_meta_prompt_name("20260917.12.30.45.txt"), false)
  assert_eq(is_meta_prompt_name("20260917.1230.45.md"), false)
  assert_eq(is_meta_prompt_name("README.md"), false)
}

///|
test "watchdog M-2: 目录取最新一份、忽略下划线辅助文件" {
  let dir = wd_meta_dir("watchdog_meta_dir", [
    ("_index.md", "辅助说明，应被忽略"),
    ("20260901.10.00.00.md", "旧轮提示词"),
    ("20260917.12.30.45.md", "最新轮提示词"),
    ("README.md", "非规范命名，应被忽略"),
  ])
  assert_eq(latest_meta_prompt_in_dir(dir), Some("20260917.12.30.45.md"))
  match read_meta_prompt(dir) {
    Some(c) => assert_eq(c, "最新轮提示词")
    None => abort("应读到最新元提示词")
  }
  match read_meta_prompt(dir + "/20260901.10.00.00.md") {
    Some(c) => assert_eq(c, "旧轮提示词")
    None => abort("单文件形式应可读")
  }
}

///|
test "watchdog M-3: 路径不存在 / 目录无合法文档 -> 不续轮、不 panic" {
  let e = wd_sqlite_engine("watchdog_m3.db")
  wd_publish(e, "cron-auto")
  wd_to_completed(e)
  // 路径不存在
  let j1 = wd_tick_ok(
    e,
    "2026-09-17T02:00:00Z",
    ns="cron-auto",
    meta_prompt_path="不存在目录_xyz",
  )
  assert_eq(wd_action(j1), "idle")
  assert_eq(e.list_in_ns("cron-auto").length(), 1)
  // 目录存在但无合法命名文档
  ignore(wd_meta_dir("watchdog_meta_empty", [("_only.md", "仅辅助文件")]))
  let j2 = wd_tick_ok(
    e,
    "2026-09-17T02:01:00Z",
    ns="cron-auto",
    meta_prompt_path="temp/watchdog_meta_empty",
  )
  assert_eq(wd_action(j2), "idle")
  assert_eq(e.list_in_ns("cron-auto").length(), 1)
}

///|
test "watchdog M-4: 用元提示词文档内容作为下一轮描述" {
  ignore(
    wd_meta_dir("watchdog_meta_dir2", [
      ("_draft.md", "草稿，不应被采用"),
      ("20260917.09.00.00.md", "元提示词：先做 A"),
      ("20260917.12.30.45.md", "元提示词：继续推进下一轮"),
    ]),
  )
  let e = wd_sqlite_engine("watchdog_m4.db")
  wd_publish(e, "cron-auto")
  wd_to_completed(e)
  let j = wd_tick_ok(
    e,
    "2026-09-17T02:00:00Z",
    ns="cron-auto",
    meta_prompt_path="temp/watchdog_meta_dir2",
  )
  assert_eq(wd_action(j), "advanced")
  let new_id = wd_str(j, "new_task_id")
  match e.get_task(new_id) {
    Some(t) => assert_eq(t.description, "元提示词：继续推进下一轮")
    None => abort("新任务应存在: " + new_id)
  }
  // 显式 next_description 优先于元提示词文档
  let e2 = wd_sqlite_engine("watchdog_m4b.db")
  wd_publish(e2, "cron-auto")
  wd_to_completed(e2)
  let j2 = wd_tick_ok(
    e2,
    "2026-09-17T02:00:00Z",
    ns="cron-auto",
    next_description="显式描述优先",
    meta_prompt_path="temp/watchdog_meta_dir2",
  )
  assert_eq(wd_action(j2), "advanced")
  match e2.get_task(wd_str(j2, "new_task_id")) {
    Some(t) => assert_eq(t.description, "显式描述优先")
    None => abort("新任务应存在")
  }
}

// ---------------------------------------------------------------------------
// D. 冷启动：空库 + cold_start=true -> 直接发布首个根任务
// ---------------------------------------------------------------------------

///|
test "watchdog D-1: 冷启动 — 空库 + cold_start=true -> advanced + T0 发布" {
  let e = wd_sqlite_engine("watchdog_d1.db")
  // 空库，无任何任务
  assert_eq(e.list_in_ns("cron-auto").length(), 0)
  let j = wd_tick_ok(
    e,
    "2026-09-17T10:00:00Z",
    ns="cron-auto",
    next_description="冷启动首任务：修复 Token::Hash 编译错误",
    cold_start=true,
    project_dir="/tmp/pentad",
  )
  assert_eq(wd_action(j), "advanced")
  assert_eq(wd_str(j, "new_task_id"), "T0")
  assert_eq(e.list_in_ns("cron-auto").length(), 1)
  match e.get_task("T0") {
    Some(t) => {
      assert_eq(t.get_status().to_string(), "待领取")
      assert_eq(t.ns, "cron-auto")
      assert_eq(
        t.description,
        "冷启动首任务：修复 Token::Hash 编译错误",
      )
    }
    None => abort("T0 应存在")
  }
}

///|
test "watchdog D-2: 冷启动 — cold_start=false + 空库 -> idle（不发布）" {
  let e = wd_sqlite_engine("watchdog_d2.db")
  let j = wd_tick_ok(
    e,
    "2026-09-17T10:00:00Z",
    ns="cron-auto",
    next_description="不应被发布",
    cold_start=false,
  )
  assert_eq(wd_action(j), "idle")
  assert_eq(e.list_in_ns("cron-auto").length(), 0)
}

///|
test "watchdog D-3: 冷启动 — default 命名空间 + cold_start=true -> 失败（安全限制）" {
  let e = wd_sqlite_engine("watchdog_d3.db")
  let j = wd_tick_ok(
    e,
    "2026-09-17T10:00:00Z",
    ns="default",
    next_description="不应被发布到 default",
    cold_start=true,
  )
  // default 命名空间拒绝冷启动发布，退化为 idle
  assert_eq(wd_action(j), "idle")
  assert_eq(e.list_in_ns("default").length(), 0)
}

///|
test "watchdog D-4: 冷启动幂等 — 已有任务后 cold_start=true 不再重复发布" {
  let e = wd_sqlite_engine("watchdog_d4.db")
  // 第一次冷启动
  let j1 = wd_tick_ok(
    e,
    "2026-09-17T10:00:00Z",
    ns="cron-auto",
    next_description="首次冷启动",
    cold_start=true,
  )
  assert_eq(wd_action(j1), "advanced")
  assert_eq(e.list_in_ns("cron-auto").length(), 1)
  // 第二次 cold_start，已有任务，cold_publish 拒绝重复发布，退化
  // T0 是待领取状态，不在 active_ids 中 -> action 为 "idle"
  let j2 = wd_tick_ok(
    e,
    "2026-09-17T10:01:00Z",
    ns="cron-auto",
    next_description="不应重复发布",
    cold_start=true,
  )
  // 没有重复发布，action 为 idle 或 waiting（取决于 active_ids 分类）
  assert_eq(wd_action(j2) != "advanced", true)
  assert_eq(e.list_in_ns("cron-auto").length(), 1)
}

///|
test "watchdog D-5: 冷启动 — meta_prompt_path + cold_start=true 组合" {
  ignore(
    wd_meta_dir("watchdog_cold_meta", [
      ("20260917.10.00.00.md", "元提示词驱动的修复任务"),
    ]),
  )
  let e = wd_sqlite_engine("watchdog_d5.db")
  let j = wd_tick_ok(
    e,
    "2026-09-17T10:00:00Z",
    ns="cron-auto",
    meta_prompt_path="temp/watchdog_cold_meta",
    cold_start=true,
    project_dir="/tmp/pentad",
  )
  assert_eq(wd_action(j), "advanced")
  assert_eq(wd_str(j, "new_task_id"), "T0")
  match e.get_task("T0") {
    Some(t) => assert_eq(t.description, "元提示词驱动的修复任务")
    None => abort("T0 应存在")
  }
}

// —— E. Omega 强验证集成 ——

///|
fn wd_tick_omega_ok(
  e : @engine.FistEngine,
  now : String,
  ns? : String = "",
  next_description? : String = "",
  cold_start? : Bool = false,
  project_dir? : String = "",
  omega_strong_verify? : Bool = false,
  omega_split_n? : Int = 3,
) -> Json {
  let r = @ops.watchdog_tick(
    e,
    now,
    ns~,
    next_description~,
    cold_start~,
    project_dir~,
    omega_strong_verify~,
    omega_split_n~,
  )
  match r {
    Ok(j) => j
    Err(m) => abort("watchdog_tick 失败: " + m)
  }
}

///|
test "watchdog E-1: 续轮时开启 omega_strong_verify 自动拆分并打标记" {
  let e = wd_sqlite_engine("watchdog_e1.db")
  wd_publish(e, "cron-omega")
  wd_to_completed(e)
  let j = wd_tick_omega_ok(
    e,
    "2026-09-17T10:00:00Z",
    ns="cron-omega",
    next_description="Omega 强验证任务",
    omega_strong_verify=true,
  )
  assert_eq(wd_action(j), "advanced")
  assert_eq(wd_str(j, "new_task_id"), "T0r2")
  // 检查 omega 字段存在
  match j {
    Object(m) =>
      match m.get("omega") {
        Some(Object(om)) => {
          assert_eq(om.get("enabled"), Some(Json::boolean(true)))
          assert_eq(om.get("root"), Some(Json::string("T0r2")))
        }
        _ => abort("omega 字段应存在且为对象")
      }
    _ => abort("tick 应返回 JSON 对象")
  }
  // 检查子任务已带 [omega:required] 标记
  let children = e.children_of("T0r2")
  assert_eq(children.length() > 0, true)
  assert_true(children[0].get_description().contains("[omega:required]"))
}

///|
test "watchdog E-2: omega_strong_verify=false 时子任务无标记" {
  let e = wd_sqlite_engine("watchdog_e2.db")
  wd_publish(e, "cron-no-omega")
  wd_to_completed(e)
  let j = wd_tick_omega_ok(
    e,
    "2026-09-17T10:00:00Z",
    ns="cron-no-omega",
    next_description="普通任务",
    omega_strong_verify=false,
  )
  assert_eq(wd_action(j), "advanced")
  let children = e.children_of("T0r2")
  // 子任务不应带 [omega:required] 标记
  for c in children {
    assert_false(c.get_description().contains("[omega:required]"))
  }
}

///|
test "watchdog E-3: omega 冷启动 + 强验证" {
  let e = wd_sqlite_engine("watchdog_e3.db")
  let j = wd_tick_omega_ok(
    e,
    "2026-09-17T10:00:00Z",
    ns="cron-omega-cold",
    next_description="Omega 冷启动任务",
    cold_start=true,
    omega_strong_verify=true,
  )
  assert_eq(wd_action(j), "advanced")
  assert_eq(wd_str(j, "new_task_id"), "T0")
  // 检查子任务已带 [omega:required] 标记
  let children = e.children_of("T0")
  assert_eq(children.length() > 0, true)
  assert_true(children[0].get_description().contains("[omega:required]"))
}

///|
test "watchdog E-4: omega 强验证下执行前必须语料审核通过" {
  let e = wd_sqlite_engine("watchdog_e4.db")
  wd_publish(e, "cron-omega-gate")
  wd_to_completed(e)
  let j = wd_tick_omega_ok(
    e,
    "2026-09-17T10:00:00Z",
    ns="cron-omega-gate",
    next_description="Omega 门禁任务",
    omega_strong_verify=true,
  )
  assert_eq(wd_action(j), "advanced")
  let cid = "T0r2.1"
  // 领取任务
  ignore(e.claim(task_id=cid, assignee="exec-1", now="2026-09-17T10:01:00Z"))
  // 尚无语料 -> 禁止执行
  match
    e.execute(task_id=cid, deliverable="成果", now="2026-09-17T10:02:00Z") {
    Ok(_) => abort("无语料时不应放行执行")
    Err(m) => assert_true(m.contains("尚未创建语料"))
  }
  // 创建语料并审核通过
  ignore(
    e.omega_spec_create(
      task_id=cid,
      author="spec_author",
      content="验收标准",
      now="2026-09-17T10:03:00Z",
    ),
  )
  ignore(
    e.omega_spec_review(
      task_id=cid,
      reviewer="verifier",
      verdict="approve",
      now="2026-09-17T10:04:00Z",
    ),
  )
  // 审核通过后 -> 可执行
  match
    e.execute(task_id=cid, deliverable="成果", now="2026-09-17T10:05:00Z") {
    Ok(t) => assert_true(t.get_status().is_executing())
    Err(m) => abort("语料通过后执行应放行: " + m)
  }
}
