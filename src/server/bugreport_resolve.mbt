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
/// BUG-4 fix: 校验 run_check 的 workdir 合法。
/// 规则：拒绝空串/含 ".." / 绝对路径（盘符、前导分隔符）。
/// 注：当前未做严格子树匹配（需 path.resolve），基础拦截已覆盖最危险场景。
pub fn run_check_workdir_ok(workdir : String, project_dir : String) -> Bool {
  if workdir.is_empty() {
    return false
  }
  if workdir.contains("..") {
    return false
  }
  let c0 = workdir[0]
  if c0 == '/' || c0 == '\\' {
    return false
  }
  if workdir.length() >= 2 && workdir[1] == ':' {
    return false
  }
  true
}
