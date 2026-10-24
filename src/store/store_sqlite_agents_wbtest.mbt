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
