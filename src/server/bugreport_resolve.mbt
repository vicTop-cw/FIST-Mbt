/// bugreport_resolve.mbt —— BUG-5 / BUG-4 修复：路径规范化 + workdir 校验
///
/// 纯 MoonBit 实现，js+native 双 target 零依赖。

///|
/// 将相对路径做最小规范化：反斜杠→正斜杠，去尾部斜杠。
/// 已通过 bug_project_dir_ok 校验（无绝对路径/盘符/..）。
/// BUG-134 顺手修的半格：这里从前用 `replace`（**只换第一处**），于是 `E:\a\b` 规范化成 `E:/a\b`——
/// 过去的输入都是相对路径（至多一个反斜杠，甚至没有），这条只在把 server cwd 喂进来之后才暴露。
pub fn bug_resolve_path(dir : String) -> String {
  let s = dir.replace_all(old="\\", new="/")
  // 去尾部斜杠（保留 "/" 本身）
  if s.length() > 1 && s.has_suffix("/") {
    s[0:s.length() - 1].to_string()
  } else {
    s
  }
}

///|
/// BUG-134：把 `project_dir` 拼成**可独立审落轨**的绝对落点。
/// 此前 `resolved_path` 直接回显 `bug_resolve_path(project_dir)`，也就是「相对 server cwd 的规范化路径」，
/// 而工具自述写的是「绝对 + normalize」——写错轨时（插件连接器的 cwd 不是仓库根）从回执本身判不出来。
/// `cwd` 传空串表示宿主取不到工作目录，此时退回相对形态（调用面可用同批回显的 `server_cwd` 是否为空看出这一层）。
/// 分隔符统一规范化为正斜杠：Windows 的 `E:\repo` 与相对段 `a/b` 混在一条串里没法逐字对表。
pub fn bug_abs_path(cwd : String, dir : String) -> String {
  let root = bug_resolve_path(cwd)
  let rel = bug_resolve_path(dir)
  if root == "" {
    rel
  } else if rel == "." || rel == "" {
    root
  } else {
    root + "/" + rel
  }
}

///|
/// server 进程自己的工作目录（BUG-134 的「相对哪个根」）。取不到时回空串——
/// 空串本身就是信号，不拿 "." 冒充一个绝对落点。
pub fn bug_server_cwd() -> String {
  match @env.current_dir() {
    None => ""
    Some(d) => bug_resolve_path(d)
  }
}

///|
/// BUG-4 fix（Round 1 最小收口，Round 2 起为**兼容别名**）：run_check 的 workdir 校验。
/// 真正语义已搬到 run_check_guard.mbt 的 `run_check_workdir_in_project`：
///   - Round 1 版一律拒绝绝对路径/盘符，会打断真实调用面（execute_cron.py 与
///     Round 1 流水线都以 workdir == 任务的绝对 project_dir 传参，实测 38/51 次）；
///   - Round 2 版按「project_dir 子树」判定：同形态且在子树内（含相等）放行，
///     `..` 上跳 / 跨盘 / 绝对-相对形态不一致 拒绝。
/// 保留这个名字只为不破坏既有测试与 .mbti 出口；新代码请用 run_check_guard.mbt。
pub fn run_check_workdir_ok(workdir : String, project_dir : String) -> Bool {
  run_check_workdir_in_project(workdir, project_dir)
}
