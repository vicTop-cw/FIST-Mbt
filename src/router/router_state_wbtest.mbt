/// router_state_wbtest.mbt —— 状态序列化/恢复的回归锁（schema v1 的真源在本包）
///
/// 测试里的 JSON 一律**用构造器搭**：MoonBit 没有单引号字符串，且双引号转义会把断言埋进噪音里。

///|
fn qj(items : Array[(String, Json)]) -> Json {
  Json::object(Map(items))
}

///|
fn qs(s : String) -> Json {
  Json::string(s)
}

///|
fn qn(v : Int32) -> Json {
  Json::number(v.to_double())
}

///|
/// 池条目：{name,limit,used?,window_start?}
fn ent(
  name : String,
  limit : Int32,
  used~ : Int32 = -1,
  win~ : String = "",
) -> Json {
  let mut items : Array[(String, Json)] = [
    ("name", qs(name)),
    ("limit", qn(limit)),
  ]
  if used >= 0 {
    items = items + [("used", qn(used))]
  }
  if win != "" {
    items = items + [("window_start", qs(win))]
  }
  qj(items)
}

///|
fn cfg2(free : Array[Json], paid : Array[Json]) -> Json {
  qj([
    ("window_seconds", qn(18000)),
    ("threshold_pct", Json::number(95.0)),
    ("free_pool", Json::array(free)),
    ("paid_pool", Json::array(paid)),
  ])
}

///|
test "rs_1_往返一致：to_state 到 router_restore 保留用量、档位、游标、切换计数" {
  let cfg = cfg2([ent("f1", 2)], [ent("p1", 2)])
  let (r0, _) = router_restore(Json::null(), config=cfg)
  assert_eq(r0.pick(now="2026-09-26T10:00:00Z").model_name, "f1")
  // limit=2 ⇒ 第 1 次调用 50% 不切档，第 2 次 100% 才越过 95% 阈值
  let _ = r0.record_call(model="f1", now="2026-09-26T10:00:00Z")
  assert_eq(r0.current_tier, Free)
  let _ = r0.record_call(model="f1", now="2026-09-26T10:00:00Z")
  assert_eq(r0.current_tier, Paid)
  let state = r0.to_state()
  let (r1, w1) = router_restore(state)
  assert_eq(r1.last_pick, r0.last_pick) // "真在用哪个模型"也要跨进程复原（BUG-56）
  assert_eq(r1.current_tier, Paid)
  assert_eq(w1.length(), 0)
  assert_eq(
    r1.usage_report().stringify() == r0.usage_report().stringify(),
    true,
  )
  assert_eq(r1.switch_count, r0.switch_count)
  assert_eq(r1.pick(now="2026-09-26T10:30:00Z").model_name, "p1")
}

///|
test "rs_2_config 覆盖池定义但保留同名模型用量，改定义不等于清零" {
  let cfg = cfg2([ent("f1", 10)], [ent("p1", 10)])
  let (r0, _) = router_restore(Json::null(), config=cfg)
  let _ = r0.record_call(model="f1", now="2026-09-26T10:00:00Z")
  let _ = r0.record_call(model="f1", now="2026-09-26T10:00:00Z")
  let cfg2b = cfg2([ent("f1", 3)], [ent("p1", 10)])
  let (r1, w1) = router_restore(r0.to_state(), config=cfg2b)
  assert_eq(r1.config.free_models.length(), 1)
  assert_eq(r1.config.free_models[0].limit, 3)
  assert_eq(r1.config.free_models[0].used, 2)
  assert_true(w1.to_string().contains("覆盖池定义"))
  let cfg3 = cfg2([ent("f2", 3)], [ent("p1", 10)])
  let (r2, _) = router_restore(r0.to_state(), config=cfg3)
  assert_eq(r2.config.free_models[0].name, "f2")
  assert_eq(r2.config.free_models[0].used, 0)
}

///|
test "rs_3_坏状态逐项兜底且不静默" {
  let broken = qj([
    ("schema", qn(1)),
    ("current_tier", qs("wat")),
    ("free_idx", qn(-7)),
    ("window_seconds", qn(0)),
    ("threshold_pct", Json::number(900.0)),
    ("free_pool", Json::array([qj([("limit", qn(5))]), ent("ok", 2, used=-3)])),
    ("paid_pool", qs("nope")),
  ])
  let (r, warns) = router_restore(broken)
  assert_eq(r.current_tier, Free)
  assert_eq(r.config.free_models.length(), 1)
  assert_eq(r.config.free_models[0].name, "ok")
  assert_eq(r.config.free_models[0].used, 0)
  assert_eq(r.config.paid_models.length(), 4)
  assert_eq(r.config.window_seconds, 18000)
  assert_eq(r.config.threshold_pct, 95.0)
  // 越界游标必须被夹紧（负游标取模后落到负下标 ⇒ panic），且要点名留 warning
  // 为什么必须夹紧：MoonBit 的 % 与被除数同号，-7 % 2 = -1 而不是 1
  assert_eq(-7 % 2, -1)
  assert_eq(r.free_idx, 0)
  assert_true(r.current_model() is Some(_))
  assert_true(warns.length() >= 3)
  let wt = warns.join(" | ")
  for needle in ["free_idx", "current_tier", "window_seconds", "threshold_pct"] {
    assert_true(wt.contains(needle))
  }
  let (r2, w2) = router_restore(Json::number(3.0))
  assert_eq(r2.current_tier, Free)
  assert_eq(r2.config.free_models.length(), 8)
  assert_true(w2.length() >= 1)
  let (cfgd, wd) = RouterConfig::from_json(Json::null())
  assert_eq(wd.length(), 0)
  assert_eq(cfgd.window_seconds, 18000)
}

///|
test "rs_4_reset_windows 保档位，hard_reset 全复位" {
  let cfg = cfg2([ent("f1", 10)], [ent("p1", 10)])
  let (r, _) = router_restore(Json::null(), config=cfg)
  let _ = r.record_call(model="f1", now="2026-09-26T10:00:00Z")
  let _ = r.force_switch(tier=Paid, now="2026-09-26T10:05:00Z")
  assert_eq(r.current_tier, Paid)
  r.reset_windows()
  assert_eq(r.current_tier, Paid)
  assert_eq(r.config.paid_models[0].used, 0)
  assert_eq(r.config.paid_models[0].window_start, "")
  assert_eq(r.switch_count, 1)
  assert_true(r.last_pick != "") // hard 之前必须"记得在用哪个"，才谈得上复位
  r.hard_reset()
  assert_eq(r.last_pick, "")
  assert_eq(r.current_tier, Free)
  assert_eq(r.switch_count, 0)
  assert_eq(r.last_switch_at, "")
  assert_eq(r.config.free_models[0].used, 0)
}

///|
test "rs_5_state 落盘体含 schema 版本且绝不含密钥形状" {
  let (r, _) = router_restore(Json::null())
  let s = r.to_state().stringify()
  assert_true(s.contains("schema"))
  for bad in ["api_key", "apikey", "token", "sk-", "Bearer", "password"] {
    assert_true(!s.contains(bad))
  }
}

///|
/// BUG-65：rs_3 的"负 used 夹紧"原本是**假绿**——ent() 用 `used >= 0` 当哨兵，
/// 传 used=-3 时该键根本没进 JSON，断言测的是"字段缺失走默认"而不是夹紧。
/// 这里把任意 JSON 值真塞进去，夹紧（model_router.mbt 的 ModelQuota::new）才第一次被钉住。
test "rs_6_负 used 真进 JSON 并被夹紧为 0（补 rs_3 的假绿）" {
  let raw = qj([
    ("schema", qn(1)),
    (
      "free_pool",
      Json::array([
        qj([("name", qs("neg-used")), ("limit", qn(5)), ("used", qn(-3))]),
      ]),
    ),
    (
      "paid_pool",
      Json::array([
        qj([("name", qs("neg-used-paid")), ("limit", qn(5)), ("used", qn(-1))]),
      ]),
    ),
  ])
  let (r, _) = router_restore(raw)
  assert_eq(r.config.free_models.length(), 1)
  assert_eq(r.config.free_models[0].used, 0)
  assert_eq(r.config.paid_models[0].used, 0)
  // 夹紧后仍要能正常决策；current_model 钉**具体名字**而不是"is Some(_)"（rs_3 的弱断言）
  match r.current_model() {
    Some(q) => assert_eq(q.name, "neg-used")
    None => abort("免费池非空，current_model 不该为空")
  }
  assert_eq(r.pick(now="2026-09-27T00:00:00Z").model_name, "neg-used")
}

///|
/// T0r11 白盒锁：CAF 三字段（use_caf_memory / caf_default_preference /
/// caf_min_evidences）纳入 to_state 序列化面 + restore 读回面后，
/// 「播种 → 落盘 → 无 config 读回」往返三字段逐字存活。
/// 机制格（判例-29）：直接断言序列化 JSON 里的三把钥匙——只测「往返后还在」时，
/// to_state 丢字段 + restore 回落默认可能碰巧同值；钥匙名钉在 JSON 面上，
/// 变异对照：任一字段不再序列化 ⇒ 本格当场 abort（锁必红）。
test "rs_7_caf三字段to_state序列化_restore读回_往返逐字存活" {
  let cfg = qj([
    ("window_seconds", qn(18000)),
    ("threshold_pct", Json::number(95.0)),
    ("use_caf_memory", Json::boolean(true)),
    ("caf_default_preference", Json::array([qs("free-a"), qs("free-b")])),
    ("caf_min_evidences", qn(3)),
    ("free_pool", Json::array([ent("f1", 10)])),
    ("paid_pool", Json::array([])),
  ])
  let (r0, _) = router_restore(Json::null(), config=cfg)
  assert_true(r0.config.use_caf_memory)
  let sm : Map[String, Json] = match r0.to_state() {
    Json::Object(m) => m
    _ => abort("to_state 应返回 JSON 对象")
  }
  // 变异对照面：三把钥匙必须真的在序列化 JSON 里
  match sm.get("use_caf_memory") {
    Some(Json::True) => ()
    _ =>
      abort("use_caf_memory 必须出现在 to_state 序列化面且为 true")
  }
  match sm.get("caf_default_preference") {
    Some(Json::Array(a)) => {
      assert_eq(a.length(), 2)
      match (a[0], a[1]) {
        (Json::String(s0), Json::String(s1)) => {
          assert_eq(s0, "free-a")
          assert_eq(s1, "free-b")
        }
        _ =>
          abort("caf_default_preference 序列化面必须是字符串数组")
      }
    }
    _ => abort("caf_default_preference 必须出现在 to_state 序列化面")
  }
  match sm.get("caf_min_evidences") {
    Some(Json::Number(n, ..)) => assert_eq(n.to_int(), 3)
    _ =>
      abort("caf_min_evidences 必须出现在 to_state 序列化面且为 3")
  }
  // 往返格：无 config 的 restore（= model_router_status 的读回路径）
  let (r1, w1) = router_restore(r0.to_state())
  assert_eq(w1.length(), 0)
  assert_true(r1.config.use_caf_memory)
  assert_eq(r1.config.caf_default_preference.length(), 2)
  assert_eq(r1.config.caf_default_preference[0], "free-a")
  assert_eq(r1.config.caf_default_preference[1], "free-b")
  assert_eq(r1.config.caf_min_evidences, 3)
}

///|
/// T0r11 兼容格：旧格式状态文件（schema v1、无 CAF 三字段）回读不崩、零噪音告警，
/// 三字段回落 config 缺省；旧格式状态 + config 显式给了 CAF ⇒ config 生效
/// （与池定义「config 覆盖定义」同语义）。
test "rs_8_旧格式状态文件缺CAF字段_回读不崩_兼容回落" {
  let legacy = qj([
    ("schema", qn(1)),
    ("current_tier", qs("free")),
    ("free_pool", Json::array([ent("f1", 10)])),
    ("paid_pool", Json::array([])),
  ])
  // 无 config（= model_router_status 读回路径）：三字段回落缺省，零告警
  let (r, w) = router_restore(legacy)
  assert_false(r.config.use_caf_memory)
  assert_eq(r.config.caf_default_preference.length(), 0)
  assert_eq(r.config.caf_min_evidences, 10)
  assert_eq(w.length(), 0)
  // 旧格式状态 + 显式 config：config 的 CAF 三件生效
  let cfg = qj([
    ("use_caf_memory", Json::boolean(true)),
    ("caf_default_preference", Json::array([qs("free-a")])),
    ("caf_min_evidences", qn(2)),
  ])
  let (r2, w2) = router_restore(legacy, config=cfg)
  assert_eq(w2.length(), 0)
  assert_true(r2.config.use_caf_memory)
  assert_eq(r2.config.caf_default_preference.length(), 1)
  assert_eq(r2.config.caf_default_preference[0], "free-a")
  assert_eq(r2.config.caf_min_evidences, 2)
}

///|
/// T0r11 坏类型兜底格：状态文件里 CAF 字段类型坏了 ⇒ 回落 config 缺省且点名，
/// 不静默采纳（与 rs_3「坏状态逐项兜底且不静默」同纪律）。
test "rs_9_CAF字段坏类型_兜底且不静默" {
  let bad = qj([
    ("schema", qn(1)),
    ("current_tier", qs("free")),
    ("free_pool", Json::array([ent("f1", 10)])),
    ("paid_pool", Json::array([])),
    ("use_caf_memory", qs("yes")),
    ("caf_default_preference", Json::array([qn(1), qs("free-a")])),
    ("caf_min_evidences", qs("abc")),
  ])
  let (r, w) = router_restore(bad)
  assert_false(r.config.use_caf_memory)
  assert_eq(r.config.caf_default_preference.length(), 1)
  assert_eq(r.config.caf_default_preference[0], "free-a") // 非字符串元素被忽略
  assert_eq(r.config.caf_min_evidences, 10)
  let wt = w.join(" | ")
  assert_true(wt.contains("use_caf_memory"))
  assert_true(wt.contains("caf_default_preference"))
  assert_true(wt.contains("caf_min_evidences"))
}
