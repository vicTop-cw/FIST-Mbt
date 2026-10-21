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
  if !hay.contains(needle) {
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

///|
/// Star 门接入锁（mo_10）：默认未配置 `FIST_STAR_GATE_PUBKEY_HEX` 时必须保持现状——
/// 回执带 `star_gate` 字段、`gate_enabled=false`、`free_pool_unlocked=true`、`ok=true`，
/// 且 `warnings` 仍为零（不污染既有零警告语义）。判定逻辑本身由 star_gate_wbtest 的
/// policy 五锁覆盖；本锁只钉「接线 + 零回归」这一半。
test "mo_10_Star门默认未启用：回执带 star_gate 且不拦免费池" {
  let d = mo_prep("mo10")
  let j = mo_unwrap(model_route_impl(d, ns="mo10", config=mo_cfg(1, 1)))
  assert_true(mo_bool(j, "ok"))
  let g = mo_get(j, "star_gate")
  assert_false(mo_bool(g, "gate_enabled"))
  assert_true(mo_bool(g, "free_pool_unlocked"))
  if mo_str(g, "note").contains("FIST_STAR_GATE_PUBKEY_HEX") {

  } else {
    fail("未配置的 note 应点明 env 名，实际: \{mo_str(g, "note")}")
  }
}

///|
fn mr_read_text(path : String) -> String {
  @fs.read_file_to_string(path, encoding="utf8") catch {
    _ => ""
  }
}

///|
/// `model_auth_status`（ma_*）—— 只读认证/Star 门状态查询的回归锁。
/// 判定逻辑走纯计算 `mr_auth_gate`（合成值直传，**不污染真实 env**，CI 上可复现）；
/// `ma_4` 再走一次 impl 端到端，锁"零副作用"那一半。
/// 锁三档：默认未配置零回归 / 只配公钥 fail-closed / 坏 attestation 不崩溃。

///|
test "ma_1_默认未配置：gate_enabled=false、free_pool_unlocked=true、verdict 空" {
  let g = mr_auth_gate("", "", "", 0L)
  assert_false(mo_bool(g, "gate_enabled"))
  assert_true(mo_bool(g, "free_pool_unlocked"))
  assert_false(mo_bool(g, "pinned_key_configured"))
  assert_false(mo_bool(g, "attestation_present"))
  assert_false(mo_bool(g, "user_login_configured"))
  assert_eq(mo_str(g, "verdict"), "")
  assert_true(mo_str(g, "note").contains("FIST_STAR_GATE_PUBKEY_HEX"))
  // 没有 attestation 可解析，TTL 与签发年龄都必须给 0（不是 0L 占位的伪读数）
  assert_eq(mo_int(g, "ttl_seconds"), 0)
  assert_eq(mo_int(g, "attestation_age_seconds"), 0)
}

///|
test "ma_2_只配 pinned key 无 attestation：门启用但 fail-closed" {
  let g = mr_auth_gate("deadbeef", "", "vicTop-cw", 1000L)
  assert_true(mo_bool(g, "gate_enabled"))
  assert_false(mo_bool(g, "free_pool_unlocked"))
  assert_true(mo_bool(g, "pinned_key_configured"))
  assert_false(mo_bool(g, "attestation_present"))
  assert_true(mo_bool(g, "user_login_configured"))
  // 未提供 attestation ⇒ verdict 缺省（gate 的 verdict 空串），TTL/年龄仍是 0
  assert_eq(mo_str(g, "verdict"), "")
  assert_eq(mo_int(g, "ttl_seconds"), 0)
  assert_eq(mo_int(g, "attestation_age_seconds"), 0)
}

///|
test "ma_3_伪造/残缺 attestation：verdict 归 unreadable 或 bad_format 且不崩溃" {
  // ① 根本不是 JSON → Unreadable
  let g1 = mr_auth_gate("deadbeef", "<<<不是JSON>>>", "vicTop-cw", 1000L)
  assert_true(mo_bool(g1, "gate_enabled"))
  assert_false(mo_bool(g1, "free_pool_unlocked"))
  assert_eq(mo_str(g1, "verdict"), "unreadable")
  // ② 合法 JSON 但 format 非本门格式 → BadFormat
  let g2 = mr_auth_gate(
    "deadbeef", "{\"format\":\"other/v9\",\"issued_at\":100,\"ttl_seconds\":1}",
    "vicTop-cw", 1000L,
  )
  assert_eq(mo_str(g2, "verdict"), "bad_format")
  // ③ format 对但缺字段 → BadFormat，且 TTL/年龄读不到给 0（不崩溃）
  let g3 = mr_auth_gate(
    "deadbeef", "{\"format\":\"fist-star-gate-attestation/v1\",\"algorithm\":\"ed25519\"}",
    "vicTop-cw", 1000L,
  )
  assert_eq(mo_str(g3, "verdict"), "bad_format")
  assert_eq(mo_int(g3, "ttl_seconds"), 0)
  assert_eq(mo_int(g3, "attestation_age_seconds"), 0)
  // ④ 有效字段齐备但签名非法 → bad_signature（钉死公钥 ≠ 清单公钥路径）
  let g4 = mr_auth_gate(
    "aaaapinned",
    "{\"format\":\"fist-star-gate-attestation/v1\",\"algorithm\":\"ed25519\"," +
    "\"list\":[\"vicTop-cw\"],\"issued_at\":10,\"ttl_seconds\":999," +
    "\"public_key_hex\":\"zz\",\"signature_hex\":\"zz\"}",
    "vicTop-cw",
    1000L,
  )
  assert_eq(mo_str(g4, "verdict"), "bad_signature")
  assert_false(mo_bool(g4, "free_pool_unlocked"))
}

///|
test "ma_4_impl 端到端零副作用：不建状态文件、gate 与 pools 都在位" {
  let d = mo_prep("ma4")
  let path = "temp/mo_ops/memory/model-router-ma4.json"
  must_not_exist(path)
  let j = mo_unwrap(model_auth_status_impl(d, ns="ma4"))
  assert_true(mo_bool(j, "ok"))
  let gate = mo_get(j, "gate")
  // 默认未配置 Star 门（本测试不设 env，CI 上三个 FIST_STAR_GATE_* 均为空）
  assert_false(mo_bool(gate, "gate_enabled"))
  assert_true(mo_bool(gate, "free_pool_unlocked"))
  let pools = mo_get(j, "pools")
  assert_true(mo_get(pools, "exists") != Json::null())
  // 零副作用：只读查询不得落任何状态文件
  must_not_exist(path)
}

///|
test "bug229_重试分支记账冷却不留静默吞错" {
  // mr_retry_note：Ok→""，Err→"model: err"
  assert_eq(mr_retry_note("m1", Ok(())), "")
  assert_eq(mr_retry_note("m1", Err("disk full")), "m1: disk full")
  // mr_opt_arr_field：空数组→[]（不出字段），非空→出字段
  assert_eq(mr_opt_arr_field("k", []).length(), 0)
  assert_eq(mr_opt_arr_field("k", ["a"]).length(), 1)
  // mr_record_failure：模型不在池中→Ok(())（不报错）
  let d = mo_prep("bug229")
  match mr_record_failure(d, "nonexistent_model", ns="bug229") {
    Ok(_) => ()
    Err(e) => abort("不在池中的模型应返回 Ok，实际 Err: " + e)
  }
}

// ===== CAF dry_run 预览（验收标准 3 的 server 层接线锁）=====

///|
/// caf_dr 用配置：`use_caf_memory=true` + 双模型池（两模型都健康，便于软性重排有空间）。
/// `use_caf` 传 false 时只把开关关掉，其余保持不变（供 caf_dr_3 的对照面）。
fn caf_cfg(use_caf : Bool) -> Json {
  let pool = fn(name : String, limit : Int) -> Json {
    Json::object({
      "name": Json::string(name),
      "limit": Json::number(limit.to_double()),
    })
  }
  Json::object({
    "window_seconds": Json::number(18000.0),
    "threshold_pct": Json::number(95.0),
    "free_pool": Json::array([pool("caf_free_a", 9), pool("caf_free_b", 9)]),
    "paid_pool": Json::array([pool("caf_paid", 9)]),
    "use_caf_memory": Json::boolean(use_caf),
  })
}

///|
/// caf_dr 用独立目录：复用 mo_prep，额外清掉 CAF 状态文件（保证每次从"无记忆"起步）。
fn caf_prep(ns : String) -> String {
  let d = mo_prep(ns)
  @fs.remove_file("temp/mo_ops/memory/model-router-caf-" + ns + ".json") catch {
    _ => ()
  }
  d
}

///|
/// 预览形状锁：dry_run=true 必须回建议模型 + 历史依据（decision.basis 是数组）、
/// persisted=false，且**未创建任何状态文件**（CAF 状态文件 + 普通路由状态文件都没有）。
test "caf_dr_1_零副作用预览形状" {
  let d = caf_prep("caf_dr1")
  let j = mo_unwrap(
    model_route_impl(
      d,
      ns="caf_dr1",
      config=caf_cfg(true),
      dry_run=true,
      context="任务A",
    ),
  )
  assert_true(mo_bool(j, "ok"))
  assert_false(mo_bool(j, "persisted"))
  assert_eq(mo_str(j, "context"), "任务A")
  must_contain(mo_str(j, "mode"), "caf-dry-run")
  // decision 是标准 3 形状：suggestion + basis（数组）
  let dec = mo_get(j, "decision")
  assert_true(mo_str(dec, "suggestion") != "")
  assert_true(!mo_str(dec, "base").is_empty())
  match mo_get(dec, "basis") {
    Json::Array(_) => ()
    _ => abort("decision.basis 应为数组，实际不是")
  }
  // 零副作用：dry_run 连"播种池定义"那一步都没走
  must_not_exist(mo_str(j, "state_path"))
  must_not_exist(mo_str(j, "caf_state_path"))
}

///|
/// 空记忆零回归：无 CAF 状态文件时，suggestion 必须等于 base（软性重排不改变原决策），
/// basis 必须是**空数组**（`[]`，不是 null）——调用方按数组遍历不会 panic。
test "caf_dr_2_空记忆零回归" {
  let d = caf_prep("caf_dr2")
  let j = mo_unwrap(
    model_route_impl(d, ns="caf_dr2", config=caf_cfg(true), dry_run=true),
  )
  let dec = mo_get(j, "decision")
  assert_eq(mo_str(dec, "suggestion"), mo_str(dec, "base"))
  match mo_get(dec, "basis") {
    Json::Array(a) => assert_eq(a.length(), 0)
    _ => abort("空记忆 basis 应为空数组，实际不是")
  }
  // 空记忆也绝不落盘
  must_not_exist(mo_str(j, "state_path"))
  must_not_exist(mo_str(j, "caf_state_path"))
}

///|
/// 未开启显式拒绝：`use_caf_memory=false`（默认配置）时 dry_run 必须回 Err 且点名 CAF，
/// 而不是静默降级回普通查询（BUG-31 同族的最难查静默降级）。
test "caf_dr_3_未开启显式拒绝" {
  let d = caf_prep("caf_dr3")
  match model_route_impl(d, ns="caf_dr3", dry_run=true) {
    Err(e) => {
      must_contain(e, "CAF")
      must_contain(e, "use_caf_memory=false")
    }
    Ok(j) =>
      abort(
        "未开启 CAF 的 dry_run 应被拒绝，实际 Ok: " + j.stringify(),
      )
  }
  // 显式给 use_caf_memory=false 也一样拒
  match model_route_impl(d, ns="caf_dr3", config=caf_cfg(false), dry_run=true) {
    Err(e) => must_contain(e, "CAF")
    Ok(j) =>
      abort(
        "显式 use_caf_memory=false 应被拒绝，实际 Ok: " + j.stringify(),
      )
  }
}

///|
/// 零副作用不落盘的最强形式：连调两次，决策/模式/状态路径逐字节一致
/// （stamped_at 走墙钟、粒度 1s，跨秒边界会不同，故不把它纳入逐字节比较——这是时钟本身的性质，
/// 不是副作用），且工作目录下**不新增** model-router-caf-* 与 model-router-* 状态文件。
test "caf_dr_4_零副作用不落盘" {
  let d = caf_prep("caf_dr4")
  let j1 = mo_unwrap(
    model_route_impl(
      d,
      ns="caf_dr4",
      config=caf_cfg(true),
      dry_run=true,
      context="ctx",
    ),
  )
  let j2 = mo_unwrap(
    model_route_impl(
      d,
      ns="caf_dr4",
      config=caf_cfg(true),
      dry_run=true,
      context="ctx",
    ),
  )
  assert_eq(
    mo_get(j1, "decision").stringify(),
    mo_get(j2, "decision").stringify(),
  )
  assert_eq(mo_bool(j1, "persisted"), mo_bool(j2, "persisted"))
  assert_eq(mo_str(j1, "mode"), mo_str(j2, "mode"))
  assert_eq(mo_str(j1, "state_path"), mo_str(j2, "state_path"))
  assert_eq(mo_str(j1, "caf_state_path"), mo_str(j2, "caf_state_path"))
  must_not_exist(mo_str(j1, "state_path"))
  must_not_exist(mo_str(j1, "caf_state_path"))
  must_not_exist("temp/mo_ops/memory/model-router-caf_dr4.json")
  must_not_exist("temp/mo_ops/memory/model-router-caf-caf_dr4.json")
}

///|
/// 有记忆时 basis 有条目：预写一条与 context 同 feature_hash 的 CAF 记录，
/// dry_run 读盘恢复后，basis 必须非空（证明"历史依据"真的来自落盘的 CAF 记忆）。
test "caf_dr_5_有记忆时 basis 有条目" {
  let d = caf_prep("caf_dr5")
  let mem = @router.CafMemory::new()
  for i = 0; i < 5; i = i + 1 {
    mem.push(
      @router.CafRecord::new(
        feature_hash=@router.caf_feature_hash("ctx"),
        model="caf_free_a",
        ok=true,
        cost=1.0,
        ts="2026-10-15T00:00:00Z",
      ),
    )
  }
  let caf_dir = "temp/mo_ops/memory"
  @fs.create_dir(caf_dir) catch {
    _ => ()
  }
  let caf_path = caf_dir + "/model-router-caf-caf_dr5.json"
  @fs.write_string_to_file(
    caf_path,
    @router.caf_memory_dump(mem).stringify(),
    encoding="utf8",
  ) catch {
    _ => abort("预写 CAF 状态文件失败")
  }
  let j = mo_unwrap(
    model_route_impl(
      d,
      ns="caf_dr5",
      config=caf_cfg(true),
      dry_run=true,
      context="ctx",
    ),
  )
  match mo_get(mo_get(j, "decision"), "basis") {
    Json::Array(a) => assert_true(a.length() >= 1)
    _ => abort("有记忆时 basis 应为非空数组")
  }
  // dry_run 读过记忆但仍不落盘（连回写都不做）
  must_not_exist(mo_str(j, "state_path"))
}

///|
/// 一条白盒辅助：读 CAF 记忆文件并返回 `records` 数组长度（读不到/非法即 abort，测试自爆）。
fn caf_read_rec_count(path : String) -> Int {
  let raw = @fs.read_file_to_string(path, encoding="utf8") catch {
    _ => abort("读 CAF 记忆文件失败：" + path)
  }
  let parsed = @json.parse(raw) catch {
    _ => abort("CAF 文件不是合法 JSON：" + path)
  }
  match mo_get(parsed, "records") {
    Json::Array(a) => a.length()
    _ => abort("CAF 文件缺 records 数组")
  }
}

///|
/// 读侧降级锁（Slice B · caf_dr_6）：CAF 记忆文件是**坏 JSON** 时，dry_run 路径必须
/// 降级为「空记忆 + warning」且**不 panic**，返回 Ok；warnings 必须点名坏 JSON
/// （否则调用方以为"没建议是因为真的没记忆"，其实是记忆坏了，BUG-31 同族最难查的静默降级）。
/// 坏文件本身保留不删（坏状态是证据，与 mr_read 同款纪律）。
test "caf_dr_6_坏记忆JSON降级不panic" {
  let d = caf_prep("caf_dr6")
  @fs.create_dir("temp/mo_ops/memory") catch {
    _ => ()
  }
  let caf_path = "temp/mo_ops/memory/model-router-caf-caf_dr6.json"
  let bad = "{ 这不是合法 JSON @@"
  @fs.write_string_to_file(caf_path, bad, encoding="utf8") catch {
    _ => abort("预写坏 JSON 失败")
  }
  let j = mo_unwrap(
    model_route_impl(
      d,
      ns="caf_dr6",
      config=caf_cfg(true),
      dry_run=true,
      context="ctx",
    ),
  )
  assert_true(mo_bool(j, "ok"))
  // 降级为空记忆：suggestion == base，basis 是空数组（不 panic、不塌成 null）
  let dec = mo_get(j, "decision")
  assert_eq(mo_str(dec, "suggestion"), mo_str(dec, "base"))
  match mo_get(dec, "basis") {
    Json::Array(a) => assert_eq(a.length(), 0)
    _ => abort("坏 JSON 时应降级为空 basis 数组")
  }
  // warnings 点名坏 JSON（根因可见，不静默）
  assert_true(mo_warn_count(j) >= 1)
  let wt = match mo_get(j, "warnings") {
    Json::Array(a) => a.map(fn(x) { x.stringify() }).join(" | ")
    _ => ""
  }
  assert_true(wt.contains("坏 JSON"))
  // 坏文件是证据：读侧不得删除/覆盖
  assert_eq(
    @fs.read_file_to_string(caf_path, encoding="utf8") catch {
      _ => abort("坏文件被读侧删掉了")
    },
    bad,
  )
  // dry_run 零副作用：普通路由状态文件不写
  must_not_exist(mo_str(j, "state_path"))
}

///|
/// 写半闭环锁（Slice B · caf_dr_7）：真消耗（record_model）且 `use_caf_memory=true` 时，
/// 本次调用必须作为一条 evidence **追加**进 CAF 记忆文件（3 条，不是覆盖成 1 条），
/// 并且随后在同 ns 的 dry_run 能看见历史依据（basis 非空）——闭合标准 3 的读写两半。
test "caf_dr_7_真消耗回写CAF记忆并闭合读写闭环" {
  let d = caf_prep("caf_dr7")
  let caf_path = "temp/mo_ops/memory/model-router-caf-caf_dr7.json"
  // 先播 1 条既有 evidence，验证 push 是"追加"而非"覆盖"
  let seed = @router.CafMemory::new()
  seed.push(
    @router.CafRecord::new(
      feature_hash=@router.caf_feature_hash(
        @router.caf_normalize_context("旧任务"),
      ),
      model="caf_free_b",
      ok=true,
      cost=0.1,
      ts="2026-10-17T00:00:00Z",
    ),
  )
  @fs.create_dir("temp/mo_ops/memory") catch {
    _ => ()
  }
  @fs.write_string_to_file(
    caf_path,
    @router.caf_memory_dump(seed).stringify(),
    encoding="utf8",
  ) catch {
    _ => abort("预写种子失败")
  }
  assert_eq(caf_read_rec_count(caf_path), 1)
  // 真消耗：记账 + CAF 写半同时发生
  let j = mo_unwrap(
    model_route_impl(
      d,
      ns="caf_dr7",
      config=caf_cfg(true),
      record_model="caf_free_a",
      context="新任务",
    ),
  )
  assert_true(mo_bool(j, "persisted"))
  assert_eq(caf_read_rec_count(caf_path), 2)
  // 闭合读写闭环：同 ns 的 dry_run 现在能看见 evidence → basis 非空
  let j2 = mo_unwrap(
    model_route_impl(
      d,
      ns="caf_dr7",
      config=caf_cfg(true),
      dry_run=true,
      context="新任务",
    ),
  )
  match mo_get(mo_get(j2, "decision"), "basis") {
    Json::Array(a) => assert_true(a.length() >= 1)
    _ => abort("回写后 dry_run 的 basis 应为非空数组")
  }
  // 幂等（§三.6）：每次真消耗恰好追加 1 条（1+1+1=3），不重复计数也不丢
  let _again = mo_unwrap(
    model_route_impl(
      d,
      ns="caf_dr7",
      config=caf_cfg(true),
      record_model="caf_free_a",
      context="新任务",
    ),
  )
  assert_eq(caf_read_rec_count(caf_path), 3)
}

///|
/// 零回归红线锁（Slice B · caf_dr_8）：`use_caf_memory=false` 时，即使真消耗发生，
/// CAF 记忆文件也**一个字节都不碰**（不存在 → 仍不存在）。路由器状态照常记账（persisted=true），
/// 但 CAF 写半必须被门禁挡下。
test "caf_dr_8_未开启use_caf_memory真消耗不写CAF文件" {
  let d = caf_prep("caf_dr8")
  let j = mo_unwrap(
    model_route_impl(
      d,
      ns="caf_dr8",
      config=caf_cfg(false),
      record_model="caf_free_a",
      context="ctx",
    ),
  )
  assert_true(mo_bool(j, "persisted"))
  must_not_exist("temp/mo_ops/memory/model-router-caf-caf_dr8.json")
}

///|
/// 写半证据保留锁（Slice B · caf_dr_9）：push 路径遇到坏 JSON 记忆文件时，**不覆盖不删除**——
/// 文件字节级不变（坏状态是证据），本次 evidence 跳过，warnings 点名坏 JSON（不静默吞）。
/// 主路径（记账）不受影响。
test "caf_dr_9_坏JSON记忆push不覆盖不删除" {
  let d = caf_prep("caf_dr9")
  @fs.create_dir("temp/mo_ops/memory") catch {
    _ => ()
  }
  let caf_path = "temp/mo_ops/memory/model-router-caf-caf_dr9.json"
  let bad = "{ 这不是合法 JSON @@"
  @fs.write_string_to_file(caf_path, bad, encoding="utf8") catch {
    _ => abort("预写坏 JSON 失败")
  }
  let j = mo_unwrap(
    model_route_impl(
      d,
      ns="caf_dr9",
      config=caf_cfg(true),
      record_model="caf_free_a",
      context="ctx",
    ),
  )
  // 主路径照常（CAF 写半是旁路增强，不把路由决策/记账拉黑）
  assert_true(mo_bool(j, "persisted"))
  // 坏证据字节级保留
  assert_eq(
    @fs.read_file_to_string(caf_path, encoding="utf8") catch {
      _ => abort("坏文件被 push 覆盖/删掉了")
    },
    bad,
  )
  // warnings 点名坏 JSON
  assert_true(mo_warn_count(j) >= 1)
  let wt = match mo_get(j, "warnings") {
    Json::Array(a) => a.map(fn(x) { x.stringify() }).join(" | ")
    _ => ""
  }
  assert_true(wt.contains("坏 JSON"))
}

///|
/// 一条白盒辅助：读 CAF 记忆文件并返回**末条**记录的 `ok` 字段（读不到/非法即 abort）。
fn caf_read_last_ok(path : String) -> Bool {
  let raw = @fs.read_file_to_string(path, encoding="utf8") catch {
    _ => abort("读 CAF 记忆文件失败：" + path)
  }
  let parsed = @json.parse(raw) catch {
    _ => abort("CAF 文件不是合法 JSON：" + path)
  }
  match mo_get(parsed, "records") {
    Json::Array(a) =>
      if a.is_empty() {
        abort("CAF 文件 records 为空，无末条可读")
      } else {
        let last = a[a.length() - 1]
        match mo_get(last, "ok") {
          Json::True => true
          Json::False => false
          _ => abort("末条记录缺 ok 布尔字段")
        }
      }
    _ => abort("CAF 文件缺 records 数组")
  }
}

///|
/// 失败执行污染锁（Slice B 遗留项 · caf_dr_10）：`mr_record_only` / `model_route_impl` 在
/// 真消耗后 push 的 CAF evidence 必须带上调用方给定的 `ok` 语义——
///   失败执行 → push ok=false，成功执行 → push ok=true（默认）。失败不得误写 ok=true。
/// 修法前此处硬编码 `ok=true`：失败执行也 push `ok=true`，长期抬高"常失败模型"的 CAF 成功率。
/// 本锁在**穿透链**上验证（model_route_impl → mr_caf_push_evidence → 落盘读回），
/// 不触发 OFM/CLI 真执行（与 caf_dr_7 同口径的最小可验一格）。
test "caf_dr_10_失败执行push_ok_false_CAF学成败" {
  let d = caf_prep("caf_dr10")
  let caf_path = "temp/mo_ops/memory/model-router-caf-caf_dr10.json"
  // 失败执行：显式 ok=false → 写进 CAF 记忆的是 ok=false（而非默认 true）
  let j = mo_unwrap(
    model_route_impl(
      d,
      ns="caf_dr10",
      config=caf_cfg(true),
      record_model="caf_free_a",
      context="ctx",
      ok=false,
    ),
  )
  assert_true(mo_bool(j, "persisted"))
  assert_false(caf_read_last_ok(caf_path))
  // 成功执行：不给 ok（默认 true）→ 写进 CAF 记忆的是 ok=true
  let j2 = mo_unwrap(
    model_route_impl(
      d,
      ns="caf_dr10",
      config=caf_cfg(true),
      record_model="caf_free_b",
      context="ctx",
    ),
  )
  assert_true(mo_bool(j2, "persisted"))
  assert_true(caf_read_last_ok(caf_path))
  // 两条都落进同一记忆：末条为成功侧、总数 = 2，验证"追加"而非"覆盖"
  assert_eq(caf_read_rec_count(caf_path), 2)
}
