/// engine_boundary_test.mbt —— boundary_probe（边界审视叶 + 边界四问）回归锁。
///
/// 对准 atgc-merge 归因报告：机理 1「递归拆解损失全局视角 ⇒ 全局不变量无 owner」、
/// 机理 2「验收锚定 + 弱语料 ⇒ 执行体停在判据边界」。默认关闭必须零回归。

///|
fn bp_engine(root_desc : String) -> @engine.FistEngine {
  let e = @engine.FistEngine::new()
  let t = @core.Task::new(
    id="R",
    project_dir="/proj/bp",
    description=root_desc,
    created_at="2026-01-01T00:00:00Z",
    depends_on=[],
  )
  ignore(e.store.create_task(t))
  e
}

///|
/// 递归收集树里所有子任务 id。
fn bp_ids(j : Json) -> Array[String] {
  let mut out : Array[String] = []
  match j.value("tree") {
    Some(tree) =>
      match tree.value("children") {
        Some(Array(arr)) =>
          for n in arr {
            match n.value("id") {
              Some(String(id)) => out = out + [id]
              _ => ()
            }
          }
        _ => ()
      }
    _ => ()
  }
  out
}

///|
/// 默认关闭：拆出的叶子必须与旧行为逐字一致（零回归红线）。
test "boundary_probe_default_off_zero_regression" {
  let e = bp_engine("做一个编解码器 [omega:required]")
  let j = match
    e.plan_deep(
      task_id="R",
      split_n=2,
      by="captain",
      now="2026-01-02T00:00:00Z",
    ) {
    Ok(x) => x
    Err(m) => abort("默认拆解失败: " + m)
  }
  let ids = bp_ids(j)
  assert_eq(ids.length(), 2)
  for id in ids {
    let d = match e.store.get_task(id) {
      Some(t) => t.description
      None => abort("子任务缺失: " + id)
    }
    if d.contains("边界审视") || d.contains("边界四问") {
      abort("默认关闭却注入了边界文本: " + d)
    }
  }
}

///|
/// 打开后：多出一条「边界审视叶」作为全局输入域 owner，其余每条叶挂「边界四问」。
test "boundary_probe_on_adds_owner_leaf_and_per_leaf_hint" {
  let e = bp_engine("做一个编解码器")
  let j = match
    e.plan_deep(
      task_id="R",
      split_n=2,
      by="captain",
      now="2026-01-02T00:00:00Z",
      boundary_probe=true,
    ) {
    Ok(x) => x
    Err(m) => abort("boundary_probe 拆解失败: " + m)
  }
  let ids = bp_ids(j)
  assert_eq(ids.length(), 3)
  let mut owner = 0
  let mut hinted = 0
  for id in ids {
    let d = match e.store.get_task(id) {
      Some(t) => t.description
      None => abort("子任务缺失: " + id)
    }
    if d.contains("边界审视·全局输入域 owner") {
      owner = owner + 1
      // owner 自己必须写清四类域外行为，且不得沉默
      if !d.contains("空输入") ||
        !d.contains("极值") ||
        !d.contains("非法输入") ||
        !d.contains("资源极限") {
        abort("边界审视叶缺四类之一: " + d)
      }
    } else if d.contains("边界四问") {
      hinted = hinted + 1
    }
  }
  assert_eq(owner, 1)
  assert_eq(hinted, 2)
}
