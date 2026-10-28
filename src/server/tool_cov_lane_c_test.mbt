// tool_cov_lane_c_test.mbt —— Lane C「有状态 / 引擎生命周期族」工具覆盖（第一批 3 个工具）
//
// 覆盖工具：dag_publish / selfdrive_init / selfdrive_get
// 验收判据：scripts/check_tool_coverage.py 的 A 外壳面（工具名出现在测试里）。
//
// ## 接线面（诚实声明，判例-29/30）
//
// 这三个工具的 handler 是 `src/server/server.mbt` 里 `instrumented_tool(...)` 的
// **匿名闭包**，包外无法取得句柄（`build_server` 不是 pub，唯一 pub 入口是 `run_server`），
// 所以本文件锁的是「handler 体内联逻辑**调用的实现函数** + 文档承诺的回执形状 +
// handler 依赖的守卫」，而不是闭包本身：
//
//   dag_publish     → @engine.FistEngine::publish_with_deps / deps_satisfied / ready_tasks
//                     （handler 把 depends_on 的 JSON 数组解析成 Array[String] 后原样透传）
//   selfdrive_init  → @server.write_gate_audit（先过写入门禁 + 落审计）+ @ops.selfdrive_memory_init
//   selfdrive_get   → @ops.selfdrive_memory_get
//
// ⇒ 变异对照的有效面：把上述实现函数改坏（丢 depends_on / 不写文件 / get 造假内容）本文件必红；
// **闭包体内部漏传一个具名实参**（例如 handler 忘了把 depends_on~ 传给 publish_with_deps）
// 本文件抓不到 —— 这是匿名闭包不可注入的结构性残差，已在回执里作为缺口上报，
// 不在此处用「工具名只出现在注释里」的假绿掩盖（判例-30）。

// ---------------------------------------------------------------------------
// 测试辅助
// ---------------------------------------------------------------------------

///|
/// 独立内存引擎（不碰全局 mstore，用例之间零串扰）。
fn lc_engine() -> @engine.FistEngine {
  @engine.FistEngine::new()
}

///|
/// 读 JSON 字符串字段（缺失返回 ""，类型不符直接失败）。
fn lc_str(j : Json, key : String) -> String {
  match jget(j, key) {
    Some(Json::String(s)) => s
    Some(_) => abort("字段 \{key} 不是字符串: " + j.stringify())
    None => ""
  }
}

///|
/// 读 JSON 布尔字段（缺失或类型不符直接失败——不接受「缺失当 false」的软判）。
fn lc_bool(j : Json, key : String) -> Bool {
  match jget(j, key) {
    Some(Json::True) => true
    Some(Json::False) => false
    _ => abort("字段 \{key} 缺失或不是布尔: " + j.stringify())
  }
}

///|
/// 读 JSON 数组字段长度（缺失直接失败）。
fn lc_arr_len(j : Json, key : String) -> Int32 {
  match jget(j, key) {
    Some(Json::Array(a)) => a.length()
    _ => abort("字段 \{key} 缺失或不是数组: " + j.stringify())
  }
}

///|
/// 发布一条无依赖根任务（等价 dag_publish 在 depends_on=[] 时的下游路径）。
fn lc_publish_root(e : @engine.FistEngine, desc : String) -> String {
  match
    e.publish(
      project_dir="/proj/lanec",
      description=desc,
      created_by="human_steward",
      now="2026-10-28T10:00:00Z",
    ) {
    Ok(id) => id
    Err(m) => abort("publish 失败: \{m}")
  }
}

///|
/// dag_publish 的实现路径：publish_with_deps（handler 解析完 depends_on 后调的就是它）。
fn lc_publish_with_deps(
  e : @engine.FistEngine,
  desc : String,
  deps : Array[String],
  now~ : String = "2026-10-28T10:01:00Z",
) -> String {
  match
    e.publish_with_deps(
      project_dir="/proj/lanec",
      description=desc,
      depends_on=deps,
      created_by="human_steward",
      now~,
    ) {
    Ok(id) => id
    Err(m) => abort("publish_with_deps 失败: \{m}")
  }
}

///|
/// 取任务 id 列表（断言用的可比读数）。
fn lc_ids(tasks : Array[@core.Task]) -> Array[String] {
  tasks.map(fn(t) { t.id })
}

///|
/// 走完 认领→执行→提交→验收，把任务推到「已完成」。
fn lc_drive_done(e : @engine.FistEngine, id : String) -> Unit {
  match e.claim(task_id=id, assignee="agent_lc", now="2026-10-28T10:02:00Z") {
    Ok(_) => ()
    Err(m) => abort("claim \{id} 失败: \{m}")
  }
  match
    e.execute(task_id=id, deliverable="d-\{id}", now="2026-10-28T10:03:00Z") {
    Ok(_) => ()
    Err(m) => abort("execute \{id} 失败: \{m}")
  }
  match e.submit(task_id=id, now="2026-10-28T10:04:00Z") {
    Ok(_) => ()
    Err(m) => abort("submit \{id} 失败: \{m}")
  }
  match
    e.verify(task_id=id, verifier="human_steward", now="2026-10-28T10:05:00Z") {
    Ok(_) => ()
    Err(m) => abort("verify \{id} 失败: \{m}")
  }
}

///|
/// 准备自驱用例目录：清掉 memory 四件套（不删目录），使用例可重复运行。
fn lc_sd_dir(name : String) -> String {
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
  for f in ["product.md", "target.md", "task.md", "thinking.md"] {
    @fs.remove_file(d + "/memory/" + f) catch {
      _ => ()
    }
  }
  d
}

// ---------------------------------------------------------------------------
// 一、dag_publish
// ---------------------------------------------------------------------------

///|
/// 正常路径：带 depends_on 发布 → 三条读数全部要成立
/// ① 任务真存在（回执 task_id 能读回任务本体）；② 依赖边真落库；③ dag_check/dag_ready 符合预期。
test "dag_publish：带 depends_on 发布 → 任务可读回 + 依赖边成立 + dag_check/dag_ready 读数符合预期" {
  let e = lc_engine()
  let pre = lc_publish_root(e, "前置任务：准备语料")
  let child = lc_publish_with_deps(e, "后继任务：消费语料", [pre])
  // ① 任务真的落库（不是只回执一个字符串）
  let t = match e.get_task(child) {
    Some(t) => t
    None => abort("dag_publish 回执的 task_id 读不回: " + child)
  }
  assert_eq(t.id, child)
  assert_true(
    t.get_status().is_pending(),
    msg="新发布任务应为待领取: " + t.id,
  )
  // ② 依赖边成立：depends_on 确实写进了任务（不是只写在回执文字里）
  assert_eq(t.depends_on.length(), 1)
  assert_eq(t.depends_on[0], pre)
  // ③ dag_check 读数：前驱仍是待领取 → 依赖未满足
  assert_eq(
    e.deps_satisfied(child),
    false,
    msg="前驱未完成时 dag_check 必须报未满足: " + child,
  )
  // ④ dag_ready 读数：前驱在就绪集，后继不在（依赖边真的参与调度）
  let ready = lc_ids(e.ready_tasks(ns_filter="default"))
  assert_true(
    ready.contains(pre),
    msg="无依赖的前驱应在 dag_ready: " + ready.join(","),
  )
  assert_true(
    !ready.contains(child),
    msg="依赖未满足的后继不得进 dag_ready: " + ready.join(","),
  )
}

///|
/// 依赖边要「真的影响调度」：前驱完成后 dag_check 翻 true、后继才进 dag_ready。
/// 若实现把 depends_on 写成一个永不参与判定的装饰字段，这两条断言会红。
test "dag_publish：前驱完成后 dag_check 翻 true + 后继进 dag_ready（依赖边真参与调度）" {
  let e = lc_engine()
  let pre = lc_publish_root(e, "前置任务：准备语料")
  let child = lc_publish_with_deps(e, "后继任务：消费语料", [pre])
  // 基线（翻转前）——没有这一格，"翻 true"可能只是恒 true
  assert_eq(e.deps_satisfied(child), false)
  lc_drive_done(e, pre)
  assert_eq(
    e.deps_satisfied(child),
    true,
    msg="前驱验收完成后 dag_check 必须翻 true: " + child,
  )
  let ready = lc_ids(e.ready_tasks(ns_filter="default"))
  assert_true(
    ready.contains(child),
    msg="前驱完成后后继应可领取: " + ready.join(","),
  )
}

///|
/// 边界：依赖不存在必须**拒绝发布**且不留悬空边/半成品任务。
/// 边界：created_by 非人类身份必须拒绝（publish 的人类特权口径）。
test "dag_publish 边界：不存在的依赖被拒且不落半成品任务 + created_by 只允许人类" {
  let e = lc_engine()
  let before = e.list_all().length()
  match
    e.publish_with_deps(
      project_dir="/proj/lanec",
      description="孤儿任务：依赖一个不存在的 id",
      depends_on=["NO-SUCH-DEP"],
      created_by="human_steward",
      now="2026-10-28T10:06:00Z",
    ) {
    Err(m) => assert_true(m.contains("依赖任务不存在"), msg=m)
    Ok(_) =>
      abort(
        "依赖不存在时不该发布成功（会留下悬空依赖边）",
      )
  }
  // 拒绝必须是「整笔不落库」，不是「先建任务再报错」
  assert_eq(
    e.list_all().length(),
    before,
    msg="被拒的 dag_publish 不得留下半成品任务",
  )
  // 边界：非人类发布者
  match
    e.publish_with_deps(
      project_dir="/proj/lanec",
      description="机器人发布",
      depends_on=[],
      created_by="robot",
      now="2026-10-28T10:07:00Z",
    ) {
    Err(m) => assert_true(m.contains("仅限人类指挥官"), msg=m)
    Ok(_) => abort("created_by=robot 应被拒绝")
  }
  // 边界：dag_check 对不存在的任务返回 false（不是误判为「已满足」）；
  // 注意此返回值与「依赖未满足」不可分，属已知语义模糊，见回执「缺口与风险」。
  assert_eq(e.deps_satisfied("NO-SUCH-TASK"), false)
}

// ---------------------------------------------------------------------------
// 二、selfdrive_init → selfdrive_get
// ---------------------------------------------------------------------------

///|
/// 硬要求：init 后 get 必须回读到**同一会话状态**（回读一致）。
/// 三条读数：init 真建出四件套；get 的 exists 为真；get 的 content 与磁盘逐字相等。
test "selfdrive_init → selfdrive_get：init 后 get 回读到同一份状态（content 与磁盘逐字相等）" {
  let dir = lc_sd_dir("lc_sd_c1")
  let now = "2026-10-28T10:08:00Z"
  // handler 的第一道门：写入门禁 + 审计（memory/thinking.md 在白名单内，必须放行）
  let audit = @ops.AuditLog::new()
  match
    @server.write_gate_audit(
      dir, "memory/thinking.md", audit, now, "selfdrive_init",
    ) {
    Ok(_) => ()
    Err(m) => abort("白名单内的 memory/thinking.md 不该被门拒: \{m}")
  }
  let j_init = match @ops.selfdrive_memory_init(dir, ns="lanec") {
    Ok(j) => j
    Err(m) => abort("selfdrive_init 失败: \{m}")
  }
  assert_eq(lc_str(j_init, "action"), "init")
  assert_eq(lc_str(j_init, "namespace"), "lanec")
  // 四件套全部新建（不是「返回 Ok 就算成功」）
  assert_eq(lc_arr_len(j_init, "created"), 4)
  assert_eq(lc_arr_len(j_init, "skipped"), 0)
  assert_eq(lc_arr_len(j_init, "errors"), 0)
  // 回读一致：get 的 content 必须等于磁盘原文
  let j_get = match @ops.selfdrive_memory_get(dir, ns="lanec", kind="product") {
    Ok(j) => j
    Err(m) => abort("selfdrive_get 失败: \{m}")
  }
  assert_eq(lc_str(j_get, "action"), "get")
  assert_eq(lc_bool(j_get, "exists"), true)
  let on_disk = @fs.read_file_to_string(
    dir + "/memory/product.md",
    encoding="utf8",
  ) catch {
    _ => abort("读盘失败: product.md")
  }
  assert_eq(
    lc_str(j_get, "content"),
    on_disk,
    msg="get 回读内容必须与磁盘逐字相等",
  )
  assert_true(
    lc_str(j_get, "content").contains("产品目标"),
    msg="应回读到 product 模板本体",
  )
  // 二次 init 幂等：不覆盖，且 get 回读仍与磁盘一致（同一会话状态不被改写）
  let j_init2 = match @ops.selfdrive_memory_init(dir, ns="lanec") {
    Ok(j) => j
    Err(m) => abort("selfdrive_init 第二次失败: \{m}")
  }
  assert_eq(lc_arr_len(j_init2, "created"), 0)
  assert_eq(lc_arr_len(j_init2, "skipped"), 4)
  let j_get2 = match
    @ops.selfdrive_memory_get(dir, ns="lanec", kind="product") {
    Ok(j) => j
    Err(m) => abort("selfdrive_get 第二次失败: \{m}")
  }
  assert_eq(
    lc_str(j_get2, "content"),
    on_disk,
    msg="幂等 init 不得改写既有内容",
  )
}

///|
/// 边界：未初始化时 get 必须 exists=false 且**不得**回一个空串冒充 content；
/// 对照组：init 之后同一 kind 的 exists 翻 true（证明 false 不是恒 false）。
/// 边界：越界写入门禁必须拒，且拒绝要落审计（handler 依赖这条拒路返回 Err）。
test "selfdrive_get 边界：未初始化 → exists=false 且无 content；越界写入被门拒并落审计" {
  let dir = lc_sd_dir("lc_sd_c2")
  let j0 = match @ops.selfdrive_memory_get(dir, ns="lanec", kind="thinking") {
    Ok(j) => j
    Err(m) => abort("selfdrive_get 失败: \{m}")
  }
  assert_eq(lc_str(j0, "action"), "get")
  assert_eq(lc_bool(j0, "exists"), false)
  assert_true(
    jget(j0, "content") is None,
    msg="文件不存在时不得回 content 字段（空串冒充内容即假绿）: " +
      j0.stringify(),
  )
  assert_eq(lc_str(j0, "kind"), "thinking")
  // 对照：init 之后 exists 翻 true
  ignore(@ops.selfdrive_memory_init(dir, ns="lanec"))
  let j1 = match @ops.selfdrive_memory_get(dir, ns="lanec", kind="thinking") {
    Ok(j) => j
    Err(m) => abort("selfdrive_get 失败: \{m}")
  }
  assert_eq(lc_bool(j1, "exists"), true)
  // 边界：越界写入门禁（.git/config 不在白名单）——handler 在 init 前遇到它必须回 Err
  let audit = @ops.AuditLog::new()
  match
    @server.write_gate_audit(
      dir, ".git/config", audit, "2026-10-28T10:09:00Z", "selfdrive_get",
    ) {
    Ok(_) => abort("白名单外的 .git/config 应被写入门禁拒绝")
    Err(m) => assert_true(m.contains("越界写入被拒"), msg=m)
  }
  let entries = audit.entries()
  assert_eq(entries.length(), 1, msg="被拒的写入必须落一条审计")
  assert_eq(entries[0].action, "write_gate:reject")
  assert_true(
    entries[0].detail.contains("selfdrive_get"),
    msg="审计明细必须点名是哪个工具被拒: " + entries[0].detail,
  )
}
