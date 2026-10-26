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
/// 修法（(a)+(b) 组合，BUG-421/422 二次收口后）：
///   (b) `infer_role_from_agent` 收窄：**只**认人类指挥官的整名 `human_steward`/`human`；
///       军官整名 `leader`/`lead` 与其它一切名字一律 Executor（BUG-421 删掉了那条白名单）
///   (a) `resolve_agent_role(name, declared)`：declared 只作**下限融合**、只接受可继承角色
///       （Leader/Executor），且取数侧剔除「server 自身份」记录（BUG-422）
///
/// 本文件钉四件事：
///   ① 本缺陷反例格：各种自称 commander 的名字 + 整名 leader/lead 全拿 Executor
///   ② 防修过头：显式声明 Leader ⇒ 拿到并标 `declared`；HumanSteward 声明不可继承；
///      推断是下限（human_steward 不被 Executor 降级）
///   ③ 变异对照：含大小写变体与后缀变体（只断言行为，守判例-30）
///   ④ 钉 (a) 真生效：`agent_fp_of(原始名)` 能查到指纹键、原始名查不到

///|
/// 锁 1（**本缺陷反例格**）：各种「带高角色词但不等于整名」的自称名字全拿 Executor
///
/// ⚠️ **BUG-421 改判**：`leader` / `lead` 这两个**整名**从本格「合法名单」里移出，
/// 现在它们与 `commander-fake` 同档 —— 见锁 3。留下的合法整名只有
/// `human_steward` / `human`（人类指挥官唯一的两个写法）。
/// 本格打的是**子串/前缀/后缀**那一类 + **整名军官单词**：`commander-fake`、`leader`、`lead` 等。
test "role_resolve_wb1_commander_names_get_executor" {
  let attack_names = [
    // 带 commander 子串/前缀 —— 这就是 BUG-418 的原始越权面
    "commander-fake", "commander", "commander-alpha", "my-commander", "fake-commander-tail",
    // 大写变体（抓「忘记 to_lower」）
     "COMMANDER", "Commander-Fake",
    // human_steward 的**变体**（不是整名，仍应 Executor）
     "human_steward-fake", "HUMAN_STEWARD_X", "human-steward", // 连字符不是合法整名
    // leader 的变体
     "leader-x", "x-leader", "lead2", "polish-lane", // 旧的 polish 子串规则已废
     "optimization-lane", // 旧的 optimization 子串规则已废
    // ★ BUG-421：军官**整名单词**也不再提权（此前被当合法路径，实测可订 src/engine/）
     "leader", "lead", "LEADER", "Lead",
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
/// 锁 2（防修过头 + declared 的**唯一**生效面）：`declared` 只能抬 Leader，不能抬 HumanSteward
///
/// BUG-418 原文：「高角色必须**派下来**，不能靠名字猜」——本格保留这条positive面：
/// 一条**通过过滤的** `role="Leader"` 登记记录仍然生效（来源标 `declared`）。
///
/// BUG-422 加固：`HumanSteward` **永不从登记表继承**（`inheritable_role` 返回 None）。
/// 理由：HS 独占 4 条不可逆路径，而「报名字 ⇒ 继承 HS」比 BUG-418 的 `commander-*`
/// 子串面更宽（连猜都不用猜）。现网 `agents` 表 0 条 HS 记录 ⇒ 本限制代价为 0。
test "role_resolve_wb2_declared_role_wins" {
  // ① declared=Leader 生效（军官可以派下来）
  let (r1, s1) = resolve_agent_role("any-fake-name", Some("Leader"))
  assert_eq(r1, "Leader")
  assert_eq(s1, "declared")
  // ② declared=HumanSteward **不生效**（不可继承 ⇒ 退推断）
  let (r2, s2) = resolve_agent_role("any-fake-name", Some("HumanSteward"))
  assert_eq(r2, "Executor")
  assert_eq(s2, "inferred")
  // ③ 推断是**下限**：名字已是 human_steward，声明 Executor 不许把它降级
  let (r3, s3) = resolve_agent_role("human_steward", Some("Executor"))
  assert_eq(r3, "HumanSteward")
  assert_eq(s3, "inferred")
  // ④ 未知角色值 / 空串 ⇒ 退推断（fail-closed）
  let (r4, s4) = resolve_agent_role("plain-agent", Some(""))
  assert_eq(r4, "Executor")
  assert_eq(s4, "inferred")
  let (r5, s5) = resolve_agent_role("plain-agent", Some("God"))
  assert_eq(r5, "Executor")
  assert_eq(s5, "inferred")
  // ⑤ 查不到 ⇒ 退推断
  let (r6, s6) = resolve_agent_role("plain-agent", None)
  assert_eq(r6, "Executor")
  assert_eq(s6, "inferred")
}

///|
/// 锁 3（**BUG-421 本体的纯函数格**）：整名 `leader` / `lead` 一律 Executor
///
/// **改判记录**：本格原先把 `leader`/`lead`/`LEADER` 钉成 `Leader`
/// （BUG-418 修法期「保留军官自报这条路」的政策），BUG-421 落地后改为钉 `Executor`。
/// 同一份输入、同一个函数 —— 变的是政策，不是实现。
///
/// 变异对照：把 `infer_role_from_agent` 里那条 `else if a == "leader" || a == "lead"`
/// 加回来 ⇒ 本格立刻红（实测见 reports/ 的变异读数）。
test "role_resolve_wb3_exact_leader_is_executor" {
  assert_eq(infer_role_from_agent("leader"), "Executor")
  assert_eq(infer_role_from_agent("lead"), "Executor")
  assert_eq(infer_role_from_agent("LEADER"), "Executor") // 大小写不敏感，一律 Executor
  // 仅存的合法整名（人类指挥官）必须还能认出来 —— 防「一刀切全 Executor」
  assert_eq(infer_role_from_agent("human_steward"), "HumanSteward")
  assert_eq(infer_role_from_agent("human"), "HumanSteward")
  // 带后缀/前缀的也不行（子串不给高角色）
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
    fail(
      "agent_fp_of 没有做哈希 —— 查 agents.role 会永远查不到",
    )
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
