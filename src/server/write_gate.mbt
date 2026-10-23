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
/// MCP 客户端传的 `project_dir` 是合法**绝对**路径（如 `E:/IDEProjects/AI/rx-mbt`），
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
