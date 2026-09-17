///|
/// —— 外部判据闸门（[gate:required]，默认关闭即现状）——
///
/// 背景：LLM 执行方与 LLM 测试方同源，"cargo test 全绿"不构成验收判据
/// （自写自测恒绿）。本闸门是流水线中第一个**非 LLM 判据源**的强制关口：
///   1) 任务 description 含 [gate:required] 时，verify 之前必须先由
///      服务端 run_check 工具**真实执行**一条外部命令（如 bash
///      scripts/e2e_golden.sh：真跑可执行产物 + golden diff）并把结果
///      落库（specs 表，spec_type="check"，status="passed"/"failed"）；
///   2) 闸门校验该记录**新鲜**——检查时间必须不早于任务最后一次
///      updated_at（防止改完代码后用旧的一次通过记录蒙混）；
///   3) 未标记任务行为与现状完全一致（零侵入）。
///
/// 记录 content 为 run_check 产出的 JSON 文本（exit/stdout/stderr），
/// 人类可直接在库内复核真实命令输出。

///|
/// 外部判据标记：出现在任务 description 中即表示该任务验收必须过闸门。
pub fn gate_mark() -> String {
  "[gate:required]"
}

///|
/// 任务是否开启外部判据闸门。
pub fn gate_enabled(t : @core.Task) -> Bool {
  t.get_description().contains(gate_mark())
}

///|
/// 记录一次外部命令检查结果（status = "passed" 当且仅当 exit_code==0）。
/// 记录 id = check:<task_id>:r<round>（round = 该任务已有 check 记录数 + 1）。
pub fn FistEngine::gate_check_record(
  self : FistEngine,
  task_id : String,
  check_json : String,
  status : String,
  now : String,
) -> Result[Json, String] {
  match self.store.get_task(task_id) {
    None => Err("task not found: \{task_id}")
    Some(_) => {
      let round = self.omega_count_type(task_id, "check") + 1
      let rec = @store.SpecRecord::new(
        id="check:\{task_id}:r\{round}",
        task_id~,
        spec_type="check",
        content=check_json,
        status~,
        created_at=now,
        updated_at=now,
      )
      match self.store.upsert_spec(rec) {
        Err(e) => Err(e)
        Ok(_) => {
          let m : Map[String, Json] = Map([])
          m.set("ok", Json::boolean(true))
          m.set("check_id", Json::string(rec.id))
          m.set("task_id", Json::string(task_id))
          m.set("round", Json::number(round.to_double()))
          m.set("status", Json::string(status))
          m.set(
            "note",
            Json::string(
              "外部判据已落库；若任务带 [gate:required]，verify 将校验本记录新鲜度（created_at >= 任务 updated_at）",
            ),
          )
          Ok(Json::object(m))
        }
      }
    }
  }
}

///|
/// 验收前闸门：[gate:required] 任务须存在**最新且通过且新鲜**的 check 记录。
/// 未标记任务直接放行（默认关闭即现状）。
pub fn FistEngine::gate_verify_gate(
  self : FistEngine,
  task_id : String,
) -> Result[Unit, String] {
  match self.store.get_task(task_id) {
    None => Ok(())
    Some(t) =>
      if !gate_enabled(t) {
        Ok(())
      } else {
        match self.omega_latest(task_id, "check") {
          None =>
            Err(
              "外部判据闸门：任务 [\{task_id}] 带 [gate:required]，但尚无外部检查记录。请先由服务端执行 run_check（真实运行外部命令并落库）",
            )
          Some(c) =>
            if c.status != "passed" {
              Err(
                "外部判据闸门：任务 [\{task_id}] 最新外部检查 [\{c.id}] 状态为 [\{c.status}]，未通过前禁止验收",
              )
            } else if c.created_at < t.get_updated_at() {
              Err(
                "外部判据闸门：任务 [\{task_id}] 的检查记录 [\{c.id}]（\{c.created_at}）早于任务最后更新（\{t.get_updated_at()}），代码可能已变更，请重新执行 run_check",
              )
            } else {
              Ok(())
            }
        }
      }
  }
}
