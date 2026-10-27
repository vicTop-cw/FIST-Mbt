/// bugreport_status_wbtest.mbt —— BUG-9 控制面的回归锁：账本状态位可改，且改完仍是合法账本。
///
/// 缺陷原状：memory/bugs.md 此前**只写不销**——`report_bug` 能开条，没有任何 API 能把
/// OPEN 改成 FIXED/DUPLICATE/FALSE_POSITIVE，于是"还剩几条没修"永远只能靠人肉数，
/// 而对外投影（插件正文的待修数）由 gen_plugins 从抬头状态反解，缺控制面就意味着
/// 要么谎报（手写数字）、要么永远红。
///
/// 判据口径：全部落在独立 scratch 账本 temp/bug9_status/memory/bugs.md，不碰仓库真账本
/// （`project_dir` 越界会被拒 ⇒ bug 账只能开在临时区，见 BUG-53 的双轨记账）。

///|
/// 造一本三条 OPEN 的临时账本；编号、抬头文法与真账本一致（`## BUG-n [ts] [sev] 状态`）。
fn b9_seed() -> String {
  let d = "temp/bug9_status"
  @fs.create_dir("temp") catch {
    _ => ()
  }
  @fs.create_dir(d) catch {
    _ => ()
  }
  mem_ensure_dir(mem_dir(d))
  let body = "## BUG-901 [2026-09-27T00:00:00Z] [low] OPEN\n- summary: 甲\n\n" +
    "## BUG-902 [2026-09-27T00:00:00Z] [low] OPEN\n- summary: 乙\n\n" +
    "## BUG-903 [2026-09-27T00:00:00Z] [low] OPEN\n- summary: 丙\n\n"
  let _ = mem_write(bug_file_path(d), body)
  d
}

///|
fn b9_read(d : String) -> String {
  match mem_read(bug_file_path(d)) {
    None => ""
    Some(s) => s
  }
}

///|
/// 从账本正文里数某个状态出现了几次（按抬头行，不按正文提及）。
fn b9_status_count(text : String, status : String) -> Int32 {
  let mut n = 0
  for v in text.split("\n") {
    let line = v.to_owned().trim().to_owned()
    if bug_is_header(line) {
      let (_, _, _, cur, _) = bug_split_header(line)
      if cur == status {
        n = n + 1
      }
    }
  }
  n
}

///|
/// 取 [start_needle, end_needle) 之间的正文片段；任一端点找不到返回哨兵串，让断言红得出来。
fn b9_between(text : String, start : String, end : String) -> String {
  let cs = text.to_array()
  let ss = start.to_array()
  let es = end.to_array()
  let mut a = -1
  let mut b = -1
  let mut i = 0
  while i + ss.length() <= cs.length() {
    let mut hit = true
    for k = 0; k < ss.length(); k = k + 1 {
      if cs[i + k] != ss[k] {
        hit = false
      }
    }
    if hit && a < 0 {
      a = i + ss.length()
    }
    i = i + 1
  }
  i = 0
  while i + es.length() <= cs.length() {
    let mut hit = true
    for k = 0; k < es.length(); k = k + 1 {
      if cs[i + k] != es[k] {
        hit = false
      }
    }
    if hit && b < 0 && i > a {
      b = i
    }
    i = i + 1
  }
  if a < 0 || b < 0 {
    "<b9-between-missing>"
  } else {
    text[a:b].to_owned()
  }
}

///|
fn b9_str(j : Json, key : String) -> String {
  match jget(j, key) {
    Some(String(s)) => s
    _ => ""
  }
}

///|
fn b9_int(j : Json, key : String) -> Int32 {
  match jget(j, key) {
    Some(Number(n, ..)) => n.to_int()
    _ => -1
  }
}

///|
fn b9_bool(j : Json, key : String) -> Bool {
  match jget(j, key) {
    Some(Json::True) => true
    Some(Json::False) => false
    _ => false
  }
}

///|
test "BUG-9：bug_fix 同一笔改抬头 + 落点名整批的小记（幂等，第二条邻居正文不被吞）" {
  let d = b9_seed()
  let r = match
    bug_fix(
      d,
      ["BUG-901", "BUG-902"],
      evidence="真源 x.mbt，锁 y",
      ts="2026-09-27T12:00:00Z",
    ) {
    Ok(j) => j
    Err(m) => abort("bug_fix 失败: " + m)
  }
  assert_eq(b9_int(r, "heading_changed"), 2)
  assert_eq(b9_int(r, "already_fixed"), 0)
  assert_true(b9_bool(r, "note_written"))
  let text = b9_read(d)
  assert_eq(b9_status_count(text, "FIXED"), 2)
  assert_eq(b9_status_count(text, "OPEN"), 1)
  // 抬头文法必须还是判据认的形状：状态是最后一个字段，时间戳/严重度原样保留
  assert_true(text.contains("## BUG-901 [2026-09-27T00:00:00Z] [low] FIXED"))
  // 一条小记点名整批（不是两条各点自己）——这正是「小记数≠修好数」那套旧口径的反例
  assert_true(
    text.contains("### FIXED(2026-09-27T12:00:00Z / BUG-901, BUG-902)"),
  )
  assert_true(text.contains("- evidence: 真源 x.mbt，锁 y"))
  // 邻居条目的 summary 不能被搬进本批的证据里（insert_at 取的是本批最后一条的末尾）
  let seg = b9_between(text, "### FIXED(", "## BUG-903")
  assert_true(seg.contains("- evidence:"))
  assert_true(!seg.contains("summary: 丙"))

  // 幂等：同 ts 同批再跑一次 ⇒ 不再改抬头、不再写第二条小记
  let again = match
    bug_fix(
      d,
      ["BUG-901", "BUG-902"],
      evidence="重复调用",
      ts="2026-09-27T12:00:00Z",
    ) {
    Ok(j) => j
    Err(m) => abort("bug_fix 二次调用失败: " + m)
  }
  assert_eq(b9_int(again, "heading_changed"), 0)
  assert_eq(b9_int(again, "already_fixed"), 2)
  assert_true(!b9_bool(again, "note_written"))
  let text2 = b9_read(d)
  assert_eq(b9_status_count(text2, "FIXED"), 2)
  let mut notes = 0
  for v in text2.split("\n") {
    if v.to_owned().trim().to_owned().has_prefix("### FIXED(") {
      notes = notes + 1
    }
  }
  assert_eq(notes, 1)
}

///|
test "BUG-9：状态闭集、FIXED 不许走抬头、DUPLICATE 必须指向合法主编号" {
  let d = b9_seed()
  // ① 闭集外的词一律拒（防 Fixed/fixed/已修 各写一套）
  let bad = bug_mark_status(d, "BUG-901", "Fixed", ts="2026-09-27T12:00:00Z")
  match bad {
    Err(m) => assert_true(m.contains("不在闭集"))
    Ok(_) => abort("闭集外的状态词 Fixed 被接受了")
  }
  // ② 想标修好只能走 bug_fix —— 只改抬头会把账本写成生成器拒绝产出的红状态
  let skip = bug_mark_status(d, "BUG-901", "FIXED", ts="2026-09-27T12:00:00Z")
  match skip {
    Err(m) => assert_true(m.contains("bug_fix"))
    Ok(_) => abort("绕开小记直接标 FIXED 成功了")
  }
  // ③ DUPLICATE 缺主编号 / 指自己 / 指向不存在的 / 形成链 —— 四条都要红
  let no_main = bug_mark_status(
    d,
    "BUG-901",
    "DUPLICATE",
    ts="2026-09-27T12:00:00Z",
  )
  match no_main {
    Err(m) => assert_true(m.contains("主编号"))
    Ok(_) => abort("DUPLICATE 没带 →BUG-m 也放行")
  }
  let self_ref = bug_mark_status(
    d,
    "BUG-901",
    "DUPLICATE",
    dup_of="BUG-901",
    ts="2026-09-27T12:00:00Z",
  )
  match self_ref {
    Err(m) => assert_true(m.contains("自己"))
    Ok(_) => abort("主编号指向自己也被放行")
  }
  let ghost = bug_mark_status(
    d,
    "BUG-901",
    "DUPLICATE",
    dup_of="BUG-999",
    ts="2026-09-27T12:00:00Z",
  )
  match ghost {
    Err(m) => assert_true(m.contains("不存在"))
    Ok(_) => abort("主编号不存在也被放行")
  }
  // 合法并入：902 → 901，抬头带上 →BUG-901
  let ok = bug_mark_status(
    d,
    "BUG-902",
    "DUPLICATE",
    dup_of="BUG-901",
    ts="2026-09-27T12:00:00Z",
  )
  match ok {
    Ok(j) => assert_eq(b9_str(j, "duplicate_of"), "BUG-901")
    Err(m) => abort("合法 DUPLICATE 被拒: " + m)
  }
  // 901 现在自己是 DUPLICATE ⇒ 903 再指向 901 就是链条，必须红
  let move = bug_mark_status(d, "BUG-901", "OPEN", ts="2026-09-27T12:00:00Z")
  match move {
    Ok(_) => ()
    Err(m) => abort("改回 OPEN 被拒: " + m)
  }
  let first = bug_mark_status(
    d,
    "BUG-901",
    "DUPLICATE",
    dup_of="BUG-903",
    ts="2026-09-27T12:00:00Z",
  )
  match first {
    Ok(_) => ()
    Err(m) => abort("第一次并入失败: " + m)
  }
  let chain = bug_mark_status(
    d,
    "BUG-903",
    "DUPLICATE",
    dup_of="BUG-901",
    ts="2026-09-27T12:00:00Z",
  )
  match chain {
    Err(m) => assert_true(m.contains("链条"))
    Ok(_) => abort("DUPLICATE 指向 DUPLICATE 被放行")
  }
}

///|
test "BUG-9：终态之间不互跳，空 evidence 与非法 project_dir 一律拒" {
  let d = b9_seed()
  let fp = bug_mark_status(
    d,
    "BUG-903",
    "FALSE_POSITIVE",
    evidence="该面自述是设计，非缺陷",
    ts="2026-09-27T12:00:00Z",
  )
  match fp {
    Ok(_) => ()
    Err(m) => abort("误报立据失败: " + m)
  }
  let text = b9_read(d)
  assert_eq(b9_status_count(text, "FALSE_POSITIVE"), 1)
  assert_true(
    text.contains(
      "- false_positive(2026-09-27T12:00:00Z): 该面自述是设计",
    ),
  )
  // 终态之间不许直接跳（要改判先回 OPEN）——和记账规则表同一条约束
  let jump = bug_fix(
    d,
    ["BUG-903"],
    evidence="想直接改成修好",
    ts="2026-09-27T12:00:00Z",
  )
  match jump {
    Err(m) => assert_true(m.contains("不互跳"))
    Ok(_) => abort("误报被直接改成了修好")
  }
  // 空 evidence：正是"空口标修好"的形状，必须拒
  let empty = bug_fix(d, ["BUG-901"], evidence="   ", ts="2026-09-27T12:00:00Z")
  match empty {
    Err(m) => assert_true(m.contains("evidence"))
    Ok(_) => abort("空 evidence 的 bug_fix 通过了")
  }
  // 缺 ts：时间戳由调用层服务端盖章，API 不接受"没有 ts 的写"
  let no_ts = bug_fix(d, ["BUG-901"], evidence="有证据但没盖章", ts="")
  match no_ts {
    Err(m) => assert_true(m.contains("ts"))
    Ok(_) => abort("缺 ts 也放行")
  }
  // 非法 project_dir：拒绝绝对路径/穿越/盘符（BUG-53 的越界面）
  let bad_dir = bug_fix(
    "../escape",
    ["BUG-901"],
    evidence="越界写",
    ts="2026-09-27T12:00:00Z",
  )
  match bad_dir {
    Err(m) => assert_true(m.contains("project_dir"))
    Ok(_) => abort("project_dir 越界被接受")
  }
  // 不存在的编号必须点名报错，不许静默少写一条
  let ghost = bug_fix(
    d,
    ["BUG-901", "BUG-999"],
    evidence="混一条不存在的",
    ts="2026-09-27T12:00:00Z",
  )
  match ghost {
    Err(m) => assert_true(m.contains("BUG-999"))
    Ok(_) => abort("不存在的编号被静默忽略")
  }
  // 上一条被拒的调用必须**一个字节都没写**（整笔原子，不留半改状态）
  assert_eq(b9_status_count(b9_read(d), "FIXED"), 0)
}

///|
test "BUG-88：severity 闭集里每个值都能写出被账本文法读得的抬头，缺省值也不例外" {
  let d = b9_seed()
  // report_bug 的第 3 个必填位是引擎（编译期类型报告点名：…, FistEngine, now~），
  // 缺省 publish_task=false ⇒ 只入账、不派单。
  let eng = @engine.FistEngine::new()
  // 旧形状：写侧 bug_severities() 收 critical/open，而 memory/bugs.md 的抬头文法只认
  // high|medium|low ⇒ 一条**完全合法**的 report_bug 就能产出一行判据读不到的抬头，
  // 而 gen_plugins 遇到读不到的抬头是 FATAL（整条投影链停摆），不是"少数一条"。
  let mut n = 0
  for sev in bug_severities() {
    n = n + 1
    let r = report_bug(
      d,
      "severity 往返探针 " + sev,
      detail="逐值往返锁",
      severity=sev,
      ref_call_id="",
      reported_by="wbtest",
      publish_task=false,
      eng,
      now="2026-09-27T12:00:00Z",
    )
    match r {
      Ok(_) => ()
      Err(m) => abort("severity=" + sev + " 被自己拒了: " + m)
    }
  }
  let text = b9_read(d)
  for sev in bug_severities() {
    assert_true(
      text.contains("] [" + sev + "] OPEN"),
      msg="severity=" +
        sev +
        " 写出的抬头读不回来（闭集与文法漂移）",
    )
  }
  // 缺省严重度：旧缺省是状态词 "open"（把 OPEN 当严重度用），必须是文法内的真严重度
  // 调用面（MCP 工具）在没给 severity 时传空串 ⇒ 落到服务端缺省值
  let _ = report_bug(
    d,
    "缺省严重度探针",
    detail="省略 severity",
    severity="",
    ref_call_id="",
    reported_by="wbtest",
    publish_task=false,
    eng,
    now="2026-09-27T12:00:00Z",
  )
  let text2 = b9_read(d)
  assert_true(text2.contains("] [medium] OPEN"))
  assert_true(!text2.contains("] [open] OPEN"))
  // 非法值只能被拒，不许"顺手当成 medium"——静默改写会让上报方以为自己的分级生效了
  let bad = report_bug(
    d,
    "非法严重度探针",
    detail="severity=blocker",
    severity="blocker",
    ref_call_id="",
    reported_by="wbtest",
    publish_task=false,
    eng,
    now="2026-09-27T12:00:00Z",
  )
  match bad {
    Err(m) => assert_true(m.contains("severity"))
    Ok(_) => abort("闭集外的 severity 被放行")
  }
}

///|
test "BUG-204：publish_task 发布失败不再静默——返回带 publish_error 且不谎报 task_id" {
  let d = b9_seed()
  let eng = @engine.FistEngine::new()
  // task_ns="default" 被 publish_parallel 硬拒（并行发布仅限定时/自驱 ns），
  // 是一条确定性失败路径：best-effort 落账仍成功，但发布必须显式回执错误。
  let r = report_bug(
    d,
    "发布失败回执探针",
    detail="task_ns=default 触发 publish_parallel Err",
    severity="medium",
    ref_call_id="",
    reported_by="wbtest",
    publish_task=true,
    task_ns="default",
    eng,
    now="2026-10-15T12:00:00Z",
  )
  match r {
    Err(m) =>
      abort("report_bug 不该整笔失败（best-effort 落账）: " + m)
    Ok(j) =>
      match j {
        Object(m) => {
          // 发布失败 ⇒ 不得回显 task_id（回显即谎报单已发）
          let has_tid = match m.get("task_id") {
            Some(_) => true
            _ => false
          }
          assert_true(!has_tid, msg="发布失败却回了 task_id")
          // 失败必须显式体现在返回里（函数注释承诺"仅在返回里体现"）
          let pe = match m.get("publish_error") {
            Some(String(s)) => s
            _ => ""
          }
          assert_true(pe != "", msg="发布失败未回执 publish_error")
        }
        _ => abort("report_bug 返回非对象")
      }
  }
  // best-effort：落账不受发布失败影响，条目仍在
  assert_true(b9_read(d).contains("发布失败回执探针"))
}

///|
/// 造一本含**同号两条独立条目**的临时账本（BUG-241 复现底座）：
/// `## BUG-217 [ts1] [high] OPEN` 与 `## BUG-217 [ts2] [medium] OPEN` 并存，
/// 模拟历史上同号不同 ts/summary 重复记账的真实形状（BUG-185/186/217 均有）。
fn b241_seed() -> String {
  let d = "temp/bug241_dup"
  @fs.create_dir("temp") catch {
    _ => ()
  }
  @fs.create_dir(d) catch {
    _ => ()
  }
  mem_ensure_dir(mem_dir(d))
  let body = "## BUG-217 [2026-10-15T13:20:00Z] [high] OPEN\n- summary: 首条（selfdrive 静默吞错）\n\n" +
    "## BUG-903 [2026-09-27T00:00:00Z] [low] OPEN\n- summary: 邻居，正文不得被吞\n\n" +
    "## BUG-217 [2026-10-15T13:22:34Z] [medium] OPEN\n- summary: 次条（claimguard 副作用）\n\n"
  let _ = mem_write(bug_file_path(d), body)
  d
}

///|
/// BUG-241：同号多条独立条目时 `bug_fix` 必须逐条改判，而不是只改首条。
/// 旧实现 `bug_header_line` 只取首个命中 ⇒ 真正待闭环的那条（此处次条）永久 OPEN。
/// 修复后：heading_changed=2（两条都被改）、named 去重只点一次号、小记落在最后一条之后。
test "BUG-241：同号重复条目被逐条标 FIXED，不再只改首条" {
  let d = b241_seed()
  let r = match
    bug_fix(
      d,
      ["BUG-217"],
      evidence="claimguard.mbt may_proceed_full 只读预检（commit ba4fd93）",
      ts="2026-10-16T14:35:00Z",
    ) {
    Ok(j) => j
    Err(m) => abort("bug_fix 失败: " + m)
  }
  // 两条同号条目都应被改判 ⇒ heading_changed=2（旧实现此处=1）
  assert_eq(b9_int(r, "heading_changed"), 2)
  assert_eq(b9_int(r, "already_fixed"), 0)
  let text = b9_read(d)
  // 两条 217 都变成 FIXED（按抬头行数统计）
  assert_eq(b9_status_count(text, "FIXED"), 2)
  // 邻居 BUG-903 保持 OPEN，正文不被吞
  assert_eq(b9_status_count(text, "OPEN"), 1)
  assert_true(text.contains("summary: 邻居，正文不得被吞"))
  // 两条 217 各自保留了原 ts/sev 抬头（不能互相覆盖）
  assert_true(text.contains("## BUG-217 [2026-10-15T13:20:00Z] [high] FIXED"))
  assert_true(text.contains("## BUG-217 [2026-10-15T13:22:34Z] [medium] FIXED"))
  // named 去重：只点一次号，不出现 BUG-217, BUG-217
  // 小记应落在**最后一条**更新条目之后（旧实现在首条之后，会把次条正文挤到小记之前）
  // 用「次条 FIXED」到文件尾的片段检查，避免跨条目误判
  let parts = text
    .split("## BUG-217 [2026-10-15T13:22:34Z] [medium] FIXED")
    .to_array()
  let after = if parts.length() == 2 { parts[1] } else { "" }
  assert_true(after.contains("### FIXED(2026-10-16T14:35:00Z / BUG-217)"))
  assert_true(
    after.contains("- evidence: claimguard.mbt may_proceed_full 只读预检"),
  )
  assert_true(!after.contains("BUG-217, BUG-217"))
  // 首条 FIXED 与次条 FIXED 之间的片段**不得**含小记头（旧实现在此，会挤到次条正文之前）
  // 正确行为：小记落在次条之后，不在两条之间
  let middle = text
    .split("## BUG-217 [2026-10-15T13:20:00Z] [high] FIXED")
    .to_array()
  let after_first = if middle.length() == 2 { middle[1] } else { "" }
  let between = after_first
    .split("## BUG-217 [2026-10-15T13:22:34Z] [medium] FIXED")
    .to_array()
  let mid_seg = if between.length() == 2 { between[0] } else { "" }
  assert_true(!mid_seg.contains("### FIXED(2026-10-16T14:35:00Z / BUG-217)"))
}

///|
/// BUG-434：账本**条目抬头必须是「日期 + 严重度 + 状态」三段式**。
///
/// 为什么必须有这把锁：`bug_fix` / `report_bug` 把 evidence/detail **原样追加**进账本，
/// 调用方完全可能在里面写小节标题（实测：`## BUG-421：…`），
/// **甚至只是在围栏代码块里引用一行既有抬头** —— 那些行以前会被当成条目抬头，
/// 造成「同编号两条 ⇒ 后一条覆盖前一条 ⇒ 真实状态不进任何计数」。
/// 口径与 `scripts/gen_plugins.py` 的 `RE_BUG_HEAD` / `RE_BUG_STATUS` 一致。
test "bug434_heading_is_three_segment_only" {
  // 正例①：完整三段式（真抬头）
  assert_true(
    bug_is_header("## BUG-421 [2026-10-26T14:14:16Z] [medium] FIXED"),
  )
  // 正例②：DUPLICATE 带 `→BUG-1` 后缀 ⇒ **仍是合法抬头**（防修过头）
  assert_true(
    bug_is_header("## BUG-2 [2026-09-26T00:00:01Z] [medium] DUPLICATE →BUG-1"),
  )
  // 正例③：FALSE_POSITIVE 带括号后缀
  assert_true(
    bug_is_header("## BUG-3 [2026-09-26T00:00:02Z] [low] FALSE_POSITIVE (evidence)"),
  )
  // 反例①：**污染行**（小节标题，无 [] 段）—— 这就是本轮实测撞到的形状
  assert_false(bug_is_header("## BUG-421：整名 leader/lead 提权面 → 已删白名单"))
  assert_false(bug_is_header("## BUG-422：查表键仍是自报名字 → B 案三层"))
  // 反例②：只有日期段、缺状态
  assert_false(bug_is_header("## BUG-999 [x] [medium]"))
  // 反例③：严重度不在闭集
  assert_false(bug_is_header("## BUG-998 [x] [bogus] OPEN"))
  // 反例④：状态不在闭集
  assert_false(bug_is_header("## BUG-997 [x] [medium] MAYBE"))
}
