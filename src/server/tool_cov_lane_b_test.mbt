// tool_cov_lane_b_test.mbt —— Lane B（env / IO 族）工具外壳覆盖锁 · 第一批 4 格。
//
// 覆盖工具（`check_tool_coverage.py` 的「外壳零覆盖」清单点名项）：
//   · github_env_check   —— env 四元组形状 + ready 合取律（零网络、零密钥回显）
//   · gitcode_env_check  —— 同上，GitCode 面（project_id 维度）
//   · github_queue_status—— 真实 JSONL 队列 IO：空队列 / 入队 / 标记已发三态
//   · reserve_release    —— 内存引擎真状态变化：预订 → 越权拒绝 → 释放 → 幂等
//
// 三条施工口径（对齐判例-29/30，避免「自指假绿」）：
//   ① **不写网络、不读真实密钥**：env 类工具只读进程环境变量并返回「配没配」的布尔位，
//      本文件断言的是**形状与合取律**，任何一条都不依赖真实 token 的值；
//   ② **断言的是行为返回值**，不是「源码里有某个字符串就算过」；唯一的源码面断言
//      （v4 格）单独存在且明确标注用途：它锁的是「工具名 → 实现函数」这根线，
//      而 `reserve_release` 的 shell 只有一个转发（`engine.rsv_release`），
//      行为断言已在 v1~v3 覆盖，源码面断言不替代它们。
//   ③ **未配置分支诚实标注**：github/gitcode 的真实 IO 成功路径（真发 POST/PUT）本文件
//      **不测**——那需要真实 token 与外部网络，违反本任务边界；未配置态的字段形状才是
//      本轮验收面。环境已配置时，对应的 hint 断言自动跳过（不假装环境一定是空的）。

// ---------------------------------------------------------------------------
// 测试辅助（lb_ 前缀，避免与同包其它测试文件的包级 helper 撞名）
// ---------------------------------------------------------------------------

///|
/// 取 Json 对象的布尔字段（缺失 / 类型不符 → None，不静默当 false）。
fn lb_jbool(j : Json, key : String) -> Bool? {
  match j {
    Json::Object(m) =>
      match m.get(key) {
        Some(Json::True) => Some(true)
        Some(Json::False) => Some(false)
        _ => None
      }
    _ => None
  }
}

///|
/// 取 Json 对象的字符串字段。
fn lb_jstr(j : Json, key : String) -> String? {
  match j {
    Json::Object(m) =>
      match m.get(key) {
        Some(Json::String(s)) => Some(s)
        _ => None
      }
    _ => None
  }
}

///|
/// 取 Json 对象的数字字段。
fn lb_jnum(j : Json, key : String) -> Double? {
  match j {
    Json::Object(m) =>
      match m.get(key) {
        Some(Json::Number(n, ..)) => Some(n)
        _ => None
      }
    _ => None
  }
}

///|
/// 取 Json 对象的数组字段。
fn lb_jarr(j : Json, key : String) -> Array[Json]? {
  match j {
    Json::Object(m) =>
      match m.get(key) {
        Some(Json::Array(a)) => Some(a)
        _ => None
      }
    _ => None
  }
}

///|
/// 键是否在对象里（用来断言「某个字段不该出现」，如 token 值）。
fn lb_has_key(j : Json, key : String) -> Bool {
  match j {
    Json::Object(m) =>
      match m.get(key) {
        Some(_) => true
        None => false
      }
    _ => false
  }
}

///|
/// 必取布尔（缺失即红，并把整个回执打进失败信息，便于定位）。
fn lb_bool(j : Json, key : String) -> Bool {
  match lb_jbool(j, key) {
    Some(b) => b
    None => abort("字段 '" + key + "' 缺失或非布尔： " + j.stringify())
  }
}

///|
/// 必取字符串。
fn lb_str(j : Json, key : String) -> String {
  match lb_jstr(j, key) {
    Some(s) => s
    None =>
      abort("字段 '" + key + "' 缺失或非字符串： " + j.stringify())
  }
}

///|
/// 必取整数字段（Json number 是 Double，取整后比较，避免 Double 相等比较）。
fn lb_int(j : Json, key : String) -> Int32 {
  match lb_jnum(j, key) {
    Some(n) => n.to_int()
    None => abort("字段 '" + key + "' 缺失或非数字： " + j.stringify())
  }
}

///|
/// 必取数组长度。
fn lb_arr_len(j : Json, key : String) -> Int32 {
  match lb_jarr(j, key) {
    Some(a) => a.length()
    None => abort("字段 '" + key + "' 缺失或非数组： " + j.stringify())
  }
}

///|
/// hints 数组拼成一段文本（断言「哪个维度没配就提示哪个变量名」）。
fn lb_hints_text(j : Json) -> String {
  let arr = match lb_jarr(j, "hints") {
    Some(a) => a
    None => abort("字段 'hints' 缺失或非数组： " + j.stringify())
  }
  let mut out = ""
  for it in arr {
    match it {
      Json::String(s) => out = out + s + " | "
      _ => abort("hints 元素应为字符串，实为: " + it.stringify())
    }
  }
  out
}

///|
/// 取 by_severity 里某个严重度的 pending 计数（缺失按 0 计，方便断言「该桶消失了」）。
fn lb_sev(j : Json, sev : String) -> Int32 {
  match j {
    Json::Object(m) =>
      match m.get("by_severity") {
        Some(Json::Object(inner)) =>
          match inner.get(sev) {
            Some(Json::Number(n, ..)) => n.to_int()
            _ => 0
          }
        _ =>
          abort("字段 'by_severity' 缺失或非对象： " + j.stringify())
      }
    _ => abort("回执不是对象： " + j.stringify())
  }
}

///|
/// by_severity 的桶数量（空队列时应为 0）。
fn lb_sev_buckets(j : Json) -> Int32 {
  match j {
    Json::Object(m) =>
      match m.get("by_severity") {
        Some(Json::Object(inner)) => inner.length()
        _ =>
          abort("字段 'by_severity' 缺失或非对象： " + j.stringify())
      }
    _ => abort("回执不是对象： " + j.stringify())
  }
}

///|
/// 取 pending_list 里第 0 条的 bug_id（空表即红——调用方先断言长度）。
fn lb_first_pending_bug_id(j : Json) -> String {
  let arr = match lb_jarr(j, "pending_list") {
    Some(a) => a
    None =>
      abort("字段 'pending_list' 缺失或非数组： " + j.stringify())
  }
  match arr.get(0) {
    Some(Json::Object(first)) =>
      match first.get("bug_id") {
        Some(Json::String(s)) => s
        _ => abort("pending_list[0].bug_id 非字符串： " + j.stringify())
      }
    _ => abort("pending_list 为空或首项非对象： " + j.stringify())
  }
}

///|
/// 造一个干净的队列用例目录：建目录 + 清掉上次残留的队列文件（可重复运行）。
fn lb_queue_dir(name : String) -> String {
  @fs.create_dir("temp") catch {
    _ => ()
  }
  let d = "temp/" + name
  @fs.create_dir(d) catch {
    _ => ()
  }
  @fs.remove_file(d + "/memory/bugs_pending_github.json") catch {
    _ => ()
  }
  d
}

// ---------------------------------------------------------------------------
// 1) github_env_check —— env 四元组形状 + ready 合取律
// ---------------------------------------------------------------------------

///|
/// 【B1-GH】`github_env_check` 的返回形状与 `ready` 合取律（零网络、零密钥回显）。
///
/// 断言面（4 条）：
///   ① `repo_set` 与 `repo` 同源 —— 两个字段不许各算一套（写反了就是调用方读到矛盾的配置态）
///   ② `ready == enabled && repo_set && token_present` —— 改坏任一臂（如漏掉 repo_set）本格即红
///   ③ 每个「没配」的维度都有一条指向对应环境变量的 hint —— 未配置分支的可操作性；
///      环境已配时该维度自动跳过（不假设测试进程环境一定是空的）
///   ④ 绝不回显密钥本体 —— 只有 `token_present` 布尔位，没有 `token` 值字段
test "lane-b#1 github_env_check 四元组形状与 ready 合取律（不碰网络）" {
  let j = match @server.github_env_check() {
    Ok(j) => j
    Err(e) =>
      abort("github_env_check 不该返回 Err（纯 env 读取）： " + e)
  }
  let enabled = lb_bool(j, "enabled")
  let repo = lb_str(j, "repo")
  let repo_set = lb_bool(j, "repo_set")
  let token_present = lb_bool(j, "token_present")
  let ready = lb_bool(j, "ready")
  // ① repo_set 必须就是「repo 非空」，不是另一个独立开关
  assert_eq(
    repo_set,
    !repo.is_empty(),
    msg="repo_set 必须与 repo 同源，实为 repo_set=\{repo_set} repo='\{repo}'",
  )
  // ② ready 恰为三项合取（不是「enabled 就算 ready」，也不漏 token）
  assert_eq(
    ready,
    enabled && repo_set && token_present,
    msg="ready 必须是 enabled&&repo_set&&token_present，实为 enabled=\{enabled} repo_set=\{repo_set} token_present=\{token_present} ready=\{ready}",
  )
  // ③ 未配置维度 → 对应 hint 指路（名对名，不许张冠李戴）
  let hints = lb_hints_text(j)
  if !enabled {
    assert_true(
      hints.contains("FIST_GITHUB_ENABLED"),
      msg="enabled=false 时 hints 应点名 FIST_GITHUB_ENABLED，实为: \{hints}",
    )
  }
  if !repo_set {
    assert_true(
      hints.contains("FIST_GITHUB_REPO"),
      msg="repo 为空时 hints 应点名 FIST_GITHUB_REPO，实为: \{hints}",
    )
  }
  if !token_present {
    assert_true(
      hints.contains("FIST_GITHUB_TOKEN"),
      msg="token_present=false 时 hints 应点名 FIST_GITHUB_TOKEN，实为: \{hints}",
    )
  }
  // ④ 不回显密钥：只有布尔位，没有 token 值字段
  assert_true(lb_has_key(j, "token_present"))
  assert_false(
    lb_has_key(j, "token"),
    msg="回执不得含 token 值字段（只允许 token_present 布尔位）: \{j.stringify()}",
  )
}

// ---------------------------------------------------------------------------
// 2) gitcode_env_check —— 同一套形状，维度换成 project_id
// ---------------------------------------------------------------------------

///|
/// 【B1-GC】`gitcode_env_check` 的返回形状与 `ready` 合取律（零网络、零密钥回显）。
///
/// 断言面（4 条，与 github 面同构但**逐字段独立**：GitCode 的维度是 project_id 而非 repo）：
///   ① `project_id_set == !project_id.is_empty()`
///   ② `ready == enabled && project_id_set && token_present`
///   ③ 未配置维度各有对应 hint（FIST_GITCODE_ENABLED / _PROJECT_ID / _TOKEN）
///   ④ 无 token 值字段
test "lane-b#2 gitcode_env_check 四元组形状与 ready 合取律（不碰网络）" {
  let j = match @server.gitcode_env_check() {
    Ok(j) => j
    Err(e) =>
      abort("gitcode_env_check 不该返回 Err（纯 env 读取）： " + e)
  }
  let enabled = lb_bool(j, "enabled")
  let project_id = lb_str(j, "project_id")
  let project_id_set = lb_bool(j, "project_id_set")
  let token_present = lb_bool(j, "token_present")
  let ready = lb_bool(j, "ready")
  assert_eq(
    project_id_set,
    !project_id.is_empty(),
    msg="project_id_set 必须与 project_id 同源，实为 project_id_set=\{project_id_set} project_id='\{project_id}'",
  )
  assert_eq(
    ready,
    enabled && project_id_set && token_present,
    msg="ready 必须是 enabled&&project_id_set&&token_present，实为 enabled=\{enabled} project_id_set=\{project_id_set} token_present=\{token_present} ready=\{ready}",
  )
  let hints = lb_hints_text(j)
  if !enabled {
    assert_true(
      hints.contains("FIST_GITCODE_ENABLED"),
      msg="enabled=false 时 hints 应点名 FIST_GITCODE_ENABLED，实为: \{hints}",
    )
  }
  if !project_id_set {
    assert_true(
      hints.contains("FIST_GITCODE_PROJECT_ID"),
      msg="project_id 为空时 hints 应点名 FIST_GITCODE_PROJECT_ID，实为: \{hints}",
    )
  }
  if !token_present {
    assert_true(
      hints.contains("FIST_GITCODE_TOKEN"),
      msg="token_present=false 时 hints 应点名 FIST_GITCODE_TOKEN，实为: \{hints}",
    )
  }
  assert_true(lb_has_key(j, "token_present"))
  assert_false(
    lb_has_key(j, "token"),
    msg="回执不得含 token 值字段（只允许 token_present 布尔位）: \{j.stringify()}",
  )
}

// ---------------------------------------------------------------------------
// 3) github_queue_status —— 真实 JSONL 队列 IO 三态
// ---------------------------------------------------------------------------

///|
/// 【B1-Q0】空队列的字段形状（真实 IO：读一个不存在的队列文件 → 全零，而不是 Err）。
///
/// 边界语义：队列文件不存在 ≠ 读失败。若实现把「文件缺失」当 Err，
/// 首次上报 bug 前的每一次状态查询都会红。
test "lane-b#3 github_queue_status 空队列：全零 + 空 oldest + path 指向队列文件" {
  let dir = lb_queue_dir("lane_b_gq_empty")
  let j = match @server.github_queue_status(dir) {
    Ok(j) => j
    Err(e) =>
      abort(
        "空队列不该返回 Err（文件缺失应视为空队列）： " + e,
      )
  }
  assert_eq(
    lb_int(j, "total"),
    0,
    msg="空队列 total 应为 0： \{j.stringify()}",
  )
  assert_eq(
    lb_int(j, "pending"),
    0,
    msg="空队列 pending 应为 0： \{j.stringify()}",
  )
  assert_eq(
    lb_int(j, "sent"),
    0,
    msg="空队列 sent 应为 0： \{j.stringify()}",
  )
  assert_eq(
    lb_str(j, "oldest_pending_ts"),
    "",
    msg="空队列 oldest_pending_ts 应为空串（无待发条目就没有最老时间）",
  )
  assert_eq(
    lb_arr_len(j, "pending_list"),
    0,
    msg="空队列 pending_list 应为空数组",
  )
  assert_eq(lb_sev_buckets(j), 0, msg="空队列 by_severity 应无任何桶")
  let eq_path = lb_str(j, "path")
  assert_true(
    eq_path.has_suffix("bugs_pending_github.json"),
    msg="path 应指向 JSONL 队列文件，实为: " + eq_path,
  )
}

///|
/// 【B1-Q1】真实入队 → 统计 → 标记已发 → 口径变化（全程只碰本地 JSONL，不碰网络）。
///
/// 断言面：
///   ① 入队两条后 total/pending/sent = 2/2/0，oldest 取**更早**那条的 ts（不是最后写入的）
///   ② by_severity 逐桶计数（critical=1 / high=1）
///   ③ mark_sent 后 total 不变、pending 1 / sent 1，且 pending_list 里只剩未发的那条
///   ④ mark_sent 掉的严重度桶从 by_severity 消失（统计不是「加上去就不减」）
test "lane-b#4 github_queue_status 真实入队→统计→标记已发→口径变化" {
  let dir = lb_queue_dir("lane_b_gq_flow")
  let labels : Array[String] = ["bug"]
  // ① 真实写队列（github_queue_append 走 write_gate + 真实文件写）
  match
    @server.github_queue_append(
      dir, "LB-1", "看板渲染越界", "detail-1", "critical", "2026-10-28T01:00:00Z",
      "owner/repo", labels,
    ) {
    Ok(_) => ()
    Err(e) => abort("入队 LB-1 失败（队列 IO 面坏了）： " + e)
  }
  match
    @server.github_queue_append(
      dir, "LB-2", "会话态未落盘", "detail-2", "high", "2026-10-28T02:00:00Z",
      "owner/repo", labels,
    ) {
    Ok(_) => ()
    Err(e) => abort("入队 LB-2 失败（队列 IO 面坏了）： " + e)
  }
  let j1 = match @server.github_queue_status(dir) {
    Ok(j) => j
    Err(e) => abort("入队后查状态失败： " + e)
  }
  assert_eq(
    lb_int(j1, "total"),
    2,
    msg="两条入队后 total=2： \{j1.stringify()}",
  )
  assert_eq(
    lb_int(j1, "pending"),
    2,
    msg="未标记前 pending=2： \{j1.stringify()}",
  )
  assert_eq(
    lb_int(j1, "sent"),
    0,
    msg="未标记前 sent=0： \{j1.stringify()}",
  )
  // oldest 取更早那条（01:00 早于 02:00）——写反成「最后一次写入」本格即红
  let oldest1 = lb_str(j1, "oldest_pending_ts")
  assert_eq(
    oldest1,
    "2026-10-28T01:00:00Z",
    msg="oldest_pending_ts 应取最老待发条目（01:00），实为: " +
      oldest1,
  )
  assert_eq(
    lb_sev(j1, "critical"),
    1,
    msg="critical 桶应为 1： \{j1.stringify()}",
  )
  assert_eq(lb_sev(j1, "high"), 1, msg="high 桶应为 1： \{j1.stringify()}")
  assert_eq(lb_arr_len(j1, "pending_list"), 2, msg="pending_list 应有 2 条")
  // ② 标记 LB-1 已发（写 sent_at + github_issue_number），再查口径
  let ids : Array[String] = ["LB-1"]
  let nums : Map[String, Int32] = Map([("LB-1", 42)])
  match
    @server.github_queue_mark_sent(
      dir,
      ids,
      nums,
      sent_at="2026-10-28T03:00:00Z",
    ) {
    Ok(_) => ()
    Err(e) => abort("mark_sent 失败（回写队列 IO 面坏了）： " + e)
  }
  let j2 = match @server.github_queue_status(dir) {
    Ok(j) => j
    Err(e) => abort("标记后查状态失败： " + e)
  }
  assert_eq(
    lb_int(j2, "total"),
    2,
    msg="标记不改变 total（仍 2 条）： \{j2.stringify()}",
  )
  assert_eq(lb_int(j2, "sent"), 1, msg="标记后 sent=1： \{j2.stringify()}")
  assert_eq(
    lb_int(j2, "pending"),
    1,
    msg="标记后 pending=1： \{j2.stringify()}",
  )
  assert_eq(
    lb_first_pending_bug_id(j2),
    "LB-2",
    msg="已发的 LB-1 不该再出现在 pending_list",
  )
  assert_eq(
    lb_sev(j2, "critical"),
    0,
    msg="已发条目的严重度桶应从 by_severity 消失（统计要减）",
  )
  let oldest2 = lb_str(j2, "oldest_pending_ts")
  assert_eq(
    oldest2,
    "2026-10-28T02:00:00Z",
    msg="只剩 LB-2 时 oldest 应变 02:00，实为: " + oldest2,
  )
}

///|
/// 【B1-Q2 · 边界/异常】非法 `project_dir` 四种形态一律 Err 点名，且**不静默返回全零**。
///
/// 为什么这条值钱：path 型入参若被静默接受成「读不到 → total=0」，
/// 调用方会把「路径写错」读成「没有待同步 bug」（本仓 BUG-74 同族的两栏混读）。
test "lane-b#5 github_queue_status 边界：非法 project_dir 一律 Err 点名" {
  let bads : Array[String] = ["", "temp/../etc", "/abs/path", "C:/abs/path"]
  for bad in bads {
    match @server.github_queue_status(bad) {
      Err(m) =>
        assert_true(
          m.contains("非法 project_dir"),
          msg="拒绝理由应点名非法 project_dir，实为: \{m}",
        )
      Ok(j) => {
        let got = j.stringify()
        abort(
          "project_dir='\{bad}' 应被拒绝，却返回了 \{got}（静默当成空队列 = 调用方无法区分「路径写错」与「没有待同步」）",
        )
      }
    }
  }
}

// ---------------------------------------------------------------------------
// 4) reserve_release —— 内存引擎真状态变化
// ---------------------------------------------------------------------------

///|
/// 【B1-R1】`reserve_release` 背后的真实状态机：预订 → 越权拒绝 → 本人释放 → 幂等 false。
///
/// shell（`server.mbt` 的 `reserve_release` 工具）只有一个动作：
/// `engine.rsv_release(scope, agent)` → 回执 `{scope, released}`。
/// 本格用**同一个引擎方法**在内存后端上跑真实状态迁移，覆盖 5 个断言面：
///   ① 从未预订就释放 ⇒ false（不是「假装成功」）
///   ② 预订后读侧能读到持有者与 TTL（写入即真落库）
///   ③ 他人释放 ⇒ false **且预订仍在**（越权释放不得破坏互斥）
///   ④ 本人释放 ⇒ true **且读侧真没了**
///   ⑤ 再释放 ⇒ false（幂等；恒 true 的实现会被本格抓住）
test "lane-b#6 reserve_release 真状态：预订→越权拒→本人释放→幂等" {
  let e = @engine.FistEngine::new()
  let scope = "sc/lane-b-reserve"
  let me = "lane-b-io"
  // ① 未预订就释放 ⇒ false
  assert_false(
    e.rsv_release(scope, me),
    msg="从未预订的 scope 上 release 必须返回 false（回执不许假成功）",
  )
  // ② 预订（真状态写入）
  match
    e.rsv_set(
      scope~,
      agent=me,
      ttl_until="2099-01-01T00:00:00Z",
      created_at="2026-10-28T00:00:00Z",
    ) {
    Ok(_) => ()
    Err(m) => abort("预订失败（引擎预订面坏了）： " + m)
  }
  match e.rsv_get(scope) {
    None => abort("预订后 rsv_get 应返回 Some，实为 None")
    Some((holder, ttl, _created)) => {
      assert_eq(
        holder,
        me,
        msg="持有者应逐字等于写入值，实为: \{holder}",
      )
      assert_eq(
        ttl,
        "2099-01-01T00:00:00Z",
        msg="TTL 应逐字等于写入值，实为: \{ttl}",
      )
    }
  }
  // ③ 越权释放：false，且预订仍在（互斥不被破坏）
  assert_false(
    e.rsv_release(scope, "other-lane"),
    msg="非持有者 release 必须返回 false（谁都能删别人的预订就是没互斥）",
  )
  assert_true(
    e.rsv_get(scope) is Some(_),
    msg="越权释放后预订必须仍在",
  )
  // ④ 本人释放：true，且读侧真没了
  assert_true(e.rsv_release(scope, me), msg="持有者 release 应返回 true")
  assert_true(e.rsv_get(scope) is None, msg="释放后 rsv_get 应为 None")
  // ⑤ 再释放：false（幂等）
  assert_false(
    e.rsv_release(scope, me),
    msg="重复 release 必须返回 false（恒 true 的实现 = 回执不可信）",
  )
}

///|
/// 【B1-R2 · 接线锁】`reserve_release` 工具名 → 实现函数这根线还在。
///
/// 为什么单独一格（判例-29「机制格 ≠ 实现路径格」）：上面 B1-R1 证明的是
/// **引擎方法**的状态机对，但「MCP 工具名是否仍指向这个方法」是另一件事——
/// 工具被改名/删注册/接到别的函数上，B1-R1 全绿而调用面已经坏了。
/// 本格只锁两处字面：注册名 `"reserve_release"` 与 handler 内的转发调用。
test "lane-b#7 reserve_release 工具名到 engine.rsv_release 的接线仍在" {
  let src = @fs.read_file_to_string("src/server/server.mbt", encoding="utf8") catch {
    _ =>
      abort(
        "读不到 src/server/server.mbt（测试须在项目根跑）——本接线锁无法自证",
      )
  }
  assert_true(
    src.contains("\"reserve_release\""),
    msg="server.mbt 里找不到 reserve_release 的注册名（工具被改名/删注册）",
  )
  assert_true(
    src.contains("engine.rsv_release(scope, agent)"),
    msg="reserve_release 的 handler 不再转发到 engine.rsv_release(scope, agent)（接线断了）",
  )
}
