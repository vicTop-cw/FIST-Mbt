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
  assert_true(mo_bool(j1, "persisted"))
  assert_eq(mo_str(mo_get(j1, "decision"), "model"), "mo_free")
  // 消耗掉免费档（limit=1 ⇒ 100% 越过 95% 阈值）
  let j2 = mo_unwrap(model_route_impl(d, ns="mo2", record_model="mo_free"))
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
  // 回落后的窗口必须可判定：越界配置不能把过期检查变成永不过期
  assert_true(mo_bool(j, "persisted"))
}

///|
test "mo_5_reset 只清窗口，hard 才动档位与计数" {
  let d = mo_prep("mo5")
  let _ = mo_unwrap(model_route_impl(d, ns="mo5", config=mo_cfg(1, 5)))
  let j2 = mo_unwrap(model_route_impl(d, ns="mo5", record_model="mo_free"))
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
