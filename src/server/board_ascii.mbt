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
    if not(rendered.contains(st)) {
      append_group(lines, st, arr)
    }
  }
  let sum : Array[String] = []
  for (st, arr) in buckets {
    sum.push(st + ":" + arr.length().to_string())
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
    } else {
      1
    }
  })
  for t in sorted {
    let mut indent = ""
    for _k = 0; _k < t.depth; _k = _k + 1 {
      indent = indent + "· "
    }
    let short_id = if t.get_id().length() > 10 {
      t.get_id().substring(start=0, end=10)
    } else {
      t.get_id()
    }
    let mut desc = t.get_description()
    if desc.length() > 40 {
      desc = desc.substring(start=0, end=40) + "…"
    }
    // R55：看板每行标注自身难度档（复用 pub extract_difficulty 单一来源，支柱①②"一目了然+复用"）
    let mut diff_note = ""
    let raw_diff = @engine.extract_difficulty(t.get_description())
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
    lines.push(indent + "[" + st + "] " + short_id + " · " + desc + diff_note)
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
    "by_difficulty": Json::object(diffJson),
    "active_namespaces": Json::array(active_ns.map(fn(s) { Json::string(s) })),
  })
}

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
  let grade = if total == 0 {
    "empty"
  } else if blocked > 0 {
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
  let done_cycles : Array[Int] = []
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
    let p50 = done_cycles[n * 50 / 100]
    let p90 = done_cycles[n * 90 / 100]
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
