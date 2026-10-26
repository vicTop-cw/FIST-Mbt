/// engine_role_resolve_wbtest.mbt —— BUG-418 的成对锁：角色推断不得被名字绕过。
///
/// 缺陷原形（可主动利用的越权面）：
/// ```
/// fn infer_role_from_agent(name) {
///   if name.contains("commander") || name.contains("human_steward") || name == "human" {
///     "HumanSteward"     // ← 自称 commander-fake 就是 HumanSteward
///   } else if name.contains("leader") || name.contains("lead") || ... {
///     "Leader"
///   } else { "Executor" }
/// }
/// ```
/// ⇒ 任何 agent 只要起名带 `commander` 就能改 `src/store/store_sqlite.mbt` /
/// `src/server/server.mbt` / `moon.mod`（HumanSteward 独占面）。
///
/// **注释写着「不是安全门禁」，但两个调用点拿它的返回值直接决定 `RoleDenied` / 放行**
/// —— 注释说不用于安全、代码却用于安全，等于两者都不可信。
/// **判断方法：看返回值是否进了 `if`/`match` 的分支选择，而不是看注释怎么说。**
///
/// 修法（(a)+(b) 组合）：
///   (b) `infer_role_from_agent` 收窄：永不返回 HumanSteward，只留 `leader`/`lead` 整名
///   (a) `resolve_agent_role(name, declared)`：权威面 `agents.role` 优先，推断只做兜底
///
/// 本文件钉四件事：
///   ① 本缺陷反例格：各种自称 commander 的名字全拿 Executor
///   ② 防修过头：显式声明 HumanSteward ⇒ 拿到，且来源标 `declared`
///   ③ 变异对照：含大小写变体与后缀变体（只断言行为，守判例-30）
///   ④ 钉 (a) 真生效：`agent_fp_of(原始名)` 能查到指纹键、原始名查不到

///|
/// 锁 1（**本缺陷反例格**）：各种「带高角色词但不等于整名」的自称名字全拿 Executor
///
/// ⚠️ 注意：`human_steward` / `human` / `leader` / `lead` 这几个**整名**是**合法**的
/// （人类指挥官与军官自报就用它们），不在本格攻击名里 —— 见锁 3。
/// 本格打的是**子串/前缀/后缀**那一类：`commander-fake`、`my-commander` 等。
test "role_resolve_wb1_commander_names_get_executor" {
  let attack_names = [
    // 带 commander 子串/前缀 —— 这就是 BUG-418 的原始越权面
    "commander-fake",
    "commander",
    "commander-alpha",
    "my-commander",
    "fake-commander-tail",
    // 大写变体（抓「忘记 to_lower」）
    "COMMANDER",
    "Commander-Fake",
    // human_steward 的**变体**（不是整名，仍应 Executor）
    "human_steward-fake",
    "HUMAN_STEWARD_X",
    "human-steward", // 连字符不是合法整名
    // leader 的变体
    "leader-x",
    "x-leader",
    "lead2",
    "polish-lane", // 旧的 polish 子串规则已废
    "optimization-lane", // 旧的 optimization 子串规则已废
  ]
  for n in attack_names {
    let r = infer_role_from_agent(n)
    if r == "HumanSteward" {
      fail("★越权面未修：名字 '" + n + "' 拿到了 HumanSteward")
    }
    assert_eq(r, "Executor")
  }
}

///|
/// 锁 2（防修过头）：显式声明 `HumanSteward` ⇒ 拿到，且来源标 `declared`
///
/// 这是 (a) 的正例：高角色必须**派下来**，不能靠名字猜。
test "role_resolve_wb2_declared_role_wins" {
  let (r1, s1) = resolve_agent_role("any-fake-name", Some("HumanSteward"))
  assert_eq(r1, "HumanSteward")
  assert_eq(s1, "declared")
  // 声明为 Leader 也认
  let (r2, s2) = resolve_agent_role("any-fake-name", Some("Leader"))
  assert_eq(r2, "Leader")
  assert_eq(s2, "declared")
  // 声明为空串 ⇒ 退回推断，且来源标 inferred
  let (r3, s3) = resolve_agent_role("plain-agent", Some(""))
  assert_eq(r3, "Executor")
  assert_eq(s3, "inferred")
  // 查不到 ⇒ 退回推断
  let (r4, s4) = resolve_agent_role("plain-agent", None)
  assert_eq(r4, "Executor")
  assert_eq(s4, "inferred")
}

///|
/// 锁 3（变异对照，判例-29）：`leader`/`lead` 整名仍拿 Leader（收窄没修过头）
///
/// 若把收窄规则改成「恒 Executor」，本格必红 —— 那是修过头。
test "role_resolve_wb3_exact_leader_still_works" {
  assert_eq(infer_role_from_agent("leader"), "Leader")
  assert_eq(infer_role_from_agent("lead"), "Leader")
  assert_eq(infer_role_from_agent("LEADER"), "Leader") // 大小写不敏感
  // 但带后缀/前缀的不行（子串不给高角色）
  assert_eq(infer_role_from_agent("leader-x"), "Executor")
  assert_eq(infer_role_from_agent("x-leader"), "Executor")
  assert_eq(infer_role_from_agent("lead2"), "Executor")
}

///|
/// 锁 4（**钉 (a) 真生效**）：`agent_fp_of(原始名)` 是落库键，原始名查不到
///
/// 为什么必须有这一格：`reserve_scope` 收到的是调用方自由填的**原始名**，
/// 而 `agents.agent_id` 落的是 16 位指纹。若调用方直接传原始名去 `agents_get`，
/// **永远查不到** ⇒ 「查权威角色」静默失效 ⇒ 等于只做了 (b)。
///
/// 这一格是 **Lane S 实测发现的关键陷阱**的锁：
///   reserve_scope 的 agent = 原始名（未哈希）
///   agents.agent_id        = 16 位指纹
test "role_resolve_wb4_fingerprint_is_the_key" {
  let raw = "commander-fake"
  let fp = agent_fp_of(raw)
  // 指纹必须与原始名不同（否则说明没做哈希）
  if fp == raw {
    fail("agent_fp_of 没有做哈希 —— 查 agents.role 会永远查不到")
  }
  // 指纹必须是 16 位 hex（与 @omega.fnv1a64 同构）
  assert_eq(fp.length(), 16)
  // 与 server 侧同构：@omega.fnv1a64("agent_id:" + raw)
  assert_eq(fp, @omega.fnv1a64("agent_id:" + raw))
  // 不同原始名 ⇒ 不同指纹（简单反碰撞）
  if agent_fp_of("a") == agent_fp_of("b") {
    fail("agent_fp_of 对不同输入返回同值 —— 哈希坏了")
  }
}
