/// evolve/lesson.mbt —— 失败回流学习（learn-from-reject）的统一持久化层
///
/// 将「把一次被打回/失败的原因归档成一条 [lesson]<类目> 资产」这一语义收拢到此包，
/// 供以下两处共用（避免重复造轮子、避免跨包循环依赖）：
///   - server/evolve_lesson.mbt：独立 `evolve_lesson` 工具的完整路径（内存 Archive + 落库）
///   - engine/omega_strong.mbt：Omega 打回时自动回流（仅落库，不经内存 Archive）
///
/// 落库都走 `store.evolve_upsert` 写 evolve_artifacts 表，goal 带 `[lesson]` 前缀，
/// 使 plan/claim 的 inject 与 dead_ends 可直接检索到「踩过的坑」。

///|
/// 构造 lesson 类目目标串：goal 前加 `[lesson]` 前缀（幂等，已有前缀则原样返回）。
pub fn lesson_goal(cat : String) -> String {
  let c = cat.trim().to_owned()
  if c.has_prefix("[lesson]") {
    c
  } else {
    "[lesson] " + c
  }
}

///|
/// 从时间戳提取 id 片段（去分隔符后**保留到「秒」**），用于生成可读且趋唯一的 lesson id。
///
/// **R148 一次修掉两个缺陷**（都在下面这条链式 `replace` 上）：
///
/// ① **`replace` 只替换第一次出现** ⇒ 分隔符去不干净。实测 `"2026-10-28"` 走完三个 `replace`
///    后是 `"202610-28"`（第二个 `-` 还在）、ISO 全串的 `:` 也只去掉第一个 ⇒ 生成的 id 里
///    **残留 `-` / `:`**，与函数名与文档承诺（"去分隔符"）不符。改用 **`replace_all`**。
/// ② **上限 16 切掉秒的个位**：修①后 `"2026-10-28T12:34:56Z"` ⇒ `20261028.12.34.56Z`（18 字符），
///    截 16 ⇒ `20261028.12.34.5` ⇒ 同一 **10 秒窗口**内两条教训拿到**同一个 id**；而该 id 是
///    `lesson-<part>` 的唯一来源、落库口径是 **upsert（重复 id 覆盖）** ⇒ 后一条**静默覆盖**前一条。
///    改 **17**（= `YYYYMMDD.HH.MM.SS` 的长度，正好停在字段边界）。
pub fn lesson_ts_part(now : String) -> String {
  let compact = now
    .replace_all(old="-", new="")
    .replace_all(old=":", new=".")
    .replace_all(old="T", new=".")
  if compact.length() > 17 {
    compact[0:17].to_owned()
  } else {
    compact
  }
}

///|
/// lesson 分数默认 0.5（教训典型中性样本，不参与 best，但参与死路地图权重）。
pub fn score_of_lesson(score : Double) -> Double {
  if score == 0.0 {
    0.5
  } else {
    score
  }
}

///|
/// 把一条教训持久化为 [lesson] 资产（域无关，仅落库 evolve_artifacts）。
///   - store 为数据库句柄（None = 内存态，返回 false）
///   - id 由调用方生成并保证趋唯一（重复 id 走 upsert 覆盖，避免多轮打回互相覆盖）
///   - note 存失败原因、code 存纠偏提示（为空则取 reason）
/// 返回是否成功落库。
pub fn evolve_lesson_persist(
  store : @store.SqliteStore?,
  id~ : String,
  cat : String,
  reason : String,
  fix : String,
  now : String,
  score~ : Double = 0.5,
) -> Bool {
  let goal = lesson_goal(cat)
  let code = if fix == "" { reason } else { fix }
  let sc = score_of_lesson(score)
  match store {
    None => false
    Some(s) =>
      match
        s.evolve_upsert(
          id~,
          parent_id="",
          goal~,
          note=reason.to_string(),
          code~,
          score=sc,
          parts_json="{}",
          created_at=now,
        ) {
        Ok(_) => true
        Err(_) => false
      }
  }
}
