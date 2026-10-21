/// claimguard_wbtest.mbt —— 逻辑项互斥闸（BACKLOG 多 lane 盲点收口，F094 §4 推荐形态）
///
/// 物理文件锁 / 作用域锁 / file_binds 只防「物理并发」；
/// 关不上「两个 agent 在互不相交的文件作用域里实现同一个 BACKLOG 项」这扇逻辑碰撞门
/// （见 reports/2026-10-13-multilane-lock-mechanism-report.md §9 的实测证据）。
/// 本测试证明 claimguard 这一层能补上：单一裁决真源 + 批量原子抢占 + 盲点探测。
/// 白盒（与源同编译单元）直接构造 ClaimGuardState 并调用内部函数。

///|
/// 空闲项 -> Claimed（逻辑项从无主到被本 agent 持有）。
test "cg_claim_free" {
  let g = make_guard()
  let v = claim_item(g, "L38-symbolic", "A")
  match v {
    Claimed => ()
    _ => abort("cg_claim_free: expected Claimed")
  }
  assert_eq(holder_of(g, "L38-symbolic"), Some("A"))
}

///|
/// 本人重复认领 -> Renewed（与 store_rsv.mbt::rsv_action owner==agent 同序：排在过期前）。
test "cg_claim_renew" {
  let g = make_guard()
  ignore(claim_item(g, "L38-symbolic", "A"))
  let v = claim_item(g, "L38-symbolic", "A")
  match v {
    Renewed => ()
    _ => abort("cg_claim_renew: expected Renewed")
  }
  // 状态不变：仍是 A
  assert_eq(holder_of(g, "L38-symbolic"), Some("A"))
}

///|
/// 他主已持有 -> Denied（这是物理锁看不见的碰撞：两个作用域互不相交却抢同一项）。
test "cg_claim_denied" {
  let g = make_guard()
  ignore(claim_item(g, "L38-symbolic", "A"))
  let v = claim_item(g, "L38-symbolic", "B")
  match v {
    Denied => ()
    _ => abort("cg_claim_denied: expected Denied")
  }
  // 持主不变，B 不得写入
  assert_eq(holder_of(g, "L38-symbolic"), Some("A"))
}

///|
/// 释放：只有持主能释放；他主释放被拒（防误删他人锁）。
test "cg_release_owner" {
  let g = make_guard()
  ignore(claim_item(g, "L35-milestone", "A"))
  // 他主释放 -> Denied
  let r1 = release_item(g, "L35-milestone", "B")
  match r1 {
    Denied => ()
    _ => abort("cg_release_owner: expected Denied")
  }
  assert_eq(holder_of(g, "L35-milestone"), Some("A"))
  // 持主释放 -> Released
  let r2 = release_item(g, "L35-milestone", "A")
  match r2 {
    Released => ()
    _ => abort("cg_release_owner: expected Released")
  }
  assert_eq(holder_of(g, "L35-milestone"), None)
}

///|
/// 释放空闲项 -> Released（幂等，不报错）。
test "cg_release_free" {
  let g = make_guard()
  match release_item(g, "nope", "A") {
    Released => ()
    _ => abort("cg_release_free: expected Released")
  }
}

///|
/// 批量原子抢占：任一被他主持有 -> 整批 Denied，且不得静默写入子集。
test "cg_claim_all_conflict" {
  let g = make_guard()
  ignore(claim_item(g, "item-x", "A"))
  let res = claim_all(g, ["item-x", "item-y"], "B")
  assert_true(res is Err(_))
  // item-y 不应被 B 抢占（整批回滚）
  assert_eq(holder_of(g, "item-y"), None)
  assert_eq(holder_of(g, "item-x"), Some("A"))
}

///|
/// 批量原子抢占：全空闲 -> 整批成功。
test "cg_claim_all_ok" {
  let g = make_guard()
  let res = claim_all(g, ["item-a", "item-b"], "A")
  assert_true(res is Ok(_))
  assert_eq(holder_of(g, "item-a"), Some("A"))
  assert_eq(holder_of(g, "item-b"), Some("A"))
  release_all(g, ["item-a", "item-b"], "A")
  assert_eq(holder_of(g, "item-a"), None)
  assert_eq(holder_of(g, "item-b"), None)
}

///|
/// 盲点判定：作用域互不相交 且 项已被他主逻辑持有 -> blind_spot=true。
/// 正是「物理锁静默、逻辑锁必须报警」的现场还原。
test "cg_blind_spot_true" {
  // A 在 src/symbolic/ 实现 L38；B 在 src/constraint/ 实现同一个逻辑项（历史实景）
  let a_scope = ["src/symbolic/"]
  let b_scope = ["src/constraint/"]
  assert_true(scopes_disjoint(a_scope, b_scope))
  let g = make_guard()
  ignore(claim_item(g, "L38-logic-engine", "A")) // A 已逻辑认领
  let claimed_by_other = match holder_of(g, "L38-logic-engine") {
    Some(h) => h != "B"
    None => false
  }
  assert_true(
    blind_spot_holds(scopes_disjoint(a_scope, b_scope), claimed_by_other),
  )
}

///|
/// 非盲点：作用域相交时物理锁会报警，不应误判为盲点。
test "cg_blind_spot_false_when_overlap" {
  let a_scope = ["src/store/"]
  let b_scope = ["src/store/", "src/server/"]
  assert_true(!scopes_disjoint(a_scope, b_scope))
  // 即便项被他主持有，作用域相交 -> 物理锁已能看见，不算盲点
  assert_true(!blind_spot_holds(scopes_disjoint(a_scope, b_scope), true))
}

///|
/// 门控：逻辑认领被拒时，即便文件作用域互不相交也不得 proceed。
test "cg_may_proceed_denied" {
  let g = make_guard()
  ignore(claim_item(g, "L38-logic-engine", "A"))
  // B 文件作用域与 A 不相交，但逻辑项已被 A 占 -> 必须拦下
  assert_true(!may_proceed(g, "L38-logic-engine", "B"))
  // 未被静默写入
  assert_eq(holder_of(g, "L38-logic-engine"), Some("A"))
}

///|
/// 门控：逻辑认领成功方可 proceed（含续订自己）。
test "cg_may_proceed_ok" {
  let g = make_guard()
  assert_true(may_proceed(g, "L49-f094", "B"))
  // 同一 agent 续订仍可 proceed
  assert_true(may_proceed(g, "L49-f094", "B"))
  assert_eq(holder_of(g, "L49-f094"), Some("B"))
}

///|
/// snapshot 隔离：只读拷贝，外部修改不动闸内状态。
test "cg_snapshot_isolated" {
  let g = make_guard()
  ignore(claim_item(g, "k", "A"))
  let s = snapshot(g)
  s.set("k", "B") // 仅改快照
  assert_eq(holder_of(g, "k"), Some("A")) // 闸内不受影响
}

///|
/// 语义盲点（比 item-id 更深）：两 agent 实现「不同但重叠」的逻辑项、文件作用域互不相交。
/// 物理锁（作用域不相交）静默；item-id 锁（两项 id 不同）静默；唯有 topic 标签交集能发现。
test "cg_semantic_collision_detected" {
  let g = make_guard()
  // A 认领了 L16「native 巡检」并打标签 native/inspection
  ignore(claim_item(g, "L16-native-inspect", "A"))
  set_tags(g, "L16-native-inspect", ["native", "inspection"])
  // B 想做 L33「self_search 入库」，标签 native/evolve —— 与 A 的 native 标签重合
  let proposed_tags = ["native", "evolve"]
  assert_true(semantic_collision(g, "L33-self-search", proposed_tags, "B"))
  // 综合门：本应被拦下，即便文件作用域不相交
  assert_true(!may_proceed_sematic(g, "L33-self-search", proposed_tags, "B"))
}

///|
/// 语义不碰撞：标签完全无交集 -> 可 proceed（即便都是 native 系的不同子系统）。
test "cg_semantic_no_collision_ok" {
  let g = make_guard()
  ignore(claim_item(g, "L35-milestone", "A"))
  set_tags(g, "L35-milestone", ["decompose", "planning"])
  let proposed_tags = ["diff", "text"]
  assert_true(!semantic_collision(g, "L31-diff", proposed_tags, "B"))
  assert_true(may_proceed_sematic(g, "L31-diff", proposed_tags, "B"))
}

///|
/// 自重叠豁免：同一 agent 的两条重叠标签项不算碰撞（允许本人跨项复用能力）。
test "cg_semantic_self_overlap_exempt" {
  let g = make_guard()
  ignore(claim_item(g, "L16-native-inspect", "A"))
  set_tags(g, "L16-native-inspect", ["native", "inspection"])
  // 同一 agent A 又认领带 native 标签的项 -> 不算与他主碰撞
  let proposed_tags = ["native", "evolve"]
  assert_true(!semantic_collision(g, "L33-self-search", proposed_tags, "A"))
  assert_true(may_proceed_sematic(g, "L33-self-search", proposed_tags, "A"))
}

///|
/// tags_overlap 纯函数：交集即 true，空集/无交集即 false。
test "cg_tags_overlap" {
  assert_true(tags_overlap(["native", "x"], ["native", "y"]))
  assert_true(!tags_overlap(["a", "b"], ["c", "d"]))
  assert_true(!tags_overlap([], ["a"]))
}

///|
/// set_tags 持久化 + 释放即清标签：避免残留标签误触发后续语义碰撞。
test "cg_tags_lifecycle" {
  let g = make_guard()
  ignore(claim_item(g, "L16-native-inspect", "A"))
  set_tags(g, "L16-native-inspect", ["native", "inspection"])
  assert_eq(tags_of(g, "L16-native-inspect"), ["native", "inspection"])
  ignore(release_item(g, "L16-native-inspect", "A"))
  assert_eq(tags_of(g, "L16-native-inspect"), [])
}

///|
/// 三维综合门（Round 6）：item-id 层被拒即拦（即便作用域不相交、标签无交集）。
test "cg_full_gate_item_id_block" {
  let g = make_guard()
  // A 逻辑认领 L38
  ignore(claim_item(g, "L38-logic-engine", "A"))
  // B 在互不相交的文件作用域里想做同一项，且标签完全无关 -> 仍应在 item-id 层被拦
  let proposed_tags = ["decompose", "planning"]
  assert_true(
    !may_proceed_full(g, "L38-logic-engine", proposed_tags, "B", true, true),
  )
  assert_eq(holder_of(g, "L38-logic-engine"), Some("A"))
}

///|
/// 三维综合门（Round 6）：三层都通过才放行（不同 id + 作用域相交本应物理报警 -> 这里以
/// scopes_disjoint=false 表示物理锁已可见、不算盲点，且标签无交集）。
test "cg_full_gate_ok" {
  let g = make_guard()
  // 已有人认领一个带 native 标签的项
  ignore(claim_item(g, "L16-native-inspect", "A"))
  set_tags(g, "L16-native-inspect", ["native", "inspection"])
  // B 想做另一项：id 不同、作用域不相交(物理静默)、标签无交集 -> 三层全过，放行
  let proposed_tags = ["diff", "text"]
  assert_true(may_proceed_full(g, "L31-diff", proposed_tags, "B", true, false))
}

///|
/// 跨 agent 调和对账（Round 7）：两个 agent 各自维护一份 guard 状态、文件作用域互不相交，
/// 物理锁全程静默；仅当把两份状态对账时，才能发现「同一个 item-id 被两个不同 agent 各认领一次」。
test "cg_reconcile_id_conflict" {
  let ga = make_guard()
  let gb = make_guard()
  ignore(claim_item(ga, "L38-logic-engine", "A")) // A 在 src/symbolic 认领
  ignore(claim_item(gb, "L38-logic-engine", "B")) // B 在 src/constraint 也认领同一项
  // 各自单看：都以为自己独占；物理锁静默（作用域不相交）
  assert_eq(holder_of(ga, "L38-logic-engine"), Some("A"))
  assert_eq(holder_of(gb, "L38-logic-engine"), Some("B"))
  // 对账揭示冲突
  let conflicts = reconcile_id_conflicts(ga, gb)
  assert_eq(conflicts.get("L38-logic-engine"), Some(("A", "B")))
  // 对账是只读的，不动任一方状态
  assert_eq(holder_of(ga, "L38-logic-engine"), Some("A"))
  assert_eq(holder_of(gb, "L38-logic-engine"), Some("B"))
}

///|
/// 跨 agent 对账·语义（Round 7）：不同 id、不同 agent、作用域不相交，但标签交集——
/// 两份状态各自 silent、物理锁 silent，只有对账能发现。
test "cg_reconcile_semantic_collision" {
  let ga = make_guard()
  let gb = make_guard()
  // A 在 L16「native 巡检」打 native/inspection
  ignore(claim_item(ga, "L16-native-inspect", "A"))
  set_tags(ga, "L16-native-inspect", ["native", "inspection"])
  // B 在 L33「self_search 入库」打 native/evolve
  ignore(claim_item(gb, "L33-self-search", "B"))
  set_tags(gb, "L33-self-search", ["native", "evolve"])
  // 各自单看：无同 id 冲突、各自无语义碰撞（自己跟自己）
  assert_true(reconcile_id_conflicts(ga, gb).is_empty())
  // 对账发现跨 agent 语义碰撞（native 标签交集）
  let hits = reconcile_semantic_conflicts(ga, gb)
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].agent_a, "A")
  assert_eq(hits[0].agent_b, "B")
  assert_eq(hits[0].tag, "native")
  // 同 tag 多对也会计入（反向对也出现一次 -> 双向枚举）
  let hits2 = reconcile_semantic_conflicts(gb, ga)
  assert_eq(hits2.length(), 1)
}

///|
/// 集中裁决（Round 8）：协调器读两份 agent 状态，给出单一放行布尔。
/// 同 id 双重认领 -> 拦（即便作用域不相交、物理锁静默）。
test "cg_may_reconcile_id_block" {
  let ga = make_guard()
  let gb = make_guard()
  ignore(claim_item(ga, "L38-logic-engine", "A"))
  ignore(claim_item(gb, "L38-logic-engine", "B")) // 两 agent 各认领同 id，作用域不相交
  assert_true(!may_reconcile_ok(ga, gb))
  let (nid, nsem) = reconcile_summary(ga, gb)
  assert_eq(nid, 1)
  assert_eq(nsem, 0)
}

///|
/// 集中裁决（Round 8）：跨 agent 语义碰撞 -> 拦；反向也拦（对称性）。
test "cg_may_reconcile_semantic_block" {
  let ga = make_guard()
  let gb = make_guard()
  ignore(claim_item(ga, "L16-native-inspect", "A"))
  set_tags(ga, "L16-native-inspect", ["native", "inspection"])
  ignore(claim_item(gb, "L33-self-search", "B"))
  set_tags(gb, "L33-self-search", ["native", "evolve"])
  assert_true(!may_reconcile_ok(ga, gb))
  assert_true(!may_reconcile_ok(gb, ga)) // 对称性
  let (nid, nsem) = reconcile_summary(ga, gb)
  assert_eq(nid, 0)
  assert_eq(nsem, 1)
}

///|
/// 集中裁决（Round 8）：两份状态无 id 冲突、无语义交集 -> 放行（双 agent 真可并行）。
test "cg_may_reconcile_ok" {
  let ga = make_guard()
  let gb = make_guard()
  ignore(claim_item(ga, "L41-curriculum", "A"))
  set_tags(ga, "L41-curriculum", ["curriculum", "evolve"])
  ignore(claim_item(gb, "L44-posoco", "B"))
  set_tags(gb, "L44-posoco", ["architecture", "research"])
  assert_true(may_reconcile_ok(ga, gb))
  let (nid, nsem) = reconcile_summary(ga, gb)
  assert_eq(nid, 0)
  assert_eq(nsem, 0)
}

///|
/// N-agent 全配对对账（Round 9）：三 agent 各自认领互不相交的 id、标签互不相交 ->
/// 全可并行，集中裁决放行，全配对报告零冲突。
test "cg_reconcile_all_ok" {
  let ga = make_guard()
  let gb = make_guard()
  let gc = make_guard()
  ignore(claim_item(ga, "L41-curriculum", "A"))
  set_tags(ga, "L41-curriculum", ["curriculum", "evolve"])
  ignore(claim_item(gb, "L44-posoco", "B"))
  set_tags(gb, "L44-posoco", ["architecture", "research"])
  ignore(claim_item(gc, "L47-saga", "C"))
  set_tags(gc, "L47-saga", ["saga", "compensation"])
  let states = [ga, gb, gc]
  assert_true(may_reconcile_all_ok(states))
  let (nid, nsem) = reconcile_all_summary(states)
  assert_eq(nid, 0)
  assert_eq(nsem, 0)
}

///|
/// N-agent 全配对对账（Round 9）：三 agent 中 A 与 C 经同一 id 双重认领 ->
/// 即便是「A-B 不相交、B-C 不相交」的链式，全配对仍能抓出 A-C 冲突并拦下。
test "cg_reconcile_all_id_block" {
  let ga = make_guard()
  let gb = make_guard()
  let gc = make_guard()
  ignore(claim_item(ga, "L38-logic-engine", "A")) // A 认领
  ignore(claim_item(gb, "L44-posoco", "B")) // B 互不相交
  ignore(claim_item(gc, "L38-logic-engine", "C")) // C 也认领同 id（链式末端）
  let states = [ga, gb, gc]
  assert_true(!may_reconcile_all_ok(states))
  let (nid, nsem) = reconcile_all_summary(states)
  assert_eq(nid, 1) // 仅 A-C 一对命中
  assert_eq(nsem, 0)
  // 报告里记到的是 A 与 C（i<j 序），不动任一方状态
  assert_eq(reconcile_all(states).id_conflicts[0].item, "L38-logic-engine")
  assert_eq(reconcile_all(states).id_conflicts[0].agent_a, "A")
  assert_eq(reconcile_all(states).id_conflicts[0].agent_b, "C")
}

///|
/// N-agent 全配对对账（Round 9）：三 agent 中 B 与 C 语义标签交集（native 系） ->
/// 抓出跨 agent 语义碰撞并拦下，A-B / A-C 不相交不误报（A 仅带 curriculum 标签，干净）。
test "cg_reconcile_all_semantic_block" {
  let ga = make_guard()
  let gb = make_guard()
  let gc = make_guard()
  ignore(claim_item(ga, "L41-curriculum", "A"))
  set_tags(ga, "L41-curriculum", ["curriculum"])
  ignore(claim_item(gb, "L16-native-inspect", "B"))
  set_tags(gb, "L16-native-inspect", ["native", "inspection"])
  ignore(claim_item(gc, "L33-self-search", "C"))
  set_tags(gc, "L33-self-search", ["native", "evolve"])
  let states = [ga, gb, gc]
  assert_true(!may_reconcile_all_ok(states))
  let (nid, nsem) = reconcile_all_summary(states)
  assert_eq(nid, 0)
  assert_eq(nsem, 1) // 仅 B-C 一对 native 交集
  assert_eq(reconcile_all(states).semantic_conflicts[0].agent_b, "C")
}

///|
/// 准入门（Round 10）：在飞三 agent（A/B/C 互不相交）已就位，新 agent D 想认领
/// 一个全新 id、带不相交标签 -> 准入放行，碰撞 agent 列表为空（不误伤任何在飞 agent）。
test "cg_admit_ok" {
  let ga = make_guard()
  let gb = make_guard()
  let gc = make_guard()
  ignore(claim_item(ga, "L41-curriculum", "A"))
  set_tags(ga, "L41-curriculum", ["curriculum", "evolve"])
  ignore(claim_item(gb, "L44-posoco", "B"))
  set_tags(gb, "L44-posoco", ["architecture", "research"])
  ignore(claim_item(gc, "L47-saga", "C"))
  set_tags(gc, "L47-saga", ["saga", "compensation"])
  let gd = make_guard()
  ignore(claim_item(gd, "L50-patch", "D")) // D 全新 id
  set_tags(gd, "L50-patch", ["patch", "hotfix"])
  let r = admit(gd, [ga, gb, gc])
  assert_true(r.ok)
  assert_eq(r.colliding_agents.length(), 0)
  assert_true(admit_ok(gd, [ga, gb, gc]))
}

///|
/// 准入门（Round 10）：在飞 A 已认领 L41-curriculum，新 agent D 也想认领同 id ->
/// 准入拦下，且精确点名碰撞 agent = ["A"]（不误伤干净的 B/C），不动任一方状态。
test "cg_admit_id_block" {
  let ga = make_guard()
  ignore(claim_item(ga, "L41-curriculum", "A"))
  let gb = make_guard()
  ignore(claim_item(gb, "L44-posoco", "B"))
  let gc = make_guard()
  ignore(claim_item(gc, "L47-saga", "C"))
  let gd = make_guard()
  ignore(claim_item(gd, "L41-curriculum", "D")) // 与 A 抢同 id
  let r = admit(gd, [ga, gb, gc])
  assert_true(!r.ok)
  assert_eq(r.colliding_agents.length(), 1)
  assert_true(r.colliding_agents.contains("A"))
  // 在飞 agent 之间本就干净，所以门禁只暴露 D-A 这一处 id 冲突
  assert_eq(r.id_conflicts.length(), 1)
  assert_eq(r.semantic_conflicts.length(), 0)
  assert_eq(r.id_conflicts[0].item, "L41-curriculum")
  // 全配对里 proposed(gd) 在 index 0 -> 记为 agent_a，被撞的 peer(ga) -> agent_b
  assert_eq(r.id_conflicts[0].agent_a, "D")
  assert_eq(r.id_conflicts[0].agent_b, "A")
}

///|
/// 准入门（Round 10）：三 agent A/B/C 经同一 id 互相双重认领（A-B、A-C、B-C 三对都冲突） ->
/// 全配对报告 + 分诊记分牌能给每个 agent 打出「参与度 = 2」的冲突度，供协调器决定谁先让。
test "cg_conflict_scoreboard" {
  let ga = make_guard()
  let gb = make_guard()
  let gc = make_guard()
  ignore(claim_item(ga, "L38-logic-engine", "A"))
  ignore(claim_item(gb, "L38-logic-engine", "B"))
  ignore(claim_item(gc, "L38-logic-engine", "C"))
  let states = [ga, gb, gc]
  let report = reconcile_all(states)
  assert_eq(report.id_conflicts.length(), 3) // 三对全冲突
  let board = conflict_scoreboard(report)
  assert_eq(board.get_or_default("A", 0), 2)
  assert_eq(board.get_or_default("B", 0), 2)
  assert_eq(board.get_or_default("C", 0), 2)
  // 没有任何在飞 agent 是干净的（全部卷入），分诊一目了然
  assert_eq(board.length(), 3)
}

///|
/// 协商层（Round 11）：peer_yield 是「模拟让权」——把某 agent 持有的全部 item 释放，
/// 返回全新状态、不动原状态。纯函数，不碰 claim_item/release_item，也不改任何 Map。
test "cg_peer_yield" {
  let ga = make_guard()
  ignore(claim_item(ga, "L41-curriculum", "A"))
  ignore(claim_item(ga, "L44-posoco", "B")) // B 持有，A 让权不该动到它
  ignore(claim_item(ga, "L47-saga", "A"))
  let relaxed = peer_yield(ga, "A")
  // A 让出后只剩 B 的 L44
  assert_eq(relaxed.holders.length(), 1)
  assert_eq(relaxed.holders.get_or_default("L44-posoco", ""), "B")
  assert_eq(relaxed.holders.get("L41-curriculum") is Some(_), false)
  assert_eq(relaxed.holders.get("L47-saga") is Some(_), false)
  // 原状态未被 mutation（A 的两项还在）
  assert_eq(ga.holders.length(), 3)
  assert_eq(ga.holders.get_or_default("L41-curriculum", ""), "A")
}

///|
/// 协商层（Round 11）：advise_yield 在分诊记分牌上挑冲突度最高者先谈（tie 取最小名）。
/// A/B/C 三 agent 同抢 L38-logic-engine -> 各参与度 2 -> 取 "A"。
test "cg_advise_yield" {
  let ga = make_guard()
  let gb = make_guard()
  let gc = make_guard()
  ignore(claim_item(ga, "L38-logic-engine", "A"))
  ignore(claim_item(gb, "L38-logic-engine", "B"))
  ignore(claim_item(gc, "L38-logic-engine", "C"))
  let report = reconcile_all([ga, gb, gc])
  let target = advise_yield(report)
  assert_true(target is Some(_))
  assert_eq(target.unwrap(), "A")
}

///|
/// 协商层（Round 11）：admit_after_yield 模拟「若让 target 让权，新 agent 能否进」。
/// D 抢 A 的 L41-curriculum；若 A 让权（释放其全部 item），D 即被准入、colliding 清空。
/// 纯模拟：others 每个状态都被 peer_yield 投影后才重跑 R10 的 admit，不落任何真实变更。
test "cg_admit_after_yield" {
  let ga = make_guard()
  ignore(claim_item(ga, "L41-curriculum", "A"))
  let gb = make_guard()
  ignore(claim_item(gb, "L44-posoco", "B"))
  let gc = make_guard()
  ignore(claim_item(gc, "L47-saga", "C"))
  let gd = make_guard()
  ignore(claim_item(gd, "L41-curriculum", "D")) // 与 A 抢同 id
  // 先确认不让权时 D 被拦
  assert_true(!admit(gd, [ga, gb, gc]).ok)
  // 模拟 A 让权：D 应被准入
  let after = admit_after_yield(gd, [ga, gb, gc], "A")
  assert_true(after.ok)
  assert_eq(after.colliding_agents.length(), 0)
  // 真实在飞状态未被改动（A 仍持 L41）
  assert_eq(ga.holders.get_or_default("L41-curriculum", ""), "A")
}

///|
/// 协商层（Round 12）：级联谈判——新 agent 同时撞多个 peer，协调器逐个请最 contested 者让权，
/// 重跑准入直到通过。D 既抢 A 的 L41-curriculum、又抢 B 的 L44-posoco -> 需 A、B 两次让权才放行。
test "cg_negotiate_admit_chain" {
  let ga = make_guard()
  ignore(claim_item(ga, "L41-curriculum", "A"))
  let gb = make_guard()
  ignore(claim_item(gb, "L44-posoco", "B"))
  let gc = make_guard()
  ignore(claim_item(gc, "L47-saga", "C"))
  let gd = make_guard()
  ignore(claim_item(gd, "L41-curriculum", "D")) // 与 A 抢同 id
  ignore(claim_item(gd, "L44-posoco", "D")) // 与 B 也抢同 id -> 双碰撞
  // 不让权时 D 被拦，且点名两个 peer
  let blocked = admit(gd, [ga, gb, gc])
  assert_true(!blocked.ok)
  assert_eq(blocked.colliding_agents.length(), 2)
  // 级联谈判：max_steps 足够 -> 两次让权后放行
  let neg = negotiate_admit(gd, [ga, gb, gc], 4)
  assert_true(neg.ok)
  assert_eq(neg.yielded.length(), 2)
  // 真实在飞状态未被改动（A 仍持 L41、B 仍持 L44）
  assert_eq(ga.holders.get_or_default("L41-curriculum", ""), "A")
  assert_eq(gb.holders.get_or_default("L44-posoco", ""), "B")
}

///|
/// 协商层（Round 12）：谈判步数预算不足 -> 提前放弃，ok=false 且 yielded 如实记录已尝试的轮次。
test "cg_negotiate_admit_budget" {
  let ga = make_guard()
  ignore(claim_item(ga, "L41-curriculum", "A"))
  let gb = make_guard()
  ignore(claim_item(gb, "L44-posoco", "B"))
  let gc = make_guard()
  ignore(claim_item(gc, "L47-saga", "C"))
  let gd = make_guard()
  ignore(claim_item(gd, "L41-curriculum", "D"))
  ignore(claim_item(gd, "L44-posoco", "D"))
  // max_steps=0 -> 连一轮都不谈，直接返回当前 verdict（被拦）
  let neg0 = negotiate_admit(gd, [ga, gb, gc], 0)
  assert_true(!neg0.ok)
  assert_eq(neg0.yielded.length(), 0)
  // max_steps=1 -> 只谈一轮（让一个 peer），仍有第二处碰撞 -> 仍被拦，但已记 1 步
  let neg1 = negotiate_admit(gd, [ga, gb, gc], 1)
  assert_true(!neg1.ok)
  assert_eq(neg1.yielded.length(), 1)
}

///|
/// 协商层（Round 13）：优先级感知的让权目标选择。
/// 两个 peer 与 D 的碰撞度数相同（各 1），但优先级不同：Z=1（低）、A=9（高）。
/// 协调器应让「低优先级」先让（priority asc），故谈判序列首位为 Z，而非按名字升序的 A。
test "cg_negotiate_admit_priority_order" {
  let gz = make_guard()
  ignore(claim_item(gz, "item-z", "Z"))
  let ga = make_guard()
  ignore(claim_item(ga, "item-a", "A"))
  let gd = make_guard()
  ignore(claim_item(gd, "item-z", "D")) // 与 Z 抢同 id
  ignore(claim_item(gd, "item-a", "D")) // 与 A 也抢同 id -> 双碰撞、度数相同
  let prio : Map[String, Int] = Map([])
  prio.set("Z", 1)
  prio.set("A", 9)
  // 优先级感知级联：max_steps 足够 -> 两次让权后放行
  let neg = negotiate_admit_priority(gd, [gz, ga], 4, prio)
  assert_true(neg.ok)
  assert_eq(neg.yielded.length(), 2)
  // 关键断言：度数相当时，低优先级（Z=1）先于高优先级（A=9）被请让权
  assert_eq(neg.yielded[0], "Z")
  assert_eq(neg.yielded[1], "A")
  // 真实在飞状态未被改动（Z 仍持 item-z、A 仍持 item-a）
  assert_eq(gz.holders.get_or_default("item-z", ""), "Z")
  assert_eq(ga.holders.get_or_default("item-a", ""), "A")
}

///|
/// 协商层（Round 13）：与 R12 名字序级联的对照——同一场景、关掉优先级维度后，
/// 回退到「名字升序」选目标（A 先于 Z），证明 R13 的优先级维度确实改变了谈判序列。
test "cg_negotiate_admit_priority_vs_name" {
  let gz = make_guard()
  ignore(claim_item(gz, "item-z", "Z"))
  let ga = make_guard()
  ignore(claim_item(ga, "item-a", "A"))
  let gd = make_guard()
  ignore(claim_item(gd, "item-z", "D"))
  ignore(claim_item(gd, "item-a", "D"))
  // R12 名字序级联：ties 按名字升序 -> 先让 A
  let by_name = negotiate_admit(gd, [gz, ga], 4)
  assert_true(by_name.ok)
  assert_eq(by_name.yielded.length(), 2)
  assert_eq(by_name.yielded[0], "A") // 名字序：A < Z
  // R13 优先级级联：ties 按优先级升序 -> 先让 Z（优先级 1 < 9）
  let prio : Map[String, Int] = Map([])
  prio.set("Z", 1)
  prio.set("A", 9)
  let by_prio = negotiate_admit_priority(gd, [gz, ga], 4, prio)
  assert_eq(by_prio.yielded[0], "Z")
  // 两者首位不同 -> 优先级维度确实生效
  assert_true(by_name.yielded[0] != by_prio.yielded[0])
}

///|
/// 协商层（Round 14）：协调器可用的「谈判计划」包装层。
/// 复用 R13 的优先级感知级联，额外给出两个决策面度量：
///   priority_cost = 被请让权的 peer 优先级之和（干扰成本，越低越省心）
///   freed_for_proposed = 若全部让权成功，D 将能拿到的争用条目
test "cg_negotiate_plan_cost" {
  let gz = make_guard()
  ignore(claim_item(gz, "item-z", "Z"))
  let ga = make_guard()
  ignore(claim_item(ga, "item-a", "A"))
  let gd = make_guard()
  ignore(claim_item(gd, "item-z", "D"))
  ignore(claim_item(gd, "item-a", "D"))
  let prio : Map[String, Int] = Map([])
  prio.set("Z", 1)
  prio.set("A", 9)
  let plan = negotiate_plan(gd, [gz, ga], 4, prio)
  // 底层级联放行
  assert_true(plan.report.ok)
  assert_eq(plan.report.yielded.length(), 2)
  assert_eq(plan.report.yielded[0], "Z")
  assert_eq(plan.report.yielded[1], "A")
  // 干扰成本 = Z(1) + A(9) = 10
  assert_eq(plan.priority_cost, 10)
  // 释放条目 = D 想要的两条争用条目（Z 持 item-z、A 持 item-a）
  assert_eq(plan.freed_for_proposed.length(), 2)
  assert_true(plan.freed_for_proposed.contains("item-z"))
  assert_true(plan.freed_for_proposed.contains("item-a"))
  // 真实在飞状态未被改动
  assert_eq(gz.holders.get_or_default("item-z", ""), "Z")
  assert_eq(ga.holders.get_or_default("item-a", ""), "A")
}

///|
/// 协商层（Round 14）：零干扰情形——proposed 不与任何在飞 peer 争用，
/// 级联无需让权，priority_cost 必须为 0、freed 必须为空。
test "cg_negotiate_plan_clean" {
  let gz = make_guard()
  ignore(claim_item(gz, "item-z", "Z"))
  let gd = make_guard()
  ignore(claim_item(gd, "item-only-d", "D")) // 独占条目，无碰撞
  let prio : Map[String, Int] = Map([])
  prio.set("Z", 1)
  let plan = negotiate_plan(gd, [gz], 4, prio)
  assert_true(plan.report.ok)
  assert_eq(plan.report.yielded.length(), 0)
  assert_eq(plan.priority_cost, 0)
  assert_eq(plan.freed_for_proposed.length(), 0)
}

///|
/// 协商层（Round 14）：协调器决策面——同一组在飞 peer，两个候选 proposed，
/// 优先级成本更低者优先被采纳（proposed P2 只争 Z，比争 Z+A 的 P1 省心）。
test "cg_negotiate_plan_coordinator_pick" {
  let gz = make_guard()
  ignore(claim_item(gz, "item-z", "Z"))
  let ga = make_guard()
  ignore(claim_item(ga, "item-a", "A"))
  let prio : Map[String, Int] = Map([])
  prio.set("Z", 1)
  prio.set("A", 9)
  // P1 争 Z+A：让权 Z(1)+A(9)，成本 10
  let p1 = make_guard()
  ignore(claim_item(p1, "item-z", "P1"))
  ignore(claim_item(p1, "item-a", "P1"))
  let plan1 = negotiate_plan(p1, [gz, ga], 4, prio)
  // P2 只争 Z：仅让权 Z(1)，成本 1
  let p2 = make_guard()
  ignore(claim_item(p2, "item-z", "P2"))
  let plan2 = negotiate_plan(p2, [gz, ga], 4, prio)
  // 决策度量确实可排序：P2 比 P1 省心
  assert_true(plan2.priority_cost < plan1.priority_cost)
  assert_eq(plan2.priority_cost, 1)
  assert_eq(plan1.priority_cost, 10)
  // P2 仅需释放 item-z 即可放行
  assert_eq(plan2.freed_for_proposed.length(), 1)
  assert_true(plan2.freed_for_proposed.contains("item-z"))
}

///|
/// 调度层（Round 15）：协调器对「多个候选 newcomer」做最省心优先贪心采纳。
/// 同一组在飞 peer（Z 持 item-z、A 持 item-a），两个候选 P1(只争 a,成本9)、
/// P2(只争 z,成本1)：二者争的条目互不相交，故都放行；候选顺序故意反着给
/// （先 P1 后 P2），证明调度器按成本重排而非输入顺序——P2 成本更低先放。
test "cg_schedule_admit_cheapest_first" {
  let gz = make_guard()
  ignore(claim_item(gz, "item-z", "Z"))
  let ga = make_guard()
  ignore(claim_item(ga, "item-a", "A"))
  let prio : Map[String, Int] = Map([])
  prio.set("Z", 1)
  prio.set("A", 9)
  let p1 = make_guard()
  ignore(claim_item(p1, "item-a", "P1"))
  let p2 = make_guard()
  ignore(claim_item(p2, "item-z", "P2"))
  // 候选顺序故意反着给（先 P1 后 P2），证明调度器按成本重排而非输入顺序
  let rep = schedule_admit([gz, ga], [p1, p2], 4, prio)
  // 两个争的条目互不相交，都该放行
  assert_eq(rep.admitted.length(), 2)
  assert_eq(rep.rejected.length(), 0)
  // 首位必须是成本更低的 P2（争 z，成本 1）
  assert_eq(rep.admitted[0].agent, "P2")
  assert_eq(rep.admitted[1].agent, "P1")
}

///|
/// 调度层（Round 15）：多候选、条目互不相交——全部采纳且成本累加正确。
/// 在飞 peer 持三件互不相交条目，三个候选各争一件；调度器按成本升序全放，
/// 末态 scene 含三个 newcomer 的持有，总让权成本 = 9+5+3 = 17。
test "cg_schedule_admit_multi_disjoint" {
  let ga = make_guard()
  ignore(claim_item(ga, "item-a", "A"))
  let gb = make_guard()
  ignore(claim_item(gb, "item-b", "B"))
  let gc = make_guard()
  ignore(claim_item(gc, "item-c", "C"))
  let prio : Map[String, Int] = Map([])
  prio.set("A", 9)
  prio.set("B", 5)
  prio.set("C", 3)
  let p1 = make_guard()
  ignore(claim_item(p1, "item-a", "P1"))
  let p2 = make_guard()
  ignore(claim_item(p2, "item-b", "P2"))
  let p3 = make_guard()
  ignore(claim_item(p3, "item-c", "P3"))
  // 反序给，验证成本升序重排（P3 成本3 → P2 成本5 → P1 成本9）
  let rep = schedule_admit([ga, gb, gc], [p1, p2, p3], 4, prio)
  assert_eq(rep.admitted.length(), 3)
  assert_eq(rep.rejected.length(), 0)
  assert_eq(rep.total_priority_cost, 17)
  assert_eq(rep.admitted[0].agent, "P3")
  assert_eq(rep.admitted[1].agent, "P2")
  assert_eq(rep.admitted[2].agent, "P1")
  // 末态 scene 含三个 newcomer 的持有
  let mut saw_a = false
  let mut saw_b = false
  let mut saw_c = false
  for s in rep.scene {
    if s.holders.get_or_default("item-a", "") == "P1" {
      saw_a = true
    }
    if s.holders.get_or_default("item-b", "") == "P2" {
      saw_b = true
    }
    if s.holders.get_or_default("item-c", "") == "P3" {
      saw_c = true
    }
  }
  assert_true(saw_a && saw_b && saw_c)
}

///|
/// 调度层（Round 15）：已采纳的 newcomer 是「既成事实」——绝不被后来候选挤让。
/// 两个候选争同一件被高优先级 peer 独占的条目：先被采纳者提交持有，后者若想
/// 进场必须让前者让权（即挤让已提交 newcomer），于是不被采纳、整组拒绝其一个。
/// 这把「先到先得 + 提交即锁定」的不变式钉死。
test "cg_schedule_admit_committed_not_evicted" {
  let ga = make_guard()
  ignore(claim_item(ga, "item-a", "A"))
  let prio : Map[String, Int] = Map([])
  prio.set("A", 9)
  let p1 = make_guard()
  ignore(claim_item(p1, "item-a", "P1"))
  let p2 = make_guard()
  ignore(claim_item(p2, "item-a", "P2"))
  let rep = schedule_admit([ga], [p1, p2], 4, prio)
  // 两件候选互斥：恰好一个被采纳，另一个被拒（不能靠挤让已提交者进场）
  assert_eq(rep.admitted.length(), 1)
  assert_eq(rep.rejected.length(), 1)
  // 被采纳者在末态 scene 里实际持有 item-a
  let mut saw_holder = false
  for s in rep.scene {
    if s.holders.get_or_default("item-a", "") != "" {
      saw_holder = true
    }
  }
  assert_true(saw_holder)
}

///|
/// 调度层（Round 15）：步数预算不足 -> 全部拒绝，不静默放行、不改已放行集合。
/// 两个候选都争两件被高优先级 peer 独占、且单步预算下无法同时让出的条目：
/// 各自都需要 2 步才能让清，max_steps=1 下谁都进不来。
test "cg_schedule_admit_reject" {
  let gz = make_guard()
  ignore(claim_item(gz, "item-z", "Z"))
  let ga = make_guard()
  ignore(claim_item(ga, "item-a", "A"))
  let prio : Map[String, Int] = Map([])
  prio.set("Z", 1)
  prio.set("A", 9)
  let p1 = make_guard()
  ignore(claim_item(p1, "item-z", "P1"))
  ignore(claim_item(p1, "item-a", "P1"))
  let p2 = make_guard()
  ignore(claim_item(p2, "item-z", "P2"))
  ignore(claim_item(p2, "item-a", "P2"))
  // max_steps=1：需让出 Z+A(两步)才能放任一候选，一步预算下谁都进不来
  let rep = schedule_admit([gz, ga], [p1, p2], 1, prio)
  assert_eq(rep.admitted.length(), 0)
  assert_eq(rep.rejected.length(), 2)
  assert_eq(rep.total_priority_cost, 0)
}

///|
/// 调度层（Round 15）：纯只读不污染调用方——在飞 peer 与候选状态原样未被改动。
test "cg_schedule_admit_pure" {
  let gz = make_guard()
  ignore(claim_item(gz, "item-z", "Z"))
  let ga = make_guard()
  ignore(claim_item(ga, "item-a", "A"))
  let p1 = make_guard()
  ignore(claim_item(p1, "item-z", "P1"))
  ignore(claim_item(p1, "item-a", "P1"))
  let p2 = make_guard()
  ignore(claim_item(p2, "item-z", "P2"))
  let prio : Map[String, Int] = Map([])
  prio.set("Z", 1)
  prio.set("A", 9)
  let _rep = schedule_admit([gz, ga], [p1, p2], 4, prio)
  // 原在飞状态未被改动
  assert_eq(gz.holders.get_or_default("item-z", ""), "Z")
  assert_eq(ga.holders.get_or_default("item-a", ""), "A")
  // 候选状态未被改动
  assert_eq(p1.holders.get_or_default("item-a", ""), "P1")
  assert_eq(p2.holders.get_or_default("item-z", ""), "P2")
}

///|
/// 端到端不变量（Round 16）：调度器末态 scene 中，任一逻辑项至多被一个 agent 持有。
/// 这是物理文件锁 / 作用域锁 / file_binds 都关不上的「逻辑碰撞门」——
/// 两个 agent 在互不相交文件作用域里实现同一 BACKLOG 项。调度层必须把关到底：
/// peers_live ++ committed 的合并 scene 不允许出现 (item, h1) 与 (item, h2) 且 h1 != h2。
/// 返回 (是否碰撞, 项, 甲方, 乙方)。
fn cg_scene_collision(
  scene : Array[ClaimGuardState],
) -> (Bool, String, String, String) {
  let seen : Map[String, String] = Map([])
  for s in scene {
    for it, h in s.holders.iter2() {
      match seen.get(it) {
        None => seen.set(it, h)
        Some(prev) => if prev != h { return (true, it, prev, h) }
      }
    }
  }
  (false, "", "", "")
}

///|
/// 端到端（Round 16）：多候选条目互不相交——末态 scene 完全无逻辑碰撞，
/// 且每个被采纳候选的持有项都在 scene 中落到该候选名下。
test "cg_schedule_scene_invariant_disjoint" {
  let ga = make_guard()
  ignore(claim_item(ga, "item-a", "A"))
  let gb = make_guard()
  ignore(claim_item(gb, "item-b", "B"))
  let gc = make_guard()
  ignore(claim_item(gc, "item-c", "C"))
  let prio : Map[String, Int] = Map([])
  prio.set("A", 9)
  prio.set("B", 5)
  prio.set("C", 3)
  let p1 = make_guard()
  ignore(claim_item(p1, "item-a", "P1"))
  let p2 = make_guard()
  ignore(claim_item(p2, "item-b", "P2"))
  let p3 = make_guard()
  ignore(claim_item(p3, "item-c", "P3"))
  let rep = schedule_admit([ga, gb, gc], [p1, p2, p3], 4, prio)
  // 末态 scene 无逻辑碰撞
  let col = cg_scene_collision(rep.scene)
  assert_true(!col.0)
  // 每个被采纳候选的持有项在 scene 中落到该候选名下
  let mut saw_p1 = false
  let mut saw_p2 = false
  let mut saw_p3 = false
  for s in rep.scene {
    if s.holders.get_or_default("item-a", "") == "P1" {
      saw_p1 = true
    }
    if s.holders.get_or_default("item-b", "") == "P2" {
      saw_p2 = true
    }
    if s.holders.get_or_default("item-c", "") == "P3" {
      saw_p3 = true
    }
  }
  assert_true(saw_p1 && saw_p2 && saw_p3)
}

///|
/// 端到端（Round 16）：两候选争同一被 peer 独占的项——恰好一个被采纳，另一个被拒。
/// 末态 scene 无逻辑碰撞，且「被拒候选的 agent 名」绝不应作为任何状态的持主出现
/// （被拒者不得静默落到 scene 里抢走该项）。
test "cg_schedule_scene_invariant_conflict" {
  let ga = make_guard()
  ignore(claim_item(ga, "item-a", "A"))
  let prio : Map[String, Int] = Map([])
  prio.set("A", 9)
  let p1 = make_guard()
  ignore(claim_item(p1, "item-a", "P1"))
  let p2 = make_guard()
  ignore(claim_item(p2, "item-a", "P2"))
  let rep = schedule_admit([ga], [p1, p2], 4, prio)
  assert_eq(rep.admitted.length(), 1)
  assert_eq(rep.rejected.length(), 1)
  let col = cg_scene_collision(rep.scene)
  assert_true(!col.0)
  // 被拒候选不得作为持主出现在 scene 中
  let rejected_agent = rep.rejected[0]
  let mut leak = false
  for s in rep.scene {
    for _it, h in s.holders.iter2() {
      if h == rejected_agent {
        leak = true
      }
    }
  }
  assert_true(!leak)
}

///|
/// 端到端（Round 16）：步数预算不足导致全部候选被拒——scene 由在飞 peer 原样构成、
/// 完全无逻辑碰撞，且被拒候选（P1/P2）都不作为持主出现在 scene 中。
test "cg_schedule_scene_rejected_no_leak" {
  let gz = make_guard()
  ignore(claim_item(gz, "item-z", "Z"))
  let ga = make_guard()
  ignore(claim_item(ga, "item-a", "A"))
  let prio : Map[String, Int] = Map([])
  prio.set("Z", 1)
  prio.set("A", 9)
  let p1 = make_guard()
  ignore(claim_item(p1, "item-z", "P1"))
  ignore(claim_item(p1, "item-a", "P1"))
  let p2 = make_guard()
  ignore(claim_item(p2, "item-z", "P2"))
  ignore(claim_item(p2, "item-a", "P2"))
  let rep = schedule_admit([gz, ga], [p1, p2], 1, prio)
  assert_eq(rep.admitted.length(), 0)
  assert_eq(rep.rejected.length(), 2)
  let col = cg_scene_collision(rep.scene)
  assert_true(!col.0)
  // 两个被拒候选都不得泄漏进 scene
  let mut leak = false
  for s in rep.scene {
    for _it, h in s.holders.iter2() {
      if h == "P1" || h == "P2" {
        leak = true
      }
    }
  }
  assert_true(!leak)
}

///|
/// 组成收口（Round 17）：物理层（reserve_scope / lock_acquire）按 scope 字符串裁决，
/// 两 agent 在互不相交 scope 上各自 "reserved"/"active" 时物理层视为不冲突
/// （store_rsv.rsv_action 只看 scope 维度的 owner）。它们若实现同一 BACKLOG 项
/// （item id 相同），物理层看不见这扇逻辑碰撞门。本测试把这条收口钉成不变量：
/// 若把 claimguard 也错误地按「每 agent 一份」拆分（与物理层同病），合并 scene
/// 即出现逻辑碰撞；正确用法是 claimguard 作为全局共享的逻辑互斥闸（单一 item→holder 真源），
/// 开工前先过 claim_item，B 在门禁处即被 Denied，物理盲区被关上。
test "cg_composition_gate_closes_physical_blind_spot" {
  // 危险路径：把 claimguard 错配成「每 agent 一份」——A/B 在 disjoint scope 各自开工同一项
  let ga = make_guard()
  let gb = make_guard()
  ignore(claim_item(ga, "L38", "A")) // A 落子（未在共享门禁后再开工）
  ignore(claim_item(gb, "L38", "B")) // B 同样落子（物理层放行，scope 不同）
  let hazard = cg_scene_collision([ga, gb])
  assert_true(hazard.0) // 物理层盲区真实存在：合并 scene 出现 (L38, A) 与 (L38, B)
  assert_true(hazard.1 == "L38")

  // 正确路径：claimguard 作为全局共享逻辑互斥闸，开工前先过 claim_item
  let g = make_guard()
  match claim_item(g, "L38", "A") {
    Claimed => ()
    _ => abort("cg_composition: A should Claimed")
  }
  match claim_item(g, "L38", "B") {
    Denied => () // B 在门禁处被拒，根本不会去 reserve_scope 开工
    _ => abort("cg_composition: B must be Denied by logical gate")
  }
  let safe = cg_scene_collision([g])
  assert_true(!safe.0)
}

///|
/// 选举层 split-brain 对照（Round 21，对应 reports/…-multilane-lock-mechanism-report.md §10.20）：
/// 物理选举层 `assistant_claim` 在 `taken_over` 时只记 `force_takeover` 违例、**不立即罢免旧主**，
/// 旧主 `is_primary && status=="active"` 行要等 `assistant_sweep` 心跳陈旧才标 dead
/// ⇒ 存在 ≤stale_secs 的「双 active 主助理」窗口，`assistant_active_primary` 静默选最新、不断言唯一。
/// 逻辑闸 claimguard 正好相反：同一 item 的互斥是**即时的、无窗口**——任一时刻 `holder_of(item)`
/// 至多一个 agent，第二者必 Denied，且其宣称后持有者仍是原主，绝不会变成 (A,B) 并存。
/// 本测试把「逻辑层无 split-brain 窗口」钉成回归，作为 §10.20 对照发现的锚点。
test "cg_logical_gate_has_no_primary_split_window" {
  let g = make_guard()
  match claim_item(g, "L38", "A") {
    Claimed => ()
    _ => abort("cg_split: A should Claimed")
  }
  assert_true(holder_of(g, "L38") == Some("A"))
  // B 在同一时刻来抢同一 item —— 物理选举层此瞬间可能已存在「双主」，逻辑层则直接 Denied。
  match claim_item(g, "L38", "B") {
    Denied => ()
    _ =>
      abort(
        "cg_split: B must be Denied (no split-brain window at logical layer)",
      )
  }
  // 关键断言：B 被拒后，持有者仍是 A，绝不变 B、也绝不会 (A,B) 并存。
  assert_true(holder_of(g, "L38") == Some("A"))
}

///|
/// 选举层「心跳复活 defeat 接管」对照（Round 22，对应 reports/…-multilane-lock-mechanism-report.md §10.21）：
/// 物理选举层在 `taken_over` 后**不原子罢免旧主**，且 `assistant_heartbeat` 只刷新 `heartbeat_at`
/// 而保留 `is_primary`/`status` —— 旧主只要持续心跳，sweep 的 `status=="active" && heartbeat_at<cutoff`
/// 永不满足 ⇒ 双 active 主助理**无界共存**（非 R21 初判的「≤stale_secs 有界」）。
/// 逻辑闸 claimguard 无「心跳」概念、互斥是即时的——即便旧主「反复心跳」（这里模拟为旧主反复来抢），
/// 其宣称始终 Denied、持有者恒为现任，绝不出现「复活后推翻现任」或 (A,B) 并存。
/// 本测试把「逻辑层对『旧主复活』免疫」钉成回归，作为 §10.21 对照发现的锚点。
test "cg_logical_gate_immune_to_hb_resurrection" {
  let g = make_guard()
  match claim_item(g, "L38", "A") {
    Claimed => ()
    _ => abort("cg_resurrect: A should Claimed")
  }
  // 模拟「旧主 B 反复心跳来抢同一 item」（选举层里 B 会借此 defeat takeover）
  for i = 0; i < 5; i = i + 1 {
    match claim_item(g, "L38", "B") {
      Denied => () // 每一拍都被拒，绝不被「复活心跳」翻盘
      _ => abort("cg_resurrect: B attempt " + i.to_string() + " must be Denied")
    }
    // 现任 A 也在心跳（刷新，但 claimguard 不需；这里只验证 A 仍是唯一持有者）
    assert_true(holder_of(g, "L38") == Some("A"))
  }
  // 终态：仍只有 A 一个持有者，B 从未染指。
  assert_true(holder_of(g, "L38") == Some("A"))
}

///|
/// 选举层「无自动清扫 ⇒ 罢免需人工」对照（Round 23，对应 reports/…-multilane-lock-mechanism-report.md §10.22）：
/// 物理选举层在 `taken_over` 后**不立即罢免旧主**，且全仓 grep 证明 `assistant_sweep`（唯一标 dead 的路径）
/// **没有任何调用方**——设计文档把它写成「每拍或定时的 reaper」，但代码里它只是个**手动 MCP 工具**，
/// 无 watchdog/cron/pipeline/self-drive 任何自动接线 ⇒ 旧主（哪怕已死）要等**人工调 `assistant_sweep`** 才被罢免，
/// 双 active 主助理行在默认下**无界存在**（R21 的「≤stale_secs 有界」是错的；R22 补「心跳复活」、R23 补「无自动清扫」）。
/// 逻辑闸 claimguard 的释放是**同步、自洽、零外部依赖**的——`release_item` 即刻把持有者置空，
/// 无需任何「清扫拍/心跳/TTL」概念，第二任持有者立即可认领，绝不遗留「待罢免」中间态被旧主借心跳翻盘。
/// 本测试把「逻辑层释放不依赖外部 reaper」钉成回归，作为 §10.22 对照发现的锚点。
test "cg_logical_gate_release_needs_no_external_reaper" {
  let g = make_guard()
  match claim_item(g, "L38", "A") {
    Claimed => ()
    _ => abort("cg_reaper: A should Claimed")
  }
  // 模拟「A 被接管/主动退位」：逻辑层释放是即时权威动作，无中间态
  match release_item(g, "L38", "A") {
    Released => ()
    _ => abort("cg_reaper: A release must be Released")
  }
  // 释放后瞬间：持有者即空，不需要任何「sweep/heartbeat/TTL」来把这个状态落成
  assert_true(holder_of(g, "L38") == None)
  // 第二任 B 可**立即**认领——不像物理层要等人工清扫才让出 is_primary
  match claim_item(g, "L38", "B") {
    Claimed => ()
    _ => abort("cg_reaper: B should Claimed immediately after A release")
  }
  assert_true(holder_of(g, "L38") == Some("B"))
  // 关键对照：逻辑层根本没有「旧主靠心跳复活」或「靠外部 reaper 才失效」的机制，
  // 所以不会出现「A 已释放、却因没人调清扫而仍被当成持有者」这种物理层才有的无界窗口。
  assert_true(holder_of(g, "L38") != Some("A"))
}

///|
/// 物理文件锁「acquire 是检测型、非拒绝型互斥」对照（Round 24，对应 reports/…-multilane-lock-mechanism-report.md §10.23 Finding 1）：
/// 真源 `src/store/store_rsv.mbt::locks_upsert`（内存 L176 / SQLite L1058）**无条件**覆盖写
/// （SQLite `ON CONFLICT(scope) DO UPDATE`，内存 `file_locks.set`），只把「旧锁 active 且他人且未过期」
/// 记一条 `lock_taken_over` 违例；工具 `lock_acquire`（server.mbt L4473-4484）**恒回** `status:"active"`，
/// 没有 denied 分支。`reserve_scope` 则是真互斥（rsv_action「conflict」⇒ 不写、reserved:false）。
/// 本测试用「物理层语义的极简重建」锚定：scope 被 A 持有时，B 仍 acquire 成功（持有者变成 B、记一条违例），
/// 即「检测到了、但没拒绝」；对照 claimguard.claim_item 同场景回 Denied（真互斥）。证明物理锁在**同一 scope**
/// 这种用户字面问的并发场景里，并不阻止第二 agent 拿到锁，只是事后记账。
test "cg_physical_lock_acquire_is_detection_only_not_mutex" {
  // —— 重建物理层 locks_upsert 的「覆盖写 + 仅记违例」语义 ——
  // 返回 (final_holder, violation_logged)
  fn phys_upsert(cur_holder : String?, requester : String) -> (String, Bool) {
    // 旧锁 active 且他人且未过期 → 记违例（这里用 Bool 表示有无违例即可）
    let violation = match cur_holder {
      Some(h) => h != requester
      None => false
    }
    // 无论如何覆盖写：最终持有者 = 请求方（物理层不拒绝）
    (requester, violation)
  }
  // 场景：scope S 当前被 A 持有
  let (final1, v1) = phys_upsert(Some("A"), "B")
  assert_true(final1 == "B") // B 拿到了锁
  assert_true(v1) // 记了「B 接管 A」违例
  // 但 physical 层没有「denied」概念：B 的 acquire 调用返回 success
  // —— 对照：claimguard 同场景必须 Denied（真互斥）
  let g = make_guard()
  match claim_item(g, "S", "A") {
    Claimed => ()
    _ => abort("cg_detect: A should Claimed first")
  }
  match claim_item(g, "S", "B") {
    Denied => ()
    _ => abort("cg_detect: claimguard must Denied B when A holds S")
  }
  assert_true(holder_of(g, "S") == Some("A")) // claimguard 保护住 A 的持有，B 没拿到
}

///|
/// 物理文件锁「读改写非原子 ⇒ 违例漏记」对照（Round 24，对应 §10.23 Finding 2）：
/// `locks_upsert` 先做 `locks_get`（读）再做 `INSERT…ON CONFLICT`（写），两段**没有包进事务**
/// （store_sqlite.mbt L1058-1170 无 BEGIN；只有 WAL + busy_timeout=5000，仅挡「同 row 写写争锁」，
/// 不挡「读写一致性」）。并发交错下：两方各自「读时无锁」，都走插入、互不记违例，一方静默覆盖另一方——
/// 违例账本（唯一安全网）漏记了它本该抓的那次冲突。本测试锚定该交错：两 agent 都「先读到空」再「写」，
/// 结果都成功、且 **零违例**；对照 claimguard 第二认领会 Denied（绝不会两个都 Claimed）。
test "cg_physical_lock_rmw_not_atomic_allows_double_claim" {
  // —— 重建「两方都在各自 read 之后、write 之前插入」的交错 ——
  // 用 (saw_none_before_write, final_holder) 建模：A、B 都先读到 None，然后各自写
  let a_read = None // A 在写之前读到：无锁
  let b_read = None // B 并发地也在写之前读到：无锁（交错发生在 A 写 与 B 读 之间）
  // A 写：读到 None ⇒ 不记违例，插入 A
  let a_violation = match a_read {
    Some(h) => h != "A"
    None => false
  }
  // B 写：B 的 read 发生在 A 写之前 ⇒ 仍读到 None ⇒ 不记违例，ON CONFLICT 覆盖成 B
  let b_violation = match b_read {
    Some(h) => h != "B"
    None => false
  }
  let final_holder = "B" // 后写者覆盖
  // 锚定：两方都「成功」拿到锁，但账本漏记（a/b 违例皆 false）
  assert_true(a_violation == false)
  assert_true(b_violation == false)
  assert_true(final_holder == "B") // 且一方被静默覆盖
  // 对照：claimguard 串行裁决绝不会两个都 Claimed
  let g = make_guard()
  match claim_item(g, "S", "A") {
    Claimed => ()
    _ => abort("cg_rmw: A should Claimed")
  }
  match claim_item(g, "S", "B") {
    Denied => ()
    _ => abort("cg_rmw: B must be Denied, never double-claimed")
  }
  assert_true(holder_of(g, "S") == Some("A"))
}

///|
/// 组成收口（Round 17）：claimguard 的裁决矩阵是 store_rsv.rsv_action 的「逻辑项」同构——
/// None -> Claimed(=物理 reserved) ；同主 -> Renewed(=物理 renewed) ；异主 -> Denied(=物理 conflict)。
/// 物理层缺 TTL 接管口径（那是 lock_acquire/taken_over 的事），逻辑层是纯互斥、无 TTL，
/// 故只比对前三者；本测试把「同构单一真源」钉成回归，防止两处矩阵漂移。
test "cg_verdict_mirrors_rsv_action_matrix" {
  let g = make_guard()
  match decide_claim(None, "A") {
    Claimed => ()
    _ => abort("cg_verdict: None -> Claimed")
  }
  ignore(claim_item(g, "x", "A"))
  match decide_claim(g.holders.get("x"), "A") {
    Renewed => ()
    _ => abort("cg_verdict: self -> Renewed")
  }
  match decide_claim(g.holders.get("x"), "B") {
    Denied => ()
    _ => abort("cg_verdict: other -> Denied")
  }
}

///|
/// 物理锁层「不复用 rsv_action 单一真源 ⇒ 丢弃 deny 裁决」对照（Round 25，对应 reports/…-multilane-lock-mechanism-report.md §10.24）：
/// 源码精读确认——`reserve_scope` 走 `rsv_try_set`（`store_rsv.mbt` L102 / `store_sqlite.mbt` L778），
/// **真正调用** `rsv_action` 并把 `(may_write, action)` 当真源：异主活体 ⇒ `(false,"conflict")` ⇒ **跳过写入**（真互斥）。
/// 而 `lock_acquire` 的工具体（`server.mbt` L4473-4484）直接 `engine.locks_upsert(lock)` 并**恒回** `status:"active"`；
/// `locks_upsert`（内存 L176 / SQLite L1058）**从不调用 `rsv_action`**，只在「旧锁 active 且他人且未过期」时
/// 用一段**手写的 forked 谓词**决定要不要追一条 `lock_taken_over` 违例，然后**无条件覆盖写**——即把 `rsv_action`
/// 本该返回的 `conflict/denied` 裁决**直接丢弃**。这既背离了本报告 §2「三层都收敛到 rsv_action」的论断，
/// 也与 `lock_renew`（server.mbt L4507-4510，持有者非本人即 Err）**自身不一致**。
/// 本测试重建两条路径的「写前决策」并断言：reserve_scope 路径对异主活体返回 may_write=false（拒绝），
/// lock_acquire 路径对手写谓词只算「要不要记违例」、仍无条件把 B 写进持有者（不拒绝），
/// 对照 claimguard.decide_claim 同场景回 Denied 且持有者保持 A（真互斥、单一真源）。
test "cg_physical_lock_bypasses_rsv_action_source_of_truth" {
  // —— 重建 reserve_scope / rsv_try_set 的「真正复用 rsv_action」语义 ——
  // 返回 (may_write, action)；异主活体 ⇒ (false,"conflict") ⇒ 不写
  fn reserve_decision(
    prev_owner : String?,
    requester : String,
  ) -> (Bool, String) {
    match prev_owner {
      None => (true, "reserved")
      Some(o) if o == requester => (true, "renewed")
      // 简化：这里只关心异主活体的 conflict 分支（TTL 接管不在本对照范围）
      Some(_) => (false, "conflict")
    }
  }
  // 场景：scope S 被 A 活体持有，B 来抢
  let (rw, act) = reserve_decision(Some("A"), "B")
  assert_true(act == "conflict")
  assert_true(rw == false) // reserve_scope 路径：拒绝 B，不写

  // —— 重建 lock_acquire / locks_upsert 的「手写 forked 谓词 + 无条件覆盖」语义 ——
  // 手写谓词只回答「要不要记违例」，不回答「要不要拒绝」；覆盖写恒发生
  fn lock_upsert(cur_holder : String?, requester : String) -> (String, Bool) {
    // 手写谓词（对应内存 L178-180 / SQLite L1065-1067 的 status/agent/ttl 三段）
    let logged = match cur_holder {
      Some(h) if h != requester => true // 异主 ⇒ 记 lock_taken_over
      _ => false
    }
    (requester, logged) // 无条件：final holder = requester
  }
  let (final_h, viol) = lock_upsert(Some("A"), "B")
  assert_true(viol) // 记了违例（检测到）
  assert_true(final_h == "B") // 但 B 仍被写进持有者（没拒绝）—— 背离 rsv_action 的 deny

  // —— 对照：claimguard 单一真源，decide_claim 同场景 Denied 且持有者不变 ——
  let g = make_guard()
  match claim_item(g, "S", "A") {
    Claimed => ()
    _ => abort("cg_bypass: A should Claimed first")
  }
  match claim_item(g, "S", "B") {
    Denied => ()
    _ =>
      abort(
        "cg_bypass: claimguard must Denied B when A holds S (single source of truth)",
      )
  }
  assert_true(holder_of(g, "S") == Some("A")) // 真互斥：持有者保持 A
}

///|
/// 物理锁层「acquire 不门禁、renew 却门禁」内部不一致对照（Round 25，对应 §10.24 副发现）：
/// `lock_acquire`（server.mbt L4473-4484）对异主活体**零预检**——直接 upsert 并回 active；
/// `lock_renew`（server.mbt L4507-4510）却**有预检**——`locks_get` 后若 `l.agent != agent` 即 `Err("held by another agent")`。
/// 同一把锁的「获取」与「续期」两套规则不对称：获取允许静默抢锁，续期却拒绝非持有者。
/// 本测试重建这一不对称：同样的「B 对非持有 scope 操作」，acquire 路径返回 success(B 成持有者)，
/// renew 路径返回 Err；对照 claimguard 两操作都统一走 decide_claim（获取 Denied、续期 Renewed 仅本人）。
test "cg_physical_lock_acquire_renew_asymmetric_gate" {
  // acquire 路径：B 对 A 持有的 scope 直接 upsert（无门禁）→ 成功、B 成持有者
  fn acquire(cur : String?, requester : String) -> (String, Bool) {
    // 无预检：final holder = requester，是否记违例由 forked 谓词定（这里只关心「成功」）
    let logged = match cur {
      Some(h) => h != requester
      None => false
    }
    (requester, logged)
  }
  // renew 路径：B 对非本人持有的 scope 直接 Err（门禁）
  fn renew(cur : String?, requester : String) -> Result[String, Unit] {
    match cur {
      Some(h) if h != requester => Err(())
      Some(h) => Ok(h) // 本人续期
      None => Err(()) // 无锁
    }
  }
  let (acq_h, _) = acquire(Some("A"), "B")
  assert_true(acq_h == "B") // acquire 不门禁：B 拿到
  match renew(Some("A"), "B") {
    Err(_) => () // renew 门禁：B 被拒
    Ok(_) => abort("cg_asym: renew must Err for non-holder B")
  }
  // 对照：claimguard 统一门禁——B 获取 Denied、A 续期 Renewed
  let g = make_guard()
  match claim_item(g, "S", "A") {
    Claimed => ()
    _ => abort("cg_asym: A should Claimed")
  }
  match claim_item(g, "S", "B") {
    Denied => ()
    _ => abort("cg_asym: B acquire must Denied")
  }
  match decide_claim(g.holders.get("S"), "A") {
    Renewed => ()
    _ => abort("cg_asym: A renew must Renewed")
  }
  assert_true(holder_of(g, "S") == Some("A"))
}
