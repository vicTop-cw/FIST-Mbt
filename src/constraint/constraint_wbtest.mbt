/// constraint_wbtest.mbt —— 布尔约束引擎白盒测试（BACKLOG L38）
///
/// 全程确定性：时间戳用零填充串，字典型比较 == 数值比较。
/// 重点覆盖「多 agent 文件锁」的四种裁决（reserved/renewed/taken_over/conflict），
/// 证明约束层与 `src/store/store_rsv.mbt::rsv_action` 语义一致。
/// 白盒（与源同编译单元）才能构造内部 struct 并直接调用非 pub 内部函数。

///|
/// 空闲作用域 -> reserved，可写。
test "rsv_verdict_reserved" {
  let (may, verdict) = rsv_conflict_verdict(None, "A", "2026-01-01T00:00:05")
  assert_true(may)
  assert_eq(verdict, "reserved")
}

///|
/// 本人续订（owner==agent）-> renewed，可写，且排在过期判定之前。
test "rsv_verdict_renewed" {
  let (may, verdict) = rsv_conflict_verdict(
    Some(("A", "2026-01-01T00:00:99", "")),
    "A",
    "2026-01-01T00:00:05",
  )
  assert_true(may)
  assert_eq(verdict, "renewed")
}

///|
/// 旧主已过期（ttl < now）-> taken_over，可写（接管）。
test "rsv_verdict_taken_over" {
  let (may, verdict) = rsv_conflict_verdict(
    Some(("A", "2026-01-01T00:00:00", "")),
    "B",
    "2026-01-01T00:00:05",
  )
  assert_true(may)
  assert_eq(verdict, "taken_over")
}

///|
/// 他人 live 持有（ttl >= now 且 owner != agent）-> conflict，不可写。
test "rsv_verdict_conflict" {
  let (may, verdict) = rsv_conflict_verdict(
    Some(("A", "2026-01-01T00:00:99", "")),
    "B",
    "2026-01-01T00:00:05",
  )
  assert_true(!may)
  assert_eq(verdict, "conflict")
}

///|
/// **R17 委托格（实现路径格，判例-29）**：`rsv_conflict_verdict` 必须与
/// `@store.rsv_action` **逐输入恒等**。
///
/// 为什么需要这一格：上面几条只断言**行为**（reserved/renewed/taken_over/conflict），
/// 它们**在手工镜像时代就已存在且全绿**。也就是说 ——
/// 「把这四条锁留在这里、把实现改回手工抄本」，它们**照样全绿**
/// （判例-29「机制格 ≠ 实现路径格」：测了行为，不等于测了「它真的在委托」）。
///
/// 本格把两侧**同一批输入**各喂一遍，断言返回值逐一相等：
///   · 若它改回手工抄本、且抄本与 `rsv_action` 一致 ⇒ 本格仍绿（**这是对的**：
///     此时行为确实等价，漂移风险由「两侧一致」兜住）；
///   · 若抄本与 `rsv_action` 漂移（任一方向）⇒ **本格红**。
/// 即本格锁的是**「行为恒等」这个事实**，而不是「实现里有没有 `@store.` 这个串」
/// （后者会命中注释、造成判例-30 自指假绿）。
test "rsv_verdict_delegates_to_rsv_action" {
  // 覆盖 rsv_action 四个分支 + ttl==now 边界 + 空 agent
  let cases : Array[((String, String, String)?, String, String)] = [
    (None, "A", "t1"),
    (None, "", "t1"),
    (Some(("A", "t9", "t0")), "A", "t1"),
    (Some(("A", "t1", "t0")), "A", "t1"),
    (Some(("B", "t0", "t0")), "A", "t1"),
    (Some(("B", "t1", "t0")), "A", "t1"),
    (Some(("B", "t9", "t0")), "A", "t1"),
    (Some(("", "t9", "t0")), "A", "t1"),
  ]
  for (prev, agent, now) in cases {
    let mine = rsv_conflict_verdict(prev, agent, now)
    let theirs = @store.rsv_action(prev, agent, now)
    if mine != theirs {
      abort(
        "rsv_conflict_verdict 与 @store.rsv_action 漂移：prev=" +
        (match prev {
          None => "None"
          Some((a, t, _)) => "Some(" + a + "," + t + ")"
        }) +
        " agent=" +
        agent +
        " now=" +
        now +
        " ⇒ constraint=" +
        mine.0.to_string() +
        "/" +
        mine.1 +
        " store=" +
        theirs.0.to_string() +
        "/" +
        theirs.1,
      )
    }
  }
  assert_eq(cases.length(), 8)
}

///|
/// 构造一个世界快照的小工具。
fn mk_world(
  reservations : Array[ActiveReservation],
  agents : Array[String],
) -> WorldState {
  WorldState::{ reservations, agents, }
}

///|
/// 约束3·本人续订：action.agent 与该 scope 的 live holder 相同 -> 放行（renewed）。
test "eval_no_overlap_renewed_allowed" {
  let w = mk_world(
    [
      ActiveReservation::{
        scope: "src/x",
        holder: "A",
        ttl_until: "2026-01-01T00:00:99",
      },
    ],
    ["A", "B"],
  )
  let v = eval_no_overlap(w, PlannedAction::{
    agent: "A",
    scopes: ["src/x"],
    now: "2026-01-01T00:00:05",
  })
  assert_true(v.allowed)
  assert_eq(v.reasons.length(), 0)
}

///|
/// 约束3·接管：他者持有的 scope 已过期 -> 放行（taken_over）。
test "eval_no_overlap_takeover_allowed" {
  let w = mk_world(
    [
      ActiveReservation::{
        scope: "src/x",
        holder: "A",
        ttl_until: "2026-01-01T00:00:00",
      },
    ],
    ["A", "B"],
  )
  let v = eval_no_overlap(w, PlannedAction::{
    agent: "B",
    scopes: ["src/x"],
    now: "2026-01-01T00:00:05",
  })
  assert_true(v.allowed)
}

///|
/// 约束3·冲突：他者 live 持有 -> 拒绝，reason 含 "conflict" 与持有者。
test "eval_no_overlap_conflict" {
  let w = mk_world(
    [
      ActiveReservation::{
        scope: "src/x",
        holder: "A",
        ttl_until: "2026-01-01T00:00:99",
      },
    ],
    ["A", "B"],
  )
  let v = eval_no_overlap(w, PlannedAction::{
    agent: "B",
    scopes: ["src/x"],
    now: "2026-01-01T00:00:05",
  })
  assert_true(!v.allowed)
  assert_true(v.reasons.length() == 1)
  assert_true(v.reasons[0].contains("conflict"))
  assert_true(v.reasons[0].contains("'A'"))
}

///|
/// 约束3·多作用域：一个冲突即整体拒绝。
test "eval_no_overlap_multi_scope" {
  let w = mk_world(
    [
      ActiveReservation::{
        scope: "src/x",
        holder: "A",
        ttl_until: "2026-01-01T00:00:99",
      },
      ActiveReservation::{
        scope: "src/y",
        holder: "B",
        ttl_until: "2026-01-01T00:00:99",
      },
    ],
    ["A", "B", "C"],
  )
  let v = eval_no_overlap(w, PlannedAction::{
    agent: "C",
    scopes: ["src/x", "src/y"],
    now: "2026-01-01T00:00:05",
  })
  assert_true(!v.allowed)
  assert_eq(v.reasons.length(), 2)
}

///|
/// 约束3·同一 action 重复申报同一 scope：只对第一个实例裁决，不重复报冲突。
test "eval_no_overlap_duplicate_scope_dedup" {
  let w = mk_world(
    [
      ActiveReservation::{
        scope: "src/x",
        holder: "A",
        ttl_until: "2026-01-01T00:00:99",
      },
    ],
    ["A", "B"],
  )
  let v = eval_no_overlap(w, PlannedAction::{
    agent: "B",
    scopes: ["src/x", "src/x", "src/x"],
    now: "2026-01-01T00:00:05",
  })
  assert_true(!v.allowed)
  assert_eq(v.reasons.length(), 1)
}

///|
/// 约束1·未知执行者 -> 拒绝。
test "eval_known_agent_unknown" {
  let w = mk_world([], ["A"])
  let v = eval_known_agent(w, PlannedAction::{
    agent: "Z",
    scopes: [],
    now: "x",
  })
  assert_true(!v.allowed)
  assert_true(v.reasons[0].contains("unknown agent"))
}

///|
/// 约束1·已登记执行者 -> 放行。
test "eval_known_agent_known" {
  let w = mk_world([], ["A"])
  let v = eval_known_agent(w, PlannedAction::{
    agent: "A",
    scopes: [],
    now: "x",
  })
  assert_true(v.allowed)
}

///|
/// 约束2·同一动作重复申报同一作用域 -> 拒绝。
test "eval_disjoint_scopes_dup" {
  let w = mk_world([], ["A"])
  let v = eval_disjoint_scopes(w, PlannedAction::{
    agent: "A",
    scopes: ["src/x", "src/x"],
    now: "x",
  })
  assert_true(!v.allowed)
  assert_true(v.reasons[0].contains("twice"))
}

///|
/// 默认组合·全绿：已登记 + 作用域不相交 + 无冲突 -> 放行。
test "eval_default_pass" {
  let w = mk_world(
    [
      ActiveReservation::{
        scope: "src/y",
        holder: "B",
        ttl_until: "2026-01-01T00:00:99",
      },
    ],
    ["A", "B"],
  )
  let v = eval_default(w, PlannedAction::{
    agent: "A",
    scopes: ["src/x"],
    now: "2026-01-01T00:00:05",
  })
  assert_true(v.allowed)
}

///|
/// 默认组合·未知执行者优先于锁冲突被汇总拒绝。
test "eval_default_unknown_agent" {
  let w = mk_world([], ["A"])
  let v = eval_default(w, PlannedAction::{
    agent: "Z",
    scopes: ["src/x"],
    now: "2026-01-01T00:00:05",
  })
  assert_true(!v.allowed)
  assert_true(v.reasons[0].contains("unknown agent"))
}
