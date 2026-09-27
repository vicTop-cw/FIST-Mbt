/// run_check_guard_test.mbt —— BUG-4（Round 2 收口）回归测试：宿主命令执行面。
///
/// 钉住两件事（摘掉任一修复都会变红）：
///   ① cmd 白名单**默认收紧**：实测调用面用到的解释器必须仍然能跑（零回归锁），
///      白名单外的任意宿主二进制必须被拒且给出扩展出路（否则=默认放行）；
///   ② workdir 按 project_dir 子树判定：绝对 project_dir 本身必须放行
///      （Round 1 版一律拒绝对路径，正是这里会红），越界/上跳/跨盘必须拒。

///|
/// 带诊断的断言（仓库里 assert 的 label/message 参数跨版本不稳，故用 abort 传话）。
fn must(cond : Bool, msg : String) -> Unit {
  if cond {
    ()
  } else {
    abort(msg)
  }
}

///|
test "BUG-4 零回归锁：实测调用面（call_log 直方图）的每个 cmd 仍必须放行" {
  // 这组值逐个来自 temp/r2_calllog_raw.json 的真实 run_check 调用（见 guard 文件头注）。
  // 若有人把默认白名单改窄（或改成"只允许 moon"），这里立刻红。
  let measured : Array[String] = [
    "moon", "python", "bash", "powershell", "D:/Program Files/Git/usr/bin/bash.exe",
    "E:\\Program Files\\Git\\usr\\bin\\bash.exe",
  ]
  for cmd in measured {
    must(
      run_check_cmd_allowed(cmd, []),
      "实测调用面 cmd 被误拒: " + cmd,
    )
  }
  // 同类项目脚本解释器（文档承诺的"项目脚本解释器"集合）
  for cmd in ["node", "python3", "py", "sh", "zsh", "pwsh", "/usr/bin/python3"] {
    must(run_check_cmd_allowed(cmd, []), "脚本解释器被误拒: " + cmd)
  }
}

///|
test "BUG-4 默认收紧：白名单外命令必须被拒，且文案给出可用扩展出路" {
  // 摘掉白名单（改成默认放行）→ 这一组全部变红
  for cmd in ["rm", "curl", "reg", "certutil", "cmd", "echo test", "nc"] {
    must(!run_check_cmd_allowed(cmd, []), "白名单外命令被放行: " + cmd)
  }
  match run_check_cmd_denied("rm", []) {
    None => abort("rm 未被拒（白名单失效）")
    Some(reason) => {
      // 拒绝必须可审：说清是白名单、并告知两条扩展路径（不只说"不行"）
      must(
        reason.contains("白名单"),
        "拒绝文案未说明是白名单问题: " + reason,
      )
      must(
        reason.contains("FIST_RUN_CHECK_ALLOW"),
        "拒绝文案未给出扩展位: " + reason,
      )
    }
  }
}

///|
test "BUG-4 显式登记：项目内相对判据脚本放行，裸名/越界脚本拒" {
  // 「显式登记的判据命令」= 放在项目目录里的相对路径脚本
  assert_true(run_check_cmd_allowed("scripts/check.sh", []))
  assert_true(run_check_cmd_allowed("_build/js/debug/entry/main/index.js", []))
  // 裸文件名不算登记（可能是 PATH 上的任意二进制），上跳的更不行
  assert_false(run_check_cmd_allowed("judge.sh", []))
  assert_false(run_check_cmd_allowed("../scripts/evil.sh", []))
  assert_false(run_check_cmd_allowed("./evil", []))
}

///|
test "BUG-4 扩展位：调用方显式登记才生效，且不改变默认集合（默认拒绝 + 显式扩展）" {
  assert_false(run_check_cmd_allowed("git", []))
  assert_true(run_check_cmd_allowed("git", ["git"]))
  // 登记路径形态也认（运维常写绝对路径）
  assert_true(run_check_cmd_allowed("git", ["/usr/bin/git"]))
  // 登记不能顺带放开别人
  assert_false(run_check_cmd_allowed("cargo", ["git"]))
  // 默认集合本身被钉住（改了要同步文档/测试，不能漂）
  assert_eq(run_check_default_allow_cmds().length(), 10)
}

///|
test "BUG-4 workdir：绝对 project_dir 本身必须放行（Round 1 版在这里会红）" {
  // 实测调用面 38/51 次就是 workdir == 任务的绝对 project_dir
  let abs = "E:/IDEProjects/AI/Cypy"
  assert_true(run_check_workdir_in_project(abs, abs))
  assert_true(run_check_workdir_in_project("E:\\IDEProjects\\AI\\Cypy", abs))
  assert_true(run_check_workdir_in_project(abs + "/sub", abs))
  assert_true(run_check_workdir_in_project(abs + "/scripts/../tests", abs))
  // 同盘但不在子树内 → 拒
  assert_false(run_check_workdir_in_project("E:/IDEProjects/AI/Pentad", abs))
  // 靠 `..` 跳出项目 → 拒
  assert_false(run_check_workdir_in_project(abs + "/../Pentad", abs))
  // 跨盘 → 拒
  assert_false(run_check_workdir_in_project("D:/Windows", abs))
  // 绝对 workdir 配相对 project_dir（形态不一致，无法判定归属）→ 拒
  assert_false(run_check_workdir_in_project("E:/IDEProjects/AI/Cypy", "."))
}

///|
test "BUG-4 workdir：相对 project_dir 下 `.` 与子目录放行、上跳与绝对越界拒" {
  assert_true(run_check_workdir_in_project(".", "."))
  assert_true(run_check_workdir_in_project("./", "."))
  assert_true(run_check_workdir_in_project("scripts", "."))
  assert_true(run_check_workdir_in_project("temp/r2_x/db", "."))
  assert_false(run_check_workdir_in_project("../etc", "."))
  assert_false(run_check_workdir_in_project("..", "."))
  assert_false(run_check_workdir_in_project("", "."))
  assert_false(run_check_workdir_in_project("/", "."))
  // 相对 project_dir 的子树同样成立（temp/proj 下的任务）
  assert_true(run_check_workdir_in_project("temp/proj", "temp/proj"))
  assert_true(run_check_workdir_in_project("temp/proj/scripts", "temp/proj"))
  assert_false(run_check_workdir_in_project(".", "temp/proj"))
  assert_false(run_check_workdir_in_project("temp/other", "temp/proj"))
}

///|
test "BUG-4 workdir 拒绝文案必须自带出路（说清接受什么形态，不让调用方读源码猜）" {
  match run_check_workdir_denied("../etc", ".") {
    None => abort("上跳 workdir 未被拒")
    Some(r) => {
      must(r.contains("子树"), "文案未说明子树规则: " + r)
      must(r.contains(".."), "文案未点出越界形态: " + r)
    }
  }
  // 空 project_dir 视为 `.`（server cwd 子树），不能变成"什么都放行"
  assert_true(run_check_workdir_in_project("scripts", ""))
  assert_false(run_check_workdir_in_project("../scripts", ""))
  // 守卫摘要与工具描述同源
  let note = run_check_guard_note()
  assert_true(note.contains("FIST_RUN_CHECK_ALLOW"))
  assert_true(note.contains("子树"))
}

///|
/// BUG-51 成对锁：路径口径统一后，"同一个相对根跑完整链路"必须能走通。
/// 修复前这三条 ALLOW 全红（`.` 配绝对 project_dir 被"与项目不同根"打断，
/// 正是模板第 3 步卡住的位置）；反向的 REJECT 若被放宽则是真漏洞。
test "BUG-51 相对 workdir 按任务 project_dir 解析：`.` 与子目录放行、上跳仍拒" {
  let abs = "E:/IDEProjects/AI/FIST-Mbt"
  // ALLOW：合法用法（含"丑但在树内"——只测拒绝侧会把过严实现也判成通过）
  assert_true(run_check_workdir_in_project(".", abs))
  assert_true(run_check_workdir_in_project("scripts", abs))
  assert_true(run_check_workdir_in_project("src/../scripts", abs))
  // REJECT：冲出自身起点（拼接后"看起来在里面"的唯一作案形态）
  assert_false(run_check_workdir_in_project("../../etc", abs))
  assert_false(run_check_workdir_in_project("a/../../b", abs))
  // REJECT：相对 project_dir 承载不了绝对 workdir（真实位置取决于 server cwd）
  assert_false(run_check_workdir_in_project(abs, "."))
  // 零回归：相对/相对仍是子树判定，`.` 不在 temp/proj 里面
  assert_false(run_check_workdir_in_project(".", "temp/proj"))
  assert_true(run_check_workdir_in_project("temp/proj", "temp/proj"))
}

///|
/// BUG-51：守卫放行相对 workdir 之后，真正 spawn 的 cwd 必须是归一后的绝对形态。
/// 只改判定不改执行面 = 判据说"在项目里"而进程跑在 server cwd，比拒绝更糟。
test "BUG-51 执行面 cwd 归一：混形态给绝对路径，同形态逐字不动" {
  let abs = "E:/IDEProjects/AI/FIST-Mbt"
  assert_eq(run_check_effective_workdir(".", abs), abs)
  assert_eq(run_check_effective_workdir("scripts", abs), abs + "/scripts")
  assert_eq(run_check_effective_workdir("temp/r2/../x", abs), abs + "/temp/x")
  // 反斜杠绝对 project_dir 同样归一（实测调用面里有 E:\... 形态）
  assert_eq(
    run_check_effective_workdir("scripts", "E:\\IDEProjects\\AI\\FIST-Mbt"),
    abs + "/scripts",
  )
  // 同形态调用逐字返回原值 ⇒ 既有 38/51 次绝对用法零回归
  assert_eq(run_check_effective_workdir(abs, abs), abs)
  assert_eq(
    run_check_effective_workdir("temp/proj/scripts", "temp/proj"),
    "temp/proj/scripts",
  )
  // 被守卫拒掉的形态不改写（该拿不到执行机会）
  assert_eq(run_check_effective_workdir("../../etc", abs), "../../etc")
}

///|
test "BUG-51 绝对 workdir 配相对 project_dir：拒绝文案点名两条出路" {
  match run_check_workdir_denied("E:/x/y", ".") {
    None => abort("绝对 workdir + 相对 project_dir 未被拒")
    Some(r) => {
      must(r.contains("相对"), "文案未说明形态差异: " + r)
      must(r.contains("出路"), "文案未给出可执行出路: " + r)
      // 出路 ① 就是本次统一的口径：相对 workdir 按任务 project_dir 相对
      must(
        r.contains("project_dir 相对"),
        "文案未指认统一后的口径: " + r,
      )
    }
  }
}
