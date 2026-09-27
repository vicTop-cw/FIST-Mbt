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
fn qn(v : Int) -> Json {
  Json::number(v.to_double())
}

///|
/// 池条目：{name,limit,used?,window_start?}
fn ent(
  name : String,
  limit : Int,
  used? : Int = -1,
  win? : String = "",
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
  assert_eq(r2.config.free_models.length(), 2)
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
