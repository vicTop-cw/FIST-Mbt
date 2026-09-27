/// run_check_guard.mbt —— BUG-4（Round 2 收口）：宿主命令执行面的默认收紧门。
///
/// 为什么需要这一层：`run_check` 是**宿主命令执行能力**（js target 走 node
/// `child_process.spawn`，见 run_check_js.mbt），任何连上本 MCP 端口的客户端都等价于
/// 拿到 server 进程权限。Round 1 只做了 workdir 的基础拦截（bugreport_resolve.mbt 的
/// `run_check_workdir_ok`：拒空/`..`/绝对路径/盘符），既没有 cmd 白名单，还误伤了
/// 合法用法（见下）。本轮补齐两件事：
///   ① cmd 白名单（默认只放项目脚本解释器 + 项目内显式登记的判据脚本，白名单外拒绝）；
///   ② workdir 真正按「项目目录子树」判定（相等或在子树内放行，越界拒绝），
///      并给出**可审的拒绝原因**（说明错在哪、接受什么形态、怎么扩展）。
///
/// 默认白名单**来自实测调用面**（不是拍脑袋）：从 `call_log` 拉 2000 条历史调用，
/// 解析 run_check 的入参（判据脚本 temp/r2_runcheck_surface.py，原始留档
/// temp/r2_calllog_raw.json），真实用过的 cmd 恰为 `moon`(x7)、`python`(x14)、
/// `bash`(x22)、`powershell`(x6)、`D:/Program Files/Git/usr/bin/bash.exe`(x2)；
/// workdir 恰为「任务自己的 project_dir」（含绝对形态 `E:/IDEProjects/AI/Cypy`、
/// `E:\IDEProjects\AI\Cypy`、`E:/IDEProjects/ai/Pentad`、`E:/IDEProjects/AI/Actus`）
/// 或 `.`（当 project_dir 为 `.` 时）。
/// 所以默认白名单必须含 {moon, python, bash, powershell}（外加同类解释器 node/sh/zsh 与
/// 跨平台别名 python3/py/pwsh），且**绝对路径的 workdir == project_dir 必须放行**——
/// 这正是 Round 1 那版拦截会打断的用法（execute_cron.py 就以绝对 project_dir 传 workdir）。
///
/// 边界与诚实声明（写在这里，也写进工具描述）：
///   - 白名单约束的是**可执行文件**，不是**参数**：放行 `bash` 就放行 `bash -c "..."`。
///     本门要收掉的是「任意宿主二进制」这一大类，同时零回归。
///   - 更严格的形态是「默认拒绝 + 显式扩展位」：扩展位只有运维侧能开
///     （环境变量 FIST_RUN_CHECK_ALLOW，逗号分隔），MCP 调用方自传参数**不能**扩权。
///   - laya/github 的 `sh -c` 拼接路径不在本文件射程内（属同类原语加固，另单）。
///   - workdir/project_dir 精确逐段比较（不做大小写折叠）：实测调用面里 workdir 总是
///     由调用方按同一字符串传入（== project_dir），精确比较零回归；放宽只会造成误放行。
///   - **路径口径（BUG-51 统一后）**：`run_check` 的 workdir 相对时按**任务 project_dir**
///     相对解析（`.` 即项目目录本身）；而 `report_bug`/`bug_list` 的 project_dir 是
///     **账本落盘根**，只接受相对 store 根的路径（拒绝绝对/盘符/`..`，防把 bug 账写到
///     项目外）。两者语义不同、规则相反是有意为之，但必须各自写明——旧版没写，
///     照模板用同一个 `.` 跑完整链路会在第 3 步被"形态不一致"打断。
///
/// 纯 MoonBit、零依赖、js+native 同码：判定与执行分离，server.mbt 的 handler 只负责
/// 「问一次 → 拒了就落审计」。

///|
/// 默认放行的宿主命令（按 basename 比对，忽略 Windows 扩展名）。
/// 集合来源见文件头「实测调用面」注释——每一项都能在 call_log 里数出真实调用。
pub fn run_check_default_allow_cmds() -> Array[String] {
  [
    "moon", // 本项目构建/测试判据（moon test/check/fmt/info）
     "node", // JS 运行时（MCP server 本体、JS 侧判据脚本）
     "python", // 实测 x14：scripts/*.py 判据驱动
     "python3", // 同类别名（Linux/WSL 侧）
     "py", // Windows py launcher 别名
     "bash", // 实测 x22（含 Git 的绝对路径 bash.exe x2）
     "sh", // 同类 POSIX shell
     "zsh", // 同类 shell（macOS 默认）
     "powershell", // 实测 x6：Windows 侧判据脚本（native-env.ps1 等）
     "pwsh", // PowerShell Core 别名
  ]
}

///|
/// 运维侧显式扩展位：环境变量 FIST_RUN_CHECK_ALLOW（逗号分隔的命令名或路径）。
/// 只有 server 进程环境能扩，MCP 调用方不能自授权限（默认拒绝 + 显式扩展）。
fn run_check_env_extra_cmds() -> Array[String] {
  let out : Array[String] = []
  match @env.get_env_var("FIST_RUN_CHECK_ALLOW") {
    Some(v) =>
      for seg in v.split(",") {
        let t = seg.to_owned().trim().to_owned()
        if t != "" {
          out.push(t)
        }
      }
    None => ()
  }
  out
}

///|
/// 路径/命令的归一形态：段列表 + 是否绝对 + 盘符 + 是否被 `..` 冲出根。
struct RcPath {
  segs : Array[String]
  absolute : Bool
  drive : String
  escaped : Bool
}

///|
/// 归一路径：反斜杠→正斜杠、去空段与 `.`、按 `..` 回退。
/// 相对路径出现越过根的 `..` 记 escaped=true（越界的主作案形态）。
fn rc_path(s0 : String) -> RcPath {
  // 注意：必须 replace_all——String::replace 只换**第一处**（实测把
  // `E:\IDEProjects\AI\Cypy` 变成 `E:/IDEProjects\AI\Cypy`，段列表整个错位）。
  let s = s0.replace_all(old="\\", new="/")
  let mut drive = ""
  let mut rest = s
  let mut absolute = false
  if s.length() >= 2 && s[1] == ':' {
    // Windows 盘符（E:/ 或 E:\）：盘符连同冒号整体作为根标识
    drive = s[0:2].to_owned()
    rest = s[2:].to_owned()
    absolute = true
  }
  if rest.length() > 0 && rest[0] == '/' {
    absolute = true
  }
  let segs : Array[String] = []
  let mut escaped = false
  for seg in rest.split("/") {
    let name = seg.to_owned()
    if name == "" || name == "." {
      continue
    } else if name == ".." {
      match segs.pop() {
        None => if not(absolute) { escaped = true }
        Some(_) => ()
      }
    } else {
      segs.push(name)
    }
  }
  { segs, absolute, drive, escaped, }
}

///|
/// 用 `/` 连接段列表（不依赖 Array::join，跨版本稳定）。
fn rc_join(segs : Array[String]) -> String {
  let mut out = ""
  for i = 0; i < segs.length(); i = i + 1 {
    if i > 0 {
      out = out + "/"
    }
    out = out + segs[i]
  }
  out
}

///|
/// workdir 是否落在 project_dir 子树内（含相等）。
pub fn run_check_workdir_in_project(
  workdir : String,
  project_dir : String,
) -> Bool {
  match run_check_workdir_denied(workdir, project_dir) {
    None => true
    Some(_) => false
  }
}

///|
/// 越界判定 + **可审的拒绝原因**（None=放行）。文案必须说清「错在哪 + 接受什么形态」，
/// 否则调用方只能读源码猜（BUG-5 记的就是这种文案债）。
pub fn run_check_workdir_denied(
  workdir : String,
  project_dir : String,
) -> String? {
  let proj = if project_dir.trim() == "" { "." } else { project_dir }
  if workdir.trim() == "" {
    return Some(
      "run_check: workdir 为空。接受与任务 project_dir(=\{proj}) 同形态的路径：项目目录本身、其子目录（如 \{proj}/scripts），或 project_dir 为相对时传 `.`",
    )
  }
  let w = rc_path(workdir)
  let p = rc_path(proj)
  if w.escaped {
    return Some(
      "run_check: workdir=\{workdir} 含越出根目录的 `..`（BUG-4 收口：拒绝上跳）。只接受项目目录 \{proj} 本身或其子树内的目录",
    )
  }
  // BUG-51（口径统一）：**相对 workdir 一律按任务 project_dir 相对解析**，与 project_dir
  // 是绝对还是相对无关——旧版在这里判"形态不一致"直接拒，导致同一条链路上
  // report_bug(project_dir='.') 能过、run_check(workdir='.') 被拒（模板第 3 步必卡）。
  // 安全性不降：上面的 escaped 已排除 `..` 冲出自身起点，故拼接结果必落在项目子树内；
  // 反向（绝对 workdir + 相对 project_dir）仍然拒——相对根的真实位置取决于 server cwd，
  // 无法判定绝对路径归属，放开就是拿"不知道"当"在里面"。
  if not(w.absolute) && p.absolute {
    return None
  }
  if w.absolute != p.absolute {
    return Some(
      "run_check: workdir=\{workdir} 是绝对路径，而任务 project_dir=\{proj} 是相对形态，无法判定其归属（相对根的真实位置取决于 server cwd）。两条出路：① workdir 改传相对路径（按任务 project_dir 相对，`.` 即项目目录本身）；② 发布任务时就把 project_dir 记成绝对路径",
    )
  }
  if w.drive != p.drive {
    return Some(
      "run_check: workdir=\{workdir} 与项目不同根（workdir 盘符=\{w.drive} 项目盘符=\{p.drive}）。只接受项目目录 \{proj} 所在根下的路径",
    )
  }
  if p.segs.length() > w.segs.length() {
    return Some(
      "run_check: workdir=\{workdir} 不在项目目录 \{proj} 子树内（比项目根还浅）。只接受项目目录本身或其子孙目录",
    )
  }
  for i = 0; i < p.segs.length(); i = i + 1 {
    if p.segs[i] != w.segs[i] {
      return Some(
        "run_check: workdir=\{workdir} 不在项目目录 \{proj} 子树内（第 \{i + 1} 段即偏离）。只接受项目目录本身或其子孙目录",
      )
    }
  }
  None
}

///|
/// 真正给子进程当 cwd 的路径（BUG-51）：守卫放行相对 workdir 之后，执行面必须**用它解析后的
/// 绝对形态**，否则 `workdir='.'` 会落到 server cwd 而不是任务项目目录——判据说"在里面"，
/// 执行却在别处，那比拒绝更糟。同形态调用（绝对/绝对、相对/相对）逐字返回原值，零回归。
pub fn run_check_effective_workdir(
  workdir : String,
  project_dir : String,
) -> String {
  let proj = if project_dir.trim() == "" { "." } else { project_dir }
  let w = rc_path(workdir)
  let p = rc_path(proj)
  if not(w.absolute) && p.absolute && not(w.escaped) {
    let segs = p.segs.copy()
    for s in w.segs {
      segs.push(s)
    }
    let tail = rc_join(segs)
    if p.drive == "" {
      "/" + tail
    } else {
      p.drive + "/" + tail
    }
  } else {
    workdir
  }
}

///|
/// ASCII 大小写折叠（只在码元上做 [A-Z] → [a-z]；不引入 unicode 依赖。
/// 边界值直接取字符串下标（`"A"[0]`）而非字面量后缀，避免版本间字面量类型差异）。
fn rc_u16_lower(c : UInt16) -> UInt16 {
  let up_a = "A"[0]
  let up_z = "Z"[0]
  let lo_a = "a"[0]
  if c >= up_a && c <= up_z {
    c + (lo_a - up_a)
  } else {
    c
  }
}

///|
/// 大小写不敏感后缀比较（Windows 扩展名 .exe/.EXE 一视同仁）。
fn rc_ci_suffix(s : String, ext : String) -> Bool {
  let n = s.length()
  let m = ext.length()
  if m > n {
    return false
  }
  let mut ok = true
  for i = 0; i < m && ok; i = i + 1 {
    if rc_u16_lower(s[n - m + i]) != rc_u16_lower(ext[i]) {
      ok = false
    }
  }
  ok
}

///|
/// 取命令的 basename 并去掉 Windows 可执行扩展名（bash.exe → bash）。
fn rc_cmd_basename(cmd : String) -> String {
  let p = rc_path(cmd)
  let base = if p.segs.length() > 0 {
    p.segs[p.segs.length() - 1]
  } else {
    cmd.trim().to_owned()
  }
  let exts : Array[String] = [".exe", ".com", ".bat", ".cmd"]
  let mut stem = base
  for ext in exts {
    if rc_ci_suffix(base, ext) {
      stem = base[0:base.length() - ext.length()].to_owned()
      break
    }
  }
  stem
}

///|
/// cmd 是否允许执行（薄封装，便于断言）。
pub fn run_check_cmd_allowed(cmd : String, allow_extra : Array[String]) -> Bool {
  match run_check_cmd_denied(cmd, allow_extra) {
    None => true
    Some(_) => false
  }
}

///|
/// 白名单外判定 + 拒绝原因（None=放行）。规则：
///   ① basename ∈ 默认白名单 ∪ 运维扩展位（FIST_RUN_CHECK_ALLOW）∪ 调用方登记的扩展；
///   ② 或 cmd 是**项目内的相对可执行路径**（非绝对、不上跳、至少一层目录）——
///      即「显式登记的判据命令」，如 `scripts/check.sh`、`_build/js/.../judge`。
pub fn run_check_cmd_denied(
  cmd : String,
  allow_extra : Array[String],
) -> String? {
  if cmd.trim() == "" {
    return Some(
      "run_check: cmd 为空。要给判据请给项目脚本解释器（moon/node/python/bash/powershell 之一）",
    )
  }
  let p = rc_path(cmd)
  let base = rc_cmd_basename(cmd)
  // 三层放行来源（默认白名单 / 运维环境变量 / 调用方显式登记）。用嵌套遍历而不是数组
  // 拼接：跨 MoonBit 版本的 Array 追加算子不稳定，少一个依赖点少一处坑。
  let groups : Array[Array[String]] = [
    run_check_default_allow_cmds(),
    run_check_env_extra_cmds(),
    allow_extra,
  ]
  for group in groups {
    for a in group {
      let aa = a.trim().to_owned()
      if aa == "" {
        continue
      }
      // 扩展位可写命令名（git）或路径（/usr/bin/git）：按同一 basename 规则比对；
      // 也接受逐字全路径登记（同名命令需要精确区分时）
      if base == rc_cmd_basename(aa) || cmd == aa {
        return None
      }
    }
  }
  // 项目内显式登记的判据脚本：相对、不上跳、至少一层目录
  if not(p.absolute) && not(p.escaped) && p.segs.length() >= 2 {
    return None
  }
  let allow_txt = rc_join(run_check_default_allow_cmds())
  Some(
    "run_check: cmd=\{cmd}（basename=\{base}）不在宿主命令白名单内（BUG-4 收口）。默认允许：\{allow_txt}（集合来源=call_log 实测调用面，见 src/server/run_check_guard.mbt 头注）。扩展方式：① 把判据脚本放进项目目录、按 `scripts/xxx.sh` 这种带目录的相对路径调用；② 运维侧设环境变量 FIST_RUN_CHECK_ALLOW=git,cargo 追加（调用方参数不能给自己扩权）",
  )
}

///|
/// 守卫摘要（供审计 detail / 工具描述同源自洽）。
pub fn run_check_guard_note() -> String {
  let allow_txt = rc_join(run_check_default_allow_cmds())
  "run_check 受 BUG-4 收口约束：cmd 白名单（默认 \{allow_txt}；运维扩展位 FIST_RUN_CHECK_ALLOW）+ workdir 必须在任务 project_dir 子树内（相对 workdir 按 project_dir 相对解析，`.` 即项目目录本身；BUG-51 统一口径）；被拒尝试写进审计（进程内 audit_log + 跨进程 call_log）"
}
