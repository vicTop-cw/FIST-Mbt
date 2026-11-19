// ---------------------------------------------------------------------------
// ops_loop.mbt —— 组合环编排层（Phase 6）
//
// 设计原则：
//   - 不修改 PipelineMode enum（6 个单模式保持零改动）
//   - 纯计算：本文件零 IO。持久化编排在 src/server/server.mbt 的 loop 段
//     （轮 192 · JSONL 追加式）；本文件只给两面——写面 `loop_to_json`、
//     读面 `loop_from_json`（同一套字段名的逆运算，漂移即静默丢状态）
//   - 编排层 vs 执行层分离：loop_tick 返回下一步 mode 字符串，
//     server 层用它调 pipeline_tick(mode=...)
//
// 终止条件（优先级从上到下）：
//   1. max_rounds 硬上限（安全网，默认 5）
//   2. goal_reached（project_health=healthy + 零 blocked_tasks）
//   3. exceeded（test_count ↑10%+ 或 bug_count ↓50%+ 相对于 loop 创建 baseline）
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// 组合环状态
// ---------------------------------------------------------------------------

///|
/// **⚠️ 当前无生产构造点**（2026-10-29 普查：生产构造 0 / 测试构造 5 /
/// 生产消费 0，唯一函数 `loop_status_str` 也无生产调用方）。
///
/// **为什么保留而不是删**（Lane DM 定夺，**推翻了初判的「① 真死」**）：
/// 初判只扫了 `src/` 就断言「整组孤立」，**漏了这个包自己的白盒测试** ——
/// `ops_loop_wbtest.mbt:317` 有一格完整覆盖 5 个变体 + `loop_status_str`
/// ⇒ 它**不是死代码**，而是「**枚举与其字符串化已实现、生产侧尚无调用方**」，
/// 与 `constraint` 的三个 struct（`WorldState` 等）同类。
///
/// 且 `ops_loop.mbt` 有 15 个公开项，**不能连文件删**。
/// 若 90 天内仍无生产调用方，再评估删除。
pub enum LoopStatus {
  Active // 正常推进中
  MaxRoundsHit // 硬上限触发
  GoalReached // 目标达成
  Exceeded // 超额完成
  NoSteps // 环定义里 steps 为空（非法）
}

// ---------------------------------------------------------------------------
// PipelineLoop — 组合环核心结构
// ---------------------------------------------------------------------------

///|
pub struct PipelineLoop {
  name : String
  steps : Array[String]
  current_idx : Int32
  round : Int32
  max_rounds : Int32
  stop_on_goal : Bool
  stop_on_exceeded : Bool
  created_at : String
  updated_at : String
  stop_reason : String
  goal_reached : Bool
  exceeded : Bool
  baseline_test_count : Int32
  baseline_open_bug_count : Int32
}

///|
pub struct LoopTickResult {
  loop_id : String
  next_mode : String
  next_step_idx : Int32
  next_round : Int32
  should_stop : Bool
  stop_reason : String
  history_json : Json
  loop_after : PipelineLoop
}

// ---------------------------------------------------------------------------
// 构造 / 预设
// ---------------------------------------------------------------------------

///|
/// 创建新组合环（纯计算）
pub fn loop_create(
  name : String,
  steps : Array[String],
  now : String,
  max_rounds~ : Int32 = 5,
  stop_on_goal~ : Bool = true,
  stop_on_exceeded~ : Bool = true,
  baseline_test_count~ : Int32 = 0,
  baseline_open_bug_count~ : Int32 = 0,
) -> PipelineLoop {
  PipelineLoop::{
    name,
    steps,
    current_idx: 0,
    round: 0,
    max_rounds,
    stop_on_goal,
    stop_on_exceeded,
    created_at: now,
    updated_at: now,
    stop_reason: "",
    goal_reached: false,
    exceeded: false,
    baseline_test_count,
    baseline_open_bug_count,
  }
}

///|
/// 5 个内置预设环（开箱即用）
pub fn preset_loop(name : String) -> Result[(Array[String], String), String] {
  match name.to_lower() {
    "fix-iterate" =>
      Ok(
        (
          ["bugfind", "fix_and_merge"],
          "持续寻虫到修复循环，直到零 OPEN bug",
        ),
      )
    "build-verify" =>
      Ok(
        (
          ["advance", "verify", "polish"],
          "开发到验证到打磨循环，直到 API 完备",
        ),
      )
    "full-iterate" =>
      Ok(
        (
          ["advance", "bugfind", "fix_and_merge", "verify"],
          "四模式流水线迭代：推进到寻虫到修复到验证",
        ),
      )
    "perf-iterate" =>
      Ok(
        (
          ["advance", "polish", "verify", "advance"],
          "R12-R4 算子扩展：推进（性能优化）到打磨到验证到再推进，持续性能迭代",
        ),
      )
    "scan-fix-verify" =>
      Ok(
        (
          ["bugfind", "fix_and_merge", "verify"],
          "R12-R4 算子扩展：扫描到修复到验证，把一次发现的 bug 家族彻底收口",
        ),
      )
    _ =>
      Err(
        "unknown preset loop: " +
        name +
        ". available: fix-iterate, build-verify, full-iterate, perf-iterate, scan-fix-verify",
      )
  }
}

// ---------------------------------------------------------------------------
// 状态机推进
// ---------------------------------------------------------------------------

///|
/// 推进一环：取当前 idx 的 mode，算 idx/round 推进，判终止。
/// 参数名不用 loop（MoonBit 保留字），统一用 lp。
pub fn loop_tick(
  lp : PipelineLoop,
  now : String,
  current_test_count~ : Int32 = 0,
  current_open_bug_count~ : Int32 = 0,
  project_health_grade~ : String = "",
  blocked_tasks~ : Int32 = 0,
) -> LoopTickResult {
  // 空 steps 保护
  if lp.steps.length() == 0 {
    return LoopTickResult::{
      loop_id: lp.name,
      next_mode: "",
      next_step_idx: 0,
      next_round: lp.round,
      should_stop: true,
      stop_reason: "loop has no steps",
      history_json: Json::object(
        Map([
          ("loop_id", Json::string(lp.name)),
          ("action", Json::string("tick_abort")),
          ("reason", Json::string("no_steps")),
        ]),
      ),
      loop_after: PipelineLoop::{
        name: lp.name,
        steps: lp.steps,
        current_idx: lp.current_idx,
        round: lp.round,
        max_rounds: lp.max_rounds,
        stop_on_goal: lp.stop_on_goal,
        stop_on_exceeded: lp.stop_on_exceeded,
        created_at: lp.created_at,
        updated_at: now,
        stop_reason: "no_steps",
        goal_reached: lp.goal_reached,
        exceeded: lp.exceeded,
        baseline_test_count: lp.baseline_test_count,
        baseline_open_bug_count: lp.baseline_open_bug_count,
      },
    }
  }

  // BUG-144: 先算 next_idx（下一步下标），再取下一步的 mode。
  // 旧实现先取当前 idx 的 mode（即「刚完成」那一步），与字段名/工具描述相反。
  let next_idx = (lp.current_idx + 1) % lp.steps.length()
  let next_mode = lp.steps[next_idx]
  let mut next_round = lp.round
  if next_idx == 0 {
    next_round = next_round + 1
  }

  // --- 判终止 ---
  let mut should_stop = false
  let mut stop_reason = ""

  // 1. max_rounds 硬上限
  // BUG-203：off-by-one——next_round 是「下一步将进入」的轮号，
  // max_rounds 是轮数上限，故 >= 才算越界（旧 > 让 max_rounds=1 实际跑 2 轮）。
  if next_round >= lp.max_rounds {
    should_stop = true
    stop_reason = "max_rounds_hit: round " +
      next_round.to_string() +
      " > max " +
      lp.max_rounds.to_string()
  }

  // 2. goal_reached（BUG-162：首轮 round=0 时一律不让 goal_reached 停，
  //    因为调用方很可能还没跑过 verify 步骤、项目健康度是手工填的占位值）
  if !should_stop && lp.stop_on_goal && next_round > 0 {
    let g = project_health_grade.to_lower()
    if g == "healthy" && blocked_tasks == 0 {
      should_stop = true
      stop_reason = "goal_reached: project is healthy with zero blocked tasks"
    }
  }

  // 3. exceeded（test 上 10%+ 或 open bug 下 50%+）
  //    BUG-162：同样首轮跳过（baseline 可能是 0 或手工占位）
  if !should_stop && lp.stop_on_exceeded && next_round > 0 {
    let mut exceeded_hit = false
    if lp.baseline_test_count > 0 {
      let growth : Double = (current_test_count - lp.baseline_test_count).to_double() /
        lp.baseline_test_count.to_double() *
        100.0
      if growth >= 10.0 {
        exceeded_hit = true
      }
    }
    if !exceeded_hit && lp.baseline_open_bug_count > 0 {
      let drop : Double = (lp.baseline_open_bug_count - current_open_bug_count).to_double() /
        lp.baseline_open_bug_count.to_double() *
        100.0
      if drop >= 50.0 {
        exceeded_hit = true
      }
    }
    if exceeded_hit {
      should_stop = true
      stop_reason = "exceeded: baseline_test=" +
        lp.baseline_test_count.to_string() +
        " -> now=" +
        current_test_count.to_string() +
        ", open_bugs=" +
        lp.baseline_open_bug_count.to_string() +
        " -> now=" +
        current_open_bug_count.to_string()
    }
  }

  // --- 组装 loop_after ---
  let stop_is_goal = should_stop && stop_reason.has_prefix("goal_reached")
  let stop_is_exceeded = should_stop && stop_reason.has_prefix("exceeded")
  let loop_after : PipelineLoop = PipelineLoop::{
    name: lp.name,
    steps: lp.steps,
    current_idx: next_idx,
    round: next_round,
    max_rounds: lp.max_rounds,
    stop_on_goal: lp.stop_on_goal,
    stop_on_exceeded: lp.stop_on_exceeded,
    created_at: lp.created_at,
    updated_at: now,
    stop_reason,
    goal_reached: stop_is_goal,
    exceeded: stop_is_exceeded,
    baseline_test_count: lp.baseline_test_count,
    baseline_open_bug_count: lp.baseline_open_bug_count,
  }

  LoopTickResult::{
    loop_id: lp.name,
    next_mode,
    next_step_idx: next_idx,
    next_round,
    should_stop,
    stop_reason,
    history_json: Json::object(
      Map([
        ("loop_id", Json::string(lp.name)),
        ("action", Json::string("tick")),
        ("from_idx", Json::number(lp.current_idx.to_double())),
        ("next_mode", Json::string(next_mode)),
        ("to_idx", Json::number(next_idx.to_double())),
        ("round", Json::number(next_round.to_double())),
        ("should_stop", Json::boolean(should_stop)),
        ("stop_reason", Json::string(stop_reason)),
      ]),
    ),
    loop_after,
  }
}

///|
/// LoopStatus 到字符串
pub fn loop_status_str(s : LoopStatus) -> String {
  match s {
    Active => "active"
    MaxRoundsHit => "max_rounds_hit"
    GoalReached => "goal_reached"
    Exceeded => "exceeded"
    NoSteps => "no_steps"
  }
}

///|
/// PipelineLoop 到 JSON（供 server 层返回）
pub fn loop_to_json(lp : PipelineLoop) -> Json {
  let status_str = if lp.stop_reason == "" {
    "active"
  } else if lp.goal_reached {
    "goal_reached"
  } else if lp.exceeded {
    "exceeded"
  } else {
    "stopped"
  }
  let steps_json = lp.steps.map(fn(s) { Json::string(s) })
  Json::object(
    Map([
      ("name", Json::string(lp.name)),
      ("steps", Json::array(steps_json)),
      ("current_idx", Json::number(lp.current_idx.to_double())),
      ("round", Json::number(lp.round.to_double())),
      ("max_rounds", Json::number(lp.max_rounds.to_double())),
      ("stop_on_goal", Json::boolean(lp.stop_on_goal)),
      ("stop_on_exceeded", Json::boolean(lp.stop_on_exceeded)),
      ("created_at", Json::string(lp.created_at)),
      ("updated_at", Json::string(lp.updated_at)),
      ("status", Json::string(status_str)),
      ("stop_reason", Json::string(lp.stop_reason)),
      ("goal_reached", Json::boolean(lp.goal_reached)),
      ("exceeded", Json::boolean(lp.exceeded)),
      ("baseline_test_count", Json::number(lp.baseline_test_count.to_double())),
      (
        "baseline_open_bug_count",
        Json::number(lp.baseline_open_bug_count.to_double()),
      ),
    ]),
  )
}

///|
/// 校验 steps 合法性：每步都是 7 种合法 mode 之一
pub fn validate_loop_steps(steps : Array[String]) -> String? {
  if steps.length() == 0 {
    return Some("steps is empty")
  }
  let valid_modes = [
    "advance", "polish", "verify", "bugfind", "fix_and_merge", "tidy", "explore",
  ]
  for s in steps {
    let mut ok = false
    for m in valid_modes {
      if s.to_lower() == m {
        ok = true
        break
      }
    }
    if !ok {
      return Some(
        "invalid step mode: " +
        s +
        ". must be one of: advance, polish, verify, bugfind, fix_and_merge, " +
        "tidy, explore",
      )
    }
  }
  None
}

// ---------------------------------------------------------------------------
// LoopRegistry —— 进程内组合环注册表（模仿 AuditLog 模式）
// ---------------------------------------------------------------------------

///|
pub struct LoopRegistry {
  loops : Map[String, PipelineLoop]
}

///|
pub fn LoopRegistry::new() -> LoopRegistry {
  { loops: Map([]), }
}

///|
/// 注册/更新一个组合环
pub fn LoopRegistry::set(
  self : LoopRegistry,
  name : String,
  lp : PipelineLoop,
) -> Unit {
  self.loops.set(name, lp)
}

///|
/// 按 name 取环状态
pub fn LoopRegistry::get(self : LoopRegistry, name : String) -> PipelineLoop? {
  self.loops.get(name)
}

///|
/// 删除一个环
pub fn LoopRegistry::remove(self : LoopRegistry, name : String) -> Unit {
  self.loops.remove(name)
}

///|
/// 列出所有已注册环的 name
pub fn LoopRegistry::list_names(self : LoopRegistry) -> Array[String] {
  self.loops.keys().to_array()
}

// ---------------------------------------------------------------------------
// JSON → PipelineLoop（轮 192 · loop 状态持久化的**读回面**）
//
// 为什么在这里、而落盘 IO 不在这里：本文件的设计原则是「纯计算零 IO」
// （文件头），落盘/读盘的编排在 src/server/server.mbt 的 loop 段（loop_store_*）。
// 序列化用现成的 `loop_to_json`，反序列化必须与它**同一套字段名**——
// 改了任一边就是「写进去、读不回」的静默丢状态，白盒锁
// src/ops/ops_loop_persist_wbtest.mbt 用往返逐字段相等 + 变异对照钉这一条。
// ---------------------------------------------------------------------------

///|
/// 取字符串字段（缺失/类型不符 → None；不静默当空串——空串在这里是「没这个字段」）
fn loop_rec_str(obj : Map[String, Json], key : String) -> String? {
  match obj.get(key) {
    Some(Json::String(s)) => Some(s)
    _ => None
  }
}

///|
/// 取布尔字段
fn loop_rec_bool(obj : Map[String, Json], key : String) -> Bool? {
  match obj.get(key) {
    Some(Json::True) => Some(true)
    Some(Json::False) => Some(false)
    _ => None
  }
}

///|
/// 取整数字段：Json number 承载是 Double，越界钳到 Int32 两端，NaN → None。
///
/// 为什么钳而不是直接 `to_int()`：落盘面是文本、可能被半截写或人工改过，
/// `1e300` 直接转在 js 侧是不确定值；钳位让「读回一个能跑的环」胜过「整行作废」，
/// 而 NaN 两边比较都不成立 ⇒ 走 None（这一支由白盒锁覆盖）。
fn loop_rec_int(obj : Map[String, Json], key : String) -> Int32? {
  match obj.get(key) {
    Some(Json::Number(n, ..)) =>
      if n >= -2147483648.0 && n <= 2147483647.0 {
        Some(n.to_int())
      } else if n > 2147483647.0 {
        Some(2147483647)
      } else if n < -2147483648.0 {
        Some(-2147483648)
      } else {
        None
      }
    _ => None
  }
}

///|
/// 取 steps：数组里每个都必须是字符串（混进数字/对象 ⇒ 整行判非法，不半收）
fn loop_rec_steps(obj : Map[String, Json]) -> Array[String]? {
  match obj.get("steps") {
    Some(Json::Array(arr)) => {
      let out : Array[String] = []
      for it in arr {
        match it {
          Json::String(s) => out.push(s)
          _ => return None
        }
      }
      Some(out)
    }
    _ => None
  }
}

///|
/// 逐字段取回一个 PipelineLoop（14 个字段全在 `loop_to_json` 的输出里）。
fn loop_rec_loop(obj : Map[String, Json]) -> PipelineLoop? {
  let name = match loop_rec_str(obj, "name") {
    Some(s) => s
    None => return None
  }
  // 空 name 的行不是环（LoopRegistry 以 name 为键，空键会让读回的环无从寻址）
  if name.is_empty() {
    return None
  }
  let steps = match loop_rec_steps(obj) {
    Some(s) => s
    None => return None
  }
  let current_idx = match loop_rec_int(obj, "current_idx") {
    Some(v) => v
    None => return None
  }
  let round = match loop_rec_int(obj, "round") {
    Some(v) => v
    None => return None
  }
  let max_rounds = match loop_rec_int(obj, "max_rounds") {
    Some(v) => v
    None => return None
  }
  let stop_on_goal = match loop_rec_bool(obj, "stop_on_goal") {
    Some(v) => v
    None => return None
  }
  let stop_on_exceeded = match loop_rec_bool(obj, "stop_on_exceeded") {
    Some(v) => v
    None => return None
  }
  let created_at = match loop_rec_str(obj, "created_at") {
    Some(v) => v
    None => return None
  }
  let updated_at = match loop_rec_str(obj, "updated_at") {
    Some(v) => v
    None => return None
  }
  let stop_reason = match loop_rec_str(obj, "stop_reason") {
    Some(v) => v
    None => return None
  }
  let goal_reached = match loop_rec_bool(obj, "goal_reached") {
    Some(v) => v
    None => return None
  }
  let exceeded = match loop_rec_bool(obj, "exceeded") {
    Some(v) => v
    None => return None
  }
  let baseline_test_count = match loop_rec_int(obj, "baseline_test_count") {
    Some(v) => v
    None => return None
  }
  let baseline_open_bug_count = match
    loop_rec_int(obj, "baseline_open_bug_count") {
    Some(v) => v
    None => return None
  }
  Some(PipelineLoop::{
    name,
    steps,
    current_idx,
    round,
    max_rounds,
    stop_on_goal,
    stop_on_exceeded,
    created_at,
    updated_at,
    stop_reason,
    goal_reached,
    exceeded,
    baseline_test_count,
    baseline_open_bug_count,
  })
}

///|
/// JSON → PipelineLoop：`loop_to_json` 的**逆运算**（轮 192 持久化读回面）。
///
/// 形状不合法一律 `None`（不抛、不半收）：追加式 JSONL 允许出现半截行与
/// 别的写入方的行，解析侧必须**跳过**那一行而不是让整次读回失败。
///
/// **不在这里重跑 `validate_loop_steps`**：合法创建的环不该因为 mode 白名单
/// 将来收窄而读不回来（读不回 = 静默丢状态，比读回一个非法 mode 更坏）；
/// 非法 mode 的兜底在调用侧（pipeline_tick 自己会拒未知 mode）。
pub fn loop_from_json(j : Json) -> PipelineLoop? {
  match j {
    Json::Object(obj) => loop_rec_loop(obj)
    _ => None
  }
}
