/// baton_wbtest.mbt —— T0r58 交接包生成/消费的白盒锁。
///
/// 契约真源：`docs/plans/2026-11-25-longrun-baton-handover-contract.md`（T0r54 §2~§4）。
/// 本文件钉四件事（T0r54 §5 的验收锚点）：
///   ① **生成**：合法入参 ⇒ 信封八段齐全、context/progress 由任务体投影而来；
///   ② **消费**：合法包**不误红**（往返），三道门逐层 fail-closed（非空/format/必填+task_id）；
///   ③ **生成侧拒绝**：task_id/written_by/next_step 三键/idempotency_key 任一为空即拒；
///   ④ **变异对照**：直接断言被测机制的源码仍在（判例-30：改坏代码锁必须红）。
///
/// 包外构造约束同 `longrun_wbtest.mbt`：`Task` 构造体 read-only ⇒ 走 `from_db_longrun`。

///|
/// 包外造指定状态的 Task（与 longrun_wbtest 同源，参数面 = store 的还原入口）。
fn bt_task(id : String, st : String) -> @core.Task {
  @core.Task::from_db_longrun(
    id,
    None,
    ".",
    "default",
    "中",
    "中",
    3,
    3,
    6,
    st,
    None,
    "长程交接任务",
    "产出：baton 契约落地",
    "2026-11-25T00:00:00Z",
    "2026-11-25T00:00:00Z",
    None,
    "deferred",
    [],
    false,
    "human_steward",
    "/p/.fist-mbt/longrun/x.json",
    "",
    42L,
    [],
  )
}

///|
/// 合法包构造器（供往返格复用）
fn bt_ok(task_id : String, task : @core.Task) -> Json {
  match
    baton_body(
      task_id, task, "2026-11-25T12:00:00Z", "codearts-autoplan", "先 resume 取回上下文，再补 baton 集成测试",
      "先 fist_longrun_resume", "moon test --target js 全绿且新增白盒含变异对照",
      "baton-T0r58-1",
    ) {
    Ok(j) => j
    Err(e) => abort("合法入参竟被生成侧拒绝：\{e}")
  }
}

///|
/// ① 生成：信封八段齐全 + context/progress 由任务体投影而来（不另立序列化）。
test "baton: body envelope and task projection" {
  let t = bt_task("T0r58", "已暂停")
  let j = bt_ok("T0r58", t)
  match j {
    Object(m) => {
      for
        k in [
          "format", "task_id", "written_at", "written_by", "context", "progress",
          "next_step", "idempotency_key",
        ] {
        if m.get(k) == None {
          abort("交接包信封缺键：" + k)
        }
      }
      match m.get("format") {
        Some(String(f)) =>
          if f != "fist-longrun-baton-v1" {
            abort("format 标记漂移：\{f}")
          }
        _ => abort("format 不是字符串")
      }
      // progress.budget_used 必须回显任务行读数（消费方核验一致性的依据）
      match m.get("progress") {
        Some(Object(p)) =>
          match p.get("budget_used") {
            Some(Number(n, ..)) =>
              if n.to_int64() != 42L {
                abort("budget_used 未回显任务行：\{n}")
              }
            _ => abort("progress.budget_used 缺失或非数字")
          }
        _ => abort("progress 段不是对象")
      }
      // checkpoint_path 从任务体取（不是写死的空串）
      match m.get("context") {
        Some(Object(c)) =>
          match c.get("checkpoint_path") {
            Some(String(s)) =>
              if s != "/p/.fist-mbt/longrun/x.json" {
                abort("checkpoint_path 未随任务投影：\{s}")
              }
            _ => abort("context.checkpoint_path 缺失")
          }
        _ => abort("context 段不是对象")
      }
    }
    _ => abort("baton_body 顶层不是对象")
  }
}

///|
/// ② 消费：合法包**不误红**（往返）——生成侧放行的包，消费侧必须能读回。
///    这一格防的是「两面各自实现、各说各话」：只测拒绝面会漏掉契约漂移。
test "baton: legal package round-trips (no false red)" {
  let t = bt_task("T0r58", "已暂停")
  let text = bt_ok("T0r58", t).stringify()
  match parse_baton(text, "T0r58") {
    Ok(j) =>
      match j {
        Object(m) =>
          match m.get("task_id") {
            Some(String(tid)) =>
              if tid != "T0r58" {
                abort("往返 task_id 不符：\{tid}")
              }
            _ => abort("往返后 task_id 缺失")
          }
        _ => abort("往返后顶层不是对象")
      }
    Err(e) => abort("合法交接包被消费侧误拒：\{e}")
  }
}

///|
/// ③ 消费侧三道门：顺序即契约（非空 → format → 必填齐且 task_id 一致）。
///    每层拒绝文案必须点名是哪一层（否则人分不清「没交接过」还是「包坏了」）。
test "baton: consume gate order (empty -> format -> required+owner)" {
  // 门①：无接力棒（不是错误，是还没交接过）
  match parse_baton("", "T0r58") {
    Ok(_) => abort("空串竟被接受为交接包")
    Err(e) =>
      if !e.contains("无接力棒") {
        abort("空串拒绝文案未点名「无接力棒」：\{e}")
      }
  }
  // 门②：格式不符（别的工具写的包）
  let wrong_fmt = "{\"format\":\"other-tool-v9\",\"task_id\":\"T0r58\"}"
  match parse_baton(wrong_fmt, "T0r58") {
    Ok(_) => abort("别的工具的包竟被接受")
    Err(e) =>
      if !e.contains("格式不符") {
        abort("格式拒绝文案未点名格式：\{e}")
      }
  }
  // 门②变体：JSON 损坏
  match parse_baton("{not json", "T0r58") {
    Ok(_) => abort("非法 JSON 竟被接受")
    Err(e) =>
      if !e.contains("合法 JSON") {
        abort("损坏拒绝文案未点名 JSON：\{e}")
      }
  }
  // 门③：task_id 归属不符（拒绝把别人的棒接过来）
  let t = bt_task("T0r58", "已暂停")
  let text = bt_ok("T0r58", t).stringify()
  match parse_baton(text, "T-OTHER") {
    Ok(_) => abort("别人任务的接力棒竟被接受")
    Err(e) =>
      if !e.contains("不匹配") {
        abort("归属拒绝文案未点名不匹配：\{e}")
      }
  }
}

///|
/// 从 JSON 对象里**删掉一个键**后重新序列化（返回 `None` = 该键本来就没有）。
///
/// 为什么不做字符串替换：`String::replace` 的标签面（`old~`/`new~`）与序列化空格
/// 都让「抽字段」这一步依赖实现细节；而按结构删键是幂等的、可断言「键确实在」。
fn bt_drop(j : Json, key : String) -> Json? {
  match j {
    Object(m) =>
      if m.get(key) == None {
        None
      } else {
        let out : Map[String, Json] = Map([])
        for k, v in m.iter2() {
          if k != key {
            out.set(k, v)
          }
        }
        Some(Json::object(out))
      }
    _ => None
  }
}

///|
/// 顶层段版本：把 `j[段]` 里的 `键` 删掉后拼回顶层（`None` = 段或键不存在）。
fn bt_drop_in(j : Json, section : String, key : String) -> Json? {
  match j {
    Object(m) =>
      match m.get(section) {
        Some(seg) =>
          match bt_drop(seg, key) {
            None => None
            Some(dropped) => {
              let out : Map[String, Json] = Map([])
              for k, v in m.iter2() {
                if k == section {
                  out.set(k, dropped)
                } else {
                  out.set(k, v)
                }
              }
              Some(Json::object(out))
            }
          }
        _ => None
      }
    _ => None
  }
}

///|
/// 断言「抽掉某字段后的包必被消费侧拒，且文案点名该字段」。
/// `label` 用于夹具自证（键确实存在），`needle` 是必须在拒绝文案里出现的串。
fn bt_expect_reject(
  label : String,
  needle : String,
  cut : Json?,
  expect_task_id : String,
) -> Unit {
  match cut {
    None =>
      abort("夹具未包含字段 " + label + "（契约或实现漂移）")
    Some(c) =>
      match parse_baton(c.stringify(), expect_task_id) {
        Ok(_) => abort("抽掉 " + label + " 竟被接受")
        Err(e) =>
          if !e.contains(needle) {
            abort("抽掉 " + label + " 的拒绝文案未点名：\{e}")
          }
      }
  }
}

///|
/// ④ 消费侧逐字段抽掉必拒（fail-closed，不做尽力猜测）。
///
/// 覆盖 T0r54 §2 字段裁决表的**全字段集**（§5 要求「缺各必填字段必红」）：
/// 顶层五键 + context 三键 + progress 三键 + next_step 三键 = 14 格。
/// 其中 `context.checkpoint_path` / `artifacts` 的**值可空、但键必须在**
/// ⇒ 抽键必拒（T0r54 §2 明写「⬜ 空值合法」，指值不指键）。
test "baton: consume rejects each missing required field by name" {
  let base = bt_ok("T0r58", bt_task("T0r58", "已暂停"))
  // (段名, 键名, 拒绝文案必须点名的串)
  for
    (section, key, needle) in [
      ("", "format", "format"),
      ("", "task_id", "task_id"),
      ("", "written_at", "written_at"),
      ("", "written_by", "written_by"),
      ("", "idempotency_key", "idempotency_key"),
      ("context", "summary", "summary"),
      ("context", "checkpoint_path", "checkpoint_path"),
      ("context", "artifacts", "artifacts"),
      ("progress", "done", "done"),
      ("progress", "remaining", "remaining"),
      ("progress", "budget_used", "budget_used"),
      ("next_step", "instruction", "instruction"),
      ("next_step", "entry_hint", "entry_hint"),
      ("next_step", "acceptance", "acceptance"),
    ] {
    let cut = if section == "" {
      bt_drop(base, key)
    } else {
      bt_drop_in(base, section, key)
    }
    let label = if section == "" { key } else { section + "." + key }
    bt_expect_reject(label, needle, cut, "T0r58")
  }
}

///|
/// ④b 段缺失：整个 `context` / `progress` / `next_step` 段不见了也要点名拒。
test "baton: consume rejects missing sections" {
  let base = bt_ok("T0r58", bt_task("T0r58", "已暂停"))
  for
    (section, needle) in [
      ("context", "context"),
      ("progress", "progress"),
      ("next_step", "next_step"),
    ] {
    match bt_drop(base, section) {
      None => abort("夹具未包含段 " + section)
      Some(cut) =>
        match parse_baton(cut.stringify(), "T0r58") {
          Ok(_) => abort("抽掉整段 " + section + " 竟被接受")
          Err(e) =>
            if !e.contains(needle) {
              abort("抽掉 " + section + " 的拒绝文案未点名：\{e}")
            }
        }
    }
  }
}

///|
/// ⑤ 生成侧拒绝：四个必填入参任一为空即拒，文案点名缺哪个。
test "baton: generate rejects empty required inputs" {
  let t = bt_task("T0r58", "已暂停")
  // task_id 空
  match baton_body("", t, "ts", "by", "ins", "hint", "acc", "key") {
    Ok(_) => abort("空 task_id 竟生成了交接包")
    Err(e) =>
      if !e.contains("task_id") {
        abort("空 task_id 拒绝文案未点名：\{e}")
      }
  }
  // written_by 空
  match baton_body("T0r58", t, "ts", "", "ins", "hint", "acc", "key") {
    Ok(_) => abort("空 written_by 竟生成了交接包")
    Err(e) =>
      if !e.contains("written_by") {
        abort("空 written_by 拒绝文案未点名：\{e}")
      }
  }
  // next_step 三键任一空
  for
    (label, ins, hint, acc) in [
      ("instruction", "", "hint", "acc"),
      ("entry_hint", "ins", "", "acc"),
      ("acceptance", "ins", "hint", ""),
    ] {
    match baton_body("T0r58", t, "ts", "by", ins, hint, acc, "key") {
      Ok(_) => abort("空 " + label + " 竟生成了交接包")
      Err(e) =>
        if !e.contains(label) {
          abort("空 " + label + " 拒绝文案未点名：\{e}")
        }
    }
  }
  // idempotency_key 空
  match baton_body("T0r58", t, "ts", "by", "ins", "hint", "acc", "") {
    Ok(_) => abort("空 idempotency_key 竟生成了交接包")
    Err(e) =>
      if !e.contains("idempotency_key") {
        abort("空 idempotency_key 拒绝文案未点名：\{e}")
      }
  }
}

///|
/// ⑥ **变异对照**（判例-30/29）：直接断言被测机制的真实分支仍在源码里。
///
/// 判例-30 踩过的形状：模式串若在注释里出现，改坏代码后匹配仍命中 ⇒ 锁恒绿。
/// 故锚定**行首的真实代码行**（trim 后以 `@core.` / `return Err(` 起头），
/// 注释行 trim 后以 `///` 起头，天然排除。
test "mutation control: baton gates present in source" {
  let src = @fs.read_file_to_string("src/longrun/baton.mbt", encoding="utf8") catch {
    _ => abort("变异对照读不到被测源码：src/longrun/baton.mbt")
  }
  let mut seen_empty_gate = false
  let mut seen_format_gate = false
  let mut seen_owner_gate = false
  for line in src.split("\n") {
    let l = line.trim()
    // 门① 非空闸（在 parse_baton 里，判断入参 text）
    if l.has_prefix("if text == \"\" {") {
      seen_empty_gate = true
    }
    // 门② format 比对（消费侧读 top 的 format）
    if l.has_prefix("Some(String(f)) =>") {
      seen_format_gate = true
    }
    // 门③ 归属比对
    if l.has_prefix("if tid != expect_task_id {") {
      seen_owner_gate = true
    }
  }
  if !seen_empty_gate {
    abort(
      "变异对照失效：源码里「空串闸」不见了 ⇒ 门① 被改坏",
    )
  }
  if !seen_format_gate {
    abort(
      "变异对照失效：源码里「format 闸」不见了 ⇒ 门② 被改坏",
    )
  }
  if !seen_owner_gate {
    abort(
      "变异对照失效：源码里「task_id 归属闸」不见了 ⇒ 门③ 被改坏",
    )
  }
}
