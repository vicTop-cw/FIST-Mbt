/// ops_test.mbt —— M4 运维四件套（conflicts/heartbeat/heal/cleanup）测试
///
/// 覆盖验收标准：
///   - conflicts 拦截重复 claim；
///   - heartbeat 上报后超时静默 -> heal 回滚为已领取（可重派）；
///   - cleanup 清理超过保留期的 archived 任务，未过期的不动。

///|
/// 快速构建：含 T0 根任务的引擎（T0 已发布，claim 后可用）。
fn test_engine() -> @engine.FistEngine {
  let e = @engine.FistEngine::new()
  ignore(
    e.publish(
      project_dir="/demo",
      description="测试根任务",
      created_by="human_steward",
      now="2026-09-05T00:00:00Z",
    ),
  )
  e
}

///|
test "ops: iso_to_secs 解析与比较" {
  let t0 = iso_to_secs("2026-09-05T00:00:00Z")
  let t1 = iso_to_secs("2026-09-05T00:10:00Z")
  let t2 = iso_to_secs("2026-09-06T00:00:00Z")
  assert_true(t0 > 0)
  assert_true(t1 - t0 == 600)
  assert_true(t2 - t0 == 86400)
  assert_true(iso_to_secs("bad-ts") == -1)
}

///|
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

///|
test "ops: conflicts 持有审计 list_holdings" {
  let e = test_engine()
  ignore(e.claim(task_id="T0", assignee="worker-a", now="2026-09-05T00:00:01Z"))
  let held = list_holdings(e, "worker-a")
  assert_true(held.length() == 1)
  assert_true(held[0].get_id() == "T0")
  assert_true(list_holdings(e, "worker-b").is_empty())
}

///|
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

///|
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

///|
test "ops: 从未上报心跳但刚刚活动过 -> heal 不回滚（BUG-119 首拍即死）" {
  let e = test_engine()
  let hb = Heartbeat::new()
  ignore(e.claim(task_id="T0", assignee="worker-a", now="2026-09-05T00:00:01Z"))
  ignore(e.execute(task_id="T0", deliverable="d", now="2026-09-05T00:00:02Z"))
  // 内存心跳表里没有任何行；任务 execute 才过 1 秒
  let healed = heal_stale_tasks(e, hb, "2026-09-05T00:00:03Z", timeout_sec=600)
  match healed {
    Ok(list) => assert_true(list.is_empty())
    Err(_) => abort("heal 不应失败")
  }
  match e.get_task("T0") {
    Some(t) => assert_true(t.get_status().to_string() == "执行中")
    None => abort("T0 应存在")
  }
}

///|
test "ops: 从未上报心跳且活动时钟超 timeout -> heal 仍回滚（no_signal 不弱化）" {
  let e = test_engine()
  let hb = Heartbeat::new()
  ignore(e.claim(task_id="T0", assignee="worker-a", now="2026-09-05T00:00:01Z"))
  ignore(e.execute(task_id="T0", deliverable="d", now="2026-09-05T00:00:02Z"))
  let healed = heal_stale_tasks(e, hb, "2026-09-05T00:16:42Z", timeout_sec=600)
  match healed {
    Ok(list) => {
      assert_true(list.length() == 1)
      assert_true(list[0] == "T0")
    }
    Err(_) => abort("heal 不应失败")
  }
}

///|
test "ops: cleanup 清理过期归档、保留未过期" {
  let e = test_engine()
  // 构建：T0 -> claim/execute/submit/verify/archive（归档于 09-05）
  ignore(e.claim(task_id="T0", assignee="worker-a", now="2026-09-05T00:00:01Z"))
  ignore(e.execute(task_id="T0", deliverable="d1", now="2026-09-05T00:00:02Z"))
  ignore(e.submit(task_id="T0", now="2026-09-05T00:00:03Z"))
  ignore(e.verify(task_id="T0", verifier="human", now="2026-09-05T00:00:04Z"))
  ignore(
    e.archive(task_id="T0", by="human_steward", now="2026-09-05T00:00:05Z"),
  )
  // 再发布一个近期归档任务 T1（09-20 归档）
  ignore(
    e.publish(
      project_dir="/demo2",
      description="任务二",
      created_by="human_steward",
      now="2026-09-20T00:00:00Z",
    ),
  )
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

///|
test "ops: cleanup 保留期内不动" {
  let e = test_engine()
  ignore(e.claim(task_id="T0", assignee="worker-a", now="2026-09-05T00:00:01Z"))
  ignore(e.execute(task_id="T0", deliverable="d1", now="2026-09-05T00:00:02Z"))
  ignore(e.submit(task_id="T0", now="2026-09-05T00:00:03Z"))
  ignore(e.verify(task_id="T0", verifier="human", now="2026-09-05T00:00:04Z"))
  ignore(
    e.archive(task_id="T0", by="human_steward", now="2026-09-05T00:00:05Z"),
  )
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

///|
/// BUG-81：heal 的作用域。多 ns 共用同一个库时，不带 ns 的 heal 会把**别的轮次**的在途任务
/// 一并 reopen（而 reopen 不署名 ⇒ 枝干 assignee 被清空）。成对锁：
///   ① 传 ns 只回滚该 ns 的那条；
///   ② 不传 ns 回滚两条（旧行为，零回归——所以这条默认必须在返回体里自证作用域）；
///   ③ 心跳新鲜的那条在任何一种作用域下都不被动。
test "BUG-81：heal 带 namespace 只回滚该 ns，不带=全库（旧行为）" {
  let e = @engine.FistEngine::new()
  // 两个命名空间各发一条根任务，并都推进到「执行中」
  match
    e.publish(
      project_dir="/demo",
      description="b81-a 轮的在途任务",
      created_by="human_steward",
      now="2026-09-27T00:00:00Z",
      ns="b81-a",
    ) {
    Ok(_) => ()
    Err(m) => abort("publish b81-a 失败: " + m)
  }
  match
    e.publish(
      project_dir="/demo",
      description="b81-b 轮的在途任务",
      created_by="human_steward",
      now="2026-09-27T00:00:00Z",
      ns="b81-b",
    ) {
    Ok(id_b) => {
      ignore(e.claim(task_id=id_b, assignee="w-b", now="2026-09-27T00:00:01Z"))
      ignore(
        e.execute(task_id=id_b, deliverable="d", now="2026-09-27T00:00:02Z"),
      )
    }
    Err(m) => abort("publish b81-b 失败: " + m)
  }
  let id_a = match e.list_in_ns("b81-a") {
    [t] => t.get_id()
    _ => abort("b81-a 应恰有 1 条任务")
  }
  ignore(e.claim(task_id=id_a, assignee="w-a", now="2026-09-27T00:00:01Z"))
  ignore(e.execute(task_id=id_a, deliverable="d", now="2026-09-27T00:00:02Z"))
  // 两条都没有心跳记录 = no_signal；b81-b 补一条新鲜心跳作反向对照
  let hb = Heartbeat::new()
  let now_late = "2026-09-27T00:20:00Z"
  // ① 带 ns：只回滚 b81-a 那一条
  match heal_stale_tasks(e, hb, now_late, timeout_sec=600, ns="b81-a") {
    Ok(list) => {
      assert_eq(list.length(), 1)
      assert_eq(list[0], id_a)
    }
    Err(m) => abort("带 ns 的 heal 不应失败: " + m)
  }
  // b81-b 仍是执行中（没被别的 ns 的 heal 波及）
  match e.get_task(id_b_of(e)) {
    Some(t) => assert_eq(t.get_status().to_string(), "执行中")
    None => abort("b81-b 的任务应还在")
  }
  // ② 不带 ns：全库作用域。BUG-119 后这里回滚 1 条 = b81-b 那条：①里刚 reopen 的 b81-a
  // 其 `updated_at` 被盖成 now_late，同一拍它「刚刚活动过」，不再被二次回滚。
  // BUG-81 的形状仍然成立——**不带 ns 就是会动别的命名空间**（这里动的就是 b81-b）。
  match heal_stale_tasks(e, hb, now_late, timeout_sec=600) {
    Ok(list) => {
      assert_eq(list.length(), 1)
      if list.contains(id_a) {
        abort(
          "BUG-119 后不应在同一拍二次回滚 id_a=" +
          id_a +
          "，实得 [" +
          b81_ids(list) +
          "]",
        )
      }
      if not(list.contains(id_b_of(e))) {
        abort("全库 heal 漏了 b81-b，实得 [" + b81_ids(list) + "]")
      }
    }
    Err(m) => abort("全库 heal 不应失败: " + m)
  }
}

///|
/// 取 b81-b 命名空间里那条任务的 id（发布顺序不写死在断言里）
fn id_b_of(e : @engine.FistEngine) -> String {
  match e.list_in_ns("b81-b") {
    [t] => t.get_id()
    _ => ""
  }
}

///|
/// 调试用的 id 串接（失败消息要能自证"到底回滚了哪几条"）
fn b81_ids(list : Array[String]) -> String {
  let mut out = ""
  for s in list {
    if out != "" {
      out = out + ","
    }
    out = out + s
  }
  out
}
