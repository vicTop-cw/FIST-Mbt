/// evolve_lesson.mbt —— 失败回流学习（learn-from-reject）最小闭环（独立工具路径）
///
/// 把一次「被打回/失败」的原因（reason）结构化归档成一条 [lesson]<类目> 资产，
/// 复用 evolve 档案库的查重/谱系/注入通路，让建档库能「学教训」。
/// 类目前缀 `[lesson]`、时间戳 id、分数归一与最终落库语义已收拢到
/// `@evolve` 包（lesson.mbt），本文件只负责「内存档案库 + 落库」的完整路径；
/// Omega 打回的自动回流见 engine/omega_strong.mbt（经 evolve_auto_wire.mbt）。

///|
/// 失败回流记录执行：归档成 [lesson] 资产（进程内 Archive + SQLite）。
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
  let goal_l = @evolve.lesson_goal(cat)
  let id = "lesson-" + @evolve.lesson_ts_part(now)
  // 复用与 evolve_submit 相同的查重语义（同类目+相似原因视为重复教训）
  let dup_key = goal_l + " " + reason
  let duplicate = @evolve.Archive::is_duplicate(arc, dup_key, threshold=0.88)
  let note = reason
  let code = if fix == "" { reason } else { fix }
  let sc = @evolve.score_of_lesson(score)
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
  // 统一落库语义（复用 evolve 包的单一真源，与 Omega 打回自动回流一致）
  let stored = @evolve.evolve_lesson_persist(store, id~, cat, reason, fix, now, score=sc)
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
/// 把 SQLite 中已沉淀的 [lesson] 教训回灌进内存 Archive（幂等，按 id 去重）。
/// 目的：Omega 打回自动回流（engine 侧仅落库）写入的教训，经此同步后在同一进程内
/// 对立于 `evolve_snapshot`/`dead_ends`/plan·claim 的 `inject` 可见。
/// 返回本次新同步条数。
fn sync_db_lessons(
  arc : @evolve.Archive,
  store : @store.SqliteStore?,
) -> Int {
  let mut n = 0
  match store {
    None => ()
    Some(s) =>
      for j in s.evolve_list() {
        let a = @evolve.Artifact::from_json(j)
        if a.goal.has_prefix("[lesson]") {
          if arc.get(a.id) is None {
            @evolve.Archive::add(arc, a)
            n = n + 1
          }
        }
      }
  }
  n
}
