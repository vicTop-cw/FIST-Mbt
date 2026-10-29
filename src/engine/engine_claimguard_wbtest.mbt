/// engine_claimguard_wbtest.mbt —— T0r2：`src/claimguard/` 接进 `claim` 路径的白盒锁。
///
/// 背景：`src/claimguard/` 落地后**零接线**（`grep -c claimguard src/engine/engine.mbt`
/// 与 `src/server/server.mbt` 都是 0），「同一逻辑项同一时刻只被一人持有」这条承诺
/// 在真实 claim 路径上一次也没生效过。本文件锁的就是「接线」本身。
///
/// 判例纪律：
///   · **确定性双路互斥**（判例-31）：手工复刻「A 已持有 → B 再 claim」两步，
///     **不用 sleep 抢时序**（不可复现的锁 = 不可信的锁）；
///   · 只断言**返回值 / 错误文案 / guard 状态**，**不断言「源码里有某字符串」**
///     （判例-30 自指假绿：模式串自己就在被测文件里，改坏代码也照样命中）；
///   · 变异对照（把前置互斥改成直接放行 ⇒ 5 格转红）的实测读数写在
///     T0r2 回执里，判据形态见本文件末尾 G6 注释。
///
/// 为什么是**白盒**：`claim_guard` / `claim_item_key` / `release_claim_item` 都是
/// 包内私有——只有同编译单元的白盒测试能直接读到「持有者是谁」，
/// 黑盒只能拿到错误文案，锁不住「释放真的发生了」。

///|
/// 取 Result 错误文案（Ok 侧哨兵；与 claim_rank_wbtest 的 cr_err_of 同形）。
fn cgx_err_of(r : Result[@core.Task, String]) -> String {
  match r {
    Err(e) => e
    Ok(_) => "<ok>"
  }
}

///|
/// 在指定 ns 发布一个根任务（默认 level=6 连长级：执行者档 rank=5 可领），返回 task_id。
/// 每个用例用**自己的 ns**，让 guard 键天然隔离，互不污染（也顺带锁住「键带 ns」）。
fn cgx_publish(e : FistEngine, ns : String, desc : String) -> String {
  match
    e.publish(
      project_dir="/proj/claimguard",
      description=desc,
      created_by="human_steward",
      now="2026-10-29T20:00:00Z",
      ns~,
    ) {
    Ok(id) => id
    Err(m) => abort("publish failed: \{m}")
  }
}

///|
/// 认领必须成功（成功语义零回归的正例哨兵）。
/// 注意：`assert_eq` 会抛错，只能出现在 `test` 块里；helper 里用 `abort` 表达同义。
fn cgx_claim_ok(
  e : FistEngine,
  tid : String,
  who : String,
  now : String,
) -> Unit {
  match e.claim(task_id=tid, assignee=who, now~) {
    Ok(t) =>
      if t.assignee != Some(who) {
        abort("\{who} 认领 \{tid} 应成功且 assignee 为其本人")
      }
    Err(m) => abort("\{who} 认领 \{tid} 应成功，实际被拒: \{m}")
  }
}

// ===== G1：确定性双路互斥（核心判据）=====

///|
/// G1：A 已持有 ⇒ **同一逻辑项**上的 B 再 claim 必被拒，且错误文案里能读到 A。
///
/// 两步都是**显式手工调用**，中间没有任何等待：第一步的 `Ok` 就代表账本已落定
/// （已领取 + guard 记下 A），第二步的拒绝因此是确定性的，不依赖调度顺序。
///
/// 变异对照（实测见回执）：把 claim 里的 `claim_item` 互斥改成直接放行 ⇒
/// 本格第二条断言必红（B 的 claim 会落到状态门 ⇒ 文案不含 `CLAIM_GUARD`、也读不到 A）。
test "claim_guard G1: A 已持有 ⇒ B 再 claim 同一逻辑项被拒且点名 A" {
  let e = FistEngine::new()
  let ns = "cg-g1"
  let tid = cgx_publish(e, ns, "逻辑项互斥·主路径")
  let key = claim_item_key(ns, tid)
  // 第一步：A 认领成功（既有成功语义不变）
  cgx_claim_ok(e, tid, "lane-A", "2026-10-29T20:01:00Z")
  // guard 真的记下了持有者（不是「看起来过了」）
  assert_eq(@claimguard.holder_of(claim_guard, key), Some("lane-A"))
  // 第二步：B 再 claim 同一任务 ⇒ 必被拒，且文案可读出 A（便于调用方自救）
  let msg = cgx_err_of(
    e.claim(task_id=tid, assignee="lane-B", now="2026-10-29T20:02:00Z"),
  )
  assert_true(msg.contains("CLAIM_GUARD"))
  assert_true(msg.contains("lane-A"))
  // B 不得夺走持有（拒绝必须无副作用）
  assert_eq(@claimguard.holder_of(claim_guard, key), Some("lane-A"))
}

///|
/// G1-b：**同 id 不同 ns 不得互相拦截**（键必须带 ns）。
///
/// 任务 id 空间是**每库各自**的（T0/T0r2 在多棵树里都存在）——只按 task_id 记
/// 会把两个 ns 的无关任务判成同一条逻辑项。这格就是那条边界的反例位。
test "claim_guard G1: 同 id 不同 ns 互不拦截（键带 ns）" {
  let e = FistEngine::new()
  let tid_a = cgx_publish(e, "cg-g1b-a", "ns A 的任务")
  let tid_b = cgx_publish(e, "cg-g1b-b", "ns B 的任务")
  // 两个库各自的第一个根任务，id 大概率相同（publish 用 first_free_root_id）
  cgx_claim_ok(e, tid_a, "lane-A", "2026-10-29T20:03:00Z")
  // B 在自己 ns 里认领同名 id：必须放行（键里的 ns 不同）
  cgx_claim_ok(e, tid_b, "lane-B", "2026-10-29T20:04:00Z")
  assert_eq(
    @claimguard.holder_of(claim_guard, claim_item_key("cg-g1b-a", tid_a)),
    Some("lane-A"),
  )
  assert_eq(
    @claimguard.holder_of(claim_guard, claim_item_key("cg-g1b-b", tid_b)),
    Some("lane-B"),
  )
}

// ===== G2：释放后可再生（防死锁式持有）=====

///|
/// G2：`pause` 释放持有 ⇒ 该逻辑项**可以再被拿到**，且后续 claim 不再撞 CLAIM_GUARD。
///
/// 为什么断言两条：
///   ① guard 层「可再生」——释放后 B 能拿到这一项（证明不是只清了错误文案）；
///   ② 端到端不泄漏——B 的 claim 落到**状态门**（任务已暂停）而不是 CLAIM_GUARD，
///      即「暂停后无人能接」那种死锁式持有不存在。
test "claim_guard G2: pause 释放持有 ⇒ 逻辑项可再生、不锁死" {
  let e = FistEngine::new()
  let ns = "cg-g2"
  let tid = cgx_publish(e, ns, "释放后可再生")
  let key = claim_item_key(ns, tid)
  cgx_claim_ok(e, tid, "lane-A", "2026-10-29T20:05:00Z")
  assert_eq(@claimguard.holder_of(claim_guard, key), Some("lane-A"))
  // 暂停 = 释放点之一
  match e.pause_task(task_id=tid, now="2026-10-29T20:06:00Z") {
    Ok(_) => ()
    Err(m) => abort("pause 应成功，实际: \{m}")
  }
  assert_eq(@claimguard.holder_of(claim_guard, key), None)
  // ① guard 层：B 现在能拿到这一项
  match @claimguard.claim_item(claim_guard, key, "lane-B") {
    Claimed => ()
    _ =>
      abort(
        "释放后 B 应能拿到该逻辑项（实际 verdict != Claimed）",
      )
  }
  ignore(@claimguard.release_item(claim_guard, key, "lane-B"))
  // ② 端到端：B 的 claim 不再被 CLAIM_GUARD 拦（改由状态门拒绝），文案必须不含 CLAIM_GUARD
  let msg = cgx_err_of(
    e.claim(task_id=tid, assignee="lane-B", now="2026-10-29T20:07:00Z"),
  )
  assert_false(msg.contains("CLAIM_GUARD"))
}

///|
/// G2-b：`reject`（打回）也是释放点 —— 打回后该项退回可返工态，持有必须释放。
test "claim_guard G2: reject 打回释放持有" {
  let e = FistEngine::new()
  let ns = "cg-g2b"
  let tid = cgx_publish(e, ns, "打回释放")
  let key = claim_item_key(ns, tid)
  cgx_claim_ok(e, tid, "lane-A", "2026-10-29T20:08:00Z")
  match
    e.execute(task_id=tid, deliverable="交付物", now="2026-10-29T20:09:00Z") {
    Ok(_) => ()
    Err(m) => abort("execute 应成功，实际: \{m}")
  }
  match e.submit(task_id=tid, now="2026-10-29T20:10:00Z") {
    Ok(_) => ()
    Err(m) => abort("submit 应成功，实际: \{m}")
  }
  assert_eq(@claimguard.holder_of(claim_guard, key), Some("lane-A"))
  match
    e.reject_task(
      task_id=tid,
      reason="重做",
      by="human_steward",
      now="2026-10-29T20:11:00Z",
    ) {
    Ok(_) => ()
    Err(m) => abort("reject 应成功，实际: \{m}")
  }
  assert_eq(@claimguard.holder_of(claim_guard, key), None)
}

///|
/// G2-c：`verify`（验收完成）也是释放点 —— 验收即该项了结，持有不再需要。
test "claim_guard G2: verify 验收完成释放持有" {
  let e = FistEngine::new()
  let ns = "cg-g2c"
  let tid = cgx_publish(e, ns, "验收释放")
  let key = claim_item_key(ns, tid)
  cgx_claim_ok(e, tid, "lane-A", "2026-10-29T20:12:00Z")
  match
    e.execute(task_id=tid, deliverable="交付物", now="2026-10-29T20:13:00Z") {
    Ok(_) => ()
    Err(m) => abort("execute 应成功，实际: \{m}")
  }
  match e.submit(task_id=tid, now="2026-10-29T20:14:00Z") {
    Ok(_) => ()
    Err(m) => abort("submit 应成功，实际: \{m}")
  }
  match
    e.verify(task_id=tid, verifier="human_steward", now="2026-10-29T20:15:00Z") {
    Ok(_) => ()
    Err(m) => abort("verify 应成功，实际: \{m}")
  }
  assert_eq(@claimguard.holder_of(claim_guard, key), None)
}

///|
/// G2-d：`archive`（归档）也是释放点。
///
/// 做法：verify 已释放一次 ⇒ 先**人工植入**一条残留持有，再 archive，
/// 断言归档把这残留清掉。若 archive 里没有释放点，这条残留会一直留着 ⇒ 本格红。
test "claim_guard G2: archive 归档释放持有" {
  let e = FistEngine::new()
  let ns = "cg-g2d"
  let tid = cgx_publish(e, ns, "归档释放")
  let key = claim_item_key(ns, tid)
  cgx_claim_ok(e, tid, "lane-A", "2026-10-29T20:16:00Z")
  match
    e.execute(task_id=tid, deliverable="交付物", now="2026-10-29T20:17:00Z") {
    Ok(_) => ()
    Err(m) => abort("execute 应成功，实际: \{m}")
  }
  match e.submit(task_id=tid, now="2026-10-29T20:18:00Z") {
    Ok(_) => ()
    Err(m) => abort("submit 应成功，实际: \{m}")
  }
  match
    e.verify(task_id=tid, verifier="human_steward", now="2026-10-29T20:19:00Z") {
    Ok(_) => ()
    Err(m) => abort("verify 应成功，实际: \{m}")
  }
  // 植入残留持有（模拟「释放点漏了一处」的形状），archive 必须把它清掉
  ignore(@claimguard.claim_item(claim_guard, key, "lane-stale"))
  assert_eq(@claimguard.holder_of(claim_guard, key), Some("lane-stale"))
  match e.archive(task_id=tid, by="human_steward", now="2026-10-29T20:20:00Z") {
    Ok(_) => ()
    Err(m) => abort("archive 应成功，实际: \{m}")
  }
  assert_eq(@claimguard.holder_of(claim_guard, key), None)
}

// ===== G3：拒绝必须无副作用（门的先后顺序锁）=====

///|
/// G3：被**前序门**拒掉的认领，不得在 guard 里留下任何条目。
///
/// guard 若被前移到军衔门之前，一次「越级被拒」就会留下一条持有 ⇒ 该任务被锁死，
/// 而失败方根本没拿到它。本格用 RANK_GATE 做前序门（rank=5 领 level=4 必拒）。
test "claim_guard G3: 被前序门拒掉不留持有（门在 guard 之前）" {
  let e = FistEngine::new()
  let ns = "cg-g3"
  let tid = cgx_publish(e, ns, "团长级任务")
  // 先把它抬到 level=4（用 publish 的 level 参数另发一条更直接，这里复用同库第二条）
  let hi = match
    e.publish(
      project_dir="/proj/claimguard",
      description="团长级（level=4）",
      created_by="human_steward",
      now="2026-10-29T20:21:00Z",
      ns~,
      level=4,
    ) {
    Ok(id) => id
    Err(m) => abort("publish level=4 失败: \{m}")
  }
  let msg = cgx_err_of(
    e.claim(task_id=hi, assignee="lane-A", now="2026-10-29T20:22:00Z"),
  )
  assert_true(msg.contains("RANK_GATE"))
  // 被拒的认领不得留下持有
  assert_eq(@claimguard.holder_of(claim_guard, claim_item_key(ns, hi)), None)
  // 同库另一条可领的任务不受影响（防「门装成一刀切」）
  cgx_claim_ok(e, tid, "lane-A", "2026-10-29T20:23:00Z")
}

// ===== G4：陈旧持有对账（不锁死）=====

///|
/// G4：guard 是**进程内**的、账本是**库内**的。同 (ns,id) 在**另一份库**留下的持有，
/// 在本库表现为「行仍是待领取」⇒ 必须允许接管，否则一条陈旧条目把任务**永久锁死**。
///
/// 这条同时说明我们**没有**在这里偷偷改变 claim 的成功语义：接管后照常 Ok。
test "claim_guard G4: 账本仍待领取 ⇒ 陈旧持有被接管（不锁死）" {
  let ns = "cg-g4"
  // 库 1：A 认领成功 ⇒ guard 记下 (cg-g4, T0) = lane-A
  let e1 = FistEngine::new()
  let tid1 = cgx_publish(e1, ns, "库1 的任务")
  cgx_claim_ok(e1, tid1, "lane-A", "2026-10-29T20:24:00Z")
  assert_eq(
    @claimguard.holder_of(claim_guard, claim_item_key(ns, tid1)),
    Some("lane-A"),
  )
  // 库 2：同 ns、同 id 的**另一行**，状态仍是待领取
  let e2 = FistEngine::new()
  let tid2 = cgx_publish(e2, ns, "库2 的任务")
  assert_eq(tid1, tid2) // 证明确实是同一个 (ns,id) 键（否则本格测的不是这条边界）
  // 账本说这行没人认领 ⇒ 陈旧持有必须被接管，B 照常拿到
  cgx_claim_ok(e2, tid2, "lane-B", "2026-10-29T20:25:00Z")
  assert_eq(
    @claimguard.holder_of(claim_guard, claim_item_key(ns, tid2)),
    Some("lane-B"),
  )
}

// ===== G6：变异对照（读数在 T0r2 回执里，不是常量断言）=====
//
// 变异体（**已实测**，读数见 T0r2 回执「证据 · 变异红/绿」一栏；本文件不写死报告路径，
// 免得文档一搬家就留一条悬空引用）：
//   把 claim 里的
//     `match @claimguard.claim_item(claim_guard, gitem, assignee) { Denied => return Err(...) ... }`
//   改成永远放行（`let mut gowned = false` 之后不再调用 claim_item）⇒
//     · 实测 **8 格 → 3 passed / 5 failed**：G1（互斥）、G1-b、G2（pause）、G2-b（reject）、
//       G4（陈旧对账）全红 —— 它们要么依赖互斥裁决，要么依赖「持有真的被记下来」；
//     · G2-c（verify）/ G2-d（archive）/ G3（前序门无副作用）仍绿：它们不依赖互斥，
//       恰好自证「这 3 格测的是释放入口与门的顺序，不是同一件事」。
//   还原后复绿（8/8）。
// 这一格不用 `assert_true(msg.contains(...))` 断言源码，而是**真改实现再跑**——
// 判例-30/32：锁只认行为读数，不认「文件里有没有那个字符串」。
