///|
/// agent P0 骨架的白盒锁。**只钉纯函数**（不碰 `@fs` / `@env` / 进程面）：
/// 那样两个 target 都能跑，且断言与 IO 抖动无关。
///
/// 为什么每格都配反向对照：只断言「正常路径通过」的锁证明不了它真在看
/// （判例-30 自指假绿）——所以未知旗标、无目录名、读回失败各有独立一格。

///|
test "agent-1：子命令词法归位，未知必落 Unknown 臂" {
  assert_eq(parse_agent_cmd("serve"), Serve)
  assert_eq(parse_agent_cmd("--serve"), Serve)
  assert_eq(parse_agent_cmd("run"), Run)
  assert_eq(parse_agent_cmd("--once"), Run)
  assert_eq(parse_agent_cmd("status"), Status)
  assert_eq(parse_agent_cmd("stop"), Stop)
  assert_eq(parse_agent_cmd("help"), Help)
  assert_eq(parse_agent_cmd("--help"), Help)
  assert_eq(parse_agent_cmd("-h"), Help)
  // 反向对照：拼错的必须落 Unknown，不能静默归到 help/status
  match parse_agent_cmd("versoin") {
    Unknown(s) => assert_eq(s, "versoin")
    _ => panic()
  }
  match parse_agent_cmd("") {
    Unknown(s) => assert_eq(s, "")
    _ => panic()
  }
}

///|
test "agent-2：未知旗标必拒（R207 同族：拼错开关 = 静默换分支）" {
  // 合法臂
  let f = match parse_agent_flags(["--once"]) {
    Ok(f) => f
    Err(_) => panic()
  }
  assert_eq(f.is_once(), true)
  assert_eq(f.is_dry_run(), false)
  let f = match parse_agent_flags(["--dry-run"]) {
    Ok(f) => f
    Err(_) => panic()
  }
  assert_eq(f.is_once(), false)
  assert_eq(f.is_dry_run(), true)
  assert_eq(f.should_mutate(), false)
  assert_eq(parse_agent_flags([]).unwrap().should_mutate(), true)

  // 变异对照：把 --once 拼成 --onse ⇒ 必须 Err（否则会静默落进真分支，
  // 人以为跑了单轮，实际跑了常驻）
  let bad = parse_agent_flags(["--onse"])
  match bad {
    Err(e) => assert_true(e.contains("未知参数"))
    Ok(_) => panic()
  }
  // 另一个方向：混在合法旗标里的坏旗标同样要拒（不是「有一个对的就收」）
  match parse_agent_flags(["--once", "--bogus"]) {
    Err(e) => assert_true(e.contains("--bogus"))
    Ok(_) => panic()
  }
  // 退出码契约：用法错 = 2（与 subcmd.mbt 的 USAGE_ERROR_EXIT_CODE 同一档）
  assert_eq(USAGE_ERROR_EXIT_CODE, 2)
}

///|
test "agent-3：状态目录跟着 FIST_DB_PATH 改道，绝不裸落 cwd" {
  // 未设 / 空串 / 纯相对名 ⇒ 空串（交给上层回落 .fist-mbt/data，同 store 口径）
  assert_eq(agent_db_dir(None), "")
  assert_eq(agent_db_dir(Some("")), "")
  assert_eq(agent_db_dir(Some("   ")), "")
  assert_eq(agent_db_dir(Some("redirected.db")), "")
  // 改道生效：取的是**目录**部分（含末尾分隔符），不是库文件所在层级再套一层
  assert_eq(agent_db_dir(Some("C:/fist-runs/redirected.db")), "C:/fist-runs/")
  assert_eq(agent_db_dir(Some("/var/tmp/fist/fist-mbt.db")), "/var/tmp/fist/")
  // Windows 反斜杠同样认
  assert_eq(
    agent_db_dir(Some("C:\\fist-runs\\redirected.db")),
    "C:\\fist-runs\\",
  )
  // 反向对照：只有文件名时没有目录可跟，不许凭空造出 `/_…` 这种越界路径
  assert_eq(agent_db_dir(Some("db.sqlite")), "")
  // 服务目录常量与锁/状态/日志文件名是同名面：改名必须同步（漂移雷）
  assert_eq(AGENT_SERVICE_DIR, "agent-service")
  assert_eq(AGENT_LOCK_FILE, "agent.lock")
  assert_eq(AGENT_STATE_FILE, "state.json")
  assert_eq(AGENT_LOG_FILE, "worker.log")
}

///|
test "agent-4：状态记录读写成环，读回失败不回默认对象（禁伪造 running）" {
  let base = {
    status: "running",
    pid: 4242,
    started_at: "t0",
    last_heartbeat: "t0",
    last_task_id: "",
    rounds: 0,
  }
  // beat：心跳刷新 + 轮数 +1；没领到任务时保留旧 id（不抹掉上一轮的痕迹）
  let b = base.beat("t1", "")
  assert_eq(b.rounds, 1)
  assert_eq(b.last_heartbeat, "t1")
  assert_eq(b.last_task_id, "")
  let b2 = base.beat("t2", "T1")
  assert_eq(b2.last_task_id, "T1")
  assert_eq(b2.started_at, "t0")
  assert_eq(b2.status, "running")

  // mark_stopped：只改状态，其余逐字不动（时间戳不许被「停止时刻」覆盖）
  let s = b.mark_stopped()
  assert_eq(s.status, "stopped")
  assert_eq(s.rounds, 1)
  assert_eq(s.last_heartbeat, "t1")
  assert_eq(s.pid, 4242)

  // 写→读成环
  match AgentState::from_json_text(base.to_json_text()) {
    None => panic()
    Some(r) => assert_eq(r.pid, 4242)
  }
  // 字段固定六键：多写的键不被读（语义上无意义），少的键回落零值不报错
  let six = base.to_json_text()
  assert_true(six.contains("\"rounds\""))
  assert_true(!six.contains("extra"))

  // 变异对照：读回失败必须 None（回默认对象 = 伪造一条 running 状态）
  match AgentState::from_json_text("") {
    None => ()
    Some(_) => panic()
  }
  match AgentState::from_json_text("not json") {
    None => ()
    Some(_) => panic()
  }
  // status 键缺失/类型不对同样 None（不能靠其它键凑出 running）
  match AgentState::from_json_text("{\"pid\":1}") {
    None => ()
    Some(_) => panic()
  }
  match AgentState::from_json_text("{\"status\":1,\"pid\":1}") {
    None => ()
    Some(_) => panic()
  }
}

///|
test "agent-5：task-packet 是唯一给外置执行器的载荷面（含空 id 边界）" {
  let p = agent_packet_for("T0r86", "now")
  assert_true(p.contains("T0r86"))
  assert_true(p.contains("now"))
  assert_true(p.contains("agent-worker"))
  // 空 id ⇒ 空串（claim 失败时不许吐一个空壳 packet 让执行器去跑）
  assert_eq(agent_packet_for("", "now"), "")
  // 回执文本：没领到时明确说 none，不回空白（空白会被读成「跑了但没输出」）
  let t = agent_round_text({
    claimed_task_id: "",
    packet: "",
    note: "no_pending",
    dry_run: false,
  })
  assert_true(t.contains("(none)"))
  assert_true(t.contains("no_pending"))
  assert_true(!t.contains("dry-run"))
  let t2 = agent_round_text({
    claimed_task_id: "T1",
    packet: "{}",
    note: "claimed",
    dry_run: true,
  })
  assert_true(t2.contains("dry-run"))
  assert_true(t2.contains("T1"))
}
