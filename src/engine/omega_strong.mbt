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
/// 边界四问·叶级提示（R115 后置改进，对准 atgc-merge 归因报告机理 2「验收锚定 + 弱语料」）。
/// 语料只断言"做了没"时，执行体理性地停在判据边界上；这一行把"域外行为"变成每条叶子的显式义务。
pub fn boundary_probe_hint() -> String {
  " [边界四问:空输入/极值/非法输入/资源极限——须有用例或声明不适用]"
}

///|
/// 边界审视叶的切片文本（对准机理 1「递归拆解损失全局视角 ⇒ 全局不变量无 owner」）。
/// 拆完之后"spec 没写的域外行为"是无人负责地带；本切片给这类思考一个可领取、可验收的归属。
pub fn boundary_probe_slice() -> String {
  "[边界审视·全局输入域 owner] 根任务 spec 未写的域外行为归本叶：对输入域逐项给出空输入 / 极值 / 非法输入 / 资源极限 四类用例，或显式声明该项不适用并说明依据；不得因 spec 未提及而默认沉默（写下限语料时，强验证只会验证下限）。"
}

///|
/// 语料 author 前缀（纯文本行，避免为嵌入 author 而引入 JSON 转义）。
pub fn omega_author_prefix() -> String {
  "OMEGA-AUTHOR: "
}

///|
/// 任务是否处于强验证模式（未打标记 = 关闭 = 既有行为）。
/// BUG-389 方向②：门禁判据以 tasks 元数据列 omega_required 为准（description 被
/// supervisor_task_upsert 覆盖后仍成立）；description 里的 [omega:required] 标记
/// 保留为旧数据的兜底兼容（两者取或）。
pub fn omega_enabled(t : @core.Task) -> Bool {
  t.get_omega_required() || t.description.contains(omega_mark())
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
    out = out + part.to_owned()
  }
  out.trim().to_owned()
}

///|
/// 「孤儿 Omega 任务」判据（BUG-417）：本任务自己**没开** omega（元数据列 = false），
/// 描述里的 `[omega:required]` 是**从父层切片继承来的残留**，且**直接父任务已归档**。
///
/// 为什么需要这个判据：`omega_enabled` 的文本兜底（`description.contains(mark)`）
/// **不区分标记归属** —— 一个 `omega_required=0` 的任务，只因描述里引用了父层文本
/// （含标记）就被判为强验证任务。`task_plan_deep` 递归下钻 + `reinject_context`
/// 把父层切片拼进子层描述时，标记会逐层累积。
///
/// 实测（Lane T）：孤儿 `T0r636.1.2` 描述长 4683 字节，`[父计划:` 出现 4 次，
/// 两个 omega 标记**都在嵌套段内** ⇒ `strip_plan_annotations` 的单层截断有盲区。
///
/// 与 BUG-389 正相反：那条是「标记被静默**覆盖**」，本条是「标记被静默**继承**」。
///
/// **语义依据**：`omega_strong_verify` 的语义是「**这棵任务树**的成果要被验证」。
/// 父已归档 ⇒ 那棵树的验收语境已终结 ⇒ 让一个没有父亲的叶子继续满足门禁是**判据错位**。
///
/// **只豁免「直接父已归档」这一种**：父未归档 / 取不到 / 祖父归档 / 根任务 一律 false（fail-closed）。
/// `parent_status` 由调用方查库传入 ⇒ 本函数保持纯、可单测、无 IO。
pub fn omega_orphan_of_archived_parent(
  t : @core.Task,
  parent_status : @core.TaskStatus?,
) -> Bool {
  // 元数据列真开了 ⇒ 是正经 Omega 任务，不许豁免
  if t.get_omega_required() {
    return false
  }
  // 描述里没有标记 ⇒ 文本兜底根本不会触发，无需豁免
  if !t.description.contains(omega_mark()) {
    return false
  }
  // **根任务无父 ⇒ 不豁免**（Lane P 原始设计里有这一条，我这里曾漏掉，
  // 被锁 omega_orphan_wb2 抓出来：只信 parent_status 参数会让「根任务 + 传已归档」
  // 也返回 true）。判据必须自己确认「确实有父」。
  match t.get_parent() {
    None => false
    Some(_) =>
      match parent_status {
        None => false // 父取不到 ⇒ fail-closed 不豁免
        Some(st) => st.is_archived()
      }
  }
}

///|
/// 切到某个标记首次出现处之前（沿用 omega_author_of 的「迭代首个元素即返回」写法，
/// 不对数组下标取，避免潜在越界）。无该标记则原样返回。
fn cut_before(s : String, mark : String) -> String {
  if !s.contains(mark) {
    return s
  }
  for part in s.split(mark) {
    return part.to_owned()
  }
  s
}

///|
/// decomposer 结构标记清单（单一真源）。`strip_plan_annotations` 与
/// `preserve_plan_markers` 共用同一份清单，消除两份清单漂移的风险。
/// 标记面必须与 decompose_rec 写入端一字不差（含前导空格）——本函数是唯一落点。
fn plan_markers() -> Array[String] {
  [
    " [难度梯度 ",
    " [父计划:",
    " | [父计划: ",
    " [边界四问",
    " [spec:",
    omega_mark(),
  ]
}

///|
/// 去掉「拆解引擎自己追加」的计划标注，只留任务本体描述（R113）。
/// `omega_clean_slice` 只洗强验证标记，而 gradient / reinject_context / boundary_probe /
/// spec 指纹四项同样会在递归下钻时被逐层重喂（child.description 当作下一层的
/// parent_desc，且又被嵌进「更简单变体」引用与「父计划」字段），实测 2 层拆分叶子
/// 1996 字节、根部仅 12 字节，并出现同一叶两个互相矛盾的梯度档。
/// 逐标记顺序截断 = 截在最靠前的那个标记之前，因此对已叠加多层的文本也能一次洗净。
/// 标记面来自 `plan_markers()`（单一真源）。
pub fn strip_plan_annotations(s : String) -> String {
  let markers = plan_markers()
  let mut out = s
  for m in markers {
    out = cut_before(out, m)
  }
  out.trim().to_owned()
}

///|
/// 合并 decomposer 注入的结构标记：新描述缺哪些，就把旧描述里的对应标记补回（BUG-389）。
///
/// `supervisor_task_upsert` 用 `with_description` **整体覆盖** description，而用户经超级管家
/// 更新任务描述时通常不会带上 `[omega:required]` / `[边界四问…]` / `[难度梯度 …]` /
/// `[父计划:…]` / `[spec:…]` 这些由 decomposer 注入的结构标记；覆盖后标记被静默丢失，
/// 之后 `omega_spec_create` 判门禁读到 description 不含 `[omega:required]` 就误报
/// 「未开启 Omega 强验证」，把「标记丢失」伪装成「用户没开 Omega」。
///
/// 语义：对 `plan_markers()` 列出的标记面做「缺失补回」——若旧描述含某标记而新描述不含，
/// 则把该标记（连同其前导空格，`omega_mark()` 无前导空格）追加到新描述末尾。
pub fn preserve_plan_markers(old_desc : String, new_desc : String) -> String {
  let markers = plan_markers()
  let mut out = new_desc
  for m in markers {
    if !out.contains(m) {
      if old_desc.contains(m) {
        out = out + m
      }
    }
  }
  out
}

///|
/// 默认最大打回轮次。
pub fn omega_max_rounds_default() -> Int32 {
  3
}

///|
/// 归一化轮次上限：非正数取默认，超过 10 硬截断（防死循环的最终边界）。
pub fn omega_norm_max_rounds(v : Int32) -> Int32 {
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
pub fn omega_spec_id(task_id : String, round : Int32) -> String {
  "spec:\{task_id}:r\{round}"
}

///|
/// 成果复验记录 id：result:<task_id>:r<round>
pub fn omega_result_id(task_id : String, round : Int32) -> String {
  "result:\{task_id}:r\{round}"
}

///|
/// 升级记录 id：escalation:<task_id>:<stage>:r<round>
pub fn omega_escalation_id(
  task_id : String,
  stage : String,
  round : Int32,
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
    return line.to_owned()
  }
  rest.to_owned()
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
) -> Int32 {
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
) -> Int32 {
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

// —— 门禁 ——

///|
/// 占位符规整：把字符串拆成 Char 数组，剔除所有非字母数字的字符（空白/标点/全角标点），
/// 再转小写。MoonBit 用 `String::to_array()` 拿到 `Array[Char]`（同 evolve.mbt 的做法）。
fn placeholder_normalize(s : String) -> String {
  let out : Array[String] = []
  for c in s.to_lower().to_array() {
    let is_cjk = c.to_int() >= 0x4E00 && c.to_int() <= 0x9FFF
    let is_ascii_alnum = (c.to_int() >= 0x30 && c.to_int() <= 0x39) ||
      (c.to_int() >= 0x41 && c.to_int() <= 0x5A) ||
      (c.to_int() >= 0x61 && c.to_int() <= 0x7A)
    if is_cjk || is_ascii_alnum {
      out.push(c.to_string())
    }
  }
  out.join("")
}

///|
/// 预执行审计门禁（P2 BACKLOG「Pre-execution audit gate」）：
/// 在 `can_execute` 通过之后、`execute()` 迁移之前插入，拦截「空交付物」与「占位符交付物」——
/// 「已完成但无交付物」的病灶形状：执行者写了空串/纯空白/「done」/「完成」/「ok」这类占位符
/// deliverable，账本记「完成」但没有任何产物可核。判据两条：
///   ① deliverable trim 后非空；② 非纯占位符（如 "done"/"完成"/"ok"/"yes"/"通过"，大小写不敏感；不做全角归一化）。
/// 只拦确定性问题，不做过度拦截；零回归（正常交付物一定含具体改动/路径/验证信息）。
pub fn FistEngine::audit_execute_gate(
  _self : FistEngine,
  _task_id : String,
  deliverable : String,
) -> Result[Unit, String] {
  let trimmed = deliverable.trim().to_owned()
  if trimmed.is_empty() {
    return Err(
      "预执行审计门禁：deliverable 为空。请写清改动/路径/验证后再 execute",
    )
  }
  // 占位符检测：把常见 fake-GREEN 词规整后比对（大小写/空白/标点容忍）。
  // 只判「整串等于占位符」这种确定性问题，不做语义判定，避免过度拦截。
  // R10 修：旧实现只 to_lower，注释里承诺的「空白/标点容忍」落了空——`"Done ."` / `"完成！"`
  // 这类「占位符 + 杂散空白/标点」能绕过。现在把全串拆成字符后剔除所有非字母数字的字符，
  // 再做大小写归一，与规整后的占位符词表比对。
  let stripped = placeholder_normalize(trimmed)
  let placeholder_words : Array[String] = [
    "done", "完成", "ok", "yes", "通过", "finished",
  ]
  for w in placeholder_words {
    if stripped == w {
      return Err(
        "预执行审计门禁：deliverable 是占位符 [" +
        trimmed +
        "]，没有可核产物。请写清改动/路径/验证后再 execute",
      )
    }
  }
  Ok(())
}

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
  max_rounds~ : Int32 = 0,
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
  reason~ : String = "",
  now~ : String,
  max_rounds~ : Int32 = 0,
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
    // rejected = existing + 1, so > max_r means existing >= max_r (consistent with omega_spec_create)
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
  reason~ : String = "",
  now~ : String,
  max_rounds~ : Int32 = 0,
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
    // rejected = existing + 1, so > max_r means existing >= max_r (consistent with omega_spec_create)
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
  rounds : Int32,
  max_r : Int32,
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
  let mut spec_err = ""
  match self.store.upsert_spec(rec) {
    Ok(_) => ()
    Err(e) => spec_err = e
  }
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
    "spec_persist_error": Json::string(spec_err),
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
