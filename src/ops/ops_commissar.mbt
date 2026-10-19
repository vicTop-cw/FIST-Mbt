/// ops_commissar.mbt —— 政委引导提醒监控体系（同机异进程事件触发）
///
/// 体系组成（.commissar/ 目录，位于项目根，同机共享）：
///   events/        信号目录：send 进程（指挥官 / 外部 agent）写 .rhop 信封文件，
///                  watch 进程（政委常驻）用 rx-mbt rhop.from_filesystem_with
///                  （node fs.watch 事件驱动）实时接收 —— 事件触发，非轮询。
///   inbox/         R1 引导提醒落盘：guidance 信号到达后写入 <ts>.md 引导文件，
///                  供目标角色/管家查收。
///   reminder_log.md R4 心跳汇报：轮询/事件摘要追加日志，供 supervisor_status 展示。
///
/// 职责映射（docs/2026-10-12-fist-mbt-reminder-role-plan.md）：
///   R1 引导提醒  = guidance 信号（进程 A 注入引导 -> 进程 B 实时提醒落盘）
///   R2 方向偏离  = stale 信号 / commissar_tick 扫描（活跃任务超时未更新）
///   R3 事项提醒  = pending 信号 / commissar_tick 扫描（待处理任务超时未被接管）
///   R4 心跳汇报  = heartbeat 信号 / commissar_tick 摘要 -> reminder_log.md
///
/// 运行方式：
///   moon run cmd/commissar -- watch <project_dir>   # 政委常驻（事件驱动）
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
/// R4 心跳汇报日志
pub fn commissar_log_path(project_dir : String) -> String {
  commissar_root(project_dir) + "/reminder_log.md"
}

///|
/// 确保 .commissar 目录树存在（幂等）。
pub fn commissar_ensure_dirs(project_dir : String) -> Unit {
  commissar_ensure_dir(commissar_root(project_dir))
  commissar_ensure_dir(commissar_events_dir(project_dir))
  commissar_ensure_dir(commissar_inbox_dir(project_dir))
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
    _ => println("commissar: 写 reminder_log 失败: \{path}")
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
  println("commissar: sent \{id} kind=\{sig.kind} target=\{sig.target}")
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
          None => println("commissar: 忽略无法解析的信号 \{pkt.id}")
          Some(sig) => {
            append_log(project_dir, signal_line(sig, at))
            match sig.kind {
              "guidance" =>
                // R1 引导提醒：落 inbox/<ts>.md 供目标角色查收
                write_inbox(project_dir, sig, at)
              "heartbeat" =>
                // R4 心跳汇报：摘要已入日志，不额外动作
                println("commissar: heartbeat from \{sig.target}: \{sig.text}")
              // R2/R3 及任意信号：触发一次全量提醒检查
              _ => {
                let r = commissar_tick(
                  engine,
                  now~,
                  project_dir~,
                  stale_hours~,
                  pending_hours~,
                )
                println(
                  "commissar: \{sig.kind} 触发检查，提醒 \{reminder_count_of(r).to_string()} 条",
                )
              }
            }
          }
        }
      },
      fn(err : String) { println("commissar watch error: \{err}") },
      fn() { println("commissar watch completed") },
    ),
  )
  println(
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
    _ => println("commissar: 写 inbox 失败: \{path}")
  }
  println("commissar: R1 引导提醒已投递 inbox -> \{path}")
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
