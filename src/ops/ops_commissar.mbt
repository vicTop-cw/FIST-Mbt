/// ops_commissar.mbt —— 政委引导提醒监控体系（同机异进程消息池）
///
/// 体系组成（`.commissar/` 目录，位于**项目根**，同机共享；T0r3 正式化）：
///   events/          **信号目录（唯一收发信道）**：send 侧写 `<id>.rhop` 信封文件；
///                    接收侧用 `commissar_read` **同步遍历**读出（一次性、不订阅）。
///   inbox/           R1 引导提醒落盘：guidance 信号到达后写入 `<ts>.md`，供目标角色/管家查收。
///   outbox/          **出站目录（预留）**：接收侧回执 / reply 通道的落点。
///                    本版本只建目录、不写入 —— 谁写、写什么语义留给后续单元定案。
///   archive/         **归档目录（预留）**：已消费信号的人工/工具归档落点。
///                    本模块**不自动搬移**（自动搬会让"读过的还在不在"变得不可预期）。
///   reminder_log.md  R4 心跳汇报：轮询/事件摘要追加日志，供 supervisor_status 展示。
///
/// ⚠️ **没有迁移到 `.fist-mbt/pool/messages/`**：4 池子提案的 owner 未定案，
///    本模块不为未定案的目录布局预支兼容成本。
///
/// 职责映射（docs/2026-10-12-fist-mbt-reminder-role-plan.md）：
///   R1 引导提醒  = guidance 信号（进程 A 注入引导 -> 进程 B 提醒落盘）
///   R2 方向偏离  = stale 信号 / commissar_tick 扫描（活跃任务超时未更新）
///   R3 事项提醒  = pending 信号 / commissar_tick 扫描（待处理任务超时未被接管）
///   R4 心跳汇报  = heartbeat 信号 / commissar_tick 摘要 -> reminder_log.md
///
/// 运行方式：
///   moon run cmd/commissar -- watch <project_dir>   # ⚠️ 不可接 MCP（订阅型，见 BUG-480）
///   moon run cmd/commissar -- send  <project_dir> <kind> <target> <text>
///   moon run cmd/commissar -- tick  <project_dir>   # 一次性全量检查

///|
/// 政委根目录
pub fn commissar_root(project_dir : String) -> String {
  project_dir + "/.commissar"
}

///|
/// 信号目录（send 写 / watch 监听）
pub fn commissar_events_dir(project_dir : String) -> String {
  commissar_root(project_dir) + "/events"
}

///|
/// R1 引导提醒收件箱
pub fn commissar_inbox_dir(project_dir : String) -> String {
  commissar_root(project_dir) + "/inbox"
}

///|
/// 出站目录（接收侧回执 / reply 通道的预留落点；本版本只建目录不写入）
pub fn commissar_outbox_dir(project_dir : String) -> String {
  commissar_root(project_dir) + "/outbox"
}

///|
/// 归档目录（已消费信号的归档落点；本模块不自动搬移）
pub fn commissar_archive_dir(project_dir : String) -> String {
  commissar_root(project_dir) + "/archive"
}

///|
/// R4 心跳汇报日志
pub fn commissar_log_path(project_dir : String) -> String {
  commissar_root(project_dir) + "/reminder_log.md"
}

///|
/// 确保 `.commissar` 目录树存在（幂等）。
///
/// T0r3 起覆盖**四子目录**：`events/`（收发信道）、`inbox/`（R1 落盘）、
/// `outbox/`（回执预留）、`archive/`（归档预留）。
/// outbox/archive 目前**只建不写** —— 建出来是为了让「目录约定」在同机上是同一个事实，
/// 而不是每个消费者各自猜。
pub fn commissar_ensure_dirs(project_dir : String) -> Unit {
  commissar_ensure_dir(commissar_root(project_dir))
  commissar_ensure_dir(commissar_events_dir(project_dir))
  commissar_ensure_dir(commissar_inbox_dir(project_dir))
  commissar_ensure_dir(commissar_outbox_dir(project_dir))
  commissar_ensure_dir(commissar_archive_dir(project_dir))
}

///|
fn commissar_ensure_dir(p : String) -> Unit {
  if @fs.path_exists(p) {
    return
  }
  @fs.create_dir(p) catch {
    _ => ()
  }
}

///|
/// 政委信号（R1-R4 统一载荷，置于 RhopPacket.payload）
pub struct CommissarSignal {
  kind : String
  target : String
  text : String
  ns : String
}

///|
pub fn CommissarSignal::new(
  kind~ : String,
  target~ : String,
  text~ : String,
  ns~ : String = "default",
) -> CommissarSignal {
  { kind, target, text, ns, }
}

///|
pub fn CommissarSignal::to_json(self : CommissarSignal) -> Json {
  Json::object({
    "kind": Json::string(self.kind),
    "target": Json::string(self.target),
    "text": Json::string(self.text),
    "ns": Json::string(self.ns),
  })
}

///|
pub fn CommissarSignal::from_json(payload : Json) -> CommissarSignal? {
  if payload
    is {
      "kind": String(kind),
      "target": String(target),
      "text": String(text),
      "ns": String(ns),
      ..
    } {
    Some({ kind, target, text, ns, })
  } else {
    None
  }
}

///|
fn signal_line(sig : CommissarSignal, at_ms : Int64) -> String {
  "[\{at_ms.to_string()}] kind=\{sig.kind} target=\{sig.target} ns=\{sig.ns}\n  \{sig.text}\n"
}

///|
fn append_log(project_dir : String, line : String) -> Unit {
  let path = commissar_log_path(project_dir)
  let old = if @fs.path_exists(path) {
    @fs.read_file_to_string(path) catch {
      _ => ""
    }
  } else {
    ""
  }
  @fs.write_string_to_file(path, old + line) catch {
    _ => eprintln("commissar: 写 reminder_log 失败: \{path}")
  }
}

///|
/// 发送一条政委信号（进程 A / 指挥官 / 外部 agent 调用）。
/// at_ms 为 epoch 毫秒（调用方提供，js 目标可用 Date.now()）。
/// 事件文件写入 events/ 目录，watch 进程实时收到。
pub fn commissar_send(
  project_dir : String,
  sig : CommissarSignal,
  at_ms : Int64,
) -> Unit {
  commissar_ensure_dirs(project_dir)
  let id = "sig-\{at_ms.to_string()}-\{commissar_seq_next().to_string()}"
  let pkt = @rhop.RhopPacket::new(
    id,
    "commissar-send",
    sig.kind,
    sig.to_json(),
    at_ms,
  )
  @rhop.rhop_send(
    commissar_events_dir(project_dir),
    id,
    pkt,
    @rhop.RhopCipherNone::new(),
  )
  eprintln("commissar: sent \{id} kind=\{sig.kind} target=\{sig.target}")
}

///|
/// 一次性提醒检查（R2/R3 全量扫描 + R4 心跳汇报落日志）。
/// 返回 JSON 摘要，供 supervisor_status / CLI 展示。
pub fn commissar_tick(
  engine : @engine.FistEngine,
  now~ : String,
  project_dir~ : String,
  stale_hours~ : Int32 = 24,
  pending_hours~ : Int32 = 48,
) -> Json {
  let scan = engine.supervisor_reminder_tick(now~, stale_hours~, pending_hours~)
  let count = reminder_count_of(scan)
  let log_line = "== commissar_tick \{now} ==\n  发现提醒 \{count.to_string()} 条\n"
  append_log(project_dir, log_line)
  Json::object({
    "ts": Json::string(now),
    "stale_hours": Json::number(stale_hours.to_double()),
    "pending_hours": Json::number(pending_hours.to_double()),
    "reminder_count": Json::number(count.to_double()),
    "scan": scan,
  })
}

///|
/// 政委常驻监听（进程 B）：事件驱动，信号到达立即处理，不做轮询。
/// js 目标基于 node fs.watch（persistent），进程保持；native 目标为占位（打印 Unsupported）。
pub fn commissar_watch(
  engine : @engine.FistEngine,
  project_dir~ : String,
  now~ : String,
  stale_hours~ : Int32 = 24,
  pending_hours~ : Int32 = 48,
) -> Unit {
  commissar_ensure_dirs(project_dir)
  let events = commissar_events_dir(project_dir)
  let source = @rhop.from_filesystem_with(
    events,
    @rhop.RhopCipherNone::new(),
    true,
  )
  let _ = source.subscribe(
    @rx.Observer::new(
      fn(pkt : @rhop.RhopPacket) {
        let at = pkt.at
        match CommissarSignal::from_json(pkt.payload) {
          None => eprintln("commissar: 忽略无法解析的信号 \{pkt.id}")
          Some(sig) => {
            append_log(project_dir, signal_line(sig, at))
            match sig.kind {
              "guidance" =>
                // R1 引导提醒：落 inbox/<ts>.md 供目标角色查收
                write_inbox(project_dir, sig, at)
              "heartbeat" =>
                // R4 心跳汇报：摘要已入日志，不额外动作
                eprintln("commissar: heartbeat from \{sig.target}: \{sig.text}")
              // R2/R3 及任意信号：触发一次全量提醒检查
              _ => {
                let r = commissar_tick(
                  engine,
                  now~,
                  project_dir~,
                  stale_hours~,
                  pending_hours~,
                )
                eprintln(
                  "commissar: \{sig.kind} 触发检查，提醒 \{reminder_count_of(r).to_string()} 条",
                )
              }
            }
          }
        }
      },
      fn(err : String) { eprintln("commissar watch error: \{err}") },
      fn() { eprintln("commissar watch completed") },
    ),
  )
  eprintln(
    "commissar watch started: \{events}（事件驱动，Ctrl-C 退出）",
  )
  // js 目标：fs.watch persistent 保持事件循环；native 目标（占位）自然返回。
}

///|
/// R1 引导提醒落盘：inbox/<ts>.md
fn write_inbox(
  project_dir : String,
  sig : CommissarSignal,
  at_ms : Int64,
) -> Unit {
  let path = commissar_inbox_dir(project_dir) + "/" + at_ms.to_string() + ".md"
  let content = "---\nkind: \{sig.kind}\ntarget: \{sig.target}\nns: \{sig.ns}\nat: \{at_ms.to_string()}\n---\n\n\{sig.text}\n"
  @fs.write_string_to_file(path, content) catch {
    _ => eprintln("commissar: 写 inbox 失败: \{path}")
  }
  eprintln("commissar: R1 引导提醒已投递 inbox -> \{path}")
}

///|
/// 从 commissar_tick 返回 JSON 提取提醒条数
fn reminder_count_of(j : Json) -> Int32 {
  match j {
    Object(obj) =>
      match obj.get("reminder_count") {
        Some(Number(n, ..)) => n.to_int()
        _ => 0
      }
    _ => 0
  }
}

///|
/// 进程内自增序号（同进程连续发送同毫秒时保证文件名唯一）。
let commissar_seq : @ref.Ref[Int32] = Ref(0)

///|
fn commissar_seq_next() -> Int32 {
  let v = commissar_seq.val
  commissar_seq.val = v + 1
  v
}

// ══════════════════════════════════════════════════════════════════════════
// 接收侧 · **同步读取**（T0r3）
//
// 为什么是「同步读」而不是「订阅」：**BUG-480 / 账本结论** —— js 后端
// `@rhop.from_filesystem_with` 底层是 `fs.watch(path, {persistent: true})`，
// 即便 `Subscription::dispose()` 之后 handle 也**不释放** ⇒ 一旦把订阅型工具
// 注册成 MCP 工具，**server 进程永不退出**。而 MCP 本身是请求/响应模型，
// 「持续订阅」与它不匹配。
//
// ⇒ 本模块的接收面 = **一次性遍历目录**：
//    无 watcher / 无 Subscription / 无后台任务 / 无句柄要释放，
//    调用返回即结束，进程随时可以退出。
//    要持续收消息 ⇒ **反复调用**（短轮询），而不是让长驻订阅可关闭。
// ══════════════════════════════════════════════════════════════════════════

///|
/// 读取面：一条**已成功解码**的政委信号。
///
/// 与 `CommissarSignal`（发送侧载荷）分开：读取面还要带出 rhop 信封里的
/// `id` / `source` / `at`（游标字段），那是信封的，不是 payload 的。
pub struct CommissarEntry {
  id : String
  source : String
  kind : String
  target : String
  text : String
  ns : String
  at : Int64
}

///|
pub fn CommissarEntry::to_json(self : CommissarEntry) -> Json {
  Json::object({
    "id": Json::string(self.id),
    "source": Json::string(self.source),
    "kind": Json::string(self.kind),
    "target": Json::string(self.target),
    "text": Json::string(self.text),
    "namespace": Json::string(self.ns),
    // seq 与 at_ms 同值：`seq` 是给 `since_seq` 游标用的名字，
    // `at_ms` 是它的物理含义（信号发送时刻 epoch 毫秒）。两个都发，免得调用方猜。
    "seq": Json::number(self.at.to_double()),
    "at_ms": Json::number(self.at.to_double()),
  })
}

///|
/// 读取面回执：信号数组 + **逐类跳过统计**。
///
/// 为什么把"跳过"拆成这么多格而不是一个 `skipped` 总数：
/// 坏文件、解不开的密文、能解密但 payload 不合规是**四种不同的故障**，
/// 合成一个数就只剩"有东西被丢了"，没人能判断该修哪一段（BUG-74 同族：
/// 两栏混读会把"没读到"读成"没有"）。
pub struct CommissarReadReport {
  events_dir : String
  dir_exists : Bool
  /// 非空表示**目录级**故障（读目录失败）；空串表示这次扫描本身是可信的
  error : String
  entries : Array[CommissarEntry]
  /// 目录里 `*.rhop` 文件总数（= 本次真正尝试解码的个数）
  scanned : Int32
  /// 通过 kind/target/since_seq 过滤后、截断前的条数
  matched : Int32
  /// 实际返回条数（= entries.length()）
  returned : Int32
  /// 非 `.rhop` 文件数（`.rhop.tmp` 残留等）
  ignored : Int32
  filtered_kind : Int32
  filtered_target : Int32
  before_cursor : Int32
  bad_read : Int32
  bad_envelope : Int32
  bad_decrypt : Int32
  bad_packet : Int32
  bad_payload : Int32
  /// "文件名: 原因"（最多 20 条 + 一行省略提示）—— 坏文件**逐个点名**，不静默吞
  bad_files : Array[String]
  /// 因 limit 被截掉的条数（= 被截掉的更早信号数）
  dropped_by_limit : Int32
}

///|
pub fn CommissarReadReport::to_json(self : CommissarReadReport) -> Json {
  let bad_total = self.bad_read +
    self.bad_envelope +
    self.bad_decrypt +
    self.bad_packet +
    self.bad_payload
  Json::object({
    "events_dir": Json::string(self.events_dir),
    "dir_exists": Json::boolean(self.dir_exists),
    "error": Json::string(self.error),
    "entries": Json::array(self.entries.map(fn(e) { e.to_json() })),
    "counts": Json::object({
      "scanned": commissar_jint(self.scanned),
      "matched": commissar_jint(self.matched),
      "returned": commissar_jint(self.returned),
      "ignored_non_rhop": commissar_jint(self.ignored),
    }),
    "skipped": Json::object({
      "filtered_kind": commissar_jint(self.filtered_kind),
      "filtered_target": commissar_jint(self.filtered_target),
      "before_cursor": commissar_jint(self.before_cursor),
      "dropped_by_limit": commissar_jint(self.dropped_by_limit),
    }),
    "bad": Json::object({
      "total": commissar_jint(bad_total),
      "read": commissar_jint(self.bad_read),
      "envelope": commissar_jint(self.bad_envelope),
      "decrypt": commissar_jint(self.bad_decrypt),
      "packet": commissar_jint(self.bad_packet),
      "payload": commissar_jint(self.bad_payload),
      "files": Json::array(self.bad_files.map(fn(s) { Json::string(s) })),
    }),
  })
}

///|
fn commissar_jint(n : Int32) -> Json {
  Json::number(n.to_double())
}

///|
/// 坏文件登记（最多留 20 条明细，之后只留一行省略提示 —— 明细不为输出体积服务，
/// 但**计数永远是全量**，不存在"因为太多所以不数了"）。
fn commissar_record_bad(
  list : Array[String],
  name : String,
  reason : String,
) -> Unit {
  if list.length() < 20 {
    list.push("\{name}: \{reason}")
  } else if list.length() == 20 {
    list.push(
      "……更多坏文件已省略明细（见 bad.total 计数，计数是全量的）",
    )
  }
}

///|
/// 列目录（失败返回空数组，并把原因写进 `err` —— 不挂在返回值上，
/// 是为了让"没有目录"与"目录读不了"在回执里仍然是两件事）。
fn commissar_list_names(dir : String, err : @ref.Ref[String]) -> Array[String] {
  let names = @fs.read_dir(dir) catch {
    _ => {
      err.val = "commissar_read: 读目录失败（权限不足或不是目录）：\{dir}"
      []
    }
  }
  names.to_owned()
}

///|
/// **同步读取** `.commissar/events/*.rhop` —— 一次性遍历，不订阅、不留句柄。
///
/// 解码链（与 `commissar_send` 成对，全部走 rhop **自己的**解码器）：
///   读盘 → `RhopEnvelope::decode` → `RhopCipher::decrypt`
///   → `RhopPacket::from_json_text` → `CommissarSignal::from_json`
///
/// 参数：
///   limit      最多返回多少条（默认 100；`<=0` 回落默认；上限 1000）。
///              取**最新** limit 条，按时间升序（旧→新）返回 —— 队列消费的自然顺序。
///   kind       按信号类别精确过滤（空串 = 不过滤）
///   target     按目标精确过滤（空串 = 不过滤）
///   since_seq  游标下界，**闭区间**（`seq >= since_seq`），`seq` = 信号发送时刻 epoch 毫秒。
///              默认 0 = 不截断。⚠️ 闭区间的取舍：同一毫秒的多条会**一起**进出
///              （宁可重复，不可丢 —— 丢消息比重复一条更难查）。
///
/// 坏文件策略：**逐个计数 + 逐个点名原因**，且坏文件**不影响**其余文件读出。
/// 目录不存在 ⇒ 返回空 + `dir_exists=false`，**不是错误**（"还没人发过"是合法状态）。
pub fn commissar_read(
  project_dir : String,
  limit~ : Int32 = 100,
  kind~ : String = "",
  target~ : String = "",
  since_seq~ : Int64 = 0L,
) -> CommissarReadReport {
  let events = commissar_events_dir(project_dir)
  let entries : Array[CommissarEntry] = []
  let bad_files : Array[String] = []
  let err : @ref.Ref[String] = @ref.Ref("")
  let mut scanned = 0
  let mut ignored = 0
  let mut filtered_kind = 0
  let mut filtered_target = 0
  let mut before_cursor = 0
  let mut bad_read = 0
  let mut bad_envelope = 0
  let mut bad_decrypt = 0
  let mut bad_packet = 0
  let mut bad_payload = 0
  let dir_exists = @fs.path_exists(events)
  let names = if dir_exists { commissar_list_names(events, err) } else { [] }
  for name in names {
    if !name.has_suffix(".rhop") {
      // `.rhop.tmp`（原子写的中间态）也落在这里：它不是信号，不该算坏文件
      ignored = ignored + 1
      continue
    }
    scanned = scanned + 1
    let path = events + "/" + name
    let text = @fs.read_file_to_string(path) catch { _ => "" }
    if text == "" {
      bad_read = bad_read + 1
      commissar_record_bad(
        bad_files, name, "读盘失败或文件为空（空 .rhop 也是坏文件）",
      )
      continue
    }
    let env = match @rhop.RhopEnvelope::decode(text) {
      Err(reason) => {
        bad_envelope = bad_envelope + 1
        commissar_record_bad(bad_files, name, reason)
        continue
      }
      Ok(e) => e
    }
    if env.v != 1 {
      bad_envelope = bad_envelope + 1
      commissar_record_bad(
        bad_files,
        name,
        "信封版本不支持：v=\{env.v.to_string()}（本读取器只认 v=1）",
      )
      continue
    }
    if env.alg != "none" {
      // 只认 none：拿 RhopCipherNone 去解别的 alg 会得到垃圾明文，
      // 然后在 packet 层报"字段缺失"—— 那会把"解不开密文"误报成"payload 不合规"
      bad_decrypt = bad_decrypt + 1
      commissar_record_bad(
        bad_files,
        name,
        "信封 alg=\{env.alg}，本读取器只支持 none（无法解密）",
      )
      continue
    }
    let plain = match @rhop.RhopCipherNone::new().decrypt(env.ct) {
      None => {
        bad_decrypt = bad_decrypt + 1
        commissar_record_bad(
          bad_files, name, "解密失败：ct 不是合法 base64/UTF-8",
        )
        continue
      }
      Some(p) => p
    }
    let pkt = match @rhop.RhopPacket::from_json_text(plain) {
      Err(reason) => {
        bad_packet = bad_packet + 1
        commissar_record_bad(bad_files, name, reason)
        continue
      }
      Ok(p) => p
    }
    let sig = match CommissarSignal::from_json(pkt.payload) {
      None => {
        bad_payload = bad_payload + 1
        commissar_record_bad(
          bad_files, name, "payload 不是合法 CommissarSignal",
        )
        continue
      }
      Some(s) => s
    }
    if kind != "" && sig.kind != kind {
      filtered_kind = filtered_kind + 1
      continue
    }
    if target != "" && sig.target != target {
      filtered_target = filtered_target + 1
      continue
    }
    if pkt.at < since_seq {
      before_cursor = before_cursor + 1
      continue
    }
    let entry : CommissarEntry = {
      id: pkt.id,
      source: pkt.source,
      kind: sig.kind,
      target: sig.target,
      text: sig.text,
      ns: sig.ns,
      at: pkt.at,
    }
    entries.push(entry)
  }
  // 时间序（同一毫秒按 id 稳定 —— id 里带进程内自增序号）
  entries.sort_by(fn(a, b) {
    let c = a.at.compare(b.at)
    if c != 0 {
      c
    } else {
      a.id.compare(b.id)
    }
  })
  let matched = entries.length()
  let cap = if limit <= 0 { 100 } else if limit > 1000 { 1000 } else { limit }
  let start = if matched > cap { matched - cap } else { 0 }
  let out : Array[CommissarEntry] = []
  let mut i = start
  while i < matched {
    out.push(entries[i])
    i = i + 1
  }
  {
    events_dir: events,
    dir_exists,
    error: err.val,
    entries: out,
    scanned,
    matched,
    returned: out.length(),
    ignored,
    filtered_kind,
    filtered_target,
    before_cursor,
    bad_read,
    bad_envelope,
    bad_decrypt,
    bad_packet,
    bad_payload,
    bad_files,
    dropped_by_limit: start,
  }
}

///|
/// **运维侧清理**：`commissar_gc(keep~)` —— 保留最近 N 条 `.rhop`，其余删掉。
///
/// ## 为什么参数是 `keep` 而不是 `retention_hours`（设计形状限制，不是代码细节）
///
/// 本包可用的 `@fs` 接口是：`path_exists` / `read_dir` / `read_file_to_string` /
/// `write_string_to_file` / `create_dir` / `remove_dir` / `remove_file` ——
/// **没有 `stat` / `mtime` / `metadata`** ⇒ 拿不到「文件多老」⇒ 按小时删**不可行**。
///
/// 改成「保留最近 N 条」不但可行，**语义还更好**：不依赖时钟（时钟回拨/时区不影响）、
/// 可预测、且与 seq 的「位置」语义天然对齐。
///
/// ## 排序键：文件名（`sig-<at_ms>-<counter>.rhop`）
///
/// `at_ms` 是 13 位 epoch 毫秒 ⇒ **按文件名字典序 == 按时间序**（同位数左对齐）。
/// 同一毫秒内用 `counter` 兜底 ⇒ 全序稳定。
///
/// ## 为什么不在 `commissar_read` 里裁
///
/// 读操作删文件是**最坏的副作用类型**：两个客户端并发读会互相删掉对方**还没读的**。
/// 清理必须是**独立工具**，且必须由调用方显式选择「保留几条」。
///
/// 参数：`keep` 必须 ≥ 0；`dry_run=true` 只报不删。
/// 返回：删除的文件名列表 + 保留数 + 是否真删（`dry_run` 时 `deleted` 为空）。
pub fn commissar_gc(
  project_dir : String,
  keep~ : Int32 = 1000,
  dry_run~ : Bool = false,
) -> CommissarGcReport {
  let events = commissar_events_dir(project_dir)
  let err : @ref.Ref[String] = @ref.Ref("")
  // ⚠️ 目录不存在 ⇒ 不是错误（还没发过消息的仓就是这种态）；返回「删 0 保 0」。
  let names = if @fs.path_exists(events) {
    commissar_list_names(events, err)
  } else {
    []
  }
  // 只留 `.rhop`（`.rhop.tmp` 是原子写的中间态，不属于可清对象，也不该算进 keep 配额）
  let live : Array[String] = []
  for name in names {
    if name.has_suffix(".rhop") {
      live.push(name)
    }
  }
  // 按文件名升序 == 按时间升序（`at_ms` 同位数）
  live.sort()
  let n = live.length()
  let k = if keep < 0 { 0 } else { keep }
  // 保留**末尾**（最新）的 k 条；前缀超出的部分是可删集
  let cut = if n > k { n - k } else { 0 }
  let doomed : Array[String] = []
  let deleted : Array[String] = []
  let failed : Array[String] = []
  for i in 0..<n {
    if i < cut {
      doomed.push(live[i])
      if !dry_run {
        let path = events + "/" + live[i]
        @fs.remove_file(path) catch {
          _ => {
            failed.push(live[i])
            continue
          }
        }
        deleted.push(live[i])
      }
    }
  }
  CommissarGcReport::{
    total: n,
    kept: n - cut,
    doomed,
    deleted,
    failed,
    dry_run,
    err: err.val,
  }
}

///|
/// `commissar_gc` 的回执。
///
/// **分栏理由**（BUG-74 同族：「没删」和「删不掉」不许混读）：
///  `doomed` = 本次判定该删的（`dry_run` 时这就是预览全貌）
///  `deleted` = 真删成功的
///  `failed` = 判定该删但删失败的（**不静默吞**，否则下一个人会以为清干净了）
pub struct CommissarGcReport {
  /// 目录里 `.rhop` 总数（= kept + doomed）
  total : Int32
  /// 保留条数（= total - doomed）
  kept : Int32
  /// 判定该删的文件名（升序，早的在前）
  doomed : Array[String]
  /// 真删成功的文件名（`dry_run` 时恒空）
  deleted : Array[String]
  /// 判定该删但删失败的（`dry_run` 时恒空）
  failed : Array[String]
  dry_run : Bool
  /// 非空表示目录级故障（读目录失败）
  err : String
}
