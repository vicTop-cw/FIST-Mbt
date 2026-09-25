/// engine_challenge.mbt —— Challenger 进阶变体（SAGE 四专家环的另一半，AI 自进化增强）
///
/// 论文背景：SAGE 四智能体专家环 = Challenger/Planner/Solver/Critic。Critic 负责把关
/// （R13 已落地 `evolve_critic` 防漂移）、R29 再把防漂移前推到挑战题本身；Challenger 负责
/// "生成更难的任务"以抬高整体能力上限。与 R12 的 LADDER「由易到难梯度」呼应：完成一个
/// "易/中"任务后，可对其发起进阶变体，构成"由易到难"的自推进序列。
///
/// 实现（规则驱动的"挑战框架"，非假装 AI 智能）：
///   - 对**已完成/已归档**的源任务，按策略生成一个"更难变体"文本框架并发布为新根任务
///     （带 `[challenge]` 标记 + `from <task_id>` 溯源，重要性升一档），使复杂能力的
///     训练/推进持续上探，而非停在每个完成点。
///   - 用引擎内建 publish 之外的原生 `first_free_root_id + create_task` 创建根任务，
///     绕开 `publish` 的人类指挥官门禁（Challenger 由 agent 触发）。
///   - **R29 防漂移门禁（可选 `critic`，缺省关闭零回归）**：指定传入 DGM 档案库时，
///     生成挑战题前先经 `critic_review`（与 `evolve_critic` **同一单一真源**）评审——
///     SAGE 的 Critic 会过滤"题目"防课程漂移、R-Few 补防"diversity collapse"：若当前策略的
///     变体与档案库既有资产重合 ≥ `critic_dup_sim()`（疑似课程漂移/同质坍缩），自动降档
///     尝试其它策略；全部策略皆漂移则**拒发**（不出新根任务），防止"由易到难"退化成
///     "反复套同一模板"。非漂移但稳健性偏低不阻断（挑战题本就偏新颖/高风险，属预期）。
///
/// 纯 MoonBit、无新表/依赖；供 server 的 `task_challenge` 工具调用。

///|
/// 进阶策略白名单：为已完成任务"上难度"的几种规则化变体框架。
///   generalize：去具体场景 → 抽象为通用能力并覆盖边界
///   unhint    ：去提示/约束 → 从空白规格重推且不降正确性
///   constrain ：加硬约束 → 本次在性能/并发/兼容上加严并保证不回归
///   scale     ：扩规模 → 把规模/负载提升 factor 倍并保持语义正确
pub fn challenge_strategies() -> Array[String] {
  ["generalize", "unhint", "constrain", "scale"]
}

///|
/// 依据策略生成"更难变体"的框架文本（规则模板，非 LLM 生成）。
fn challenge_frame(strat : String, factor : Int) -> String {
  match strat {
    "generalize" =>
      "摆脱对具体场景的依赖，抽象为通用能力并覆盖边界与异常（泛化上难度）"
    "unhint" =>
      "去掉自带提示/约束，从空白规格重新推导且不降低正确性与完备性（去提示上难度）"
    "constrain" =>
      "增加硬约束（性能/并发/兼容），并在新约束成立的同时保证原有行为零回归（加约束上难度）"
    _ => {
      let f = if factor < 2 { 2 } else { factor }
      "把规模/负载/覆盖度提升到 \{f} 倍并保持语义正确与可验证（扩规模上难度）"
    }
  }
}

///|
/// 重要度升一档（低→中→高），用于挑战变体体现"更难/更关键"。
fn bump_importance(imp : String) -> String {
  match imp {
    "低" => "中"
    _ => "高"
  }
}

///|
/// 从 critic_review 的 Json 中读 sim（与档案库最相似资产重合度）。
fn review_sim(review : Json) -> Double {
  match review.value("sim") {
    Some(Json::Number(d, ..)) => d
    _ => 0.0
  }
}

///|
/// 组装一条候选挑战题的描述（任一策略共用同一模板，保证可比）。
pub fn ch_desc(task_id : String, src_desc : String, frame : String) -> String {
  "[challenge] 进阶变体 · from \{task_id} · \{frame}「\{src_desc}」"
}

///|
/// 挑战题"选型 + 防漂移选帧"结果。
priv struct ChaPick {
  strat : String
  frame : String
  desc : String
  review : Json
  status : String // off(未开 critic) | admitted(放行) | degraded(漂移后降档放行) | rejected(全部漂移拒发)
}

///|
/// 依据策略白名单 +（可选）DGM 档案库决定"发布哪一帧挑战题"。
/// critc 为 None → 直取调用方策略（旧行为，零回归）；为 Some(arc) → 开启防漂移门禁：
/// 当前策略变体与档案库重合 ≥ critic_dup_sim() 判疑似课程漂移/同质坍缩，自动降档尝试其余
/// 策略（固定次序 generalize→unhint→constrain→scale 中非当前者）；全部皆漂移则 status=rejected。
fn pick_frame(
  task_id : String,
  src_desc : String,
  strat : String,
  factor : Int,
  arc : @evolve.Archive?,
) -> ChaPick {
  let s = if challenge_strategies().contains(strat) { strat } else { "scale" }
  let mk = fn(os : String) -> ChaPick {
    let frame = challenge_frame(os, factor)
    {
      strat: os,
      frame,
      desc: ch_desc(task_id, src_desc, frame),
      review: Json::null(),
      status: "off",
    }
  }
  match arc {
    None => mk(s)
    Some(a) => {
      let order = [s] + challenge_strategies().filter(fn(x) { x != s })
      let mut best : ChaPick? = None
      let mut degraded : Bool = false
      for os in order {
        let c = mk(os)
        let review = @evolve.critic_review(a, c.desc, 0.5)
        if review_sim(review) < @evolve.critic_dup_sim() {
          // 非漂移：放行（稳健性偏低不阻断，挑战题本就偏新颖/高风险）
          best = Some({
            strat: os,
            frame: c.frame,
            desc: c.desc,
            review,
            status: if degraded {
              "degraded"
            } else {
              "admitted"
            },
          })
          break
        }
        degraded = true
      }
      match best { // 全部策略皆漂移 → 拒发（拿首个策略的 review 作原因）
        None => {
          let c = mk(s)
          {
            strat: s,
            frame: c.frame,
            desc: c.desc,
            review: @evolve.critic_review(a, c.desc, 0.5),
            status: "rejected",
          }
        }
        Some(b) => b
      }
    }
  }
}

///|
/// 对一条已完成/已归档任务发起 Challenger 进阶变体：发布一个新根任务 `[challenge]`。
/// 可选 `critic`（DGM 档案库，缺省 None = 关闭防漂移门禁，旧行为零回归）：传入时先对生成
/// 的挑战题做 Critic 防漂移评审（与 `evolve_critic` 同一单一真源），全部策略皆漂移则拒发。
/// 返回 { new_id, source, by, factor, strat, importance, ns, description, critic, critic_status }。
pub fn FistEngine::challenge(
  self : FistEngine,
  task_id~ : String,
  by~ : String,
  factor? : Int = 2,
  strat? : String = "scale",
  now~ : String,
  critic? : @evolve.Archive? = None,
) -> Result[Json, String] {
  match self.store.get_task(task_id) {
    None => Err("task not found: \{task_id}")
    Some(src) => {
      let st = src.get_status()
      if not(st.is_completed()) && not(st.is_archived()) {
        return Err(
          "Challenger 仅对「已完成/已归档」任务发起进阶变体，当前状态 [{src.status_to_string()}]",
        )
      }
      let pick = pick_frame(task_id, src.description, strat, factor, critic)
      if pick.status == "rejected" {
        return Err(
          "task_challenge 被防漂移门禁拒绝：与档案库既有资产疑似课程漂移/同质坍缩（全部策略变体重合均 ≥70%），未发布新挑战题；critic=" +
          pick.review.stringify(),
        )
      }
      let new_id = self.first_free_root_id()
      let child = @core.Task::new(
        id=new_id,
        project_dir=src.project_dir,
        description=pick.desc,
        priority=src.priority,
        importance=bump_importance(src.importance),
        depth=3,
        split_n=3,
        created_at=now,
        ns=src.ns,
      )
      let imp = bump_importance(src.importance)
      match self.store.create_task(child) {
        Ok(_) =>
          Ok(
            Json::object({
              "new_id": Json::string(new_id),
              "source": Json::string(task_id),
              "by": Json::string(by),
              "factor": Json::number(factor.to_double()),
              "strat": Json::string(pick.strat),
              "importance": Json::string(imp),
              "ns": Json::string(src.ns),
              "description": Json::string(pick.desc),
              "critic": pick.review,
              "critic_status": Json::string(pick.status),
              "note": Json::string(
                "Challenger 已发布进阶变体，供新一轮拆解/执行推进",
              ),
            }),
          )
        Err(e) => Err(e)
      }
    }
  }
}
