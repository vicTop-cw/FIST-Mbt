/// bugreport_resolve.mbt —— BUG-5 / BUG-4 修复：路径规范化 + workdir 校验
///
/// 纯 MoonBit 实现，js+native 双 target 零依赖。

///|
/// 将相对路径做最小规范化：反斜杠→正斜杠，去尾部斜杠。
/// 已通过 bug_project_dir_ok 校验（无绝对路径/盘符/..）。
pub fn bug_resolve_path(dir : String) -> String {
  let s = dir.replace(old="\\", new="/")
  // 去尾部斜杠（保留 "/" 本身）
  if s.length() > 1 && s.has_suffix("/") {
    s[0:s.length() - 1].to_string()
  } else {
    s
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
