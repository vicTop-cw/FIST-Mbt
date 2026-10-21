// engine_rank_test.mbt —— 军衔等级（level）接线锁（Phase 2）。
// 覆盖：publish 根任务默认连长级 / 显式声明 / 越界钳制；plan / plan_deep 子任务降一级继承；
// publish_parallel / publish_with_deps 根任务 level 透传。

///|
fn rank_engine() -> FistEngine {
  FistEngine::new()
}

///|
fn rank_publish(
  e : FistEngine,
  desc~ : String = "军衔根任务",
  level~ : Int32 = 6,
) -> String {
  match
    e.publish(
      project_dir="/proj/rank",
      description=desc,
      created_by="human_steward",
      now="2026-10-18T10:00:00Z",
      level~,
    ) {
    Ok(id) => id
    Err(m) => abort("publish failed: \{m}")
  }
}

///|
/// 读任务 level，取不到即 abort。
fn rank_level_of(e : FistEngine, id : String) -> Int32 {
  match e.get_task(id) {
    Some(t) => t.get_level()
    None => abort("task missing: \{id}")
  }
}

///|
test "publish 不传 level → 根任务连长级（6）" {
  let e = rank_engine()
  let id = rank_publish(e)
  assert_eq(rank_level_of(e, id), 6)
}

///|
test "publish 显式 level=2 → 根任务师长级（2）" {
  let e = rank_engine()
  let id = rank_publish(e, desc="显式师长级", level=2)
  assert_eq(rank_level_of(e, id), 2)
}

///|
test "publish 越界钳制：level=9 → 7（排长封顶）" {
  let e = rank_engine()
  let id = rank_publish(e, desc="越界 9", level=9)
  assert_eq(rank_level_of(e, id), 7)
}

///|
test "publish 越界钳制：level=-1 → 0（司令下限）" {
  let e = rank_engine()
  let id = rank_publish(e, desc="越界 -1", level=-1)
  assert_eq(rank_level_of(e, id), 0)
}

///|
test "plan 子任务降一级：父连长(6) → 子排长(7)" {
  let e = rank_engine()
  let id = rank_publish(e)
  ignore(e.claim(task_id=id, assignee="leader_a", now="2026-10-18T10:01:00Z"))
  match
    e.plan(task_id=id, split_n=2, by="leader_a", now="2026-10-18T10:02:00Z") {
    Ok(children) => {
      assert_eq(children.length(), 2)
      // 子任务 depth = 父 depth(3) - 1 = 2，非叶子（depth>1）→ 按 rank_of
      for c in children {
        assert_eq(rank_level_of(e, c), 7)
      }
    }
    Err(m) => abort("plan failed: \{m}")
  }
}

///|
test "plan 子任务封顶：父排长(7) → 子仍排长(7)" {
  let e = rank_engine()
  let id = rank_publish(e, desc="父排长", level=7)
  ignore(e.claim(task_id=id, assignee="leader_a", now="2026-10-18T10:01:00Z"))
  match
    e.plan(task_id=id, split_n=2, by="leader_a", now="2026-10-18T10:02:00Z") {
    Ok(children) => {
      assert_eq(children.length(), 2)
      for c in children {
        assert_eq(rank_level_of(e, c), 7)
      }
    }
    Err(m) => abort("plan failed: \{m}")
  }
}

///|
test "plan_deep 递归拆解：孙任务封顶 7，且军衔与 depth 分离" {
  let e = rank_engine()
  let id = rank_publish(e)
  ignore(e.claim(task_id=id, assignee="leader_a", now="2026-10-18T10:01:00Z"))
  match
    e.plan_deep(
      task_id=id,
      split_n=2,
      by="leader_a",
      now="2026-10-18T10:02:00Z",
    ) {
    Ok(_) => ()
    Err(m) => abort("plan_deep failed: \{m}")
  }
  // 根 6 → 一层子 7 → 二层孙仍 7（封顶）
  assert_eq(rank_level_of(e, id), 6)
  let children = e.children_of(id)
  assert_eq(children.length(), 2)
  for c in children {
    assert_eq(rank_level_of(e, c.get_id()), 7)
    let grand = e.children_of(c.get_id())
    for g in grand {
      assert_eq(rank_level_of(e, g.get_id()), 7)
    }
  }
}

///|
test "publish_parallel 根任务透传 level" {
  let e = rank_engine()
  match
    e.publish_parallel(
      ns="rank-ns",
      description="并行根 师长",
      created_by="human_steward",
      project_dir="/proj/rank",
      now="2026-10-18T10:00:00Z",
      level=2,
    ) {
    Ok(id) => assert_eq(rank_level_of(e, id), 2)
    Err(m) => abort("publish_parallel failed: \{m}")
  }
}

///|
test "publish_with_deps 根任务透传 level" {
  let e = rank_engine()
  let dep = rank_publish(e, desc="前置依赖")
  match
    e.publish_with_deps(
      project_dir="/proj/rank",
      description="带依赖的师长根",
      depends_on=[dep],
      created_by="human_steward",
      now="2026-10-18T10:00:00Z",
      level=3,
    ) {
    Ok(id) => assert_eq(rank_level_of(e, id), 3)
    Err(m) => abort("publish_with_deps failed: \{m}")
  }
}
