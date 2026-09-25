/// engine_dispatch.mbt —— 引擎层 store-backed 自治派单 primitive（R56）
///
/// 自治闭环的最后一块地基：把"给某个执行者派单"下沉到 engine 层、直接读 store 持久化的
/// 执行者能力注册（executor_list），复用 executor 包的 `route_pick` 纯计算路由（单真源），
/// 不经 server 进程内 `exec_reg`。纯增量：新增 pub 函数，不改任何既有工具/看门狗行为（零回归）。
///
/// 这样 `watchdog_tick`（ops 层有 engine 引用）即可在显式 ns 无人值守场景直接调用
/// `engine.dispatch_next(...)` 实现"按能力/负载自动派单"，而不再受 server 全局 exec_reg 耦合。

///|
/// 解析执行者能力注册（abilities_json 为 JSON 字符串数组）-> Array[String]。
fn parse_abilities(abs_json : String) -> Array[String] {
  let out : Array[String] = []
  let v = @json.parse(abs_json) catch {
    _ => return out
  }
  match v {
    Array(a) =>
      for x in a {
        match x {
          String(s) => out.push(s)
          _ => ()
        }
      }
    _ => ()
  }
  out
}

///|
/// 计算每个执行者的活跃负载：名下"未完成且未归档"的任务数（由 store 分配状态推得，纯读）。
fn executor_loads(
  self : FistEngine,
  names : Array[String],
) -> Map[String, Int] {
  let m : Map[String, Int] = Map([])
  for n in names {
    m.set(n, 0)
  }
  for t in self.list_all() {
    match t.assignee {
      Some(a) =>
        if m.contains(a) {
          let done = t.get_status().is_completed() ||
            t.get_status().to_string() == "已归档"
          if not(done) {
            m.set(a, m.get(a).unwrap_or(0) + 1)
          }
        }
      None => ()
    }
  }
  m
}

///|
/// 读 Json 对象的字符串字段（内部辅助）。
fn _jstr(j : Json, key : String) -> String {
  match j.value(key) {
    Some(Json::String(s)) => s
    _ => ""
  }
}

///|
/// 引擎层自治派单（纯增量、零回归）：取 `triage` 顶部可领取任务 → 用 store 持久化执行者能力
/// 注册经 executor 包 `route_pick` 按「能力覆盖 → 负载」路由最佳执行者 → 将任务直接认领给该执行者；
/// 无注册/路由失败时回退到 `agent`。返回 { dispatched, task_id, to_executor, remaining, note?/error? }。
pub fn FistEngine::dispatch_next(
  self : FistEngine,
  ns : String,
  agent : String,
  want : String,
  now : String,
) -> Json {
  let tri = self.triage(ns, agent, want)
  let top = _jstr(tri, "task_id")  // triage 顶层 task_id 字段（若顶层是 suggestion 则回退解析）
  let top2 : String = if top == "" {
    match tri.value("suggestion") {
      Some(Object(sm)) => _jstr(Json::object(sm), "task_id")
      _ => ""
    }
  } else {
    top
  }
  if top2 == "" {
    return Json::object({
      "dispatched": Json::boolean(false),
      "task_id": Json::string(""),
      "to_executor": Json::string(""),
      "note": Json::string("无可派发的待领取任务（依赖满足集合为空）"),
    })
  }
  // 从 store 构建执行者注册表
  var reg = @executor.ExecutorRegistry::new()
  for (name, abl, _created) in self.executor_list() {
    reg = reg.add_ability(name, parse_abilities(abl))
  }
  let names = reg.list()
  let load = self.executor_loads(names)
  let route = reg.route_pick(want, load)
  let best = match route.value("best") {
    Some(Object(b)) => _jstr(Json::object(b), "name")
    _ => ""
  }
  let to = if best != "" { best } else { agent }
  let remaining = match tri.value("count") {
    Some(Json::Number(n, ..)) => if n > 1.0 { (n - 1.0).to_int() } else { 0 }
    _ => 0
  }
  match self.claim(task_id=top2, assignee=to, now~) {
    Ok(_) =>
      Json::object({
        "dispatched": Json::boolean(true),
        "task_id": Json::string(top2),
        "to_executor": Json::string(to),
        "remaining": Json::number(remaining.to_double()),
        "note": Json::string("已按能力/负载路由自动派发给执行者(无注册则回退 agent)"),
      })
    Err(e) =>
      Json::object({
        "dispatched": Json::boolean(false),
        "task_id": Json::string(top2),
        "to_executor": Json::string(to),
        "error": Json::string(e),
        "note": Json::string("派发认领失败，未改动任何状态"),
      })
  }
}