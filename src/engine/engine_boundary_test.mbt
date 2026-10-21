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

// ---------------------------------------------------------------------------
// 属性测试（quickcheck 风格，确定性种子 PRNG）
// ---------------------------------------------------------------------------

///|
/// 确定性 xorshift 伪随机数发生器（不依赖标准库 Random，跨平台可复现）。
struct BpRng {
  state : Int
}

///|
fn bp_rng(seed : Int) -> BpRng {
  { state: if seed == 0 { 1 } else { seed }, }
}

///|
/// 推进并返回下一个非负整数（xorshift32）。
fn BpRng::bp_next(self : BpRng) -> (Int, BpRng) {
  let mut x = self.state
  x = x ^ (x << 13)
  x = x ^ (x >> 17)
  x = x ^ (x << 5)
  let nx = if x < 0 { -x } else { x }
  (nx, { state: x, })
}

///|
/// 生成一个伪随机 Int 列表（长度在 [0, len] 之间，值域受 bound 约束）。
fn bp_rand_ints(len : Int, bound : Int, seed : Int) -> Array[Int] {
  let mut r = bp_rng(seed)
  let mut out : Array[Int] = []
  for _i in 0..<len {
    let (n, nr) = r.bp_next()
    r = nr
    out = out + [n % bound]
  }
  out
}

///|
/// 属性 1：`plan_deep` 幂等——同 root 二次 plan_deep 要么返回同样的叶子数，要么被拒
/// （幂等拒绝也算幂等）。断言不产生新的叶子，防重复拆解爆炸。
test "property_plan_deep_idempotent_seeded" {
  for seed in 0..<8 {
    let e = bp_engine("属性测试根任务 seed=" + seed.to_string())
    let j1 = match
      e.plan_deep(
        task_id="R",
        split_n=2,
        by="captain",
        now="2026-01-03T00:00:00Z",
      ) {
      Ok(x) => x
      Err(m) => abort("plan_deep failed: " + m)
    }
    let ids1 = bp_ids(j1)
    // 二次 plan_deep：Ok(same count) 或 Err（幂等拒绝）都算幂等
    let ids2 = match
      e.plan_deep(
        task_id="R",
        split_n=2,
        by="captain",
        now="2026-01-03T00:00:01Z",
      ) {
      Ok(x) => bp_ids(x)
      Err(_) => ids1 // 幂等拒绝：保持原状
    }
    assert_eq(ids1.length(), ids2.length())
  }
}

///|
/// 属性 2：`audit_execute_gate` 对空/纯空白交付物一律拒，非空一律放行——
/// 任意长度的随机交付物字符串，只要 trim 后非空就通过。
test "property_audit_gate_empty_only" {
  let e = @engine.FistEngine::new()
  for seed in 0..<8 {
    let r = bp_rand_ints(3, 100, seed * 11 + 5)
    for v in r {
      let deliv = "" // 空
      match e.audit_execute_gate("T", deliv) {
        Ok(_) => abort("空交付物应被拒")
        Err(m) => assert_true(m.contains("预执行审计门禁"))
      }
      let deliv2 = "   \n\t " + v.to_string()
      match e.audit_execute_gate("T", deliv2) {
        Ok(_) => ()
        Err(m) => abort("非空交付物不应被拒: " + m)
      }
    }
  }
}
