/// claim_rank_wbtest.mbt —— P0-2 Claim 军衔硬门（rank gate）白盒锁。
///
/// 背景（2026-10-22 实测）：master `c03d78ce` 给 `FistEngine::claim` 加了军衔门
/// （`estimate_rank` / `rank_can_claim` / `level_to_rank` + claim 接线），但**全仓零测试覆盖**——
/// 新门无锁 = 无门（本仓既往教训：红着没人读、没锁的判据等于没有）。
///
/// 本文件锁四件事：
///   G1 纯函数语义：`estimate_rank` 五档（司令/连长/团长/营长/其它）+ 前缀匹配；
///   G2 边界：`rank_can_claim` 的 `==` 等号两侧、司令例外、以及**恰好越级**必须拒；
///   G3 映射：`level_to_rank` 0..7 + 越界回落"士兵"；
///   G4 接线：真实 `claim` 路径——低军衔认领高级任务必须 `Err` 且文案含 `RANK_GATE`，
///      高军衔(司令)放行，同级与下级放行（防"门装反了"）。

///|
/// 取 Result 错误文案（Ok 侧哨兵；同 frozen 测试模式）。
fn cr_err_of(r : Result[@core.Task, String]) -> String {
  match r {
    Err(e) => e
    Ok(_) => "<ok>"
  }
}

///|
/// 发布一个指定 level 的根任务，返回 task_id。
fn cr_publish(e : FistEngine, desc : String, level : Int32) -> String {
  match
    e.publish(
      project_dir="/proj/rank",
      description=desc,
      created_by="human_steward",
      now="2026-10-22T00:00:00Z",
      level~,
    ) {
    Ok(id) => id
    Err(m) => abort("publish failed: \{m}")
  }
}

///|
/// G1：`estimate_rank` 五档 + 前缀匹配。
test "rank_gate G1: estimate_rank 五档映射" {
  assert_eq(estimate_rank("human_steward"), 0) // 司令（例外通吃）
  assert_eq(estimate_rank("human"), 0)
  assert_eq(estimate_rank("leader_x"), 6) // 连长
  assert_eq(estimate_rank("polish-lead-1"), 6)
  assert_eq(estimate_rank("atomcode-r90"), 4) // 团长
  assert_eq(estimate_rank("aider-m1"), 4)
  assert_eq(estimate_rank("slave01"), 5) // 其它 → 营长
  assert_eq(estimate_rank(""), 5)
}

///|
/// G2：`rank_can_claim` 边界（等号两侧 + 司令例外 + 恰好越级）。
test "rank_gate G2: rank_can_claim 边界" {
  // 司令例外：任何 level 都能领
  assert_true(rank_can_claim(0, 0))
  assert_true(rank_can_claim(0, 7))
  // 同级放行（连长 6 领 level 6）
  assert_true(rank_can_claim(6, 6))
  // 领更低级的任务放行（连长领 level 7 排长）
  assert_true(rank_can_claim(6, 7))
  // 恰好越一级必须拒（连长领 level 5 营长）
  assert_false(rank_can_claim(6, 5))
  // 团长 4：领 4 放行、领 3 拒
  assert_true(rank_can_claim(4, 4))
  assert_false(rank_can_claim(4, 3))
  // 营长 5 边界
  assert_true(rank_can_claim(5, 5))
  assert_false(rank_can_claim(5, 4))
}

///|
/// G3：`level_to_rank` 0..7 映射 + 越界回落。
test "rank_gate G3: level_to_rank 映射与越界" {
  // 显式字面量：本版 MoonBit 的 Int/Int32 无 to_int32 转换，字面量直接按 Int32 推断
  assert_eq(level_to_rank(0), "司令")
  assert_eq(level_to_rank(1), "军长")
  assert_eq(level_to_rank(2), "师长")
  assert_eq(level_to_rank(3), "旅长")
  assert_eq(level_to_rank(4), "团长")
  assert_eq(level_to_rank(5), "营长")
  assert_eq(level_to_rank(6), "连长")
  assert_eq(level_to_rank(7), "排长")
  assert_eq(level_to_rank(-1), "士兵")
  assert_eq(level_to_rank(8), "士兵")
}

///|
/// G4-a：低军衔认领高级任务 ⇒ Err 且文案含 RANK_GATE（门装了且身份可读）。
test "rank_gate G4: 连长认领团长级任务被拒且文案含 RANK_GATE" {
  let e = FistEngine::new()
  let tid = cr_publish(e, "团长级任务（level=4）", 4)
  let msg = cr_err_of(e.claim(task_id=tid, assignee="leader_a", now="2026-10-22T01:00:00Z"))
  assert_true(msg.contains("RANK_GATE"))
  // 文案要能读出双方军衔，否则运维无法判断是"没权限"还是"任务建错了"
  assert_true(msg.contains("rank=6"))
  assert_true(msg.contains("level=4"))
}

///|
/// G4-b：司令例外通吃——同一任务换人类指挥官必须放行（防"门装反成一刀切"）。
test "rank_gate G4: 人类指挥官放行（司令例外）" {
  let e = FistEngine::new()
  let tid = cr_publish(e, "团长级任务（level=4）", 4)
  match e.claim(task_id=tid, assignee="human_steward", now="2026-10-22T01:00:00Z") {
    Ok(t) => assert_eq(t.assignee, Some("human_steward"))
    Err(m) => abort("司令应可认领任意级任务，实际被拒: \{m}")
  }
}

///|
/// G4-c：同级与下级放行（连长领 level=6 连长级、level=7 排长级）。
test "rank_gate G4: 同级/下级任务放行" {
  let e = FistEngine::new()
  let t6 = cr_publish(e, "连长级任务（level=6）", 6)
  match e.claim(task_id=t6, assignee="leader_a", now="2026-10-22T01:00:00Z") {
    Ok(_) => ()
    Err(m) => abort("同级任务应放行，实际被拒: \{m}")
  }
  let t7 = cr_publish(e, "排长级任务（level=7）", 7)
  match e.claim(task_id=t7, assignee="leader_b", now="2026-10-22T01:00:00Z") {
    Ok(_) => ()
    Err(m) => abort("下级任务应放行，实际被拒: \{m}")
  }
}

///|
/// G4-d：atomcode（团长 4）领 level=3（旅长级）被拒 —— 覆盖"另一档军衔"的越级。
test "rank_gate G4: atomcode 团长认领旅长级任务被拒" {
  let e = FistEngine::new()
  let tid = cr_publish(e, "旅长级任务（level=3）", 3)
  let msg = cr_err_of(e.claim(task_id=tid, assignee="atomcode-r91", now="2026-10-22T01:00:00Z"))
  assert_true(msg.contains("RANK_GATE"))
  // 同一任务 atomcode 领 level=4 应放行（另一个用例已覆盖同级，这里确认门不误伤相邻档）
  let t4 = cr_publish(e, "团长级任务（level=4）", 4)
  match e.claim(task_id=t4, assignee="atomcode-r91", now="2026-10-22T01:00:00Z") {
    Ok(_) => ()
    Err(m) => abort("团长级任务应放行，实际被拒: \{m}")
  }
}
