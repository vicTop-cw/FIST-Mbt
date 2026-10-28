/// critic_test.mbt —— SAGE Critic 防漂移门禁测试
/// 覆盖：空库放行、与档案库重复→判漂移拒收、全新→放行、默认零副作用（只评审不写库）。

///|
fn cr_engine() -> @evolve.Archive {
  @evolve.Archive::new("mem-critic-test")
}

///|
fn cr_add(arc : @evolve.Archive, note : String) -> Unit {
  let art = @evolve.Artifact::create(
    id="cr-" + note.hash().to_string(),
    parent_id=None,
    goal="[principle] 测试",
    note~,
    code="",
    score=0.9,
    parts=Map([]),
    created_at="2026-09-05T10:00:00Z",
  )
  @evolve.Archive::add(arc, art)
}

///|
test "evolve_critic 空库：放行且 sim=0" {
  let arc = cr_engine()
  let j = @evolve.critic_review(arc, "全新的独立目标设计", 0.9)
  match jget(j, "admit") {
    Some(True) => ()
    _ => abort("空库应直接放行: " + j.stringify())
  }
  match jget(j, "sim") {
    Some(Number(n, ..)) => assert_eq(n, 0.0)
    _ => abort("空库 sim 应为 0: " + j.stringify())
  }
}

///|
test "evolve_critic 重复漂移：与档案库高重合 → 建议拒绝" {
  let arc = cr_engine()
  let note = "专注解析器前端词法分析的实现"
  cr_add(arc, note)
  // 评审同一条 note（高重合 = 疑似课程漂移/重复）
  let j = @evolve.critic_review(
    arc, "专注解析器前端词法分析的实现", 0.9,
  )
  match jget(j, "admit") {
    Some(False) => ()
    _ => abort("高重合应判漂移拒收: " + j.stringify())
  }
  match jget(j, "reason") {
    Some(String(r)) => assert_eq(r.contains("课程漂移"), true)
    _ => abort("reason 应提及课程漂移: " + j.stringify())
  }
}

///|
test "evolve_critic 全新目标：放行且理由含放行" {
  let arc = cr_engine()
  cr_add(arc, "专注解析器前端词法分析的实现")
  let j = @evolve.critic_review(
    arc, "抽象语法树到四进制字节码的转译器设计", 0.9,
  )
  match jget(j, "admit") {
    Some(True) => ()
    _ => abort("低重合应放行: " + j.stringify())
  }
  match jget(j, "reason") {
    Some(String(r)) => assert_eq(r.contains("放行"), true)
    _ => abort("reason 应含放行: " + j.stringify())
  }
}

///|
test "evolve_critic 低稳健性：平均分低于阈值 → 拒收" {
  let arc = cr_engine()
  // 空库（high novelty 也救不回来），score 极低 → combined 低 → 拒收
  let j = @evolve.critic_review(
    arc, "某些支离破碎的半成品思路", 0.1,
  )
  match jget(j, "admit") {
    Some(False) => ()
    _ => abort("低分应拒收: " + j.stringify())
  }
}

///|
test "evolve_critic 中性 score=0.5：不得被一个没算过的分数一票否决（BUG-60）" {
  let arc = cr_engine()
  // 空库 ⇒ 新颖度 1.0。修复前：combined=(0.5+1.0)/2=0.75 < 0.85 ⇒ 永远拒收，
  // 于是 evolve_critic（不传 score）与 task_challenge（硬传 0.5）的门禁全部形同虚设。
  let j = @evolve.critic_review(
    arc, "把模型路由的决策与 IO 分包的可检锚点", 0.5,
  )
  match jget(j, "admit") {
    Some(True) => ()
    _ => abort("未计分应按新颖度放行: " + j.stringify())
  }
  // 成对：漂移防护仍然生效——重复条目即使中性分也必须拒收（不是"放宽门禁"）
  let arc2 = cr_engine()
  cr_add(arc2, "专注解析器前端词法分析的实现")
  let dup = @evolve.critic_review(
    arc2, "专注解析器前端词法分析的实现", 0.5,
  )
  match jget(dup, "admit") {
    Some(False) => ()
    _ => abort("高重合仍须拒收: " + dup.stringify())
  }
  // 成对：真给了低分照旧拒收（显式 score 的加权语义不变）
  let low = @evolve.critic_review(arc, "又一个全新的独立目标", 0.1)
  match jget(low, "admit") {
    Some(False) => ()
    _ => abort("显式低分应拒收: " + low.stringify())
  }
}

///|
/// R140：`critic_most_similar` 的**边界语义**（此前零直接引用，只被 `critic_review` 间接用）。
///
/// 关键一条：**零重合必须返回 None**，不能返回 `("", "", 0.0)` 这种"空 id 的假最相似"——
/// 那会让回执渲染出「最相似：（空）」并把 `sim` 假成 0 却带一个 id，读者无法区分
/// 「最相似的是空」与「根本没有相似项」。
test "critic_most_similar_boundaries" {
  let arc = cr_engine()
  // ① 空库 ⇒ None
  assert_true(@evolve.critic_most_similar(arc, "任意目标") == None)
  cr_add(arc, "熔断器三态状态机与半开探测")
  // ② 候选 tokenize 后为空（纯空白）⇒ None
  assert_true(@evolve.critic_most_similar(arc, "   ") == None)
  // ③ 零重合 ⇒ None（不是空 id 假结果）
  assert_true(@evolve.critic_most_similar(arc, "qqq zzz") == None)
  // ④ 有重合 ⇒ Some，且 id/note 非空、相似度落在 (0,1]
  match @evolve.critic_most_similar(arc, "熔断器半开探测") {
    None => abort("有重合却返回 None")
    Some((id, note, sim)) => {
      assert_true(!id.is_empty())
      assert_true(!note.is_empty())
      assert_true(sim > 0.0 && sim <= 1.0)
    }
  }
}

///|
/// R140：`critic_dup_sim()` 是**判重阈值的单真源**（0.70），被 `critic_review` 的
/// `sim < dup_sim` 当作拒收边界。值被改动会**静默**改变"多像才算重复"。
/// 变异对照：改成 0.10 ⇒ 本格红，且大量全新目标会被判成重复。
test "critic_dup_sim_is_documented_threshold" {
  assert_eq(@evolve.critic_dup_sim(), 0.70)
}

///|
/// R140：`score_of_lesson` 的归一语义 —— **0.0 视为"没算过"⇒ 0.5 中性**，其余原样。
///
/// 为什么钉它：`critic_review` 里「score==0.5（未计分）⇒ combined = novelty」那条分支
/// 依赖的正是这个归一；若 0.0 原样传下去，**未计分条目会被当成"极差"而遭拒收**
/// （静默误拒，比崩溃难查）。
test "score_of_lesson_neutralizes_zero" {
  assert_eq(@evolve.score_of_lesson(0.0), 0.5)
  assert_eq(@evolve.score_of_lesson(0.9), 0.9)
  assert_eq(@evolve.score_of_lesson(0.5), 0.5)
}
