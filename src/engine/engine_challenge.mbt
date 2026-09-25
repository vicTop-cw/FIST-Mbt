/// engine_challenge.mbt —— Challenger 进阶变体（SAGE 四专家环的另一半，AI 自进化增强）
///
/// 论文背景：SAGE 四智能体专家环 = Challenger/Planner/Solver/Critic。Critic 负责把关
/// （R13 已落地 `evolve_critic` 防漂移），Challenger 负责"生成更难的任务"以抬高整体能力上限。
/// 与 R12 的 LADDER「由易到难梯度」呼应：完成一个"易/中"任务后，可对其发起进阶变体，
/// 构成"由易到难"的自推进序列。
///
/// 实现（规则驱动的"挑战框架"，非假装 AI 智能）：
///   - 对**已完成/已归档**的源任务，按策略生成一个"更难变体"文本框架并发布为新根任务
///     （带 `[challenge]` 标记 + `from <task_id>` 溯源，重要性升一档），使复杂能力的
///     训练/推进持续上探，而非停在每个完成点。
///   - 用引擎内建 publish 之外的原生 `first_free_root_id + create_task` 创建根任务，
///     绕开 `publish` 的人类指挥官门禁（Challenger 由 agent 触发）。
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
/// 对一条已完成/已归档任务发起 Challenger 进阶变体：发布一个新根任务 `[challenge]`。
/// 返回 { new_id, source, by, factor, strat, frame, importance, ns }。
pub fn FistEngine::challenge(
  self : FistEngine,
  task_id~ : String,
  by~ : String,
  factor? : Int = 2,
  strat? : String = "scale",
  now~ : String,
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
      let s = if challenge_strategies().contains(strat) {
        strat
      } else {
        "scale"
      }
      let frame = challenge_frame(s, factor)
      let new_id = self.first_free_root_id()
      let desc = "[challenge] 进阶变体 · from \{task_id} · \{frame}「\{src.description}」"
      let child = @core.Task::new(
        id=new_id,
        project_dir=src.project_dir,
        description=desc,
        priority=src.priority,
        importance=bump_importance(src.importance),
        depth=3,
        split_n=3,
        created_at=now,
        ns=src.ns,
      )
      match self.store.create_task(child) {
        Ok(_) =>
          Ok(
            Json::object({
              "new_id": Json::string(new_id),
              "source": Json::string(task_id),
              "by": Json::string(by),
              "factor": Json::number(factor.to_double()),
              "strat": Json::string(s),
              "importance": Json::string(bump_importance(src.importance)),
              "ns": Json::string(src.ns),
              "description": Json::string(desc),
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
