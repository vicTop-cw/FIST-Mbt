/// constraint_store_equiv_test.mbt —— BUG-435 的交叉一致性锁。
///
/// **形态**：`src/constraint/constraint.mbt` 的 `rsv_conflict_verdict` 是
/// `src/store/store_rsv.mbt` 的 `rsv_action` 的**手工逐字重抄**。
///
/// **为什么不直接把 constraint 改成 `import store`**：`constraint` 是**零依赖包**
/// （`moon.pkg` 只有 `supported_targets`），它的注释写明这是**刻意的政策侧镜像** ——
/// 「让约束层不耦合到 store 层」。硬加依赖会破坏那个架构意图。
///
/// **为什么又必须锁**：「两副本会各自漂移」是真实风险，而两个包互不依赖 ⇒
/// **没有任何现有测试能同时看见两者** ⇒ 任一边改了规则，另一边静默过期。
///
/// **解法**：本包**只做这件事** —— 同时依赖 store 与 constraint，交叉断言两者
/// 对同一组输入**逐字同结论**。生产面零依赖保持不变，漂移被一格锁死。

///|
/// 四个分支 × 边界，覆盖 `rsv_action` 注释里点明的全部语义（含「同持有者排在过期之前」）。
fn _cases() -> Array[((String, String, String)?, String, String)] {
  [
    // ① None ⇒ reserved
    (None, "A", "2026-01-01T00:00:05"),
    // ② 本人 + 未过期 ⇒ renewed
    (Some(("A", "2026-01-01T00:01:00", "2026-01-01T00:00:00")), "A", "2026-01-01T00:00:05"),
    // ③ 本人 + **已过期** ⇒ renewed（不是 taken_over —— 同持有者优先，注释点名的坑）
    (Some(("A", "2026-01-01T00:00:01", "2026-01-01T00:00:00")), "A", "2026-01-01T00:00:05"),
    // ④ 他人 + 已过期 ⇒ taken_over
    (Some(("B", "2026-01-01T00:00:01", "2026-01-01T00:00:00")), "A", "2026-01-01T00:00:05"),
    // ⑤ 他人 + 未过期 ⇒ conflict
    (Some(("B", "2026-01-01T00:01:00", "2026-01-01T00:00:00")), "A", "2026-01-01T00:00:05"),
    // ⑥ ttl == now ⇒ conflict（严格 `<` 而非 `<=`）
    (Some(("B", "2026-01-01T00:00:05", "2026-01-01T00:00:00")), "A", "2026-01-01T00:00:05"),
  ]
}

///|
/// 锁（成对）：constraint 的镜像与 store 的真源对**每一组输入**给出**逐字相同**的 `(may, verdict)`。
///
/// 变异方向：
/// - 改 `rsv_action`（真源）⇒ 本格红（镜像过期）
/// - 改 `rsv_conflict_verdict`（镜像）⇒ 本格红（与真源分叉）
/// - 任一侧把「同持有者优先」那支顺序调换 ⇒ 第 ③ 组红
test "bug435_constraint_mirror_matches_store_rsv_action" {
  for c in _cases() {
    let (prev, agent, now) = c
    let from_store = @store.rsv_action(prev, agent, now)
    let from_mirror = @constraint.rsv_conflict_verdict(prev, agent, now)
    if from_store != from_mirror {
      fail(
        "BUG-435 镜像漂移：prev=" +
        (match prev {
          None => "None"
          Some(p) => "Some(" + p.0 + ") ttl=" + p.1
        }) +
        " agent=" +
        agent +
        " now=" +
        now +
        " ⇒ store=" +
        from_store.1 +
        " vs constraint=" +
        from_mirror.1,
      )
    }
  }
}

///|
/// 锁（单侧）：四个动词标签在两侧**都在**（防「两边一起改名」这种同时漂移）。
///
/// 为什么需要它：上面那格只比对「两边相同」，若有人把**两边**都改成 `"acquired"`，
/// 上格仍绿 —— 但那时 store 的 SQL 侧 `ON CONFLICT ... WHERE` 与账本口径已经不一致了。
/// 本格把四个**规范动词**钉死（`reserved` / `renewed` / `taken_over` / `conflict`）。
test "bug435_canonical_verdicts_unchanged_on_both_sides" {
  let expected : Array[String] = ["reserved", "renewed", "taken_over", "conflict"]
  let got_store : Array[String] = []
  let got_mirror : Array[String] = []
  for c in _cases() {
    let (prev, agent, now) = c
    got_store.push(@store.rsv_action(prev, agent, now).1)
    got_mirror.push(@constraint.rsv_conflict_verdict(prev, agent, now).1)
  }
  // 六组用例里出现过的动词集合必须恰好是这四个（顺序无关，集合相等）
  for want in expected {
    if !got_store.contains(want) {
      fail("BUG-435：store 侧不再产出规范动词 " + want)
    }
    if !got_mirror.contains(want) {
      fail("BUG-435：constraint 镜像不再产出规范动词 " + want)
    }
  }
  // 且双方不得产出任何**超出**这四者的动词
  for got in got_store {
    if !expected.contains(got) {
      fail("BUG-435：store 侧出现非规范动词 " + got)
    }
  }
  for got in got_mirror {
    if !expected.contains(got) {
      fail("BUG-435：constraint 镜像出现非规范动词 " + got)
    }
  }
}
