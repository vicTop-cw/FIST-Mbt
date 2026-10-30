/// bugreport_trailing_newline_wbtest.mbt —— 账本落盘「尾随空行归一」的回归锁。
///
/// 缺陷原状（2026-10-26 实测，两条路径只修了一条）：
///   · 第一次修（`09c0867c`）只改了 `bug_lines_to_text` —— `bug_fix` / `bug_mark_status` 走它；
///   · 而 **`report_bug` 走另一条路**：自己 fold 出 `entry` 再 `old + entry` 直拼，
///     根本不经过 `bug_lines_to_text` ⇒ 那笔修复对 `report_bug` 完全无效；
///   · 叠加效应：`old` 以 `\n` 结尾，`entry` 又以 `lines.push("\n")` 收尾
///     ⇒ 落盘 **两个尾随换行**，pre-commit 的 `git diff --cached --check` 报
///     `new blank line at EOF` 挡住整笔提交（本会话被它挡过两次）。
///   · Lane D 补修 `ac4c7fa6`（MCP 真调实测 2→1），但**未补白盒锁**
///     ⇒ 谁删掉那几行归一逻辑，全部既有测试仍然全绿
///     （与 BUG-411 同构：「修复已落地、测试面 0 命中」）。
///
/// 本文件补的就是这个缺口：锁住「恰好一个终止换行」这个精确形状。
///
/// 判据口径：全部落在独立 scratch 账本 `temp/bug9_tnl*/memory/bugs.md`，
/// **不碰仓库真账本**（`project_dir` 越界会被拒 ⇒ bug 账只能开在临时区，见 BUG-53 双轨记账）。

///|
/// 数一段文本**末尾的连续换行个数**（尾随空行的唯一量化口径）。
///
/// 判据用「换行个数」而非 `trim` 后比较：要锁的正是「恰好一个终止换行」这个**精确形状** ——
/// 归一成 0 个（把终止换行也吃掉）或留下 2 个（缺陷复现）都必须能区分出来。
fn tnl_trailing_newlines(s : String) -> Int32 {
  let mut n = 0
  let mut i = s.length()
  while i > 0 && s[i - 1] == '\n' {
    n = n + 1
    i = i - 1
  }
  n
}

///|
/// 造一本空账本（`report_bug` 会从零建条）。
fn tnl_seed(d : String) -> Unit {
  @fs.create_dir("temp") catch {
    _ => ()
  }
  @fs.create_dir(d) catch {
    _ => ()
  }
  mem_ensure_dir(mem_dir(d))
  let _ = mem_write(bug_file_path(d), "")
}

///|
/// 锁 1（**核心回归锁**）：`report_bug` 落盘后，文件末尾换行数**必须恰好是 1**。
///
/// 连报两条是有意的：第二条才会走 `old + entry` 的拼接路径 —— 正是缺陷发生点。
/// 只报一条时 `old` 为空串，叠加效应不复现 ⇒ 锁不住。
///
/// 变异对照（判例-29）：把 `bugreport.mbt` 的
/// `let normalized = combined[0:end].to_owned() + "\n"` 改回 `let normalized = combined`
/// （即不归一）⇒ 本锁读到 2 ⇒ 必红。
test "tnl_1 report_bug 落盘末尾换行恰好 1" {
  let d = "temp/bug9_tnl_t1"
  tnl_seed(d)
  let eng = @engine.FistEngine::new()
  let r1 = report_bug(
    d,
    "第一条（尾随空行锁）",
    detail="",
    severity="low",
    ref_call_id="",
    reported_by="wbtest",
    publish_task=false,
    eng,
    now="2026-10-26T00:00:00Z",
  )
  match r1 {
    Ok(_) => ()
    Err(m) => {
      fail("report_bug 第一条失败: " + m)
      return
    }
  }
  let r2 = report_bug(
    d,
    "第二条（拼接路径，缺陷发生点）",
    detail="",
    severity="low",
    ref_call_id="",
    reported_by="wbtest",
    publish_task=false,
    eng,
    now="2026-10-26T00:00:01Z",
  )
  match r2 {
    Ok(_) => ()
    Err(m) => {
      fail("report_bug 第二条失败: " + m)
      return
    }
  }
  let n = tnl_trailing_newlines(bug_read_text(d))
  if n != 1 {
    fail(
      "report_bug 落盘末尾换行数 = " +
      n.to_string() +
      "，应为 1（2 = Lane D 修的尾随空行缺陷复现；0 = 归一过头把终止换行也吃了）",
    )
  }
}

///|
/// 锁 2：归一必须是「无尾部空行 + **恰好一个**终止换行」，不能是「吃掉全部换行」。
///
/// 为什么单立：把归一写成「删掉所有尾随换行」也能让部分场景通过，
/// 但它违反 POSIX 文本惯例，且会让后续 `split("\n")` 读回多一个空元素。
/// 本锁把「归一的**方向**」也钉住 —— 不只锁「不超标」，也锁「不欠一个」。
test "tnl_2 归一是恰好一个终止换行而非零个" {
  let d = "temp/bug9_tnl_t2"
  tnl_seed(d)
  let eng = @engine.FistEngine::new()
  let r = report_bug(
    d,
    "零个换行也不行",
    detail="",
    severity="low",
    ref_call_id="",
    reported_by="wbtest",
    publish_task=false,
    eng,
    now="2026-10-26T00:00:00Z",
  )
  match r {
    Ok(_) => ()
    Err(m) => {
      fail("report_bug 失败: " + m)
      return
    }
  }
  let n = tnl_trailing_newlines(bug_read_text(d))
  if n == 0 {
    fail(
      "末尾换行数 = 0（正文末尾无终止换行，违反 POSIX 文本惯例）",
    )
  }
  if n > 1 {
    fail(
      "末尾换行数 = " + n.to_string() + "（尾随空行缺陷复现）",
    )
  }
}

///|
/// 锁 3：`report_bug` 与 `bug_fix` 两条写入路径落盘后，**尾随换行数必须一致**。
///
/// 这是 Lane D 发现的核心 —— 同一语义存在**两处实现**
/// （`report_bug` 自己归一 + `bug_lines_to_text` 归一），历史上正是因为只修了一处才出的缺陷。
/// 本锁不要求把两处合并成一函数（那是重构，超出本单边界），只要求**两条路径产出一致**：
/// 谁再单独改坏其中一处，这里立刻红。
test "tnl_3 report_bug 与 bug_fix 尾随换行一致" {
  let d = "temp/bug9_tnl_t3"
  tnl_seed(d)
  let eng = @engine.FistEngine::new()
  let r = report_bug(
    d,
    "路径 A：report_bug",
    detail="",
    severity="low",
    ref_call_id="",
    reported_by="wbtest",
    publish_task=false,
    eng,
    now="2026-10-26T00:00:00Z",
  )
  let bid = match r {
    Ok(j) =>
      match j {
        Object(o) =>
          match o.get("bug_id") {
            Some(String(s)) => s
            _ => ""
          }
        _ => ""
      }
    Err(m) => {
      fail("report_bug 失败: " + m)
      return
    }
  }
  if bid.is_empty() {
    fail("report_bug 没回 bug_id，无法继续锁 3")
    return
  }
  let na = tnl_trailing_newlines(bug_read_text(d))
  // bug_fix 返回 Result（不是 raise 型）⇒ 必须 match，不能用 catch
  match
    bug_fix(
      d,
      [bid],
      evidence="尾随换行一致性锁：bugreport_trailing_newline_wbtest.mbt",
      ts="2026-10-26T00:00:02Z",
    ) {
    Ok(_) => ()
    Err(m) => {
      fail("bug_fix 失败: " + m)
      return
    }
  }
  let nb = tnl_trailing_newlines(bug_read_text(d))
  if na != nb {
    fail(
      "两条写入路径尾随换行不一致：report_bug=" +
      na.to_string() +
      " / bug_fix(" +
      bid +
      ")=" +
      nb.to_string() +
      " ⇒ 又回到「同一语义两处实现、只修一处」的原始缺陷形状",
    )
  }
  if nb != 1 {
    fail("bug_fix 后末尾换行 = " + nb.to_string() + "，应为 1")
  }
}
