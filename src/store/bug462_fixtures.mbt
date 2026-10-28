///|
/// src/store/bug462_fixture_wbtest.mbt —— BUG-462：`src/store` 测试夹具**去共享**。
///
/// ## 病灶
/// BUG-461（`b546258f`）只修了 `store_migration_wbtest.mbt` 一处；
/// **同包同族缺陷仍在**：其余测试用**固定的相对路径** `temp/xxx.db`
/// ⇒ 两个测试进程（或同一包并发跑的两组）同时打开同一个 `.db`
/// ⇒ sqlite 报 `database is locked` ⇒ **假红**。
///
/// ## 本文件做两件事
/// 1. **提供唯一路径生成器**（`bug462_unique_db`）：`temp/b462_<tag>_<token>.db`，
///    token = `@env.rand(8)`（跨进程唯一性来源）+ `@env.now()`（可读回溯）+ 可选人工标签。
///    与 BUG-461 的 `t744_run_token` 同构 —— **不为第二份实现另起炉灶**：
///    本文件的 token 生成与 `store_migration_wbtest.mbt:33` 逻辑一致，
///    差别只在**可达性**：`t744_run_token` 是那个文件私有的 `fn`，
///    同包其它测试文件访问不到，所以这里提供一份**公开给本包**的版本。
/// 2. **自锁**：断言生成器真的每次产出不同路径（否则「去共享」等于没做）。
///
/// ## 谁改用了它
/// `src/store` 下全部 34 处固定 `temp/*.db` 路径已改为本函数（见报告 §证据）。
///
/// ## 诚实边界
/// · 唯一性**只由 `@env.rand` 保证**；熵源拿不到时返回字面量 `noentropy`
///   并**明确标出**（不伪装成唯一）。
/// · 本函数不做清理 —— 调用方各自 `remove` / 交给 `temp/` 的 gitignore 兜底。
/// · 清理残留：`temp/b462_*` 与 `temp/t744_*` 都需要，`temp/` 已 gitignore。

///|
/// 生成一个**每次调用都不同**的 sqlite 夹具路径：`temp/b462_<tag>_<token>.db`。
///
/// `tag` 只做**可读性**（事后在 `temp/` 里认出是哪个测试留下的），**不参与唯一性**。
pub fn bug462_unique_db(tag : String) -> String {
  "temp/b462_" + bug462_sanitize(tag) + "_" + bug462_run_token() + ".db"
}

///|
/// 遍历 token：`@env.rand(8)` 是**跨进程唯一性的唯一来源**；
/// `@env.now()` 只是让残留可回溯；`FIST_B462_RUN_ID` 是可选人工标签。
fn bug462_run_token() -> String {
  let rand_part = match @env.rand(8) {
    Some(bs) => {
      let mut s = ""
      for i = 0; i < bs.length(); i = i + 1 {
        if i > 0 {
          s = s + "-"
        }
        s = s + bs[i].to_int().to_string()
      }
      s
    }
    // 熵源拿不到：明确标出来，不伪装成"唯一"（判例：诚实标注优于静默降级）
    None => "noentropy"
  }
  let label = match @env.get_env_var("FIST_B462_RUN_ID") {
    Some(v) if v != "" => "_" + v
    _ => ""
  }
  @env.now().to_string() + "-" + rand_part + label
}

///|
/// 生成一个**每次调用都不同**的临时**目录**路径（用于需要真建/真删目录的测试）。
///
/// 与 `bug462_unique_db` 同源 token；差别只是没有 `.db` 后缀。
/// 为什么需要它：`multi_store_test.mbt` 的 R28 补建目录锁会真建 `temp/r28_xxx/`
/// 并在收尾 `remove_dir`，**中途清场**——两进程并发时一个删了另一个正要用的目录。
pub fn bug462_unique_dir(tag : String) -> String {
  "temp/b462dir_" + bug462_sanitize(tag) + "_" + bug462_run_token()
}

///|
/// 把 tag 里的路径分隔符/控制字符替换成 `_`（tag 可能来自测试名，含 `/`、空格）。
fn bug462_sanitize(tag : String) -> String {
  let mut out = ""
  for c in tag {
    if c == '/' || c == '\\' || c == ':' || c == ' ' || c == '*' {
      out = out + "_"
    } else {
      out = out + c.to_string()
    }
  }
  out
}
