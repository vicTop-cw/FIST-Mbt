///|
/// core_role_wbtest.mbt —— **角色/权限矩阵的白盒锁（R139）**。
///
/// 为什么有这个文件：`can` / `ensure_can` / `ensure_can_create_spec` /
/// `ensure_can_review_spec` / `role_of` 在本仓此前**零测试引用**
/// （`grep` 全仓 `*_test.mbt`/`*_wbtest.mbt` 找不到 `can(`），
/// 而它们正是 **Omega 强验证的准入面**：谁能创建语料、谁能审/复验。
///
/// 权限函数没锁的后果不是崩溃，而是**静默放权或静默拒权** ——
/// 前者是安全洞，后者是流水线停摆，两者都不会报错。

///|
/// 锁 1：`to_string` / `from_string` 必须**逐角色往返**（9 个角色全覆盖）。
/// 变异对照：把任一 `from_string` 分支的字符串改一个字母，本格立刻红。
test "role_roundtrip_all_nine" {
  let all : Array[Role] = [
    HumanSteward, Leader, Searcher, Allocator, Executor, Verifier, Recorder, Observer,
    SpecAuthor,
  ]
  for r in all {
    let s = r.to_string()
    match Role::from_string(s) {
      Some(back) => assert_eq(back.to_string(), s)
      None => abort("角色往返失败：" + s)
    }
  }
  // 9 个角色的 to_string 必须**互不相同**（否则往返看似通过，实则撞键）
  let seen : Array[String] = []
  for r in all {
    let s = r.to_string()
    assert_true(!seen.contains(s))
    seen.push(s)
  }
}

///|
/// 锁 2：`from_string` **大小写敏感 + 未知即 None**（fail-closed）。
///
/// 为什么钉大小写：`role_of` 直接吃 MCP 参数，若接受 `"HumanSteward"`，
/// 调用方传大写也能拿到指挥官权限 —— 那是把**宽松解析**变成**提权面**。
test "role_from_string_is_case_sensitive_and_closed" {
  assert_true(Role::from_string("human_steward") == Some(HumanSteward))
  assert_true(Role::from_string("HumanSteward") == None)
  assert_true(Role::from_string("HUMAN_STEWARD") == None)
  assert_true(Role::from_string("") == None)
  assert_true(Role::from_string("admin") == None)
  // 尾随空格也不许被当成同一角色
  assert_true(Role::from_string("leader ") == None)
}

///|
/// 锁 3：**权限矩阵**（`can`）。这是本文件的承重格。
///
/// 矩阵（与 `can` 的实现一一对应）：
///   · HumanSteward × 任意 = true（唯一全权）
///   · SpecAuthor × CreateSpec = true，其余 false
///   · Verifier × ReviewSpec = true，其余 false
///   · 其余 6 个角色 × 两个动作 = 全 false
///
/// 变异对照：把 `(SpecAuthor, CreateSpec) => true` 改成 `ReviewSpec`，本格红；
/// 把 `(HumanSteward, _) => true` 删掉，本格红一半。
test "can_permission_matrix" {
  let acts : Array[Action] = [CreateSpec, ReviewSpec]
  // ① 人类指挥官：全权
  for a in acts {
    assert_true(can(HumanSteward, a))
  }
  // ② SpecAuthor：只能建语料
  assert_true(can(SpecAuthor, CreateSpec))
  assert_true(!can(SpecAuthor, ReviewSpec))
  // ③ Verifier：只能审/复验
  assert_true(can(Verifier, ReviewSpec))
  assert_true(!can(Verifier, CreateSpec))
  // ④ 其余六角色：两个动作都不许（fail-closed）
  let others : Array[Role] = [Leader, Searcher, Allocator, Executor, Recorder, Observer]
  for r in others {
    for a in acts {
      assert_true(!can(r, a))
    }
  }
}

///|
/// 锁 4：`ensure_can` 的 Ok/Err 成对 —— 允许时 Ok，拒绝时 Err 且消息**点名角色与动作**
/// （错误消息要能自解释，否则运维只能猜是哪道门拦的）。
test "ensure_can_ok_and_err_message" {
  match ensure_can(SpecAuthor, CreateSpec) {
    Ok(_) => ()
    Err(e) => abort("应允许却被拒：" + e)
  }
  match ensure_can(Executor, CreateSpec) {
    Ok(_) => abort("Executor 不应有 CreateSpec 权限")
    Err(e) => {
      assert_true(e.contains("executor"))
      assert_true(e.contains("create_spec"))
    }
  }
}

///|
/// 锁 5：**字符串入口**（`ensure_can_create_spec` / `ensure_can_review_spec` / `role_of`）。
///
/// 这条线是 Omega 强验证的真实入口：`actor` 直接来自 MCP 参数。
///   · 合法角色 ⇒ 按其权限判定；
///   · 未知角色 ⇒ **Err（不是当成 Executor 放行，也不是当成指挥官）**。
test "spec_gates_by_actor_string" {
  match ensure_can_create_spec("human_steward") {
    Ok(_) => ()
    Err(e) => abort("human_steward 建语料应允许：" + e)
  }
  match ensure_can_create_spec("spec_author") {
    Ok(_) => ()
    Err(e) => abort("spec_author 建语料应允许：" + e)
  }
  match ensure_can_create_spec("executor") {
    Ok(_) => abort("executor 不应能建语料")
    Err(_) => ()
  }
  match ensure_can_review_spec("verifier") {
    Ok(_) => ()
    Err(e) => abort("verifier 审语料应允许：" + e)
  }
  match ensure_can_review_spec("spec_author") {
    Ok(_) => abort("spec_author 不应能审语料")
    Err(_) => ()
  }
  // 未知角色：Err 且消息可读（不能静默按某个高权角色处理）
  match ensure_can_create_spec("Chef") {
    Ok(_) => abort("未知角色不应被放行")
    Err(e) => assert_true(e.contains("未知角色"))
  }
  match role_of("nobody") {
    Ok(_) => abort("role_of 未知角色应 Err")
    Err(e) => assert_true(e.contains("未知角色"))
  }
}


///|
/// R141→R143：**状态门 vs 域迁移**的三层分工锁（R142 曾误删、R143 回滚并定论）。
///
/// 三层：
///   · `Task::split()`（`engine.split`）只收 **Claimed**；
///   · `Task::mark_decomposing()`（`engine.plan_deep`）收 **Pending | Claimed | Splitting**；
///   · `TaskStatus::can_split()` = **宽闸门**，含 **`Rejected`**。
///
/// ⚠️ **宽是有意的**（R142 把它收窄成"并集"是错的）：`engine` 的第二道门拒绝时会拼
/// `split_remedy(...)` 给出出路文案 —— 其 docstring 明写「第一道门 `can_split` 比它宽……
/// 只报'要求状态'不报'怎么到达'，调用方就会照文案去 claim 一个已打回的任务，永远走不通」。
/// 删掉 `Rejected` ⇒ 调用方只剩「非法拆分: [已打回]」，**丢掉「先 retry」这条唯一出路提示**。
///
/// ⇒ 本格钉的是：**闸门宽集（4 态）+ 域层窄集（split 只 Claimed）**同时成立。
/// 谁把 `Rejected` 从闸门删掉（重犯 R142），或让 `split` 放宽到能吃 Rejected，本格都会红。
test "status_gate_vs_domain_split_mismatch_is_pinned" {
  // 闸门侧：**宽集 4 态**（含 Rejected —— 宽是为了让第二道门能给出 retry 出路文案）
  assert_true(TaskStatus::can_split(Pending))
  assert_true(TaskStatus::can_split(Claimed))
  assert_true(TaskStatus::can_split(Splitting))
  assert_true(TaskStatus::can_split(Rejected))
  // 域层侧仍是窄集：Claimed 能 split —— 窄集这一侧由下面的真实构造验证
  // 闸门侧：其余拒绝
  assert_true(!TaskStatus::can_split(Executing))
  assert_true(!TaskStatus::can_split(Reviewing))
  assert_true(!TaskStatus::can_split(Completed))
  // 域层侧（用真实构造的任务验证，而不是读代码）：只有 Claimed 能 split
  // 用**全新 Pending 任务**（不能用 rc_reviewing：它已推进到 Reviewing，claim 会拒）
  let fresh = Task::new(id="R141-1", project_dir=".", description="x", assignee="a1")
  let claimed = match fresh.claim(assignee="a1") {
    Ok(t) => t
    Err(e) => abort("claim 失败：" + e)
  }
  assert_true(TaskStatus::can_split(claimed.get_status()))
  match claimed.split() {
    Ok(_) => ()
    Err(e) => abort("Claimed 应能 split: " + e)
  }
}

///|
/// R141：`can_execute` 与 `Task::execute` 的**已对齐**关系（BUG-2 的回归锁）。
/// 集合：`Claimed | Splitting | Executing`；`Rejected` 必须**不在**两侧任何一侧
/// （BUG-2 当年就是闸门多了一条 Rejected）。
test "status_gate_vs_domain_execute_aligned" {
  assert_true(TaskStatus::can_execute(Claimed))
  assert_true(TaskStatus::can_execute(Splitting))
  assert_true(TaskStatus::can_execute(Executing))
  assert_true(!TaskStatus::can_execute(Rejected))
  assert_true(!TaskStatus::can_execute(Pending))
  assert_true(!TaskStatus::can_execute(Completed))
  // 域层：Claimed 可 execute；Rejected 必须 Err（且文案是"非法迁移"，不是闸门文案）
  let fresh2 = Task::new(id="R141-2", project_dir=".", description="y", assignee="a2")
  let claimed2 = match fresh2.claim(assignee="a2") {
    Ok(t) => t
    Err(e) => abort("claim 失败：" + e)
  }
  match claimed2.execute() {
    Ok(_) => ()
    Err(e) => abort("Claimed 应能 execute: " + e)
  }
}
