/// engine_triage.mbt —— 下一步该做啥（Task Triage）：给"更好的 AI 项目管理工具"补推荐式挑选原语
///
/// dag_ready/board 只"列出"可领取任务；本原语进一步"推荐排序"——对指定命名空间（缺省全量）
/// 把"待领取且依赖已满足"的任务按下述序排出优先级，并给出一条"建议下一步"，供 agent
/// 无需全量扫描就能知道此刻该领哪条：
///   排序键：priority(高>中>低) → importance(高>中>低) → depth(叶=可执行单元优先，越小越前) → id(稳定)。
/// 难度标签直接复用 plan_deep gradient 嵌入子任务描述的 `难度梯度 i/n:易/中/难` 标记（未命中按深度粗判）。
/// 复用现有 store.list_all / deps_satisfied / get_status，无新表/依赖。

///|
/// 从任务描述提取 gradient 难度标签（`…:易]`/`…:中]`/`…:难]` 结尾），未命中返回空串。
fn triage_label_of(desc : String) -> String {
  if desc.contains(":易]") {
    "易"
  } else if desc.contains(":中]") {
    "中"
  } else if desc.contains(":难]") {
    "难"
  } else {
    ""
  }
}

///|
/// 优先级/重要度的档位秩（越小越高优）。
fn ranking(x : String) -> Int {
  match x {
    "高" => 0
    "中" => 1
    "低" => 2
    _ => 1
  }
}

///|
/// 截断描述到 max 字符（避免返回里塞一整棵描述）。
fn truncate(s : String, max : Int) -> String {
  if s.length() <= max {
    s
  } else {
    s.substring(start=0, end=max) + "…"
  }
}

///|
/// 下一步排行行（triage 内部行）。
struct TriageRow {
  id : String
  ns : String
  priority : String
  importance : String
  difficulty : String
  depth : Int
  desc : String
}

///|
/// 候选描述/ id 是否命中能力关键词（want 为空视为全命中，即不做能力偏好）。
fn cap_match(r : TriageRow, want : String) -> Bool {
  want == "" || r.desc.contains(want) || r.id.contains(want)
}

///|
/// 下一步推荐（Triage，带能力偏好路由）：返回 { count, ns, agent, want, suggestion?, tasks:[...] }。
/// namespace 为空表示全量；只统计"待领取且依赖已满足"的任务。want 为能力关键词（Marketplookup 雏形）：
/// 非空时，命中该关键词的候选排在头部（按能力匹配路由"这个 agent 擅长啥就先领啥"），不命中者照旧跟进。
pub fn FistEngine::triage(
  self : FistEngine,
  namespace : String,
  agent : String,
  want : String,
) -> Json {
  let rows : Array[TriageRow] = []
  for t in self.list_all() {
    if namespace != "" && t.ns != namespace {
      continue
    }
    if not(t.get_status().is_pending()) {
      continue
    }
    if not(self.deps_satisfied(t.get_id())) {
      continue
    }
    let lab : String = triage_label_of(t.description)
    let difficulty = if lab != "" {
      lab
    } else if t.is_leaf() {
      "叶(可执行)"
    } else {
      "分支"
    }
    rows.push({
      id: t.get_id(),
      ns: t.ns,
      priority: t.priority,
      importance: t.importance,
      difficulty,
      depth: t.get_depth(),
      desc: truncate(t.description, 60),
    })
  }
  rows.sort_by(fn(a, b) {
    // 能力偏好：命中 want 的排在头部（Router 雏形）
    let am = cap_match(a, want)
    let bm = cap_match(b, want)
    if am != bm {
      if am {
        -1
      } else {
        1
      }
    } else {
      let pc = ranking(a.priority) - ranking(b.priority)
      if pc != 0 {
        pc
      } else {
        let ic = ranking(a.importance) - ranking(b.importance)
        if ic != 0 {
          ic
        } else if a.depth != b.depth {
          if a.depth < b.depth {
            -1
          } else {
            1
          }
        } else {
          a.id.compare(b.id)
        }
      }
    }
  })
  let tasks : Array[Json] = []
  for r in rows {
    tasks.push(
      Json::object({
        "id": Json::string(r.id),
        "ns": Json::string(r.ns),
        "priority": Json::string(r.priority),
        "importance": Json::string(r.importance),
        "difficulty": Json::string(r.difficulty),
        "depth": Json::number(r.depth.to_double()),
        "desc": Json::string(r.desc),
      }),
    )
  }
  let m : Map[String, Json] = Map([
    ("count", Json::number(rows.length().to_double())),
    ("ns", Json::string(namespace)),
    ("agent", Json::string(agent)),
    ("want", Json::string(want)),
    ("tasks", Json::array(tasks)),
  ])
  if not(rows.is_empty()) {
    let top = rows[0]
    let cap = if cap_match(top, want) && want != "" {
      "；能力匹配<\{want}>"
    } else {
      ""
    }
    let reason = "依赖已满足；优先级\{top.priority}/重要度\{top.importance}/难度\{top.difficulty}\{cap}，建议优先领取"
    m.set(
      "suggestion",
      Json::object({
        "task_id": Json::string(top.id),
        "ns": Json::string(top.ns),
        "reason": Json::string(reason),
      }),
    )
  }
  Json::object(m)
}

///|
/// 下一步自动取单（自驱推进）：按 triage 的能力推荐取顶部候选并认领给 `agent`（0 状态迁移：待领取→已领取）。
/// 复用 `triage`（排行+suggestion）与 `claim`（认领），只动一条推荐任务，不动看门狗主流程（零回归）。
/// 返回 { picked, remaining, claimed, ns, want, task?, note|error? }。
pub fn FistEngine::pick_next(
  self : FistEngine,
  namespace : String,
  agent : String,
  want : String,
  now : String,
) -> Json {
  let tg = self.triage(namespace, agent, want)
  let m = match tg {
    Object(mm) => mm
    _ => Map([])
  }
  let count = match m.get("count") {
    Some(Number(n, ..)) => n.to_int()
    _ => 0
  }
  let m2 = match m.get("suggestion") {
    Some(Object(s)) => s
    _ => Map([])
  }
  let picked = match m2.get("task_id") {
    Some(String(id)) => Some(id)
    _ => None
  }
  match picked {
    None =>
      Json::object({
        "picked": Json::string(""),
        "remaining": Json::number(count.to_double()),
        "claimed": Json::boolean(false),
        "ns": Json::string(namespace),
        "want": Json::string(want),
        "note": Json::string(
          "无可领取的推荐任务（待领取且依赖已满足集合为空）",
        ),
      })
    Some(pid) =>
      match self.claim(task_id=pid, assignee=agent, now~) {
        Ok(t) =>
          Json::object({
            "picked": Json::string(pid),
            "remaining": Json::number(
              (if count > 0 { count - 1 } else { 0 }).to_double(),
            ),
            "claimed": Json::boolean(true),
            "ns": Json::string(namespace),
            "want": Json::string(want),
            "task": t.to_json(),
            "note": Json::string("已按能力推荐认领该条"),
          })
        Err(e) =>
          Json::object({
            "picked": Json::string(""),
            "remaining": Json::number(count.to_double()),
            "claimed": Json::boolean(false),
            "ns": Json::string(namespace),
            "want": Json::string(want),
            "error": Json::string(e),
            "note": Json::string("认领失败，未改动任何状态"),
          })
      }
  }
}
