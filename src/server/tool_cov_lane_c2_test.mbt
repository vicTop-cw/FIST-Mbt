// tool_cov_lane_c2_test.mbt —— Lane C「有状态 / 引擎生命周期族」第二批 4 个工具
//
// 覆盖工具：selfdrive_dispatch / atgc_old_compile / atgc_old_run / atgc_old_talk
// 验收判据：scripts/check_tool_coverage.py 的 A 外壳面（工具名出现在测试里）。
//
// ## 接线面（诚实声明，判例-29/30 —— 与 c1 同口径）
//
// 四个 handler 都在 `src/server/server.mbt` 的 `instrumented_tool(...)` 里以内联闭包/
// 同包顶层 `fn`（atgc 三支由 `atgc_tool_handlers.mbt` 抽离）形式存在，**包外拿不到闭包句柄**
// （`build_server` 非 pub，唯一 pub 入口是 `run_server`）。故本文件锁的是 handler 体内联逻辑
// **实际调用的实现函数与其分叉读数**：
//
//   selfdrive_dispatch → @engine.FistEngine::triage（suggestion.task_id 有无 = 「有没有可派单」）
//                        + @executor.ExecutorRegistry::route_pick（best.coverage/name = 「派给谁」）
//                        + @engine.FistEngine::claim（落成动作）
//   atgc_old_compile   → @atgc_old.atgc_compile
//   atgc_old_run       → @atgc_old.atgc_run
//   atgc_old_talk      → @atgc_old.atgc_talk
//
// ⇒ 变异有效面：把 triage 的 suggestion 去掉、把 route_pick 的覆盖率排序改坏、把 atgc 的
// 转录/执行语义改坏，本文件必红；**闭包里漏传具名实参**抓不到（结构性残差，已回执上报）。
//
// atgc 三支是**纯计算衍生子项目**（无 IO 无状态）：本文件按「同一输入两次调用结果相等」
// 这一确定性口径锁，并附边界（非法碱基）格 —— 非法输入必须走 Err/提示，不许崩。

// ---------------------------------------------------------------------------
// 辅助（复用 c1 的 lc_* 助手：同包测试文件共用一份）
// ---------------------------------------------------------------------------

///|
/// 读 JSON 数字字段（缺失或类型不符直接失败）。
fn lc2_num(j : Json, key : String) -> Double {
  match jget(j, key) {
    Some(Json::Number(n, ..)) => n
    _ => abort("字段 \{key} 缺失或不是数字: " + j.stringify())
  }
}

///|
/// triage 回执里 suggestion.task_id（无 suggestion / 无 task_id 均返回 ""）。
fn lc2_suggestion_task_id(tri : Json) -> String {
  match jget(tri, "suggestion") {
    Some(sug) =>
      match jget(sug, "task_id") {
        Some(Json::String(s)) => s
        _ => ""
      }
    None => ""
  }
}

///|
/// 把 atgc 的 JSON 字符串回执解析成 Json（解析失败直接失败，不做字符串搜）。
fn lc2_parse(raw : String) -> Json {
  @json.parse(raw) catch {
    _ => abort("atgc 回执不是合法 JSON: " + raw)
  }
}

///|
/// 发布一条指定 ns 的根任务（dispatch 用例要 ns 过滤，故不复用 c1 的 lc_publish_root）。
fn lc2_publish_ns(e : @engine.FistEngine, desc : String, ns : String) -> String {
  match
    e.publish(
      project_dir="/proj/lanec",
      description=desc,
      created_by="human_steward",
      now="2026-10-28T11:00:00Z",
      ns~,
    ) {
    Ok(id) => id
    Err(m) => abort("publish 失败: \{m}")
  }
}

// ---------------------------------------------------------------------------
// 一、selfdrive_dispatch（重点：降级分支，不许只测 happy path）
// ---------------------------------------------------------------------------

///|
/// 降级分支 ①：队列为空 → triage 不给 suggestion ⇒ handler 走 dispatched=false 分支
/// （回执 note「无可领取的推荐任务」）。对照组：发布一条任务后 suggestion 出现（证明 false 不是恒 false）。
test "selfdrive_dispatch 降级①：无待领取任务 → triage 无 suggestion（dispatched=false 分支）" {
  let e = lc_engine()
  let empty = e.triage("lanec", "self", "json")
  assert_eq(lc2_num(empty, "count").to_int(), 0)
  assert_true(
    jget(empty, "suggestion") is None,
    msg="空队列不得给 suggestion（否则 handler 会拿空 task_id 去派单）: " +
      empty.stringify(),
  )
  assert_eq(lc2_suggestion_task_id(empty), "")
  // 对照：发布一条待领取任务后 suggestion 必须出现，且 task_id 指回该任务
  let id = lc2_publish_ns(e, "编写 json 序列化模块", "lanec")
  let tri = e.triage("lanec", "self", "json")
  assert_eq(lc2_num(tri, "count").to_int(), 1)
  assert_eq(lc2_suggestion_task_id(tri), id)
}

///|
/// 降级分支 ②：**没有匹配执行者** → 候选覆盖率全为 0（内置执行者无能力标签）
/// ⇒ handler 的判定 `cov > 0 && best_name != ""` 为假 ⇒ 回退把任务认领给 `agent` 本身。
/// 这是「能力路由失配」的唯一兜底路径，必须断言，不能只测 happy path。
test "selfdrive_dispatch 降级②：无匹配执行者 → route_pick 无 best → 回退认领给 agent" {
  let e = lc_engine()
  let id = lc2_publish_ns(e, "编写 json 序列化模块", "lanec")
  let tri = e.triage("lanec", "self", "json")
  assert_eq(lc2_suggestion_task_id(tri), id) // 有任务可派
  // 裸注册表 = 内置 McpDelegateExecutor / manual 两条**无能力标签**的执行者（new() 预置）。
  // 所以「无匹配执行者」的实测形状不是「没有候选」，而是「候选覆盖率全为 0」——
  // handler 的判定 `cov > 0 && best_name != ""` 在这一格必为假，从而回退给 agent。
  let reg = @executor.ExecutorRegistry::new()
  let load : Map[String, Int32] = Map([])
  let route = reg.route_pick("json", load)
  assert_eq(
    lc2_num(route, "count").to_int(),
    2,
    msg="new() 预置 McpDelegateExecutor/manual 两条内置执行者: " +
      route.stringify(),
  )
  let best = match jget(route, "best") {
    Some(Json::Object(o)) => Json::object(o)
    Some(other) =>
      abort("有候选时 best 不得为 null: " + other.stringify())
    None => abort("best 字段缺失: " + route.stringify())
  }
  assert_eq(
    lc2_num(best, "coverage"),
    0.0,
    msg="内置执行者无能力标签 ⇒ 覆盖率必须为 0（handler 据此回退）",
  )
  // 全部候选覆盖率都是 0：没有任何执行者能接这单
  match jget(route, "candidates") {
    Some(Json::Array(rows)) =>
      for r in rows {
        assert_eq(
          lc2_num(r, "coverage"),
          0.0,
          msg="无能力标签的执行者覆盖率必须为 0: " +
            r.stringify(),
        )
      }
    _ => abort("candidates 缺失: " + route.stringify())
  }
  // 回退分支真能落成动作：以 agent 身份认领成功，且 assignee 就是回退身份
  match e.claim(task_id=id, assignee="self", now="2026-10-28T11:01:00Z") {
    Ok(t) => {
      assert_eq(t.assignee, Some("self"))
      assert_true(
        t.get_status().is_claimed(),
        msg="回退认领后应为已领取",
      )
    }
    Err(m) => abort("回退认领应成功（待领取→已领取）: \{m}")
  }
}

///|
/// 正常路径：注册执行者能力命中 → triage 顶部任务 + route_pick 命中该执行者 → 认领给它。
/// 「路由推荐」要真的落成「派单动作」，所以最后一格必须查任务状态的迁移结果。
test "selfdrive_dispatch 正常：能力命中 → route_pick 选中执行者 → 任务被认领给该执行者" {
  let e = lc_engine()
  let id = lc2_publish_ns(e, "编写 json 序列化模块", "lanec")
  let reg = @executor.ExecutorRegistry::new()
  let reg2 = reg.register("w-json").add_ability("w-json", ["json"])
  let load : Map[String, Int32] = Map([])
  let route = reg2.route_pick("json", load)
  assert_eq(
    lc2_num(route, "count").to_int(),
    3,
    msg="2 条内置 + 1 条新注册（w-json）都进候选: " +
      route.stringify(),
  )
  let best = match jget(route, "best") {
    Some(Json::Object(o)) => Json::object(o)
    _ => abort("有候选时 best 必须是对象: " + route.stringify())
  }
  assert_eq(lc_str(best, "name"), "w-json")
  assert_true(
    lc2_num(best, "coverage") > 0.0,
    msg="能力命中时覆盖率须 > 0",
  )
  // triage 侧：同一条任务是可派单的顶部候选
  let tri = e.triage("lanec", "self", "json")
  assert_eq(lc2_suggestion_task_id(tri), id)
  // 落成动作：认领给路由选中的执行者
  match e.claim(task_id=id, assignee="w-json", now="2026-10-28T11:02:00Z") {
    Ok(t) => {
      assert_eq(t.assignee, Some("w-json"))
      assert_true(t.get_status().is_claimed())
    }
    Err(m) => abort("派单认领失败: \{m}")
  }
  // 派完即出队：再次 triage 不得再把同一条任务推成 suggestion
  let tri2 = e.triage("lanec", "self", "json")
  assert_eq(lc2_suggestion_task_id(tri2), "")
}

// ---------------------------------------------------------------------------
// 二、atgc_old_compile（纯计算：确定性 + 边界）
// ---------------------------------------------------------------------------

///|
/// 编译 (1+2)*3 程序：回执必须是 JSON 且带齐 5 个契约字段；同一输入两次调用**逐字相等**。
test "atgc_old_compile：编译产出契约字段 + 同一输入两次调用结果相等" {
  let prog = "ATGCATAATCATAAGATTCATAACTTTAAATAA"
  let raw1 = match @atgc_old.atgc_compile(prog) {
    Ok(s) => s
    Err(m) => abort("合法 DNA 不该编译失败: \{m}")
  }
  let j = lc2_parse(raw1)
  assert_true(
    lc_str(j, "transcription") != "",
    msg="转录产物不该为空（有义链/反义链至少一路）",
  )
  let ops = lc_str(j, "ops")
  assert_true(
    ops.contains("START"),
    msg="操作列表应以 START 起头: " + ops,
  )
  assert_true(
    ops.contains("ADD") && ops.contains("MUL"),
    msg="(1+2)*3 应含 ADD 与 MUL: " + ops,
  )
  assert_true(lc_str(j, "mode") != "", msg="编译模式不得为空")
  assert_eq(lc_bool(j, "rollback"), false, msg="该程序未开 .ROLLBACK")
  // 确定性：同一输入两次调用结果逐字相等（纯计算子项目的硬口径）
  let raw2 = match @atgc_old.atgc_compile(prog) {
    Ok(s) => s
    Err(m) => abort("第二次编译失败: \{m}")
  }
  assert_eq(raw2, raw1, msg="同一输入两次编译结果必须相等")
}

///|
/// 边界：非法碱基（`-`/`X` 等）必须返回 Err 且文案点名「无效输入」，不许崩溃/不许静默编出空程序。
test "atgc_old_compile 边界：非法碱基 → Err（不许崩溃，也不许编出空程序）" {
  let bad = "ATGC-XYZ"
  match @atgc_old.atgc_compile(bad) {
    Err(m) => {
      assert_true(m.contains("无效输入"), msg=m)
      assert_true(
        m.contains("ATGCU"),
        msg="错误文案应指明允许的碱基集: " + m,
      )
    }
    Ok(s) => abort("非法碱基必须被拒，实际产出: " + s)
  }
  // 对照：空白（空格/换行）不算非法 —— 合法输入不误杀。
  // 注：`;` 之后只能跟空白（valid_input 只放行 [ATGCU]/空白/`;`），写「注释文字」反而会非法。
  match @atgc_old.atgc_compile("ATG C\nCAT") {
    Ok(_) => ()
    Err(m) => abort("空白不应被判非法: \{m}")
  }
}

// ---------------------------------------------------------------------------
// 三、atgc_old_run（纯计算：确定性 + 数值 + 边界）
// ---------------------------------------------------------------------------

///|
/// 运行 (1+2)*3 程序：输出 9、result=ok、未回滚、8 条栈轨迹；同一输入两次结果相等。
test "atgc_old_run：执行 (1+2)*3 输出 9 + 栈轨迹条数 + 同一输入两次结果相等" {
  let prog = "ATGCATAATCATAAGATTCATAACTTTAAATAA"
  let raw1 = match @atgc_old.atgc_run(prog) {
    Ok(s) => s
    Err(m) => abort("合法 DNA 不该运行失败: \{m}")
  }
  let j = lc2_parse(raw1)
  assert_eq(lc_str(j, "output"), "9", msg="(1+2)*3 的输出必须是 9")
  assert_eq(lc_str(j, "result"), "ok")
  assert_eq(lc_bool(j, "rolled_back"), false)
  assert_eq(
    lc_arr_len(j, "stack_history"),
    8,
    msg="每条指令一次栈轨迹（见 atgc_test 验收 2）",
  )
  let raw2 = match @atgc_old.atgc_run(prog) {
    Ok(s) => s
    Err(m) => abort("第二次运行失败: \{m}")
  }
  assert_eq(
    raw2,
    raw1,
    msg="同一输入两次运行结果必须相等（纯计算、无随机源）",
  )
}

///|
/// 边界：非法碱基 → Err；且 run 与 compile 的拒绝口径一致（同一 valid_input 门）。
test "atgc_old_run 边界：非法碱基 → Err（与 compile 同口径，不崩溃）" {
  match @atgc_old.atgc_run("ATGC123") {
    Err(m) => assert_true(m.contains("无效输入"), msg=m)
    Ok(s) => abort("非法碱基必须被拒，实际产出: " + s)
  }
  // 另一条真实可跑的向量：1+2+2 = 5（§10.1），证明 run 不是只会跑一条硬编码程序
  let raw = match @atgc_old.atgc_run("ATGCATAATCATAAGCATAAGATTATTAAATAA") {
    Ok(s) => s
    Err(m) => abort("§10.1 程序不应失败: \{m}")
  }
  assert_eq(lc_str(lc2_parse(raw), "output"), "5")
}

// ---------------------------------------------------------------------------
// 四、atgc_old_talk（纯计算：叙事 + 确定性 + 边界）
// ---------------------------------------------------------------------------

///|
/// 叙事三态：① 无 seq → 简介；② 有 seq → 生物故事且数值与 run 一致；③ 带 question → 追加回答段。
/// 同一输入两次结果相等（叙事文本也是确定性产物）。
test "atgc_old_talk：三态叙事（简介 / 故事 / 带问题）+ 同一输入两次结果相等" {
  // ① 无序列 → 双链虚拟机简介
  let intro = @atgc_old.atgc_talk("", "")
  assert_true(
    intro.contains("ATGC 双链虚拟机"),
    msg="无 seq 应返回简介: " + intro,
  )
  assert_true(intro.contains("四进制"), msg="简介应说明四进制底座")
  // ② 有序列 → 生物故事，且最终数值与 atgc_run 一致（两工具不许各说一套）
  let prog = "ATGCATAATCATAAGATTCATAACTTTAAATAA"
  let story = @atgc_old.atgc_talk(prog, "")
  assert_true(
    story.contains("DNA 故事"),
    msg="有 seq 应讲生物故事: " + story,
  )
  assert_true(
    story.contains("结果：ok"),
    msg="故事应带上运行结果: " + story,
  )
  let run_raw = match @atgc_old.atgc_run(prog) {
    Ok(s) => s
    Err(m) => abort("atgc_run 失败: \{m}")
  }
  let out = lc_str(lc2_parse(run_raw), "output")
  assert_true(
    story.contains(out),
    msg="叙事里的数值必须与 run 的输出（" +
      out +
      "）一致: " +
      story,
  )
  // ③ 带问题 → 追加「关于你的问题」段
  let q = "这个程序怎么算出 9 的？"
  let talked = @atgc_old.atgc_talk(prog, q)
  assert_true(
    talked.contains("关于你的问题"),
    msg="带 question 应追加回答段: " + talked,
  )
  assert_true(talked.contains(q))
  // 确定性：同一输入两次调用逐字相等
  assert_eq(
    @atgc_old.atgc_talk(prog, q),
    talked,
    msg="同一输入两次叙事必须相等",
  )
}

///|
/// 边界：非法输入不崩溃 —— talk 无 Err 分支，必须以「无法解读」提示代替，且不得编出故事。
test "atgc_old_talk 边界：非法碱基 → 明确提示「无法解读」（不崩溃、不编故事）" {
  let bad = @atgc_old.atgc_talk("ATGC-XYZ", "")
  assert_true(
    bad.contains("无法解读"),
    msg="非法输入应提示无法解读: " + bad,
  )
  assert_true(
    !bad.contains("DNA 故事"),
    msg="非法输入不得编出生物故事（假绿）: " + bad,
  )
  // 边界：只有空白也算「无序列」→ 简介（trim 口径）
  let blank = @atgc_old.atgc_talk("   ", "")
  assert_true(
    blank.contains("ATGC 双链虚拟机"),
    msg="纯空白按无 seq 处理: " + blank,
  )
}
