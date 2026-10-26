/// engine_scope_perm_role_wbtest.mbt —— BUG-418 的**端到端**回归锁：
/// 「角色不可从 agent 名字推断」必须在 `reserve_scope` 真正走的那条路上成立。
///
/// 缺陷原形（已提交版本 `git show HEAD:src/engine/engine_scope_perm.mbt` 逐字如此）：
/// ```
/// fn infer_role_from_agent(agent_name) {
///   let a = agent_name.to_lower()
///   if a.contains("commander") || a.contains("human_steward") || a == "human" {
///     "HumanSteward"
///   } else if a.contains("leader") || a.contains("lead") || a.contains("polish")
///     || a.contains("optimization") {
///     "Leader"
///   } else { "Executor" }
/// }
/// ```
/// 而 `engine_rsv.rsv_set` / `rsv_try_set` 拿它的返回值**直接决定 `RoleDenied` 还是放行**。
/// 名字是 MCP `reserve_scope(agent=…)` 原样透传的**不可信输入** ⇒ 「命名即提权」：
///   `agent="lane-b-leader"`   ⇒ Leader      ⇒ 可预订 `src/engine/`（军官保护面）
///   `agent="not-a-commander"` ⇒ HumanSteward ⇒ 可预订 `src/store/store_sqlite.mbt`（统帅独占）
///
/// 本文件补的是**别人没测的那一半**：同包 `engine_role_resolve_wbtest.mbt` 钉的是
/// 纯函数（`infer_role_from_agent` / `resolve_agent_role` / `agent_fp_of`）的正确性，
/// 而这里每一格都走 `FistEngine::rsv_try_set` —— 也就是 `reserve_scope` 工具的真实调用路径，
/// 所以它同时证明「纯函数对了」和「接线没被绕过」（判例-29：机制格 ≠ 实现路径格）。
///
/// 六格：
///   ① 纯函数：带特权语义子串的名字一律 fail-closed 成 Executor（旧实现会提权）
///   ② 纯函数：**整名** human_steward / human 仍是 HumanSteward（合法路径不退化）
///   ③ 端到端：命名绕过拿不到 Leader / HumanSteward 保护面（Err）
///   ④ 端到端：合法 human_steward 仍能预订同样这两条 scope（Ok）
///   ⑤ 端到端（A 案权威面）：`agents.role` 里登记成 Leader 的 agent **能**过军官门；
///      而它旁边那个「名字带 leader 但没登记」的 agent **不能** —— 权威面真的在生效
///   ⑥ 变异对照 + 函数体扫描：把旧宽松规则写进判据里跑同一输入；并断言现函数体内
///      不再出现子串匹配（注释里提到 contains 不算，因为只扫函数体）
///
/// ## 已知残留（本轮**不修**，需要认证身份才能真收口 —— 见下）
/// 修法把「角色来源」改成「`agents.role` 优先、推断兜底」，但**查表键仍是调用方自报的名字**。
/// 实测（临时探针，`FistEngine::open_sqlite` + `agents_register` 复刻 server 启动注册）：
///   · `agent="fist-mbt"` ⇒ declared=Leader ⇒ **ALLOWED** on `src/engine/`、`src/core/`
///     （`server.mbt:16-18` 就以 role="Leader" 登记了该名）——名字仍是通行证；
///     HumanSteward 独占面（`store_sqlite.mbt`/`moon.mod`）仍 **DENIED**，故残留面**只到 Leader 级**。
///   · 名字自带 leader/commander 的未登记名（`leader-fist-mbt`/`lane-b-leader`）全部 **DENIED**。 ✅
/// 另一条副作用（同样不修，只记录）：`human_steward` 若被 `claim`/`execute` 的
/// `agent_touch_first_seen` 以 role="Executor" 注册进 agents 表（ON CONFLICT **不更新** role ⇒ 永久 Executor），
/// `resolve_agent_role` 的「declared 优先」会把合法统帅**锁在 HumanSteward 面之外**（实测 DENIED）。
/// 收口方向：① 认证身份（pubkey/会话令牌）取代自报名字；② 整名白名单 `human_steward`/`human`
/// 当**下限**（`role = max(declared, inferred)`），注册面不能把统帅降级。

///|
/// 锁 1（**BUG-418 本体**）：带特权重语义子串/前缀的名字**一律**降级为 Executor。
///
/// 修前实测：这些名字里 `lane-b-leader`/`leader-foo`/`polish-lane`/… 全部拿到 "Leader"，
/// `not-a-commander`/`fake-human_steward` 全部拿到 "HumanSteward"。
test "scope_role_wb1_privileged_substring_names_fail_closed" {
  let spoofed = [
    // 旧实现会判 Leader 的一批（子串 leader / lead / polish / optimization）
    "lane-b-leader",
    "leader-foo",
    "lead-dev",
    "my-lead",
    "polish-lane",
    "optimization-bot",
    "LEADER-UPPER",
    // 旧实现会判 HumanSteward 的一批（子串 commander / human_steward）
    "not-a-commander",
    "commander-in-chief",
    "fake-human_steward",
    "x-human_steward-y",
    // 整名 + 后缀（子串能过、整名匹配不能过）
    "human_steward_but_actually_executor",
  ]
  for name in spoofed {
    let role = infer_role_from_agent(name)
    if role != "Executor" {
      fail(
        "★BUG-418 仍成立：agent 名字 '" +
        name +
        "' 被推断成 '" +
        role +
        "'（应 fail-closed 成 Executor）",
      )
    }
  }
}

///|
/// 锁 2：**整名** human_steward / human 仍是 HumanSteward（收窄 ≠ 把合法路径关死）。
///
/// 大小写归一（HUMAN_STEWARD）仍认 —— 那是同一个名字的拼写，不是新增一条推断面。
test "scope_role_wb2_exact_human_steward_still_steward" {
  for name in ["human_steward", "human", "HUMAN_STEWARD", "Human"] {
    let role = infer_role_from_agent(name)
    if role != "HumanSteward" {
      fail("合法路径退化：agent 名字 '" + name + "' 不再判 HumanSteward（实得 " + role + "）")
    }
  }
}

///|
/// 锁 3（**端到端**）：命名绕过拿不到 Leader / HumanSteward 保护面。
///
/// 走 `FistEngine::rsv_try_set`（= server `reserve_scope` 的同一条路），
/// 内存后端下 `agents_get` 恒 None ⇒ 只剩推断这一层，正好复现攻击面。
test "scope_role_wb3_end_to_end_naming_bypass_denied" {
  let e = FistEngine::new()
  let guarded = [
    ("src/engine/engine.mbt", "lane-b-leader"),
    ("src/router/model_router.mbt", "leader-foo"),
    ("src/store/store_sqlite.mbt", "not-a-commander"),
    ("src/server/server.mbt", "polish-lane"),
    ("moon.mod", "commander-in-chief"),
  ]
  for pair in guarded {
    let (scope, agent) = pair
    match
      e.rsv_try_set(
        scope~,
        agent~,
        ttl_until="2026-12-31T00:00:00Z",
        created_at="2026-10-26T00:00:00Z",
      ) {
      Ok(o) =>
        fail(
          "★BUG-418 仍成立：agent '" +
          agent +
          "' 靠名字预订了受保护 scope '" +
          scope +
          "'（action=" +
          o.action +
          "）",
        )
      Err(msg) =>
        if !msg.contains("拒绝") {
          fail("预期权限拒绝，实得错误：" + msg)
        }
    }
  }
}

///|
/// 锁 4（**端到端 · 合法路径**）：`human_steward` 仍能预订军官/统帅保护面。
test "scope_role_wb4_end_to_end_legit_human_steward_works" {
  let e = FistEngine::new()
  for scope in ["src/engine/engine.mbt", "src/store/store_sqlite.mbt", "moon.mod"] {
    match
      e.rsv_try_set(
        scope~,
        agent="human_steward",
        ttl_until="2026-12-31T00:00:00Z",
        created_at="2026-10-26T00:00:00Z",
      ) {
      Ok(o) =>
        if !o.reserved {
          fail("human_steward 应能预订 '" + scope + "'，实得 action=" + o.action)
        }
      Err(msg) => fail("★合法路径被打死：human_steward 预订 '" + scope + "' 被拒：" + msg)
    }
  }
}

///|
/// 锁 5（**端到端 · A 案权威面**）：`agents.role` 里登记成 Leader 的 agent 真能过军官门，
/// 而「名字自带 leader、但没登记」的 agent 不能 —— 权威面在生效，名字不再是通行证。
///
/// 为什么这一格必须有：修法把角色来源改成了「先查 `agents.role`」，
/// 若那条查库路径写错（例如拿**原始名**去查而库里存的是 16 位指纹），
/// 它会**静默失效**、永远退回推断 —— 纯函数锁全绿，而 A 案一点没生效。
/// 这一格直接钉「登记过的 Leader 真的能过门」+「同名族里没登记的过不去」。
test "scope_role_wb5_declared_role_wins_end_to_end" {
  let db = "temp/bug418_declared_role_wb.db"
  let e = match FistEngine::open_sqlite(db) {
    None => abort("open_sqlite 失败：" + db)
    Some(x) => x
  }
  let registered = "lane-q-sqlite-leader-42"
  match
    e.agents_register(
      agent_id=agent_fp_of(registered),
      agent_type="executor",
      role="Leader",
      soldier="工兵",
      pubkey_fp="",
      pid=1,
      now="2026-10-26T00:00:00Z",
    ) {
    Err(msg) => abort("agents_register 失败：" + msg)
    Ok(_) => ()
  }
  // ① 已登记 Leader ⇒ 军官保护面放行（A 案权威面真生效）
  match
    e.rsv_try_set(
      scope="src/engine/engine_scope_perm.mbt",
      agent=registered,
      ttl_until="2026-12-31T00:00:00Z",
      created_at="2026-10-26T00:00:00Z",
    ) {
    Err(msg) => fail("★A 案没生效：已登记 Leader 的 agent 仍被拒：" + msg)
    Ok(o) =>
      if !o.reserved {
        fail("已登记 Leader 应能预订军官保护面，实得 action=" + o.action)
      }
  }
  // ② 名字更"像" Leader、但没登记的 agent ⇒ 仍 fail-closed（名字不是通行证）
  match
    e.rsv_try_set(
      scope="src/engine/engine_rsv.mbt",
      agent="leader-" + registered,
      ttl_until="2026-12-31T00:00:00Z",
      created_at="2026-10-26T00:00:00Z",
    ) {
    Ok(o) =>
      fail(
        "★名字绕过仍在：未登记的 'leader-" +
        registered +
        "' 预订了 src/engine/（action=" +
        o.action +
        "）",
      )
    Err(_) => ()
  }
  // ③ 已登记的 Leader 也进不了 HumanSteward 独占面（别修成"登记即全通"）
  match
    e.rsv_try_set(
      scope="src/store/store_sqlite.mbt",
      agent=registered,
      ttl_until="2026-12-31T00:00:00Z",
      created_at="2026-10-26T00:00:00Z",
    ) {
    Ok(o) =>
      fail(
        "★豁免过宽：登记成 Leader 的 agent 抢到了 HumanSteward 独占面（action=" +
        o.action +
        "）",
      )
    Err(_) => ()
  }
}

///|
/// 锁 6（**变异对照 + 函数体扫描**，判例-29/30）：
///   6a 把旧宽松规则写进判据里跑同一输入 ⇒ 旧规则确实提权（机制存在的证据）
///   6b 现实现必须 fail-closed（若自己退回旧规则，这里必红）
///   6c 现 `infer_role_from_agent` 的**函数体**里不得再出现子串匹配
///
/// 为什么 6c 要只扫函数体：文件里的注释**逐字引用了** `contains("commander")` 说明病灶，
/// 全文扫会命中注释（判例-30 的自指假绿/假红），必须限定到函数体。
test "scope_role_wb6_mutation_control_and_body_scan" {
  // —— 6a/6b：旧实现（BUG-418 病灶）原样复刻，仅用于对照 ——
  let old_infer = fn(name : String) -> String {
    let a = name.to_lower()
    if a.contains("commander") || a.contains("human_steward") || a == "human" {
      "HumanSteward"
    } else if a.contains("leader") ||
      a.contains("lead") ||
      a.contains("polish") ||
      a.contains("optimization") {
      "Leader"
    } else {
      "Executor"
    }
  }
  assert_eq(old_infer("lane-b-leader"), "Leader")
  assert_eq(old_infer("not-a-commander"), "HumanSteward")
  assert_eq(infer_role_from_agent("lane-b-leader"), "Executor")
  assert_eq(infer_role_from_agent("not-a-commander"), "Executor")

  // —— 6c：**修前/修后的可执行对照** ——
  // 规则表（`scope_permissions`）与 `check_scope_permission` 本轮**一字未改**，
  // 变的只有「角色从哪来」。所以用旧推断结果去喂现役判定函数，就是修前那条伤害链的
  // 逐字重放：旧实现下 `lane-b-leader` 拿到 Leader ⇒ `src/engine/` 的门是开的。
  match check_scope_permission("src/engine/engine.mbt", old_infer("lane-b-leader")) {
    Allowed => ()
    _ => fail("对照失效：旧推断 'lane-b-leader' 竟打不开 src/engine/（夹具与现役规则表不匹配）")
  }
  match
    check_scope_permission(
      "src/store/store_sqlite.mbt",
      old_infer("not-a-commander"),
    ) {
    Allowed => ()
    _ => fail("对照失效：旧推断 'not-a-commander' 竟打不开 HumanSteward 独占面")
  }
  // 修后：同一条输入、同一张规则表 ⇒ 门是关的
  match
    check_scope_permission(
      "src/engine/engine.mbt",
      infer_role_from_agent("lane-b-leader"),
    ) {
    RoleDenied(_) => ()
    _ => fail("★修后仍能开门：'lane-b-leader' 对 src/engine/ 未被 RoleDenied")
  }
  match
    check_scope_permission(
      "src/store/store_sqlite.mbt",
      infer_role_from_agent("not-a-commander"),
    ) {
    RoleDenied(_) => ()
    _ => fail("★修后仍能开门：'not-a-commander' 对 store_sqlite 未被 RoleDenied")
  }

  // —— 6d：函数体扫描（只认带缩进的代码形状，注释不参与） ——
  let perm = @fs.read_file_to_string(
    "src/engine/engine_scope_perm.mbt",
    encoding="utf8",
  ) catch {
    _ => abort("读 src/engine/engine_scope_perm.mbt 失败：接线格没跑到被测面")
  }
  let marker = "pub fn infer_role_from_agent(agent_name : String) -> String {"
  let mut in_fn = false
  let mut body = ""
  for line in perm.split("\n") {
    let t = line.trim()
    if in_fn {
      body = body + line.to_owned() + "\n"
      if t == "}" {
        in_fn = false
      }
    } else if t == marker {
      in_fn = true
      body = body + line.to_owned() + "\n"
    }
  }
  if body == "" {
    abort("没抽到 infer_role_from_agent 的函数体 —— 判据没跑到被测面（函数改名/改签名了？）")
  }
  if body.contains(".contains(") {
    fail("★BUG-418 回潮：infer_role_from_agent 函数体内又出现子串匹配（.contains）")
  }
  // 必须是「整名比较」形状：`a ==` 或 `match a`
  if !body.contains("a ==") && !body.contains("match a") {
    fail("infer_role_from_agent 不再按整名比较（既无 `a ==` 也无 `match a`）")
  }
}
