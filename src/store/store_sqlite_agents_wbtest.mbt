///|
// T0r5 白盒锁：agent 指纹注册表 + 默认 fail-closed ACL + PID 换绑 + 陈旧扫描。
//
// 为什么锁这些点：agent 身份与 ACL 是本轮"agent-fingerprint-pid-guard"的承载面，
// 任何一条语义悄悄回退（默认 can_write 变 1、pid_bound 不校验、stale 把刚心跳的判死）
// 都会把"默认拒绝写"这个安全承诺拆掉，而黑盒测试看不到 agents 表内里，
// 只能靠 wbtest 直接戳 `s.db` / 方法返回值。
// 每条用独立库文件，避免测试相互污染；`temp/` 目录已存在（其它 store wbtest 同用）。

///|
test "agents: register + get 首次出现登记、重复注册只刷新 pid/last_seen" {
  match SqliteStore::open("temp/agents_register_wb.db") {
    None => fail("sqlite open 失败：判据没跑到被测面")
    Some(s) => {
      // 首次注册
      let r1 = s.agents_register(
        agent_id="fp-agent-a",
        agent_type="server",
        role="Leader",
        soldier="通信兵",
        pubkey_fp="",
        pid=1001,
        now="2026-10-22T00:00:00Z",
      )
      assert_eq(r1, Ok(()))
      match s.agents_get("fp-agent-a") {
        None => fail("首次注册后 agents_get 必须命中")
        Some(a) => {
          assert_eq(a.agent_id, "fp-agent-a")
          assert_eq(a.pid, 1001)
          assert_eq(a.status, "active")
          assert_eq(a.first_seen, "2026-10-22T00:00:00Z")
          assert_eq(a.last_seen, "2026-10-22T00:00:00Z")
        }
      }
      // 重复注册：身份不变（first_seen 不覆盖），pid 换绑
      let r2 = s.agents_register(
        agent_id="fp-agent-a",
        agent_type="server",
        role="Leader",
        soldier="通信兵",
        pubkey_fp="",
        pid=2002,
        now="2026-10-22T01:00:00Z",
      )
      assert_eq(r2, Ok(()))
      match s.agents_get("fp-agent-a") {
        None => fail("重复注册后仍须命中")
        Some(a) => {
          assert_eq(a.first_seen, "2026-10-22T00:00:00Z")
          assert_eq(a.pid, 2002)
          assert_eq(a.last_seen, "2026-10-22T01:00:00Z")
        }
      }
      // 未注册的 agent_get 返回 None（AgentRecord 无 Eq/Debug，用 match 判）
      match s.agents_get("fp-ghost") {
        None => ()
        Some(_) => fail("未注册的 agent_get 必须返回 None")
      }
    }
  }
}

///|
test "agents_set_pid: 换绑后 agents.pid 更新" {
  match SqliteStore::open("temp/agents_setpid_wb.db") {
    None => fail("sqlite open 失败")
    Some(s) => {
      ignore(
        s.agents_register(
          agent_id="fp-b",
          agent_type="agent",
          role="Executor",
          soldier="工兵",
          pubkey_fp="",
          pid=1,
          now="2026-10-22T00:00:00Z",
        ),
      )
      assert_eq(s.agents_set_pid(agent_id="fp-b", pid=777), Ok(()))
      match s.agents_get("fp-b") {
        None => fail("换绑后仍须命中")
        Some(a) => assert_eq(a.pid, 777)
      }
    }
  }
}

///|
test "agents_acl_ensure + agents_acl_check: 默认 can_write=0 → 写面 Err（fail-closed）" {
  match SqliteStore::open("temp/agents_acl_default_wb.db") {
    None => fail("sqlite open 失败")
    Some(s) => {
      // 默认档用专属 agent（本测试从不对它 grant），保证重复执行时
      // `INSERT OR IGNORE` 不会读到上一次 grant 留下的 can_write=1。
      let agent_id = "fp-c-default"
      ignore(
        s.agents_register(
          agent_id~,
          agent_type="agent",
          role="Executor",
          soldier="工兵",
          pubkey_fp="",
          pid=123,
          now="2026-10-22T00:00:00Z",
        ),
      )
      assert_eq(
        s.agents_acl_ensure(agent_id~, ns="default", now="2026-10-22T00:00:00Z"),
        Ok(()),
      )
      // 默认：读放行、写拒绝
      assert_eq(
        s.agents_acl_check(
          agent_id~,
          ns="default",
          write=false,
          current_pid=123,
        ),
        Ok(()),
      )
      let wr = s.agents_acl_check(
        agent_id~,
        ns="default",
        write=true,
        current_pid=123,
      )
      match wr {
        Err(_) => ()
        Ok(_) => fail("默认 ACL 的 can_write=0，写面必须 Err")
      }
      // pid_bound 档：grant 之后 pid 换了进程 → 拒绝
      let gid = "fp-c-bound"
      ignore(
        s.agents_register(
          agent_id=gid,
          agent_type="agent",
          role="Executor",
          soldier="工兵",
          pubkey_fp="",
          pid=123,
          now="2026-10-22T00:00:00Z",
        ),
      )
      assert_eq(
        s.agents_acl_ensure(
          agent_id=gid,
          ns="default",
          now="2026-10-22T00:00:00Z",
        ),
        Ok(()),
      )
      assert_eq(
        s.agents_acl_grant(
          agent_id=gid,
          ns="default",
          can_read=true,
          can_write=true,
          pid_bound=true,
          now="2026-10-22T00:00:00Z",
          by="commander",
        ),
        Ok(()),
      )
      match
        s.agents_acl_check(
          agent_id=gid,
          ns="default",
          write=true,
          current_pid=999,
        ) {
        Err(_) => ()
        Ok(_) => fail("pid_bound 已绑定，换了 pid 必须拒绝写")
      }
      // 同一 pid → 放行
      assert_eq(
        s.agents_acl_check(
          agent_id=gid,
          ns="default",
          write=true,
          current_pid=123,
        ),
        Ok(()),
      )
    }
  }
}

///|
test "agents_acl_grant: 收权 can_write=false 落 revoked_at/revoked_by" {
  match SqliteStore::open("temp/agents_acl_revoke_wb.db") {
    None => fail("sqlite open 失败")
    Some(s) => {
      let agent_id = "fp-d"
      ignore(
        s.agents_acl_ensure(agent_id~, ns="default", now="2026-10-22T00:00:00Z"),
      )
      assert_eq(
        s.agents_acl_grant(
          agent_id~,
          ns="default",
          can_read=true,
          can_write=false,
          pid_bound=false,
          now="2026-10-22T01:00:00Z",
          by="commander",
        ),
        Ok(()),
      )
      match
        s.agents_acl_check(agent_id~, ns="default", write=true, current_pid=1) {
        Err(_) => ()
        Ok(_) => fail("can_write=false 必须拒绝写")
      }
    }
  }
}

///|
test "agents_stale_check: last_seen 早于 cutoff 判 stale" {
  match SqliteStore::open("temp/agents_stale_wb.db") {
    None => fail("sqlite open 失败")
    Some(s) => {
      ignore(
        s.agents_register(
          agent_id="fp-fresh",
          agent_type="agent",
          role="Executor",
          soldier="工兵",
          pubkey_fp="",
          pid=1,
          now="2026-10-22T01:00:00Z",
        ),
      )
      ignore(
        s.agents_register(
          agent_id="fp-old",
          agent_type="agent",
          role="Executor",
          soldier="工兵",
          pubkey_fp="",
          pid=2,
          now="2026-10-01T00:00:00Z",
        ),
      )
      // cutoff = 2026-10-22T00:30:00Z：fp-old (10-01) 早于 cutoff → stale；fp-fresh (10-22T01) 晚 → 不 stale
      let stale = s.agents_stale_check("2026-10-22T00:30:00Z")
      assert_eq(stale.length(), 1)
      assert_eq(stale[0].agent_id, "fp-old")
    }
  }
}

///|
/// BUG-411 测试库清理：每个测试用独立库文件，重复跑时先 clear 掉上次残留。
/// 为什么需要：不清理时第二次跑锁 1/锁 3 的「默认应为 0」前置断言会假红
/// （库里有上次 grant 留下的 can_write=1 行），与本缺陷本身无关。
fn _reset_bug411(path : String) -> Unit {
  // 直接删库文件而不是 `Store::clear`：实测 `clear` 不清 agent_acl 表，
  // 第二次跑时残留的 can_write=1 行会让锁 1/锁 3 的「默认应为 0」前置断言假红。
  if @fs.path_exists(path) {
    @fs.remove_file(path) catch {
      _ => ()
    }
  }
}

///|
/// BUG-411 锁 1：新建 ns 无人可写 ⇒ count_writable=0 且 write 门拒绝。
/// 成对：与锁 2 互为反例（0 → 1）。
test "bug411_no_writer_means_claim_would_be_rejected" {
  _reset_bug411("temp/bug411_lock1.db")
  match SqliteStore::open("temp/bug411_lock1.db") {
    None => fail("sqlite open 失败：判据没跑到被测面")
    Some(s) => {
      ignore(
        s.agents_acl_ensure(
          agent_id="agent-x",
          ns="bug411-ns-1",
          now="2026-10-26T00:00:00Z",
        ),
      )
      if s.agents_acl_count_writable(ns="bug411-ns-1") != 0 {
        fail("BUG-411: 新建 ns 应 0 个可写 agent")
      }
      match
        s.agents_acl_check(
          agent_id="agent-x",
          ns="bug411-ns-1",
          write=true,
          current_pid=0,
        ) {
        Ok(_) =>
          fail("BUG-411: can_write=0 却放行写 —— fail-closed 漏了")
        Err(_) => ()
      }
    }
  }
}

///|
/// BUG-411 锁 2：授权后 ⇒ count_writable=1 且 write 门放行。
test "bug411_granted_writer_means_claim_ready" {
  _reset_bug411("temp/bug411_lock2.db")
  match SqliteStore::open("temp/bug411_lock2.db") {
    None => fail("sqlite open 失败：判据没跑到被测面")
    Some(s) => {
      ignore(
        s.agents_acl_ensure(agent_id="agent-y", ns="bug411-ns-2", now="T0"),
      )
      ignore(
        s.agents_acl_grant(
          agent_id="agent-y",
          ns="bug411-ns-2",
          can_read=true,
          can_write=true,
          pid_bound=false,
          now="T1",
          by="human_steward",
        ),
      )
      if s.agents_acl_count_writable(ns="bug411-ns-2") != 1 {
        fail("BUG-411: 授权后应 1 个可写 agent")
      }
      match
        s.agents_acl_check(
          agent_id="agent-y",
          ns="bug411-ns-2",
          write=true,
          current_pid=0,
        ) {
        Ok(_) => ()
        Err(_) => fail("BUG-411: 已授权却被拒")
      }
    }
  }
}

///|
/// BUG-411 锁 3（变异对照，判例-29）：ns 过滤真在生效。
/// 抓的变异：把 count_writable 的 `WHERE ns = ?` 删掉 ⇒ ns=OTHER 那一格会返回 1 ⇒ 必红。
test "bug411_count_writable_ns_filter_mutation" {
  _reset_bug411("temp/bug411_lock3.db")
  match SqliteStore::open("temp/bug411_lock3.db") {
    None => fail("sqlite open 失败：判据没跑到被测面")
    Some(s) => {
      ignore(
        s.agents_acl_ensure(agent_id="agent-z", ns="bug411-ns-3", now="T0"),
      )
      if s.agents_acl_count_writable(ns="bug411-ns-3") != 0 {
        fail("前置不成立：默认应为 0")
      }
      ignore(
        s.agents_acl_grant(
          agent_id="agent-z",
          ns="bug411-ns-3",
          can_read=true,
          can_write=true,
          pid_bound=false,
          now="T1",
          by="test",
        ),
      )
      if s.agents_acl_count_writable(ns="bug411-ns-3") != 1 {
        fail("BUG-411: count 与 check 口径不同源")
      }
      // 【变异对照核心】ns 过滤若被删，这里会拿到 1
      if s.agents_acl_count_writable(ns="bug411-ns-OTHER") != 0 {
        fail(
          "BUG-411: count_writable 的 ns 过滤失效 —— WHERE ns = ? 被删或被绕过",
        )
      }
    }
  }
}

///|
/// BUG-423 锁 1：`agents_register` 的 `ON CONFLICT` **可抬高** role
///
/// 场景：低权路径（claim/execute 的 `agent_touch_first_seen`）先把某身份登记成
/// Executor，之后 HumanSteward 显式注册成 HumanSteward ⇒ 必须能抬上去。
/// 若实现把 `role` 从 DO UPDATE 里彻底删掉（原实现），本格必红。
test "bug423_register_can_raise_executor_to_steward" {
  // 清场（与 `_reset_bug411` 同款理由）：本格用固定路径 `temp/bug423_raise.db`，
  // 第二次跑时库里残留上一轮的 `role=HumanSteward`，第一步的「首次应是 Executor」
  // 前置断言必假红（实测连跑两次：76/76 → 75/76，红的就是本格）。
  if @fs.path_exists("temp/bug423_raise.db") {
    @fs.remove_file("temp/bug423_raise.db") catch {
      _ => ()
    }
  }
  match SqliteStore::open("temp/bug423_raise.db") {
    None => fail("sqlite open 失败：判据没跑到被测面")
    Some(s) => {
      // 第一步：低权路径先把它登记成 Executor（模拟 claim 的 agent_touch_first_seen）
      match
        s.agents_register(
          agent_id="fp-steward-x",
          agent_type="server",
          role="Executor",
          soldier="工兵",
          pubkey_fp="",
          pid=2001,
          now="T1",
        ) {
        Err(e) => fail("首次登记失败：" + e)
        Ok(_) => ()
      }
      match s.agents_get("fp-steward-x") {
        None => fail("首次登记后必须存在")
        Some(a) =>
          if a.role != "Executor" {
            fail("前置不成立：首次应是 Executor，实得 " + a.role)
          }
      }
      // 第二步：显式注册抬高为 HumanSteward ⇒ 必须抬上去
      match
        s.agents_register(
          agent_id="fp-steward-x",
          agent_type="server",
          role="HumanSteward",
          soldier="工兵",
          pubkey_fp="",
          pid=2002,
          now="T2",
        ) {
        Err(e) => fail("二次登记失败：" + e)
        Ok(_) => ()
      }
      match s.agents_get("fp-steward-x") {
        None => fail("二次登记后必须存在")
        Some(a) =>
          if a.role != "HumanSteward" {
            fail(
              "BUG-423: 显式注册没能抬高角色（实得 " +
              a.role +
              "）",
            )
          }
      }
    }
  }
}

///|
/// BUG-423 锁 2（**核心反例格**）：`ON CONFLICT` **防降级**
///
/// 场景：某身份已是 HumanSteward，低权路径（claim 传 Executor）又来登记一次
/// ⇒ **必须仍是 HumanSteward**，不许被打回 Executor。
///
/// 这正是本条 bug 的原始形状：`agent_touch_first_seen` 对任意 assignee 写
/// `role="Executor"`，若不防降级，统帅被这样注册过后永久锁死在 HumanSteward 面外。
test "bug423_register_does_not_downgrade_steward" {
  match SqliteStore::open("temp/bug423_nodown.db") {
    None => fail("sqlite open 失败：判据没跑到被测面")
    Some(s) => {
      // 先正当地登记成 HumanSteward
      match
        s.agents_register(
          agent_id="fp-steward-y",
          agent_type="human",
          role="HumanSteward",
          soldier="后勤兵",
          pubkey_fp="",
          pid=3001,
          now="T1",
        ) {
        Err(e) => fail("首次登记失败：" + e)
        Ok(_) => ()
      }
      // 低权路径再来一次（模拟 claim 的 agent_touch_first_seen 传 Executor）
      match
        s.agents_register(
          agent_id="fp-steward-y",
          agent_type="server",
          role="Executor",
          soldier="工兵",
          pubkey_fp="",
          pid=3002,
          now="T2",
        ) {
        Err(e) => fail("二次登记失败：" + e)
        Ok(_) => ()
      }
      match s.agents_get("fp-steward-y") {
        None => fail("二次登记后必须存在")
        Some(a) => {
          if a.role != "HumanSteward" {
            fail(
              "BUG-423 未修：HumanSteward 被低权路径降级为 " +
              a.role +
              "（统帅会永久锁死在独占面外）",
            )
          }
          // 顺带确认心跳字段仍被刷新（防「一刀切不更新」的过度修复）
          if a.pid != 3002 {
            fail(
              "过度修复：pid 应被刷新为 3002，实得 " +
              a.pid.to_string(),
            )
          }
        }
      }
    }
  }
}

///|
/// BUG-423 锁 3：Leader 同样不被 Executor 降级（不止 HumanSteward 一档）
test "bug423_register_does_not_downgrade_leader" {
  match SqliteStore::open("temp/bug423_leader.db") {
    None => fail("sqlite open 失败：判据没跑到被测面")
    Some(s) => {
      let _ = s.agents_register(
        agent_id="fp-leader-z",
        agent_type="human",
        role="Leader",
        soldier="通信兵",
        pubkey_fp="",
        pid=4001,
        now="T1",
      )
      let _ = s.agents_register(
        agent_id="fp-leader-z",
        agent_type="server",
        role="Executor",
        soldier="工兵",
        pubkey_fp="",
        pid=4002,
        now="T2",
      )
      match s.agents_get("fp-leader-z") {
        None => fail("必须存在")
        Some(a) =>
          if a.role != "Leader" {
            fail("BUG-423: Leader 被降级为 " + a.role)
          }
      }
    }
  }
}

///|
/// BUG-422 锁 1：`agents_role_for_judgment` 把「本进程自身份」记录剔出角色裁决。
///
/// 病灶：角色裁决的查表键是**调用方自报的名字**，而 `agents` 表里唯一的高角色记录
/// 恰好是 server 给自己登记的那一条（`agent_type="server"`, `role="Leader"`）⇒
/// `agent="fist-mbt"` 直接继承 Leader（实测 ALLOWED on `src/engine/` · `src/core/`）。
///
/// 本格钉的是**取数面**（判例-29：机制格 ≠ 实现路径格）：
///   ① server 自身份 ⇒ `agents_get` 有记录（证明「不是查不到」）但裁决面 None
///   ② 非 server 类型的 Leader ⇒ 裁决面 Some("Leader")（便利性没被一刀切掉）
///   ③ 纯谓词 `agent_record_is_process_self` 大小写无关（"SERVER" 也算自身份）
///   ④ `HumanSteward` 记录**在 store 层照旧可读** —— 「不可继承」是 engine 侧政策
///      （`inheritable_role`），存取层不替政策做决定
test "bug422_agents_role_for_judgment_filters_process_self" {
  match SqliteStore::open("temp/bug422_agents_judgment_wb.db") {
    None => fail("sqlite open 失败：判据没跑到被测面")
    Some(s) => {
      // ① server 自身份（复刻 server.mbt 启动注册）
      let self_id = "fp-bug422-server-self"
      let _ = s.agents_register(
        agent_id=self_id,
        agent_type="server",
        role="Leader",
        soldier="通信兵",
        pubkey_fp="",
        pid=5001,
        now="T1",
      )
      match s.agents_get(self_id) {
        None =>
          abort("★判据没跑到被测面：server 自身份记录没写成")
        Some(a) => assert_eq(a.role, "Leader")
      }
      match s.agents_role_for_judgment(self_id) {
        Some(r) =>
          fail(
            "★BUG-422 未修：server 自身份仍进角色裁决（role=" +
            r +
            "）",
          )
        None => ()
      }
      // ② 非 server 类型的 Leader：仍可裁决（防修过头）
      let lane_id = "fp-bug422-lane-leader"
      let _ = s.agents_register(
        agent_id=lane_id,
        agent_type="executor",
        role="Leader",
        soldier="工兵",
        pubkey_fp="",
        pid=5002,
        now="T1",
      )
      match s.agents_role_for_judgment(lane_id) {
        None =>
          fail(
            "★修过头：非 server 类型的 Leader 记录也被剔除了",
          )
        Some(r) => assert_eq(r, "Leader")
      }
      // ③ 纯谓词大小写无关
      let _ = s.agents_register(
        agent_id="fp-bug422-upper",
        agent_type="SERVER",
        role="Leader",
        soldier="通信兵",
        pubkey_fp="",
        pid=5003,
        now="T1",
      )
      match s.agents_get("fp-bug422-upper") {
        None => abort("登记失败：判据没跑到被测面")
        Some(a) =>
          if !agent_record_is_process_self(a) {
            fail(
              "agent_record_is_process_self 大小写敏感 —— agent_type=\"SERVER\" 漏判",
            )
          }
      }
      match s.agents_role_for_judgment("fp-bug422-upper") {
        Some(_) =>
          fail("★大小写漏判：agent_type=\"SERVER\" 仍进角色裁决")
        None => ()
      }
      // ④ HumanSteward 记录在 store 层照旧可读（政策在 engine 侧）
      let hs_id = "fp-bug422-hs"
      let _ = s.agents_register(
        agent_id=hs_id,
        agent_type="agent",
        role="HumanSteward",
        soldier="工兵",
        pubkey_fp="",
        pid=5004,
        now="T1",
      )
      match s.agents_role_for_judgment(hs_id) {
        None =>
          fail(
            "store 层不该替政策决定 —— HS 记录应原样返回给 engine",
          )
        Some(r) => assert_eq(r, "HumanSteward") // engine 侧 inheritable_role 会拒绝它
      }
      // ⑤ 未登记 ⇒ None
      match s.agents_role_for_judgment("fp-bug422-ghost") {
        Some(_) => fail("未登记的 agent 必须返回 None")
        None => ()
      }
    }
  }
}
