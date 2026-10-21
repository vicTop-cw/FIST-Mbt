///|
/// `--upgrade` 纯逻辑白盒锁（阶段 1 · 只读检测）。
///
/// 钉两件事：
///   1) `cmp_version` 按三段整数比，**绝不按浮点**——十进位陷阱
///      （`0.10.0 > 0.9.0`，浮点比会得出反结论）；
///   2) 版本号解析失败回 Err，**绝不回 0 假绿**（R7 不假绿）。
/// 与 upgrade_core.mbt 同文件同源：改掉比较算法，这里立刻红。

///|
test "upgrade-1：语义版本比较（三段整数，不是浮点）" {
  assert_eq(cmp_version("0.3.8", "0.3.7"), Ok(1))
  assert_eq(cmp_version("0.3.8", "0.3.8"), Ok(0))
  assert_eq(cmp_version("0.3.7", "0.3.8"), Ok(-1))
  // 十进位陷阱：0.10 > 0.9，浮点比会得出 0.10 < 0.9
  assert_eq(cmp_version("0.10.0", "0.9.0"), Ok(1))
  assert_eq(cmp_version("0.9.0", "0.10.0"), Ok(-1))
  assert_eq(cmp_version("1.0.0", "0.9.9"), Ok(1))
}

///|
test "upgrade-2：容忍 v 前缀与 pre-release/build 后缀" {
  // 去 v 前缀
  assert_eq(cmp_version("v0.3.8", "0.3.7"), Ok(1))
  // pre-release 低于同号正式版
  assert_eq(cmp_version("0.3.8-alpha1", "0.3.8"), Ok(-1))
  // build 元数据不算版本高低（截断后比较）
  assert_eq(cmp_version("0.3.8+build5", "0.3.8"), Ok(0))
}

///|
test "upgrade-3：版本号无法解析必须回 Err，绝不回 0 假绿（R7）" {
  let bad1 = cmp_version("abc", "0.3.8")
  assert_eq(is_err(bad1), true)
  let bad2 = cmp_version("0.3", "0.3.8")
  assert_eq(is_err(bad2), true)
  let bad3 = cmp_version("0.3.x", "0.3.8")
  assert_eq(is_err(bad3), true)
}

///|
fn is_err(r : Result[Int32, String]) -> Bool {
  match r {
    Err(_) => true
    Ok(_) => false
  }
}

///|
/// 阶段 2（真写盘）纯逻辑锁：
///   4) `backup_name`：备份名 = `fist-mbt.js.bak-<L>`，与安装目录同卷（还原靠它）；
///   5) `should_upgrade`：**只对 `远端 > 本地` 且非 `--check` 才进写盘流程**——
///      `--check` 永不写盘；已是最新 / 本地超前都不写盘。

///|
test "upgrade-4：备份名 = fist-mbt.js.bak-<L>（同卷可还原）" {
  assert_eq(backup_name("0.3.7"), "fist-mbt.js.bak-0.3.7")
  assert_eq(backup_name("0.10.0"), "fist-mbt.js.bak-0.10.0")
  // 不带 v 前缀（版本号是纯三段，v 只在 tag 层）
  assert_eq(backup_name("0.3.7-alpha1"), "fist-mbt.js.bak-0.3.7-alpha1")
}

///|
/// BUG-C：`latest_url` 必须尊重 `--base-url`——
/// 给了镜像 base 就走 `{base}/releases/latest`（与 GitHub API 返回形状兼容），
/// 空 base 才走 GitHub API。**改回硬编码 api.github.com，这里立刻红。**
test "upgrade-6：latest_url 尊重 base_url（镜像 /releases/latest）" {
  // 给了 base：走镜像（去尾斜杠，防双斜杠）
  assert_eq(
    latest_url("vicTop-cw/FIST-Mbt", "http://127.0.0.1:8765"),
    "http://127.0.0.1:8765/releases/latest",
  )
  assert_eq(
    latest_url("vicTop-cw/FIST-Mbt", "http://mirror.local/"),
    "http://mirror.local/releases/latest",
  )
  // 空 base：走 GitHub API（upgrade --check 无 --base-url 的默认形态）
  assert_eq(
    latest_url("vicTop-cw/FIST-Mbt", ""),
    "https://api.github.com/repos/vicTop-cw/FIST-Mbt/releases/latest",
  )
  // 纯空白 base 视同未给（不拼出 "/releases/latest" 的畸形 URL）
  assert_eq(
    latest_url("vicTop-cw/FIST-Mbt", "   "),
    "https://api.github.com/repos/vicTop-cw/FIST-Mbt/releases/latest",
  )
}

///|
test "upgrade-5：should_upgrade 只在 远端>本地 且非 --check 时放行写盘" {
  // --check 永不写盘（阶段 1 只读）：即使有升级也不放行
  assert_eq(should_upgrade(1, true), false)
  // 非 --check：远端>本地 才放行
  assert_eq(should_upgrade(1, false), true)
  // 已是最新 / 本地超前：都不写盘
  assert_eq(should_upgrade(0, false), false)
  assert_eq(should_upgrade(-1, false), false)
  // 已是最新 且 --check：双保险不写盘
  assert_eq(should_upgrade(0, true), false)
}
