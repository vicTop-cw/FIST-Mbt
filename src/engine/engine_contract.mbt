/// engine_contract.mbt —— 迁移契约检查（R109 · Design by Contract 蒸馏）。
/// 任何状态迁移动作先过 Meyer 三件套只读预检（precondition / invariant / postcondition），
/// 任一失败整笔拒绝、状态 A 回稳（不落库）。纯计算只读不写库（决策建议，执行权在调用方/指挥官）。

///|
/// 动作 → 文档化目标态（postcondition 基准；TaskStatus::to_string 为中文态名）。
fn contract_target_status(action : String) -> String? {
  match action {
    "claim" => Some("已领取")
    "split" => Some("拆分中")
    "execute" => Some("执行中")
    "submit" => Some("待验收")
    "reject" => Some("已打回")
    "retry" => Some("执行中")
    "pause" => Some("已暂停")
    "resume" => Some("已领取")
    "reopen" => Some("已领取")
    "complete" => Some("已完成")
    "archive" => Some("已归档")
    "mark_decomposing" => Some("拆分中")
    _ => None
  }
}

///|
/// 对任务值副本尝试执行动作（precondition 判定：Err 即前置失败，返回失败原文）。
fn contract_try(
  task : @core.Task,
  action : String,
  assignee : String,
  completed_by : String,
) -> Result[@core.Task, String] {
  match action {
    "claim" => task.claim(assignee=assignee)
    "split" => task.split()
    "execute" => task.execute()
    "submit" => task.submit()
    "reject" => task.reject()
    "retry" => task.retry()
    "pause" => task.pause()
    "resume" => task.resume_task()
    "reopen" => task.reopen()
    "complete" => task.complete(completed_by=completed_by)
    "archive" => task.archive()
    "mark_decomposing" => task.mark_decomposing()
    _ => Err("未知动作: " + action)
  }
}

///|
/// 领域不变量（throughout）：迁移后状态上校验，任一违反返回原因。
/// IN-1 id 非空 / IN-2 depth≥1（K 值合法）/ IN-3 split_n≥1 /
/// IN-4 身份保持（id/project_dir/ns 迁移前后一致）/ IN-5 assignee 纪律（claim/reopen 除外）。
fn invariant_violations(
  before : @core.Task,
  after : @core.Task,
  action : String,
) -> Array[String] {
  let out : Array[String] = []
  if after.id == "" {
    out.push("IN-1 违反: 任务 id 为空")
  }
  if after.depth < 1 {
    out.push("IN-2 违反: K 值非法（depth=" + after.depth.to_string() + "，须 ≥1）")
  }
  if after.split_n < 1 {
    out.push("IN-3 违反: split_n=" + after.split_n.to_string() + "，须 ≥1")
  }
  if after.id != before.id ||
    after.project_dir != before.project_dir ||
    after.ns != before.ns {
    out.push("IN-4 违反: 身份字段在迁移后漂移（id/project_dir/ns 须保持）")
  }
  if action != "claim" && action != "reopen" && after.assignee != before.assignee {
    out.push("IN-5 违反: assignee 在非认领/重开动作下漂移")
  }
  out
}

///|
/// 迁移契约检查（R109 · Design by Contract 蒸馏）：precondition / invariant / postcondition 三件套只读预检。
/// 任一失败 → verdict=rejected 整笔拒绝，状态 A 回稳（不落库）；全部通过 → verdict=allowed（建议仍走正式生命周期工具执行）。
pub fn FistEngine::transition_contract(
  self : FistEngine,
  task_id : String,
  action : String,
  assignee? : String = "agent",
  completed_by? : String = "human_steward",
) -> Json {
  match self.get_task(task_id) {
    None =>
      Json::object({
        "ok": Json::boolean(false),
        "task_id": Json::string(task_id),
        "action": Json::string(action),
        "note": Json::string("任务不存在: " + task_id),
      })
    Some(t) =>
      match contract_try(t, action, assignee, completed_by) {
        Err(msg) =>
          Json::object({
            "ok": Json::boolean(true),
            "task_id": Json::string(task_id),
            "action": Json::string(action),
            "phase": Json::string("precondition"),
            "verdict": Json::string("rejected"),
            "reasons": Json::array([Json::string(msg)]),
            "target_state": Json::string(""),
            "state_stable": Json::boolean(true),
            "note": Json::string(
              "迁移契约检查（Design by Contract）：precondition 失败 → 整笔拒绝，状态 A 回稳（不落库）。",
            ),
          })
        Ok(nt) =>
          if invariant_violations(t, nt, action).length() > 0 {
            Json::object({
              "ok": Json::boolean(true),
              "task_id": Json::string(task_id),
              "action": Json::string(action),
              "phase": Json::string("invariant"),
              "verdict": Json::string("rejected"),
              "reasons": Json::array(
                invariant_violations(t, nt, action).map(Json::string),
              ),
              "target_state": Json::string(""),
              "state_stable": Json::boolean(true),
              "note": Json::string(
                "迁移契约检查（Design by Contract）：precondition 通过但 invariant 违反 → 整笔拒绝，状态 A 回稳（不落库）。",
              ),
            })
          } else {
            match contract_target_status(action) {
              None =>
                Json::object({
                  "ok": Json::boolean(true),
                  "task_id": Json::string(task_id),
                  "action": Json::string(action),
                  "phase": Json::string("postcondition"),
                  "verdict": Json::string("rejected"),
                  "reasons": Json::array([Json::string("动作无契约定义")]),
                  "target_state": Json::string(""),
                  "state_stable": Json::boolean(true),
                  "note": Json::string("迁移契约检查：动作不在契约表内。"),
                })
              Some(target) =>
                if nt.status_to_string() != target {
                  Json::object({
                    "ok": Json::boolean(true),
                    "task_id": Json::string(task_id),
                    "action": Json::string(action),
                    "phase": Json::string("postcondition"),
                    "verdict": Json::string("rejected"),
                    "reasons": Json::array([
                      Json::string(
                        "postcondition 违反: 目标态 [" + nt.status_to_string() +
                          "] ≠ 文档化目标态 [" + target + "]",
                      ),
                    ]),
                    "target_state": Json::string(""),
                    "state_stable": Json::boolean(true),
                    "note": Json::string(
                      "迁移契约检查（Design by Contract）：postcondition 失败 → 整笔拒绝，状态 A 回稳（不落库）。",
                    ),
                  })
                } else {
                  Json::object({
                    "ok": Json::boolean(true),
                    "task_id": Json::string(task_id),
                    "action": Json::string(action),
                    "phase": Json::string("all_pass"),
                    "verdict": Json::string("allowed"),
                    "reasons": Json::array([]),
                    "target_state": Json::string(target),
                    "state_stable": Json::boolean(true),
                    "note": Json::string(
                      "迁移契约检查（Design by Contract）：precondition/invariant/postcondition 全通过，可安全迁移（建议仍走正式生命周期工具执行）。",
                    ),
                  })
                }
            }
          }
      }
  }
}
