/// model_router_ops_wbtest.mbt —— 路由编排层（落盘 + 盖章 + 路径校验）的回归锁
///
/// 钉四件事：① project_dir 越界一律 Err（与 report_bug 同一条校验，不能各写一套）；
/// ② 状态**真的走文件**——第二次调用必须看见第一次的用量/档位（跨进程可复现，不靠内存）；
/// ③ 坏配置逐项回落并点名（warnings 非空且能定位到字段）；④ reset 与 hard_reset 的差别。
///
/// `executor_run` 的可执行面是 async 的（同步测试无法 await，沿用 BUG-14/BUG-16 的做法）：
/// argv 形状锁在 src/executor/cli_argv_test.mbt，起进程那段由调用面冒烟覆盖
/// （`python scripts/fist.py call executor_run ... --dry_run`）。

///|
fn mo_get(j : Json, key : String) -> Json {
  match j {
    Json::Object(m) =>
      match m.get(key) {
        Some(v) => v
        None => Json::null()
      }
    _ => Json::null()
  }
}

///|
fn mo_str(j : Json, key : String) -> String {
  match mo_get(j, key) {
    Json::String(s) => s
    _ => ""
  }
}

///|
fn mo_bool(j : Json, key : String) -> Bool {
  match mo_get(j, key) {
    Json::True => true
    Json::False => false
    _ => false
  }
}

///|
fn mo_int(j : Json, key : String) -> Int {
  match mo_get(j, key) {
    Json::Number(n, ..) => n.to_int()
    _ => -999999
  }
}

///|
fn mo_warn_count(j : Json) -> Int {
  match mo_get(j, "warnings") {
    Json::Array(a) => a.length()
    _ => -1
  }
}

///|
/// 用构造器搭配置池（MoonBit 无单引号字符串，字面量 JSON 会埋进转义噪音）
fn mo_cfg(free_limit : Int, paid_limit : Int) -> Json {
  let pool = fn(name : String, limit : Int) -> Json {
    Json::object({
      "name": Json::string(name),
      "limit": Json::number(limit.to_double()),
    })
  }
  Json::object({
    "window_seconds": Json::number(18000.0),
    "threshold_pct": Json::number(95.0),
    "free_pool": Json::array([pool("mo_free", free_limit)]),
    "paid_pool": Json::array([pool("mo_paid", paid_limit)]),
  })
}

///|
/// 独立可重复运行的目录：每次先删状态文件
fn mo_prep(ns : String) -> String {
  @fs.create_dir("temp") catch {
    _ => ()
  }
  let d = "temp/mo_ops"
  @fs.create_dir(d) catch {
    _ => ()
  }
  @fs.remove_file(d + "/memory/model-router-" + ns + ".json") catch {
    _ => ()
  }
  d
}

///|
fn mo_unwrap(r : Result[Json, String]) -> Json {
  match r {
    Ok(j) => j
    Err(e) => abort("应成功，实际 Err: " + e)
  }
}

///|
test "mo_1_绝对路径与穿越路径一律拒绝" {
  for bad in ["C:/Windows", "/etc", "../outside", "a/../b"] {
    match model_route_impl(bad, ns="mo") {
      Err(e) => assert_true(e.contains("project_dir"))
      Ok(_) => abort("越界 project_dir 不该被接受: " + bad)
    }
    match model_router_status_impl(bad, ns="mo") {
      Err(e) => assert_true(e.contains("project_dir"))
      Ok(_) => abort("越界 project_dir 不该被接受: " + bad)
    }
    match model_router_reset_impl(bad, ns="mo") {
      Err(e) => assert_true(e.contains("project_dir"))
      Ok(_) => abort("越界 project_dir 不该被接受: " + bad)
    }
  }
}

///|
test "mo_2_状态走文件：第二次调用看得见第一次的用量与档位" {
  let d = mo_prep("mo2")
  let cfg = mo_cfg(1, 1)
  let j1 = mo_unwrap(model_route_impl(d, ns="mo2", config=cfg))
  assert_true(mo_bool(j1, "ok"))
  assert_eq(
    mo_str(j1, "state_path"),
    "temp/mo_ops/memory/model-router-mo2.json",
  )
  // BUG-62 后语义：只问不消耗 ⇒ persisted=false（没记账）。但显式给了 config 时池**定义**
  // 会被播种进状态文件——这正是 BUG-61 接线的前提：executor_run 自动记账那一笔不带 config，
  // 只认文件里的池。播种只带定义不带用量，所以文件里的 total_used 必须还是 0。
  assert_false(mo_bool(j1, "persisted"))
  assert_true(@fs.path_exists(mo_str(j1, "state_path")))
  assert_eq(mo_str(mo_get(j1, "decision"), "model"), "mo_free")
  let st0 = mo_unwrap(model_router_status_impl(d, ns="mo2"))
  assert_eq(mo_int(mo_get(st0, "status"), "total_used"), 0)
  // 消耗掉免费档（limit=1 ⇒ 100% 越过 95% 阈值）：这一笔同样不带 config，
  // 能记上账本身就证明播种的池定义真的走文件
  let j2 = mo_unwrap(model_route_impl(d, ns="mo2", record_model="mo_free"))
  assert_true(mo_bool(j2, "persisted"))
  assert_eq(mo_str(mo_get(j2, "decision"), "tier"), "paid")
  // 关键：这一笔**不带 config**，只能从状态文件里读到用量——内存传不下来
  let j3 = mo_unwrap(model_route_impl(d, ns="mo2"))
  assert_eq(mo_str(mo_get(j3, "decision"), "model"), "mo_paid")
  assert_eq(mo_warn_count(j3), 0)
  let st = mo_unwrap(model_router_status_impl(d, ns="mo2"))
  assert_true(mo_bool(st, "exists"))
  assert_true(@fs.path_exists("temp/mo_ops/memory/model-router-mo2.json"))
}

///|
test "mo_3_两池耗尽显式失败且不静默改用别的模型" {
  let d = mo_prep("mo3")
  // 只问不消耗 ⇒ 用量不落账，但给了 config 就把池定义播种进文件（BUG-61 接线前提），
  // 所以下面两笔不带 config 的记账仍然落在 mo_free/mo_paid 上
  let _ = mo_unwrap(model_route_impl(d, ns="mo3", config=mo_cfg(1, 1)))
  let _ = mo_unwrap(model_route_impl(d, ns="mo3", record_model="mo_free"))
  let _ = mo_unwrap(model_route_impl(d, ns="mo3", record_model="mo_paid"))
  let j = mo_unwrap(model_route_impl(d, ns="mo3"))
  assert_true(!mo_bool(j, "ok"))
  assert_true(mo_str(j, "note").contains("无可用模型"))
  assert_eq(mo_str(mo_get(j, "decision"), "model"), "")
  // 未配置的模型名：不静默记账，reason 里点名
  let k = mo_unwrap(model_route_impl(d, ns="mo3", record_model="ghost"))
  assert_true(
    mo_str(mo_get(k, "decision"), "reason").contains("未在任何池中配置"),
  )
}

///|
test "mo_4_坏配置逐项回落并点名 warning" {
  let d = mo_prep("mo4")
  let broken = Json::object({
    "window_seconds": Json::number(0.0),
    "threshold_pct": Json::number(900.0),
    "free_pool": Json::array([
      Json::object({ "limit": Json::number(3.0) }),
      Json::object({
        "name": Json::string("ok_model"),
        "limit": Json::number(4.0),
      }),
    ]),
    "paid_pool": Json::string("不是数组"),
  })
  let j = mo_unwrap(model_route_impl(d, ns="mo4", config=broken))
  assert_true(mo_warn_count(j) >= 2)
  let wt = match mo_get(j, "warnings") {
    Json::Array(a) => a.map(fn(x) { x.stringify() }).join(" | ")
    _ => ""
  }
  assert_true(wt.contains("window_seconds"))
  assert_true(wt.contains("threshold_pct"))
  // 池里缺 name 的条目被跳过而不是变成无名模型；坏 paid 池回落默认池（4 个）
  let free = match mo_get(mo_get(j, "usage"), "free_pool") {
    Json::Array(a) => a
    _ => []
  }
  assert_eq(free.length(), 1)
  assert_eq(mo_str(free[0], "name"), "ok_model")
  let paid = match mo_get(mo_get(j, "usage"), "paid_pool") {
    Json::Array(a) => a
    _ => []
  }
  assert_eq(paid.length(), 4)
  // 回落后的窗口必须可判定：越界配置不能把过期检查变成永不过期。
  // 且坏配置照样要能真记账——查询不落盘（BUG-62），这里补一笔消耗来验 persist_error 缺席
  assert_false(mo_bool(j, "persisted"))
  let c = mo_unwrap(
    model_route_impl(d, ns="mo4", record_model="ok_model", config=broken),
  )
  assert_true(mo_bool(c, "persisted"))
  assert_eq(mo_get(c, "persist_error"), Json::null())
}

///|
test "mo_5_reset 只清窗口，hard 才动档位与计数" {
  let d = mo_prep("mo5")
  let _ = mo_unwrap(
    model_route_impl(d, ns="mo5", record_model="mo_free", config=mo_cfg(1, 5)),
  )
  let j2 = mo_unwrap(model_route_impl(d, ns="mo5"))
  assert_eq(mo_str(mo_get(j2, "decision"), "tier"), "paid")
  let soft = mo_unwrap(model_router_reset_impl(d, ns="mo5"))
  assert_eq(mo_str(soft, "reset"), "window")
  assert_eq(mo_str(mo_get(soft, "usage"), "current_tier"), "paid")
  let hard = mo_unwrap(model_router_reset_impl(d, ns="mo5", hard=true))
  assert_eq(mo_str(hard, "reset"), "hard")
  assert_eq(mo_str(mo_get(hard, "usage"), "current_tier"), "free")
  // 硬复位后必须回到免费池（配额清零 + 档位回 free）
  let after = mo_unwrap(model_route_impl(d, ns="mo5"))
  assert_eq(mo_str(mo_get(after, "decision"), "model"), "mo_free")
}

///|
/// BUG-61/62 成对锁：「只问不消耗」必须真的零副作用。
/// BUG-62：不带 config 的查询必须**零副作用**——不建文件、不记账、不推进 pick 的轮询游标。
/// 修复前查询也 mr_save ⇒ 游标被无人消耗地推进、pick 顺手盖上的 window_start（5h 窗口倒计时）
/// 也进了账，而工具描述与 AGENTS.md 承诺的是"record_model 缺省=只问不消耗"。
test "mo_6_无 config 的查询零副作用：不建文件、不换模型" {
  let d = mo_prep("mo6")
  // 两个默认免费模型：只有"游标会不会被推进"这件事能区分两种实现
  let q1 = mo_unwrap(model_route_impl(d, ns="mo6"))
  let p1 = mo_str(q1, "state_path")
  assert_false(mo_bool(q1, "persisted"))
  must_not_exist(p1)
  assert_true(mo_str(q1, "mode").contains("不落盘"))
  let q2 = mo_unwrap(model_route_impl(d, ns="mo6"))
  let q3 = mo_unwrap(model_route_impl(d, ns="mo6"))
  // 同一本（不存在的）账，三次查询必须给同一个模型
  assert_eq(
    mo_str(mo_get(q1, "decision"), "model"),
    mo_str(mo_get(q2, "decision"), "model"),
  )
  assert_eq(
    mo_str(mo_get(q2, "decision"), "model"),
    mo_str(mo_get(q3, "decision"), "model"),
  )
  must_not_exist(p1)
}

///|
/// BUG-61/62 的成对锁：显式给了 config_json 的查询**只播种定义、不播种用量**。
/// 不播种 → executor_run 自动记账那一笔（不带 config）只能拿默认池，自定义模型名走
/// "未在任何池中配置"，配额形同虚设；播种了用量 → 又退回 BUG-62 的偷偷建账。
test "mo_8_带 config 的查询播种池定义：文件里有名但用量为零" {
  let d = mo_prep("mo8")
  let pool = fn(name : String, limit : Int) -> Json {
    Json::object({
      "name": Json::string(name),
      "limit": Json::number(limit.to_double()),
    })
  }
  let cfg = Json::object({
    "window_seconds": Json::number(18000.0),
    "threshold_pct": Json::number(95.0),
    "free_pool": Json::array([pool("mo8_a", 9), pool("mo8_b", 9)]),
    "paid_pool": Json::array([pool("mo8_p", 9)]),
  })
  let q1 = mo_unwrap(model_route_impl(d, ns="mo8", config=cfg))
  assert_false(mo_bool(q1, "persisted"))
  assert_true(mo_str(q1, "mode").contains("播种"))
  let st0 = mo_unwrap(model_router_status_impl(d, ns="mo8"))
  assert_true(mo_bool(st0, "exists"))
  assert_eq(mo_int(mo_get(st0, "status"), "total_used"), 0)
  // 播种后连问三次仍是同一个模型：游标被写过就会被推进，这条就是那件事的反证
  let q2 = mo_unwrap(model_route_impl(d, ns="mo8", config=cfg))
  let q3 = mo_unwrap(model_route_impl(d, ns="mo8", config=cfg))
  let m1 = mo_str(mo_get(q1, "decision"), "model")
  assert_eq(m1, "mo8_a")
  assert_eq(mo_str(mo_get(q2, "decision"), "model"), m1)
  assert_eq(mo_str(mo_get(q3, "decision"), "model"), m1)
  // 反向成对：真消耗（不带 config）必须落在播种下来的池上
  let r1 = mo_unwrap(model_route_impl(d, ns="mo8", record_model="mo8_a"))
  assert_true(mo_bool(r1, "persisted"))
  assert_true(mo_str(r1, "mode").contains("consume"))
  assert_eq(mo_str(mo_get(r1, "decision"), "model"), "mo8_a")
  let st1 = mo_unwrap(model_router_status_impl(d, ns="mo8"))
  assert_eq(mo_int(mo_get(st1, "status"), "total_used"), 1)
  assert_true(usage_has_model(st1, "mo8_a"))
}

///|
/// usage 里是否列出了某个模型名（不依赖字段顺序，只判"账上有名"）。
fn usage_has_model(status_json : Json, name : String) -> Bool {
  let models = match mo_get(mo_get(status_json, "status"), "free_pool") {
    Json::Array(a) => a
    _ => []
  }
  let mut found = false
  for mm in models {
    if mo_str(mm, "name") == name {
      found = true
    }
  }
  found
}

///|
fn must_not_exist(path : String) -> Unit {
  if @fs.path_exists(path) {
    abort("只查询不该建状态文件，但它存在：" + path)
  }
}

///|
/// BUG-64：命名空间必须过 safe_ns —— 写不进盘的 ns 旧实现照样回 ok=true，
/// 配额上限形同虚设。现在三个同步入口一律显式拒绝；空 ns 仍按 default（零回归）。
test "mo_7_非法 namespace 三个入口全拒，空 ns 仍按 default 零回归" {
  let d = mo_prep("mo7")
  // 空 ns = 既有约定里的 default，不许被新校验带着一起拒（零回归对照）
  let okj = mo_unwrap(model_route_impl(d, ns=""))
  assert_true(mo_bool(okj, "ok"))
  assert_true(mo_str(okj, "state_path").contains("model-router-default.json"))
  for bad in ["a/b", "x\\y", "with space", "../esc", "a\\b\\c"] {
    match model_route_impl(d, ns=bad) {
      Ok(j) => abort("非法 ns 未被拒: " + bad + " -> " + j.stringify())
      Err(e) => {
        must_contain(e, "namespace")
        must_contain(e, "只允许")
      }
    }
    match model_router_status_impl(d, ns=bad) {
      Ok(j) => abort("status 未拒非法 ns: " + bad + " -> " + j.stringify())
      Err(e) => must_contain(e, "namespace")
    }
    match model_router_reset_impl(d, ns=bad) {
      Ok(j) => abort("reset 未拒非法 ns: " + bad + " -> " + j.stringify())
      Err(e) => must_contain(e, "namespace")
    }
    // executor_run 是 async（同步测试无法 await，沿用文件头的做法）：
    // 它的 ns 校验由调用面冒烟覆盖，见 scripts/fist.py call executor_run
  }
}

///|
fn must_contain(hay : String, needle : String) -> Unit {
  if not(hay.contains(needle)) {
    abort("文案缺 '\{needle}'：\{hay}")
  }
}

///|
/// BUG-62 最强形式：查询一个字节都不许动状态文件。
/// pick 不止推进游标，还会给选中的模型盖上 window_start（5h 窗口开始倒计时）——
/// 只断言 used==0 的锁看不见这一半，所以这里做**逐字节对照**。
test "mo_9_查询逐字节不改写状态文件，消耗才改写" {
  let d = mo_prep("mo9")
  let dir = "temp/mo_ops/memory"
  @fs.create_dir(dir) catch {
    _ => ()
  }
  let path = dir + "/model-router-mo9.json"
  let pool = fn(name : String) -> Json {
    Json::object({
      "name": Json::string(name),
      "limit": Json::number(9.0),
      "used": Json::number(0.0),
      "window_start": Json::string(""),
    })
  }
  // 手工播种：free_idx=1 ⇒ 决策必须读到文件里的游标，这同时证明"账真的走文件"
  let raw = Json::object({
    "schema": Json::number(1.0),
    "current_tier": Json::string("free"),
    "free_idx": Json::number(1.0),
    "paid_idx": Json::number(0.0),
    "switch_count": Json::number(0.0),
    "last_switch_at": Json::string(""),
    "last_reason": Json::string(""),
    "last_pick": Json::string(""),
    "window_seconds": Json::number(18000.0),
    "threshold_pct": Json::number(95.0),
    "free_pool": Json::array([pool("mo9_a"), pool("mo9_b")]),
    "paid_pool": Json::array([pool("mo9_p")]),
  })
  let _ = @fs.write_string_to_file(path, raw.stringify(), encoding="utf8")
  let before = mr_read_text(path)
  let q = mo_unwrap(model_route_impl(d, ns="mo9"))
  assert_eq(mo_str(mo_get(q, "decision"), "model"), "mo9_b")
  assert_false(mo_bool(q, "persisted"))
  assert_eq(before, mr_read_text(path))
  let _ = mo_unwrap(model_route_impl(d, ns="mo9"))
  let _ = mo_unwrap(model_route_impl(d, ns="mo9"))
  assert_eq(before, mr_read_text(path))
  // 反向成对：真消耗必须改写文件，且账上出现这一次用量
  let r1 = mo_unwrap(model_route_impl(d, ns="mo9", record_model="mo9_a"))
  assert_true(mo_bool(r1, "persisted"))
  assert_true(mr_read_text(path) != before)
  let st = mo_unwrap(model_router_status_impl(d, ns="mo9"))
  assert_eq(mo_int(mo_get(st, "status"), "total_used"), 1)
}

///|
fn mr_read_text(path : String) -> String {
  @fs.read_file_to_string(path, encoding="utf8") catch {
    _ => ""
  }
}
