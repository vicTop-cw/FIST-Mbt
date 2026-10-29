/// server/board_ascii.mbt —— 实时任务看板 ASCII（一眼看项目全貌）
///
/// 与 `fist://map`（静态代码库地图）、`dag_ascii`（依赖结构）互补：
/// 按状态分组 + 深度缩进渲染当前命名空间的全部任务，让 agent 一次读到
/// 「有哪些任务、各自什么状态、分布在树的哪一层」，不必全项目翻找。
/// 复用既有 @core 模型与引擎任务集，不新造存储。

///|
/// 用分隔符连接若干行（兼容双端，不依赖 Array.join）。
fn join_sep(lines : Array[String], sep : String) -> String {
  let sb = StringBuilder()
  let mut first = true
  for ln in lines {
    if first {
      sb.write_string(ln)
      first = false
    } else {
      sb.write_string(sep)
      sb.write_string(ln)
    }
  }
  sb.to_string()
}

///|
/// 看板渲染：返回 { counts: {状态:数量}, ascii: 多行字符串 }。
pub fn render_board_ascii(
  tasks : Array[@core.Task],
  ns_filter : String,
) -> Json {
  let order : Array[String] = [
    "待领取", "已领取", "拆分中", "执行中", "待验收", "已打回",
    "已完成", "已暂停", "已归档",
  ]
  // 按状态分组
  let buckets : Map[String, Array[@core.Task]] = Map([])
  for t in tasks {
    if ns_filter == "" || t.ns == ns_filter {
      let st = t.status_to_string()
      if st == "" {
        continue
      }
      match buckets.get(st) {
        Some(a) => a.push(t)
        None => buckets.set(st, [t])
      }
    }
  }
  // 计数
  let counts : Map[String, Double] = Map([])
  for (st, arr) in buckets {
    counts.set(st, arr.length().to_double())
  }
  // 渲染顺序：先 order 内状态，再追赶任何未列出的状态
  let rendered : Map[String, Bool] = Map([])
  let lines : Array[String] = []
  for st in order {
    match buckets.get(st) {
      None => ()
      Some(arr) => {
        rendered.set(st, true)
        append_group(lines, st, arr)
      }
    }
  }
  for (st, arr) in buckets {
    if !rendered.contains(st) {
      append_group(lines, st, arr)
    }
  }
  let sum : Array[String] = []
  let mut residue = 0
  for (st, arr) in buckets {
    // BUG-29：已完成档在合计行里直接标出"其中无交付物"，看板自证成果与残留
    if st == "已完成" {
      residue = done_no_artifact(arr)
    }
    let label = if st == "已完成" && residue > 0 {
      st +
      ":" +
      arr.length().to_string() +
      "(无交付物" +
      residue.to_string() +
      ")"
    } else {
      st + ":" + arr.length().to_string()
    }
    sum.push(label)
  }
  let ns_label = if ns_filter == "" { "全部命名空间" } else { ns_filter }
  let header = "== FIST 任务看板（" + ns_label + "） =="
  let body = join_sep(lines, "\n")
  let footer = "== 状态合计: " + join_sep(sum, "｜") + " =="
  let countsJson : Map[String, Json] = Map([])
  for (st, n) in counts {
    countsJson.set(st, Json::number(n))
  }
  Json::object({
    "counts": Json::object(countsJson),
    "done_no_artifact": Json::number(residue.to_double()),
    "ascii": Json::string(header + "\n" + body + "\n" + footer),
  })
}

///|
/// 把一个状态分组的任务追加到 lines（组内按深度、创建时间升序，深度缩进 + 状态 + 截断描述）。
fn append_group(
  lines : Array[String],
  st : String,
  arr : Array[@core.Task],
) -> Unit {
  let sorted = arr
  sorted.sort_by(fn(a, b) {
    if a.depth != b.depth {
      if a.depth < b.depth {
        -1
      } else {
        1
      }
    } else if a.created_at < b.created_at {
      -1
    } else if a.created_at > b.created_at {
      1
    } else {
      // BUG-210：depth 与 created_at 全等时按 id 升序收尾。旧实现落入此分支返回 1，
      // 导致 cmp(a,b)=cmp(b,a)=1——严格弱序反对称性被破坏，排序结果未定义。
      // id 全序 tiebreak 同时保证同刻批量发布任务的输出确定性
      //（与 dag_ascii L190、triage_rest L150 的 id 收尾模式一致）。
      a.get_id().compare(b.get_id())
    }
  })
  for t in sorted {
    let mut indent = ""
    for _k = 0; _k < t.depth; _k = _k + 1 {
      indent = indent + "· "
    }
    let tid = t.get_id()
    let short_id = if tid.length() > 10 { tid[0:10].to_owned() } else { tid }
    // R12-R6 性能：`t.get_description()` 对 SqliteStore 是 DB 读，这里只取一次。
    // 旧代码在同一行里调了两次（一次给 desc 截断，一次给 extract_difficulty），
    // 等于每任务 2 次 DB 读；2079 任务 → 多出 2079 次 DB 读。
    let full_desc = t.get_description()
    let mut desc = full_desc
    if desc.length() > 40 {
      // R152：**中文 description 的字节硬切会切在字符中间**（半个汉字 ⇒ 乱码）。
      // 走 @core.clip_utf8（全仓唯一的 UTF-8 边界安全截断真源）。
      desc = @core.clip_utf8(desc, 40) + "…"
    }
    // R55：看板每行标注自身难度档（复用 pub extract_difficulty 单一来源，支柱①②"一目了然+复用"）
    let mut diff_note = ""
    let raw_diff = @engine.extract_difficulty(full_desc)
    let diff_label = if raw_diff.contains("难") {
      "难"
    } else if raw_diff.contains("中") {
      "中"
    } else if raw_diff.contains("易") {
      "易"
    } else {
      ""
    }
    if diff_label != "" {
      diff_note = " 难度[" + diff_label + "]"
    }
    // 军衔标注（§8.1 军衔体系）：来源是 `t.get_level()`，与 depth（缩进）严格分离。
    // 叶子恒为士兵（leaf_label），非叶子按 rank_of(level) 定级（连长→排长→…）。
    let rank_label = if t.is_leaf() {
      @display.leaf_label(t.get_level())
    } else {
      @display.rank_of(t.get_level())
    }
    let rank_note = " 军衔[" + rank_label + "]"
    lines.push(
      indent +
      "[" +
      st +
      "] " +
      short_id +
      " · " +
      desc +
      rank_note +
      diff_note,
    )
  }
}

///|
/// 项目脉冲摘要：返回 { version, total_tasks, by_status:{状态:数量}, by_difficulty:{易/中/难/无:数量},
///   active_namespaces }。
/// 供 agent 一次调用概览项目健康，无需 list+逐条筛选。by_difficulty 统计"待领取"任务的难度结构，
/// 复用 @engine.extract_difficulty 单一抽取来源（支柱②复用），"难度一目了然"（支柱①）。
/// tasks 为引擎任务集；active_ns 为当前已打开命名空间清单；version 为模块版本串。
pub fn render_status_summary(
  tasks : Array[@core.Task],
  active_ns : Array[String],
  version : String,
) -> Json {
  let by_status : Map[String, Double] = Map([])
  let by_diff : Map[String, Double] = Map([
    ("易", 0.0),
    ("中", 0.0),
    ("难", 0.0),
    ("无", 0.0),
  ])
  let mut total = 0
  for t in tasks {
    let st = t.status_to_string()
    if st != "" {
      total = total + 1
      match by_status.get(st) {
        Some(n) => by_status.set(st, n + 1.0)
        None => by_status.set(st, 1.0)
      }
    }
    // 难度分布：仅统计待领取（可动手）任务
    if t.status_to_string() == "待领取" {
      let raw = @engine.extract_difficulty(t.description)
      let key = if raw.contains("难") {
        "难"
      } else if raw.contains("中") {
        "中"
      } else if raw.contains("易") {
        "易"
      } else {
        "无"
      }
      by_diff.set(key, by_diff.get(key).unwrap_or(0.0) + 1.0)
    }
  }
  let stJson : Map[String, Json] = Map([])
  for (st, n) in by_status {
    stJson.set(st, Json::number(n))
  }
  let diffJson : Map[String, Json] = Map([])
  for (d, n) in by_diff {
    diffJson.set(d, Json::number(n))
  }
  Json::object({
    "version": Json::string(version),
    "total_tasks": Json::number(total.to_double()),
    "by_status": Json::object(stJson),
    // BUG-29：已完成 ≠ 有交付物且被验过——探针/绕过验收的单会停在"已完成"。
    // 单列一档，读侧才能自证"已完成里有多少其实没交付物"。
    "done_no_artifact": Json::number(done_no_artifact(tasks).to_double()),
    "by_difficulty": Json::object(diffJson),
    "active_namespaces": Json::array(active_ns.map(fn(s) { Json::string(s) })),
  })
}

///|
/// 已完成但交付物为空的任务数（BUG-29 的"无成果已完成"档，全库口径由调用方传入的任务集决定）。
pub fn done_no_artifact(tasks : Array[@core.Task]) -> Int32 {
  let mut n = 0
  for t in tasks {
    if t.status_to_string() == "已完成" && t.deliverable == "" {
      n = n + 1
    }
  }
  n
}

///|
/// 残留硬门基线（BUG-29）：账本里**点名作废**的探针单数——T0r286/T0r287（memory/bugs.md BUG-29，
/// 判据=只读直查 status='已完成' 且 deliverable 空 且 specs=0 且 created_at==updated_at）。
/// 只许降不许升：新高出基线即 residue_over_baseline=true，project_health 据此把等级压到 attention。
let done_no_artifact_baseline : Int32 = 2

///|
/// 项目健康卡（R68）：单次调用看全项目健康，无需 list+逐条筛选。
/// 聚合 in_flight(执行中/已领取/拆分中) / ready(待领取) / done(已完成) /
/// blocked(已暂停/已打回) / reviewing(待验收) / archived(已归档) 六类计数，
/// 并给一档健康等级：empty(无任务) / attention(有阻塞) / stalled(无进行无就绪) /
/// healthy(有就绪或进行中且无阻塞)。——"agent 一眼看全项目健康"（支柱①）。
pub fn render_project_health(
  tasks : Array[@core.Task],
  version : String,
) -> Json {
  let mut in_flight = 0
  let mut ready = 0
  let mut done = 0
  let mut blocked = 0
  let mut reviewing = 0
  let mut archived = 0
  let blocked_ids : Array[String] = []
  for t in tasks {
    match t.status_to_string() {
      "执行中" | "已领取" | "拆分中" => in_flight = in_flight + 1
      "待领取" => ready = ready + 1
      "已完成" => done = done + 1
      "待验收" => reviewing = reviewing + 1
      "已归档" => archived = archived + 1
      "已暂停" | "已打回" => {
        blocked = blocked + 1
        blocked_ids.push(t.get_id())
      }
      _ => ()
    }
  }
  let total = tasks.length()
  // BUG-29 棘轮：已完成但无交付物（探针/绕过验收的残留）不得多于账本点名作废的基线；
  // 高出即把等级压到 attention——"已完成"不再自动等于成果，读侧一眼能看见差了多少条。
  let residue = done_no_artifact(tasks)
  let residue_over = residue > done_no_artifact_baseline
  let grade = if total == 0 {
    "empty"
  } else if blocked > 0 || residue_over {
    "attention"
  } else if in_flight == 0 && ready == 0 {
    "stalled"
  } else {
    "healthy"
  }
  Json::object({
    "version": Json::string(version),
    "grade": Json::string(grade),
    "total_tasks": Json::number(total.to_double()),
    "in_flight": Json::number(in_flight.to_double()),
    "ready": Json::number(ready.to_double()),
    "done": Json::number(done.to_double()),
    "done_no_artifact": Json::number(residue.to_double()),
    "done_no_artifact_baseline": Json::number(
      done_no_artifact_baseline.to_double(),
    ),
    "residue_over_baseline": Json::boolean(residue_over),
    "blocked": Json::number(blocked.to_double()),
    "reviewing": Json::number(reviewing.to_double()),
    "archived": Json::number(archived.to_double()),
    "blocked_tasks": Json::array(blocked_ids.map(fn(s) { Json::string(s) })),
  })
}

///|
/// 四金信号健康巡检（R102，Google SRE Book 2016「Monitoring Distributed Systems」四金信号
/// latency/traffic/errors/saturation 蒸馏）：project_health 从"一个等级"升级为"四个信号"——
/// latency=最近已完成任务完成周期（created_at→updated_at 秒，p50/p90，<3 条 insufficient，
/// SRE 要点：百分位而非均值）；traffic=活跃需求（in_flight 执行中+已领取+拆分中）；errors=
/// 失败率（已打回+已暂停/总数）；saturation=积压率（待领取/总数——SRE 先行指标：系统先积压
/// 后坏，>0.5 attention 预警）。单信号 verdict：saturation>0.5 attention / errors>0.3 attention
/// / latency insufficient / traffic=0 idle；grade=最差信号。纯计算、只读不写库。
pub fn render_health_check(tasks : Array[@core.Task], ns : String) -> Json {
  let total = tasks.length()
  let mut in_flight = 0
  let mut ready = 0
  let mut blocked = 0
  let done_cycles : Array[Int32] = []
  for t in tasks {
    match t.status_to_string() {
      "执行中" | "已领取" | "拆分中" => in_flight = in_flight + 1
      "待领取" => ready = ready + 1
      "已完成" => {
        let a = @ops.iso_to_secs(t.created_at)
        let b = @ops.iso_to_secs(t.updated_at)
        if a > 0 && b > 0 && b >= a {
          done_cycles.push(b - a)
        }
      }
      "已暂停" | "已打回" => blocked = blocked + 1
      _ => ()
    }
  }
  done_cycles.sort()
  let n = done_cycles.length()
  let latency_json = if n < 3 {
    Json::object({
      "verdict": Json::string("insufficient"),
      "count": Json::number(n.to_double()),
      "note": Json::string(
        "已完成样本 <3，无法算百分位（SRE：用百分位不用均值）",
      ),
    })
  } else {
    // BUG-207：p50/p90 索引用最近秩口径 (n-1)*p/100（复用 @engine.mc_percentile_index）。
    // 旧代码 `done_cycles[n*50/100]` / `done_cycles[n*90/100]` 比最近秩恒高 1（升序数组里
    // 读偏高一个元素），系统性**高估** latency 的 p50 与 p90。现有测试只用 3 个相同周期
    // （全 120s）的任务，n*50/100 与 (n-1)*50/100 恰好相等，掩盖了偏差。
    let p50 = done_cycles[@engine.mc_percentile_index(n, 50)]
    let p90 = done_cycles[@engine.mc_percentile_index(n, 90)]
    Json::object({
      "verdict": Json::string("ok"),
      "count": Json::number(n.to_double()),
      "p50_secs": Json::number(p50.to_double()),
      "p90_secs": Json::number(p90.to_double()),
    })
  }
  let errors_rate = if total <= 0 {
    0.0
  } else {
    blocked.to_double() / total.to_double()
  }
  let saturation = if total <= 0 {
    0.0
  } else {
    ready.to_double() / total.to_double()
  }
  let errors_verdict = if errors_rate > 0.3 { "attention" } else { "ok" }
  let saturation_verdict = if saturation > 0.5 { "attention" } else { "ok" }
  let traffic_verdict = if in_flight <= 0 && ready <= 0 { "idle" } else { "ok" }
  let grade = if saturation_verdict == "attention" ||
    errors_verdict == "attention" {
    "attention"
  } else if traffic_verdict == "idle" {
    "idle"
  } else {
    "healthy"
  }
  Json::object({
    "ok": Json::boolean(true),
    "namespace": Json::string(ns),
    "total_tasks": Json::number(total.to_double()),
    "signals": Json::object({
      "latency": latency_json,
      "traffic": Json::object({
        "verdict": Json::string(traffic_verdict),
        "in_flight": Json::number(in_flight.to_double()),
        "ready": Json::number(ready.to_double()),
      }),
      "errors": Json::object({
        "verdict": Json::string(errors_verdict),
        "rate": Json::number(errors_rate),
        "blocked": Json::number(blocked.to_double()),
      }),
      "saturation": Json::object({
        "verdict": Json::string(saturation_verdict),
        "rate": Json::number(saturation),
        "backlog": Json::number(ready.to_double()),
        "note": Json::string(
          "SRE 先行指标：系统先积压后坏，>0.5 预警",
        ),
      }),
    }),
    "grade": Json::string(grade),
    "basis": Json::string(
      "Google SRE Book 2016 四金信号（latency/traffic/errors/saturation）蒸馏",
    ),
  })
}

///|
/// 状态流转 ASCII（P2 Dashboard「状态流转」）：把 Task 生命周期画成一行流程，
/// 让 agent 一次读到「合法迁移图 + 当前任务分布」。返回 { ascii, counts, in_flow }。
/// 与 board_ascii（按状态分组）、dag_ascii（依赖结构）、status_summary（脉冲）互补。
pub fn render_state_flow_ascii(
  tasks : Array[@core.Task],
  ns_filter : String,
) -> Json {
  let flow = "待领取 → 已领取 → 拆分中 → 执行中 → 待验收 → 已完成 → 已归档\n" +
    "                         │         │\n" +
    "                         ▼         ▼\n" +
    "                   已暂停→已领取  已打回→执行中\n" +
    "                        (恢复)       (重试)"
  let bucket : Map[String, Int32] = Map([])
  for t in tasks {
    if ns_filter == "" || t.ns == ns_filter {
      let st = t.status_to_string()
      if st == "" {
        continue
      }
      match bucket.get(st) {
        Some(n) => bucket.set(st, n + 1)
        None => bucket.set(st, 1)
      }
    }
  }
  let counts : Map[String, Json] = Map([])
  for (k, v) in bucket {
    counts.set(k, Json::number(v.to_double()))
  }
  // in_flow = ready(待领取) + in_flight(已领取/拆分中/执行中，对齐 project_health) + reviewing(待验收)；
  // 「已完成」是终态不计入。
  let in_flow_names = [
    "待领取", "已领取", "拆分中", "执行中", "待验收",
  ]
  let mut in_flow = 0
  for name in in_flow_names {
    match bucket.get(name) {
      Some(n) => in_flow = in_flow + n
      None => ()
    }
  }
  let sb = StringBuilder()
  sb.write_string(flow)
  sb.write_string("\n\n当前分布：")
  let order : Array[String] = [
    "待领取", "已领取", "拆分中", "执行中", "待验收", "已打回",
    "已完成", "已暂停", "已归档",
  ]
  let mut first = true
  for st in order {
    match bucket.get(st) {
      Some(n) => {
        if !first {
          sb.write_string("  ")
        }
        sb.write_string(st + "=" + n.to_string())
        first = false
      }
      None => ()
    }
  }
  if first {
    sb.write_string("(空)")
  }
  sb.write_string(
    "\n在流任务（待领取/已领取/拆分中/执行中/待验收）：" +
    in_flow.to_string(),
  )
  Json::object({
    "ascii": Json::string(sb.to_string()),
    "counts": Json::object(counts),
    "in_flow": Json::number(in_flow.to_double()),
  })
}
