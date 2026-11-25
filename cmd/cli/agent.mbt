///|
/// `fist agent` —— **会话内嵌 worker 的 P0 骨架**（issue #1 / P11 工作项 P0）。
///
/// 范围严格收在「锁 → 心跳 → 一轮」这条主干上；执行器（P1）与仓库池（P2）不在本文件。
/// 设计红线：**server 保持被动不改造**——本模块零 spawn server、只操作状态文件。
///
/// 子命令面（`serve` / `status` / `stop` / `run`）：
///   · `fist agent serve [--once] [--dry-run]` —— 取单实例锁 → 循环{心跳→一轮}→收尾
///   · `fist agent serve --once`                —— **跑一轮、不常驻**（issue #1 的最小可用形态）
///   · `fist agent run`                         —— `serve --once` 的别名
///   · `fist agent status`                      —— 只读状态/日志尾（不改任何东西）
///   · `fist agent stop`                        —— 标 stopped + 释放锁
///
/// **`--once` 的确切含义**：**跑一轮、退出**。一轮里做满「心跳 → list → claim →
/// task-packet → 回执骨架」，P1 再把执行器接进这一轮。之所以 P0 就要这一链：
/// issue 验收第 2 条「不重复领取」的最小可观测形态正是「这轮 claim 的 id，下轮不再
/// claim 同一个」——没有这一链，P1 无从判断自己有没有重复领。

///|
/// agent 服务状态目录名（`<data_dir>/agent-service/`）。
/// 与 `loop_store_path_in` 同一口径：改道针指哪就跟着走。
pub const AGENT_SERVICE_DIR : String = "agent-service"

///|
/// 状态文件名（含 pid / 启动时刻 / 最近心跳 / 轮数）。
pub const AGENT_STATE_FILE : String = "state.json"

///|
/// 日志文件名（每轮追加一行 JSONL，`status` 读它的尾部）。
pub const AGENT_LOG_FILE : String = "worker.log"

///|
/// 单实例锁文件名。**这是进程级互斥，不是 `@store.FileLock`**：
/// 后者是库内的逻辑锁记录（scope/agent/status，给权限门读的），没有跨进程排他能力，
/// 拿它当单实例锁会得到「两个进程都说自己持有」。这里用 OS 级原子创建（`flag:'wx'`）。
pub const AGENT_LOCK_FILE : String = "agent.lock"

///|
/// 锁的 stale 阈值（毫秒）。超过即视为持有者已死，可回收重取。
pub const AGENT_LOCK_STALE_MS : Double = 30000.0

///|
/// 常驻轮询间隔（毫秒）。P0 固定值，P2 再做 `--interval`。
pub const AGENT_POLL_INTERVAL_MS : Double = 15000.0

///|
/// `status` 默认回看的日志行数。
pub const AGENT_STATUS_TAIL_LINES : Int32 = 10

// ─────────────────────────────────────────────────────────────────────────
// 词法与旗标（与 `subcmd.mbt` 同构：词法一处展开，退出码读同一份）
// ─────────────────────────────────────────────────────────────────────────

///|

///|
#derive(Eq, Debug)
pub enum AgentCmd {
  Serve
  Run
  Status
  Stop
  Help
  Unknown(String)
}

///|
pub fn parse_agent_cmd(sub : String) -> AgentCmd {
  match sub {
    "serve" | "--serve" => Serve
    "run" | "--once" => Run
    "status" => Status
    "stop" => Stop
    "help" | "--help" | "-h" => Help
    other => Unknown(other)
  }
}

///|
pub struct AgentFlags {
  once : Bool
  dry_run : Bool
}

///|
/// 解析 agent 子命令的旗标。**未知旗标必须回 Err**（判据 hygiene 硬要求：
/// 白名单 + 未知即拒。否则把 `--once` 拼成 `--onse` 会静默落进真分支，
/// 人以为跑了单轮）。
pub fn parse_agent_flags(args : Array[String]) -> Result[AgentFlags, String] {
  let mut once : Bool = false
  let mut dry_run : Bool = false
  for a in args {
    if a == "--once" {
      once = true
    } else if a == "--dry-run" {
      dry_run = true
    } else {
      return Err("未知参数: \{a}（已知：--once / --dry-run）")
    }
  }
  Ok({ once, dry_run, })
}

///|
pub fn AgentFlags::is_once(self : AgentFlags) -> Bool {
  self.once
}

///|
pub fn AgentFlags::is_dry_run(self : AgentFlags) -> Bool {
  self.dry_run
}

///|
/// 一轮动作是否真的落库（`--dry-run` ⇒ 只观测不回写）。
pub fn AgentFlags::should_mutate(self : AgentFlags) -> Bool {
  !self.dry_run
}

// ─────────────────────────────────────────────────────────────────────────
// 状态目录：唯一 env 读取点（判例-29 —— 同一条规则不许有两份 env 读取）
// ─────────────────────────────────────────────────────────────────────────

///|
/// 回落目录。与 `loop_store_fallback_dir` / store_open 默认档同源（`.fist-mbt/data`），
/// **绝不裸写仓库根/cwd**——那是 BUG-392 的形状。
const AGENT_DATA_FALLBACK_DIR : String = ".fist-mbt/data"

///|
/// 取「最后一个分隔符」的下标，纯相对名返回 None（与 `subcmd.mbt:last_path_sep` 同口径）。
fn agent_last_sep(p : String) -> Int32? {
  let n = p.length()
  let mut acc : Int32? = None
  let mut i : Int32 = 0
  while i < n {
    let c = p[i]
    if c == '/' || c == '\\' {
      acc = Some(i)
    }
    i = i + 1
  }
  acc
}

///|
/// `FIST_DB_PATH` 改道针指向的**目录**（未设 / 空串 / 纯相对名 ⇒ 空串，交给上层回落）。
pub fn agent_db_dir(env_value : String?) -> String {
  match env_value {
    Some(p) => {
      let t = p.trim().to_owned()
      if t.is_empty() {
        ""
      } else {
        match agent_last_sep(t) {
          Some(i) => t[:i + 1].to_owned()
          None => ""
        }
      }
    }
    None => ""
  }
}

///|
/// 服务状态根目录（**每次现算**，不缓存：重启后改道针要立刻生效）。
pub fn agent_service_dir() -> String {
  let from_db = agent_db_dir(@env.get_env_var("FIST_DB_PATH"))
  let dir = if from_db.is_empty() { AGENT_DATA_FALLBACK_DIR } else { from_db }
  if dir.ends_with("/") {
    dir + AGENT_SERVICE_DIR
  } else {
    dir + "/" + AGENT_SERVICE_DIR
  }
}

///|
pub fn agent_state_path() -> String {
  agent_service_dir() + "/" + AGENT_STATE_FILE
}

///|
pub fn agent_log_path() -> String {
  agent_service_dir() + "/" + AGENT_LOG_FILE
}

///|
pub fn agent_lock_path() -> String {
  agent_service_dir() + "/" + AGENT_LOCK_FILE
}

// ─────────────────────────────────────────────────────────────────────────
// 状态记录（state.json）
// ─────────────────────────────────────────────────────────────────────────

///|
/// `state.json` 的字段集。**只写这几个键**，多写的键 status 也不读——
/// 让「状态文件被塞了别的东西」在语义上无意义。
pub struct AgentState {
  status : String
  pid : Int32
  started_at : String
  last_heartbeat : String
  last_task_id : String
  rounds : Int32
}

///|
/// 状态记录 → JSON 文本。字段顺序固定（快照可逐字比对）。
pub fn AgentState::to_json_text(self : AgentState) -> String {
  let m : Map[String, Json] = Map([])
  m.set("status", Json::string(self.status))
  m.set("pid", Json::number(self.pid.to_double()))
  m.set("started_at", Json::string(self.started_at))
  m.set("last_heartbeat", Json::string(self.last_heartbeat))
  m.set("last_task_id", Json::string(self.last_task_id))
  m.set("rounds", Json::number(self.rounds.to_double()))
  Json::object(m).stringify()
}

///|
/// JSON 文本 → 状态记录。**读回失败不回默认对象**（那会伪造 running），
/// 返回 None，让调用方按「读不到」处理。
pub fn AgentState::from_json_text(text : String) -> AgentState? {
  let j = @json.parse(text) catch { _ => return None }
  match j.as_object() {
    None => None
    Some(m) =>
      match m.get("status") {
        Some(Json::String(_)) => {
          let st = match m.get("status") {
            Some(Json::String(s)) => s
            _ => ""
          }
          Some({
            status: st,
            pid: agent_json_num(m, "pid").to_int(),
            started_at: agent_json_str(m, "started_at"),
            last_heartbeat: agent_json_str(m, "last_heartbeat"),
            last_task_id: agent_json_str(m, "last_task_id"),
            rounds: agent_json_num(m, "rounds").to_int(),
          })
        }
        _ => None
      }
  }
}

///|
fn agent_json_str(m : Map[String, Json], key : String) -> String {
  match m.get(key) {
    Some(Json::String(s)) => s
    _ => ""
  }
}

///|
fn agent_json_num(m : Map[String, Json], key : String) -> Double {
  match m.get(key) {
    Some(Json::Number(n, ..)) => n
    _ => 0.0
  }
}

///|
/// 心跳：刷 last_heartbeat、轮数 +1；认领到任务时记下 id。
pub fn AgentState::beat(
  self : AgentState,
  now : String,
  task_id : String,
) -> AgentState {
  {
    status: self.status,
    pid: self.pid,
    started_at: self.started_at,
    last_heartbeat: now,
    last_task_id: if task_id.is_empty() {
      self.last_task_id
    } else {
      task_id
    },
    rounds: self.rounds + 1,
  }
}

///|
pub fn AgentState::mark_stopped(self : AgentState) -> AgentState {
  {
    status: "stopped",
    pid: self.pid,
    started_at: self.started_at,
    last_heartbeat: self.last_heartbeat,
    last_task_id: self.last_task_id,
    rounds: self.rounds,
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 单实例锁（OS 级原子创建 + 基于 mtime 的 stale 回收）
// ─────────────────────────────────────────────────────────────────────────

///|
/// 持锁结果三档：拿到 / 被别人持有 / IO 失败。**三档必须可分辨**——
/// 把「锁冲突」报成普通 IO 错，人就无法判断该等还是该查。
#derive(Eq, Debug)
pub enum LockResult {
  Acquired
  HeldBy(String)
  Failed(String)
}

///|
/// 锁内容就是 pid：释放时比对，确保**只删自己持有的那把锁**
/// （否则会把下一个 worker 刚拿到的锁删掉）。
pub fn agent_lock_content(pid : Int32) -> String {
  "\{pid}"
}

///|
/// 取锁 + stale 回收。规则：
///   · 原子创建成功 ⇒ Acquired；
///   · EEXIST 且锁 mtime **超龄** ⇒ 视为持有者已死，删旧锁后**只重取一次**；
///   · EEXIST 且未超龄 ⇒ HeldBy(pid)（`--once` 下这是正常出口，不是错误）。
pub fn agent_lock_acquire() -> LockResult {
  let pid = agent_io_pid()
  // 先保证服务目录在：直接对锁文件做原子创建会因父目录缺失回 ENOENT，
  // 而那会被误读成「取锁失败」——目录是 worker 自己要管的，不是环境错。
  match agent_io_mkdir(agent_service_dir()) {
    Ok(_) => ()
    Err(e) => return Failed("mkdir: \{e}")
  }
  match agent_io_write_exclusive(agent_lock_path(), agent_lock_content(pid)) {
    Ok(_) => Acquired
    Err(e) =>
      if e.has_prefix("lock_exists:") {
        let holder = agent_strip_lock_prefix(e)
        let mtime = agent_io_stat_mtime(agent_lock_path())
        if mtime > 0.0 && agent_io_now_ms() - mtime > AGENT_LOCK_STALE_MS {
          // 超龄：回收后**只重试一次**（不循环抢，避免两个进程互删）
          ignore(agent_io_remove(agent_lock_path()))
          match
            agent_io_write_exclusive(agent_lock_path(), agent_lock_content(pid)) {
            Ok(_) => Acquired
            Err(e2) => lock_err_to_result(e2)
          }
        } else {
          HeldBy(holder)
        }
      } else {
        Failed(e)
      }
  }
}

///|
fn lock_err_to_result(e : String) -> LockResult {
  if e.has_prefix("lock_exists:") {
    HeldBy(agent_strip_lock_prefix(e))
  } else {
    Failed(e)
  }
}

///|
fn agent_strip_lock_prefix(e : String) -> String {
  match e.strip_prefix("lock_exists:") {
    Some(rest) => rest.to_owned()
    None => e
  }
}

///|
/// 释放锁：**只在锁内容确实是自己的时候才删**。
pub fn agent_lock_release() -> Result[Unit, String] {
  match agent_io_read(agent_lock_path()) {
    Ok(text) =>
      if text.trim() == agent_lock_content(agent_io_pid()) {
        agent_io_remove(agent_lock_path())
      } else {
        // 不是自己的锁 ⇒ 不动它（release 的语义是「确保我没占着」，故回 Ok）
        Ok(())
      }
    Err(e) => Err(e)
  }
}

///|
/// 锁当前是不是我的（常驻循环的退出条件：外部 stop 会放锁 ⇒ 这里变 false）。
pub fn agent_lock_is_mine() -> Bool {
  match agent_io_read(agent_lock_path()) {
    Ok(t) => t.trim() == agent_lock_content(agent_io_pid())
    Err(_) => false
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 一轮（--once 的本体）
// ─────────────────────────────────────────────────────────────────────────

///|
/// 一轮的观测结果。**dry-run 下也要如实回「它发现了什么」**——
/// 只回一个 ok 等于没观测。
pub struct AgentRound {
  claimed_task_id : String
  packet : String
  note : String
  dry_run : Bool
}

///|
/// task-packet 文本。P1 的执行器模板 `{packet}` 就替换成这一段。
pub fn agent_packet_for(task_id : String, now : String) -> String {
  if task_id.is_empty() {
    ""
  } else {
    let m : Map[String, Json] = Map([])
    m.set("task_id", Json::string(task_id))
    m.set("claimed_at", Json::string(now))
    m.set("assignee", Json::string("agent-worker"))
    Json::object(m).stringify()
  }
}

///|
/// 跑一轮：list → claim → task-packet。
///
/// 心跳与落盘由 `agent_round_and_record` 负责，这里只做「看 + 领」，
/// 这样它可被白盒测试直接钉在引擎行为上（判例-29：机制格）。
pub fn agent_run_once(
  flags : AgentFlags,
  now : String,
) -> Result[AgentRound, String] {
  let engine = @engine.FistEngine::new()
  // P0 候选面 = 内存 store 的 Pending 任务（P2 接仓库池后换源，签名不变）
  let pending : Array[String] = []
  for t in engine.list_all() {
    if t.get_status().is_pending() {
      pending.push(t.get_id())
    }
  }

  let mut claimed : String = ""
  let mut note : String = "no_pending"
  for tid in pending {
    // claim 失败**不假绿**：如实记进 note，且不再试下一个（避免一轮抢一片）
    match engine.claim(task_id=tid, assignee="agent-worker", now~) {
      Ok(_) => {
        claimed = tid
        note = "claimed"
        break
      }
      Err(e) => {
        note = "claim_failed:\{e}"
        break
      }
    }
  }

  Ok({
    claimed_task_id: claimed,
    packet: agent_packet_for(claimed, now),
    note,
    dry_run: !flags.should_mutate(),
  })
}

///|
/// 一轮 + 记录：读状态 → beat → 落盘 → 写日志。
/// `--dry-run` 一律不落盘、不写日志（「看过但没动」必须可分辨）。
pub fn agent_round_and_record(flags : AgentFlags) -> Result[AgentRound, String] {
  let now = agent_io_now_iso()
  match agent_run_once(flags, now) {
    Err(e) => Err(e)
    Ok(round) => {
      if flags.should_mutate() {
        let state = agent_load_state_or_new(now)
        let updated = state.beat(now, round.claimed_task_id)
        match agent_write_state(updated) {
          Ok(_) => ()
          Err(e) => return Err("写状态文件失败: \{e}")
        }
        agent_log_round(
          "\{now} round=\{updated.rounds} claimed=\{round.claimed_task_id} note=\{round.note}",
        )
      }
      Ok(round)
    }
  }
}

///|
fn agent_load_state_or_new(now : String) -> AgentState {
  match agent_io_read(agent_state_path()) {
    Ok(text) =>
      if text.is_empty() {
        agent_state_default(now)
      } else {
        match AgentState::from_json_text(text) {
          Some(s) => s
          None => agent_state_default(now)
        }
      }
    Err(_) => agent_state_default(now)
  }
}

///|
/// 「状态文件不存在」时的初始态。**单独成函数是为了让 dry-run 也用它**：
/// `--dry-run` 下没有任何已存在的 running 状态可写 stopped（那是它没做过的状态），
/// 所以终态就取「刚进入服务、一轮未跑」这一格。
fn agent_state_default(now : String) -> AgentState {
  {
    status: "running",
    pid: agent_io_pid(),
    started_at: now,
    last_heartbeat: now,
    last_task_id: "",
    rounds: 0,
  }
}

///|
fn agent_write_state(s : AgentState) -> Result[Unit, String] {
  match agent_io_mkdir(agent_service_dir()) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  @fs.write_string_to_file(
    agent_state_path(),
    s.to_json_text(),
    encoding="utf8",
  ) catch {
    e => return Err("write_string_to_file: \{Repr(e)}")
  }
  Ok(())
}

///|
fn agent_log_round(line : String) -> Unit {
  ignore(agent_io_append(agent_log_path(), line + "\n"))
}

///|
/// 读日志尾 n 行（`status` 用）。读不到回空串，不报错。
pub fn agent_log_tail(n : Int32) -> String {
  let text = match agent_io_read(agent_log_path()) {
    Ok(t) => t
    Err(_) => ""
  }
  if text.is_empty() {
    return ""
  }
  let lines : Array[String] = []
  for line in text.split("\n") {
    lines.push(line.to_owned())
  }
  let total = lines.length()
  let start = if total > n { total - n } else { 0 }
  let out : Array[String] = []
  let mut i : Int32 = start
  while i < total {
    out.push(lines[i])
    i = i + 1
  }
  out.join("\n")
}

// ─────────────────────────────────────────────────────────────────────────
// 命令执行面（main 调这里）
// ─────────────────────────────────────────────────────────────────────────

///|
/// 一轮之后的落点文本（stdout）。`claimed=none` 时**明确说没有可领的**，
/// 不回空白——空白会被读成「跑了但没输出」。
pub fn agent_round_text(round : AgentRound) -> String {
  let out : Array[String] = []
  out.push(
    if round.dry_run {
      "fist agent: dry-run"
    } else {
      "fist agent: round done"
    },
  )
  out.push(
    "  claimed: \{if round.claimed_task_id.is_empty() { "(none)" } else { round.claimed_task_id }}",
  )
  out.push("  note: \{round.note}")
  if !round.packet.is_empty() {
    out.push("  packet: \{round.packet}")
  }
  out.join("\n")
}

///|
/// `fist agent serve`：取锁 → 跑一轮 → 若 `--once` 则收尾退出，否则轮询。
///
/// 锁冲突时**回 rc=0 并明说**：这是「别的 worker 正在跑」，属正常态，
/// 不是失败（否则 CI 里并发两发会被判红）。
pub fn run_agent_serve(flags : AgentFlags) -> Int32 {
  // dry-run：**只观测，不取锁、不落任何文件、不改库**（结构性保证，不靠各分支自觉）。
  // 取锁本身就会写一个 lock 文件 ⇒ 必须整段跳过；否则「dry-run 零落盘」无法成立。
  if flags.is_dry_run() {
    // 回执首行已标明 dry-run，这里不重复打横幅（重复输出会被读成跑了两次）
    return match agent_round_and_record(flags) {
      Ok(round) => {
        println(agent_round_text(round))
        0
      }
      Err(e) => {
        println("fist agent: 一轮失败: \{e}")
        1
      }
    }
  }

  match agent_lock_acquire() {
    Acquired => ()
    HeldBy(holder) => {
      println(
        "fist agent: 已有 worker 持锁（pid \{holder}），本轮退出",
      )
      return 0
    }
    Failed(e) => {
      println("fist agent: 取锁失败: \{e}")
      return 1
    }
  }

  println(
    "fist agent: 启动（pid \{agent_io_pid()}，dir \{agent_service_dir()}）",
  )
  match agent_round_and_record(flags) {
    Ok(round) => println(agent_round_text(round))
    Err(e) => println("fist agent: 一轮失败: \{e}")
  }

  if flags.is_once() {
    // 单轮模式：标 stopped + 放锁后退出（状态留痕，便于 status 看上一轮）
    agent_mark_stopped(flags)
    ignore(agent_lock_release())
    println("fist agent: --once 完成，退出")
    return 0
  }

  // 常驻：轮询直到外部 stop 放锁（锁丢失即退出）
  while agent_lock_is_mine() {
    agent_io_sleep(AGENT_POLL_INTERVAL_MS)
    match agent_round_and_record(flags) {
      Ok(round) => println(agent_round_text(round))
      Err(e) => println("fist agent: 一轮失败: \{e}")
    }
  }
  agent_mark_stopped(flags)
  ignore(agent_lock_release())
  println("fist agent: 停止")
  0
}

///|
/// `run`/`--once` 别名入口。
pub fn run_agent_once() -> Int32 {
  run_agent_serve({ once: true, dry_run: false, })
}

///|
/// 标 stopped。**dry-run 下是 no-op**：它没持有过锁、也没跑过真实轮次，
/// 把状态写成 stopped 就是在文件里声明一件没发生过的事（假绿）。
fn agent_mark_stopped(flags : AgentFlags) -> Unit {
  if flags.is_dry_run() {
    return ()
  }
  let now = agent_io_now_iso()
  let s = agent_load_state_or_new(now).mark_stopped()
  ignore(agent_write_state(s))
}

///|
/// `fist agent status`：只读快照（**不改任何东西**，含不删 stale 锁）。
/// `--dry-run` 无副作用可增，仅显式接受以便各子命令共用同一旗标面（未知旗标仍拒）。
pub fn run_agent_status(_flags : AgentFlags) -> Int32 {
  println(agent_snapshot_text(agent_snapshot(AGENT_STATUS_TAIL_LINES)))
  0
}

///|
pub struct AgentSnapshot {
  state : AgentState?
  lock_holder : String
  log_tail : String
  service_dir : String
}

///|
pub fn agent_snapshot(tail_lines : Int32) -> AgentSnapshot {
  let st = match agent_io_read(agent_state_path()) {
    Ok(text) =>
      if text.is_empty() {
        None
      } else {
        AgentState::from_json_text(text)
      }
    Err(_) => None
  }
  let holder = match agent_io_read(agent_lock_path()) {
    Ok(t) => t.trim().to_owned()
    Err(_) => ""
  }
  {
    state: st,
    lock_holder: holder,
    log_tail: agent_log_tail(tail_lines),
    service_dir: agent_service_dir(),
  }
}

///|
/// 把快照渲染成给人看的文本（stdout 面）。
pub fn agent_snapshot_text(snap : AgentSnapshot) -> String {
  let out : Array[String] = []
  out.push("fist agent status")
  out.push("  dir: \{snap.service_dir}")
  match snap.state {
    None => out.push("  state: (无 state.json —— 还没跑过)")
    Some(st) =>
      out.push(
        "  state: \{st.status} pid=\{st.pid} rounds=\{st.rounds} last_task=\{st.last_task_id} started=\{st.started_at} heartbeat=\{st.last_heartbeat}",
      )
  }
  if snap.lock_holder.is_empty() {
    out.push("  lock: (无)")
  } else {
    out.push("  lock: pid \{snap.lock_holder}")
  }
  if snap.log_tail.is_empty() {
    out.push("  log: (空)")
  } else {
    out.push("  log tail:")
    for line in snap.log_tail.split("\n") {
      out.push("    \{line.to_owned()}")
    }
  }
  out.join("\n")
}

///|
/// stop 语义的放锁：**无条件删掉锁文件**。
///
/// 为什么不能复用 `agent_lock_release`：那个只在「锁内容 == 自己 pid」时才删，
/// 而 `stop` 是**另一个进程**（pid 必然对不上）⇒ 锁永远删不掉 ⇒ 常驻 worker
/// 的 `while agent_lock_is_mine()` 永不退出 ⇒ `stop` 形同虚设（实测踩中过）。
/// stop 是人的**显式停止意图**，删锁就是它的全部作用；删掉后 worker 的
/// `is_mine` 读不到锁 ⇒ 下一轮判定即退出，不会死循环。
pub fn agent_lock_stop_release() -> Result[Unit, String] {
  match agent_io_remove(agent_lock_path()) {
    Ok(_) => Ok(())
    Err(e) =>
      // 锁本就不存在也算达成目的（worker 已不在）
      if e.has_prefix("ENOENT") || e.contains("not found") {
        Ok(())
      } else {
        Err(e)
      }
  }
}

///|
/// `fist agent stop`：标 stopped + 放锁。**不杀别人的进程**（P0 只做状态面，
/// P1 再接 pid 终止；杀进程是不可逆操作，不在骨架里做）。
/// `--dry-run` ⇒ 只回显会做什么，不动状态文件也不放锁（观测与真停必须可分辨）。
pub fn run_agent_stop(flags : AgentFlags) -> Int32 {
  if flags.is_dry_run() {
    println("fist agent: dry-run：将标 stopped 并释放锁（未执行）")
    return 0
  }
  agent_mark_stopped(flags)
  match agent_lock_stop_release() {
    Ok(_) => println("fist agent: 已标 stopped 并释放锁")
    Err(e) => {
      println("fist agent: 释放锁失败: \{e}")
      return 1
    }
  }
  0
}

///|
/// `fist agent help` 的正文（也进 `help agent` topic 的骨架说明）。
pub fn agent_help_text() -> String {
  let out : Array[String] = []
  out.push("fist agent — 会话内嵌 worker（P0 骨架）")
  out.push("")
  out.push("用法：")
  out.push(
    "  fist agent serve [--once] [--dry-run]   取单实例锁 → 轮询一轮 → 常驻/单轮",
  )
  out.push(
    "  fist agent run                           serve --once 的别名（跑一轮退出）",
  )
  out.push("  fist agent status                        只读状态/日志尾")
  out.push("  fist agent stop                          标 stopped + 释放锁")
  out.push("")
  out.push("标志：")
  out.push("  --once      只跑一轮就退出（不常驻）")
  out.push("  --dry-run   只观测不回写（不落状态、不改库）")
  out.push("")
  out.push(
    "状态目录：<data_dir>/agent-service/（跟 FIST_DB_PATH 改道走）",
  )
  out.join("\n")
}
