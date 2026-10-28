/// src/server/wt_tools.mbt —— worktree 沙箱生命周期三工具（wt_create / wt_status / wt_destroy）
///
/// **为什么需要这一层**：`git worktree` 只有三个动词（add / list / remove），它不回答
/// 「这个沙箱现在能不能回收」「删它会不会把没落盘的活一起销毁」「删这条分支会不会丢提交」。
/// 只做薄封装的结果是：调用方拿到的是「目录在」这种**存在性**，不是**生命周期**——于是多 agent
/// 车道里长出一地没人敢删的 worktree，或者反过来把已并入但还有未提交改动的沙箱当垃圾收掉。
///
/// 本文件补的是**账**：开沙箱时落一条清单（`<project>/.fist-mbt/data/wt-<task>.json`，gitignore
/// 面、跨进程可复现），状态由「目录 / git / 时间」三方读数裁决，不靠猜。
///
/// **七档状态机与 `scripts/run_light_wt.py` 的 `classify` 同名同义**（一源四态：Python 那份是
/// CLI/CI 面，本文件是产品面）。同一条 `merged` 在两张脸上必须读出同一种动作，否则无人值守车道
/// 会在一张脸上回收、在另一张脸上保留。
///
/// **判定顺序是承重的**（照 R162 的实测结论）：
///   1. **脏先看**：分支已并入 + 工作树还有未提交改动 ⇒ `blocked`。先判 merged 会让回收把
///      「已并入那条线上还没落盘的活」一起销毁。
///   2. **`idle` 只由账上的创建锚点 `created_sha` 说**，不看年龄、也不靠 git 猜「没动过」：
///      `git merge` 多为 fast-forward，ff 之后主线尖 == 分支尖，已并入的成果会被读成空沙箱；
///      而 `base` 默认是 `HEAD` 这种**活参照**，事后已看不出当年从哪个提交铺的。
///   3. **git 读不到 ⇒ `unknown`**，绝不顺着年龄写成 fresh/stale（读不到 ≠ 读到了）。
///
/// **危险面纪律**：`wt_destroy` 只动**账上登记过**的路径（目录在但不在账上 ⇒ 拒绝，除非显式
/// `force=true`）；分支**默认不删**（删分支不可逆），要删必须显式 `delete_branch=true`，且走
/// `git branch -d`（未并入的分支由 git 自己拒——这条判断不该由我们代劳）。

///|
/// 状态目录（与模型路由/多租户同一条双层目录治理：`<target>/.fist-mbt/data/`，gitignore 面）。
fn wt_state_dir(project_dir : String) -> String {
  project_dir + "/.fist-mbt/data"
}

///|
/// 单个沙箱的账文件路径。task 先过白名单（防 `../` 把账写出目录）。
fn wt_manifest_path(project_dir : String, task : String) -> String {
  // 防御纵深（R105）：本函数原**只靠调用方**先过 `wt_task_ok`（注释写明了，但没强制）。
  // 漏校验一处就能用 `../` 把账读出/写出目录。改为：task 不合规 ⇒ 返回一个
  // **必然不存在**的哨兵路径 —— 读 ⇒ None、写 ⇒ false、删 ⇒ 忽略，越界不可能发生。
  if !wt_task_ok(task) {
    return wt_state_dir(project_dir) + "/__invalid_task__"
  }
  wt_state_dir(project_dir) + "/wt-" + task + ".json"
}

///|
/// 任务 id 白名单：`[A-Za-z0-9_-]{1,64}`。空/超长/含分隔符一律拒（账文件名由它拼）。
pub fn wt_task_ok(task : String) -> Bool {
  let n = task.length()
  if n == 0 || n > 64 {
    return false
  }
  let mut i = 0
  while i < n {
    let c = task[i]
    let ok = (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '_' ||
      c == '-'
    if !ok {
      return false
    }
    i = i + 1
  }
  true
}

///|
/// 路径安全（形状判据，不判存在性）：非空、不含 `..` 段、不以分隔符结尾。
pub fn wt_path_ok(path : String) -> Bool {
  if path.is_empty() {
    return false
  }
  let p = path.replace_all(old="\\", new="/")
  if p.contains("..") {
    return false
  }
  if p.has_suffix("/") {
    return false
  }
  true
}

///|
/// 默认分支名：`wt/<task>`（task 已白名单化 ⇒ 不含空格/`~`/`^`/`:` 这些非法 ref 字符）。
pub fn wt_branch_default(task : String) -> String {
  "wt/" + task
}

///|
/// `Bool?` 的「确认是 true」判定（Option 上直接 `== Some(true)` 会要求 Eq，改用模式匹配）。
fn wt_merged_yes(v : Bool?) -> Bool {
  match v {
    Some(true) => true
    _ => false
  }
}

///|
/// 七档状态机的**纯判定面**（零 IO，供白盒锁；调用方负责先把读数取好）。
///
/// 入参语义：`dirty` = 未提交改动条数，`-1` 表示读不到；`merged` = `Some(true/false)`，
/// `None` 表示 git 给不出结论（分支不存在 / 命令失败）；`age_min` = 距创建锚点的分钟数。
/// 返回 `(state, reason)`——`reason` 是给人读的一句话，不是给机器解析的枚举。
pub fn wt_state_of(
  dir_exists : Bool,
  merged : Bool?,
  dirty : Int,
  age_min : Int,
  ttl_min : Int,
  head_sha : String,
  created_sha : String,
) -> (String, String) {
  // 1) 目录不在：账还在 ⇒ 账是孤儿，可回收
  if !dir_exists {
    return ("abandoned", "worktree 目录不在，账还留着")
  }
  // 2) 读不到不猜
  if dirty < 0 {
    return ("unknown", "沙箱内 git status 读不到，拒绝顺着年龄猜")
  }
  match merged {
    None => return ("unknown", "分支是否并入基线 git 给不出结论（分支不存在或命令失败）")
    Some(_) => ()
  }
  // 3) 脏先看：并入 + 未落盘 ⇒ blocked
  if wt_merged_yes(merged) && dirty > 0 {
    return ("blocked", "分支已并入，但工作树有未提交改动——先落盘再回收")
  }
  // 4) 已并入
  if wt_merged_yes(merged) {
    return ("merged", "分支尖已并入基线")
  }
  // 5) 脏（未并入）
  if dirty > 0 {
    return ("blocked", "工作树有未提交改动")
  }
  // 6) 没动过：只认账上的创建锚点
  if !created_sha.is_empty() && !head_sha.is_empty() && head_sha == created_sha {
    return ("idle", "从创建锚点起一次都没提交过（按账判定，不按年龄）")
  }
  // 7) 超龄 —— ⚠️ ttl 先钳制（R106）：账里/入参给 `ttl_min <= 0` 时，
  // 原来 `age_min > ttl_min` 对任何沙箱恒真 ⇒ **刚创建的沙箱立刻判 stale**（可回收），
  // 等于把活沙箱当垃圾。非正值一律按默认 120 分钟算（宁可留久，不可误收）。
  let eff_ttl = if ttl_min <= 0 { 120 } else { ttl_min }
  if age_min > eff_ttl {
    return ("stale", "超过 TTL 且未并入，属可回收的陈旧沙箱")
  }
  ("fresh", "在用：未并入、未超龄、无未落盘改动")
}

///|
/// 可回收档（无人值守车道的「能收」集合）：merged / stale / abandoned / idle。
/// blocked 与 unknown 都**不在**集合里——前者会丢活，后者会丢证据。
pub fn wt_reclaimable(state : String) -> Bool {
  state == "merged" || state == "stale" || state == "abandoned" || state == "idle"
}

///|
/// JSON 取字符串字段（非对象/非字符串一律空串）。
fn wt_s(j : Json, key : String) -> String {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
}

///|
/// JSON 取整数字段（接受 Number，缺省给 default）。
fn wt_i(j : Json, key : String, default : Int) -> Int {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(Number(n, ..)) => n.to_int()
        _ => default
      }
    _ => default
  }
}

///|
/// 建一条台账 JSON（写盘前的唯一构造点，字段名与 Python 面一致）。
pub fn wt_entry_json(
  task : String,
  path : String,
  branch : String,
  base : String,
  base_sha : String,
  created_sha : String,
  created_at : Int,
  ttl_min : Int,
) -> Json {
  let m : Map[String, Json] = Map([])
  m.set("id", Json::string(task))
  m.set("path", Json::string(path))
  m.set("branch", Json::string(branch))
  m.set("base", Json::string(base))
  m.set("base_sha", Json::string(base_sha))
  m.set("created_sha", Json::string(created_sha))
  m.set("created_at", Json::number(created_at.to_double()))
  m.set("ttl_min", Json::number(ttl_min.to_double()))
  Json::object(m)
}

///|
/// tally：状态 → 计数（回执里的钉读数；空输入返回空对象而不是 null）。
pub fn wt_tally(states : Array[String]) -> Json {
  let m : Map[String, Json] = Map([])
  for s in states {
    let cur = match m.get(s) {
      Some(Number(n, ..)) => n.to_int()
      _ => 0
    }
    m.set(s, Json::number((cur + 1).to_double()))
  }
  Json::object(m)
}

///|
/// 当前墙钟秒（服务端盖章；调用面不接受 now 入参——BUG-33 政策）。
fn wt_now_secs() -> Int {
  (@env.now().reinterpret_as_int64() / 1000L).to_int()
}

///|
/// 从 run_check_external 的结果里取 code（缺省 -1）。
fn wt_code_of(j : Json) -> Int64 {
  match j {
    Object(m) =>
      match m.get("code") {
        Some(Number(n, ..)) => n.to_int().to_int64()
        _ => -1L
      }
    _ => -1L
  }
}

///|
/// 跑一条 git：返回 (ok, code, stdout, stderr)。`ok` 只代表 rc==0；
/// native 构建下 run_check_external 直接 Err ⇒ 统一按「读不到」处理（不假装成功）。
async fn wt_git(
  args : Array[String],
  workdir : String,
  timeout_ms : Int32,
) -> (Bool, Int64, String, String) {
  match run_check_external("git", args, workdir, timeout_ms) {
    Err(e) => (false, -1L, "", e)
    Ok(j) => {
      let code = wt_code_of(j)
      (code == 0L, code, wt_s(j, "stdout"), wt_s(j, "stderr"))
    }
  }
}

///|
/// 读一条账；文件不存在/坏 JSON 一律 `None`（坏账是证据，不覆盖不删除）。
fn wt_load(project_dir : String, task : String) -> Json? {
  let raw = @fs.read_file_to_string(wt_manifest_path(project_dir, task)) catch {
    _ => ""
  }
  if raw.is_empty() {
    return None
  }
  let v = @json.parse(raw) catch { _ => return None }
  Some(v)
}

///|
/// 落一条账（先建目录再写；写失败返回 false，由调用方决定是否降级回执）。
fn wt_save(project_dir : String, task : String, j : Json) -> Bool {
  @fs.create_dir(wt_state_dir(project_dir)) catch { _ => () }
  let ok : Unit? = Some(
    @fs.write_string_to_file(wt_manifest_path(project_dir, task), j.stringify()),
  ) catch {
    _ => None
  }
  ok is Some(_)
}

///|
/// 列全部账（`wt-*.json`），返回 (task, json) 数组；读不到的条目跳过。
fn wt_load_all(project_dir : String) -> Array[(String, Json)] {
  let out : Array[(String, Json)] = []
  let names = @fs.read_dir(wt_state_dir(project_dir)) catch {
    _ => return out
  }
  for name in names {
    if name.has_prefix("wt-") && name.has_suffix(".json") {
      let task = name[3:name.length() - 5].to_owned()
      match wt_load(project_dir, task) {
        Some(j) => out.push((task, j))
        None => ()
      }
    }
  }
  out
}

///|
/// 按路径找账（`wt_destroy` 的安全面：未登记路径默认拒拆）。
fn wt_find_by_path(project_dir : String, path : String) -> (String, Json)? {
  let target = path.replace_all(old="\\", new="/")
  for pair in wt_load_all(project_dir) {
    let p = wt_s(pair.1, "path").replace_all(old="\\", new="/")
    if p == target {
      return Some(pair)
    }
  }
  None
}

///|
/// 解析 `git worktree list --porcelain`：块之间空行分隔，块内 `worktree <path>` / `HEAD <sha>` /
/// `branch refs/heads/<name>` / `detached`。解析是纯函数（白盒可锁）。
pub fn wt_parse_porcelain(stdout : String) -> Array[Json] {
  let out : Array[Json] = []
  let mut path = ""
  let mut head = ""
  let mut branch = ""
  let mut detached = false
  let mut seen = false
  for raw in stdout.split("\n") {
    let l = raw.trim().to_owned()
    if l.is_empty() {
      if seen {
        out.push(wt_porcelain_row(path, head, branch, detached))
      }
      path = ""
      head = ""
      branch = ""
      detached = false
      seen = false
      continue
    }
    seen = true
    if l.has_prefix("worktree ") {
      path = l[9:].to_owned()
    } else if l.has_prefix("HEAD ") {
      head = l[5:].to_owned()
    } else if l.has_prefix("branch ") {
      branch = wt_strip_ref(l[7:].to_owned())
    } else if l == "detached" {
      detached = true
    }
  }
  if seen {
    out.push(wt_porcelain_row(path, head, branch, detached))
  }
  out
}

///|
/// porcelain 的一行 → Json（构造点单一，白盒可对表）。
fn wt_porcelain_row(path : String, head : String, branch : String, detached : Bool) -> Json {
  let m : Map[String, Json] = Map([])
  m.set("path", Json::string(path))
  m.set("head", Json::string(head))
  m.set("branch", Json::string(branch))
  m.set("detached", Json::boolean(detached))
  Json::object(m)
}

///|
/// `refs/heads/<x>` → `<x>`（其它形状原样返回，不猜）。
fn wt_strip_ref(s : String) -> String {
  if s.has_prefix("refs/heads/") {
    s[11:].to_owned()
  } else {
    s
  }
}

///|
/// 路径归一（**仅用于比较**）：`\` → `/`，剥尾部 `/`。
/// **不改大小写**：POSIX 大小写敏感，Windows 上同目录两种大小写极罕见 —— 宁可漏认、不可误认。
fn wt_norm_path(p : String) -> String {
  let s = p.replace_all(old="\\", new="/")
  let mut end = s.length()
  while end > 1 && s[end - 1] == '/' {
    end = end - 1
  }
  s[0:end].to_owned()
}

///|
/// 「目录在但不在账上」——**第 0 条恒为主工作树**（`git worktree list` 的约定：主工作树在最前）。
/// 主工作树是仓库根、不是沙箱；把它算进 `unregistered` 会让**每次 `wt_status` 都报**
/// 「有个没人管的沙箱」——那是假信号，会诱导人去「清理」仓库根。故跳过第 0 条。
pub fn wt_unregistered(parsed : Array[Json], known : Array[String]) -> Array[Json] {
  let out : Array[Json] = []
  let mut idx = 0
  for e in parsed {
    let is_main = idx == 0
    idx = idx + 1
    if !is_main {
      let p = wt_norm_path(wt_s(e, "path"))
      let mut hit = false
      for k in known {
        if wt_norm_path(k) == p {
          hit = true
        }
      }
      if !hit {
        out.push(e)
      }
    }
  }
  out
}

///|
/// `wt_create`：开沙箱 + 落账。
///
/// 参数与 GitHub 主线那份薄封装同名同义（`project_dir` / `path` / `branch` / `detach` /
/// `timeout_ms`），额外可选 `task` / `base` / `ttl_min` —— 后三者是**账**需要的，缺省也能跑
/// （task 缺省取 path 末段，base 缺省 HEAD，ttl 缺省 120 分钟）。
pub async fn wt_create_impl(
  project_dir : String,
  path : String,
  branch : String,
  detach : Bool,
  task : String,
  base : String,
  ttl_min : Int,
  timeout_ms : Int32,
) -> Result[Json, String] {
  if !wt_path_ok(path) {
    return Err("非法 path：空 / 含 .. / 以分隔符结尾 一律拒绝")
  }
  let eff_task = if task.is_empty() { wt_last_segment(path) } else { task }
  if !wt_task_ok(eff_task) {
    return Err("非法 task id：只允许字母/数字/_/-（≤64 字符，账文件名由它拼）")
  }
  if !branch.is_empty() && detach {
    return Err("branch 与 detach 互斥：要么开分支，要么 detached HEAD")
  }
  // R106：ttl_min 必须为正 —— 0/负值会让账一落盘就被判超龄（沙箱刚建就可回收）。
  if ttl_min <= 0 {
    return Err("非法 ttl_min：必须 > 0（分钟；缺省 120）")
  }
  let eff_branch = if detach {
    ""
  } else if branch.is_empty() {
    wt_branch_default(eff_task)
  } else {
    branch
  }
  let eff_base = if base.is_empty() { "HEAD" } else { base }
  // R106：同 task 已有账**且指向别的路径** ⇒ 拒绝。原来 `wt_save` 直接覆盖，
  // 前一个沙箱的账就此消失（目录还在、账没了 ⇒ unregistered）——正是本功能要防的「账对不上」。
  match wt_load(project_dir, eff_task) {
    Some(prev) => {
      let prev_path = wt_s(prev, "path")
      if !prev_path.is_empty() && prev_path != path {
        return Err("该 task 已有账且指向别的路径（task=" + eff_task + ", path=" + prev_path + "）；先 wt_destroy 或换 task")
      }
    }
    None => ()
  }
  let args : Array[String] = ["worktree", "add"]
  if detach {
    args.push("--detach")
  } else {
    args.push("-b")
    args.push(eff_branch)
  }
  args.push(path)
  args.push(eff_base)
  let (ok, code, out, err) = wt_git(args, project_dir, timeout_ms)
  if !ok {
    let m : Map[String, Json] = Map([])
    m.set("ok", Json::boolean(false))
    m.set("path", Json::string(path))
    m.set("code", Json::number(code.to_int().to_double()))
    m.set("stdout", Json::string(out))
    m.set("stderr", Json::string(err))
    m.set("note", Json::string("git worktree add 失败，见 stderr"))
    return Ok(Json::object(m))
  }
  // 创建锚点：沙箱自己的 HEAD（不是 base 的名字——base 是活参照，事后会漂）
  let (hok, _, hout, _) = wt_git(["rev-parse", "HEAD"], path, timeout_ms)
  let created_sha = if hok { hout.trim().to_owned() } else { "" }
  let now = wt_now_secs()
  let entry = wt_entry_json(
    eff_task, path, eff_branch, eff_base, created_sha, created_sha, now, ttl_min,
  )
  let saved = wt_save(project_dir, eff_task, entry)
  let m : Map[String, Json] = Map([])
  m.set("ok", Json::boolean(true))
  m.set("path", Json::string(path))
  m.set("branch", Json::string(eff_branch))
  m.set("detached", Json::boolean(detach))
  m.set("task", Json::string(eff_task))
  m.set("created_sha", Json::string(created_sha))
  m.set("manifest_saved", Json::boolean(saved))
  m.set("code", Json::number(0))
  m.set("stdout", Json::string(out))
  if !saved {
    m.set(
      "note",
      Json::string("沙箱已建，但账没落盘：该沙箱在 wt_status 里表现为 unregistered，不会被自动回收"),
    )
  }
  Ok(Json::object(m))
}

///|
/// 取路径末段（`a/b/c` → `c`；尾部分隔符先剥）。
fn wt_last_segment(path : String) -> String {
  let p = path.replace_all(old="\\", new="/")
  let mut end = p.length()
  while end > 0 && p[end - 1] == '/' {
    end = end - 1
  }
  let head = p[0:end].to_owned()
  let mut last = ""
  for seg in head.split("/") {
    last = seg.to_owned()
  }
  last
}

///|
/// `wt_status`：git 面 + 账面对表，给每个**登记过**的沙箱判七档状态。
///
/// 回执保留 `worktrees_raw`（porcelain 原文）以兼容薄封装调用方；新字段是
/// `sandboxes` / `tally` / `unregistered`——「目录在但不在账上」也是一种要看得见的状态。
pub async fn wt_status_impl(
  project_dir : String,
  timeout_ms : Int32,
) -> Result[Json, String] {
  let (ok, code, out, err) = wt_git(["worktree", "list", "--porcelain"], project_dir, timeout_ms)
  let parsed = wt_parse_porcelain(out)
  let entries = wt_load_all(project_dir)
  let sandboxes : Array[Json] = []
  let states : Array[String] = []
  let known : Array[String] = []
  let now = wt_now_secs()
  for pair in entries {
    let task = pair.0
    let j = pair.1
    let path = wt_s(j, "path")
    let branch = wt_s(j, "branch")
    let created_sha = wt_s(j, "created_sha")
    let base = wt_s(j, "base")
    let created_at = wt_i(j, "created_at", now)
    let ttl_min = wt_i(j, "ttl_min", 120)
    known.push(path.replace_all(old="\\", new="/"))
    let dir_exists = @fs.path_exists(path)
    let head_sha = if dir_exists {
      let (hok, _, hout, _) = wt_git(["rev-parse", "HEAD"], path, timeout_ms)
      if hok { hout.trim().to_owned() } else { "" }
    } else {
      ""
    }
    let dirty = if dir_exists {
      let (dok, _, dout, _) = wt_git(["status", "--porcelain"], path, timeout_ms)
      if dok { wt_count_lines(dout) } else { -1 }
    } else {
      0
    }
    let merged : Bool? = if dir_exists && !branch.is_empty() {
      let (mok, mcode, _, _) = wt_git(
        ["merge-base", "--is-ancestor", branch, base], path, timeout_ms,
      )
      if mok {
        Some(true)
      } else if mcode == 1L {
        Some(false)
      } else {
        None
      }
    } else if dir_exists {
      // detached 沙箱没有分支可比：不参与「已并入」判定（按未并入处理，靠年龄/脏度裁决）
      Some(false)
    } else {
      None
    }
    let age_min = (now - created_at) / 60
    let (state, reason) = wt_state_of(
      dir_exists, merged, dirty, age_min, ttl_min, head_sha, created_sha,
    )
    states.push(state)
    let row : Map[String, Json] = Map([])
    row.set("task", Json::string(task))
    row.set("path", Json::string(path))
    row.set("branch", Json::string(branch))
    row.set("base", Json::string(base))
    row.set("head_sha", Json::string(head_sha))
    row.set("created_sha", Json::string(created_sha))
    row.set("age_min", Json::number(age_min.to_double()))
    row.set("ttl_min", Json::number(ttl_min.to_double()))
    row.set("dirty", Json::number(dirty.to_double()))
    row.set("state", Json::string(state))
    row.set("reason", Json::string(reason))
    row.set("reclaimable", Json::boolean(wt_reclaimable(state)))
    sandboxes.push(Json::object(row))
  }
  // 「目录在但不在账上」：看得见才敢管；它们不进 tally（没账就没有生命周期结论）
  // R107：主工作树（第 0 条）不是沙箱，不能算 unregistered（详见 wt_unregistered 注释）
  let unregistered = wt_unregistered(parsed, known)
  let m : Map[String, Json] = Map([])
  m.set("ok", Json::boolean(ok))
  m.set("code", Json::number(code.to_int().to_double()))
  m.set("worktrees_raw", Json::string(out))
  m.set("parsed", Json::array(parsed))
  m.set("sandboxes", Json::array(sandboxes))
  m.set("tally", wt_tally(states))
  m.set("unregistered", Json::array(unregistered))
  m.set("main_worktree", Json::string(if parsed.length() > 0 { wt_s(parsed[0], "path") } else { "" }))
  m.set(
    "note",
    Json::string(
      "只有登记过（有 wt-*.json 账）的沙箱才有生命周期结论；unregistered 里的目录存在但无账，不会被自动回收。native 构建下 git 读不到 ⇒ unknown，绝不顺着年龄猜",
    ),
  )
  if !ok && !err.is_empty() {
    m.set("stderr", Json::string(err))
  }
  Ok(Json::object(m))
}

///|
/// 数非空行（`git status --porcelain` 的脏文件条数）。
fn wt_count_lines(s : String) -> Int {
  let mut n = 0
  for line in s.split("\n") {
    if !line.trim().is_empty() {
      n = n + 1
    }
  }
  n
}

///|
/// `wt_destroy`：收沙箱。
///
/// 三道安全：① 只动**账上登记过**的路径（否则必须 `force=true`，且 path 仍要过形状校验）；
/// ② 分支默认不删，显式 `delete_branch=true` 才走 `git branch -d`（未并入 git 自己会拒）；
/// ③ 拆失败不删账（账留着 = 还看得见），只有 `git worktree remove` 成功才删账。
pub async fn wt_destroy_impl(
  project_dir : String,
  path : String,
  force : Bool,
  delete_branch : Bool,
  timeout_ms : Int32,
) -> Result[Json, String] {
  if !wt_path_ok(path) {
    return Err("非法 path：空 / 含 .. / 以分隔符结尾 一律拒绝")
  }
  let found = wt_find_by_path(project_dir, path)
  let registered = found is Some(_)
  if !registered && !force {
    let m : Map[String, Json] = Map([])
    m.set("ok", Json::boolean(false))
    m.set("path", Json::string(path))
    m.set("removed", Json::boolean(false))
    m.set("registered", Json::boolean(false))
    m.set(
      "note",
      Json::string("该路径不在账上（unregistered）⇒ 拒绝拆除；确认要拆请显式 force=true"),
    )
    return Ok(Json::object(m))
  }
  let task = match found {
    Some(p) => p.0
    None => ""
  }
  let branch = match found {
    Some(p) => wt_s(p.1, "branch")
    None => ""
  }
  let args : Array[String] = ["worktree", "remove"]
  if force {
    args.push("--force")
  }
  args.push(path)
  let (ok, code, out, err) = wt_git(args, project_dir, timeout_ms)
  let m : Map[String, Json] = Map([])
  m.set("ok", Json::boolean(ok))
  m.set("path", Json::string(path))
  m.set("task", Json::string(task))
  m.set("registered", Json::boolean(registered))
  m.set("removed", Json::boolean(ok))
  m.set("code", Json::number(code.to_int().to_double()))
  m.set("stdout", Json::string(out))
  m.set("stderr", Json::string(err))
  if ok && registered {
    @fs.remove_file(wt_manifest_path(project_dir, task)) catch { _ => () }
    m.set("manifest_deleted", Json::boolean(true))
  } else {
    m.set("manifest_deleted", Json::boolean(false))
  }
  // 分支：默认不删；显式要求才动，且只走 `git branch -d`（未并入会被 git 自己拒绝）
  if ok && delete_branch && !branch.is_empty() {
    let (bok, bcode, bout, berr) = wt_git(["branch", "-d", branch], project_dir, timeout_ms)
    m.set("branch_deleted", Json::boolean(bok))
    m.set("branch_code", Json::number(bcode.to_int().to_double()))
    m.set("branch_stdout", Json::string(bout))
    if !bok {
      m.set(
        "branch_error",
        Json::string("git branch -d 拒绝：通常=分支未并入（这是 git 的判断，不是本工具的判断）" + berr),
      )
    }
  } else {
    m.set("branch_deleted", Json::boolean(false))
    if delete_branch && branch.is_empty() {
      m.set("branch_error", Json::string("沙箱无分支名（detached），无可删"))
    }
  }
  if !ok {
    m.set("note", Json::string("git worktree remove 失败：账保留（还看得见的失败比静默丢账好）"))
  }
  Ok(Json::object(m))
}
