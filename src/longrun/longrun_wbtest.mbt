/// longrun_wbtest.mbt —— T0r53 长程接力最小闭环（提案方案 C · P0）的成对锁。
///
/// 本文件钉五件事：
///   ① 快照**信封完整**（format/task_id/written_at/task）且 body 能被 `parse_snapshot` 解回；
///   ② `resume_target_status` 的状态机：合法三态（已暂停/执行中/已领取）→ 已领取，
///      非法六态（待领取/拆分中/待验收/已完成/已归档/已打回）逐条拒绝并点名；
///   ③ `resume_precheck` 的两层分工：状态裁决在前、快照存在性在后（判例-29：机制格 ≠ 实现路径格）；
///   ④ core 侧 longrun 写入语义：增量预算可交换、幂等键去重；
///   ⑤ **变异对照**：直接断言被测机制的源码仍在（锚定行首真实分支，不锚注释）。
///
/// 两个包外构造约束（都实测过，别再踩）：
///   · `TaskStatus` variant 在包外 read-only（4036）⇒ 统一走 `from_string`；
///   · `Task` 构造体在包外同样 read-only ⇒ **没有 `status~` 参数**时，
///     造指定状态任务的正路是 `from_db_longrun(status_s=…)`（它就是 store 层的还原入口）。

///|
/// 包外造 `TaskStatus` 的唯一正路（与 omega_orphan_wbtest 同惯例）。
fn lr_st(s : String) -> @core.TaskStatus? {
  @core.TaskStatus::from_string(s)
}

///|
/// 包外造指定状态的 Task：走 `from_db_longrun`（status 以中文态名传入）。
///
/// 参数面与 store 的 `row_to_task` 同源 —— 它正是「库行 → Task」的还原入口，
/// 用它当夹具顺带把「列序与本函数一致」这格也钉住了（列序漂了这里就红）。
fn lr_task(id : String, st : String) -> @core.Task {
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
    "长程任务",
    "",
    "2026-11-24T00:00:00Z",
    "2026-11-24T00:00:00Z",
    None,
    "deferred",
    [],
    false,
    "human_steward",
    "",
    "",
    0L,
    [],
  )
}

///|
/// ① 快照信封完整性 + round-trip：四个键都在，解回来的 task_id 与写入一致。
test "snapshot_body envelope and round trip" {
  let t = lr_task("T0r53", "已暂停")
  let body = snapshot_body("T0r53", t, "2026-11-24T10:00:00Z")
  match body {
    Object(m) => {
      for k in ["format", "task_id", "written_at", "task"] {
        if m.get(k) == None {
          abort("快照信封缺键：" + k)
        }
      }
      match m.get("format") {
        Some(String(f)) =>
          if f != "fist-longrun-checkpoint-v1" {
            abort("format 标记漂移：\{f}")
          }
        _ => abort("format 不是字符串")
      }
    }
    _ => abort("snapshot_body 顶层不是对象")
  }
  match parse_snapshot(body.stringify()) {
    Ok((tid, tj)) => {
      if tid != "T0r53" {
        abort("round-trip task_id 不符：\{tid}")
      }
      match tj {
        Object(tm) =>
          match tm.get("id") {
            Some(String(id)) =>
              if id != "T0r53" {
                abort("task.id 未随快照往返：\{id}")
              }
            _ => abort("快照内 task.id 缺失")
          }
        _ => abort("快照内 task 不是对象")
      }
    }
    Err(e) => abort("刚构造的 body 自己解不开：\{e}")
  }
}

///|
/// ② 解析面的 fail-closed：非法 JSON / 顶层非对象 / 格式不符 / 缺 task_id /
///    task 非对象 / 缺 task。每条拒绝文案都必须点名原因（否则人分不清「损坏」还是「拿错文件」）。
test "parse_snapshot rejects malformed bodies" {
  // 非法 JSON
  match parse_snapshot("{not json") {
    Ok(_) => abort("非法 JSON 竟被接受")
    Err(e) =>
      if !e.contains("合法 JSON") {
        abort("拒绝文案未点名 JSON：\{e}")
      }
  }
  // 顶层非对象
  match parse_snapshot("[1,2,3]") {
    Ok(_) => abort("数组顶层竟被接受")
    Err(e) =>
      if !e.contains("顶层") {
        abort("拒绝文案未点名顶层：\{e}")
      }
  }
  // 格式不符
  let wrong_fmt = "{\"format\":\"other-tool-v1\",\"task_id\":\"X\",\"task\":{}}"
  match parse_snapshot(wrong_fmt) {
    Ok(_) => abort("别的工具的快照竟被接受")
    Err(e) =>
      if !e.contains("格式不符") {
        abort("拒绝文案未点名格式：\{e}")
      }
  }
  // 缺 task_id
  match
    parse_snapshot("{\"format\":\"fist-longrun-checkpoint-v1\",\"task\":{}}") {
    Ok(_) => abort("缺 task_id 竟被接受")
    Err(e) =>
      if !e.contains("task_id") {
        abort("拒绝文案未点名 task_id：\{e}")
      }
  }
  // task 非对象
  match
    parse_snapshot(
      "{\"format\":\"fist-longrun-checkpoint-v1\",\"task_id\":\"X\",\"task\":42}",
    ) {
    Ok(_) => abort("task 非对象竟被接受")
    Err(e) =>
      if !e.contains("不是对象") {
        abort("拒绝文案未点名 task 形状：\{e}")
      }
  }
  // 缺 task 字段
  match
    parse_snapshot(
      "{\"format\":\"fist-longrun-checkpoint-v1\",\"task_id\":\"X\"}",
    ) {
    Ok(_) => abort("缺 task 竟被接受")
    Err(e) =>
      if !e.contains("缺 task") {
        abort("拒绝文案未点名缺 task：\{e}")
      }
  }
}

///|
/// ③ resume 状态机：三条合法 + 六条非法（含「已完成不可被 resume 覆盖旧账」这格）。
test "resume state machine" {
  // 合法三态 → 已领取
  for st in ["已暂停", "执行中", "已领取"] {
    let s = match lr_st(st) {
      Some(v) => v
      None => abort("非法态名 " + st)
    }
    match resume_target_status(s) {
      Ok(t) =>
        if t.to_string() != "已领取" {
          abort(
            "合法态 " +
            st +
            " 的目标态错：[" +
            t.to_string() +
            "]（期望 已领取）",
          )
        }
      Err(e) => abort("合法态 " + st + " 被拒：\{e}")
    }
  }
  // 非法六态：文案必须点名该状态
  for
    st in [
      "待领取", "拆分中", "待验收", "已完成", "已归档", "已打回",
    ] {
    let s = match lr_st(st) {
      Some(v) => v
      None => abort("非法态名 " + st)
    }
    match resume_target_status(s) {
      Ok(t) =>
        abort(
          "非法态 " +
          st +
          " 竟被放行到 [" +
          t.to_string() +
          "]（越过了验收/审计面）",
        )
      Err(e) =>
        if !e.contains(st) {
          abort("拒绝文案未点名当前状态 " + st + "：\{e}")
        }
    }
  }
  // 已打回的出路必须是 retry（不能指路回 resume 本身）
  let rejected = match lr_st("已打回") {
    Some(v) => v
    None => abort("非法态名")
  }
  match resume_target_status(rejected) {
    Ok(_) => abort("已打回被放行")
    Err(e) =>
      if !e.contains("retry") {
        abort("已打回未给 retry 出路：\{e}")
      }
  }
}

///|
/// ④ resume_precheck 的两层分工 + 快照路径口径。
///
/// 这一格防的是「改坏了顺序，测试还绿」——若先查快照再裁状态，
/// 「非法态 + 无快照」会给出「缺快照」的误导文案（人跑去建快照，而真因是状态不对）。
test "resume_precheck order and snapshot path" {
  let bad = lr_task("Tbad", "已完成")
  match resume_precheck(bad, "/definitely/not/here/x.json") {
    Ok(_) => abort("已完成任务被允许 resume")
    Err(e) =>
      if !e.contains("已完成") {
        abort("非法态未先报状态错（顺序被改坏）：\{e}")
      }
  }
  // 快照路径口径：带 project_dir 前缀 + `.fist-mbt/longrun/<id>.json`
  let p = snapshot_path("/proj/nsa", "T0r53.1.2")
  if p != "/proj/nsa/.fist-mbt/longrun/T0r53.1.2.json" {
    abort("快照路径口径不符：\{p}")
  }
  let p2 = snapshot_path("", "T1")
  if p2 != ".fist-mbt/longrun/T1.json" {
    abort("空 project_dir 口径不符：\{p2}")
  }
  // checkpoint_path 为空时回落默认路径 ⇒ 无快照应报「不存在」而不是崩
  let ok_task = lr_task("Tc", "已暂停")
  match resume_precheck(ok_task, "") {
    Ok(_) => abort("无快照却放行 resume")
    Err(e) =>
      if !e.contains(".fist-mbt/longrun/Tc.json") {
        abort("默认快照路径未被用上：\{e}")
      }
  }
}

///|
/// ⑤ core 侧 longrun 写入语义：增量预算可交换、幂等键去重。
test "core longrun writers" {
  let t = lr_task("Tbw", "已领取")
  let c1 = t.with_longrun_checkpoint(
    "/p/.fist-mbt/longrun/Tbw.json", "baton-1", 3L, "t1",
  )
  let c2 = c1.with_longrun_checkpoint("", "baton-2", 4L, "t2")
  if c2.budget_used != 7L {
    abort("预算增量不可加：\{c2.budget_used}（期望 7）")
  }
  // 交换律：两条独立调用链最终预算相同（并发接力不丢更新）
  let a = t
    .with_longrun_checkpoint("", "b1", 1L, "x")
    .with_longrun_checkpoint("", "b2", 2L, "y")
  let b = t
    .with_longrun_checkpoint("", "b2", 2L, "y")
    .with_longrun_checkpoint("", "b1", 1L, "x")
  if a.budget_used != b.budget_used {
    abort("预算增量不满足交换律")
  }
  // 幂等键：新键 true、重复 false、空键 false
  let (d1, added1) = t.idempotency_add("k1", "u1")
  let (d2, added2) = d1.idempotency_add("k1", "u2")
  let (_, added3) = d2.idempotency_add("", "u3")
  if !(added1 && !added2 && !added3) {
    abort("幂等键去重语义错：\{added1}/\{added2}/\{added3}")
  }
  if d2.idempotency_keys.length() != 1 || d2.idempotency_keys[0] != "k1" {
    abort("幂等键集合内容错")
  }
  if !d2.has_idempotency_key("k1") {
    abort("has_idempotency_key 未命中既有键")
  }
  // baton 单独更新不动预算
  let e = t.with_baton("baton-x", "tb")
  if e.last_baton != "baton-x" || e.budget_used != 0L {
    abort("with_baton 语义错")
  }
}

///|
/// ⑤b **写读回环（真 IO）**：`write_snapshot` 落盘 → `read_snapshot` 读回，
///    两端的 task_id / checkpoint_path / budget_used 必须逐项一致。
///
/// 为什么单开一格：① 只钉了「构造的信封能解回」（内存往返），
/// 本格才钉到「真的过了一遍文件系统」——判例-29（机制格 ≠ 实现路径格）。
/// 落点在临时沙箱目录（`<cwd>/.tmp-lr-roundtrip-wbtest/`）并在收尾删掉，
/// 不碰仓库内任何真实快照路径。
test "checkpoint write/read round trip over real filesystem" {
  let t = lr_task("T0r58rt", "已暂停")
  let dir = ".tmp-lr-roundtrip-wbtest"
  match write_snapshot(dir, t, "2026-11-25T12:00:00Z") {
    Ok((path, reread_tid)) => {
      // 路径口径：必须是该沙箱下的 <task_id>.json
      let want = snapshot_path(dir, "T0r58rt")
      if path != want {
        abort("写回执路径口径不符：\{path} ≠ \{want}")
      }
      // 写侧自带回读校验：第二个回执值就是「落盘后读回来的 task_id」
      if reread_tid != "T0r58rt" {
        abort("写回执的读回 task_id 不符：\{reread_tid}")
      }
      match read_snapshot(path) {
        Ok((tid, task_json)) => {
          if tid != "T0r58rt" {
            abort("读回 task_id 不符：\{tid}")
          }
          match task_json {
            Object(m) =>
              match m.get("id") {
                Some(String(id)) =>
                  if id != "T0r58rt" {
                    abort("读回任务体 id 不符：\{id}")
                  }
                _ => abort("读回任务体缺 id")
              }
            _ => abort("读回 task 不是对象")
          }
        }
        Err(e) => abort("刚写入的快照读不回来：\{e}")
      }
      // 收尾：删沙箱文件与目录（幂等，失败不影响断言结论）
      @fs.remove_file(path) catch {
        _ => ()
      }
      @fs.remove_dir(dir) catch {
        _ => ()
      }
    }
    Err(e) => abort("沙箱写入失败：\{e}")
  }
}

///|
/// ⑥ **变异对照**（判例-30/判例-29）：直接断言被测机制的源码仍在。
///
/// 手法要点（判例-30 踩过）：锚定**行首的真实分支行**，而不是注释里的描述串 ——
/// 本文件的断言输入源若在注释里出现同一串，改坏代码后匹配仍命中 ⇒ 锁恒绿。
/// 故这里先 trim 再要求 `@core.Xxx =>` 开头（注释行 trim 后以 `///` 起头，天然排除）。
test "mutation control: resume legal transitions present in source" {
  let src = @fs.read_file_to_string("src/longrun/longrun.mbt", encoding="utf8") catch {
    _ => abort("变异对照读不到被测源码：src/longrun/longrun.mbt")
  }
  let mut seen_paused = false
  let mut seen_executing = false
  let mut seen_claimed = false
  for line in src.split("\n") {
    let l = line.trim()
    if l.has_prefix("@core.Paused =>") {
      seen_paused = true
    }
    if l.has_prefix("@core.Executing =>") {
      seen_executing = true
    }
    if l.has_prefix("@core.Claimed =>") {
      seen_claimed = true
    }
  }
  if !seen_paused {
    abort(
      "变异对照失效：源码里 `@core.Paused =>` 分支不见了 ⇒ 迁移表被改坏",
    )
  }
  if !seen_executing {
    abort(
      "变异对照失效：源码里 `@core.Executing =>` 分支不见了 ⇒ 跨会话中断重入没了",
    )
  }
  if !seen_claimed {
    abort(
      "变异对照失效：源码里 `@core.Claimed =>` 分支不见了 ⇒ 幂等重入没了",
    )
  }
}
