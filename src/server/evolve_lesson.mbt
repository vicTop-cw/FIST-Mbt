/// evolve_lesson.mbt —— 失败回流学习（learn-from-reject）最小闭环
///
/// 把一次「被打回/失败」的原因（reason）结构化归档成一条 [lesson]<类目> 资产，
/// 复用 evolve 档案库的查重/谱系/注入通路，让建档库能「学教训」：
///   - goal 用 `[lesson]<类目>` 前缀标识 tag（与 [principle] 平行）；
///   - note 存失败原因、code 存纠偏提示/来源（含打回 voctorative 上下文）；
///   - plan/claim 的 inject 可按类目命中检索「踩过的坑」，dead_ends 可直接映射。
/// 逻辑参数化（传 Archive + SqliteStore），同时便于 MCP handler 用模块级
/// evolve_arc，也便于单测注入独立实例。不强加新表：复用 evolve_artifacts。

///|
/// 构造 lesson 类目目标串：goal 前加 `[lesson]` 前缀。
pub fn lesson_goal(cat : String) -> String {
  let c = cat.trim().to_string()
  if c.has_prefix("[lesson]") {
    c
  } else {
    "[lesson] " + c
  }
}

///|
/// 失败回流记录执行：归档成 [lesson] 资产（进程内 + SQLite）。
/// cat 类目（可检索 tag）、reason 失败原因、fix 纠偏提示（可选）、score、now。
/// 返回 {learned:true, artifact_id, duplicate, persisted}。
pub fn do_evolve_lesson(
  arc : @evolve.Archive,
  store : @store.SqliteStore?,
  cat : String,
  reason : String,
  fix : String,
  now : String,
  score? : Double = 0.5,
) -> Json {
  let goal_l = lesson_goal(cat)
  let id = "lesson-" + lesson_ts_part(now)
  // 复用与 evolve_submit 相同的查重语义（同类目+相似原因视为重复教训）
  let dup_key = goal_l + " " + reason
  let duplicate = @evolve.Archive::is_duplicate(arc, dup_key, threshold=0.88)
  let note = reason
  let code = if fix == "" { reason } else { fix }
  let sc = score_of_lesson(score)
  let art = @evolve.Artifact::create(
    id~,
    parent_id=None,
    goal=goal_l,
    note~,
    code~,
    score=sc,
    parts=Map([]),
    created_at=now,
  )
  @evolve.Archive::add(arc, art)
  let stored : Bool = match store {
    None => false
    Some(s) =>
      match
        s.evolve_upsert(
          id~,
          parent_id="",
          goal=goal_l,
          note~,
          code~,
          score=sc,
          parts_json="{}",
          created_at=now,
        ) {
        Ok(_) => true
        Err(_) => false
      }
  }
  Json::object({
    "learned": Json::boolean(true),
    "artifact_id": Json::string(id),
    "duplicate": Json::boolean(duplicate),
    "persisted": Json::boolean(stored),
    "category": Json::string(cat),
    "note": Json::string("失败教训已回流为 [lesson] 资产"),
  })
}

///|
/// lesson 分数默认 0.5（教训典型中性样本，不参与 best，但参与死路地图权重）。
fn score_of_lesson(score : Double) -> Double {
  if score == 0.0 {
    0.5
  } else {
    score
  }
}

///|
/// 从时间戳提取 id 片段（对齐 distill_ts_part，去分隔符、取前 16 位）。
fn lesson_ts_part(now : String) -> String {
  let compact = now
    .replace(old="-", new="")
    .replace(old=":", new=".")
    .replace(old="T", new=".")
  if compact.length() > 16 {
    compact.substring(start=0, end=16)
  } else {
    compact
  }
}
