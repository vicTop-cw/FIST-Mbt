/// engine/omega_strong.mbt — 可选「Omega 强验证」开关（默认关闭）。
///
/// 设计原则（三条）：
///   1) 默认关闭即现状：未开启强验证的任务，publish / claim / plan / execute /
///      submit / verify / archive 的既有语义与行为**完全不变**。本文件所有逻辑
///      都以「任务 description 是否带 [omega:required] 标记」为唯一开关判据。
///   2) 开启后为「语料驱动」的两道关卡（递归拆解的每一轮）：
///        · 执行前：语料创建者（spec_author）写语料 → 验证者（verifier）审核，
///          不通过则打回重做，通过后才放行执行（omega_execute_gate）。
///        · 验收前：执行者产出成果后，验证者对成果与语料复验，不达标则打回重做，
///          通过后才放行验收（omega_verify_gate）。
///   3) 打回有上限、超限必升级：每类打回最多 max_rounds（默认 3，硬上限 10）次，
///      超限不再循环，而是写 escalation 记录 + 暂停任务，转人工裁决（防死循环）。

///|
/// 强验证标记：出现在任务 description 中即表示该任务处于强验证模式。
pub fn omega_mark() -> String {
  "[omega:required]"
}

///|
/// 语料 author 前缀（纯文本行，避免为嵌入 author 而引入 JSON 转义）。
pub fn omega_author_prefix() -> String {
  "OMEGA-AUTHOR: "
}

///|
/// 任务是否处于强验证模式（未打标记 = 关闭 = 既有行为）。
pub fn omega_enabled(t : @core.Task) -> Bool {
  t.description.contains(omega_mark())
}

///|
/// 去掉切片文本中已存在的强验证标记（避免递归下钻时标记逐层累积）。
pub fn omega_clean_slice(s : String) -> String {
  let mark = omega_mark()
  if !s.contains(mark) {
    return s
  }
  let mut out = ""
  for part in s.split(mark) {
    out = out + part.to_string()
  }
  out.trim().to_string()
}

///|
/// 默认最大打回轮次。
pub fn omega_max_rounds_default() -> Int {
  3
}

///|
/// 归一化轮次上限：非正数取默认，超过 10 硬截断（防死循环的最终边界）。
pub fn omega_norm_max_rounds(v : Int) -> Int {
  if v <= 0 {
    omega_max_rounds_default()
  } else if v > 10 {
    10
  } else {
    v
  }
}

///|
/// 语料记录 id：spec:<task_id>:r<round>
pub fn omega_spec_id(task_id : String, round : Int) -> String {
  "spec:\{task_id}:r\{round}"
}

///|
/// 成果复验记录 id：result:<task_id>:r<round>
pub fn omega_result_id(task_id : String, round : Int) -> String {
  "result:\{task_id}:r\{round}"
}

///|
/// 升级记录 id：escalation:<task_id>:<stage>:r<round>
pub fn omega_escalation_id(
  task_id : String,
  stage : String,
  round : Int,
) -> String {
  "escalation:\{task_id}:\{stage}:r\{round}"
}

// —— 内部工具 ——

///|
/// Omega 环节角色授权：actor 必须具备指定 Action 权限（静态权限矩阵校验）。
fn omega_authorize_create(actor : String) -> Result[Unit, String] {
  @core.ensure_can_create_spec(actor)
}

///|
/// Omega 环节角色授权：审核/复验（角色：验证者，或人类指挥官）。
fn omega_authorize_review(actor : String) -> Result[Unit, String] {
  @core.ensure_can_review_spec(actor)
}

///|
/// 从语料内容中解析 author（读取 UTF8 前缀行；无前缀返回空串）。
fn omega_author_of(content : String) -> String {
  let p = omega_author_prefix()
  if !content.has_prefix(p) {
    return ""
  }
  let rest = content[p.length():content.length()]
  for line in rest.split("\n") {
    return line.to_string()
  }
  rest.to_string()
}

///|
/// r 是否比 cur 更新（created_at 优先，其次 id 字典序，保证跨后端确定性）。
fn omega_newer(r : @store.SpecRecord, cur : @store.SpecRecord) -> Bool {
  if r.created_at != cur.created_at {
    r.created_at > cur.created_at
  } else {
    r.id > cur.id
  }
}

// —— 引擎侧语料账本读写 ——

///|
/// 列出某任务的全部语料 / 复验 / 升级记录。
pub fn FistEngine::omega_records(
  self : FistEngine,
  task_id : String,
) -> Array[@store.SpecRecord] {
  self.store.list_specs_by_task(task_id)
}

///|
/// 统计某类型记录中处于指定状态的条数。
pub fn FistEngine::omega_count(
  self : FistEngine,
  task_id : String,
  spec_type : String,
  status : String,
) -> Int {
  let mut n = 0
  for r in self.store.list_specs_by_task(task_id) {
    if r.spec_type == spec_type && r.status == status {
      n = n + 1
    }
  }
  n
}

///|
/// 统计某类型的全部记录条数。
pub fn FistEngine::omega_count_type(
  self : FistEngine,
  task_id : String,
  spec_type : String,
) -> Int {
  let mut n = 0
  for r in self.store.list_specs_by_task(task_id) {
    if r.spec_type == spec_type {
      n = n + 1
    }
  }
  n
}

///|
/// 取最新一条指定类型记录。
pub fn FistEngine::omega_latest(
  self : FistEngine,
  task_id : String,
  spec_type : String,
) -> @store.SpecRecord? {
  let mut found : @store.SpecRecord? = None
  for r in self.store.list_specs_by_task(task_id) {
    if r.spec_type == spec_type {
      found = match found {
        None => Some(r)
        Some(cur) => if omega_newer(r, cur) { Some(r) } else { Some(cur) }
      }
    }
  }
  found
}

// —— 门禁（仅对强验证任务生效） ——

///|
/// 执行前门禁：强验证任务必须先有「已通过」语料；默认关闭的任务直接放行。
pub fn FistEngine::omega_execute_gate(
  self : FistEngine,
  task_id : String,
) -> Result[Unit, String] {
  match self.store.get_task(task_id) {
    None => Ok(())
    Some(t) =>
      if !omega_enabled(t) {
        Ok(())
      } else {
        match self.omega_latest(task_id, "spec") {
          None =>
            Err(
              "Omega 强验证门禁：任务 [\{task_id}] 尚未创建语料，请先由语料创建者执行 omega_spec_create",
            )
          Some(s) =>
            if s.status == "approved" {
              Ok(())
            } else {
              Err(
                "Omega 强验证门禁：语料 [\{s.id}] 状态为 [\{s.status}]，未通过审核前禁止进入执行",
              )
            }
        }
      }
  }
}

///|
/// 验收前门禁：强验证任务必须先有「已通过」的成果复验记录。
pub fn FistEngine::omega_verify_gate(
  self : FistEngine,
  task_id : String,
) -> Result[Unit, String] {
  match self.store.get_task(task_id) {
    None => Ok(())
    Some(t) =>
      if !omega_enabled(t) {
        Ok(())
      } else {
        match self.omega_latest(task_id, "result") {
          None =>
            Err(
              "Omega 强验证门禁：任务 [\{task_id}] 尚未做成果复验，请先由验证者执行 omega_result_verify",
            )
          Some(s) =>
            if s.status == "approved" {
              Ok(())
            } else {
              Err(
                "Omega 强验证门禁：成果复验 [\{s.id}] 状态为 [\{s.status}]，未通过前禁止验收",
              )
            }
        }
      }
  }
}

// —— 第一环：语料创建 ——

///|
/// 语料创建（角色：语料创建者 spec_author，或人类指挥官）。
/// 落库 specs 表：id = spec:<task_id>:r<round>，status = pending。
pub fn FistEngine::omega_spec_create(
  self : FistEngine,
  task_id~ : String,
  author~ : String,
  content~ : String,
  now~ : String,
  max_rounds? : Int = 0,
) -> Result[Json, String] {
  match omega_authorize_create(author) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let max_r = omega_norm_max_rounds(max_rounds)
  let t = match self.store.get_task(task_id) {
    None => return Err("task not found: \{task_id}")
    Some(x) => x
  }
  if !omega_enabled(t) {
    return Err(
      "任务 [\{task_id}] 未开启 Omega 强验证（description 缺少 [omega:required] 标记），无需创建语料",
    )
  }
  if content.trim() == "" {
    return Err("语料内容不可为空")
  }
  match self.omega_latest(task_id, "spec") {
    Some(cur) =>
      if cur.status == "pending" {
        return Err(
          "已存在待审核语料 [\{cur.id}]，请先由验证者审核",
        )
      } else if cur.status == "approved" {
        return Err("语料 [\{cur.id}] 已通过审核，无需重复创建")
      }
    None => ()
  }
  let rejected = self.omega_count(task_id, "spec", "rejected")
  if rejected >= max_r {
    return Ok(
      self.omega_escalate(
        task_id, "spec", rejected, max_r, "语料连续打回达上限，转人工裁决",
        now,
      ),
    )
  }
  let round = self.omega_count_type(task_id, "spec") + 1
  let spec_id = omega_spec_id(task_id, round)
  let payload = omega_author_prefix() + author + "\n" + content
  let rec = @store.SpecRecord::new(
    id=spec_id,
    task_id~,
    spec_type="spec",
    content=payload,
    status="pending",
    created_at=now,
    updated_at=now,
  )
  match self.store.upsert_spec(rec) {
    Err(e) => Err(e)
    Ok(_) =>
      Ok(
        Json::object({
          "ok": Json::boolean(true),
          "stage": Json::string("spec"),
          "spec_id": Json::string(spec_id),
          "task_id": Json::string(task_id),
          "round": Json::number(round.to_double()),
          "status": Json::string("pending"),
          "author": Json::string(author),
          "max_rounds": Json::number(max_r.to_double()),
          "rounds_rejected": Json::number(rejected.to_double()),
          "next_action": Json::string("omega_spec_review"),
          "escalated": Json::boolean(false),
        }),
      )
  }
}

// —— 第二环：语料审核（可打回重做） ——

///|
/// 语料审核（角色：验证者 verifier，或人类指挥官）。
/// verdict = approve 通过；其余视为打回（打回累计超限则升级人工）。
pub fn FistEngine::omega_spec_review(
  self : FistEngine,
  task_id~ : String,
  reviewer~ : String,
  verdict~ : String,
  reason? : String = "",
  now~ : String,
  max_rounds? : Int = 0,
) -> Result[Json, String] {
  match omega_authorize_review(reviewer) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let max_r = omega_norm_max_rounds(max_rounds)
  let t = match self.store.get_task(task_id) {
    None => return Err("task not found: \{task_id}")
    Some(x) => x
  }
  if !omega_enabled(t) {
    return Err(
      "任务 [\{task_id}] 未开启 Omega 强验证，无语料可审",
    )
  }
  let cur = match self.omega_latest(task_id, "spec") {
    None =>
      return Err(
        "任务 [\{task_id}] 尚无语料，请先由语料创建者执行 omega_spec_create",
      )
    Some(c) => c
  }
  if cur.status != "pending" {
    return Err(
      "语料 [\{cur.id}] 当前状态为 [\{cur.status}]，不是待审核状态",
    )
  }
  let author = omega_author_of(cur.content)
  if author != "" && author == reviewer {
    return Err(
      "验证者不可审核自己创建的语料（author = reviewer = \{reviewer}）",
    )
  }
  let is_approve = verdict == "approve" ||
    verdict == "approved" ||
    verdict == "pass" ||
    verdict == "ok" ||
    verdict == "APPROVE" ||
    verdict == "PASS" ||
    verdict == "OK"
  if is_approve {
    match self.store.update_spec_status(cur.id, "approved", cur.content, now) {
      Err(e) => Err(e)
      Ok(_) =>
        Ok(
          Json::object({
            "ok": Json::boolean(true),
            "stage": Json::string("spec"),
            "verdict": Json::string("approved"),
            "spec_id": Json::string(cur.id),
            "task_id": Json::string(task_id),
            "reviewer": Json::string(reviewer),
            "reason": Json::string(reason),
            "next_action": Json::string("execute"),
            "escalated": Json::boolean(false),
          }),
        )
    }
  } else {
    let rejected = self.omega_count(task_id, "spec", "rejected") + 1
    if rejected > max_r {
      return Ok(
        self.omega_escalate(task_id, "spec", rejected, max_r, reason, now),
      )
    }
    match self.store.update_spec_status(cur.id, "rejected", cur.content, now) {
      Err(e) => Err(e)
      Ok(_) => {
        // 失败回流：语料被打回即自动落 [lesson] 教训，供 plan/claim inject 检索
        let learned = self.omega_auto_lesson(
          rejected,
          "omega.spec_rejected",
          if reason == "" {
            "语料被打回（未附原因）"
          } else {
            reason
          },
          "语料未达要求，按审核意见重写后重新 omega_spec_create",
          now,
        )
        Ok(
          Json::object({
            "ok": Json::boolean(true),
            "stage": Json::string("spec"),
            "verdict": Json::string("rejected"),
            "spec_id": Json::string(cur.id),
            "task_id": Json::string(task_id),
            "reviewer": Json::string(reviewer),
            "reason": Json::string(reason),
            "rounds_rejected": Json::number(rejected.to_double()),
            "max_rounds": Json::number(max_r.to_double()),
            "learned_lesson": Json::boolean(learned),
            "next_action": Json::string("omega_spec_create"),
            "escalated": Json::boolean(false),
          }),
        )
      }
    }
  }
}

// —— 第三环：成果复验（可打回重做） ——

///|
/// 成果复验（角色：验证者 verifier，或人类指挥官）。
/// verdict = pass 达标；其余视为打回重做（超限升级人工）。
pub fn FistEngine::omega_result_verify(
  self : FistEngine,
  task_id~ : String,
  reviewer~ : String,
  verdict~ : String,
  reason? : String = "",
  now~ : String,
  max_rounds? : Int = 0,
) -> Result[Json, String] {
  match omega_authorize_review(reviewer) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let max_r = omega_norm_max_rounds(max_rounds)
  let t = match self.store.get_task(task_id) {
    None => return Err("task not found: \{task_id}")
    Some(x) => x
  }
  if !omega_enabled(t) {
    return Err(
      "任务 [\{task_id}] 未开启 Omega 强验证，无需成果复验",
    )
  }
  let spec = match self.omega_latest(task_id, "spec") {
    None =>
      return Err(
        "强验证任务 [\{task_id}] 尚无执行前语料，不可复验成果",
      )
    Some(s) => s
  }
  if spec.status != "approved" {
    return Err(
      "执行前语料 [\{spec.id}] 未通过审核（[\{spec.status}]），不可进入成果复验",
    )
  }
  if t.deliverable.trim() == "" {
    return Err(
      "任务 [\{task_id}] 尚无交付物（deliverable 为空），无可复验成果",
    )
  }
  let round = self.omega_count_type(task_id, "result") + 1
  let result_id = omega_result_id(task_id, round)
  let is_pass = verdict == "pass" ||
    verdict == "approved" ||
    verdict == "approve" ||
    verdict == "ok" ||
    verdict == "PASS" ||
    verdict == "OK"
  let payload = "resv-reviewer: " +
    reviewer +
    "\nverdict: " +
    verdict +
    "\nreason: " +
    reason
  let rec = @store.SpecRecord::new(
    id=result_id,
    task_id~,
    spec_type="result",
    content=payload,
    status=if is_pass { "approved" } else { "rejected" },
    created_at=now,
    updated_at=now,
  )
  if is_pass {
    match self.store.upsert_spec(rec) {
      Err(e) => Err(e)
      Ok(_) =>
        Ok(
          Json::object({
            "ok": Json::boolean(true),
            "stage": Json::string("result"),
            "result_id": Json::string(result_id),
            "task_id": Json::string(task_id),
            "round": Json::number(round.to_double()),
            "status": Json::string("approved"),
            "reviewer": Json::string(reviewer),
            "reason": Json::string(reason),
            "next_action": Json::string("verify"),
            "escalated": Json::boolean(false),
          }),
        )
    }
  } else {
    let rejected = self.omega_count(task_id, "result", "rejected") + 1
    if rejected > max_r {
      return Ok(
        self.omega_escalate(task_id, "result", rejected, max_r, reason, now),
      )
    }
    match self.store.upsert_spec(rec) {
      Err(e) => Err(e)
      Ok(_) => {
        // 失败回流：成果复验未达标即自动落 [lesson] 教训
        let learned = self.omega_auto_lesson(
          rejected,
          "omega.result_rejected",
          if reason == "" {
            "成果复验未达标（未附原因）"
          } else {
            reason
          },
          "交付物未达语料要求，按复验意见重做后重新 execute/submit",
          now,
        )
        // 打回重做：若已提交待验收，则用既有 reject 语义退回执行
        let mut demoted = ""
        if t.get_status().is_reviewing() {
          demoted = match
            self.reject_task(task_id~, reason~, by=reviewer, now~) {
            Ok(_) => "待验收 -> 已打回"
            Err(e) => "打回失败: " + e
          }
        } else {
          demoted = "任务当前状态 [" +
            t.status_to_string() +
            "]，保持不动，等待执行者重做"
        }
        Ok(
          Json::object({
            "ok": Json::boolean(true),
            "stage": Json::string("result"),
            "verdict": Json::string("rejected"),
            "result_id": Json::string(result_id),
            "task_id": Json::string(task_id),
            "reviewer": Json::string(reviewer),
            "reason": Json::string(reason),
            "rounds_rejected": Json::number(rejected.to_double()),
            "max_rounds": Json::number(max_r.to_double()),
            "learned_lesson": Json::boolean(learned),
            "task_transition": Json::string(demoted),
            "next_action": Json::string("execute"),
            "escalated": Json::boolean(false),
          }),
        )
      }
    }
  }
}

// —— 超限升级（防死循环的终点） ——

///|
/// 打回超限升级：写 escalation 记录 + 暂停任务，转人工裁决。
fn FistEngine::omega_escalate(
  self : FistEngine,
  task_id : String,
  stage : String,
  rounds : Int,
  max_r : Int,
  reason : String,
  now : String,
) -> Json {
  // 失败回流：打回超限升级本身是最典型的「此路不通」教训，自动沉淀进 DGM
  let learned = self.omega_auto_lesson(
    rounds,
    "omega.escalated",
    if reason == "" {
      "打回超限升级人工（未附原因）"
    } else {
      reason
    },
    "该打回原因已反复出现，需换策略而非继续同样的做法",
    now,
  )
  let esc_id = omega_escalation_id(task_id, stage, rounds)
  let payload = "stage: " +
    stage +
    "\nrounds_rejected: " +
    rounds.to_string() +
    "\nmax_rounds: " +
    max_r.to_string() +
    "\nneeds_human_review: true" +
    "\nreason: " +
    reason
  let rec = @store.SpecRecord::new(
    id=esc_id,
    task_id~,
    spec_type="escalation",
    content=payload,
    status="escalated",
    created_at=now,
    updated_at=now,
  )
  ignore(self.store.upsert_spec(rec))
  let paused = match self.pause_task(task_id~, now~) {
    Ok(_) => true
    Err(_) => false
  }
  Json::object({
    "ok": Json::boolean(true),
    "stage": Json::string(stage),
    "verdict": Json::string("escalated"),
    "escalation_id": Json::string(esc_id),
    "task_id": Json::string(task_id),
    "rounds_rejected": Json::number(rounds.to_double()),
    "max_rounds": Json::number(max_r.to_double()),
    "reason": Json::string(reason),
    "needs_human_review": Json::boolean(true),
    "task_paused": Json::boolean(paused),
    "learned_lesson": Json::boolean(learned),
    "next_action": Json::string("human_review"),
    "escalated": Json::boolean(true),
  })
}

// —— 状态查询 ——

///|
/// 查询某任务的强验证状态（开关、语料轮次、打回次数、复验状态、是否已升级）。
pub fn FistEngine::omega_status(
  self : FistEngine,
  task_id : String,
) -> Result[Json, String] {
  match self.store.get_task(task_id) {
    None => Err("task not found: \{task_id}")
    Some(t) => {
      let records = self.store.list_specs_by_task(task_id)
      Ok(
        Json::object({
          "ok": Json::boolean(true),
          "task_id": Json::string(task_id),
          "task_status": Json::string(t.status_to_string()),
          "omega_enabled": Json::boolean(omega_enabled(t)),
          "spec_rounds": Json::number(
            self.omega_count_type(task_id, "spec").to_double(),
          ),
          "spec_rejected": Json::number(
            self.omega_count(task_id, "spec", "rejected").to_double(),
          ),
          "result_rejected": Json::number(
            self.omega_count(task_id, "result", "rejected").to_double(),
          ),
          "spec_status": Json::string(
            match self.omega_latest(task_id, "spec") {
              Some(s) => s.status
              None => "none"
            },
          ),
          "result_status": Json::string(
            match self.omega_latest(task_id, "result") {
              Some(s) => s.status
              None => "none"
            },
          ),
          "escalated": Json::boolean(
            self.omega_count(task_id, "escalation", "escalated") > 0,
          ),
          "records": Json::array(records.map(fn(r) { r.to_json() })),
        }),
      )
    }
  }
}
