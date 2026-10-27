/// acl_identity_wbtest.mbt —— BUG-436「ACL 判定身份逐调用漂移」的回归锁。
///
/// 事故现场（memory/bugs.md BUG-436，另一项目实测）：
///   claim(assignee="vools-retry-lead")  → 判定身份 4e3b9eb2cd9cb473
///   execute(task_id=…)                  → 判定身份 020934005581bee2（= fp("manual")）
///   grant 只能命中其中一个 ⇒ 干活的人永远进不去；报错里印的那串指纹再喂回 grant
///   会被再哈希一次（→ dfd9df…），于是「已落库但 execute 仍拒」。
///
/// 锁法（对应判例-29/30）：
///   · 机制格：解析链的每一档优先级都单独断言（不是只测「正常路径通过」）。
///   · 变异格：把 execute 的身份退回 `executor`（=fp("manual")）这条**旧实现路径**，
///     下面的「同任务同身份」与「grant 后 execute 能过」两格必红——因为断言的是
///     解析结果与真实 ACL 门，不是注释/文案。

///|
/// 口径锚：`fp("vools-retry-lead")` 必须等于事故现场报的 4e3b9eb2cd9cb473。
/// 这条同时钉住「指纹算法与 agent_id: 前缀」——一变，全仓既有 ACL 行全部失配。
test "BUG-436 身份指纹口径锚（与事故现场逐字一致）" {
  let id = acl_claim_identity("", "vools-retry-lead")
  assert_eq(id.raw, "vools-retry-lead")
  assert_eq(id.source, "assignee")
  assert_false(id.implicit)
  assert_eq(id.fp(), "4e3b9eb2cd9cb473")
}

///|
/// claim：显式 agent 压过 assignee（两者不同时，"谁在写"是 agent）。
test "BUG-436 claim 判定身份优先级：显式 agent > assignee" {
  let a = acl_claim_identity("explicit-bot", "vools-retry-lead")
  assert_eq(a.raw, "explicit-bot")
  assert_eq(a.source, "explicit-agent")
  assert_false(a.implicit)
  // assignee 为空时不会退回空串身份（空身份会让 ACL 行键变成 fp("")）
  let b = acl_claim_identity("", "")
  assert_eq(b.raw, "manual")
  assert_eq(b.source, "default-manual")
  assert_true(b.implicit)
}

///|
/// execute：**核心格**。executor 缺省（=未显式给出）时必须继承任务 assignee，
/// 这正是 BUG-436 的根治点：同一条 claim→execute 链只有一个身份。
/// 旧实现取 executor 的缺省值 "manual" ⇒ 这里 raw 会是 "manual"，断言当场红。
test "BUG-436 execute 判定身份继承任务 assignee（不是 executor 的缺省值 manual）" {
  let id = acl_execute_identity("", "manual", false, "vools-retry-lead")
  assert_eq(id.raw, "vools-retry-lead")
  assert_eq(id.source, "task-assignee")
  assert_eq(id.fp(), "4e3b9eb2cd9cb473")
  assert_false(id.implicit)
  // 显式传 executor="manual" 也不当身份：它是"人工执行"的占位名，不是 agent 名
  let id2 = acl_execute_identity("", "manual", true, "vools-retry-lead")
  assert_eq(id2.raw, "vools-retry-lead")
  // 显式且非占位的 executor 才作身份（调用方自报"我是谁"）
  let id3 = acl_execute_identity("", "claude-exec", true, "vools-retry-lead")
  assert_eq(id3.raw, "claude-exec")
  assert_eq(id3.source, "executor")
  // 显式 agent 最高优先，连 executor 也压过
  let id4 = acl_execute_identity(
    "pinned", "claude-exec", true, "vools-retry-lead",
  )
  assert_eq(id4.raw, "pinned")
  assert_eq(id4.source, "explicit-agent")
}

///|
/// execute：任务还没被认领（assignee 为空）且调用方没给身份 ⇒ 退回缺省 manual，
/// 但必须**标记 implicit**（错误文案据此点破"这身份是工具编的，不可预期"）。
test "BUG-436 execute 无任何身份线索时退回缺省并标记 implicit" {
  let id = acl_execute_identity("", "", false, "")
  assert_eq(id.raw, "manual")
  assert_eq(id.source, "default-manual")
  assert_true(id.implicit)
  assert_eq(id.fp(), "020934005581bee2")
}

///|
/// **核心格**：同一任务的 claim 与 execute 两条写路径，判定身份必须逐字相同。
/// 这是 bug 标题「逐调用漂移」的直接反命题。
test "BUG-436 同任务同进程：claim 与 execute 判定身份恒一致" {
  let claim_id = acl_claim_identity("", "vools-retry-lead")
  let exec_id = acl_execute_identity("", "manual", false, "vools-retry-lead")
  assert_eq(claim_id.raw, exec_id.raw)
  assert_eq(claim_id.fp(), exec_id.fp())
  // 连续多次解析也恒一致（纯函数，无时间/进程状态参与）
  for _ in 0..<3 {
    assert_eq(
      acl_execute_identity("", "manual", false, "vools-retry-lead").fp(),
      claim_id.fp(),
    )
  }
}

///|
/// 指纹形态识别：grant 靠它决定"入参是原始身份还是指纹"。
test "BUG-436 指纹形态识别（grant 兼容路径的前置判据）" {
  assert_true(acl_id_is_fp("4e3b9eb2cd9cb473"))
  assert_true(acl_id_is_fp("020934005581bee2"))
  assert_false(acl_id_is_fp("vools-retry-lead"))
  assert_false(acl_id_is_fp("4E3B9EB2CD9CB473")) // 大写不是本仓指纹形态
  assert_false(acl_id_is_fp("4e3b9eb2cd9cb47")) // 15 位
  assert_false(acl_id_is_fp("4e3b9eb2cd9cb4730")) // 17 位
  assert_false(acl_id_is_fp("g3b9eb2cd9cb473"))
  assert_false(acl_id_is_fp(""))
}

///|
/// 拒绝文案的三个要件：原始身份（grant 用它）、指纹（对表用）、"别传指纹"警示。
/// 缺任何一个，调用方就会重演「grant 报错里那串 → 仍拒」的循环。
test "BUG-436 拒绝文案给出原始身份而非误导性指纹指引" {
  let id = acl_claim_identity("", "vools-retry-lead")
  let msg = acl_gate_fail_message(
    "ACL 默认拒绝写（can_write=0）: xxx", id, "vools-retry",
  )
  assert_true(msg.contains("vools-retry-lead"))
  assert_true(msg.contains("4e3b9eb2cd9cb473"))
  assert_true(msg.contains("来源=assignee"))
  assert_true(msg.contains("agent_acl_grant(agent_id=\"vools-retry-lead\""))
  assert_true(msg.contains("BUG-436"))
  // 缺省兜出来的身份要点明「unknown/不可预期」，别让调用方去找一个不存在的参数
  let imp = acl_gate_fail_message(
    "x",
    acl_execute_identity("", "", false, ""),
    "ns1",
  )
  assert_true(imp.contains("工具缺省"))
}

///|
/// `acl_arg_given`：区分"调用方显式给了"与"取了缺省值"——这条区分就是 BUG-436
/// 与旧实现的分水岭（旧实现把缺省值当身份用）。
test "BUG-436 acl_arg_given 区分显式入参与缺省值" {
  let args : Json = Json::object({ "executor": Json::string("claude-exec") })
  assert_true(acl_arg_given(args, "executor"))
  assert_false(acl_arg_given(args, "agent"))
  let empty : Json = Json::object({ "executor": Json::string("") })
  assert_false(acl_arg_given(empty, "executor"))
}

///|
/// **端到端机制格**（真 sqlite store，不注入桩）：把事故流程原样走一遍——
///   ① 未授权 claim → 拒（fail-closed 仍在）
///   ② grant(assignee) → claim 过
///   ③ 同一任务 execute → **过**（这条是 BUG-436 的验收格：旧实现恒拒）
///   ④ 撤权 → execute 立刻拒（证明 ③ 不是门失效导致的假绿）
///   ⑤ 该 ns 一条可写行都不剩、且 fp("manual") 那一行不可写（无幽灵身份）
///
/// 起点显式收权：同路径 temp 库会带上一轮残留，不先归零会让 ① 假绿（判例-31 同族：
/// 不可复现的锁 = 不可信）。
test "BUG-436 端到端：grant 后 execute 真的能过，撤权后真的会拒" {
  let db = "temp/bug436_acl_identity_wbtest.db"
  match @store.SqliteStore::open(db) {
    None => fail("open bug436 wbtest db failed")
    Some(store) => {
      let eng = @engine.FistEngine::new(
        store=@store.StoreBackend::sqlite(store),
      )
      assert_eq(eng.heartbeat_backend(), "sqlite")
      let ns = "bug436-wbtest"
      let now = "2026-10-27T09:00:00Z"
      let claim_id = acl_claim_identity("", "vools-retry-lead")
      // 归零基线：把这条 ns 里本轮会碰到的两行显式收权（fail-closed 起点）
      for target in [claim_id.fp(), agent_fp("manual")] {
        ignore(
          eng.agents_acl_grant(
            agent_id=target,
            ns~,
            can_read=true,
            can_write=false,
            pid_bound=false,
            now~,
            by="selftest",
          ),
        )
      }
      let task_id = match
        eng.publish(
          project_dir="temp/bug436-proj",
          description="BUG-436 e2e",
          created_by="human_steward",
          now~,
          ns~,
        ) {
        Ok(id) => id
        Err(e) => fail("publish failed: " + e)
      }
      // ① 未授权：claim 的判定身份是 assignee，can_write=0 ⇒ 拒
      assert_eq(claim_id.fp(), "4e3b9eb2cd9cb473")
      ignore(eng.agents_acl_ensure(agent_id=claim_id.fp(), ns~, now~))
      let denied = agent_write_gate(eng, claim_id, ns)
      assert_true(denied is Err(_))

      // ② grant(原始身份) ⇒ claim 门通过（grant 写的就是 gate 查的那一行）
      ignore(
        eng.agents_acl_grant(
          agent_id=claim_id.fp(),
          ns~,
          can_read=true,
          can_write=true,
          pid_bound=false,
          now~,
          by="human_steward",
        ),
      )
      assert_true(agent_write_gate(eng, claim_id, ns) is Ok(_))

      // 真认领（让任务的 assignee 落地，execute 才能继承）
      let t = match eng.claim(task_id~, assignee="vools-retry-lead", now~) {
        Ok(t) => t
        Err(e) => fail("claim failed: " + e)
      }
      let assignee = t.get_assignee().unwrap_or("")
      assert_eq(assignee, "vools-retry-lead")

      // ③ execute 的判定身份 = 任务 assignee（**核心验收格**）。
      //    走的是真实接线体：入参里没有 executor（=工具缺省 "manual"）。
      let exec_args : Json = Json::object({ "task_id": Json::string(task_id) })
      let exec_id = execute_write_identity(eng, exec_args, task_id, "manual")
      assert_eq(exec_id.raw, "vools-retry-lead")
      assert_eq(exec_id.source, "task-assignee")
      assert_eq(exec_id.fp(), claim_id.fp())
      assert_true(agent_write_gate(eng, exec_id, ns) is Ok(_))
      // 真写一把交付物：门过了还要业务也过（防"门放行但引擎拒"的假绿）。
      // deliverable 不能是占位符（"done" 会被 audit_execute_gate 拦下，同 PRE-execution gate）。
      match
        eng.execute_with_meta(
          task_id~,
          deliverable="src/server/write_gate.mbt: ACL 身份解析 + 10 格白盒锁",
          now~,
        ) {
        Ok(tt) => assert_eq(tt.status_to_string(), "执行中")
        Err(e) => fail("execute failed: " + e)
      }

      // ④ 撤权 ⇒ execute 立刻拒（门是活的，③ 不是假绿）
      ignore(
        eng.agents_acl_grant(
          agent_id=claim_id.fp(),
          ns~,
          can_read=true,
          can_write=false,
          pid_bound=false,
          now~,
          by="human_steward",
        ),
      )
      assert_true(agent_write_gate(eng, exec_id, ns) is Err(_))

      // ⑤ 幽灵身份格：旧实现会给 fp("manual") 另建一行并拿它判门。
      //    这里断言"manual 那行不可写" + "该 ns 无任何可写行"。
      assert_true(
        agent_write_gate(eng, acl_execute_identity("", "", false, ""), ns)
        is Err(_),
      )
      assert_eq(eng.agents_acl_count_writable(ns~), 0)
    }
  }
}

///|
/// **接线格**（判例-29「机制格 ≠ 实现路径格」）：纯件全绿也能被"接错参数"打回。
/// 直接断言 `src/server/server.mbt` 里 claim / execute 两条写门都喂**解析后的身份**，
/// 不再把 `assignee` / `executor` 原样喂给门（那就是 BUG-436 的旧接线）。
///
/// ⚠️ 源码文本断言，脆弱但必要：它守的是"接线还在"。变异点在 `acl_execute_identity`
/// 的调用点（`let who = execute_write_identity(`），不在注释里——本文件与
/// server.mbt 的注释都**没有**写这两个完整调用串，所以下面是真代码匹配。
test "BUG-436 接线格：写门只接受解析后的身份，不许直接喂 assignee/executor" {
  let src = @fs.read_file_to_string("src/server/server.mbt", encoding="utf8") catch {
    _ => abort("读 src/server/server.mbt 失败：接线格没跑到被测面")
  }
  // 两条写门必须都经过解析体
  assert_true(src.contains("let who = acl_claim_identity("))
  assert_true(src.contains("let who = execute_write_identity("))
  // 反向：不许再出现"把原始参数直接喂门"的旧形状
  if src.contains("agent_write_gate(eng, assignee") {
    fail("BUG-436 回退：claim 又把 assignee 原样喂给写门")
  }
  if src.contains("agent_write_gate(eng, executor") {
    fail(
      "BUG-436 回退：execute 又把 executor（缺省 manual）原样喂给写门",
    )
  }
  if src.contains("agent_write_gate(eng, agent_fp(") {
    fail(
      "BUG-436 回退：写门入参又变回原始指纹串（ACP 身份未解析）",
    )
  }
  // grant 侧：必须走指纹兼容解析，且回执要列出真实写入的行
  assert_true(src.contains("granted_rows"))
  assert_true(src.contains("acl_id_is_fp(agent_id)"))
}
