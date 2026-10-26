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
/// ## 已知残留（BUG-421/422 收口后更新）
/// **已关闭**（本文件 wb7/wb8 钉住）：
///   · 整名 `leader` / `lead` 买到军官面（BUG-421）—— 推断里已无 Leader 分支
///   · 报 server 自身份名（`fist-mbt`）继承 `role="Leader"`（BUG-422）——
///     `agents_role_for_judgment` 把 `agent_type=="server"` 记录整条剔出裁决
///
/// **仍在**（需认证身份才能真收口，见 memory/bugs.md BUG-422「修法方向」A 案）：
///   · 报一个**非 server 类型**且被显式授予 Leader 的登记名，仍可继承该角色
///     （现网该类记录 0 条；`agents_register` 未暴露成 MCP 工具 ⇒ 需先有内部写入面）
///   · 另一条副作用（BUG-423 已修其注册侧）：`human_steward` 若被 `claim`/`execute` 的
///     `agent_touch_first_seen` 以 role="Executor" 注册进 agents 表，`resolve_agent_role`
///     的下限语义现在**不会再把它降级**（见 wb2 ⑤），但注册面本身仍是低权可写。

///|
/// 锁 1（**BUG-418 本体**）：带特权重语义子串/前缀的名字**一律**降级为 Executor。
///
/// 修前实测：这些名字里 `lane-b-leader`/`leader-foo`/`polish-lane`/… 全部拿到 "Leader"，
/// `not-a-commander`/`fake-human_steward` 全部拿到 "HumanSteward"。
test "scope_role_wb1_privileged_substring_names_fail_closed" {
  let spoofed = [
    // 旧实现会判 Leader 的一批（子串 leader / lead / polish / optimization）
    "lane-b-leader", "leader-foo", "lead-dev", "my-lead", "polish-lane", "optimization-bot",
    "LEADER-UPPER",
    // 旧实现会判 HumanSteward 的一批（子串 commander / human_steward）
     "not-a-commander", "commander-in-chief", "fake-human_steward", "x-human_steward-y",
    // 整名 + 后缀（子串能过、整名匹配不能过）
     "human_steward_but_actually_executor",
    // ★ BUG-421：军官**整名单词**（此前是白名单里的合法路径，实测可订 src/engine/）
     "leader", "lead", "LEADER", "Lead",
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
      fail(
        "合法路径退化：agent 名字 '" +
        name +
        "' 不再判 HumanSteward（实得 " +
        role +
        "）",
      )
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
  for
    scope in ["src/engine/engine.mbt", "src/store/store_sqlite.mbt", "moon.mod"] {
    match
      e.rsv_try_set(
        scope~,
        agent="human_steward",
        ttl_until="2026-12-31T00:00:00Z",
        created_at="2026-10-26T00:00:00Z",
      ) {
      Ok(o) =>
        if !o.reserved {
          fail(
            "human_steward 应能预订 '" +
            scope +
            "'，实得 action=" +
            o.action,
          )
        }
      Err(msg) =>
        fail(
          "★合法路径被打死：human_steward 预订 '" +
          scope +
          "' 被拒：" +
          msg,
        )
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
    Err(msg) =>
      fail("★A 案没生效：已登记 Leader 的 agent 仍被拒：" + msg)
    Ok(o) =>
      if !o.reserved {
        fail(
          "已登记 Leader 应能预订军官保护面，实得 action=" +
          o.action,
        )
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
  match
    check_scope_permission("src/engine/engine.mbt", old_infer("lane-b-leader")) {
    Allowed => ()
    _ =>
      fail(
        "对照失效：旧推断 'lane-b-leader' 竟打不开 src/engine/（夹具与现役规则表不匹配）",
      )
  }
  match
    check_scope_permission(
      "src/store/store_sqlite.mbt",
      old_infer("not-a-commander"),
    ) {
    Allowed => ()
    _ =>
      fail(
        "对照失效：旧推断 'not-a-commander' 竟打不开 HumanSteward 独占面",
      )
  }
  // 修后：同一条输入、同一张规则表 ⇒ 门是关的
  match
    check_scope_permission(
      "src/engine/engine.mbt",
      infer_role_from_agent("lane-b-leader"),
    ) {
    RoleDenied(_) => ()
    _ =>
      fail(
        "★修后仍能开门：'lane-b-leader' 对 src/engine/ 未被 RoleDenied",
      )
  }
  match
    check_scope_permission(
      "src/store/store_sqlite.mbt",
      infer_role_from_agent("not-a-commander"),
    ) {
    RoleDenied(_) => ()
    _ =>
      fail(
        "★修后仍能开门：'not-a-commander' 对 store_sqlite 未被 RoleDenied",
      )
  }

  // —— 6d：函数体扫描（只认带缩进的代码形状，注释不参与） ——
  let perm = @fs.read_file_to_string(
    "src/engine/engine_scope_perm.mbt",
    encoding="utf8",
  ) catch {
    _ =>
      abort(
        "读 src/engine/engine_scope_perm.mbt 失败：接线格没跑到被测面",
      )
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
    abort(
      "没抽到 infer_role_from_agent 的函数体 —— 判据没跑到被测面（函数改名/改签名了？）",
    )
  }
  if body.contains(".contains(") {
    fail(
      "★BUG-418 回潮：infer_role_from_agent 函数体内又出现子串匹配（.contains）",
    )
  }
  // 必须是「整名比较」形状：`a ==` 或 `match a`
  if !body.contains("a ==") && !body.contains("match a") {
    fail(
      "infer_role_from_agent 不再按整名比较（既无 `a ==` 也无 `match a`）",
    )
  }
  // —— 6e：**BUG-421 回潮的源码级 tripwire** ——
  // 只扫函数体（注释里点名 leader/lead 不算：判例-30 的自指假绿）。
  // 行为锁已经在 wb1/wb7 与 role_resolve_wb3 上；这一格是「把白名单加回来」的最快红灯。
  if body.contains("a == \"lead") {
    fail(
      "★BUG-421 回潮：infer_role_from_agent 函数体内又出现军官整名白名单（a == \"lead…）",
    )
  }
}

///|
/// 锁 7（**BUG-421 端到端**）：整名 `leader` / `lead` 拿不到军官面。
///
/// 为什么本格必须走 `rsv_try_set` 而不是只测纯函数（判例-29）：BUG-421 的病灶是
/// 「`infer_role_from_agent` 的返回值直接决定 `RoleDenied` 还是放行」——
/// 纯函数改对了、接线却把推断结果丢掉换成常量，纯函数锁照样绿。
///
/// 内存后端下 `agents` 表恒空 ⇒ 只剩推断这一层，正好复现「名字即身份」的攻击面。
test "scope_role_wb7_exact_leader_denied_end_to_end" {
  let e = FistEngine::new()
  // 四组「整名单词 → 军官保护面」，覆盖 4 条不同的 Leader 规则（engine/router/core/display）
  let guarded = [
    ("src/engine/engine_perm_probe.mbt", "leader"),
    ("src/router/model_router_probe.mbt", "lead"),
    ("src/core/core_task_probe.mbt", "LEADER"),
    ("src/display/rank_probe.mbt", "Lead"),
  ]
  for pair in guarded {
    let (scope, agent) = pair
    match
      e.rsv_try_set(
        scope~,
        agent~,
        ttl_until="2026-12-31T00:00:00Z",
        created_at="2026-10-27T00:00:00Z",
      ) {
      Ok(o) =>
        fail(
          "★BUG-421 仍成立：整名 '" +
          agent +
          "' 预订了军官保护面 '" +
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
  // 反例对照（防一刀切）：人类指挥官整名仍能订同一批 scope
  match
    e.rsv_try_set(
      scope="src/engine/engine_perm_probe.mbt",
      agent="human_steward",
      ttl_until="2026-12-31T00:00:00Z",
      created_at="2026-10-27T00:00:00Z",
    ) {
    Ok(o) =>
      if !o.reserved {
        fail("human_steward 应能订 src/engine/，实得 action=" + o.action)
      }
    Err(msg) => fail("★修过头：human_steward 被拒：" + msg)
  }
}

///|
/// 锁 8（**BUG-422 端到端**）：报 server 自身份的名字（`fist-mbt`）不再继承它的 `role="Leader"`。
///
/// 复刻 `server.mbt` 的 `make_engine()`：启动即给「自己」登记
/// `agent_touch_first_seen(eng, "fist-mbt", "default", "server", "Leader", …)`。
///
/// 五格（判例-29 的两种失败模式各有一格）：
///   ① 记录**确实在表里**（否则本格退化成「查不到」，证明不了过滤在起作用 —— 假绿风险）
///   ② 裁决取数面看不到它（`agents_role_for_judgment` ⇒ None，而 `agents_get` ⇒ Some）
///   ③ 端到端：报 `fist-mbt` 订 `src/engine/` ⇒ Err（修前 WELL ALLOWED）
///   ④ **变异对照**：把「未过滤的」`agents_get(...).role` 喂给裁决函数 ⇒ Allowed
///      （旧实现逐字重放，证明 ③ 的门是被「过滤」关上的，不是本来就没开）
///   ⑤ 正例 + 加固：非 server 类型登记 Leader 仍可继承（没修过头）；
///      而登记成 `HumanSteward` 的记录**不可继承**（HS 面永不从自报名字来）
test "scope_role_wb8_server_self_identity_not_inheritable" {
  let db = "temp/bug422_server_identity_wb.db"
  let e = match FistEngine::open_sqlite(db) {
    None => abort("open_sqlite 失败：" + db)
    Some(x) => x
  }
  let self_name = "fist-mbt"
  let self_fp = agent_fp_of(self_name)
  match
    e.agents_register(
      agent_id=self_fp,
      agent_type="server",
      role="Leader",
      soldier="通信兵",
      pubkey_fp="",
      pid=1,
      now="2026-10-27T00:00:00Z",
    ) {
    Err(msg) => abort("agents_register 失败：" + msg)
    Ok(_) => ()
  }
  // ① 记录在表里（且 role 就是 Leader）
  let raw_role = match e.agents_get(self_fp) {
    None =>
      abort("★判据没跑到被测面：server 自身份记录没写成")
    Some(rec) => {
      assert_eq(rec.role, "Leader")
      assert_true(@store.agent_record_is_process_self(rec))
      rec.role
    }
  }
  // ② 裁决面看不到它
  let judged = match e.store.sqlite_store() {
    None => abort("sqlite_store 为空 —— 判据没跑到被测面")
    Some(s) => s.agents_role_for_judgment(self_fp)
  }
  match judged {
    Some(r) =>
      fail(
        "★BUG-422 未修：server 自身份仍参与角色裁决（role=" +
        r +
        "）",
      )
    None => ()
  }
  // ③ 端到端：报这个名字拿不到军官面
  match
    e.rsv_try_set(
      scope="src/engine/engine_rsv.mbt",
      agent=self_name,
      ttl_until="2026-12-31T00:00:00Z",
      created_at="2026-10-27T00:00:00Z",
    ) {
    Ok(o) =>
      fail(
        "★BUG-422 仍成立：agent=fist-mbt 预订了 src/engine/（action=" +
        o.action +
        "）",
      )
    Err(msg) =>
      if !msg.contains("拒绝") {
        fail("预期权限拒绝，实得错误：" + msg)
      }
  }
  // ④ 变异对照：旧实现（未过滤）在同一输入上是**放行**的
  match check_scope_permission("src/engine/engine_rsv.mbt", raw_role) {
    Allowed => ()
    _ =>
      fail(
        "对照失效：未过滤的 role=" +
        raw_role +
        " 竟打不开 src/engine/（夹具与规则表不匹配）",
      )
  }
  // ⑤a 正例：非 server 类型 + 显式 Leader ⇒ 仍能过（便利性没被一刀切掉）
  let legit = "bug422-legit-leader-lane"
  match
    e.agents_register(
      agent_id=agent_fp_of(legit),
      agent_type="executor",
      role="Leader",
      soldier="工兵",
      pubkey_fp="",
      pid=2,
      now="2026-10-27T00:00:00Z",
    ) {
    Err(msg) => abort("agents_register 失败：" + msg)
    Ok(_) => ()
  }
  match
    e.rsv_try_set(
      scope="src/engine/engine_perm_legit_probe.mbt",
      agent=legit,
      ttl_until="2026-12-31T00:00:00Z",
      created_at="2026-10-27T00:00:00Z",
    ) {
    Ok(o) =>
      if !o.reserved {
        fail(
          "登记的 Leader 应能预订 src/engine/，实得 action=" +
          o.action,
        )
      }
    Err(msg) => fail("★修过头：登记的 Leader 被拒：" + msg)
  }
  // ⑤b 加固：登记成 HumanSteward 的记录**不可继承**（HS 面只认整名 human_steward/human）
  let fake_hs = "bug422-fake-hs-lane"
  match
    e.agents_register(
      agent_id=agent_fp_of(fake_hs),
      agent_type="agent",
      role="HumanSteward",
      soldier="工兵",
      pubkey_fp="",
      pid=3,
      now="2026-10-27T00:00:00Z",
    ) {
    Err(msg) => abort("agents_register 失败：" + msg)
    Ok(_) => ()
  }
  match
    e.rsv_try_set(
      scope="src/store/store_sqlite.mbt",
      agent=fake_hs,
      ttl_until="2026-12-31T00:00:00Z",
      created_at="2026-10-27T00:00:00Z",
    ) {
    Ok(o) =>
      fail(
        "★HS 面被继承：登记 role=HumanSteward 的 agent 抢到了 store_sqlite.mbt（action=" +
        o.action +
        "）",
      )
    Err(_) => ()
  }
}
