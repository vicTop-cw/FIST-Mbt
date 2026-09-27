/// github_gitcode_wbtest.mbt —— GitCode fallback 通道白盒测试
///
/// 覆盖 read / status / flush_plan / mark_sent / pending 五个纯计算函数。
/// 零网络、零 token——所有队列文件用 mem_write 手写 JSONL 构造，
/// 所有 curl 命令用字符串匹配断言关键头。
/// 与 github_sync 同队列路径（bugs_pending_github.json），
/// GitCode 条目带 gitcode_project_id 字段、GitHub 条目不带，互相隔离。

///|
/// 队列文件路径（与 github_gitcode.mbt 同 package，gq_path 可直接用）
fn gc_path(d : String) -> String {
  gq_path(d)
}

///|
/// 清场：重置 scratch 目录。
fn gc_reset(d : String) -> Unit {
  @fs.create_dir("temp") catch {
    _ => ()
  }
  @fs.create_dir(d) catch {
    _ => ()
  }
  mem_ensure_dir(mem_dir(d))
  let _ = mem_write(gc_path(d), "")
}

///|
/// 向队列追加一条 GitCode 条目（手写 JSON——不依赖 github_queue_append，
/// 因为后者不带 gitcode_project_id 字段）。
fn gc_enqueue(
  d : String,
  bug_id : String,
  summary : String,
  detail : String,
  severity : String,
  pid : String,
) -> Unit {
  let lines = match mem_read(gc_path(d)) {
    None => ""
    Some(s) => s
  }
  let nm : Map[String, Json] = Map([])
  nm.set("bug_id", Json::string(bug_id))
  nm.set("summary", Json::string(summary))
  nm.set("detail", Json::string(detail))
  nm.set("severity", Json::string(severity))
  nm.set("ts", Json::string("2026-09-27T00:00:00Z"))
  nm.set("gitcode_project_id", Json::string(pid))
  nm.set("sent_at", Json::null())
  nm.set("gitcode_issue_iid", Json::null())
  let entry_json = Json::object(nm)
  let _ = mem_write(gc_path(d), lines + entry_json.stringify() + "\n")
}

///|
/// 追加一条 GitHub 条目（对照：GitCode 函数应当忽略这类条目）。
fn gh_enqueue(
  d : String,
  bug_id : String,
  summary : String,
  repo : String,
) -> Unit {
  let lines = match mem_read(gc_path(d)) {
    None => ""
    Some(s) => s
  }
  let nm : Map[String, Json] = Map([])
  nm.set("bug_id", Json::string(bug_id))
  nm.set("summary", Json::string(summary))
  nm.set("detail", Json::string("GitHub-only detail"))
  nm.set("severity", Json::string("medium"))
  nm.set("ts", Json::string("2026-09-27T00:00:00Z"))
  nm.set("github_repo", Json::string(repo))
  nm.set("sent_at", Json::null())
  let entry_json = Json::object(nm)
  let _ = mem_write(gc_path(d), lines + entry_json.stringify() + "\n")
}

///|
/// Result[Json, String] 取正身：Err 一律 abort，不让"调用失败"降级成"结果为空"
fn gc_ok(r : Result[Json, String], what : String) -> Json {
  match r {
    Ok(j) => j
    Err(m) => abort(what + " 失败: " + m)
  }
}

///|
/// 安全取对象字段为字符串。
fn gc_str(j : Json, key : String) -> String {
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
/// 安全取对象字段为数字（转 Int）。
fn gc_int(j : Json, key : String) -> Int {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(Number(n, ..)) => n.to_int()
        _ => 0
      }
    _ => 0
  }
}

///|
/// 从完整 curl 命令里取出 `--data <值>` 的值，并反转 POSIX 单引号包装。
/// 找不到返回 Err —— 判据不许静默放过"根本没生成 --data"的形态。
/// 抄 github_sync_wbtest.mbt:41 的 extract_data_arg —— MoonBit String 没有 index_of，
/// 只能手动遍历字符数组。
fn gc_extract_data(cmd : String) -> Result[String, String] {
  let marker = "--data "
  let cs = cmd.to_array()
  let ms = marker.to_array()
  let mut at = -1
  let mut i = 0
  while at < 0 && i + ms.length() <= cs.length() {
    let mut ok = true
    for k = 0; k < ms.length(); k = k + 1 {
      if cs[i + k] != ms[k] {
        ok = false
      }
    }
    if ok {
      at = i + ms.length()
    }
    i = i + 1
  }
  if at < 0 {
    return Err("命令里没有 --data 段")
  }
  let rest = cmd.substring(start=at, end=cmd.length())
  let wrapped = rest.length() >= 2 &&
    rest.has_prefix("'") &&
    rest.has_suffix("'")
  if !wrapped {
    return Err("--data 值不是完整的单引号包装: " + rest)
  }
  // 去掉外层引号，再把 shell 的 '"'"' 还原成 '
  let inner = rest.substring(start=1, end=rest.length() - 1)
  let unwrapped = inner.replace(old="'\"'\"'", new="'")
  Ok(unwrapped)
}

// =====================================================================
// Test 1：gitcode_queue_read 空队列 → Ok(空数组)
// =====================================================================

///|
test "gc-01: queue_read 空队列返回空数组" {
  let d = "temp/gc_wbtest"
  gc_reset(d)
  let r = gc_ok(gitcode_queue_read(d), "queue_read")
  match r {
    Array(a) => assert_eq(a.length(), 0)
    _ => abort("queue_read 应返回数组")
  }
}

// =====================================================================
// Test 2：gitcode_queue_read 有数据 → Ok(有数组)
// =====================================================================

///|
test "gc-02: queue_read 能读到写入的 GitCode 条目" {
  let d = "temp/gc_wbtest"
  gc_reset(d)
  gc_enqueue(d, "GC-1", "标题", "详情", "high", "12345")
  gc_enqueue(d, "GC-2", "标题2", "详情2", "low", "12345")
  let r = gc_ok(gitcode_queue_read(d), "queue_read")
  match r {
    Array(a) => assert_eq(a.length(), 2)
    _ => abort("queue_read 应返回数组")
  }
}

// =====================================================================
// Test 3：gitcode_queue_status 空队列 → total=0, pending=0, sent=0
// =====================================================================

///|
test "gc-03: queue_status 空队列统计归零" {
  let d = "temp/gc_wbtest"
  gc_reset(d)
  let s = gc_ok(gitcode_queue_status(d, ""), "queue_status")
  assert_eq(gc_int(s, "total"), 0)
  assert_eq(gc_int(s, "pending"), 0)
  assert_eq(gc_int(s, "sent"), 0)
}

// =====================================================================
// Test 4：gitcode_queue_status 混合队列（GitHub + GitCode）→ 只统计 GitCode
// =====================================================================

///|
test "gc-04: queue_status 只统计 GitCode 条目，忽略 GitHub 条目" {
  let d = "temp/gc_wbtest"
  gc_reset(d)
  gc_enqueue(d, "GC-1", "GitCode bug", "detail", "high", "100")
  gc_enqueue(d, "GC-2", "GitCode bug 2", "detail", "low", "100")
  gc_enqueue(d, "GC-3", "GitCode bug 3", "detail", "medium", "200")
  gh_enqueue(d, "GH-1", "GitHub only", "owner/repo")
  gh_enqueue(d, "GH-2", "GitHub only 2", "owner/repo")

  // 不指定 project_id：所有 GitCode 条目都算
  let s = gc_ok(gitcode_queue_status(d, ""), "queue_status")
  assert_eq(gc_int(s, "total"), 3)
  assert_eq(gc_int(s, "pending"), 3)
  assert_eq(gc_int(s, "sent"), 0)
}

// =====================================================================
// Test 5：gitcode_queue_status 指定 gitcode_project_id → 只统计匹配的
// =====================================================================

///|
test "gc-05: queue_status 指定 project_id 后只统计匹配条目" {
  let d = "temp/gc_wbtest"
  gc_reset(d)
  gc_enqueue(d, "GC-1", "project 100 bug", "d", "high", "100")
  gc_enqueue(d, "GC-2", "project 200 bug", "d", "low", "200")

  let s100 = gc_ok(gitcode_queue_status(d, "100"), "queue_status(100)")
  assert_eq(gc_int(s100, "total"), 1)

  let s200 = gc_ok(gitcode_queue_status(d, "200"), "queue_status(200)")
  assert_eq(gc_int(s200, "total"), 1)

  let s999 = gc_ok(gitcode_queue_status(d, "999"), "queue_status(999)")
  assert_eq(gc_int(s999, "total"), 0)
}

// =====================================================================
// Test 6：gitcode_queue_status GitCode 有 sent 和 pending → 区分统计
// =====================================================================

///|
test "gc-06: queue_status 正确区分 sent 与 pending" {
  let d = "temp/gc_wbtest"
  gc_reset(d)
  gc_enqueue(d, "GC-1", "pending bug", "d", "high", "100")
  gc_enqueue(d, "GC-2", "will be sent", "d", "low", "100")

  let _ = gc_ok(gitcode_queue_mark_sent(d, "GC-1", "42"), "mark_sent")

  let s = gc_ok(gitcode_queue_status(d, ""), "queue_status")
  assert_eq(gc_int(s, "total"), 2)
  assert_eq(gc_int(s, "pending"), 1)
  assert_eq(gc_int(s, "sent"), 1)
}

// =====================================================================
// Test 7：gitcode_flush_plan 正常生成 curl → 包含 gitcode.com + PRIVATE-TOKEN + project_id
// =====================================================================

///|
test "gc-07: flush_plan 生成的 curl 命令包含 gitcode.com + PRIVATE-TOKEN + project_id" {
  let d = "temp/gc_wbtest"
  gc_reset(d)
  gc_enqueue(d, "GC-1", "GitCode bug title", "detail", "high", "99999")

  let plan = gc_ok(gitcode_flush_plan(d, "99999", 5), "flush_plan")
  let items = match plan.value("plan") {
    Some(Array(a)) => a
    _ => abort("plan 缺 plan 数组")
  }
  assert_eq(items.length(), 1)

  let cmd = gc_str(items[0], "curl_command")
  assert_true(cmd.contains("gitcode.com/api/v4/projects/99999/issues"))
  assert_true(cmd.contains("PRIVATE-TOKEN:"))
  assert_true(cmd.contains(gitcode_token_placeholder()))
}

// =====================================================================
// Test 8：gitcode_flush_plan 生成的 body payload 含标题/严重度/bug_id
// =====================================================================

///|
test "gc-08: flush_plan 生成的 payload_json 含标题与 description（带 bug_id）" {
  let d = "temp/gc_wbtest"
  gc_reset(d)
  gc_enqueue(
    d, "GC-BODY-1", "我的 bug 标题", "这是详细描述", "critical", "5555",
  )

  let plan = gc_ok(gitcode_flush_plan(d, "5555", 5), "flush_plan")
  let items = match plan.value("plan") {
    Some(Array(a)) => a
    _ => abort("plan 数组为空")
  }
  assert_eq(items.length(), 1)
  let item = items[0]
  let pj = match item.value("payload_json") {
    Some(String(s)) => s
    _ => abort("缺 payload_json")
  }
  let parsed = @json.parse(pj) catch { _ => abort("payload_json 非法 JSON") }
  let title = gc_str(parsed, "title")
  let desc = gc_str(parsed, "description")
  assert_eq(title, "我的 bug 标题")
  assert_true(desc.contains("GC-BODY-1"))
  assert_true(desc.contains("critical"))

  // 同时验证 curl 命令的 --data 段也是合法 JSON（与 payload_json 一致）
  let cmd = gc_str(item, "curl_command")
  let data_str = match gc_extract_data(cmd) {
    Ok(v) => v
    Err(e) => abort("取 --data 失败: " + e)
  }
  let data_parsed = @json.parse(data_str) catch {
    _ => abort("--data 段非法 JSON")
  }
  assert_eq(gc_str(data_parsed, "title"), title)
}

// =====================================================================
// Test 9：gitcode_flush_plan token 占位符拆开写（不被 MoonBit 插值）
// =====================================================================

///|
test "gc-09: GitCode token 占位符必须逐字是 ${FIST_GITCODE_TOKEN}（拆开写不被插值）" {
  let d = "temp/gc_wbtest"
  gc_reset(d)
  gc_enqueue(d, "GC-TOK-1", "标题", "d", "medium", "123")

  let plan = gc_ok(gitcode_flush_plan(d, "123", 5), "flush_plan")
  let items = match plan.value("plan") {
    Some(Array(a)) => a
    _ => abort("plan 空")
  }
  let cmd = gc_str(items[0], "curl_command")
  // 关键断言：cmd 里必须出现字面量 `${FIST_GITCODE_TOKEN}`
  let expected = "$" + "{FIST_GITCODE_TOKEN}"
  assert_true(cmd.contains(expected))
  assert_eq(gitcode_token_placeholder(), expected)
}

// =====================================================================
// Test 10：gitcode_flush_plan 空 project_id → Err
// =====================================================================

///|
test "gc-10: flush_plan 空 project_id 返回 Err" {
  let d = "temp/gc_wbtest"
  gc_reset(d)
  gc_enqueue(d, "GC-1", "title", "d", "high", "100")
  let r = gitcode_flush_plan(d, "", 5)
  match r {
    Ok(_) => abort("空 project_id 应返回 Err")
    Err(msg) => assert_true(msg.contains("gitcode_project_id"))
  }
}

// =====================================================================
// Test 11：gitcode_flush_plan limit 参数生效
// =====================================================================

///|
test "gc-11: flush_plan limit 参数限制生成数量" {
  let d = "temp/gc_wbtest"
  gc_reset(d)
  gc_enqueue(d, "GC-1", "title1", "d", "high", "100")
  gc_enqueue(d, "GC-2", "title2", "d", "medium", "100")
  gc_enqueue(d, "GC-3", "title3", "d", "low", "100")
  gc_enqueue(d, "GC-4", "title4", "d", "low", "100")

  let plan = gc_ok(gitcode_flush_plan(d, "100", 2), "flush_plan(limit=2)")
  let items = match plan.value("plan") {
    Some(Array(a)) => a
    _ => []
  }
  assert_eq(items.length(), 2)
}

// =====================================================================
// Test 12：gitcode_queue_mark_sent 追加 gitcode_issue_iid 字段
// =====================================================================

///|
test "gc-12: queue_mark_sent 追加 gitcode_issue_iid 字段" {
  let d = "temp/gc_wbtest"
  gc_reset(d)
  gc_enqueue(d, "GC-SENT-1", "pending 条目", "d", "high", "100")

  let _ = gc_ok(gitcode_queue_mark_sent(d, "GC-SENT-1", "77"), "mark_sent")

  let read = gc_ok(gitcode_queue_read(d), "queue_read")
  match read {
    Array(a) => {
      assert_eq(a.length(), 1)
      match a[0] {
        Object(m) => {
          let iid = match m.get("gitcode_issue_iid") {
            Some(String(s)) => s
            _ => abort("缺 gitcode_issue_iid 字段")
          }
          assert_eq(iid, "77")
          let sent_at = match m.get("sent_at") {
            Some(String(s)) => s
            _ => abort("缺 sent_at 字段")
          }
          assert_eq(sent_at, "gitcode")
        }
        _ => abort("条目不是对象")
      }
    }
    _ => abort("queue_read 返回非数组")
  }
}

// =====================================================================
// Test 13：gitcode_queue_mark_sent 标记后 status.sent 增加
// =====================================================================

///|
test "gc-13: mark_sent 后 queue_status.sent 增加" {
  let d = "temp/gc_wbtest"
  gc_reset(d)
  gc_enqueue(d, "GC-A", "bug A", "d", "high", "100")
  gc_enqueue(d, "GC-B", "bug B", "d", "low", "100")

  let before = gc_ok(gitcode_queue_status(d, ""), "status before")
  assert_eq(gc_int(before, "sent"), 0)

  let _ = gc_ok(gitcode_queue_mark_sent(d, "GC-A", "101"), "mark_sent A")

  let after = gc_ok(gitcode_queue_status(d, ""), "status after")
  assert_eq(gc_int(after, "sent"), 1)
  assert_eq(gc_int(after, "pending"), 1)
}

// =====================================================================
// Test 14：gitcode_queue_pending 空队列 → 空数组
// =====================================================================

///|
test "gc-14: queue_pending 空队列返回空数组" {
  let d = "temp/gc_wbtest"
  gc_reset(d)
  let r = gitcode_queue_pending(d)
  match r {
    Ok(j) =>
      match j {
        Array(a) => assert_eq(a.length(), 0)
        _ => abort("queue_pending 应返回数组")
      }
    Err(e) => abort("queue_pending 失败: " + e)
  }
}

// =====================================================================
// Test 15：gitcode_queue_pending 混合队列 → 只返回 GitCode pending
// =====================================================================

///|
test "gc-15: queue_pending 混合队列只返回 GitCode pending 条目" {
  let d = "temp/gc_wbtest"
  gc_reset(d)
  gc_enqueue(d, "GC-P1", "pending gitcode", "d", "high", "100")
  gc_enqueue(d, "GC-P2", "also pending", "d", "low", "200")
  gh_enqueue(d, "GH-P1", "github pending", "owner/repo")

  let r = gitcode_queue_pending(d)
  let arr = match r {
    Ok(j) =>
      match j {
        Array(a) => a
        _ => abort("queue_pending 应返回数组")
      }
    Err(e) => abort("queue_pending 失败: " + e)
  }
  assert_eq(arr.length(), 2)
  for item in arr {
    let pid = gc_str(item, "gitcode_project_id")
    assert_true(!pid.is_empty())
  }
}

// =====================================================================
// Test 16：gitcode_queue_pending 过滤掉已 sent 的 GitCode 条目
// =====================================================================

///|
test "gc-16: queue_pending 过滤掉已 sent 的 GitCode 条目" {
  let d = "temp/gc_wbtest"
  gc_reset(d)
  gc_enqueue(d, "GC-P1", "will be sent", "d", "high", "100")
  gc_enqueue(d, "GC-P2", "stays pending", "d", "low", "100")

  let _ = gc_ok(gitcode_queue_mark_sent(d, "GC-P1", "55"), "mark P1")

  let r = gitcode_queue_pending(d)
  let arr = match r {
    Ok(j) =>
      match j {
        Array(a) => a
        _ => abort("queue_pending 应返回数组")
      }
    Err(e) => abort("queue_pending 失败: " + e)
  }
  assert_eq(arr.length(), 1)
  assert_eq(gc_str(arr[0], "bug_id"), "GC-P2")
}

// =====================================================================
// Test 17：gitcode_queue_status pending_list 每条都有 gitcode_project_id
// =====================================================================

///|
test "gc-17: queue_status pending_list 每条 GitCode 条目都带 gitcode_project_id" {
  let d = "temp/gc_wbtest"
  gc_reset(d)
  gc_enqueue(d, "GC-PR1", "bug PR1", "d", "medium", "888")

  let s = gc_ok(gitcode_queue_status(d, ""), "status")
  let pl = match s.value("pending_list") {
    Some(Array(a)) => a
    _ => abort("缺 pending_list")
  }
  assert_eq(pl.length(), 1)
  let pid = gc_str(pl[0], "gitcode_project_id")
  assert_eq(pid, "888")
}

// =====================================================================
// Test 18：非法 project_dir 一律 Err（read / status / flush_plan / pending / mark_sent）
// =====================================================================

///|
test "gc-18: 非法 project_dir 一律返回 Err" {
  let bad = "..etcpasswd"
  match gitcode_queue_read(bad) {
    Ok(_) => abort("非法 project_dir 的 queue_read 应 Err")
    Err(_) => ()
  }
  match gitcode_queue_status(bad, "") {
    Ok(_) => abort("非法 project_dir 的 queue_status 应 Err")
    Err(_) => ()
  }
  match gitcode_flush_plan(bad, "100", 5) {
    Ok(_) => abort("非法 project_dir 的 flush_plan 应 Err")
    Err(_) => ()
  }
  match gitcode_queue_pending(bad) {
    Ok(_) => abort("非法 project_dir 的 queue_pending 应 Err")
    Err(_) => ()
  }
  match gitcode_queue_mark_sent(bad, "GC-1", "1") {
    Ok(_) => abort("非法 project_dir 的 mark_sent 应 Err")
    Err(_) => ()
  }
}

// =====================================================================
// Test 19：curl 命令必须包含 PRIVATE-TOKEN 头（不是 Bearer）
// =====================================================================

///|
test "gc-19: curl 命令鉴权头是 PRIVATE-TOKEN（不是 GitHub 的 Bearer）" {
  let d = "temp/gc_wbtest"
  gc_reset(d)
  gc_enqueue(d, "GC-AUTH-1", "auth test", "d", "low", "123")

  let plan = gc_ok(gitcode_flush_plan(d, "123", 5), "flush_plan")
  let items = match plan.value("plan") {
    Some(Array(a)) => a
    _ => abort("plan 空")
  }
  let cmd = gc_str(items[0], "curl_command")

  assert_true(cmd.contains("PRIVATE-TOKEN:"))
  assert_true(!cmd.contains("Bearer "))
}

// =====================================================================
// Test 20：flush_plan 只处理指定 project_id 的条目（多条不同 pid 混合）
// =====================================================================

///|
test "gc-20: flush_plan 多条不同 project_id 混合时只处理匹配的" {
  let d = "temp/gc_wbtest"
  gc_reset(d)
  gc_enqueue(d, "GC-X", "X pid 100", "d", "high", "100")
  gc_enqueue(d, "GC-Y", "Y pid 200", "d", "medium", "200")
  gc_enqueue(d, "GC-Z", "Z pid 100", "d", "low", "100")
  gh_enqueue(d, "GH-FAKE", "GH fake", "owner/repo")

  let plan100 = gc_ok(gitcode_flush_plan(d, "100", 10), "flush_plan 100")
  let items100 = match plan100.value("plan") {
    Some(Array(a)) => a
    _ => []
  }
  assert_eq(items100.length(), 2)
  for it in items100 {
    let cmd = gc_str(it, "curl_command")
    assert_true(cmd.contains("/projects/100/issues"))
  }

  let plan200 = gc_ok(gitcode_flush_plan(d, "200", 10), "flush_plan 200")
  let items200 = match plan200.value("plan") {
    Some(Array(a)) => a
    _ => []
  }
  assert_eq(items200.length(), 1)
}

// =====================================================================
// Test 21：flush_plan 生成的 curl URL 是 POST gitcode.com/api/v4/projects/{id}/issues
// =====================================================================

///|
test "gc-21: flush_plan curl URL 格式正确（POST gitcode.com api v4）" {
  let d = "temp/gc_wbtest"
  gc_reset(d)
  gc_enqueue(d, "GC-URL-1", "url test", "d", "critical", "777")

  let plan = gc_ok(gitcode_flush_plan(d, "777", 5), "flush_plan")
  let items = match plan.value("plan") {
    Some(Array(a)) => a
    _ => abort("plan 空")
  }
  let cmd = gc_str(items[0], "curl_command")
  assert_true(cmd.contains("curl -sS -X POST"))
  assert_true(cmd.contains("https://gitcode.com/api/v4/projects/777/issues"))
}
