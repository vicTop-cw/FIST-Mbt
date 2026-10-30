/// write_gate.mbt —— T0r3「核心写入门禁」（单一真源）
///
/// 政策：MCP Server 启动后**不得**在目标项目任意位置落笔；所有工件写入必须
/// 经过本门。白名单 = `<project_dir>/.fist-mbt/` 与 `<project_dir>/fist-mbt/`；
/// 另放行 FIST 自驱工件目录 `<project_dir>/memory`、`<project_dir>/reports`、
/// `<project_dir>/plans`（均在目标项目内，是 memory_consolidate / selfdrive_append /
/// report_bug / github 队列 / 审视报告这些既有工具的原生产物落点——把它们也拒了，
/// 会让"启动后不得写"变成"启动后啥都干不了"，破坏既有语义）。
/// 越界一律 Reject（fail-closed）；project_dir 为空则 NoProjectDir。
///
/// 目标相对路径 `rel` 的守卫口径与 `MultiStore::data_dir_ok` / `bug_project_dir_ok` /
/// `mr_check_ns` 同族：空、含 `..`、前导 `/` 或 `\`、盘符（第 2 位 `:`）均判非法；
/// 但 `project_dir` 本身只按「非空」判——它是绝对路径也合法。

///|
/// 写入门禁三态裁决。
pub enum WriteVerdict {
  Allow
  Reject(String)
  NoProjectDir
}

///|
/// 路径合法性。
pub fn write_gate_path_ok(p : String) -> Bool {
  if p.is_empty() {
    return false
  }
  if p.contains("..") {
    return false
  }
  let c0 = p[0]
  if c0 == '/' || c0 == '\\' {
    return false
  }
  if p.length() >= 2 && p[1] == ':' {
    return false
  }
  true
}

///|
/// 白名单顶层目录。
fn write_gate_allow_top(top : String) -> Bool {
  top == ".fist-mbt" ||
  top == "fist-mbt" ||
  top == "memory" ||
  top == "reports" ||
  top == "plans"
}

///|
/// 取相对路径的首段目录名。
fn write_gate_top(rel : String) -> String {
  let n = rel.length()
  let mut i = 0
  while i < n {
    let c = rel[i]
    if c == '/' || c == '\\' {
      return rel[0:i].to_owned()
    }
    i = i + 1
  }
  rel
}

///|
/// 白名单说明（回执里给调用方指路用）。
fn write_gate_allowlist_hint() -> String {
  "<project_dir>/.fist-mbt/, <project_dir>/fist-mbt/, <project_dir>/memory/, " +
  "<project_dir>/reports/, <project_dir>/plans/"
}

///|
/// `project_dir` 合法性（**宽容口径**）：只拒空串 → `NoProjectDir`（fail-closed）。
/// 注意**不要**对 `project_dir` 套 `write_gate_path_ok` 的盘符/前导分隔符判据——
/// MCP 客户端传的 `project_dir` 是合法**绝对**路径（如 `E:/proj/AI/rx-mbt`），
/// 把它当非法会误杀所有真实调用；越界判定只作用于**相对目标路径** `rel`。
fn write_gate_project_dir_ok(p : String) -> Bool {
  !p.is_empty()
}

///|
/// 三态裁决：`rel` 是相对 `project_dir` 的目标路径。
pub fn write_gate(project_dir : String, rel : String) -> WriteVerdict {
  if !write_gate_project_dir_ok(project_dir) {
    return NoProjectDir
  }
  if !write_gate_path_ok(rel) {
    return Reject("write_gate: 目标路径越界被拒: " + rel)
  }
  if write_gate_allow_top(write_gate_top(rel)) {
    return Allow
  }
  Reject(
    "write_gate: 越界写入被拒: " +
    rel +
    "（白名单: " +
    write_gate_allowlist_hint() +
    "）",
  )
}

///|
/// 供纯写函数调用：Allow → Ok，否则 Err（带原因，fail-closed）。
pub fn write_gate_ok(
  project_dir : String,
  rel : String,
) -> Result[Unit, String] {
  match write_gate(project_dir, rel) {
    Allow => Ok(())
    NoProjectDir => Err("write_gate: 非法 project_dir: " + project_dir)
    Reject(r) => Err(r)
  }
}

///|
/// 供 MCP 工具闭包调用：先过门 + 落一条审计，再交给纯函数。
/// Reject / NoProjectDir 时已 `audit.record(...)`，调用方直接返回 Err 即可。
pub fn write_gate_audit(
  project_dir : String,
  rel : String,
  audit : @ops.AuditLog,
  now : String,
  tool : String,
) -> Result[Unit, String] {
  match write_gate(project_dir, rel) {
    Allow => Ok(())
    NoProjectDir => {
      audit.record(
        action="write_gate:reject",
        actor="fist-mbt",
        task_id="-",
        detail="tool=" +
          tool +
          " project_dir 非法: " +
          project_dir +
          " target=" +
          rel,
        now~,
      )
      Err("write_gate: 非法 project_dir: " + project_dir)
    }
    Reject(r) => {
      audit.record(
        action="write_gate:reject",
        actor="fist-mbt",
        task_id="-",
        detail="tool=" + tool + " " + r,
        now~,
      )
      Err(r)
    }
  }
}

///|
/// ns 写门（T0r1 第②步 · 止血）：publish 等**新建**类工具拒绝写入 default/空命名空间，
/// 强制调用方先 `store_open` 自己项目的 ns。
///
/// 根因：`publish` 默认 `ns="default"`，而外部项目（cron-auto / Pentad / bugs 等）
/// 的定时进程从不传 ns——于是它们全部落进 default.db，与 FIST-Mbt 本项目任务
/// 混成一张表（实测 default ns 含 2300+ 外部项目任务，`supervisor_status` 的
/// `by_namespace.default` 一度报到 2400+）。
///
/// 只拦**新建**（publish / publish_parallel / dag_publish）：claim/execute/submit 是
/// 对既有任务的**状态迁移**，按 task_id 寻址不按 ns 新建行，不属污染源，不设门。
///
/// ns 合法性复用仓库唯一真源 `@store.MultiStore::safe_ns`（与 BUG-64 同族口径），
/// 不另设一套规则。返回 Ok 表示允许写入；Err 给出指路文案。
pub fn ns_write_gate(ns : String) -> Result[Unit, String] {
  if ns == "" || ns == "default" {
    return Err(
      "ns_gate: 拒绝写入 default 命名空间：请先 store_open(ns=<你的项目命名空间>) " +
      "再发布，避免跨项目任务污染 default.db",
    )
  }
  if @store.MultiStore::safe_ns(ns) is None {
    return Err(
      "ns_gate: 非法命名空间: " +
      ns +
      "（仅允许字母数字与 _ / -）",
    )
  }
  Ok(())
}

///|
/// BUG-389（BUG-78 修复的迁移缺口）：检测 cwd 根旧位置存量库 `<ns>.db` 是否存在。
///
/// BUG-78 把 store_open 默认 data_dir 改成 `.fist-mbt/data/`（多库落目标项目私有目录），
/// 但没迁存量库——cwd 根仍留有 BUG-78 前默认落点的 `<ns>.db`。server 重启后
/// store_open 落新空库，同 ns 任务"凭空消失"（2026-10-23 实测：fist-mbt-refactor 40 条、
/// tnr-polish 23 条、tql-b5 1 条全部丢失，只能靠 sqlite3 手工查旧库找回）。
///
/// 返回 true 表示旧位置有存量库，调用方应复用旧库（`data_dir="."`）而非静默开新空库。
/// 复用旧库是过渡兼容：新库仍按 BUG-78 落 `.fist-mbt/data/`，旧库迁移由调用方择机搬移。
pub fn legacy_store_exists_in(dir : String, ns : String) -> Bool {
  @fs.is_file(dir + "/" + ns + ".db") catch {
    _ => false
  }
}

///|
/// 便捷版：检测 cwd（server 进程工作目录）根位置的存量库。
pub fn legacy_store_exists(ns : String) -> Bool {
  legacy_store_exists_in(".", ns)
}

// ---------------------------------------------------------------------------
// BUG-436：写面 ACL 的**判定身份**（单一真源）
//
// 病灶（实测，非推断）：`claim` 的判定身份取 `assignee`（调用方给的原始名），
// `execute` 取 `executor`——而 `executor` 是可选的、缺省 `"manual"`。
// 于是同一进程里「同一个动作链」被判成两个身份：
//     claim   → fp("vools-retry-lead") = 4e3b9eb2cd9cb473
//     execute → fp("manual")           = 020934005581bee2
// grant 只能授权到前者，execute 永远进不去；而报错里印的是**指纹**，
// 调用方把那串指纹再传给 `agent_acl_grant` 会被再哈希一次（→ dfd9df…），
// 「已落库」但 execute 仍拒 —— 这就是 BUG-436 的完整闭环。
//
// 修法：把「判定身份从哪来」抽成纯函数，所有写门共用一条优先级链，
// 并且身份**永远以原始名（raw）呈现**，指纹只作为诊断附注。
// ---------------------------------------------------------------------------

///|
/// ACL 判定身份：`raw` 是调用方能说出口、也能拿去 `agent_acl_grant` 的**原始**身份；
/// `source` 记录它来自哪个参数（诊断用，直接进错误文案）；`implicit=true` 表示
/// 这身份不是调用方给的，而是工具缺省兜出来的（这种身份天然不可预期，必须点明）。
priv struct AclIdentity {
  raw : String
  source : String
  implicit : Bool
}

///|
/// 该身份对应的 ACL 指纹（与 `agent_write_gate` / `agent_acl_grant` 同一函数）。
fn AclIdentity::fp(self : AclIdentity) -> String {
  @engine.agent_fp_of(self.raw)
}

///|
/// 按优先级取第一个非空候选；全空则退回 `manual` 并标记 `implicit=true`
/// （`implicit` 是错误文案里那句「该身份来自工具缺省」的开关——没有它，
/// 「grant 了却还是拒」对调用方就是一句无法行动的谜语）。
fn acl_identity_pick(cands : Array[(String, String)]) -> AclIdentity {
  for c in cands {
    let (raw, source) = c
    if raw != "" {
      return { raw, source, implicit: false, }
    }
  }
  { raw: "manual", source: "default-manual", implicit: true, }
}

///|
/// `claim` 的判定身份：显式 `agent` > `assignee`（必填，故基本恒为它）。
fn acl_claim_identity(
  explicit_agent : String,
  assignee : String,
) -> AclIdentity {
  acl_identity_pick([(explicit_agent, "explicit-agent"), (assignee, "assignee")])
}

///|
/// `execute` 的判定身份：显式 `agent` > **显式给出且非占位**的 `executor` >
/// **任务当前 assignee**（= 同一条链上 claim 用的那个身份）> 缺省 `manual`。
///
/// 三个关键口径：
/// ① `executor="manual"` 视为**未给出**——它是「人工执行」的占位名，不是 agent 身份；
///    真要拿它当身份就得显式传 `agent="manual"`，那时文案会点明是显式选择。
/// ② 回落到任务 assignee 是根治点：`execute` 本来就是「claim 到的人汇报交付物」，
///    身份必须与 claim 同源，否则同一条链天然有两个身份（BUG-436 的形状）。
/// ③ `executor` 仍照旧作为**执行元数据**写进 executions 表，与判定身份解耦
///    （那是"用什么执行器跑的"，不是"谁在写"）。
fn acl_execute_identity(
  explicit_agent : String,
  executor : String,
  executor_explicit : Bool,
  task_assignee : String,
) -> AclIdentity {
  let executor_for_id = if executor_explicit && executor != "manual" {
    executor
  } else {
    ""
  }
  acl_identity_pick([
    (explicit_agent, "explicit-agent"),
    (executor_for_id, "executor"),
    (task_assignee, "task-assignee"),
  ])
}

///|
/// 参数「是否由调用方显式给出」（非空字符串才算给出）。
///
/// 需要它是因为 **缺省值不可当身份**：`execute` 的 `executor` 缺省 `"manual"`，
/// 拿缺省值当 ACL 身份就是 BUG-436 的病灶（调用方从没说过自己叫 manual）。
fn acl_arg_given(args : Json, key : String) -> Bool {
  match jget(args, key) {
    Some(Json::String(s)) => s != ""
    _ => false
  }
}

///|
/// 是否形似 ACL 指纹（16 位**小写**十六进制）——用于 `agent_acl_grant` 的兼容：
/// 调用方把报错里的指纹原样粘回来时，别再哈希一次（否则写进另一行 → BUG-436）。
fn acl_id_is_fp(s : String) -> Bool {
  if s.length() != 16 {
    return false
  }
  for c in s.to_array() {
    let u = c.to_int()
    let is_hex = (u >= 48 && u <= 57) || (u >= 97 && u <= 102)
    if !is_hex {
      return false
    }
  }
  true
}

///|
/// ACL 拒绝时的**可行动**文案（纯函数，好被白盒锁钉住）。
///
/// 必须同时给出：① 原始身份（grant 用它）；② 指纹（与库里的行对表）；
/// ③ 身份来源（调用方才知道自己漏了哪个参数）；④ 一句「别传指纹」的警示
/// ——这正是 BUG-436 里「grant 后仍拒」的那一环。
fn acl_gate_fail_message(
  store_err : String,
  id : AclIdentity,
  ns : String,
) -> String {
  let implicit_note = if id.implicit {
    "；⚠ 该身份来自工具缺省（调用方未显式给 agent/assignee/executor）——先显式传 agent=<你的身份> 再授权，否则它每次都是这个缺省身份"
  } else {
    ""
  }
  "acl: " +
  store_err +
  "；判定身份: " +
  id.raw +
  "（fp=" +
  id.fp() +
  "，来源=" +
  id.source +
  "）" +
  implicit_note +
  "；出路: agent_acl_grant(agent_id=\"" +
  id.raw +
  "\", namespace=\"" +
  ns +
  "\", can_write=true) —— 传**原始身份**；报错里那串 16 位指纹是身份的名字，不是身份本身（再哈希一次会写到另一行，BUG-436）"
}
