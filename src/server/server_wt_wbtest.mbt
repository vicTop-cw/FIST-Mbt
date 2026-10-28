// ============================================================================
// WT-02 **worktree 三工具**的实现路径锁（`wt_create` / `wt_destroy` / `wt_status`）
//
// 为什么要这一份：`check_tool_coverage.py` 判 A 面（外壳覆盖）——它扫全仓
// `*_test.mbt` / `*_wbtest.mbt`，要求每个注册在 `server.mbt` 的工具名**至少被一份测试碰过**。
// 合并 PR `feature/web-dashboard-health`（`c61253e5`）带进这三个工具时**没带测试**
// ⇒ 实测 `外壳零覆盖 3 / 159（1.9%）`，判据 FAIL「它们坏了没人知道」。本文件补这一面。
//
// 口径（判例-29「机制格 ≠ 实现路径格」）：本文件锁的是**这三个工具自己的实现路径**——
// 它们各自拼的 `git` 参数、各自的必填 schema、以及**互不串味**（create 不许出现 remove）。
// 只断言「`git worktree` 这件事仓里有人做过」是没有价值的（那是机制格）。
//
// 判例-30 防护：断言前先跳过注释行 —— 否则「把实现改坏、注释还写着」会假绿。
//
// ⚠️ CRLF 坑（实测踩过）：`server.mbt` 是 CRLF。`split("\n")` 切出来的每行尾部带 `\r`，
// 而 `trim()` **不剥 `\r`** ⇒ 精确相等比较（`t == "\"wt_create\","`）恒 false ⇒ 切块返回空串。
// 后果很阴：`wt_05`（断言「块里不含 X」）在空块上**假绿**，另外 5 格才红。
// ⇒ 统一在入口把 `\r` 去掉（`wt_read_src`），后续比较全在 LF 面上做。
// ============================================================================

///|
/// 读 `server.mbt` 并归一化：去注释行（判例-30）+ **去 `\r`**（CRLF 坑）。
fn wt_read_src() -> String {
  let raw = @fs.read_file_to_string("src/server/server.mbt") catch {
    _ => abort("读不到 server.mbt")
  }
  let mut acc = ""
  for line in raw.split("\n") {
    let s = line.to_owned().replace(old="\r", new="")
    let l = s.trim()
    if l.has_prefix("///") || l.has_prefix("//") {
      continue
    }
    acc = acc + s + "\n"
  }
  acc
}

///|
/// 判定「这一行是**下一个工具的名字行**」——即 `server.mbt` 里 `    "<tool_name>",` 的形状。
///
/// ⚠️ 实测踩坑：最初只判「4 空格缩进 + `"` 开头 + `",` 结尾」，结果**工具描述行也长这样**
/// （`    "创建 git worktree（…）…",`）⇒ 块只取到 1 行、全部断言假红/假绿。
/// 加两条**判据性**约束把名字行和描述行分开：工具名 ≤ 40 字符且**不含空格**
/// （描述行要么长、要么含空格；三个工具名 `wt_create`/`wt_destroy`/`wt_status` 都是 9-10 字符）。
fn wt_is_tool_name_line(s : String) -> Bool {
  let t = s.trim()
  s.has_prefix("    \"") &&
  t.has_suffix("\",") &&
  t.length() <= 40 &&
  !t.contains(" ")
}

///|
/// 取某个工具注册块：从 `"<name>",` 那一行起，到**下一个同级工具名行**为止。
///
/// 为什么必须切块：`server.mbt` 有 177 个工具，全局 `contains` 会被别处的同名参数串味
/// （判例-30 同族的「在错误的地方验」）。
fn wt_block(src : String, name : String) -> String {
  let marker = "\"" + name + "\","
  let mut out = ""
  let mut started = false
  for line in src.split("\n") {
    let s = line.to_owned()
    let t = s.trim()
    if !started {
      if t == marker {
        started = true
        out = out + s + "\n"
      }
      continue
    }
    if wt_is_tool_name_line(s) {
      break
    }
    out = out + s + "\n"
  }
  out
}

///|
/// 【WT·锁 1】三个工具都在 `server.mbt` 注册且带 schema。
test "wt_01_three_tools_registered_with_schema" {
  let src = wt_read_src()
  for name in ["wt_create", "wt_destroy", "wt_status"] {
    let blk = wt_block(src, name)
    if blk.length() == 0 {
      abort(name + " 在 server.mbt 里切不到注册块 —— 工具可能被改名/删除")
    }
    if !blk.contains("schema(") {
      abort(name + " 没有 schema —— 工具注册缺 schema 就不可调用")
    }
  }
}

///|
/// 【WT·锁 2】★ `wt_create` 真的拼 `git worktree add`（实现路径格）。
///
/// 同时锁 `detach` 开关：`--detach` 必须**由 `detach` 参数门控**，
/// 不能无条件加（否则调用方要普通 checkout 也拿不到）。
test "wt_02_create_builds_worktree_add" {
  let blk = wt_block(wt_read_src(), "wt_create")
  if !blk.contains("git_args.push(\"worktree\")") {
    abort("wt_create 没有 push(\"worktree\") —— 拼的不是 git worktree 子命令")
  }
  if !blk.contains("git_args.push(\"add\")") {
    abort("wt_create 没有 push(\"add\") —— 拼错了子命令")
  }
  if !blk.contains("git_args.push(\"--detach\")") {
    abort("wt_create 没有 --detach 分支 —— detach=true 会被静默忽略")
  }
  if !blk.contains("if detach {") {
    abort("--detach 不是由 `detach` 参数门控的 —— 无条件加会让普通 create 变成 detached HEAD")
  }
  if !blk.contains("run_check_external(\"git\"") {
    abort("wt_create 没有真跑 git —— 拼完 args 不执行等于没实现")
  }
}

///|
/// 【WT·锁 3】`wt_destroy` 拼 `git worktree remove`，`--force` 由 `force` 门控。
///
/// **`--force` 是无条件删除的后门**：不门控就会把「有未提交改动的 worktree」也删掉。
test "wt_03_destroy_builds_worktree_remove" {
  let blk = wt_block(wt_read_src(), "wt_destroy")
  if !blk.contains("git_args.push(\"remove\")") {
    abort("wt_destroy 没有 push(\"remove\") —— 拼错了子命令")
  }
  if !blk.contains("git_args.push(\"--force\")") {
    abort("wt_destroy 没有 --force 分支 —— force=true 会被静默忽略")
  }
  if !blk.contains("if force {") {
    abort("--force 不是由 `force` 参数门控的 —— 无条件强删会丢未提交改动")
  }
  if !blk.contains("run_check_external(\"git\"") {
    abort("wt_destroy 没有真跑 git")
  }
}

///|
/// 【WT·锁 4】`wt_status` 用 `git worktree list --porcelain`。
///
/// 必须带 `--porcelain`：人类可读格式会随 git 版本变，解析面不稳定
/// （工具描述里承诺的就是 porcelain stdout + 退出码）。
test "wt_04_status_uses_list_porcelain" {
  let blk = wt_block(wt_read_src(), "wt_status")
  if !blk.contains("git_args.push(\"list\")") {
    abort("wt_status 没有 push(\"list\")")
  }
  if !blk.contains("git_args.push(\"--porcelain\")") {
    abort("wt_status 没带 --porcelain —— 人读格式随 git 版本变，解析不稳定")
  }
  if !blk.contains("run_check_external(\"git\"") {
    abort("wt_status 没有真跑 git")
  }
}

///|
/// 【WT·锁 5】三个工具**互不串味**（复制粘贴防护）。
///
/// 实测风险：三块代码结构高度相似，最容易的错是「改名字没改子命令」——
/// `wt_create` 里留下 `remove`、或 `wt_status` 里留下 `add`，都会**语法正确、行为错误**。
///
/// ⚠️ 这一格**必须先证明块非空**，否则空块会让「不含 X」恒真（本次实测就假绿过一次）。
test "wt_05_three_tools_do_not_cross_contaminate" {
  let src = wt_read_src()
  let create_blk = wt_block(src, "wt_create")
  let destroy_blk = wt_block(src, "wt_destroy")
  let status_blk = wt_block(src, "wt_status")
  if create_blk.length() == 0 || destroy_blk.length() == 0 || status_blk.length() == 0 {
    abort("切块为空 ⇒ 本格会空转假绿，先修 wt_block（多半是行尾/缩进漂移）")
  }
  if create_blk.contains("git_args.push(\"remove\")") {
    abort("wt_create 块里出现了 remove —— 复制粘贴串味")
  }
  if destroy_blk.contains("git_args.push(\"add\")") {
    abort("wt_destroy 块里出现了 add —— 复制粘贴串味")
  }
  if status_blk.contains("git_args.push(\"add\")") ||
    status_blk.contains("git_args.push(\"remove\")") {
    abort("wt_status 块里出现了 add/remove —— 复制粘贴串味")
  }
}

///|
/// 【WT·锁 6】必填 schema 与工具描述承诺一致。
///
/// `wt_create` / `wt_destroy` 必须 `project_dir` + `path`；`wt_status` 只要 `project_dir`
/// （它列的是整个仓库的 worktree，没有单个 path 的概念）。
/// 三者都要有**空值前置拒绝**兜住 ⇒ 不许拿空 project_dir 去 spawn。
test "wt_06_required_params_and_empty_guard" {
  let src = wt_read_src()
  let create_blk = wt_block(src, "wt_create")
  let destroy_blk = wt_block(src, "wt_destroy")
  let status_blk = wt_block(src, "wt_status")
  if create_blk.length() == 0 || destroy_blk.length() == 0 || status_blk.length() == 0 {
    abort("切块为空 ⇒ 本格会空转假绿")
  }
  // ① create / destroy 的必填面是 project_dir + path
  if !create_blk.contains("[\"project_dir\", \"path\"]") {
    abort("wt_create 的必填参数不是 [\"project_dir\", \"path\"]")
  }
  if !destroy_blk.contains("[\"project_dir\", \"path\"]") {
    abort("wt_destroy 的必填参数不是 [\"project_dir\", \"path\"]")
  }
  // ② status 的必填面只有 project_dir
  if !status_blk.contains("[\"project_dir\"]") {
    abort("wt_status 的必填参数不是 [\"project_dir\"]")
  }
  // ③ 三者都必须有「空 project_dir 就拒绝」的前置兜底
  if !(create_blk.contains("project_dir == \"\"") && create_blk.contains("必填")) {
    abort("wt_create 没有空值前置拒绝")
  }
  if !(destroy_blk.contains("project_dir == \"\"") && destroy_blk.contains("必填")) {
    abort("wt_destroy 没有空值前置拒绝")
  }
  if !(status_blk.contains("project_dir == \"\"") && status_blk.contains("必填")) {
    abort("wt_status 没有空值前置拒绝")
  }
}
