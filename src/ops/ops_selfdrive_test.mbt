/// ops_selfdrive_test.mbt —— 自驱式编程模块（ops_selfdrive）测试
///
/// 覆盖四类能力：
///   1) memory 四件套：init 幂等 / append / get / export_tasks
///   2) 审视轮判定：无 memory → no_memory；未到轮次 → idle；到达 → review
///   3) 审视收口：无报告 → safe_exit（报告先行）；有报告 → reviewed 推进计数
///   4) 自我派活：parse_next_tasks 解析；publish_next 发布 + 幂等防重
///
/// 目录约定：每个用例使用独立目录 temp/sd_cN_xxx 与独立 sqlite 库，可重复运行。

// ---------------------------------------------------------------------------
// 测试辅助
// ---------------------------------------------------------------------------

///|
/// 准备用例目录（含 memory/reviews 骨架）。每次运行先清空本用例目录，
/// 避免上次运行残留的 Reports//memory/ 文件污染计数（用例幂等可重复跑）。
fn sd_clean_dir(dir : String) -> Unit {
  // 删除已知单文件（memory 四件套 + 计数），各自失败忽略（首次运行无残留）
  for
    f in [
      "memory/product.md", "memory/target.md", "memory/task.md", "memory/thinking.md",
      "memory/_review.count",
    ] {
    @fs.remove_file(dir + "/" + f) catch {
      _ => ()
    }
  }
  // 逐文件删除 Reports/ 与 memory/reviews/ 下已积累的报告，实现幂等
  for sub in ["Reports", "memory/reviews"] {
    let p = dir + "/" + sub
    let names = @fs.read_dir(p) catch { _ => continue }
    for n in names {
      @fs.remove_file(p + "/" + n) catch {
        _ => ()
      }
    }
  }
}

///|
/// 准备用例目录（含 memory/reviews 骨架）。每次运行先清空本用例目录，
/// 避免上次运行残留的 Reports//memory/ 文件污染计数（用例幂等可重复跑）。
fn sd_dir(name : String) -> String {
  @fs.create_dir("temp") catch {
    _ => ()
  }
  let d = "temp/" + name
  @fs.create_dir(d) catch {
    _ => ()
  }
  @fs.create_dir(d + "/memory") catch {
    _ => ()
  }
  @fs.create_dir(d + "/memory/reviews") catch {
    _ => ()
  }
  @fs.create_dir(d + "/Reports") catch {
    _ => ()
  }
  sd_clean_dir(d)
  d
}

///|
/// 落盘一份闭环报告（Reports/yyyyMMdd.HH.mm.ss.md）。
fn sd_report(dir : String, name : String, content : String) -> Unit {
  @fs.create_dir(dir + "/Reports") catch {
    _ => ()
  }
  @fs.write_string_to_file(dir + "/Reports/" + name, content, encoding="utf8") catch {
    _ => abort("写报告失败: " + name)
  }
}

///|
/// 落盘一份审视报告（memory/reviews/yyyyMMdd.HH.mm.ss.md）。
fn sd_review(dir : String, name : String, content : String) -> Unit {
  @fs.write_string_to_file(
    dir + "/memory/reviews/" + name,
    content,
    encoding="utf8",
  ) catch {
    _ => abort("写审视报告失败: " + name)
  }
}

///|
/// 读 JSON 字符串字段（缺失返回 "<null>"）。
fn sd_str(j : Json, key : String) -> String {
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
fn sd_arr_len(j : Json, key : String) -> Int {
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
/// 读 JSON 数组字段第 i 项（缺失返回 "<none>"）。
fn sd_arr_item(j : Json, key : String, i : Int) -> String {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(Array(a)) =>
          match a[i] {
            String(s) => s
            _ => "<non-string>"
          }
        _ => "<none>"
      }
    _ => "<none>"
  }
}

///|
/// 读 JSON 布尔字段（缺失返回 false）。
fn sd_bool(j : Json, key : String) -> Bool {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(True) => true
        _ => false
      }
    _ => false
  }
}

///|
/// 创建 sqlite 引擎（复用 watchdog 测试辅助）。
fn sd_engine(db : String) -> @engine.FistEngine {
  wd_sqlite_engine(db)
}

// ---------------------------------------------------------------------------
// 用例 1：memory 四件套 init 幂等
// ---------------------------------------------------------------------------

///|
test "selfdrive_1_init_idempotent" {
  let dir = sd_dir("sd_c1_init")
  let j1 = match selfdrive_memory_init(dir, ns="sd-test") {
    Ok(x) => x
    Err(m) => abort(m)
  }
  assert_eq(sd_str(j1, "action"), "init")
  assert_eq(sd_arr_len(j1, "created"), 4)
  // 二次调用：全部跳过，不覆盖
  let j2 = match selfdrive_memory_init(dir, ns="sd-test") {
    Ok(x) => x
    Err(m) => abort(m)
  }
  assert_eq(sd_str(j2, "action"), "init")
  assert_eq(sd_arr_len(j2, "created"), 0)
  assert_eq(sd_arr_len(j2, "skipped"), 4)
  // 文件已存在
  assert_true(@fs.path_exists(dir + "/memory/product.md"))
  assert_true(@fs.path_exists(dir + "/memory/thinking.md"))
  assert_true(@fs.path_exists(dir + "/memory/reviews"))
}

// ---------------------------------------------------------------------------
// 用例 2：append / get
// ---------------------------------------------------------------------------

///|
test "selfdrive_2_append_get" {
  let dir = sd_dir("sd_c2_append")
  ignore(selfdrive_memory_init(dir, ns="sd-test"))
  // thinking 追加
  let j1 = match
    selfdrive_memory_append(
      dir,
      ns="sd-test",
      kind="thinking",
      content="第一轮思考",
      now="2026-09-23T10:00:00+08:00",
    ) {
    Ok(x) => x
    Err(m) => abort(m)
  }
  assert_eq(sd_str(j1, "action"), "append")
  // 再次追加
  ignore(
    selfdrive_memory_append(
      dir,
      ns="sd-test",
      kind="thinking",
      content="第二轮思考",
      now="2026-09-23T11:00:00+08:00",
    ),
  )
  let g = match selfdrive_memory_get(dir, ns="sd-test", kind="thinking") {
    Ok(x) => x
    Err(m) => abort(m)
  }
  assert_eq(sd_str(g, "action"), "get")
  assert_true(sd_bool(g, "exists"))
  assert_true(sd_str(g, "content").contains("第一轮思考"))
  assert_true(sd_str(g, "content").contains("第二轮思考"))
  // product 覆盖写
  ignore(
    selfdrive_memory_append(
      dir,
      ns="sd-test",
      kind="product",
      content="# 产品目标\n\n- 为什么做：自驱试点",
      now="2026-09-23T12:00:00+08:00",
    ),
  )
  let gp = match selfdrive_memory_get(dir, ns="sd-test", kind="product") {
    Ok(x) => x
    Err(m) => abort(m)
  }
  assert_true(sd_str(gp, "content").contains("自驱试点"))
  // 非法 kind
  match
    selfdrive_memory_append(dir, ns="sd-test", kind="bad", content="x", now="t") {
    Err(m) => assert_true(m.contains("未知 memory kind"))
    Ok(_) => abort("非法 kind 不应成功")
  }
  // 不存在的 kind 读取
  let gm = match selfdrive_memory_get(dir, ns="sd-test", kind="missing") {
    Ok(x) => x
    Err(m) => abort(m)
  }
  assert_eq(sd_str(gm, "action"), "get")
  assert_true(not(sd_bool(gm, "exists")))
}

// ---------------------------------------------------------------------------
// 用例 3：审视轮判定（未初始化 / 未到轮次）
// ---------------------------------------------------------------------------

///|
test "selfdrive_3_review_tick_idle" {
  let dir = sd_dir("sd_c3_idle")
  // 未初始化 memory → no_memory
  let j0 = match selfdrive_review_tick(dir, ns="sd-test", review_every=3) {
    Ok(x) => x
    Err(m) => abort(m)
  }
  assert_eq(sd_str(j0, "action"), "no_memory")
  // 初始化后无报告 → idle
  ignore(selfdrive_memory_init(dir, ns="sd-test"))
  let j1 = match selfdrive_review_tick(dir, ns="sd-test", review_every=3) {
    Ok(x) => x
    Err(m) => abort(m)
  }
  assert_eq(sd_str(j1, "action"), "idle")
  assert_eq(sd_str(j1, "pending"), "0")
  // 报告不足 → idle
  sd_report(dir, "20260920.10.00.00.md", "# 报告1")
  sd_report(dir, "20260920.11.00.00.md", "# 报告2")
  let j2 = match selfdrive_review_tick(dir, ns="sd-test", review_every=3) {
    Ok(x) => x
    Err(m) => abort(m)
  }
  assert_eq(sd_str(j2, "action"), "idle")
  assert_eq(sd_str(j2, "rounds"), "2")
  assert_eq(sd_str(j2, "reviewed"), "0")
  assert_eq(sd_str(j2, "pending"), "2")
}

// ---------------------------------------------------------------------------
// 用例 4：审视轮触发 → review
// ---------------------------------------------------------------------------

///|
test "selfdrive_4_review_tick_trigger" {
  let dir = sd_dir("sd_c4_review")
  ignore(selfdrive_memory_init(dir, ns="sd-test"))
  sd_report(dir, "20260920.10.00.00.md", "# 报告1")
  sd_report(dir, "20260920.11.00.00.md", "# 报告2")
  sd_report(dir, "20260920.12.00.00.md", "# 报告3")
  sd_report(dir, "20260920.13.00.00.md", "# 报告4")
  let j = match selfdrive_review_tick(dir, ns="sd-test", review_every=3) {
    Ok(x) => x
    Err(m) => abort(m)
  }
  assert_eq(sd_str(j, "action"), "review")
  assert_eq(sd_str(j, "pending"), "4")
  // recent_reports 应返回最近 3 份（字典序最大的 3 份）
  assert_eq(sd_arr_len(j, "recent_reports"), 3)
  assert_true(
    sd_arr_item(j, "recent_reports", 0).contains("20260920.11.00.00.md"),
  )
  assert_true(
    sd_arr_item(j, "recent_reports", 2).contains("20260920.13.00.00.md"),
  )
  // memory 摘要含四件套
  assert_eq(sd_arr_len(j, "memory"), 4)
}

// ---------------------------------------------------------------------------
// 用例 5：审视收口（报告先行）
// ---------------------------------------------------------------------------

///|
test "selfdrive_5_review_ready_report_first" {
  let dir = sd_dir("sd_c5_ready")
  ignore(selfdrive_memory_init(dir, ns="sd-test"))
  sd_report(dir, "20260920.10.00.00.md", "# 报告1")
  sd_report(dir, "20260920.11.00.00.md", "# 报告2")
  sd_report(dir, "20260920.12.00.00.md", "# 报告3")
  // 无审视报告 → safe_exit（报告先行，拒绝推进）
  let j0 = match selfdrive_review_ready(dir, ns="sd-test") {
    Ok(x) => x
    Err(m) => abort(m)
  }
  assert_eq(sd_str(j0, "action"), "safe_exit")
  // 落盘审视报告后 → reviewed，计数推进到当前报告数 3
  sd_review(
    dir, "20260920.13.00.00.md", "# 审视报告\n\n## Next Tasks\n- [任务A]\n",
  )
  let j1 = match selfdrive_review_ready(dir, ns="sd-test") {
    Ok(x) => x
    Err(m) => abort(m)
  }
  assert_eq(sd_str(j1, "action"), "reviewed")
  assert_eq(sd_str(j1, "reviewed"), "3")
  // 计数已推进：再 tick 不再触发（pending=0）
  let j2 = match selfdrive_review_tick(dir, ns="sd-test", review_every=3) {
    Ok(x) => x
    Err(m) => abort(m)
  }
  assert_eq(sd_str(j2, "action"), "idle")
  assert_eq(sd_str(j2, "reviewed"), "3")
  assert_eq(sd_str(j2, "pending"), "0")
}

// ---------------------------------------------------------------------------
// 用例 6：Next Tasks 解析
// ---------------------------------------------------------------------------

///|
test "selfdrive_6_parse_next_tasks" {
  let content = "# 审视报告\n\n## 上一轮回顾\n...\n\n## Next Tasks\n- [任务A：优化生成器]\n- [任务B：补测试]\n- [x] 已完成任务\n- [任务C]\n"
  let tasks = selfdrive_parse_next_tasks(content, max_tasks=5)
  assert_eq(tasks.length(), 3)
  assert_eq(tasks[0], "任务A：优化生成器")
  assert_eq(tasks[1], "任务B：补测试")
  assert_eq(tasks[2], "任务C")
  // max_tasks 截断
  let tasks2 = selfdrive_parse_next_tasks(content, max_tasks=2)
  assert_eq(tasks2.length(), 2)
  // 无 Next Tasks 段
  let tasks3 = selfdrive_parse_next_tasks(
    "# 审视报告\n没有任务段",
    max_tasks=5,
  )
  assert_eq(tasks3.length(), 0)
}

// ---------------------------------------------------------------------------
// 用例 7：审视任务发布 + 幂等防重
// ---------------------------------------------------------------------------

///|
test "selfdrive_7_publish_next_idempotent" {
  let dir = sd_dir("sd_c7_publish")
  ignore(selfdrive_memory_init(dir, ns="sd-test"))
  sd_report(dir, "20260920.10.00.00.md", "# 报告1")
  let e = sd_engine("temp/sd_c7.db")
  // 无审视报告 → wait
  let j0 = match
    selfdrive_publish_next(
      e,
      dir,
      ns="sd-test",
      now="2026-09-23T10:00:00+08:00",
      max_tasks=5,
    ) {
    Ok(x) => x
    Err(m) => abort(m)
  }
  assert_eq(sd_str(j0, "action"), "wait")
  // 落盘审视报告（含 2 条 Next Tasks）
  sd_review(
    dir, "20260920.13.00.00.md", "# 审视报告\n\n## Next Tasks\n- [自驱任务A]\n- [自驱任务B]\n",
  )
  // 发布：首次 → published 2 条，ns 内产生 2 个任务
  let j1 = match
    selfdrive_publish_next(
      e,
      dir,
      ns="sd-test",
      now="2026-09-23T10:05:00+08:00",
      max_tasks=5,
    ) {
    Ok(x) => x
    Err(m) => abort(m)
  }
  assert_eq(sd_str(j1, "action"), "published")
  assert_eq(sd_arr_len(j1, "published"), 2)
  assert_eq(e.list_in_ns("sd-test").length(), 2)
  // 再次发布：幂等跳过，不再新增
  let j2 = match
    selfdrive_publish_next(
      e,
      dir,
      ns="sd-test",
      now="2026-09-23T10:10:00+08:00",
      max_tasks=5,
    ) {
    Ok(x) => x
    Err(m) => abort(m)
  }
  assert_eq(sd_str(j2, "action"), "wait")
  assert_eq(sd_arr_len(j2, "published"), 0)
  assert_eq(sd_arr_len(j2, "skipped"), 2)
  assert_eq(e.list_in_ns("sd-test").length(), 2)
  // 任务描述内嵌幂等标记
  let tasks = e.list_in_ns("sd-test")
  assert_true(tasks[0].description.contains("[review:20260920.13.00.00.md:0]"))
  assert_true(tasks[1].description.contains("[review:20260920.13.00.00.md:1]"))
  // Agent Contract 已随自驱发布注入
  assert_true(
    tasks[0].description.contains(
      "## 执行契约（自驱注入 · Agent Contract）",
    ),
  )
  assert_true(
    tasks[0].description.contains("- Evidence: 交付物附可复现验证"),
  )
}

///|
test "selfdrive_8_agent_contract_fields" {
  // 纯函数契约生成：必须含 7 个字段标记，且 Objective 回填任务原文
  let c = sd_agent_contract("做一个自驱任务")
  let fields = [
    "- Objective:", "- Constraints:", "- Tool policy:", "- Stop conditions:", "- Escalation:",
    "- State discipline:", "- Evidence:",
  ]
  for f in fields {
    assert_true(c.contains(f))
  }
  assert_true(c.contains("做一个自驱任务"))
}
