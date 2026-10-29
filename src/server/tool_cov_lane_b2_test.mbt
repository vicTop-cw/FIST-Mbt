// tool_cov_lane_b2_test.mbt —— Lane B（env / IO / 会话态族）工具外壳覆盖锁 · 第二批 4 格。
//
// 覆盖工具（`check_tool_coverage.py` 的「外壳零覆盖」清单点名项）：
//   · github_issue_close    —— close 计划的前置面（空映射 / 无 repo 不生成 curl / 合法映射的 PUT 形态）
//   · github_issue_comment  —— 「未 flush 必拒」+ 空参拒绝 + flush 后的 POST 形态
//   · assistant_resign      —— 内存引擎状态机：未注册拒 / 在任退位 / 退位不删行 / 重复退位幂等
//   · lock_status           —— 内存引擎回读：未锁 → active → released（行在但 locked=false）→ 过期 sweep
//
// 诚实边界（不吹全绿）：
//   ① `github_issue_close` / `github_issue_comment` 的 `force` 硬门写在 `run_server` 的 handler 闭包里，
//      **无法从测试进程调用**（`run_server` 会拉起 stdio 分发，不是可单测的入口）。本文件因此用两种手段：
//      · 行为面：测 handler 真正调用的 build_close_plan / build_comment_plan 的**全部前置拒绝分支**
//        （这两支就是「不发网络请求」的那一半，handler 在 force 通过后原样转交给它们）；
//      · 源码面：一格**显式标注的接线锁**，钉死 force 文案与 `if !force` 早退仍在（判例-29：
//        机制格 ≠ 实现路径格）。真正的 force 行为另有端到端证据（`fist.py call` 实调，不在本文件）。
//   ② 真实网络成功路径（真发 PUT/POST）**一律未测**：需要真实 token 与外部网络，超出本任务边界。
//   ③ 未配置态的形状面已在 `tool_cov_lane_b_test.mbt`（env 四元组）覆盖，本文件不重复。
//
// 复用 `tool_cov_lane_b_test.mbt` 的包级 helper（lb_jbool / lb_jstr / lb_jnum / lb_jarr /
// lb_bool / lb_str / lb_int / lb_arr_len / lb_queue_dir / lb_has_key / lb_sev / lb_first_pending_bug_id）。

// ---------------------------------------------------------------------------
// 本文件新增辅助件
// ---------------------------------------------------------------------------

///|
/// 子串出现次数（源码面接线锁用；只数**代码/文案**字面量，不数注释里的同一串）。
fn lb2_count(hay : String, needle : String) -> Int32 {
  if needle.is_empty() {
    return 0
  }
  let mut n = 0
  let mut rest = hay
  while true {
    match rest.find(needle) {
      None => break
      Some(i) => {
        n = n + 1
        let next = i + needle.length()
        // deprecated substring → 切片。安全性：`i` 来自 find、`needle.length() > 0`
        // ⇒ next = i + len ≤ rest.length()（B0/B1 边界内，实测同值）。
        rest = rest[next:].to_string()
      }
    }
  }
  n
}

///|
/// 读 `src/server/server.mbt` 源码（接线锁专用；读不到即红——不许静默跳过）。
fn lb2_server_src() -> String {
  @fs.read_file_to_string("src/server/server.mbt", encoding="utf8") catch {
    _ =>
      abort(
        "读不到 src/server/server.mbt（测试须在项目根跑）——本接线锁无法自证",
      )
  }
}

///|
/// 取 plan 数组的第 0 项（close 计划）：返回 (bug_id, repo, issue_number, curl_command)。
fn lb2_plan_first(j : Json) -> (String, String, Int32, String) {
  let arr = match lb_jarr(j, "plan") {
    Some(a) => a
    None => abort("close plan 缺少 plan 数组： " + j.stringify())
  }
  let first = match arr.get(0) {
    Some(Json::Object(m)) => m
    _ => abort("close plan 为空或首项非对象： " + j.stringify())
  }
  let bug_id = match first.get("bug_id") {
    Some(Json::String(s)) => s
    _ => abort("plan[0].bug_id 非字符串")
  }
  let repo = match first.get("repo") {
    Some(Json::String(s)) => s
    _ => abort("plan[0].repo 非字符串")
  }
  let num = match first.get("issue_number") {
    Some(Json::Number(n, ..)) => n.to_int()
    _ => abort("plan[0].issue_number 非数字")
  }
  let curl = match first.get("curl_command") {
    Some(Json::String(s)) => s
    _ => abort("plan[0].curl_command 非字符串")
  }
  (bug_id, repo, num, curl)
}

// ---------------------------------------------------------------------------
// 1) github_issue_close —— 前置面（空映射 / 无 repo / 合法映射的 PUT 形态）
// ---------------------------------------------------------------------------

///|
/// 【B2-CL】`github_issue_close` 背后的 `github_build_close_plan` 三态 + 非法入参。
///
/// handler 的控制流是「force 过门 → 解析 issue_numbers_json → build_close_plan →
/// 空 plan 则回 executed=false 不执行任何 curl」。所以**plan 为空**就是「不发网络」的那一半，
/// 本格把它钉住：
///   ① 空映射 ⇒ generated=0 / plan=[]（handler 会走「没有可以 close 的 issue」分支）
///   ② 队列里没有该 bug ⇒ 找不到 repo ⇒ 条目被跳过，仍 generated=0（**绝不拼空 repo 的 URL**）
///   ③ 入队成功后同一映射 ⇒ generated=1，curl 必须是 `-X PUT` + `/issues/{n}` + `state:closed`
///      且 token 只能是 `${FIST_GITHUB_TOKEN}` 占位符（绝不内联真实密钥）
///   ④ 非法 project_dir ⇒ Err 点名（不许把「路径写错」读成「没有可关的 issue」）
test "lane-b#8 github_issue_close 前置面：空映射/无 repo 不生成 curl，合法映射生成 PUT 占位 curl" {
  let dir = lb_queue_dir("lane_b_close")
  let empty : Map[String, Int32] = Map([])
  // ① 空映射 ⇒ 一条 curl 都不生成
  let j0 = match @server.github_build_close_plan(dir, empty) {
    Ok(j) => j
    Err(e) => abort("close plan（空映射）不该 Err： " + e)
  }
  assert_eq(
    lb_int(j0, "generated"),
    0,
    msg="空映射应生成 0 条 curl： " + j0.stringify(),
  )
  assert_eq(lb_arr_len(j0, "plan"), 0, msg="空映射 plan 必须为空数组")
  // ② 队列无此 bug ⇒ 无 repo ⇒ 跳过（generated 仍 0）
  let nums : Map[String, Int32] = Map([("LB-CLOSE-1", 7)])
  let j1 = match @server.github_build_close_plan(dir, nums) {
    Ok(j) => j
    Err(e) => abort("close plan（无 repo）不该 Err： " + e)
  }
  assert_eq(
    lb_int(j1, "generated"),
    0,
    msg="队列里没有该 bug 时应跳过而不是拼空 repo 的 URL： " +
      j1.stringify(),
  )
  // ③ 入队（repo=owner/repo, 未发）后，映射能生成一条合法 PUT
  let labels : Array[String] = ["bug"]
  match
    @server.github_queue_append(
      dir, "LB-CLOSE-1", "close 面待关", "", "high", "2026-10-28T04:00:00Z", "owner/repo",
      labels,
    ) {
    Ok(_) => ()
    Err(e) => abort("入队失败（队列 IO 坏了）： " + e)
  }
  let j2 = match @server.github_build_close_plan(dir, nums) {
    Ok(j) => j
    Err(e) => abort("close plan（合法）不该 Err： " + e)
  }
  assert_eq(
    lb_int(j2, "generated"),
    1,
    msg="应生成 1 条 close curl： " + j2.stringify(),
  )
  let (bug_id, repo, num, curl) = lb2_plan_first(j2)
  assert_eq(
    bug_id,
    "LB-CLOSE-1",
    msg="plan 必须带回 bug_id 以便回执对账",
  )
  assert_eq(
    repo,
    "owner/repo",
    msg="repo 必须来自队列条目，实为: " + repo,
  )
  assert_eq(
    num,
    7,
    msg="调用方给的 issue_number 应被采用（队列无 issue_number）",
  )
  assert_true(
    curl.contains("-X PUT") &&
    curl.contains("/issues/7") &&
    curl.contains("closed"),
    msg="close curl 必须是 PUT /issues/7 且 body 带 closed，实为: " +
      curl,
  )
  assert_true(
    curl.contains("FIST_GITHUB_TOKEN"),
    msg="token 必须是环境变量占位符，实为: " + curl,
  )
  assert_false(
    curl.contains("ghp_"),
    msg="curl 里绝不能内联真实 token（ghp_ 前缀）： " + curl,
  )
  // ④ 非法 project_dir
  match @server.github_build_close_plan("", nums) {
    Err(m) =>
      assert_true(
        m.contains("非法 project_dir"),
        msg="拒绝理由应点名非法 project_dir，实为: " + m,
      )
    Ok(j) =>
      abort("空 project_dir 应被拒绝，却返回了 " + j.stringify())
  }
}

// ---------------------------------------------------------------------------
// 2) github_issue_comment —— 「未 flush 必拒」+ 空参拒绝 + flush 后 POST 形态
// ---------------------------------------------------------------------------

///|
/// 【B2-CM】`github_issue_comment` 背后的 `github_build_comment_plan` 全前置分支。
///
/// 这条工具最容易误用的地方是「入队了就当已上报」——`github_issue_comment` 要求
/// **该 bug 已 flush 成功（队列里 github_issue_number 非空）**，否则必须拒：
///   ① 队列里压根没有该 bug ⇒ Err 含「未同步过」「先 flush 再 comment」
///   ② 已入队但未 mark_sent（issue_number 为 null）⇒ **同样拒**（入队 ≠ 已上报，两栏不许混读）
///   ③ bug_id / comment_body 为空 ⇒ Err 逐一指名（不许拼一条空评论的 curl）
///   ④ mark_sent(issue=42) 之后 ⇒ Ok：issue_number=42、POST /issues/42/comments、token 仅占位
test "lane-b#9 github_issue_comment 未 flush 必拒 + 空参拒绝 + flush 后生成 POST 占位 curl" {
  let dir = lb_queue_dir("lane_b_comment")
  // ① 队列里没有这个 bug
  match @server.github_build_comment_plan(dir, "LB-CMT-1", "评论正文") {
    Err(m) => {
      assert_true(
        m.contains("未同步过"),
        msg="未 flush 的 bug 应被拒并说明未同步过，实为: " + m,
      )
      assert_true(
        m.contains("先 flush 再 comment"),
        msg="拒绝文案应指路「先 flush 再 comment」，实为: " + m,
      )
    }
    Ok(j) =>
      abort(
        "队列里没有该 bug 却生成了 comment 计划: " + j.stringify(),
      )
  }
  // ② 入队但未 mark_sent ⇒ 仍然拒（issue_number 空）
  let labels : Array[String] = ["bug"]
  match
    @server.github_queue_append(
      dir, "LB-CMT-1", "评论面待发", "", "medium", "2026-10-28T04:10:00Z", "owner/repo",
      labels,
    ) {
    Ok(_) => ()
    Err(e) => abort("入队失败（队列 IO 坏了）： " + e)
  }
  match @server.github_build_comment_plan(dir, "LB-CMT-1", "评论正文") {
    Err(m) =>
      assert_true(
        m.contains("未同步过"),
        msg="入队但未 flush 也必须拒（入队 ≠ 已上报），实为: " +
          m,
      )
    Ok(j) => abort("未 flush 却生成了 comment 计划: " + j.stringify())
  }
  // ③ 空参拒绝
  match @server.github_build_comment_plan(dir, "", "评论正文") {
    Err(m) =>
      assert_true(
        m.contains("bug_id 不能为空"),
        msg="空 bug_id 应被点名拒绝，实为: " + m,
      )
    Ok(_) => abort("空 bug_id 应被拒绝")
  }
  match @server.github_build_comment_plan(dir, "LB-CMT-1", "") {
    Err(m) =>
      assert_true(
        m.contains("comment_body 不能为空"),
        msg="空 comment_body 应被点名拒绝，实为: " + m,
      )
    Ok(_) => abort("空 comment_body 应被拒绝")
  }
  // ④ mark_sent 之后 ⇒ 生成 POST curl
  let ids : Array[String] = ["LB-CMT-1"]
  let nums : Map[String, Int32] = Map([("LB-CMT-1", 42)])
  match
    @server.github_queue_mark_sent(
      dir,
      ids,
      nums,
      sent_at="2026-10-28T04:20:00Z",
    ) {
    Ok(_) => ()
    Err(e) => abort("mark_sent 失败（回写队列坏了）： " + e)
  }
  let j = match
    @server.github_build_comment_plan(dir, "LB-CMT-1", "lane-b 评论正文") {
    Ok(j) => j
    Err(e) =>
      abort(
        "已 flush 的 bug 应能生成 comment 计划，实为 Err： " + e,
      )
  }
  assert_eq(
    lb_int(j, "issue_number"),
    42,
    msg="issue_number 必须取队列里 mark_sent 回写的 42： " +
      j.stringify(),
  )
  let curl = lb_str(j, "curl_command")
  assert_true(
    curl.contains("-X POST") && curl.contains("/issues/42/comments"),
    msg="comment curl 必须是 POST /issues/42/comments，实为: " + curl,
  )
  assert_true(
    curl.contains("FIST_GITHUB_TOKEN"),
    msg="token 必须是占位符，实为: " + curl,
  )
  assert_false(
    curl.contains("ghp_"),
    msg="curl 里绝不能内联真实 token： " + curl,
  )
}

// ---------------------------------------------------------------------------
// 3) github_issue_close / github_issue_comment 的 force 硬门（源码面接线锁）
// ---------------------------------------------------------------------------

///|
/// 【B2-FG · 接线锁】两个 issue 工具的 `force` 硬门与控制流仍在（**显式标注的源码面断言**）。
///
/// 为什么必须是源码面：`force` 门写在 `run_server` 的 handler 闭包里，测试进程拿不到
/// `MCPServer` 实例（`run_server()` 会进入 stdio 分发循环），所以「缺 force 必拒」这条
/// **行为**断言在 .mbt 里做不出来。这里退一步锁三件可核对的实物：
///   ① 两条**逐字**拒绝文案各出现 1 次（工具被删/文案被改都会红）
///   ② `if !force {` 早退至少 2 处（close + comment；flush_execute 也有，故用 ≥2）
///   ③ handler 仍把活转给 build_close_plan / build_comment_plan（接线没断）
/// 真正的 force 行为证据走端到端实调（`fist.py call github_issue_close` 不带 force ⇒ Err），
/// 那条读数在交付报告里，不在本文件——**不假装这里测到了行为**。
test "lane-b#10 github_issue_close/comment 的 force 硬门与 plan 接线仍在（源码面）" {
  let src = lb2_server_src()
  assert_eq(
    lb2_count(src, "\"github_issue_close 需要显式 force=true 才执行\""),
    1,
    msg="github_issue_close 的 force 拒绝文案应逐字存在且唯一",
  )
  assert_eq(
    lb2_count(src, "\"github_issue_comment 需要显式 force=true 才执行\""),
    1,
    msg="github_issue_comment 的 force 拒绝文案应逐字存在且唯一",
  )
  let force_early_returns = lb2_count(src, "if !force {")
  assert_true(
    force_early_returns >= 2,
    msg="至少 close 与 comment 两处应有 if !force 早退（实为 \{force_early_returns} 处）",
  )
  assert_true(
    src.contains("\"github_issue_close\""),
    msg="server.mbt 里找不到 github_issue_close 的注册名",
  )
  assert_true(
    src.contains("github_build_close_plan(project_dir, issue_numbers)"),
    msg="github_issue_close 不再转交 github_build_close_plan(project_dir, issue_numbers)",
  )
  assert_true(
    src.contains("\"github_issue_comment\""),
    msg="server.mbt 里找不到 github_issue_comment 的注册名",
  )
  assert_true(
    src.contains("github_build_comment_plan("),
    msg="github_issue_comment 不再转交 github_build_comment_plan",
  )
}

// ---------------------------------------------------------------------------
// 4) assistant_resign —— 内存引擎状态机
// ---------------------------------------------------------------------------

///|
/// 【B2-AR】`assistant_resign` 背后的 `engine.assistant_set_status(agent, "resigned")`。
///
/// shell 只有一句转发 + 回执 `{agent, resigned}`，所以状态面必须在引擎层钉死：
///   ① 未注册的 agent ⇒ **false**（退位不许凭空造一条登记行）
///   ② 注册在任主助理 ⇒ `assistant_active_primary()` 能读到
///   ③ resign ⇒ true、主助理位消失，但**登记行仍在且 status 逐字 = resigned**
///      （退位 ≠ 注销；回执/审计还靠这行）
///   ④ 重复 resign ⇒ 仍 true 且行数不变（幂等，不重复建行、不炸）
test "lane-b#11 assistant_resign 状态机：未注册拒 → 在任退位 → 行保留 → 重复幂等" {
  let e = @engine.FistEngine::new()
  // ① 未注册 ⇒ false
  assert_false(
    e.assistant_set_status("asst-ghost", "resigned"),
    msg="未注册的 agent 退位必须返回 false（不许凭空造登记行）",
  )
  assert_eq(
    e.assistant_list().length(),
    0,
    msg="被拒的退位不得留下任何登记行",
  )
  // ② 注册在任主助理
  e.assistant_upsert(
    @store.AssistantReg::new(
      agent="asst-b",
      mode="all",
      is_primary=true,
      registered_at="2026-10-28T00:00:00Z",
      heartbeat_at="2026-10-28T00:00:00Z",
      status="active",
    ),
  )
  assert_eq(e.assistant_list().length(), 1, msg="注册后应有 1 条登记")
  assert_true(
    e.assistant_active_primary() is Some(_),
    msg="active 主助理应能被读到",
  )
  // ③ 退位：回执 true，主位消失，但行还在且 status=resigned
  assert_true(
    e.assistant_set_status("asst-b", "resigned"),
    msg="已注册 agent 退位应返回 true",
  )
  assert_true(
    e.assistant_active_primary() is None,
    msg="退位后不该再有 active 主助理",
  )
  let list1 = e.assistant_list()
  assert_eq(list1.length(), 1, msg="退位不删行（退位 ≠ 注销）")
  match list1.get(0) {
    Some(r) =>
      assert_eq(
        lb_str(r.to_json(), "status"),
        "resigned",
        msg="登记行 status 必须逐字变成 resigned",
      )
    None => abort("assistant_list 首项缺失")
  }
  // ④ 重复退位 ⇒ 幂等
  assert_true(
    e.assistant_set_status("asst-b", "resigned"),
    msg="重复退位应仍返回 true（行存在 → 改状态成功）",
  )
  assert_eq(e.assistant_list().length(), 1, msg="重复退位不得新增行")
}

// ---------------------------------------------------------------------------
// 5) lock_status —— 内存引擎回读一致性
// ---------------------------------------------------------------------------

///|
/// 【B2-LS】`lock_status` 回读的数据面：未锁 → active → released → 过期 sweep。
///
/// shell 的 `locked` 字段是 **`status == "active"`**，不是「行存在」——这是本格的核心断言：
/// 释放后行仍在（status=released），若谁把 `locked` 写成 `locks_get is Some`，
/// **每一次释放过的锁都会被读成「还锁着」**。
///   ① 从未加锁 ⇒ `locks_get` 为 None（shell 走 locked=false 分支）
///   ② acquire ⇒ 行 status=active（⇒ locked=true），且 to_json 带回 scope/agent 供回执渲染
///   ③ release ⇒ 行仍在但 status=released（⇒ locked=false），语义陷阱在此
///   ④ 过期锁 ⇒ `locks_sweep` 清掉 1 条、状态转 expired、违例 +1 且 reason=lock_expired
test "lane-b#12 lock_status 回读：未锁→active→released(行在但非 active)→过期 sweep 记违例" {
  let e = @engine.FistEngine::new()
  let scope = "lane-b/lock.txt"
  // ① 从未加锁
  assert_true(
    e.locks_get(scope) is None,
    msg="从未加锁的 scope 应返回 None（shell 走 locked=false）",
  )
  // ② 加锁 ⇒ status=active
  let lock = @store.FileLock::new(
    lock_id="lk-b1",
    batch_id="b",
    scope~,
    agent="lane-b-io",
    status="active",
    ts="2026-10-28T00:00:00Z",
    ttl_until="2099-01-01T00:00:00Z",
    meta="",
  )
  let _ = e.locks_try_acquire(lock)
  match e.locks_get(scope) {
    None => abort("acquire 之后 locks_get 必须能读到锁")
    Some(l) => {
      assert_eq(
        l.status_of(),
        "active",
        msg="刚拿到的锁 status 必须是 active",
      )
      assert_eq(
        lb_str(l.to_json(), "agent"),
        "lane-b-io",
        msg="回执的 agent 必须逐字等于持有者",
      )
    }
  }
  assert_true(
    e.locks_list().length() >= 1,
    msg="无 scope 分支（locks_list）应能看到这把锁",
  )
  // ③ 释放 ⇒ 行仍在但 status=released ⇒ locked(=status=="active") 必须为 false
  assert_true(
    e.locks_release(scope, "lane-b-io"),
    msg="持有者释放应返回 true",
  )
  match e.locks_get(scope) {
    None =>
      abort(
        "释放后行仍在（status=released）——lock_status 靠 status 判 locked，不是靠行是否存在",
      )
    Some(l) =>
      assert_false(
        l.status_of() == "active",
        msg="释放后 status 不该还是 active（否则 lock_status 会报 locked=true）",
      )
  }
  match e.locks_get(scope) {
    Some(l) =>
      assert_eq(
        l.status_of(),
        "released",
        msg="释放后 status 应逐字为 released",
      )
    None => abort("释放后 locks_get 应返回 Some(released)")
  }
  // ④ 过期：ttl 早于 sweep 的 now ⇒ 清 1 条 + 违例落案
  let scope2 = "lane-b/lock2.txt"
  let expired_lock = @store.FileLock::new(
    lock_id="lk-b2",
    batch_id="b",
    scope=scope2,
    agent="lane-b-io",
    status="active",
    ts="2026-10-26T00:00:00Z",
    ttl_until="2026-10-27T00:00:00Z",
    meta="",
  )
  let _ = e.locks_try_acquire(expired_lock)
  let viols_before = e.lock_violations_list().length()
  let swept = e.locks_sweep("2026-10-28T00:00:00Z")
  assert_eq(
    swept,
    1,
    msg="只有那把过期的 active 锁该被清（实为 \{swept} 条）",
  )
  match e.locks_get(scope2) {
    None => abort("sweep 不应删行，只该把 status 改成 expired")
    Some(l) =>
      assert_eq(
        l.status_of(),
        "expired",
        msg="过期锁 status 应变为 expired",
      )
  }
  let viols = e.lock_violations_list()
  assert_eq(
    viols.length(),
    viols_before + 1,
    msg="清理过期锁必须落一条违例（审计面），实为 +\{viols.length() - viols_before}",
  )
  match viols.get(viols.length() - 1) {
    Some(v) =>
      assert_eq(
        lb_str(v.to_json(), "reason"),
        "lock_expired",
        msg="违例 reason 应逐字为 lock_expired",
      )
    None => abort("违例列表末项缺失")
  }
}

// ---------------------------------------------------------------------------
// 6) assistant_resign / lock_status 的接线锁（判例-29：机制格 ≠ 实现路径格）
// ---------------------------------------------------------------------------

///|
/// 【B2-W2 · 接线锁】`assistant_resign` / `lock_status` 的**工具名 → 引擎方法**这根线还在。
///
/// 为什么需要单独一格：B2-AR / B2-LS 证明的是**引擎方法**的状态机对，但
/// 「工具名是否仍指向这些方法」是另一件事——工具被改名、注册被删、handler 改接别的函数时，
/// 那两个行为格**照样全绿**，而调用面已经坏了。
/// 本格钉死四处**唯一代码行**（各 1 次）+ 一处出现 ≥1 次：
///   · `engine.assistant_set_status(agent, "resigned")` —— resign 的唯一转发点
///   · `let swept = engine.locks_sweep(now)`           —— 回执 `swept` 字段的来源
///   · `engine.locks_get(scope)`                       —— 回执 `locked`/`lock` 字段的来源
///   · 两个注册名字面仍在（≥1，容忍文档追加提及）
test "lane-b#13 assistant_resign/lock_status 工具名到引擎方法的接线仍在（源码面）" {
  let src = lb2_server_src()
  assert_true(
    lb2_count(src, "\"assistant_resign\"") >= 1,
    msg="server.mbt 里找不到 assistant_resign 的注册名（工具被改名/删注册）",
  )
  assert_true(
    lb2_count(src, "\"lock_status\"") >= 1,
    msg="server.mbt 里找不到 lock_status 的注册名（工具被改名/删注册）",
  )
  assert_eq(
    lb2_count(src, "engine.assistant_set_status(agent, \"resigned\")"),
    1,
    msg="assistant_resign 不再转发 engine.assistant_set_status(agent, \"resigned\")",
  )
  assert_eq(
    lb2_count(src, "let swept = engine.locks_sweep(now)"),
    1,
    msg="lock_status 不再先 locks_sweep(now)（回执 swept 字段会失源）",
  )
  assert_true(
    lb2_count(src, "engine.locks_get(scope)") >= 1,
    msg="lock_status 不再用 engine.locks_get(scope) 读单 scope（回执 locked/lock 会失源）",
  )
}
