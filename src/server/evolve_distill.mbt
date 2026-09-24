/// evolve_distill.mbt —— 自进化蒸馏（EvolveR 最小级）工具实现
///
/// 把一次 verify 通过的任务交付物蒸馏成一条「原则」写入 DGM：
///   - 复用既有 store 的 evolve 持久化（evolve_upsert）写一条冲突类型 principle
///     的 artifact（code 字段写起蒸馏原文，note 写原则说明）；
///   - tag 概念用 goal 前加 `[principle]` 前缀标识，保持与既有 evolve_submit
///     的查重语义兼容；
///   - 不强求新表：直接写入既有 evolve_artifacts 表。
///
/// 逻辑参数化（传入 Archive 与 SqliteStore），既便于 MCP handler 复用模块级
/// evolve_arc，也便于单测注入独立 Archive / SQLite 实例。

///|
/// 构造 principle 类型产物的目标字符串：goal 前加 `[principle]` 前缀标识 tag。
pub fn distill_principle_goal(goal : String) -> String {
  let g = goal.trim().to_string()
  if g.has_prefix("[principle]") {
    g
  } else {
    "[principle] " + g
  }
}

///|
/// 蒸馏执行：查重（复用与 evolve_submit 相同的 Archive::is_duplicate 语义）
/// → 写进程内 Archive → 持久化到 SQLite evolve_artifacts。
/// 返回 {distilled:true, artifact_id}；查重命中时仍按既有 evolve_submit 语义
/// 入库（同一内容重复蒸馏不会产生新生产线，复用 upsert 幂等覆盖），
/// 并附 rejected/duplicate 标记供上层判断。
pub fn do_evolve_distill(
  arc : @evolve.Archive,
  store : @store.SqliteStore?,
  goal : String,
  note : String,
  score : Double,
  now : String,
) -> Json {
  let goal_p = distill_principle_goal(goal)
  let id = "principle-" + distill_ts_part(now)
  // 复用既有 evolve_submit 的查重语义（同目标高度相似视为重复）。
  // 用带 [principle] 前缀的目标比较，避免前缀稀释 Jaccard 导致漏判。
  let duplicate = @evolve.Archive::is_duplicate(arc, goal_p, threshold=0.88)
  // 进程内 Archive：记录该原则（不进 best/sample，仅作查重记忆与谱系）
  let art = @evolve.Artifact::create(
    id~,
    parent_id=None,
    goal=goal_p,
    note~,
    code=note,
    score~,
    parts=Map([]),
    created_at=now,
  )
  @evolve.Archive::add(arc, art)
  // 持久化到 SQLite（evolve_artifacts 表，upsert 幂等覆盖）
  let stored : Bool = match store {
    None => false
    Some(s) =>
      match
        s.evolve_upsert(
          id~,
          parent_id="",
          goal=goal_p,
          note~,
          code=note,
          score~,
          parts_json="{}",
          created_at=now,
        ) {
        Ok(_) => true
        Err(_) => false
      }
  }
  Json::object({
    "distilled": Json::boolean(true),
    "artifact_id": Json::string(id),
    "duplicate": Json::boolean(duplicate),
    "persisted": Json::boolean(stored),
    "note": Json::string("已蒸馏为 principle 入库 DGM"),
  })
}

///|
/// 从时间戳提取可作 id 的紧凑片段（去掉分隔符，取前 16 位）。
/// 同一 now 蒸馏同一目标会得到同一 id → upsert 幂等覆盖（符合既有语义）。
fn distill_ts_part(now : String) -> String {
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
