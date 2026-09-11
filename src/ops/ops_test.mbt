/// ops_test.mbt —— M4 运维四件套（conflicts/heartbeat/heal/cleanup）测试
///
/// 覆盖验收标准：
///   - conflicts 拦截重复 claim；
///   - heartbeat 上报后超时静默 -> heal 回滚为已领取（可重派）；
///   - cleanup 清理超过保留期的 archived 任务，未过期的不动。

/// 快速构建：含 T0 根任务的引擎（T0 已发布，claim 后可用）。
fn test_engine() -> @engine.FistEngine {
  let e = @engine.FistEngine::new()
  ignore(e.publish(
    project_dir="/demo",
    description="测试根任务",
    created_by="human_steward",
    now="2026-09-05T00:00:00Z",
  ))
  e
}

test "ops: iso_to_secs 解析与比较" {
  let t0 = iso_to_secs("2026-09-05T00:00:00Z")
  let t1 = iso_to_secs("2026-09-05T00:10:00Z")
  let t2 = iso_to_secs("2026-09-06T00:00:00Z")
  assert_true(t0 > 0)
  assert_true(t1 - t0 == 600)
  assert_true(t2 - t0 == 86400)
  assert_true(iso_to_secs("bad-ts") == -1)
}

test "ops: conflicts 拦截重复 claim" {
  let e = test_engine()
  // T0 初始待领取，可认领
  assert_true(check_claim(e, "T0", "worker-a").is_ok())
  ignore(e.claim(task_id="T0", assignee="worker-a", now="2026-09-05T00:00:01Z"))
  // 同一人重复认领被拒（--no-takeover）
  let dup = check_claim(e, "T0", "worker-a")
  assert_true(dup.is_err())
  // 他人认领被拒
  let other = check_claim(e, "T0", "worker-b")
  assert_true(other.is_err())
  match other {
    Err(msg) => assert_true(msg.contains("worker-a"))
    Ok(_) => abort("应返回冲突")
  }
  // 不存在的任务
  assert_true(check_claim(e, "T99", "worker-a").is_err())
}

test "ops: conflicts 持有审计 list_holdings" {
  let e = test_engine()
  ignore(e.claim(task_id="T0", assignee="worker-a", now="2026-09-05T00:00:01Z"))
  let held = list_holdings(e, "worker-a")
  assert_true(held.length() == 1)
  assert_true(held[0].get_id() == "T0")
  assert_true(list_holdings(e, "worker-b").is_empty())
}

test "ops: heartbeat 上报后未超时 -> heal 不回滚" {
  let e = test_engine()
  let hb = Heartbeat::new()
  ignore(e.claim(task_id="T0", assignee="worker-a", now="2026-09-05T00:00:01Z"))
  ignore(e.execute(task_id="T0", deliverable="d", now="2026-09-05T00:00:02Z"))
  hb.beat("T0", now="2026-09-05T00:00:02Z")
  // 20 秒后 < 600 秒超时：不回滚
  let healed = heal_stale_tasks(e, hb, "2026-09-05T00:00:22Z", timeout_sec=600)
  assert_true(healed.is_ok())
  match healed {
    Ok(list) => assert_true(list.is_empty())
    Err(_) => abort("heal 不应失败")
  }
  match e.get_task("T0") {
    Some(t) => assert_true(t.get_status().to_string() == "执行中")
    None => abort("T0 应存在")
  }
}

test "ops: 超时静默 -> heal 回滚为已领取（可重派）" {
  let e = test_engine()
  let hb = Heartbeat::new()
  ignore(e.claim(task_id="T0", assignee="worker-a", now="2026-09-05T00:00:01Z"))
  ignore(e.execute(task_id="T0", deliverable="d", now="2026-09-05T00:00:02Z"))
  hb.beat("T0", now="2026-09-05T00:00:02Z")
  // 1000 秒后 > 600 秒超时：回滚
  let healed = heal_stale_tasks(e, hb, "2026-09-05T00:16:42Z", timeout_sec=600)
  match healed {
    Ok(list) => {
      assert_true(list.length() == 1)
      assert_true(list[0] == "T0")
      assert_true(hb.last_seen_of("T0") == "") // 心跳已清
    }
    Err(_) => abort("heal 不应失败")
  }
  match e.get_task("T0") {
    Some(t) => {
      assert_true(t.get_status().to_string() == "已领取") // 可重派
      match t.get_assignee() {
        Some(a) => assert_true(a == "worker-a")
        None => abort("回滚不应清空 assignee")
      }
    }
    None => abort("T0 应存在")
  }
}

test "ops: 从未上报心跳的执行中任务 -> heal 视为 no_signal 回滚" {
  let e = test_engine()
  let hb = Heartbeat::new()
  ignore(e.claim(task_id="T0", assignee="worker-a", now="2026-09-05T00:00:01Z"))
  ignore(e.execute(task_id="T0", deliverable="d", now="2026-09-05T00:00:02Z"))
  let healed = heal_stale_tasks(e, hb, "2026-09-05T00:00:03Z", timeout_sec=600)
  match healed {
    Ok(list) => {
      assert_true(list.length() == 1)
      assert_true(list[0] == "T0")
    }
    Err(_) => abort("heal 不应失败")
  }
}

test "ops: cleanup 清理过期归档、保留未过期" {
  let e = test_engine()
  // 构建：T0 -> claim/execute/submit/verify/archive（归档于 09-05）
  ignore(e.claim(task_id="T0", assignee="worker-a", now="2026-09-05T00:00:01Z"))
  ignore(e.execute(task_id="T0", deliverable="d1", now="2026-09-05T00:00:02Z"))
  ignore(e.submit(task_id="T0", now="2026-09-05T00:00:03Z"))
  ignore(e.verify(task_id="T0", verifier="human", now="2026-09-05T00:00:04Z"))
  ignore(e.archive(task_id="T0", by="human_steward", now="2026-09-05T00:00:05Z"))
  // 再发布一个近期归档任务 T1（09-20 归档）
  ignore(e.publish(project_dir="/demo2", description="任务二", created_by="human_steward", now="2026-09-20T00:00:00Z"))
  // 根任务 id 恒定 T0，T1 需走手工造数：直接 publish 会冲突，改用 claim 后新发布？
  // 说明：publish 固定 id=T0，故此处造第二个归档任务需绕开；本用例只需验证 T0 过期待清。
  // 以 now=2026-10-01 执行保留期 10 天清理：T0（09-05 归档）距今 26 天 > 10 天 -> 清理
  let removed = cleanup_archived(e, "2026-10-01T00:00:00Z", retention_days=10)
  match removed {
    Ok(list) => {
      assert_true(list.length() == 1)
      assert_true(list[0] == "T0")
      assert_true(e.get_task("T0") is None)
    }
    Err(_) => abort("cleanup 不应失败")
  }
}

test "ops: cleanup 保留期内不动" {
  let e = test_engine()
  ignore(e.claim(task_id="T0", assignee="worker-a", now="2026-09-05T00:00:01Z"))
  ignore(e.execute(task_id="T0", deliverable="d1", now="2026-09-05T00:00:02Z"))
  ignore(e.submit(task_id="T0", now="2026-09-05T00:00:03Z"))
  ignore(e.verify(task_id="T0", verifier="human", now="2026-09-05T00:00:04Z"))
  ignore(e.archive(task_id="T0", by="human_steward", now="2026-09-05T00:00:05Z"))
  // 保留期 40 天：09-05 距今（10-01）26 天 < 40 -> 不清理
  let removed = cleanup_archived(e, "2026-10-01T00:00:00Z", retention_days=40)
  match removed {
    Ok(list) => {
      assert_true(list.is_empty())
      assert_true(e.get_task("T0") is Some(_))
    }
    Err(_) => abort("cleanup 不应失败")
  }
}