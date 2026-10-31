/// engine_acc_reject_wbtest.mbt —— 评委拒收项 I5 / I6 的回归锁。
///
/// I5「DAG 接受成环依赖」：环闸原先只长在 `dag_depend` 函数体里，
/// 第二个写 `depends_on` 的入口 `supervisor_task_upsert` 照样把环写进了库
/// （实测：A→B→C 后 upsert(A, depends_on=[C]) 与 upsert(B, depends_on=[B]) 双双成功落库）。
/// I6「Omega 验收门可由归档绕过」：`archive` / `archive_force` 有门，
/// 而第三条写 Archived 的路径 `publish_next_round`（watchdog / pipeline 自动续轮）没有门。
///
/// 两组锁都是**行为面**断言（库里到底有没有那条边、状态到底变没变成已归档），
/// 不是文案断言 —— 文案改了锁不该红，环写进库了锁必须红。

///|
fn acc_err_of(r : Result[@core.Task, String]) -> String {
  match r {
    Err(e) => e
    Ok(_) => "<ok>"
  }
}

///|
/// 本工具链已移除 Result::is_ok/is_err（AGENTS「环境要求」），判成败一律就地 match。
fn[A, E] acc_is_ok(r : Result[A, E]) -> Bool {
  match r {
    Ok(_) => true
    Err(_) => false
  }
}

///|
fn[A, E] acc_is_err(r : Result[A, E]) -> Bool {
  !acc_is_ok(r)
}

///|
/// 取回执里第 0 条 item 的 error 字段（无则空串）。
fn acc_item_error(j : Json) -> String {
  match j {
    Json::Object(m) =>
      match m.get("results") {
        Some(Json::Array(a)) =>
          if a.length() == 0 {
            ""
          } else {
            match a[0] {
              Json::Object(r) =>
                match r.get("error") {
                  Some(Json::String(s)) => s
                  _ => ""
                }
              _ => ""
            }
          }
        _ => ""
      }
    _ => ""
  }
}

///|
/// 取回执里的 ok_count（读不到回 -1.0 —— 负数不是合法读数，尺子坏了会被看出来）。
/// 返回 Double 而非 Int32：Json::Number 装的就是 Double，本工具链不给 Double 转 Int32 的直路。
fn acc_ok_count(j : Json) -> Double {
  match j {
    Json::Object(m) =>
      match m.get("ok_count") {
        Some(Json::Number(n, ..)) => n
        _ => -1.0
      }
    _ => -1.0
  }
}

///|
fn acc_deps_json(deps : Array[String]) -> Json {
  let a : Array[Json] = []
  for d in deps {
    a.push(Json::string(d))
  }
  Json::array(a)
}

///|
fn acc_item(task_id : String, deps : Array[String]) -> Json {
  let m : Map[String, Json] = Map([])
  m.set("task_id", Json::string(task_id))
  m.set("depends_on", acc_deps_json(deps))
  Json::object(m)
}

///|
fn acc_item_new(deps : Array[String]) -> Json {
  let m : Map[String, Json] = Map([])
  m.set("description", Json::string("新建带依赖"))
  m.set("depends_on", acc_deps_json(deps))
  Json::object(m)
}

///|
/// 建一条真实依赖链 A←B←C（经 dag_depend，即原本带门的那条路径）。
fn acc_chain(e : FistEngine) -> Unit {
  for id in ["A", "B", "C"] {
    ignore(
      e.store.create_task(
        @core.Task::new(
          id~,
          project_dir="/proj/acc",
          description="链节点 \{id}",
          created_at="2026-10-31T00:00:00Z",
        ),
      ),
    )
  }
  ignore(e.dag_depend(task_id="B", dep_id="A", now="2026-10-31T00:00:01Z"))
  ignore(e.dag_depend(task_id="C", dep_id="B", now="2026-10-31T00:00:02Z"))
}

///|
/// 把根任务 T0 推到已完成（走真实状态机，不开后门写状态）。
/// ns 由调用方给：publish_next_round 只认定时任务命名空间，default 会被它自己拒。
fn acc_to_completed(e : FistEngine, ns : String) -> Unit {
  ignore(
    e.publish(
      project_dir="/proj/acc",
      description="普通根任务",
      created_by="human_steward",
      now="2026-10-31T00:00:00Z",
      ns~,
    ),
  )
  ignore(e.claim(task_id="T0", assignee="exec", now="2026-10-31T00:00:01Z"))
  ignore(
    e.execute(
      task_id="T0",
      deliverable="交付物 src/demo.mbt:1 已落地并通过自测",
      now="2026-10-31T00:00:02Z",
    ),
  )
  ignore(e.submit(task_id="T0", now="2026-10-31T00:00:03Z"))
  ignore(
    e.verify(task_id="T0", verifier="human_steward", now="2026-10-31T00:00:04Z"),
  )
}

///|
/// 事后给已完成任务补上 Omega 标记（模拟「验收语境后来才成立」）。
/// omega_enabled 的判据是「元数据列 或 描述里的标记」，补描述即可触发门禁。
fn acc_stamp_omega(e : FistEngine) -> Unit {
  match e.store.get_task("T0") {
    Some(t) =>
      ignore(
        e.store.update_task(
          t.with_description(
            "补标 Omega 任务 [omega:required]", "2026-10-31T00:00:05Z",
          ),
        ),
      )
    None => ()
  }
}

///|
/// 当前状态字面量（断言一律打在盘上状态，不打在回执文案上）。
fn acc_status(e : FistEngine, id : String) -> String {
  match e.store.get_task(id) {
    Some(t) => t.get_status().to_string()
    None => "<absent>"
  }
}

///|
test "I5/depend_edge_ok：自环、悬空、传递环三拒，合法边放行" {
  let e = FistEngine::new()
  acc_chain(e)
  assert_true(
    acc_err_of(
      e.dag_depend(task_id="A", dep_id="A", now="2026-10-31T00:00:09Z"),
    ).contains("不能依赖自身"),
  )
  assert_true(acc_is_err(e.depend_edge_ok("A", "ZZ")))
  // A←B←C 已成立 ⇒ 给 A 加依赖 C 即关环
  let msg = acc_err_of(
    e.dag_depend(task_id="A", dep_id="C", now="2026-10-31T00:00:10Z"),
  )
  assert_true(msg.contains("成环") || msg.contains("传递环"), msg~)
  // 反向对照：真实存在的合法边不许被新门误杀（防恒红）
  assert_true(acc_is_ok(e.depend_edge_ok("C", "B")))
}

///|
test "I5/upsert 关环被拒，且库里的 depends_on 一个字节都没被写脏" {
  let e = FistEngine::new()
  acc_chain(e)
  let before = e.store.get_task("A").unwrap().depends_on.copy()
  let r = e.supervisor_task_upsert(
    project_dir="/proj/acc",
    by="human_steward",
    [acc_item("A", ["C"])],
    now="2026-10-31T00:00:11Z",
  )
  assert_eq(acc_ok_count(r), 0.0)
  assert_true(
    acc_item_error(r).contains("依赖边被拒"),
    msg=acc_item_error(r),
  )
  // 关键断言在盘上：A 的依赖边必须仍是原样，而不是「回执说拒了、库里却写进去了」
  assert_eq(e.store.get_task("A").unwrap().depends_on, before)
  assert_eq(acc_status(e, "C"), "待领取")
}

///|
test "I5/upsert 自环被拒（dag_depend 拒得住的，upsert 也必须拒得住）" {
  let e = FistEngine::new()
  acc_chain(e)
  let r = e.supervisor_task_upsert(
    project_dir="/proj/acc",
    by="human_steward",
    [acc_item("B", ["B"])],
    now="2026-10-31T00:00:12Z",
  )
  assert_true(
    acc_item_error(r).contains("不能依赖自身"),
    msg=acc_item_error(r),
  )
  let deps = e.store.get_task("B").unwrap().depends_on
  assert_true(!deps.contains("B"), msg=deps.join(","))
}

///|
test "I5/upsert 合法依赖照常放行；新建带悬空依赖被拒（反向对照，防新门恒红）" {
  let e = FistEngine::new()
  acc_chain(e)
  let r = e.supervisor_task_upsert(
    project_dir="/proj/acc",
    by="human_steward",
    [acc_item("C", ["A"])],
    now="2026-10-31T00:00:13Z",
  )
  assert_eq(acc_ok_count(r), 1.0)
  assert_true(e.store.get_task("C").unwrap().depends_on.contains("A"))
  let r2 = e.supervisor_task_upsert(
    project_dir="/proj/acc",
    by="human_steward",
    [acc_item_new(["不存在的那个"])],
    now="2026-10-31T00:00:14Z",
  )
  assert_true(acc_item_error(r2).contains("不存在"), msg=acc_item_error(r2))
}

///|
test "I6/自动续轮不得绕过 Omega 验收门：旧根任务留在已完成，不悄悄了账" {
  let e = FistEngine::new()
  acc_to_completed(e, "cron-auto")
  assert_eq(acc_status(e, "T0"), "已完成")
  acc_stamp_omega(e)
  let r = e.publish_next_round(
    ns="cron-auto",
    description="下一轮 [omega:required]",
    created_by="watchdog",
    prev_task_id="T0",
    now="2026-10-31T00:00:20Z",
  )
  let msg = match r {
    Err(m) => m
    Ok(_) => "<ok>"
  }
  assert_true(msg.contains("验收门") || msg.contains("Omega"), msg~)
  // 行为面：旧根任务没有被归档，续轮任务也没有落库
  assert_eq(acc_status(e, "T0"), "已完成")
  assert_eq(e.store.get_task("T0r2"), None)
}

///|
test "I6/对照：非 Omega 的已完成根任务照旧自动续轮并归档（零回归）" {
  let e = FistEngine::new()
  acc_to_completed(e, "cron-auto")
  let r = e.publish_next_round(
    ns="cron-auto",
    description="下一轮普通任务",
    created_by="watchdog",
    prev_task_id="T0",
    now="2026-10-31T00:00:21Z",
  )
  assert_true(acc_is_ok(r))
  assert_eq(acc_status(e, "T0"), "已归档")
}

///|
test "I6/archive 与 archive_force 同用一条门；未开标记时两者都放行" {
  let e = FistEngine::new()
  acc_to_completed(e, "default")
  acc_stamp_omega(e)
  let a1 = acc_err_of(
    e.archive(task_id="T0", by="human_steward", now="2026-10-31T00:00:22Z"),
  )
  let a2 = acc_err_of(
    e.archive_force(
      task_id="T0",
      by="human_steward",
      force=true,
      now="2026-10-31T00:00:23Z",
    ),
  )
  assert_true(a1.contains("Omega 门禁拦截归档"), msg=a1)
  assert_true(a2.contains("Omega 门禁拦截归档"), msg=a2)
  // 反向对照：同一套门在没有 Omega 标记时不拦（证明上面两条红是被门拦的，不是别处坏的）
  let e2 = FistEngine::new()
  acc_to_completed(e2, "default")
  assert_true(
    acc_is_ok(
      e2.archive(task_id="T0", by="human_steward", now="2026-10-31T00:00:24Z"),
    ),
  )
}
