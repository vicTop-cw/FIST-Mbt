/// engine_dag_mc_wbtest.mbt —— BUG-212 的白盒锁：环保护必须沿依赖链传播 -1 哨兵。
///
/// 缺陷原形（BUG-204 修复不完整）：mc_finish 的 -1 哨兵只在「当前节点自身被重入」
/// 时生效，外层收到 -1 后照样把内层 own 累进 best——`f + own > best` 对 f=-1 因
/// own-1 <= own 自然不生效，于是环 A↔B 的 A 拿到 A.own + B.own 的正数 finish，
/// makespan 把环当成正常最长路径。本测试直接喂 mc_finish / mc_suffix_from 造环，
/// 断言环上所有节点都返回 -1。

///|
/// 造引擎 + 一张 dur 表（环 A↔B，时长 A=3 / B=5）。
fn mcw_cycle_setup() -> (
  FistEngine,
  Map[String, Int32],
  Map[String, Array[String]],
) {
  let e = FistEngine::new()
  // 直接建 store 行（绕过 publish 的深度/默认值约束），用 depends_on 造双向环
  let ta = @core.Task::new(
    id="A",
    project_dir="/proj/mcw",
    description="A",
    created_at="2026-01-01T00:00:00Z",
    depends_on=["B"],
  )
  let tb = @core.Task::new(
    id="B",
    project_dir="/proj/mcw",
    description="B",
    created_at="2026-01-01T00:00:00Z",
    depends_on=["A"],
  )
  ignore(e.store.create_task(ta))
  ignore(e.store.create_task(tb))
  let dur : Map[String, Int32] = Map([])
  dur.set("A", 3)
  dur.set("B", 5)
  let deps : Map[String, Array[String]] = Map([])
  deps.set("A", ["B"])
  deps.set("B", ["A"])
  (e, dur, deps)
}

///|
/// 环 A↔B：mc_finish(A) 和 mc_finish(B) 都必须返回 -1。
/// 修复前：A 返回 8（= 3 + 5），B 返回 5——-1 未传播，环被当正常最长路径。
test "BUG-212：环上节点的 mc_finish 必须为 -1（-1 沿依赖链传播）" {
  let (e, dur, deps) = mcw_cycle_setup()
  let memo : Map[String, Int32] = Map([])
  let visiting : Map[String, Bool] = Map([])
  let fa = e.mc_finish("A", dur, memo, visiting, deps)
  assert_eq(fa, -1)
  let memo2 : Map[String, Int32] = Map([])
  let visiting2 : Map[String, Bool] = Map([])
  let fb = e.mc_finish("B", dur, memo2, visiting2, deps)
  assert_eq(fb, -1)
}

///|
/// 环 A↔B：mc_suffix_from(A) 和 mc_suffix_from(B) 也必须返回 -1。
test "BUG-212：环上节点的 mc_suffix_from 必须为 -1" {
  let (_e, dur, _deps) = mcw_cycle_setup()
  let memo_suf : Map[String, Int32] = Map([])
  let visiting_suf : Map[String, Bool] = Map([])
  let succ : Map[String, Array[String]] = Map([])
  succ.set("A", ["B"])
  succ.set("B", ["A"])
  let sa = mc_suffix_from("A", dur, memo_suf, visiting_suf, succ)
  assert_eq(sa, -1)
  let memo_suf2 : Map[String, Int32] = Map([])
  let visiting_suf2 : Map[String, Bool] = Map([])
  let sb = mc_suffix_from("B", dur, memo_suf2, visiting_suf2, succ)
  assert_eq(sb, -1)
}

///|
/// 对照（防误伤）：**非环**链 A→B（A 依赖 B）的 mc_finish(A) 仍为正数，
/// 未被环保护误标为 -1。
test "BUG-212 成对：非环节点的 mc_finish 不误标 -1" {
  let e = FistEngine::new()
  let ta = @core.Task::new(
    id="X",
    project_dir="/proj/mcw",
    description="X",
    created_at="2026-01-01T00:00:00Z",
    depends_on=["Y"],
  )
  let tb = @core.Task::new(
    id="Y",
    project_dir="/proj/mcw",
    description="Y",
    created_at="2026-01-01T00:00:00Z",
    depends_on=[],
  )
  ignore(e.store.create_task(ta))
  ignore(e.store.create_task(tb))
  let dur : Map[String, Int32] = Map([])
  dur.set("X", 3)
  dur.set("Y", 5)
  let deps : Map[String, Array[String]] = Map([])
  deps.set("X", ["Y"])
  deps.set("Y", [])
  let memo : Map[String, Int32] = Map([])
  let visiting : Map[String, Bool] = Map([])
  let fx = e.mc_finish("X", dur, memo, visiting, deps)
  assert_eq(fx, 8)
}
