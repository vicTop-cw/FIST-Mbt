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
  match j.value("admit") {
    Some(True) => ()
    _ => abort("空库应直接放行: " + j.stringify())
  }
  match j.value("sim") {
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
  match j.value("admit") {
    Some(False) => ()
    _ => abort("高重合应判漂移拒收: " + j.stringify())
  }
  match j.value("reason") {
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
  match j.value("admit") {
    Some(True) => ()
    _ => abort("低重合应放行: " + j.stringify())
  }
  match j.value("reason") {
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
  match j.value("admit") {
    Some(False) => ()
    _ => abort("低分应拒收: " + j.stringify())
  }
}
