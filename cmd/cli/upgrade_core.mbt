///|
/// FIST-Mbt `--upgrade` 纯逻辑核心（阶段 1 · 只读检测）
///
/// 设计（见 docs/2026-10-11-fist-upgrade-design.md §4-6）：
///   1) `parse_version` / `cmp_version` 为纯函数，零 IO，可白盒单测；
///   2) `latest_tag` 走 `upgrade_js`/`upgrade_native` 双 target（与 github_gitcode
///      的 js/native 分层同一口径）；
///   3) **关键**：版本比较按三段整数比，绝不按浮点——`0.3.10 > 0.3.9` 是硬要求，
///      踩浮点会得出 `0.3.10 < 0.3.9`（十进位陷阱）。
/// 阶段 1 只做检测，不写盘、不下载、不替换。

///|
/// 解析 "major.minor.patch[-pre][+build]" → (major, minor, patch, 是否为 pre-release)。
/// 容忍：可选 v/V 前缀、pre-release/build 后缀。
/// 三段缺一或任一非整数 → None。
/// 第四元 is_pre：`-alpha1` 之类为 true——按 semver 应排同号正式版之下，
/// 若不区分会把「有 pre-release 的旧版」误判成等于正式版（假绿风险）。
fn parse_version(s : String) -> (Int32, Int32, Int32, Bool)? {
  let mut core = s.trim().to_owned()
  if core.length() > 0 && (core[0] == 'v' || core[0] == 'V') {
    core = core[1:core.length()].to_owned()
  }
  let is_pre = has_pre_release(core)
  let parts = core.split(".").collect()
  if parts.length() != 3 {
    return None
  }
  let major = match parse_num(strip_suffix(parts[0].to_owned())) {
    Some(v) => v
    None => return None
  }
  let minor = match parse_num(strip_suffix(parts[1].to_owned())) {
    Some(v) => v
    None => return None
  }
  let patch = match parse_num(strip_suffix(parts[2].to_owned())) {
    Some(v) => v
    None => return None
  }
  Some((major, minor, patch, is_pre))
}

///|
/// 是否有 pre-release 后缀：去掉 `+build` 元数据（不参与优先级）后仍含 `-` 即 true。
fn has_pre_release(core : String) -> Bool {
  let base = core.split("+").collect()[0].to_owned()
  match base.find("-") {
    Some(_) => true
    None => false
  }
}

///|
/// 截掉 pre-release / build 后缀（`-alpha1` / `+meta`），只留数字段。
/// split 无分隔符时返回单元素，取 `[0]` 恒等于自身——无需 index_of。
fn strip_suffix(s : String) -> String {
  let dash = s.split("-").collect()
  let base = dash[0].to_owned()
  let plus = base.split("+").collect()
  plus[0].to_owned()
}

///|
/// 字符串 → 非负整数（digit 逐位累加）；含非数字或空串回 None。
/// core 未提供 String→Int 解析，这里手写（仅接受纯 ASCII 数字）。
fn parse_num(s : String) -> Int32? {
  if s.length() == 0 {
    return None
  }
  let zero = '0'.to_int()
  let nine = '9'.to_int()
  let mut n = 0
  let mut i = 0
  while i < s.length() {
    let c = s[i].to_int()
    if c >= zero && c <= nine {
      n = n * 10 + (c - zero)
      i = i + 1
    } else {
      return None
    }
  }
  Some(n)
}

///|
/// 语义版本比较：a 高于 b 回 1、相等回 0、低于回 -1。
/// 返回 Result：任一版本解析失败回 Err（**绝不回 0 假绿**——R7 不假绿）。
/// pre-release 规则（semver）：major/minor/patch 相同时，带 pre-release 的一方更低。
fn cmp_version(a : String, b : String) -> Result[Int32, String] {
  let va = parse_version(a)
  let vb = parse_version(b)
  match (va, vb) {
    (Some((a0, a1, a2, apre)), Some((b0, b1, b2, bpre))) =>
      if a0 != b0 {
        if a0 > b0 {
          Ok(1)
        } else {
          Ok(-1)
        }
      } else if a1 != b1 {
        if a1 > b1 {
          Ok(1)
        } else {
          Ok(-1)
        }
      } else if a2 != b2 {
        if a2 > b2 {
          Ok(1)
        } else {
          Ok(-1)
        }
      } else if apre != bpre {
        // 数字段全同：无 pre-release 的正式版更高；两边都有 pre-release 视为同级
        if apre {
          Ok(-1)
        } else {
          Ok(1)
        }
      } else {
        Ok(0)
      }
    _ =>
      Err(
        "版本号无法解析（不是 major.minor.patch 三段数字）：a=\{a} b=\{b}",
      )
  }
}

///|
/// 探测远端最新稳定版 tag（去 v 前缀）。
/// js target 走真 HTTP；native target 走 stub 返 Err（与 github_gitcode 同口径）。
/// 失败回 Err（含网络/API/解析任一环节），**绝不静默回空串假绿**。
/// 说明：`upgrade_fetch_latest`（upgrade_js/upgrade_native）已是 `Result[String,String]`
/// 且已完成 `{ok,tag,error}` 解包——这里**只透传，不再二次解析**。
/// 注意：`upgrade_fetch_latest` 是 async fn，从 async fn 里调用它拿到的是已 resolve 的
/// Result（MoonBit async 组合），**不能再 `.wait()`**——`.wait()` 只用于 foreign Promise。
pub async fn latest_tag(
  repo : String,
  base_url : String,
  timeout_ms : Int32,
) -> Result[String, String] {
  upgrade_fetch_latest(repo, base_url, timeout_ms)
}

///|
/// ========== 阶段 B/C（真写盘）编排纯逻辑 ==========
///
/// 分层：本文件的函数只做**决策与编排**（版本比较、备份名、路径分支、失败还原），
/// 真正的 IO（读已装版本 / 下载安装器 / 备份 / 换入 / 自检 / 写 VERSION / 回滚）
/// 全部走 `upgrade_io`（upgrade_js 真实现 / upgrade_native stub 返 Err）。
/// 失败一律 Err 回传、由 `run_upgrade` 映射 rc=3——**绝不假绿**（R7）。

///|
/// 备份文件名：`fist-mbt.js.bak-<L>`（与 `fist-mbt.js` 同目录同卷，copy 后自检失败可还原）。
fn backup_name(bak_ver : String) -> String {
  "fist-mbt.js.bak-" + bak_ver
}

///|
/// BUG-C：计算「取最新版 tag」的 URL（纯函数、零 IO，白盒可测）。
///  * `base_url` 非空 → `{base_url}/releases/latest`（内网镜像，形状与 GitHub API 兼容）；
///  * `base_url` 空 → GitHub API `repos/{repo}/releases/latest`。
/// 放这里（而非 upgrade_js.mbt）是因为它跨 target 通用，wbtest 在 native/js 都要能编译。
pub fn latest_url(repo : String, base_url : String) -> String {
  let b = base_url.trim().to_owned()
  if b.length() > 0 {
    let trimmed = if b.has_suffix("/") {
      b[0:b.length() - 1].to_owned()
    } else {
      b
    }
    return "\{trimmed}/releases/latest"
  }
  "https://api.github.com/repos/\{repo}/releases/latest"
}

///|
/// 要不要进写盘流程（纯逻辑，可白盒锁）：
///   `--check`（check_only=true）永不写盘——阶段 A 只读；
///   否则**仅当** `远端 > 本地`（cmp>0）才进入阶段 B/C。
<<<<<<< HEAD
fn should_upgrade(cmp : Int32, check_only : Bool) -> Bool {
=======
fn should_upgrade(cmp : Int, check_only : Bool) -> Bool {
>>>>>>> 9099e060 (fix(idiom): 清零 0020 deprecated 的 not(x) 子族 203 处（BUG-344）)
  cmp > 0 && !check_only
}

///|
/// 调 `upgrade_io` 并解包 JSON 回执（永不 abort：调度/解析失败回 Err）。
async fn up_io_j(op : String, payload : Json) -> Result[Json, String] {
  upgrade_io(op, payload.stringify())
}

///|
/// 从回执 JSON 对象取字符串字段；取不到回 None。
fn field_str(m : Map[String, Json], key : String) -> String? {
  match m.get(key) {
    Some(String(s)) => Some(s)
    _ => None
  }
}

///|
/// 从回执 JSON 对象取布尔字段（Json 布尔形态是 `True`/`False`，不是包装）。
fn field_bool(m : Map[String, Json], key : String) -> Bool? {
  match m.get(key) {
    Some(True) => Some(true)
    Some(False) => Some(false)
    _ => None
  }
}

///|
/// 取失败原因（error 字段优先），拼进可读消息。
fn up_err_msg(m : Map[String, Json], op : String) -> String {
  match field_str(m, "error") {
    Some(e) => "upgrade 步骤 \{op} 失败：\{e}"
    None => "upgrade 步骤 \{op} 失败（回执未给原因）"
  }
}

///|
/// 调 `upgrade_io` 并取回**一个字符串字段**（field 缺字段 / ok≠true 都归 Err）。
async fn up_str(
  op : String,
  payload : Json,
  field : String,
) -> Result[String, String] {
  let j = match up_io_j(op, payload) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  match j {
    Object(m) =>
      match (field_bool(m, "ok"), field_str(m, field)) {
        (Some(true), Some(s)) => Ok(s)
        _ => Err(up_err_msg(m, op))
      }
    _ => Err("upgrade 步骤 \{op} 回执不是 JSON 对象")
  }
}

///|
/// 调 `upgrade_io` 只判成败（`restore` / 无需取值字段的动作）。
async fn up_ok(op : String, payload : Json) -> Result[Unit, String] {
  let j = match up_io_j(op, payload) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  match j {
    Object(m) =>
      match field_bool(m, "ok") {
        Some(true) => Ok(())
        _ => Err(up_err_msg(m, op))
      }
    _ => Err("upgrade 步骤 \{op} 回执不是 JSON 对象")
  }
}

///|
/// 阶段 B/C 主流程（真写盘）。任何一步失败都回 Err、由调用方映射 rc=3。
/// 换入前必先备份、换入后必自检、自检不符必还原——**写盘三保险**。
pub async fn run_upgrade_full(
  remote : String,
  bin_name : String,
  base_url : String,
  no_path : Bool,
) -> Result[String, String] {
  // 第 1 步：定位安装目录（$InstallDir + fist-mbt.js），并确认真装了
  let info = match up_io_j("install_dir", Json::object({})) {
    Ok(j) => j
    Err(e) => return Err(e)
  }
  let mut dir = ""
  let mut js_bin = ""
  let mut js_exists = false
  match info {
    Object(m) =>
      match
        (
          field_str(m, "dir"),
          field_str(m, "js_bin"),
          field_bool(m, "js_exists"),
        ) {
        (Some(d), Some(b), Some(e)) => {
          dir = d
          js_bin = b
          js_exists = e
          // §8：node < 24 直接拒绝（SQLite 后端依赖 node:sqlite，版本过低装起来也跑不通）
          match field_str(m, "node_major") {
            Some(s) =>
              match parse_num(s) {
                Some(n) if n < 24 =>
                  return Err(
                    "需要 Node.js ≥ 24（当前 v\{n}）；请先升级 Node 再执行 upgrade",
                  )
                _ => ()
              }
            None => () // 老安装器无此字段，不阻断
          }
        }
        _ => return Err("upgrade: 定位安装目录的回执缺字段")
      }
    _ => return Err("upgrade: 定位安装目录的回执不是对象")
  }
  if !js_exists {
    return Err(
      "未检测到已安装的 fist-mbt.js（\{js_bin}）；请先运行安装器安装 fist-mbt，再执行 upgrade",
    )
  }
  // 第 2 步：读已装版本（VERSION 优先，否则反解 node version）。读不到＝不可比较，回 3。
  let installed = match
    up_str(
      "read_local",
      Json::object({ "dir": Json::string(dir), "js_bin": Json::string(js_bin) }),
      "version",
    ) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  // 第 2.5 步：用「已装版本」再比一次远端——已装已 >= 远端就不写盘（防重复升级 / 竞态）
  let recheck = match cmp_version(remote, installed) {
    Ok(c) => c
    Err(e) => return Err("upgrade: 版本再比较失败（\{e}）")
  }
  if recheck <= 0 {
    return Ok(
      "已是最新 v\{installed}（运行构建 \{bin_name}）；未做任何替换",
    )
  }
  // 第 3 步：备份旧 JS（备份名 = backup_name(installed)，两处写死同源防漂移），自检失败就靠它还原
  let bak_name = backup_name(installed)
  let backup = match
    up_str(
      "backup",
      Json::object({
        "js_bin": Json::string(js_bin),
        "local": Json::string(installed),
        "bak_name": Json::string(bak_name),
      }),
      "backup",
    ) {
    Ok(v) => v
    Err(e) => return Err("升级前备份失败（不备份不动盘）：\{e}")
  }
  // 第 4 步：下载安装器 install_onecmd.ps1（R12/R14 双栈重试在 JS 侧；失败即回 3）
  let script = match
    up_str(
      "fetch_installer",
      Json::object({
        "version": Json::string(remote),
        "base_url": Json::string(base_url),
      }),
      "path",
    ) {
    Ok(v) => v
    Err(e) =>
      return Err("取不到安装器（未换入，备份保留）：\{e}")
  }
  // 第 5 步：换入（复用安装器 R5/R6/R7 硬化；失败尝试还原备份）
  match
    up_ok(
      "run_installer",
      Json::object({
        "script": Json::string(script),
        "version": Json::string(remote),
        "base_url": Json::string(base_url),
        "no_path": Json::boolean(no_path),
      }),
    ) {
    Ok(_) => ()
    Err(e) => {
      let _ = up_ok(
        "restore",
        Json::object({
          "js_bin": Json::string(js_bin),
          "local": Json::string(installed),
          "bak_name": Json::string(bak_name),
        }),
      )
      return Err("换入失败（已尝试还原备份 v\{installed}）：\{e}")
    }
  }
  // 第 6 步：自检新版本（真实 spawn `node fist-mbt.js version`，不靠自述）
  let new_ver = match
    up_str(
      "verify",
      Json::object({ "js_bin": Json::string(js_bin) }),
      "version",
    ) {
    Ok(v) => v
    Err(e) => {
      let _ = up_ok(
        "restore",
        Json::object({
          "js_bin": Json::string(js_bin),
          "local": Json::string(installed),
          "bak_name": Json::string(bak_name),
        }),
      )
      return Err("自检失败（已还原备份 v\{installed}）：\{e}")
    }
  }
  // 第 7 步：版本符合才写 VERSION；不符合立即还原
  match cmp_version(new_ver, remote) {
    Ok(0) =>
      match
        up_str(
          "write_version",
          Json::object({
            "dir": Json::string(dir),
            "version": Json::string(remote),
          }),
          "path",
        ) {
        Ok(_) =>
          Ok(
            "升级成功：v\{installed} → v\{remote}；VERSION 已写为 \{remote}；备份保留在 \{backup}",
          )
        Err(e) => Err("已换入 v\{remote}，但写 VERSION 失败：\{e}")
      }
    Ok(_) => {
      let _ = up_ok(
        "restore",
        Json::object({
          "js_bin": Json::string(js_bin),
          "local": Json::string(installed),
          "bak_name": Json::string(bak_name),
        }),
      )
      Err(
        "自检版本不符（期望 v\{remote}，实得 v\{new_ver}）；已还原备份 v\{installed}",
      )
    }
    Err(e) => {
      let _ = up_ok(
        "restore",
        Json::object({
          "js_bin": Json::string(js_bin),
          "local": Json::string(installed),
          "bak_name": Json::string(bak_name),
        }),
      )
      Err("自检版本不可比较（\{e}）；已还原备份 v\{installed}")
    }
  }
}
