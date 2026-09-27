/// github_sync_wbtest.mbt —— BUG-35 / BUG-87 回归锁：GitHub issue 落地面的生成载荷。
///
/// 缺陷原状①（BUG-35，账本活证据）：payload 用字符串拼接生成、字段值套 shell_quote，
/// 而 build_issue_body 恒含裸换行 ⇒ 产出的 `--data` 连 `json.loads` 都过不了；
/// issue_up 的"把账本推到远端 issue"整条失败，不是某条边缘字段。
/// 缺陷原状②（BUG-87，本轮打调用面才撞出来）：命令里写的 `Bearer ${FIST_GITHUB_TOKEN}`
/// 被编译器当成**字符串插值** ⇒ JS target 运行时 `ReferenceError: FIST_GITHUB_TOKEN is
/// not defined`，三个 plan 构造器在 server 默认目标上一律不可用（native 侧编不过）。
///
/// 判据口径（零网络、零 token，账本建议③点名要的那条）：
///   取 curl_command 里 `--data` 后面那段，反转 POSIX 单引号后交给 @json.parse——
///   修好前先抛错、再是裸换行打断 JSON，两条都在修好前必红。
/// 目录约定：独立 scratch 目录 temp/gh_b35，每条判据自己清场，可重复运行。

///|
/// 队列文件按 project_dir 落盘且跨运行留存 —— 判据必须自己清场，
/// 否则第二次跑读到上一轮 mark_sent 写下的 sent_at，pending 集合为空、断言假红。
fn b35_reset(d : String) -> Unit {
  @fs.create_dir("temp") catch {
    _ => ()
  }
  @fs.create_dir(d) catch {
    _ => ()
  }
  mem_ensure_dir(mem_dir(d))
  let _ = mem_write(gq_path(d), "")
}

///|
/// Result 取正身：任何 Err 一律 abort，不让"调用失败"降级成"结果为空"
fn b35_ok(r : Result[Json, String], what : String) -> Json {
  match r {
    Ok(j) => j
    Err(m) => abort(what + " 失败: " + m)
  }
}

///|
/// 从完整 curl 命令里取出 `--data <值>` 的值，并反转 POSIX 单引号包装。
/// 找不到返回 Err —— 判据不许静默放过"根本没生成 --data"的形态。
fn extract_data_arg(cmd : String) -> Result[String, String] {
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
    rest.starts_with("'") &&
    rest.ends_with("'")
  if !wrapped {
    return Err("--data 值不是完整的单引号包装: " + rest)
  }
  // 去掉外层引号，再把 shell 的 '"'"' 还原成 '
  let inner = rest.substring(start=1, end=rest.length() - 1)
  let unwrapped = inner.replace(old="'\"'\"'", new="'")
  Ok(unwrapped)
}

///|
/// 取 payload 的某个字符串字段（解析失败/缺字段一律 abort，不放行）
fn gh_field(j : Json, key : String) -> String {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(String(s)) => s
        _ => abort("payload 缺字段 " + key + ": " + j.stringify())
      }
    _ => abort("payload 不是对象")
  }
}

///|
/// plan 数组取值：缺字段一律 abort，不回退空数组（空数组会把"没生成"读成"生成 0 条"）
fn b35_items(j : Json, what : String) -> Array[Json] {
  match j.value("plan") {
    Some(Array(a)) => a
    _ => abort(what + " 缺 plan 数组: " + j.stringify())
  }
}

///|
/// 一条 plan 项（或单条 plan）的 --data 段解成 Json，并顺带锁住 BUG-87 的占位符字面存活。
/// 三条路径（flush / comment / close）共用这一个判据，防止"只修了 flush 那一处"。
fn b35_data(item : Json, what : String) -> Json {
  let cmd = match item.value("curl_command") {
    Some(String(s)) => s
    _ => abort(what + " 缺 curl_command: " + item.stringify())
  }
  let data = match extract_data_arg(cmd) {
    Ok(v) => v
    Err(e) => abort(what + " 取 --data 失败: " + e + " / cmd=" + cmd)
  }
  // @json.parse 在非法输入上 raise —— 本仓惯例 catch 兜住再 abort（github_sync.mbt:40 同形）
  let parsed = @json.parse(data) catch {
    _ =>
      abort(
        what + " --data 段不是合法 JSON（BUG-35 复发） 段=" + data,
      )
  }
  // 断言侧同样不能写字面量 `${...}`，必须复用产品侧的 token_placeholder() 作单一真源
  if !cmd.contains("Bearer " + token_placeholder()) {
    abort(
      what +
      "：token 占位符没按字面活下来（BUG-87 复发） cmd=" +
      cmd,
    )
  }
  parsed
}

///|
fn b35_enqueue(d : String, summary : String, detail : String) -> Unit {
  let _ = b35_ok(
    github_queue_append(
      d,
      "BUG-1",
      summary,
      detail,
      "high",
      "2026-09-27T00:00:00Z",
      "vicTop-cw/fist-mbt",
      ["bug", "priority-high"],
    ),
    "queue_append",
  )
}

///|
test "BUG-35：github_flush_plan 生成的 --data 是合法 JSON（多行正文 + 引号都要活得下来）" {
  let d = "temp/gh_b35"
  b35_reset(d)
  // 正文/摘要里同时埋 换行、双引号、单引号 三类会打断拼接式 payload 的字符
  b35_enqueue(
    d, "标题含\"引号\"与 don't 缩写\n第二行", "详情第一行\n详情第二行：路径 a\\b\n带 \" 引号",
  )
  let plan = b35_ok(github_flush_plan(d, 5), "flush_plan")
  let items = b35_items(plan, "flush_plan")
  assert_eq(items.length(), 1)
  let item = items[0]
  // ① 判据本体：--data 段必须能被 JSON 解析（旧实现在这里必抛——正文里的裸换行直接打断字符串）
  let parsed = b35_data(item, "flush_plan")
  // ② 解析出来的字段必须与写入侧一致：shell/JSON 两层转义都没吃掉内容
  assert_eq(
    gh_field(parsed, "title"),
    "标题含\"引号\"与 don't 缩写\n第二行",
  )
  let body = gh_field(parsed, "body")
  assert_true(body.contains("详情第二行"))
  assert_true(body.contains("don't"))
  assert_true(body.contains("\"引号\""))
  let labels = match parsed.value("labels") {
    Some(Array(a)) => a
    _ => abort("labels 不是数组: " + parsed.stringify())
  }
  assert_eq(labels.length(), 2)
  // ③ payload_json 旁路字段（Windows 下 --data @file 的正身，不必反向解 shell 引号）
  let pj = match item.value("payload_json") {
    Some(String(s)) => s
    _ => abort("payload_json 缺失: " + item.stringify())
  }
  let pj_parsed = @json.parse(pj) catch {
    _ => abort("payload_json 非法 JSON: " + pj)
  }
  assert_eq(gh_field(pj_parsed, "title"), gh_field(parsed, "title"))
}

///|
test "BUG-35：comment 与 close 的 payload 同样必须是合法 JSON" {
  let d = "temp/gh_b35"
  b35_reset(d)
  b35_enqueue(d, "comment 用标题", "comment 用详情")
  // 先让 BUG-1 变成"已同步"，comment/close 才找得到 issue number
  let _ = b35_ok(
    github_queue_mark_sent(
      d,
      ["BUG-1"],
      Map([("BUG-1", 77)]),
      sent_at="2026-09-27T00:01:00Z",
    ),
    "mark_sent",
  )
  let cp = b35_ok(
    github_build_comment_plan(d, "BUG-1", "第一行\n带\"引号\"与 don't"),
    "comment_plan",
  )
  let cb = gh_field(b35_data(cp, "comment_plan"), "body")
  assert_eq(cb, "第一行\n带\"引号\"与 don't")
  // close：固定小 payload，同一条判据再走一遍
  let kp = b35_ok(
    github_build_close_plan(d, Map([("BUG-1", 77)])),
    "close_plan",
  )
  let kitems = b35_items(kp, "close_plan")
  assert_eq(kitems.length(), 1)
  let kparsed = b35_data(kitems[0], "close_plan")
  assert_eq(gh_field(kparsed, "state"), "closed")
}

///|
test "BUG-35/87：shell_quote 与 token 占位符不得篡改载荷" {
  // POSIX 单引号安全形态：'don'"'"'t' —— 外层引号保持，内部单引号用 '"'"' 接续
  assert_eq(shell_quote("don't"), "'don'\"'\"'t'")
  assert_eq(shell_quote("plain"), "'plain'")
  // 换行不需要额外处理：payload 已是单行 JSON（stringify 把 \n 转义成两字符），
  // 这里锁住"JSON 层不含裸换行"这一事实，否则单引号包装也救不了命令行参数
  let one_line = Json::object({ "body": Json::string("a\nb") }).stringify()
  assert_true(!one_line.contains("\n"))
  assert_eq(shell_quote(one_line), "'" + one_line + "'")
  // BUG-87：占位符逐字交给 shell——`$` 与 `{` 只能拆开拼，写成字面量会被当成插值
  let ph = "$" + "{FIST_GITHUB_TOKEN}"
  assert_eq(token_placeholder(), ph)
}
