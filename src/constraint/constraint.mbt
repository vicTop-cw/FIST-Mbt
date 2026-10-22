/// constraint.mbt —— 多 agent 文件锁裁决语义的「政策侧镜像」演示包（顺带看看锁机制）
///
/// ⚠️ 定位澄清（2026-10-13 第 2 轮复核）：BACKLOG L38「毫秒级符号逻辑引擎」的
/// **规范实现是另一条并发 lane 的 `src/symbolic/` 包（Tseitin CNF + DPLL SAT）**，
/// 本包**不是** L38 的实现，也无意与之竞争。本包的存在意义是"B=顺带看看锁机制"
/// 的示范面：把 store 层 `rsv_action` 的冲突裁决动词**逐字镜像**到约束层，证明
/// 政策层可以不耦合 in-flight 的 store 包、独立编译测试地复用同一套冲突语义。
///
/// 设计目标：在「计划动作」真正落到磁盘 / 落库之前，用一组纯布尔约束先行裁决
/// 是否允许。本引擎刻意**零副作用、零 IO**，只消费一个只读 `WorldState` 快照，
/// 因此可被白盒测试、可被 `explore` 模式的并行分支在认领作用域前预检。
///
/// 与多 agent 文件锁机制的关系（本包即"B=顺带看看锁机制"的示范面）：
/// 约束 `eval_no_overlap` 直接复用锁的裁决动词 `rsv_conflict_verdict`
/// （= `src/store/store_rsv.mbt::rsv_action` 的**忠实镜像**，逐字一致：
///  `reserved | renewed | taken_over | conflict`）。也就是说，政策层与锁机制
///  共用同一套冲突语义——两个 agent 想在同一 live 作用域上写，约束层给出
///  `conflict`，正是 `reserve_scope` / `lock_acquire` 在 store 侧会写下的同一结论。
///
/// 单一真源说明（避免漂移）：`rsv_action` 才是裁决的规范真源；本包的
///  `rsv_conflict_verdict` 是一份**政策侧镜像**，目的在于让约束层不耦合到
///  in-flight 的 store 包即可独立编译与测试。后续待办：把两者收敛到同一个共享
///  纯模块，使语义只在一处定义。

///|
/// 当前世界状态快照（只读输入）。`reservations` 仅含"当前仍 active"的预订；
/// `agents` 为已登记执行者集合。
pub struct WorldState {
  reservations : Array[ActiveReservation]
  agents : Array[String]
}

///|
/// 一条当前 active 的作用域预订。
pub struct ActiveReservation {
  scope : String
  holder : String
  ttl_until : String
}

///|
/// 一个计划动作：某 agent 想要对一组作用域做某种操作。
pub struct PlannedAction {
  agent : String
  scopes : Array[String]
  /// 当前时刻（与 `ttl_until` 同格式，建议零填充以便字典序==数值序）。
  now : String
}

///|
/// 裁决结果。`allowed=false` 时 `reasons` 给出每条被违反的约束说明。
pub struct Verdict {
  allowed : Bool
  reasons : Array[String]
}

///|
/// 锁裁决动词的忠实镜像（= `src/store/store_rsv.mbt::rsv_action` L77-88）。
/// 给定写前快照 `prev = (owner, ttl_until, created_at)?` 与本次请求
/// `(agent, now)`，返回 `(是否可写, 动作标签)`：
///   None                        -> (true,  "reserved")   空闲，新预订
///   owner == agent              -> (true,  "renewed")   本人续订
///   ttl_until < now             -> (true,  "taken_over") 旧主已过期，接管
///   其它                        -> (false, "conflict")   被他人 live 持有
///
/// 注意：本函数是 store 侧裁决的**镜像**，不是锁机制本身；锁机制把这里的
///  `conflict` 落到 `reservations` 表的 `ON CONFLICT ... WHERE` 并写
///  `lock_violations`（见 `locks_upsert` / `locks_sweep`）。
pub fn rsv_conflict_verdict(
  prev : (String, String, String)?,
  agent : String,
  now : String,
) -> (Bool, String) {
  match prev {
    None => (true, "reserved")
    Some((owner, _, _)) if owner == agent => (true, "renewed")
    Some((_, ttl, _)) if ttl < now => (true, "taken_over")
    _ => (false, "conflict")
  }
}

///|
/// 约束 1：执行者必须已登记（防幽灵 agent 落库）。
pub fn eval_known_agent(state : WorldState, action : PlannedAction) -> Verdict {
  if state.agents.contains(action.agent) {
    Verdict::{ allowed: true, reasons: [], }
  } else {
    Verdict::{ allowed: false, reasons: ["unknown agent: " + action.agent], }
  }
}

///|
/// 约束 2：同一动作申报的作用域必须两两不相交（同一 scope 不得列两次）。
pub fn eval_disjoint_scopes(
  _state : WorldState,
  action : PlannedAction,
) -> Verdict {
  let seen : Set[String] = Set([])
  for s in action.scopes {
    if seen.contains(s) {
      return Verdict::{
        allowed: false,
        reasons: ["scope declared twice in one action: " + s],
      }
    }
    seen.add(s)
  }
  Verdict::{ allowed: true, reasons: [], }
}

///|
/// 约束 3（核心·多 agent 锁示范）：动作想碰的每个作用域，不得被"其它 live agent"
/// 持有。复用锁的 `rsv_conflict_verdict` 判定：本人续订 / 旧主已过期 都放行，
/// 只有 live 的他者持有才判 `conflict`。
pub fn eval_no_overlap(state : WorldState, action : PlannedAction) -> Verdict {
  let reasons : Array[String] = []
  let seen : Set[String] = Set([])
  for s in action.scopes {
    // 同一 action 里重复申报同一 scope：只对第一个实例裁决，避免重复冲突消息
    if seen.contains(s) {
      continue
    }
    seen.add(s)
    match find_active(state, s) {
      None => () // 空闲，无冲突
      Some(r) => {
        let (may, verdict) = rsv_conflict_verdict(
          Some((r.holder, r.ttl_until, "")),
          action.agent,
          action.now,
        )
        if !may {
          let msg = "scope '" +
            s +
            "' " +
            verdict +
            ": held by '" +
            r.holder +
            "' (ttl " +
            r.ttl_until +
            ")"
          reasons.push(msg)
        }
      }
    }
  }
  if reasons.is_empty() {
    Verdict::{ allowed: true, reasons: [], }
  } else {
    Verdict::{ allowed: false, reasons, }
  }
}

///|
fn find_active(state : WorldState, scope : String) -> ActiveReservation? {
  for r in state.reservations {
    if r.scope == scope {
      return Some(r)
    }
  }
  None
}

///|
/// 组合裁决：依次跑所有约束，任一 `allowed=false` 即整体拒绝并汇总原因。
/// 约束之间是与关系（全部通过才放行）。
pub fn eval_all(
  state : WorldState,
  action : PlannedAction,
  evals : Array[(WorldState, PlannedAction) -> Verdict],
) -> Verdict {
  let reasons : Array[String] = []
  for f in evals {
    let v = f(state, action)
    if !v.allowed {
      for r in v.reasons {
        reasons.push(r)
      }
    }
  }
  if reasons.is_empty() {
    Verdict::{ allowed: true, reasons: [], }
  } else {
    Verdict::{ allowed: false, reasons, }
  }
}

///|
/// 默认约束集：登记检查 + 作用域不相交 + 多 agent 锁互斥。
pub fn eval_default(state : WorldState, action : PlannedAction) -> Verdict {
  eval_all(state, action, [
    eval_known_agent, eval_disjoint_scopes, eval_no_overlap,
  ])
}
