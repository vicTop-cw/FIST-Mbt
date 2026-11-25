/// baton.mbt —— T0r58 长程接力·交接包生成/消费（提案方案 C · P1，契约真源见
/// `docs/plans/2026-11-25-longrun-baton-handover-contract.md` §2~§4）。
///
/// 职责边界（**只做交接包的裁决**，不越界）：
///   · `baton_body`：从任务体构造交接包（上下文+进度+下一步+幂等键）；
///   · `parse_baton`：消费端三道门的纯函数（非空 → format → 必填齐且 task_id 一致）。
/// server/engine 的 IO 与 ACL 外壳不在本文件（判例-29：机制格必须能被白盒直接断言）。
///
/// **契约以 T0r54 文档为准，不另立一套**。`scripts/longrun_cli.py::make_baton` 是
/// 同一契约的**早期草图**（字段更少：无 written_by/artifacts/next_step 三键），
/// 此处按 T0r54 §2 定稿实现；两处不一致时以 T0r54 为准（该文件 §1 自述「契约定稿」）。
///
/// 设计口径与 P0 同形：**裁决是纯函数**，IO 只是它的外壳。

///|
/// 交接包格式标记：消费端必须逐字命中，否则视为「不是本工具写的包」（fail-closed）。
pub const BATON_FORMAT : String = "fist-longrun-baton-v1"

///|
/// **交接包生成（纯函数）**：`{format, task_id, written_at, written_by,
/// context, progress, next_step, idempotency_key}`。
///
/// context / progress 两段由任务体现状投影而来（走 `@core.Task` 的类型化
/// getter，不解析第二份 JSON）：
///   · `context.summary` = `description` + "；" + `deliverable`
///     （T0r54 §3 称「自解释描述」，唯一可机读的现成语料就是这两条）；
///   · `context.checkpoint_path` / `progress.budget_used` 直接回显任务行，
///     供消费方核验「baton 与任务行是否仍一致」。
///
/// 键集严格对齐 T0r54 §2 字段裁决表：progress 段**只有** done/remaining/budget_used
/// 三键（无 status——§2 字段表未列，加了就是契约外字段，故不写也不认）。
///
/// 拒绝条件（fail-closed，与 `parse_snapshot` 同风格，不做尽力猜测）：
///   1. `task_id` 为空；2. `written_by` 为空（自报身份口径同 BUG-430 公告，仅审计用）；
///   3. `next_step` 三键任一为空串（无下一步指令不叫接力棒）；
///   4. `idempotency_key` 为空（无法防重复交接副作用）。
///
/// `done` / `remaining` / `artifacts` 允许空数组，但**键必须存在**——那是
/// 「进度不完整即拒收」的一半（键缺失在 parse 侧也会被拦）。
pub fn baton_body(
  task_id : String,
  task : @core.Task,
  written_at : String,
  written_by : String,
  instruction : String,
  entry_hint : String,
  acceptance : String,
  idempotency_key : String,
) -> Result[Json, String] {
  if task_id == "" {
    return Err("交接包缺 task_id（无法确认归属）")
  }
  if written_by == "" {
    return Err(
      "交接包缺 written_by（无交接方身份，审计面不可用）",
    )
  }
  if instruction == "" {
    return Err(
      "交接包缺 next_step.instruction（无下一步指令不叫接力棒）",
    )
  }
  if entry_hint == "" {
    return Err(
      "交接包缺 next_step.entry_hint（接任者不知道从哪进来）",
    )
  }
  if acceptance == "" {
    return Err(
      "交接包缺 next_step.acceptance（没有验收标准的指令不可接力）",
    )
  }
  if idempotency_key == "" {
    return Err(
      "交接包缺 idempotency_key（无法防重复交接副作用）",
    )
  }
  let ctx : Map[String, Json] = Map([])
  ctx.set(
    "summary",
    Json::string(task.get_description() + "；" + task.deliverable),
  )
  ctx.set("checkpoint_path", Json::string(task.get_checkpoint_path()))
  ctx.set("artifacts", Json::array([]))
  let prog : Map[String, Json] = Map([])
  prog.set("done", Json::array([]))
  prog.set("remaining", Json::array([]))
  prog.set("budget_used", Json::number(task.get_budget_used().to_double()))
  let ns : Map[String, Json] = Map([])
  ns.set("instruction", Json::string(instruction))
  ns.set("entry_hint", Json::string(entry_hint))
  ns.set("acceptance", Json::string(acceptance))
  let m : Map[String, Json] = Map([])
  m.set("format", Json::string(BATON_FORMAT))
  m.set("task_id", Json::string(task_id))
  m.set("written_at", Json::string(written_at))
  m.set("written_by", Json::string(written_by))
  m.set("context", Json::object(ctx))
  m.set("progress", Json::object(prog))
  m.set("next_step", Json::object(ns))
  m.set("idempotency_key", Json::string(idempotency_key))
  Ok(Json::object(m))
}

///|
/// 取对象里的字符串字段（缺键/类型不符都返回空串）。
/// 消费端对「缺」与「空」同等 fail-closed，故这里合并处理是安全的。
fn obj_str(m : Map[String, Json], key : String) -> String {
  match m.get(key) {
    Some(String(s)) => s
    _ => ""
  }
}

///|
/// **交接包消费（纯函数，T0r54 §4 的三道门，顺序即契约）**：
///   ① `last_baton != ""`（无棒即无可消费——不是错误，而是「还没交接过」）；
///   ② JSON 可解析且 `format == BATON_FORMAT`（不是本工具的包）；
///   ③ §2 必填字段全齐，且 `task_id` 与当前任务一致。
///
/// 任一不过 ⇒ Err 并点名是哪一层、缺哪个字段（人/agent 据此知道该补什么，
/// 而不是拿到一个半截包直接开跑）。
pub fn parse_baton(
  text : String,
  expect_task_id : String,
) -> Result[Json, String] {
  if text == "" {
    return Err(
      "无接力棒（last_baton 为空）：尚未交接，先执行或等待交接",
    )
  }
  let parsed = @json.parse(text) catch {
    _ => return Err("接力棒不是合法 JSON（可能损坏或被截断）")
  }
  let top = match parsed {
    Object(m) => m
    _ => return Err("接力棒顶层不是 JSON 对象")
  }
  match top.get("format") {
    Some(String(f)) =>
      if f != BATON_FORMAT {
        return Err(
          "接力棒格式不符：实得 [" +
          f +
          "]，期望 [" +
          BATON_FORMAT +
          "]（可能是别的工具写的包）",
        )
      }
    _ =>
      return Err(
        "接力棒缺 format 字段（无法确认它是本工具的包）",
      )
  }
  for key in ["task_id", "written_at", "written_by", "idempotency_key"] {
    if obj_str(top, key) == "" {
      return Err("接力棒缺必填字段：\{key}")
    }
  }
  let tid = obj_str(top, "task_id")
  if tid != expect_task_id {
    return Err(
      "接力棒与任务不匹配：包属 [" +
      tid +
      "]，任务是 [" +
      expect_task_id +
      "]（拒绝把别人的接力棒接过来）",
    )
  }
  let ctx = match top.get("context") {
    Some(Object(m)) => m
    _ =>
      return Err("接力棒缺 context 段（无上下文即无可接力性）")
  }
  if obj_str(ctx, "summary") == "" {
    return Err("接力棒缺必填字段：context.summary")
  }
  // 可选字段：键可在、值可空；但键缺失同样拒（进度不完整）
  for key in ["checkpoint_path", "artifacts"] {
    if ctx.get(key) == None {
      return Err(
        "接力棒缺字段：context.\{key}（键必须在，值可空）",
      )
    }
  }
  let prog = match top.get("progress") {
    Some(Object(m)) => m
    _ => return Err("接力棒缺 progress 段（进度不完整）")
  }
  for key in ["done", "remaining", "budget_used"] {
    if prog.get(key) == None {
      return Err("接力棒缺字段：progress.\{key}（键必须在）")
    }
  }
  let next = match top.get("next_step") {
    Some(Object(m)) => m
    _ =>
      return Err(
        "接力棒缺 next_step 段（无下一步指令不叫接力棒）",
      )
  }
  for key in ["instruction", "entry_hint", "acceptance"] {
    if obj_str(next, key) == "" {
      return Err("接力棒缺必填字段：next_step.\{key}")
    }
  }
  Ok(Json::object(top))
}
