/// engine_saga_test.mbt —— Saga 补偿事务编排（R92）测试。
/// 覆盖：LIFO 严格倒序 + 默认标记 done（幂等）/ 幂等重登记 / mark=false 预览不消费 /
/// clear 清空 saga_log。

///|
/// 构建干净的 SQLite 引擎（先清库保证用例幂等）。
fn saga_sqlite_engine(db_path : String) -> @engine.FistEngine {
  match @store.SqliteStore::open(db_path) {
    Some(s) => ignore(s.clear())
    None => abort("sqlite open failed: " + db_path)
  }
  match @engine.FistEngine::open_sqlite(db_path) {
    None => abort("engine open failed: " + db_path)
    Some(e) => e
  }
}

///|
/// 登记一个补偿步骤（默认 ns="default"）。
fn saga_reg(
  e : @engine.FistEngine,
  root : String,
  step : String,
  comp : String,
) -> Unit {
  match
    e.saga_register(
      root_task_id=root,
      step~,
      compensation=comp,
      now="2026-09-26T05:00:00Z",
    ) {
    Ok(_) => ()
    Err(m) => abort("saga_register 失败: " + m)
  }
}

///|
/// 登记一个带 task_id 的补偿步骤（供 depends_on 闭包切片判定）。
fn saga_reg_task(
  e : @engine.FistEngine,
  root : String,
  step : String,
  task_id : String,
  comp : String,
) -> Unit {
  match
    e.saga_register(
      root_task_id=root,
      step~,
      task_id~,
      compensation=comp,
      now="2026-09-26T05:00:00Z",
    ) {
    Ok(_) => ()
    Err(m) => abort("saga_register 失败: " + m)
  }
}

///|
/// 读出 rollback JSON 的 pending_count。
fn saga_pending_count(j : Json) -> Int {
  match j.value("pending_count") {
    Some(Number(n, ..)) => n.to_int()
    _ => abort("pending_count 缺失: " + j.stringify())
  }
}

///|
/// 读出 rollback JSON 的 pending 步骤名（保持 JSON 顺序）。
fn saga_steps(j : Json) -> Array[String] {
  let out : Array[String] = []
  match j.value("pending") {
    Some(Array(a)) =>
      for x in a {
        match x.value("step") {
          Some(String(s)) => out.push(s)
          _ => abort("step 缺失")
        }
      }
    _ => abort("pending 缺失: " + j.stringify())
  }
  out
}

///|
/// 读出某根任务全部步骤的 status（前向顺序）。
fn saga_statuses(e : @engine.FistEngine, root : String) -> Array[String] {
  let rows = e.store_list_saga_actions("default", root)
  rows.map(fn(r) { r.4 })
}

///|
test "saga_rollback：LIFO 严格倒序（后登记先补偿）+ 默认标记 done + 幂等" {
  let e = saga_sqlite_engine("saga_r92_t1.db")
  saga_reg(e, "R1", "payment", "refund payment")
  saga_reg(e, "R1", "inventory", "restock inventory")
  let j1 = match e.saga_rollback("R1") {
    Ok(j) => j
    Err(m) => abort("rollback 失败: " + m)
  }
  assert_eq(saga_pending_count(j1), 2)
  // LIFO：后登记的 inventory 先补偿，再 payment
  assert_eq(saga_steps(j1).join(","), "inventory,payment")
  // 默认 mark=true：返回后即标记 done
  assert_eq(saga_statuses(e, "R1").join(","), "done,done")
  // 幂等：重复 rollback 不再出现已补偿步骤
  let j2 = match e.saga_rollback("R1") {
    Ok(j) => j
    Err(m) => abort("rollback 二次失败: " + m)
  }
  assert_eq(saga_pending_count(j2), 0)
}

///|
test "saga_register：同 (ns, root, step) 幂等重登记——行数不变、compensation 更新、status 重置 pending" {
  let e = saga_sqlite_engine("saga_r92_t2.db")
  saga_reg(e, "R2", "ship", "cancel shipment")
  saga_reg(e, "R2", "ship", "cancel shipment + notify carrier") // 重登记
  let rows = e.store_list_saga_actions("default", "R2")
  assert_eq(rows.length(), 1)
  assert_eq(rows[0].1, "ship")
  assert_eq(rows[0].3, "cancel shipment + notify carrier")
  assert_eq(rows[0].4, "pending")
}

///|
test "saga_rollback：mark=false 仅预览不消费；随后 mark=true 消费后为空" {
  let e = saga_sqlite_engine("saga_r92_t3.db")
  saga_reg(e, "R3", "a", "undo a")
  let pv = match e.saga_rollback("R3", mark=false) {
    Ok(j) => j
    Err(m) => abort("预览失败: " + m)
  }
  assert_eq(saga_pending_count(pv), 1)
  assert_eq(saga_statuses(e, "R3").join(","), "pending") // 未消费
  let co = match e.saga_rollback("R3") {
    Ok(j) => j
    Err(m) => abort("消费失败: " + m)
  }
  assert_eq(saga_pending_count(co), 1)
  assert_eq(saga_statuses(e, "R3").join(","), "done") // 已消费
  let empty = match e.saga_rollback("R3") {
    Ok(j) => j
    Err(m) => abort("再查失败: " + m)
  }
  assert_eq(saga_pending_count(empty), 0)
}

///|
test "clear 清空 saga_log（防测试/scratch 跨次残留）" {
  let e = saga_sqlite_engine("saga_r92_t4.db")
  saga_reg(e, "R4", "x", "undo x")
  assert_eq(e.store_list_saga_actions("default", "R4").length(), 1)
  // clear 在 saga_sqlite_engine 里已跑过；这里再清一次验证幂等
  ignore(e.store.clear())
  assert_eq(e.store_list_saga_actions("default", "R4").length(), 0)
}

///|
/// 读出 repair JSON 的 compensate 步骤名（保持切片内 LIFO 顺序）。
fn saga_repair_compensate(j : Json) -> Array[String] {
  let out : Array[String] = []
  match j.value("compensate") {
    Some(Array(a)) =>
      for x in a {
        match x.value("step") {
          Some(String(s)) => out.push(s)
          _ => abort("compensate step 缺失")
        }
      }
    _ => abort("compensate 缺失: " + j.stringify())
  }
  out
}

///|
/// 读出 repair JSON 的 keep 步骤名（保留承诺，保持前向顺序）。
fn saga_repair_keep(j : Json) -> Array[String] {
  let out : Array[String] = []
  match j.value("keep") {
    Some(Array(a)) =>
      for x in a {
        match x.value("step") {
          Some(String(s)) => out.push(s)
          _ => abort("keep step 缺失")
        }
      }
    _ => abort("keep 缺失: " + j.stringify())
  }
  out
}

///|
/// 读出 repair JSON 的 basis（depends_on / order）。
fn saga_repair_basis(j : Json) -> String {
  match j.value("basis") {
    Some(String(s)) => s
    _ => abort("basis 缺失: " + j.stringify())
  }
}

///|
test "saga_repair：depends_on 依赖闭包最小切片——只补偿失败及其下游，旁路 keep" {
  let e = saga_sqlite_engine("saga_r96_t1.db")
  // 任务图：t1 无依赖；t2 依赖 t1（下游）；t3 无依赖（旁路）
  let specs : Array[(String, Array[String])] = [
    ("t1", []),
    ("t2", ["t1"]),
    ("t3", []),
  ]
  for s in specs {
    let (id, deps) = s
    let t = @core.Task::new(
      id~,
      project_dir="/proj/demo",
      description="saga repair 任务 \{id}",
      created_at="2026-09-26T05:00:00Z",
      depends_on=deps,
    )
    ignore(e.store.create_task(t))
  }
  saga_reg_task(e, "R1", "s1", "t1", "undo s1")
  saga_reg_task(e, "R1", "s2", "t2", "undo s2")
  saga_reg_task(e, "R1", "s3", "t3", "undo s3")
  let j = match e.saga_repair("R1", failed_step="s1") {
    Ok(j) => j
    Err(m) => abort("repair 失败: " + m)
  }
  // 切片 = s1(t1) + s2(t2 依赖 t1)，切片内 LIFO → s2,s1
  assert_eq(saga_repair_compensate(j).join(","), "s2,s1")
  // keep = s3（t3 旁路，未受影响承诺保留）
  assert_eq(saga_repair_keep(j).join(","), "s3")
  assert_eq(saga_repair_basis(j), "depends_on")
  // 默认 mark=true：仅切片标 done；keep 仍 pending 供后续按需补偿
  assert_eq(saga_statuses(e, "R1").join(","), "done,done,pending")
}

///|
test "saga_repair：无 task_id 按注册序兜底——后注册者为潜在下游，先于失败者保留" {
  let e = saga_sqlite_engine("saga_r96_t2.db")
  saga_reg(e, "R2", "a", "undo a")
  saga_reg(e, "R2", "b", "undo b")
  saga_reg(e, "R2", "c", "undo c")
  let j = match e.saga_repair("R2", failed_step="b") {
    Ok(j) => j
    Err(m) => abort("repair 失败: " + m)
  }
  // 受影响 = b + 后注册 c（切片内 LIFO → c,b）；a 先于失败者提交，保留
  assert_eq(saga_repair_compensate(j).join(","), "c,b")
  assert_eq(saga_repair_keep(j).join(","), "a")
  assert_eq(saga_repair_basis(j), "order")
  assert_eq(saga_statuses(e, "R2").join(","), "pending,done,done")
}

///|
test "saga_repair：mark=false 预览不消费；失败步骤不在待补偿中 → Err" {
  let e = saga_sqlite_engine("saga_r96_t3.db")
  saga_reg(e, "R3", "x", "undo x")
  let pv = match e.saga_repair("R3", failed_step="x", mark=false) {
    Ok(j) => j
    Err(m) => abort("预览失败: " + m)
  }
  assert_eq(saga_repair_compensate(pv).join(","), "x")
  assert_eq(saga_statuses(e, "R3").join(","), "pending") // 未消费
  match e.saga_repair("R3", failed_step="nope") {
    Err(m) => assert_true(m.contains("不在"))
    Ok(_) => abort("应返回 Err")
  }
}

///|
test "saga_repair：消费后 keep 步骤仍可被后续 rollback 整链补偿（两级收尾共存）" {
  let e = saga_sqlite_engine("saga_r96_t4.db")
  let specs : Array[(String, Array[String])] = [("k1", []), ("k2", ["k1"])]
  for s in specs {
    let (id, deps) = s
    let t = @core.Task::new(
      id~,
      project_dir="/proj/demo",
      description="saga repair 任务 \{id}",
      created_at="2026-09-26T05:00:00Z",
      depends_on=deps,
    )
    ignore(e.store.create_task(t))
  }
  saga_reg_task(e, "R4", "s1", "k1", "undo s1")
  saga_reg_task(e, "R4", "s2", "k2", "undo s2")
  let j = match e.saga_repair("R4", failed_step="s1") {
    Ok(j) => j
    Err(m) => abort("repair 失败: " + m)
  }
  // 整链都受影响（k2 依赖 k1）→ 切片 = 全部，keep 空
  assert_eq(saga_repair_compensate(j).join(","), "s2,s1")
  assert_eq(saga_repair_keep(j).length(), 0)
  assert_eq(saga_statuses(e, "R4").join(","), "done,done")
  // 消费后 saga_rollback 无剩余 pending（整链已收尾，两级共存幂等）
  let rb = match e.saga_rollback("R4") {
    Ok(j) => j
    Err(m) => abort("rollback 失败: " + m)
  }
  assert_eq(saga_pending_count(rb), 0)
}
