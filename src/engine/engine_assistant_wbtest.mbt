/// engine_assistant_wbtest.mbt —— BUG-431 的成对锁。
///
/// **病灶**：`assistant_claim` 的「接管留痕」取决于 `assistant_sweep` **是否恰好先跑过** ——
///   ① `assistant_active_primary` **只认 `status == "active"`**
///   ② `assistant_sweep` 把心跳陈旧的主助理标 `dead`
///   ③ `assistant_claim_action(prev=None)` 判 **`elected`**（`prev_agent=""`）
///   ④ `server.mbt` 的留痕分支**只在 `action == "taken_over"` 时记** `force_takeover`
/// ⇒ 同一个业务事件（B 心跳陈旧、A 接管）会因「sweep 是否恰好先跑过」产出两种账本结果。
///
/// **修法**：新增 `assistant_last_primary()`（`is_primary` 且 `status != "resigned"`，
/// 排序键与 `active_primary` 一致），`claim` 改用它当 `prev` ⇒ 两种时序都判 `taken_over`。

///|
/// 造一条助理登记（`registered_at` 固定，方便排序断言）。
fn mk_asst(
  agent : String,
  is_primary : Bool,
  status : String,
  heartbeat_at : String,
) -> @store.AssistantReg {
  @store.AssistantReg::new(
    agent~,
    mode="all",
    is_primary~,
    registered_at="2026-10-26T08:00:00Z",
    heartbeat_at~,
    status~,
  )
}

///|
/// 锁 1：`dead` 的 primary —— `active_primary` 看不到（病灶），`last_primary` 看得到（修法）。
///
/// 这是 BUG-431 的**机制格**：证明「sweep 标 dead 之后，仍有一个查询面能看到它」。
test "bug431_last_primary_sees_dead" {
  let e = FistEngine::new()
  e.assistant_upsert(mk_asst("B", true, "dead", "2026-10-26T07:00:00Z"))
  // 前提：active_primary 确实看不到它（否则本格的修法前提不成立）
  match e.assistant_active_primary() {
    Some(_) => fail("前提不成立：active_primary 不该看到 dead 的 primary")
    None => ()
  }
  // 修法：last_primary 必须看得到
  match e.assistant_last_primary() {
    None => fail("BUG-431：last_primary 应看到 dead 的 primary（否则 claim 会误判 elected）")
    Some(_) => ()
  }
}

///|
/// 锁 2：**端到端** —— dead + 陈旧心跳 ⇒ `claim_action` 判 `taken_over` 且 `prev_agent` 点名 B。
///
/// 这是 BUG-431 的**修复点本尊**：`prev` 由 `last_primary()` 提供（而不是 `active_primary()` 的 `None`）
/// ⇒ `assistant_claim_action` 走 `Some(r) if r.heartbeat_at < cutoff => taken_over` 这一支
/// ⇒ `server.mbt` 的留痕分支才会记 `force_takeover` 违例。
/// **若把接线退回 `active_primary()`，本格必红**（`action` 会变成 `elected`、`prev_agent` 变 `""`）。
test "bug431_dead_primary_claim_is_taken_over_not_elected" {
  let e = FistEngine::new()
  e.assistant_upsert(mk_asst("B", true, "dead", "2026-10-26T07:00:00Z"))
  let (ok, action, prev_agent) = @store.assistant_claim_action(
    e.assistant_last_primary(),
    "A",
    "2026-10-26T10:00:00Z", // now
    "2026-10-26T09:00:00Z", // cutoff（B 的心跳 07:00 < 09:00 ⇒ 陈旧）
  )
  assert_true(ok)
  assert_eq(action, "taken_over")
  assert_eq(prev_agent, "B")
}

///|
/// 锁 3：`resigned` 的 primary **不参与** `last_primary` —— 主动退位后应重新选举（旧语义）。
///
/// 防「修过头」：把 `dead` 也认进来，但不能顺手把 `resigned` 也认了 ——
/// 否则退位者会一直挡着新选举，且会被误记 `force_takeover` 违例。
test "bug431_last_primary_excludes_resigned" {
  let e = FistEngine::new()
  e.assistant_upsert(mk_asst("R", true, "resigned", "2026-10-26T07:00:00Z"))
  match e.assistant_last_primary() {
    None => ()
    Some(_) => fail("BUG-431：resigned 不应参与 last_primary（退位后应重新选举）")
  }
}

///|
/// 锁 4：`active` 的新鲜 primary **仍照旧** —— `last_primary` 与 `active_primary` 同结论。
///
/// 防「修法把正常路径也改了」：有人持有且心跳新鲜 ⇒ claim 应判 `conflict`（不许抢）。
test "bug431_fresh_active_primary_still_conflict" {
  let e = FistEngine::new()
  e.assistant_upsert(mk_asst("B", true, "active", "2026-10-26T09:59:00Z"))
  // 两个查询面都该看到它
  match e.assistant_active_primary() {
    None => fail("前提不成立：新鲜的 active primary 应能被 active_primary 看到")
    Some(_) => ()
  }
  let (ok, action, prev_agent) = @store.assistant_claim_action(
    e.assistant_last_primary(),
    "A",
    "2026-10-26T10:00:00Z",
    "2026-10-26T09:00:00Z",
  )
  assert_false(ok)
  assert_eq(action, "conflict")
  assert_eq(prev_agent, "B")
}