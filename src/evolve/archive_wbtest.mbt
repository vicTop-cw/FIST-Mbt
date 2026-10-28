/// archive_wbtest.mbt —— BUG-455 第三批：`Archive` 的 6 个方法此前**零测试**。
///
/// **为什么这是真零覆盖**：`src/evolve/` 有 4 个测试文件，但 `evolve_wbtest.mbt` 的 14 格
/// 测的全是 **curriculum**（`next_level` / `standard_curriculum` / `can_graduate` /
/// `curriculum_progress` / `select_mutation` / `mutation_prompt` / `is_distillable`）——
/// **`Archive::*` 一次都没出现**（实测 `Archive::best`/`all`/`len`/`is_empty`/`get`/`sample_parent`
/// 在全部 evolve 测试文件里各 0 次）。
///
/// 而 `Archive` 是 **DGM 演化的核心数据结构** —— `evolve_snapshot` / `evolve_sample` /
/// `evolve_submit` / `evolve_asset_register` / `evolve_asset_register` / `task_challenge` 的实质
/// 全建立在它上面。
///
/// 覆盖：`new`/`len`/`is_empty` · `add`+`get`+`all` · **`add` 查重（不重复累加父 children）** ·
/// **`add` 父 children 累加** · `best`（空/非空/最高分） · `sample_parent`（空/轮盘端点/权重单调）。

///|
/// 造一个产物（`parts` 用空表，测试不需要）。
fn arch_wb_art(id : String, parent : String?, score : Double) -> Artifact {
  Artifact::create(
    id~,
    parent_id=parent,
    goal="goal-" + id,
    note="note-" + id,
    code="",
    score~,
    parts=Map([]),
    created_at="2026-01-01T00:00:00Z",
  )
}

///|
/// 锁 1：空库的 `len` / `is_empty` / `get` / `all` / `best` / `sample_parent` 全部走空分支。
///
/// 这一格钉住「空库不 panic」——`best` 与 `sample_parent` 都有 `if is_empty return None`，
/// 若有人删掉那个守卫，`all[0]` 会索引越界（不是返回 None）。
test "arch455_empty_archive_all_branches" {
  let a = Archive::new("mem://empty")
  assert_eq(a.len(), 0)
  assert_true(a.is_empty())
  assert_eq(a.all().length(), 0)
  assert_true(a.get("nope") is None)
  assert_true(a.best() is None)
  // sample_parent 空库 ⇒ None（即使 rand 恒 0 也不该 panic）
  assert_true(a.sample_parent(rand=fn() { 0.0 }) is None)
}

///|
/// 锁 2：`add` 后 `len`/`is_empty`/`get`/`all` 一致，且 `get` 能按 id 取回**同一个**产物。
test "arch455_add_then_get_all" {
  let a = Archive::new("mem://add")
  a.add(arch_wb_art("A", None, 0.5))
  a.add(arch_wb_art("B", Some("A"), 0.7))
  assert_eq(a.len(), 2)
  assert_false(a.is_empty())
  assert_eq(a.all().length(), 2)
  match a.get("B") {
    None => fail("get 取不到刚加入的 B")
    Some(b) => {
      assert_eq(b.id, "B")
      assert_eq(b.score, 0.7)
    }
  }
}

///|
/// 锁 3：**重复 `add` 同一 id 不得重复累加父节点 children**。
///
/// 这是 `Archive::add` 里那段 `let is_new = self.items.get(a.id) is None` 的存在理由
/// （注释原文：「重复添加同一 id（覆盖已有记录）时不再重复累加父节点 children，避免计数虚高」）。
/// 若删掉 `is_new` 守卫，父节点 children 会随重复 add 线性虚高。
test "arch455_add_same_id_does_not_inflate_parent_children" {
  let a = Archive::new("mem://dup")
  a.add(arch_wb_art("P", None, 0.5))
  a.add(arch_wb_art("C1", Some("P"), 0.6))
  match a.get("P") {
    None => fail("P 不在了")
    Some(p) => assert_eq(p.children, 1)
  }
  // 同一 id 再加两次（内容不同，模拟"更新既有记录"）
  a.add(arch_wb_art("C1", Some("P"), 0.9))
  a.add(arch_wb_art("C1", Some("P"), 0.95))
  match a.get("P") {
    None => fail("P 不在了")
    Some(p) => assert_eq(p.children, 1) // ★ 仍是 1，不是 3
  }
  // 但 C1 本身被更新成最后一次的 score
  match a.get("C1") {
    None => fail("C1 不在了")
    Some(c) => assert_eq(c.score, 0.95)
  }
}

///|
/// 锁 4：**新增**子代（不同 id）时父节点 children 必须 **+1**。
///
/// 与锁 3 成对：锁 3 防"多累加"，锁 4 防"少累加/不累加"。
/// 只测锁 3 的话，把 `p.children + 1` 改成 `p.children` 仍然绿。
test "arch455_add_new_child_increments_parent_children" {
  let a = Archive::new("mem://children")
  a.add(arch_wb_art("P", None, 0.5))
  assert_eq(a.get("P").unwrap().children, 0)
  a.add(arch_wb_art("C1", Some("P"), 0.6))
  a.add(arch_wb_art("C2", Some("P"), 0.65))
  a.add(arch_wb_art("C3", Some("P"), 0.7))
  assert_eq(a.get("P").unwrap().children, 3)
  // 父不存在的子代：不该崩，也不该凭空造父
  a.add(arch_wb_art("C4", Some("NO_SUCH_PARENT"), 0.4))
  assert_eq(a.len(), 5)
  assert_true(a.get("NO_SUCH_PARENT") is None)
}

///|
/// 锁 5：`best` 返回**最高分**（不是第一个/最后一个）。
///
/// 造三个产物，最高分在**中间**（B=0.9），这样「取第一个」（A）与「取最后一个」（C）都会红。
test "arch455_best_returns_highest_score" {
  let a = Archive::new("mem://best")
  a.add(arch_wb_art("A", None, 0.2))
  a.add(arch_wb_art("B", None, 0.9))
  a.add(arch_wb_art("C", None, 0.5))
  match a.best() {
    None => fail("best 不该是 None")
    Some(b) => assert_eq(b.id, "B")
  }
}

///|
/// 锁 6：`sample_parent` 的**轮盘端点**行为。
///
/// `rand` 是注入的 ⇒ 可以精确测：
/// - `rand()=0.0` ⇒ 命中**第一个**（注释原文：「用 `r < 0`（不含等号）保证 rand 返回 0
///   （贴在左端）时不会错误命中第一个元素之前」）
/// - `rand()` 接近 1.0 ⇒ 命中**最后一个**（r 走完整个 total 仍未 <0 ⇒ 兜底返最后一个）
/// 再断言「权重单调」：分数高且 children 少的产物，被选中的概率排序正确。
/// 用确定性 rand 序列统计 1000 次，**不靠随机**（判例-31：不可复现的锁不可信）。
test "arch455_sample_parent_endpoints_and_weight_order" {
  let a = Archive::new("mem://sample")
  a.add(arch_wb_art("LOW", None, 0.01)) // 低分
  a.add(arch_wb_art("HIGH", None, 10.0)) // 高分
  // 端点：rand=0 ⇒ 第一个（all() 的顺序由 Map 决定，不可依赖——改为断言"必是其一")
  match a.sample_parent(rand=fn() { 0.0 }) {
    None => fail("非空库不该 None")
    Some(x) => assert_true(x.id == "LOW" || x.id == "HIGH")
  }
  // 端点：rand→0.999999 ⇒ 必中（走完轮盘兜底）
  match a.sample_parent(rand=fn() { 0.999999 }) {
    None => fail("非空库不该 None")
    Some(x) => assert_true(x.id == "LOW" || x.id == "HIGH")
  }
  // 权重单调：用确定性序列扫 1000 次，统计各 id 命中数
  let mut hits_low = 0
  let mut hits_high = 0
  for i = 0; i < 1000; i = i + 1 {
    let r = i.to_double() / 1000.0
    match a.sample_parent(rand=fn() { r }) {
      None => fail("非空库不该 None")
      Some(x) =>
        if x.id == "LOW" {
          hits_low = hits_low + 1
        } else {
          hits_high = hits_high + 1
        }
    }
  }
  // HIGH 的权重远大于 LOW（10/(10+0.4)≈0.96 vs 0.01/(0.01+0.4)≈0.024）⇒ 命中数必须更多
  assert_true(hits_high > hits_low)
}
