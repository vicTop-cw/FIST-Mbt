/// dag_mc_test.mbt —— Monte Carlo 概率式完工预测（R94）测试。
/// 覆盖：确定性可复现 + 按期概率单调 / 关键度（最长路径任务 freq≈1）/ 空作用域 insufficient / samples 下限钳制。

///|
/// 造任务（默认 ns=default），描述带 [难度梯度 X] 控制时长分布。
fn mc_mk(
  e : @engine.FistEngine,
  id : String,
  desc : String,
  deps : Array[String],
) -> Unit {
  let t = @core.Task::new(
    id~,
    project_dir="/proj/mc",
    description=desc,
    created_at="2026-01-01T00:00:00Z",
    depends_on=deps,
  )
  ignore(e.store.create_task(t))
}

///|
/// 读顶层数值字段。
fn mc_num(j : Json, key : String) -> Double {
  match j.value(key) {
    Some(Number(n, ..)) => n
    _ => abort("缺 \{key}: " + j.stringify())
  }
}

///|
/// 读 makespan.mean。
fn mc_meanspan(j : Json) -> Double {
  match j.value("makespan") {
    Some(Object(m)) =>
      match m.get("mean") {
        Some(Number(n, ..)) => n
        _ => abort("缺 makespan.mean: " + j.stringify())
      }
    _ => abort("缺 makespan: " + j.stringify())
  }
}

///|
/// 读 criticality 首位 task_id。
fn mc_top_crit(j : Json) -> String {
  match j.value("criticality") {
    Some(Array(a)) =>
      if a.is_empty() {
        ""
      } else {
        match a[0].value("task_id") {
          Some(String(s)) => s
          _ => ""
        }
      }
    _ => ""
  }
}

///|
test "dag_mc：确定性可复现 + 按期概率随 deadline 单调（宽松 deadline P 更高）" {
  let e = @engine.FistEngine::new()
  mc_mk(e, "A", "MC 任务 A [难度梯度 中]", [])
  mc_mk(e, "B", "MC 任务 B [难度梯度 难]", ["A"])
  let j1 = e.dag_mc()
  let j2 = e.dag_mc()
  // 同 seed → 分布完全一致（确定性可复现）
  if mc_meanspan(j1) - mc_meanspan(j2) > 0.000001 ||
    mc_meanspan(j1) - mc_meanspan(j2) < -0.000001 {
    abort("同 seed 应可复现: " + j1.stringify() + " vs " + j2.stringify())
  }
  // 紧 deadline(3) 的按期概率 < 宽松 deadline(100)
  let tight = mc_num(e.dag_mc(deadline=3), "p_on_time")
  let loose = mc_num(e.dag_mc(deadline=100), "p_on_time")
  if not(tight < loose) {
    abort("p_on_time 应随 deadline 单调: tight=\{tight} loose=\{loose}")
  }
  if loose != 1.0 {
    abort("deadline=100 应必按期（最长 22 < 100）: \{loose}")
  }
}

///|
test "dag_mc：关键度——最长路径任务 freq≈1，旁路易任务不被判关键" {
  let e = @engine.FistEngine::new()
  mc_mk(e, "A", "MC 任务 A [难度梯度 中]", [])
  mc_mk(e, "B", "MC 任务 B [难度梯度 中]", ["A"]) // A→B 链，B 总是最长路径终点
  mc_mk(e, "C", "MC 任务 C [难度梯度 易]", []) // 旁路，时长 2-5，永不超过 A→B 链
  let j = e.dag_mc(seed=7)
  if mc_top_crit(j) != "B" {
    abort("关键路径终点应为 B: " + j.stringify())
  }
  // B 的 critical_freq 应≈1.0
  match j.value("criticality") {
    Some(Array(a)) =>
      match a[0].value("critical_freq") {
        Some(Number(n, ..)) =>
          if n < 0.9 {
            abort("B 关键频率应≈1.0: \{n}")
          }
        _ => abort("缺 critical_freq: " + j.stringify())
      }
    _ => abort("缺 criticality: " + j.stringify())
  }
}

///|
test "dag_mc：空作用域返回 insufficient（不崩溃）" {
  let e = @engine.FistEngine::new()
  let j = e.dag_mc()
  match j.value("insufficient") {
    Some(True) => ()
    _ => abort("空库应 insufficient: " + j.stringify())
  }
}

///|
test "dag_mc：samples 下限钳制（<10 按 10）" {
  let e = @engine.FistEngine::new()
  mc_mk(e, "A", "MC 任务 A [难度梯度 易]", [])
  let j = e.dag_mc(samples=5)
  if mc_num(j, "samples") != 10.0 {
    abort("samples 应钳到 10: " + j.stringify())
  }
}
