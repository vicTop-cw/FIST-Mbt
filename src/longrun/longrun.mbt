/// longrun.mbt —— T0r53 长程任务接力最小闭环（提案方案 C · P0）。
///
/// 职责边界（**只做 P0，不越界到 P1/P2**）：
///   · `checkpoint`：把任务**整包快照**（D1=A）写成 UTF-8 JSON 文件；
///   · `resume`：裁决「这个任务现在能不能从快照续接」（状态机迁移合法）。
/// 护栏（预算熔断/失败比例阈值）、心跳化 watch-dog、handoff 入口属于 P1/P2，
/// **不在本文件**——提案 P0→P1→P2 是显式串行依赖，不并行铺开。
///
/// 设计口径（与既有实现对齐，不新造轮子）：
///   · 快照体直接复用 `@core.Task::to_json()` 的字段面，**不另立一套序列化**
///     （判例「同一规则多份实现」）；本文件只加一层信封（format/task_id/written_at）。
///   · 目录创建沿用 `MultiStore` 踩过的坑（BUG-390：SQLite/@fs 都不建中间层），
///     但 store 那份是包私有件 ⇒ 这里持有一份**只服务快照**的最小实现，
///     不回头改 store（最小改动）。
///   · resume 的**判定**是纯函数（`resume_target_status`），IO 只是它的外壳
///     —— 判例-29：机制格必须能被白盒直接断言，否则改坏纯逻辑照样绿。

///|
/// 快照格式标记：读回时必须逐字命中，否则视为「不是本工具写的文件」。
/// 版本号进格式串（而不是另开字段）：一次改动就是一次不可混用，比字段比较更难被忽略。
let snapshot_format : String = "fist-longrun-checkpoint-v1"

///|
/// 快照落盘路径：`<project_dir>/.fist-mbt/longrun/<task_id>.json`。
///
/// 为什么带 project_dir 前缀：任务可能属于任意 ns/项目，快照必须落在**该任务的项目根**下，
/// 否则跨项目同名 id 会互相覆盖（多租户隔离的最低要求）。
/// task_id 里的 `.`（子任务 `parent.idx`）在文件名里合法，不做转义。
pub fn snapshot_path(project_dir : String, task_id : String) -> String {
  let base = if project_dir == "" {
    ".fist-mbt/longrun"
  } else {
    project_dir + "/.fist-mbt/longrun"
  }
  base + "/" + task_id + ".json"
}

///|
/// 逐层补建父目录（`@fs.create_dir` 只建单层，父层缺失会 raise —— BUG-390）。
/// 与 store 的 `ensure_dir_tree` 同形（含「盘符根不当目录建」的豁免），
/// 但**独立**：那份是包私有且服务于 db 文件，本轮不重构它（最小改动）。
fn ensure_parent_dir(file_path : String) -> Unit {
  let chars = file_path.to_array()
  let n = chars.length()
  let mut i = 0
  while i < n {
    let c = chars[i]
    if c == '/' || c == '\\' {
      if i > 0 {
        let prefix = file_path[0:i].to_owned()
        // 盘符根（`E:` / `C:`）不当目录建
        if !(prefix.length() == 2 && prefix[1] == ':') {
          @fs.create_dir(prefix) catch {
            _ => ()
          }
        }
      }
    }
    i = i + 1
  }
}

///|
/// 构造快照体（**纯函数**）：`{format, task_id, written_at, task}`。
/// 单独成件是为了让白盒能钉「信封字段齐全」，而不必先有文件系统。
pub fn snapshot_body(
  task_id : String,
  task : @core.Task,
  written_at : String,
) -> Json {
  let m : Map[String, Json] = Map([])
  m.set("format", Json::string(snapshot_format))
  m.set("task_id", Json::string(task_id))
  m.set("written_at", Json::string(written_at))
  m.set("task", task.to_json())
  Json::object(m)
}

///|
/// 解析快照文本（**纯函数**）：返回 `(task_id, task_json)`。
///
/// 拒绝条件（三条都 fail-closed，不做「尽力猜测」）：
///   1. 不是合法 JSON；2. 格式标记不等于 `snapshot_format`；3. 顶层 `task` 不是对象。
/// 拒绝文案点名缺哪一条 —— 调用方（人/agent）据此知道是「文件损坏」还是「拿错了文件」。
pub fn parse_snapshot(text : String) -> Result[(String, Json), String] {
  let parsed = @json.parse(text) catch {
    _ => return Err("快照不是合法 JSON（可能损坏或被截断）")
  }
  match parsed {
    Object(m) => {
      match m.get("format") {
        Some(String(f)) =>
          if f != snapshot_format {
            return Err(
              "快照格式不符：实得 [" +
              f +
              "]，期望 [" +
              snapshot_format +
              "]（可能是别的工具写的文件，或本工具升级过）",
            )
          }
        _ =>
          return Err(
            "快照缺 format 字段（信封不完整，拒绝恢复）",
          )
      }
      let task_id = match m.get("task_id") {
        Some(String(s)) => s
        _ =>
          return Err(
            "快照缺 task_id 字段（无法确认它属于哪个任务）",
          )
      }
      match m.get("task") {
        Some(t) =>
          match t {
            Object(_) => Ok((task_id, t))
            _ =>
              return Err("快照 task 字段不是对象（任务体损坏）")
          }
        None =>
          return Err("快照缺 task 字段（没有可恢复的任务体）")
      }
    }
    _ => Err("快照顶层不是 JSON 对象")
  }
}

///|
/// 字节 → 字符串（与 store 的 `str_from_bytes` 同一手法：UTF-8 解码到 StringBuilder）。
fn bytes_to_string(b : Bytes) -> String {
  let sb = StringBuilder()
  @encoding.decode_to(b, sb, encoding=UTF8) catch {
    _ => ()
  }
  sb.to_string()
}

///|
/// 写快照落盘：建父目录 → 写 UTF-8 → 回读校验。
///
/// **回读校验不是装饰**：写完立刻读回来 parse 一遍，能当场发现「落盘成功但内容不可解析」
/// （磁盘满/编码异常/并发写半截）。这类失败若留到 resume 才暴露，人就丢了唯一一份上下文。
/// 返回 `(路径, 回读到的 task_id)`。
pub fn write_snapshot(
  project_dir : String,
  task : @core.Task,
  written_at : String,
) -> Result[(String, String), String] {
  let task_id = task.get_id()
  let path = snapshot_path(project_dir, task_id)
  ensure_parent_dir(path)
  let body = snapshot_body(task_id, task, written_at).stringify()
  @fs.write_string_to_file(path, body) catch {
    // IOError 未实现 Show ⇒ 不能插值进文案（会编译失败）；路径已足够定位
    _ => return Err("快照写入失败（IO 错误）：\{path}")
  }
  let data : Bytes? = Some(@fs.read_file_to_bytes(path)) catch { _ => None }
  match data {
    None => return Err("快照回读失败：文件不可读 \{path}")
    Some(b) =>
      match parse_snapshot(bytes_to_string(b)) {
        Ok((tid, _)) =>
          if tid != task_id {
            return Err(
              "快照回读校验失败：写入的是 [" +
              task_id +
              "]，读回 [" +
              tid +
              "]（文件被并发改写？）",
            )
          }
        Err(e) => return Err("快照回读校验失败：\{e}")
      }
  }
  Ok((path, task_id))
}

///|
/// 读快照文件（IO 外壳）：文件不存在/不可读/空文件 ⇒ Err（fail-closed，不返回空上下文）。
pub fn read_snapshot(path : String) -> Result[(String, Json), String] {
  if !@fs.path_exists(path) {
    return Err(
      "快照文件不存在：\{path}（先跑 fist_longrun_checkpoint）",
    )
  }
  let data : Bytes? = Some(@fs.read_file_to_bytes(path)) catch { _ => None }
  match data {
    None => Err("快照文件不可读：\{path}")
    Some(b) =>
      if b.length() == 0 {
        Err("快照文件为空：\{path}（写入未完成即中断）")
      } else {
        parse_snapshot(bytes_to_string(b))
      }
  }
}

///|
/// 跨包取目标态：**不能直接写 `@core.Claimed`**（只读类型的枚举值不可在包外构造，
/// 实测报 `Cannot create values of the read-only type`）。本仓惯例（omega_orphan_wbtest
/// 已记）是走 `TaskStatus::from_string`；这里包一层并把「口径漂移」显式变成 Err，
/// 而不是静默 unwrap。
fn claimed_status() -> Result[@core.TaskStatus, String] {
  match @core.TaskStatus::from_string("已领取") {
    Some(s) => Ok(s)
    None =>
      Err(
        "内部错误：TaskStatus::from_string(\"已领取\") 返回空（状态名口径漂移）",
      )
  }
}

///|
/// **resume 的状态机裁决（纯函数，P0 的核心）**。
///
/// 合法前置态与目标态：
///   · `Paused`（已暂停）  → `Claimed`（已领取）：与 `Task::resume_task` 同一口径，零新增迁移；
///   · `Executing`（执行中）→ `Claimed`（已领取）：**跨会话中断重入**——上一会话崩在执行的
///     中途，这是长程接力最典型的场景。不放这条，「接力」就只剩暂停/恢复那半条腿；
///   · `Claimed`（已领取）  → `Claimed`：幂等重入（重复 resume 不产生第二次状态迁移）。
///
/// 明确拒绝：待领取（还没开始，无可恢复）、拆分中（拆解中态由 split 流程独占）、
/// 待验收/已完成/已归档/已打回（都不该被「续接」绕过验收或审计）。
///
/// ⚠️ 本裁决**只决定状态迁移方向**，不负责检查快照存不存在——那是 `resume_precheck` 的事，
/// 两层分开才各自可测（判例-29：机制格 ≠ 实现路径格）。
pub fn resume_target_status(
  status : @core.TaskStatus,
) -> Result[@core.TaskStatus, String] {
  let target = match claimed_status() {
    Ok(s) => s
    Err(e) => return Err(e)
  }
  match status {
    @core.Paused => Ok(target)
    @core.Executing => Ok(target)
    @core.Claimed => Ok(target)
    other =>
      Err(
        "非法 longrun resume：状态 [" +
        other.to_string() +
        "] 不可从快照续接。出路：" +
        resume_exit_hint(other),
      )
  }
}

///|
/// resume 被拒时的出路文案（按当前状态给可执行的下一步，与 `execute_exit_hint` 同风格）。
fn resume_exit_hint(status : @core.TaskStatus) -> String {
  match status {
    @core.Pending =>
      "待领取→先 claim 再 execute（尚未开始，无上下文可恢复）"
    @core.Splitting =>
      "拆分中→先等拆解完成（split 流程独占该态），完成后再 resume"
    @core.Reviewing =>
      "待验收→若要返工先 reject（→已打回）再 retry（→执行中），再 resume"
    @core.Completed =>
      "已完成→如需续做请 reopen_task（→待领取）后重新走链路，勿用 resume 覆盖旧账"
    @core.Archived =>
      "已归档→不可写；确需返工先 reopen_task，勿用 resume 绕过归档"
    @core.Rejected => "已打回→先 retry（→执行中），再 resume"
    _ =>
      "已是可续接状态（已领取/执行中/已暂停），可直接 resume"
  }
}

///|
/// resume 的完整前置裁决：状态合法 **且** 快照存在可读。
/// 返回目标状态，供 server 层一次性接线；出错文案已点名是哪一层不成立。
pub fn resume_precheck(
  task : @core.Task,
  checkpoint_path : String,
) -> Result[@core.TaskStatus, String] {
  let target = match resume_target_status(task.get_status()) {
    Ok(s) => s
    Err(e) => return Err(e)
  }
  let path = if checkpoint_path != "" {
    checkpoint_path
  } else {
    snapshot_path(task.project_dir, task.get_id())
  }
  match read_snapshot(path) {
    Ok((tid, _)) =>
      if tid != task.get_id() {
        return Err(
          "快照与任务不匹配：文件属 [" +
          tid +
          "]，任务是 [" +
          task.get_id() +
          "]（拒绝把别人的上下文恢复进来）",
        )
      }
    Err(e) => return Err("resume 前置不成立：\{e}")
  }
  Ok(target)
}
