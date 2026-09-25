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
    lines.push(indent + "[" + st + "] " + short_id + " · " + desc)
  }
}

///|
/// 项目脉冲摘要：返回 { version, total_tasks, by_status:{状态:数量}, active_namespaces }。
/// 供 agent 一次调用概览项目健康，无需 list+逐条筛选。
/// tasks 为引擎任务集；active_ns 为当前已打开命名空间清单；version 为模块版本串。
pub fn render_status_summary(
  tasks : Array[@core.Task],
  active_ns : Array[String],
  version : String,
) -> Json {
  let by_status : Map[String, Double] = Map([])
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
  }
  let stJson : Map[String, Json] = Map([])
  for (st, n) in by_status {
    stJson.set(st, Json::number(n))
  }
  Json::object({
    "version": Json::string(version),
    "total_tasks": Json::number(total.to_double()),
    "by_status": Json::object(stJson),
    "active_namespaces": Json::array(active_ns.map(fn(s) { Json::string(s) })),
  })
}
