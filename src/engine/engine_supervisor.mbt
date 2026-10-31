/// engine/engine_supervisor.mbt —— 超级管家专属工具的引擎侧纯计算/编排
///
/// 对应 docs/2026-10-12-fist-mbt-supervisor-tools-plan.md：
///   supervisor_status / supervisor_task_tree / supervisor_kill_plan / supervisor_task_upsert
/// 复用既有 store/engine API，不新增表、不改状态机；kill 只出方案不执行（金条四）。

///|
/// 全库（或指定 ns）状态聚合：供 supervisor_status 使用。纯读。
/// `detail=false`（默认）时 active 里每个任务的 description 截断到 200 字节
/// （字符边界安全，见 `@core.desc_clip`），控 MCP 返回体积——task_plan_deep 开满
/// gradient/reinject_context/boundary_probe 后描述会递归膨胀到数 KB，全量回传会炸。
/// `detail=true` 返回完整描述（调用方按需取全文）。
pub fn FistEngine::supervisor_status(
  self : FistEngine,
  ns_filter~ : String = "",
  detail~ : Bool = false,
) -> Json {
  let tasks = self.list_all()
  let by_status : Map[String, Int32] = Map([])
  let by_ns : Map[String, Int32] = Map([])
  let active : Array[Json] = []
  let mut done = 0
  let mut total = 0
  let desc_limit = if detail { -1 } else { 200 }
  for t in tasks {
    let st = t.status_to_string()
    if t.ns == ns_filter || ns_filter == "" {
      total = total + 1
      let cur = by_status.get(st).unwrap_or(0)
      by_status.set(st, cur + 1)
      let cur_ns = by_ns.get(t.ns).unwrap_or(0)
      by_ns.set(t.ns, cur_ns + 1)
      if st == "已完成" || st == "已归档" {
        done = done + 1
      }
      let a = t.get_status()
      let is_active = !a.is_pending() && !a.is_completed() && !a.is_archived()
      if is_active {
        active.push(t.to_json(desc_limit~))
      }
    }
  }
  let status_obj : Map[String, Json] = Map([])
  by_status.each(fn(k, v) { status_obj.set(k, Json::number(v.to_double())) })
  let ns_obj : Map[String, Json] = Map([])
  by_ns.each(fn(k, v) { ns_obj.set(k, Json::number(v.to_double())) })
  let progress = if total == 0 {
    0.0
  } else {
    done.to_double() * 100.0 / total.to_double()
  }
  Json::object({
    "total": Json::number(total.to_double()),
    "by_status": Json::object(status_obj),
    "by_namespace": Json::object(ns_obj),
    "progress_pct": Json::number(progress),
    "active_count": Json::number(active.length().to_double()),
    "active": Json::array(active),
  })
}

///|
/// 任务树节点：递归聚合子任务完成度。返回 (节点 JSON, 子树完成数, 子树总数)。纯读。
/// `desc_limit > 0` 时节点 task 的 description 截断（控返回体积，与 supervisor_status 同口径）。
fn FistEngine::supervisor_tree_node(
  self : FistEngine,
  idx : Map[String, Array[String]],
  task_id : String,
  desc_limit : Int32,
) -> (Json, Int32, Int32)? {
  match self.get_task(task_id) {
    None => None
    Some(t) => {
      let children : Array[Json] = []
      let mut child_total = 0
      let mut child_done = 0
      match idx.get(task_id) {
        Some(ids) =>
          for cid in ids {
            match self.supervisor_tree_node(idx, cid, desc_limit) {
              Some((cj, done, total)) => {
                child_done = child_done + done
                child_total = child_total + total
                children.push(cj)
              }
              None => ()
            }
          }
        None => ()
      }
      let st = t.get_status()
      if st.is_completed() || st.is_archived() {
        child_done = child_done + 1
      }
      child_total = child_total + 1
      let node : Json = Json::object({
        "task": t.to_json(desc_limit~),
        "subtree_total": Json::number(child_total.to_double()),
        "subtree_done": Json::number(child_done.to_double()),
        "children": Json::array(children),
      })
      Some((node, child_done, child_total))
    }
  }
}

///|
/// 任务树状态与进度汇报：root 起递归，每节点带 subtree_done/subtree_total。
/// `detail=false`（默认）时各节点 task 的 description 截断到 200 字节（与 supervisor_status 同口径）。
pub fn FistEngine::supervisor_task_tree(
  self : FistEngine,
  root_id : String,
  detail~ : Bool = false,
) -> Result[Json, String] {
  match self.get_task(root_id) {
    None => Err("task not found: \{root_id}")
    Some(_) => {
      let idx = self.children_index()
      let desc_limit = if detail { -1 } else { 200 }
      match self.supervisor_tree_node(idx, root_id, desc_limit) {
        None => Err("task not found: \{root_id}")
        Some((tree, _done, _total)) =>
          Ok(Json::object({ "root_id": Json::string(root_id), "tree": tree }))
      }
    }
  }
}

///|
/// kill 硬门链单门结果。
priv struct SupervisorGate {
  gate : String
  passed : Bool
  reason : String
}

///|
fn supervisor_gate_json(g : SupervisorGate) -> Json {
  Json::object({
    "gate": Json::string(g.gate),
    "passed": Json::boolean(g.passed),
    "reason": Json::string(g.reason),
  })
}

///|
/// kill 硬门链评估（**只读纯计算，不执行任何终止**）：
///   G1 身份门：by == human_steward 或现任主助理
///   G2 目标存在
///   G3 不可杀目标：根任务（拳长承诺，design v2 的 kill 权唯一性）不可杀
///   G4 终态检查：已完成/已归档不可杀
///   G5 force+reason：force=true 且 reason 非空才 allowed，否则 only_plan
/// verdict ∈ allowed / only_plan / blocked
pub fn FistEngine::supervisor_kill_plan(
  self : FistEngine,
  task_id~ : String,
  by~ : String,
  reason~ : String,
  force~ : Bool = false,
  apply_pause~ : Bool = false,
  now~ : String = "",
) -> Json {
  let gates : Array[SupervisorGate] = []
  // G1 身份门
  let primary = self.assistant_active_primary()
  let primary_agent = match primary {
    Some(r) => r.agent
    None => ""
  }
  let g1_pass = by == "human_steward" ||
    (primary_agent != "" && by == primary_agent)
  gates.push({
    gate: "G1_identity",
    passed: g1_pass,
    reason: if g1_pass {
      "操作者是人类指挥官或现任主助理"
    } else {
      "操作者既不是 human_steward 也不是现任主助理（kill 权唯一，见 multi-agent-lock design v2）"
    },
  })
  // G2 目标存在
  match self.get_task(task_id) {
    None => {
      gates.push({
        gate: "G2_exists",
        passed: false,
        reason: "task not found: \{task_id}",
      })
      let gate_js : Array[Json] = gates.map(supervisor_gate_json)
      return Json::object({
        "task_id": Json::string(task_id),
        "verdict": Json::string("blocked"),
        "gates": Json::array(gate_js),
        "steps": Json::array([]),
        "note": Json::string("本工具只出方案不执行（金条四）"),
      })
    }
    Some(t) => {
      gates.push({ gate: "G2_exists", passed: true, reason: "目标存在", })
      // G3 不可杀目标：根任务 = 拳长承诺（planner 分级近似），不可杀
      let is_root = match t.get_parent() {
        None => true
        Some(_) => false
      }
      if is_root {
        gates.push({
          gate: "G3_protected_planner",
          passed: false,
          reason: "根任务=拳长承诺，不可杀（force 不可越过；确需撤销请由指挥官走 archive/人工裁决）",
        })
      } else {
        gates.push({
          gate: "G3_protected_planner",
          passed: true,
          reason: "非根任务，可进入终止方案",
        })
      }
      // G4 终态检查
      let st = t.get_status()
      let terminal = st.is_completed() || st.is_archived()
      gates.push({
        gate: "G4_terminal_state",
        passed: !terminal,
        reason: if terminal {
          "目标已是终态 [\{st.to_string()}]，无需终止"
        } else {
          "目标处于活跃态，可终止"
        },
      })
      // G5 force+reason
      let g5_pass = force && reason != ""
      gates.push({
        gate: "G5_force_reason",
        passed: g5_pass,
        reason: if g5_pass {
          "force=true 且 reason 非空"
        } else {
          "需要 force=true 且非空 reason 才给出 allowed（当前仅出方案）"
        },
      })
      let blocked = !g1_pass || is_root || terminal
      let verdict = if blocked {
        "blocked"
      } else if g5_pass {
        "allowed"
      } else {
        "only_plan"
      }
      // 补偿建议（advisory，不自动执行）
      let steps : Array[Json] = []
      ignore(
        steps.push(
          Json::string(
            "按 saga_register 为该任务已交付的前向步骤登记可补偿动作（如尚未登记）",
          ),
        ),
      )
      ignore(
        steps.push(
          Json::string(
            "终止前先 supervisor_kill_plan(apply_pause=true) 走可逆暂停，观察无副作用再人工裁决",
          ),
        ),
      )
      ignore(
        steps.push(
          Json::string(
            "真正的 kill（删除子树/杀进程）由指挥官人工执行或走 assistant_kill（v3 设计，PID 通道另立项）",
          ),
        ),
      )
      let gate_js : Array[Json] = gates.map(supervisor_gate_json)
      let m : Map[String, Json] = Map([
        ("task_id", Json::string(task_id)),
        ("by", Json::string(by)),
        ("status", Json::string(st.to_string())),
        ("verdict", Json::string(verdict)),
        ("gates", Json::array(gate_js)),
        ("steps", Json::array(steps)),
        (
          "compensation_hint",
          Json::string(
            "saga_register / saga_rollback / saga_repair（LIFO 局部补偿）",
          ),
        ),
        (
          "note",
          Json::string(
            "本工具只出方案不执行（金条四）；apply_pause=true 时另行走可逆的 pause",
          ),
        ),
      ])
      // 可逆出口：apply_pause=true 且未被 G3/G4 拦下时执行 pause（已暂停可 resume）
      if apply_pause && !is_root && !terminal {
        // engine 包不依赖 @env：now 缺省回退任务自身 updated_at
        let ts = if now == "" { t.get_updated_at() } else { now }
        match self.pause_task(task_id~, now=ts) {
          Ok(t) =>
            m.set(
              "pause_applied",
              Json::object({
                "ok": Json::boolean(true),
                "status": Json::string(t.status_to_string()),
                "reversible": Json::boolean(true),
              }),
            )
          Err(e) =>
            m.set(
              "pause_applied",
              Json::object({
                "ok": Json::boolean(false),
                "error": Json::string(e),
              }),
            )
        }
      }
      Json::object(m)
    }
  }
}

///|
/// 可选的可逆出口：按 kill 方案走 pause（已暂停可 resume，可逆）。
pub fn FistEngine::supervisor_kill_apply_pause(
  self : FistEngine,
  task_id~ : String,
  now~ : String,
) -> Result[@core.Task, String] {
  self.pause_task(task_id~, now~)
}

///|
/// 单条 upsert item 的解析结果（内部结构）。
priv struct SupervisorUpsertItem {
  task_id : String
  description : String
  priority : String
  depends_on : Array[String]
}

///|
fn parse_upsert_item(v : Json) -> SupervisorUpsertItem? {
  match v {
    Json::Object(m) => {
      let get = fn(k : String) -> String {
        match m.get(k) {
          Some(Json::String(s)) => s
          _ => ""
        }
      }
      let deps : Array[String] = match m.get("depends_on") {
        Some(Json::Array(a)) =>
          a.map(fn(d) { if d is Json::String(s) { s } else { "" } })
        _ => []
      }
      Some({
        task_id: get("task_id"),
        description: get("description"),
        priority: get("priority"),
        depends_on: deps,
      })
    }
    _ => None
  }
}

///|
/// 更新目标项目任务列表：无 task_id 的 item=追加新根任务（publish，仅 human_steward），
/// 有 task_id 的 item=更新描述/优先级/追加依赖。终态任务拒改。逐条独立成败。
pub fn FistEngine::supervisor_task_upsert(
  self : FistEngine,
  project_dir~ : String,
  by~ : String,
  items : Array[Json],
  now~ : String,
  ns~ : String = "default",
) -> Json {
  let results : Array[Json] = []
  let mut ok_count = 0
  for raw in items {
    match parse_upsert_item(raw) {
      None =>
        ignore(
          results.push(
            Json::object({
              "ok": Json::boolean(false),
              "error": Json::string("item 不是对象或缺少 description"),
            }),
          ),
        )
      Some(item) =>
        if item.task_id != "" {
          // 更新已有任务
          match self.get_task(item.task_id) {
            None =>
              ignore(
                results.push(
                  Json::object({
                    "ok": Json::boolean(false),
                    "task_id": Json::string(item.task_id),
                    "error": Json::string("task not found"),
                  }),
                ),
              )
            Some(t) => {
              let st = t.get_status()
              if st.is_completed() || st.is_archived() {
                ignore(
                  results.push(
                    Json::object({
                      "ok": Json::boolean(false),
                      "task_id": Json::string(item.task_id),
                      "error": Json::string(
                        "终态任务 [\{st.to_string()}] 拒改；请走 reopen_task 或重新发布",
                      ),
                    }),
                  ),
                )
              } else {
                let mut c = t
                if item.description != "" {
                  c = c.with_description(
                    preserve_plan_markers(t.description, item.description),
                    now,
                  )
                }
                if item.priority != "" {
                  c = c.with_priority(item.priority, now)
                }
                // 依赖边必须过与 dag_depend **同一道**环闸（depend_edge_ok 是唯一真源）。
                // 此前这里直接 with_depends_on 落库，是评委实测「DAG 接受成环依赖」的
                // 那条形通道：dag_depend 拒得住的环，本入口照样写得进去。
                // 任一条被拒 ⇒ 本条整笔不写（不留半套改动，与事务性迁移同口径）。
                let mut dep_reject : String = ""
                for d in item.depends_on {
                  if d != "" && dep_reject == "" {
                    match self.depend_edge_ok(item.task_id, d) {
                      Err(e) => dep_reject = e
                      Ok(_) => ()
                    }
                  }
                }
                if dep_reject != "" {
                  ignore(
                    results.push(
                      Json::object({
                        "ok": Json::boolean(false),
                        "task_id": Json::string(item.task_id),
                        "error": Json::string(
                          "依赖边被拒，本条未写入: \{dep_reject}",
                        ),
                      }),
                    ),
                  )
                } else {
                  for d in item.depends_on {
                    if d != "" {
                      c = c.with_depends_on(d, now)
                    }
                  }
                  match self.store.update_task(c) {
                    Ok(_) => {
                      ok_count = ok_count + 1
                      ignore(
                        results.push(
                          Json::object({
                            "ok": Json::boolean(true),
                            "task_id": Json::string(item.task_id),
                            "action": Json::string("updated"),
                          }),
                        ),
                      )
                    }
                    Err(e) =>
                      ignore(
                        results.push(
                          Json::object({
                            "ok": Json::boolean(false),
                            "task_id": Json::string(item.task_id),
                            "error": Json::string("更新落库失败: \{e}"),
                          }),
                        ),
                      )
                  }
                }
              }
            }
          }
        } else {
          // 追加新任务：复用 publish（内部含 human_steward 硬门）
          match
            self.publish(
              project_dir~,
              description=item.description,
              created_by=by,
              now~,
              ns~,
            ) {
            Ok(id) => {
              ok_count = ok_count + 1
              // 追加任务可带依赖——同样过 depend_edge_ok 这道唯一环闸：
              // 新任务 id 是刚分配的，成环不可能，但**悬空依赖**（指向不存在的 id）
              // 同样是坏图，一并拒掉并如实回执（此前这里静默写进去，dag_check 事后才红）。
              if item.depends_on.length() > 0 {
                match self.get_task(id) {
                  Some(t) => {
                    let mut c = t
                    let mut dep_reject : String = ""
                    for d in item.depends_on {
                      if d != "" && dep_reject == "" {
                        match self.depend_edge_ok(id, d) {
                          Err(e) => dep_reject = e
                          Ok(_) => ()
                        }
                      }
                    }
                    if dep_reject != "" {
                      ignore(
                        results.push(
                          Json::object({
                            "ok": Json::boolean(false),
                            "task_id": Json::string(id),
                            "action": Json::string("dep_rejected"),
                            "error": Json::string(dep_reject),
                          }),
                        ),
                      )
                    } else {
                      for d in item.depends_on {
                        if d != "" {
                          c = c.with_depends_on(d, now)
                        }
                      }
                      match self.store.update_task(c) {
                        Ok(_) => ()
                        Err(e) =>
                          ignore(
                            results.push(
                              Json::object({
                                "ok": Json::boolean(false),
                                "task_id": Json::string(id),
                                "action": Json::string("dep_update_failed"),
                                "error": Json::string(e),
                              }),
                            ),
                          )
                      }
                    }
                  }
                  None => ()
                }
              }
              ignore(
                results.push(
                  Json::object({
                    "ok": Json::boolean(true),
                    "task_id": Json::string(id),
                    "action": Json::string("created"),
                  }),
                ),
              )
            }
            Err(e) =>
              ignore(
                results.push(
                  Json::object({
                    "ok": Json::boolean(false),
                    "error": Json::string(e),
                  }),
                ),
              )
          }
        }
    }
  }
  Json::object({
    "project_dir": Json::string(project_dir),
    "namespace": Json::string(ns),
    "total": Json::number(items.length().to_double()),
    "ok_count": Json::number(ok_count.to_double()),
    "results": Json::array(results),
  })
}

///|
/// ISO 时间（YYYY-MM-DDTHH:MM:SS，忽略尾部 Z/毫秒/时区）→ epoch 秒。
/// 解析失败返回 None（调用方按不可比较处理，不阻断轮询）。
fn iso_to_epoch(s : String) -> Int32? {
  if s.length() < 19 ||
    s[4] != '-' ||
    s[7] != '-' ||
    s[10] != 'T' ||
    s[13] != ':' ||
    s[16] != ':' {
    return None
  }
  let nums : Array[Int32] = []
  let idxs : Array[(Int32, Int32)] = [
    (0, 4),
    (5, 7),
    (8, 10),
    (11, 13),
    (14, 16),
    (17, 19),
  ]
  for p in idxs {
    let (lo, hi) = p
    let mut v = 0
    let mut bad = false
    for i in lo..<hi {
      let d = s[i].to_int() - 48
      if d < 0 || d > 9 {
        bad = true
      }
      v = v * 10 + d
    }
    if bad {
      return None
    }
    nums.push(v)
  }
  let yy = nums[0]
  let mo = nums[1]
  let dd = nums[2]
  let hh = nums[3]
  let mi = nums[4]
  let ss = nums[5]
  if mo < 1 || mo > 12 || dd < 1 || dd > 31 || hh > 23 || mi > 59 || ss > 59 {
    return None
  }
  let a = (14 - mo) / 12
  let y = yy + 4800 - a
  let m = mo + 12 * a - 3
  let jd = dd + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
  Some((jd - 2451545) * 86400 - 43200 + hh * 3600 + mi * 60 + ss)
}

///|
/// 提醒者轮询（纯计算，只读不修改）：扫描全库任务产出提醒清单。
///   R2 停滞：活跃任务最近更新早于 now-stale_hours；
///   R3 事项超时：待处理任务最近更新早于 now-pending_hours。
/// 时间解析失败的任务跳过（不阻断轮询）。
pub fn FistEngine::supervisor_reminder_tick(
  self : FistEngine,
  now~ : String,
  stale_hours~ : Int32 = 24,
  pending_hours~ : Int32 = 48,
) -> Json {
  let now_ep = iso_to_epoch(now).unwrap_or(0)
  let stale_cut = now_ep - stale_hours * 3600
  let pending_cut = now_ep - pending_hours * 3600
  let reminders : Array[Json] = []
  for t in self.list_all() {
    let st = t.get_status()
    let active = !st.is_pending() && !st.is_completed() && !st.is_archived()
    let up = t.get_updated_at()
    let up_ep = iso_to_epoch(up).unwrap_or(0)
    let ts_ok = now_ep > 0 && up_ep > 0
    if active && ts_ok && up_ep < stale_cut {
      reminders.push(
        Json::object({
          "kind": Json::string("stale"),
          "severity": Json::string("info"),
          "task_id": Json::string(t.get_id()),
          "ns": Json::string(t.ns),
          "status": Json::string(st.to_string()),
          "reason": Json::string(
            "活跃任务超过 \{stale_hours} 小时未更新",
          ),
          "updated_at": Json::string(up),
        }),
      )
    }
    if st.is_pending() && ts_ok && up_ep < pending_cut {
      reminders.push(
        Json::object({
          "kind": Json::string("pending_timeout"),
          "severity": Json::string("warn"),
          "task_id": Json::string(t.get_id()),
          "ns": Json::string(t.ns),
          "status": Json::string(st.to_string()),
          "reason": Json::string(
            "待处理任务超过 \{pending_hours} 小时未被接管",
          ),
          "updated_at": Json::string(up),
        }),
      )
    }
  }
  Json::object({
    "ts": Json::string(now),
    "stale_hours": Json::number(stale_hours.to_double()),
    "pending_hours": Json::number(pending_hours.to_double()),
    "reminder_count": Json::number(reminders.length().to_double()),
    "reminders": Json::array(reminders),
  })
}
