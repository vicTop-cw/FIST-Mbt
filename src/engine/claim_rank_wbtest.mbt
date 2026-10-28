/// claim_rank_wbtest.mbt —— P0-2 Claim 军衔硬门（rank gate）白盒锁。
///
/// 背景（2026-10-22 实测）：master `c03d78ce` 给 `FistEngine::claim` 加了军衔门
/// （`estimate_rank` / `rank_can_claim` / `level_to_rank` + claim 接线），但**全仓零测试覆盖**——
/// 新门无锁 = 无门（本仓既往教训：红着没人读、没锁的判据等于没有）。
///
/// **BUG-432（2026-10-27）**：军衔判据原本是 `estimate_rank(name)`（`has_prefix("leader") ⇒ 6`、
/// `has_prefix("atomcode"/"aider") ⇒ 4`）——**名字即身份**，与 BUG-418/421/422 收口的角色门
/// 是两个独立实现。现已改为 `judged_role(eng, assignee)`（登记优先 + 收窄后推断兜底）
/// → `rank_of_role(role)`（政策面，`engine_scope_perm.mbt`）。`estimate_rank` 已删除。
/// 本文件因此锁六件事：
///   G1 纯函数语义：`rank_of_role` 三角色映射 + 未知值 fail-closed（不再有名字前缀档）；
///   G2 边界：`rank_can_claim` 的 `==` 等号两侧、司令例外、以及**恰好越级**必须拒；
///   G3 映射：`level_to_rank` 0..7 + 越界回落"士兵"；
///   G4 接线：真实 `claim` 路径——低军衔认领高级任务必须 `Err` 且文案含 `RANK_GATE`，
///      高军衔(司令)放行，同级与下级放行（防"门装反了"）；
///   **G5（BUG-432 核心）**：名字既**不提权**也不**误伤** —— `leader-*` / `fist-mbt`
///      与普通执行者同档（行为翻转锁 + 已登记 Leader 的正例 + server 自身份的反例）；
///   G6 变异对照（见文件末尾注释与 `reports/` 修复回执的实测读数）。

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
/// Gate2-a：`extract_needs` 解析（需要:/need:/requires:/能力: + 三种分隔符）。
test "Gate2-a: extract_needs 关键词与分隔符" {
  assert_eq(extract_needs("需要: python, json"), ["python", "json"])
  // 顿号与全角逗号：原实现只 split ASCII 逗号 ⇒ 这里曾是"整串当一个标签"的误拒源
  assert_eq(extract_needs("需要: python、json"), ["python", "json"])
  assert_eq(extract_needs("need: a，b"), ["a", "b"])
  assert_eq(extract_needs("requires: rust"), ["rust"])
  assert_eq(extract_needs("能力：gpu"), ["gpu"])
  assert_eq(extract_needs("能力: gpu, cuda"), ["gpu", "cuda"])
  // 没有关键词行 ⇒ 空（不能把普通描述当能力需求）
  assert_eq(extract_needs("普通任务：修个 bug"), [])
  assert_eq(extract_needs(""), [])
}

///|
/// Gate2-b：能力门拒绝——abilities 缺一格必须 Err 且文案含 ABILITY_GATE 与缺失项。
test "Gate2-b: 能力不足被拒且点名缺失项" {
  let reg = @executor.ExecutorRegistry::new().add_ability("worker1", ["python"])
  let e = FistEngine::new(registry=reg)
  let tid = cr_publish(e, "实现接口\n需要: python, json", 6)
  let msg = cr_err_of(
    e.claim(task_id=tid, assignee="worker1", now="2026-10-22T01:00:00Z"),
  )
  assert_true(msg.contains("ABILITY_GATE"))
  assert_true(msg.contains("json"))
}

///|
/// Gate2-c：能力齐备 ⇒ 放行（正例，防"门装成一刀切"）。
test "Gate2-c: 能力齐备放行" {
  let reg = @executor.ExecutorRegistry::new().add_ability("worker1", [
    "python", "json",
  ])
  let e = FistEngine::new(registry=reg)
  let tid = cr_publish(e, "实现接口\n需要: python, json", 6)
  match e.claim(task_id=tid, assignee="worker1", now="2026-10-22T01:00:00Z") {
    Ok(_) => ()
    Err(m) => abort("能力齐备应放行，实际被拒: " + m)
  }
}

///|
/// Gate2-d：**未注册 abilities 的 assignee 跳过能力门**（代码注释明写的"降级零回归"契约）。
test "Gate2-d: 未注册执行者跳过能力门" {
  let e = FistEngine::new()
  let tid = cr_publish(e, "实现接口\n需要: python, json", 6)
  match e.claim(task_id=tid, assignee="leader_a", now="2026-10-22T01:00:00Z") {
    Ok(_) => ()
    Err(m) =>
      abort("未注册 abilities 应跳过能力门，实际被拒: " + m)
  }
}

///|
/// Gate2-e：任务没有"需要:"行 ⇒ 无 needs ⇒ 能力门不触发。
test "Gate2-e: 无 needs 的任务不触发能力门" {
  let reg = @executor.ExecutorRegistry::new().add_ability("worker1", ["python"])
  let e = FistEngine::new(registry=reg)
  let tid = cr_publish(e, "普通任务，无能力需求", 6)
  match e.claim(task_id=tid, assignee="worker1", now="2026-10-22T01:00:00Z") {
    Ok(_) => ()
    Err(m) => abort("无 needs 任务应放行，实际被拒: " + m)
  }
}

///|
/// G1：`rank_of_role` 三角色映射 + 未知值 fail-closed。
///
/// **修前**这里是 `estimate_rank` 五档（含 `leader_x ⇒ 6` / `atomcode ⇒ 4` 的前缀档）——
/// 那两条断言本身就是**把 bug 写成锁**（判例同族：锁固定了错误语义 ⇒ 修 bug 必先改锁）。
test "rank_gate G1: rank_of_role 角色映射（未知值 fail-closed）" {
  assert_eq(rank_of_role("HumanSteward"), 0) // 司令（通吃）
  assert_eq(rank_of_role("Leader"), 4) // 团长（军官线，比默认执行者档更高）
  assert_eq(rank_of_role("Executor"), 5) // 营长（现网默认档，逐字沿用）
  // 未知 / 空串 / 拼错：一律默认档 —— **不因未知值提权**（fail-closed）
  assert_eq(rank_of_role(""), 5)
  assert_eq(rank_of_role("human_steward"), 5) // 小写/自由文本不是角色名，不得提权
  assert_eq(rank_of_role("Commander"), 5)
  // 角色档位（role_rank，数值越大权越大）与本函数（数值越小权越大）方向相反：
  // 钉住这一点，防止下一个人用 role_rank 的直觉改这里
  assert_true(role_rank("Leader") > role_rank("Executor"))
  assert_true(rank_of_role("Leader") < rank_of_role("Executor"))
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
///
/// BUG-432 后：`leader_a` 走推断 ⇒ Executor ⇒ rank 5（修前按名字前缀是 6）。
/// 文案同时点名 `role` / `role_source`，运维才分得清「没权限」与「任务建错了」。
test "rank_gate G4: 执行者认领团长级任务被拒且文案含 RANK_GATE" {
  let e = FistEngine::new()
  let tid = cr_publish(e, "团长级任务（level=4）", 4)
  let msg = cr_err_of(
    e.claim(task_id=tid, assignee="leader_a", now="2026-10-22T01:00:00Z"),
  )
  assert_true(msg.contains("RANK_GATE"))
  // 文案要能读出双方军衔与判据来源，否则运维无法判断是"没权限"还是"任务建错了"
  assert_true(msg.contains("rank=5"))
  assert_true(msg.contains("role=Executor"))
  assert_true(msg.contains("role_source=inferred"))
  assert_true(msg.contains("level=4"))
}

///|
/// G4-b：司令例外通吃——同一任务换人类指挥官必须放行（防"门装反成一刀切"）。
test "rank_gate G4: 人类指挥官放行（司令例外）" {
  let e = FistEngine::new()
  let tid = cr_publish(e, "团长级任务（level=4）", 4)
  match
    e.claim(task_id=tid, assignee="human_steward", now="2026-10-22T01:00:00Z") {
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
/// G4-d：执行器实例名（`atomcode*`）**不再靠前缀拿团长档**（BUG-432 的第二半）。
///
/// 修前：`has_prefix("atomcode") ⇒ 4` ⇒ 能领 level=4（团长级）。**那是名字提权**：
/// 默认档 5 领不了 level=4（`5 <= 4` 假），而自称 `atomcode-xxx` 就能领 ⇒ 名字换权限。
/// 修后：`atomcode*` 与其他执行者同档（5）⇒ level=3 拒、level=4 拒、level=5 放行。
/// ⚠️ 这是本单**有意的行为收窄**（4→5 的档位平移），已在回执「缺口与风险」里点名：
/// 现网 100% 任务 level=6 ⇒ 实际影响为零，但它是「名字不再换权限」的直接代价。
test "rank_gate G4: 执行器实例名不靠前缀拿团长档" {
  let e = FistEngine::new()
  let t3 = cr_publish(e, "旅长级任务（level=3）", 3)
  let msg = cr_err_of(
    e.claim(task_id=t3, assignee="atomcode-r91", now="2026-10-22T01:00:00Z"),
  )
  assert_true(msg.contains("RANK_GATE"))
  assert_true(msg.contains("rank=5"))
  // 修前的 rank=4 档（能手 level=4）已不存在：同一名字领 level=4 现在必须被拒
  let t4b = cr_publish(e, "团长级任务（level=4）", 4)
  let msg4 = cr_err_of(
    e.claim(task_id=t4b, assignee="atomcode-r91", now="2026-10-22T01:00:00Z"),
  )
  assert_true(msg4.contains("RANK_GATE"))
  // 相邻档（level=5 营长级）放行 —— 门没被收成一刀切
  let t5 = cr_publish(e, "营长级任务（level=5）", 5)
  match
    e.claim(task_id=t5, assignee="atomcode-r91", now="2026-10-22T01:00:00Z") {
    Ok(_) => ()
    Err(m) =>
      abort("执行者档（rank=5）应可领 level=5，实际被拒: \{m}")
  }
}

// ===== BUG-432 核心锁（G5）：名字既不提权也不误伤 =====
//
// 修前实测（探针读数，见回执）：
//   estimate_rank: leader=6 · leader-xxx=6 · polish-lead=6 · fist-mbt=5 ·
//                  atomcode-r90=4 · aider-m1=4 · slave01=5 · human_steward=0
//   claim(level=5): leader-xxx ⇒ **DENY**(rank=6) ，slave01 ⇒ **ALLOW**(rank=5)
//   ⇒ 名字造成**误伤**（leader 前缀反而比匿名 agent 更受限）；
//   而 atomcode* ⇒ rank 4 能领 level=4（默认档 5 领不了）⇒ 名字造成**提权**。
// 两个方向都必须消失：军衔只由**角色**决定。

///|
/// G5-a（行为翻转锁）：`leader-*` 不再因名字拿连长档 ⇒ 与普通执行者同档，
/// **能领 level=5 的营长级任务**（修前被 RANK_GATE 拒 —— 这就是误伤本身）。
///
/// ⚠️ 变异对照（判例-29/30）：把 `claim` 里的 `judged_role + rank_of_role` 改回
/// `estimate_rank(assignee)` 后，本格的第二条 `claim` 必红（leader-xxx 又变回 rank 6/拒）。
/// 断言**行为**而不是 grep 源码字符串 —— 后者会命中注释里的 `has_prefix`（自指假绿）。
test "rank_gate G5: leader 前缀不再取得军衔（行为翻转）" {
  // 纯函数面：名字进不去军衔，角色才进得去
  let mem = FistEngine::new()
  for
    n in ["leader-xxx", "leader", "leader-tools-bot", "polish-lead", "fist-mbt"] {
    let (role, src) = judged_role(mem, n)
    assert_eq(role, "Executor")
    assert_eq(src, "inferred")
    assert_eq(rank_of_role(role), 5)
  }
  let (hs, _) = judged_role(mem, "human_steward")
  assert_eq(hs, "HumanSteward")
  assert_eq(rank_of_role(hs), 0)
  // 端到端翻转：level=5（营长级）任务，`leader-xxx` 与匿名执行者现在**同样放行**
  let e = FistEngine::new()
  let t5 = cr_publish(e, "营长级任务（level=5）", 5)
  match e.claim(task_id=t5, assignee="leader-xxx", now="2026-10-27T02:00:00Z") {
    Ok(_) => ()
    Err(m) =>
      abort(
        "leader-xxx 应与普通执行者同档（rank=5）能领 level=5（修前因 rank=6 被拒=误伤），实际: " +
        m,
      )
  }
}

///|
/// G5-b（反例 · 不提权）：`leader` / `leader-xxx` / `fist-mbt` / `atomcode*` 都**拿不到**
/// 更高军衔 —— 领 level=4（团长级）照旧被 RANK_GATE 拒，文案点名 `rank=5`。
test "rank_gate G5: 名字不得提权（含 atomcode 前缀不再拿团长档）" {
  let e = FistEngine::new()
  for
    n in [
      "leader", "leader-xxx", "leader-tools-bot", "polish-lead", "fist-mbt", "atomcode-r90",
      "aider-m1", "commander-fake",
    ] {
    let tid = cr_publish(e, "团长级任务（level=4）", 4)
    let msg = cr_err_of(
      e.claim(task_id=tid, assignee=n, now="2026-10-27T02:00:00Z"),
    )
    assert_true(msg.contains("RANK_GATE"))
    assert_true(msg.contains("rank=5"))
  }
}

///|
/// G5-c（正面 · 登记优先）：**已登记 `role="Leader"` 的 agent 拿到军官军衔**（rank 4）
/// ⇒ 能领 level=4 的团长级任务；而同前缀但**未登记**的名字仍走默认档 5 ⇒ 被拒。
///
/// 这一格同时证明「修的是取数面，不是把门一刀切」：
///   · 登记了 ⇒ Leader 军衔（role_source=declared）
///   · 没登记 ⇒ 前缀再像也只是 Executor（role_source=inferred）
test "rank_gate G5: 已登记 Leader 拿军官军衔，前缀同名未登记仍默认档" {
  let db = "temp/bug432_rank_leader_wb.db"
  let e = match FistEngine::open_sqlite(db) {
    None => abort("open_sqlite 失败：" + db)
    Some(x) => x
  }
  let legit = "bug432-officer-lane"
  match
    e.agents_register(
      agent_id=agent_fp_of(legit),
      agent_type="executor",
      role="Leader",
      soldier="工兵",
      pubkey_fp="",
      pid=7,
      now="2026-10-27T02:00:00Z",
    ) {
    Err(m) => abort("agents_register 失败：" + m)
    Ok(_) => ()
  }
  // 登记面确实生效（否则本格退化成「查不到」= 假绿）
  let (role, src) = judged_role(e, legit)
  assert_eq(role, "Leader")
  assert_eq(src, "declared")
  assert_eq(rank_of_role(role), 4)
  // 正面：军官档能领团长级任务（修前这条名字按前缀要么 5 拒、要么 6 拒 —— 都不对）
  let t4 = cr_publish(e, "团长级任务（level=4）", 4)
  match e.claim(task_id=t4, assignee=legit, now="2026-10-27T02:00:00Z") {
    Ok(_) => ()
    Err(m) =>
      abort(
        "已登记 Leader（rank=4）应可领 level=4，实际被拒: " + m,
      )
  }
  // 反例：同前缀但未登记 ⇒ 默认档 5 ⇒ 同一级别任务被拒（名字不带权限）
  let fake = "bug432-officer-lane-fake"
  let t4b = cr_publish(e, "团长级任务（level=4）", 4)
  let msg = cr_err_of(
    e.claim(task_id=t4b, assignee=fake, now="2026-10-27T02:00:00Z"),
  )
  assert_true(msg.contains("RANK_GATE"))
  assert_true(msg.contains("rank=5"))
  assert_true(msg.contains("role_source=inferred"))
}

///|
/// G5-d（反例 · BUG-422 联动）：`fist-mbt` 即便在 agents 表里有一条
/// `agent_type="server"` + `role="Leader"` 的登记（`server.mbt` 启动写的那条），
/// 也**拿不到军官军衔** —— `claimed` 侧的 RANK_GATE 与 rsv/lock 门共用同一个取数面，
/// 所以 BUG-422 的「server 自身份不提权」在这里同样生效。
test "rank_gate G5: server 自身份不因 Leader 登记拿到军官军衔" {
  let db = "temp/bug432_rank_self_wb.db"
  let e = match FistEngine::open_sqlite(db) {
    None => abort("open_sqlite 失败：" + db)
    Some(x) => x
  }
  match
    e.agents_register(
      agent_id=agent_fp_of("fist-mbt"),
      agent_type="server",
      role="Leader",
      soldier="通信兵",
      pubkey_fp="",
      pid=1,
      now="2026-10-27T02:00:00Z",
    ) {
    Err(m) => abort("agents_register 失败：" + m)
    Ok(_) => ()
  }
  // 记录在表里（假绿防护：先证明它不是「查不到」）
  match e.agents_get(agent_fp_of("fist-mbt")) {
    None =>
      abort("★判据没跑到被测面：server 自身份记录没写成")
    Some(rec) => assert_eq(rec.role, "Leader")
  }
  // 但裁决面看不到它 ⇒ Executor / inferred / rank 5
  let (role, src) = judged_role(e, "fist-mbt")
  assert_eq(role, "Executor")
  assert_eq(src, "inferred")
  assert_eq(rank_of_role(role), 5)
  // 端到端：领 level=4 仍被拒，且文案自证走了推断
  let t4 = cr_publish(e, "团长级任务（level=4）", 4)
  let msg = cr_err_of(
    e.claim(task_id=t4, assignee="fist-mbt", now="2026-10-27T02:00:00Z"),
  )
  assert_true(msg.contains("RANK_GATE"))
  assert_true(msg.contains("rank=5"))
  assert_true(msg.contains("role_source=inferred"))
}
