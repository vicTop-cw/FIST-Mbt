/// engine_triage.mbt —— 下一步该做啥（Task Triage）：给"更好的 AI 项目管理工具"补推荐式挑选原语
///
/// dag_ready/board 只"列出"可领取任务；本原语进一步"推荐排序"——对指定命名空间（缺省全量）
/// 把"待领取且依赖已满足"的任务按下述序排出优先级，并给出一条"建议下一步"，供 agent
/// 无需全量扫描就能知道此刻该领哪条：
///   排序键：能力匹配(want) → **skill 命中度(skill 非空时)** → priority(高>中>低) →
///           importance(高>中>低) → depth(叶=可执行单元优先，越小越前) → id(稳定)。
/// 难度标签直接复用 plan_deep gradient 嵌入子任务描述的 `难度梯度 i/n:易/中/难` 标记（未命中按深度粗判）。
/// skill 可选（逗号分隔 skill 关键词）：非空时把任务描述与关键词做大小写不敏感的子串匹配，把"skill 库"
/// 变成路由信号，并在 suggestion 里按 SKILL→MODE 建议表给出建议的开发模式；空串 = 不做 skill 路由（零回归）。
/// 复用现有 store.list_all / deps_satisfied / get_status，无新表/依赖。

///|
/// 从任务描述提取 gradient 难度档（易/中/难），复用 R40 的 extract_difficulty 单一抽取来源：
/// 相比旧 `:易]` 后缀粗匹配，能正确识别 calibrate 的真实难度（如 `易 d=1.0` → 易）。
/// 未命中返回空串（由调用方按叶/分支兜底）。
fn triage_label_of(desc : String) -> String {
  let d = extract_difficulty(desc)
  if d.contains("难") {
    "难"
  } else if d.contains("中") {
    "中"
  } else if d.contains("易") {
    "易"
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
  depends_on : Array[String]
  // skill 路由：命中的 skill 关键词（原样大小写）；skill 为空时恒为空数组（零回归）。
  skill_hits : Array[String]
}

///|
/// 候选描述/ id 是否命中能力关键词（want 为空视为全命中，即不做能力偏好）。
fn cap_match(r : TriageRow, want : String) -> Bool {
  want == "" || r.desc.contains(want) || r.id.contains(want)
}

///|
/// 把逗号分隔的 skill 关键词串切成数组（trim + 去空）。
fn skill_keys(skill : String) -> Array[String] {
  if skill == "" {
    []
  } else {
    skill.split(",").map(fn(s) { s.trim().to_string() }).filter(
      fn(s) { s != "" },
    ).collect()
  }
}

///|
/// 纯计算 skill 命中打分：对每个 key 做大小写不敏感的子串匹配（key 与 desc 都 lowercase 后 contains）。
/// 返回 (命中条数, 命中的原样关键词列表)。关键词可能含 `-`，只 lowercase 不做分词。
fn skill_hit(desc : String, keys : Array[String]) -> (Int, Array[String]) {
  let d = desc.to_lower()
  let hits : Array[String] = []
  for k in keys {
    if d.contains(k.to_lower()) {
      hits.push(k)
    }
  }
  (hits.length(), hits)
}

///|
/// SKILL→MODE 建议表（R§5.2-4）：只匹配关键词前缀，未命中返回空串。
/// 把 skill 库变成"建议开发模式"的路由信号——命中哪个 skill，就建议按哪种模式去跑。
fn skill_mode(key : String) -> String {
  let k = key.to_lower()
  let table : Array[(String, String)] = [
    ("tdd", "fix_and_merge"),
    ("test-driven-development", "fix_and_merge"),
    ("systematic-debugging", "bugfind"),
    ("debugging", "bugfind"),
    ("requesting-code-review", "verify"),
    ("code-review", "verify"),
    ("subagent-driven-development", "advance"),
    ("spike", "explore"),
    ("explore", "explore"),
    ("plan", "advance"),
    ("research-paper-writing", "polish"),
    ("ideation", "explore"),
    ("grill-me", "verify"),
    ("superpowers", "advance"),
  ]
  for (prefix, mode) in table {
    if k.starts_with(prefix) {
      return mode
    }
  }
  ""
}

///|
/// 排行主键之后的后继键：priority(高>中>低) → importance(高>中>低) → depth(小者前) → id(稳定)。
/// 在能力匹配与 skill 命中度都打平时复用（同一排序语义的单一真源）。
fn triage_rest(a : TriageRow, b : TriageRow) -> Int {
  let pc = ranking(a.priority) - ranking(b.priority)
  if pc != 0 {
    return pc
  }
  let ic = ranking(a.importance) - ranking(b.importance)
  if ic != 0 {
    return ic
  }
  if a.depth != b.depth {
    if a.depth < b.depth {
      return -1
    } else {
      return 1
    }
  }
  a.id.compare(b.id)
}

///|
/// 下一步推荐（Triage，带能力偏好路由 + skill 命中度路由）：返回 { count, ns, agent, want, skill?, suggestion?, tasks:[...] }。
/// namespace 为空表示全量；只统计"待领取且依赖已满足"的任务。want 为能力关键词（Marketplookup 雏形）：
/// 非空时，命中该关键词的候选排在头部（按能力匹配路由"这个 agent 擅长啥就先领啥"），不命中者照旧跟进。
/// skill 可选（逗号分隔 skill 关键词）：非空时按 skill 命中度排在能力匹配之后、优先级之前，并在 suggestion
/// 里给出建议的开发模式（SKILL→MODE 建议表）；空串 = 不做 skill 路由，排序与输出与旧版完全一致（零回归）。
pub fn FistEngine::triage(
  self : FistEngine,
  namespace : String,
  agent : String,
  want : String,
  skill? : String = "",
) -> Json {
  let keys = skill_keys(skill)
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
    let desc = truncate(t.description, 60)
    let (_, hits) = skill_hit(desc, keys)
    rows.push({
      id: t.get_id(),
      ns: t.ns,
      priority: t.priority,
      importance: t.importance,
      difficulty,
      depth: t.get_depth(),
      desc,
      depends_on: t.depends_on,
      skill_hits: hits,
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
    } else if skill != "" {
      // skill 命中度：命中多的排前（只在 skill 非空时生效，零回归）
      let ah = a.skill_hits.length()
      let bh = b.skill_hits.length()
      if ah != bh {
        bh - ah
      } else if ah > 0 {
        // 相等再按命中的第一个关键词字典序（越小越前，稳定可复现）
        let ka = a.skill_hits[0].to_lower()
        let kb = b.skill_hits[0].to_lower()
        if ka != kb {
          ka.compare(kb)
        } else {
          triage_rest(a, b)
        }
      } else {
        triage_rest(a, b)
      }
    } else {
      triage_rest(a, b)
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
        // 真实 DAG 前驱（复用 R39 gradient_dag 建边）——"就绪原因"看得见
        "depends_on": Json::array(r.depends_on.map(fn(s) { Json::string(s) })),
        // skill 命中（skill 为空时为空数组，零回归）
        "skill_hits": Json::array(
          r.skill_hits.map(fn(s) { Json::string(s) }),
        ),
      }),
    )
  }
  let m : Map[String, Json] = Map([
    ("count", Json::number(rows.length().to_double())),
    ("ns", Json::string(namespace)),
    ("agent", Json::string(agent)),
    ("want", Json::string(want)),
    ("skill", Json::string(skill)),
    ("tasks", Json::array(tasks)),
  ])
  if not(rows.is_empty()) {
    let top = rows[0]
    let cap = if cap_match(top, want) && want != "" {
      "；能力匹配<\{want}>"
    } else {
      ""
    }
    let sk = if top.skill_hits.length() > 0 { top.skill_hits[0] } else { "" }
    let mode = skill_mode(sk)
    let skSuffix = if sk != "" {
      "；skill=<\{sk}>，建议走 <\{mode}> 模式"
    } else {
      ""
    }
    let reason = "依赖已满足；优先级\{top.priority}/重要度\{top.importance}/难度\{top.difficulty}\{cap}\{skSuffix}，建议优先领取"
    m.set(
      "suggestion",
      Json::object({
        "task_id": Json::string(top.id),
        "ns": Json::string(top.ns),
        "reason": Json::string(reason),
        "skill": Json::string(sk),
        "mode": Json::string(mode),
      }),
    )
  }
  Json::object(m)
}

///|
/// 下一步自动取单（自驱推进）：按 triage 的能力/skill 推荐取顶部候选并认领给 `agent`（0 状态迁移：待领取→已领取）。
/// 复用 `triage`（排行+suggestion）与 `claim`（认领），只动一条推荐任务，不动看门狗主流程（零回归）。
/// skill 可选（逗号分隔 skill 关键词）：非空时按 skill 命中度路由取单；空串 = 不做 skill 路由（零回归）。
/// 返回 { picked, remaining, claimed, ns, want, skill, task?, note|error? }。
pub fn FistEngine::pick_next(
  self : FistEngine,
  namespace : String,
  agent : String,
  want : String,
  now : String,
  skill? : String = "",
) -> Json {
  let tg = self.triage(namespace, agent, want, skill~)
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
        "skill": Json::string(skill),
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
            "skill": Json::string(skill),
            "task": t.to_json(),
            "note": Json::string("已按推荐认领该条"),
          })
        Err(e) =>
          Json::object({
            "picked": Json::string(""),
            "remaining": Json::number(count.to_double()),
            "claimed": Json::boolean(false),
            "ns": Json::string(namespace),
            "want": Json::string(want),
            "skill": Json::string(skill),
            "error": Json::string(e),
            "note": Json::string("认领失败，未改动任何状态"),
          })
      }
  }
}
