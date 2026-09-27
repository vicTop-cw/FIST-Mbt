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
/// 从 run_check 的检查结果 JSON 推导权威门禁状态：`ok == true`（即 exit_code==0）
/// 记为 "passed"，其余一律 "failed"（fail-closed）。不信任调用方传入的 status 字符串，
/// 防止伪造 "passed" 蒙混过关（与 gate_verify_gate 的判据一致）。
fn _derived_check_status(check_json : String) -> String {
  let parsed = @json.parse(check_json) catch { _ => return "failed" }
  match parsed {
    Object(m) =>
      match m.get("ok") {
        Some(True) => "passed"
        _ => "failed"
      }
    _ => "failed"
  }
}

///|
/// 从 run_check 的结果 JSON 里取某个文本字段的**末 n 个字符**（BUG-75）。
/// 判据红了只给退出码等于没给证据：调用方要么本地重跑一遍同一条命令（那就退回到
/// "自写自测"这条 run_check 正是要防的路径），要么整单打回却不知打回原因。
/// 解析失败 / 字段缺失 / 字段不是字符串一律回 ("", false)——记录已落库，
/// 取不到尾巴不该让回执本身失败。
fn _json_str_tail(check_json : String, key : String, n : Int) -> (String, Bool) {
  let parsed = @json.parse(check_json) catch { _ => return ("", false) }
  match parsed {
    Object(m) =>
      match m.get(key) {
        Some(String(s)) => {
          let cs = s.to_array()
          let len = cs.length()
          if len <= n {
            (s, false)
          } else {
            let out : Array[Char] = []
            let mut i = len - n
            while i < len {
              out.push(cs[i])
              i = i + 1
            }
            (String::from_array(out), true)
          }
        }
        _ => ("", false)
      }
    _ => ("", false)
  }
}

///|
/// 回执携带的输出尾巴上限（字符）。取"末 N"而不是"前 N"：判据的关键信息在结尾
/// （失败断言、汇总行、exit code 说明），前 N 往往是命令回显或进度条。
fn gate_check_tail_limit() -> Int {
  2000
}

///|
/// 记录一次外部命令检查结果（门禁状态从 check_json 的 ok/exit_code==0 推导，
/// status 参数已不参与判定，仅保留以维持公开签名兼容）。
/// 记录 id = check:<task_id>:r<round>（round = 该任务已有 check 记录数 + 1）。
pub fn FistEngine::gate_check_record(
  self : FistEngine,
  task_id : String,
  check_json : String,
  status : String,
  now : String,
) -> Result[Json, String] {
  // status 参数不再被信任：实际门禁状态一律由 check_json 推导
  ignore(status)
  let eff = _derived_check_status(check_json)
  match self.store.get_task(task_id) {
    None => Err("task not found: \{task_id}")
    Some(_) => {
      let round = self.omega_count_type(task_id, "check") + 1
      let rec = @store.SpecRecord::new(
        id="check:\{task_id}:r\{round}",
        task_id~,
        spec_type="check",
        content=check_json,
        status=eff,
        created_at=now,
        updated_at=now,
      )
      match self.store.upsert_spec(rec) {
        Err(e) => Err(e)
        Ok(_) => {
          let m : Map[String, Json] = Map([])
          let (out_tail, out_cut) = _json_str_tail(
            check_json,
            "stdout",
            gate_check_tail_limit(),
          )
          let (err_tail, err_cut) = _json_str_tail(
            check_json,
            "stderr",
            gate_check_tail_limit(),
          )
          m.set("ok", Json::boolean(true))
          m.set("check_id", Json::string(rec.id))
          m.set("task_id", Json::string(task_id))
          m.set("round", Json::number(round.to_double()))
          // BUG-75：回显**推导后**的门禁状态，不再回显调用方传入的 status——
          // 上面第 57 行已声明该参数不被信任，回执与记录分着说两套话就是给伪证留口子。
          m.set("status", Json::string(eff))
          // BUG-75：把判据的实际输出带回去（末 N 字符），passed 也带，
          // 否则"通过性证据"举不出判据打了什么，只能本地重跑同一条命令。
          m.set("stdout_tail", Json::string(out_tail))
          m.set("stderr_tail", Json::string(err_tail))
          m.set("output_truncated", Json::boolean(out_cut || err_cut))
          m.set(
            "note",
            Json::string(
              "外部判据已落库；若任务带 [gate:required]，verify 将校验本记录新鲜度（created_at >= 任务 updated_at）。stdout_tail/stderr_tail 为末 \{gate_check_tail_limit()} 字符，完整结果见 specs 表 content",
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
