/// model_router_wbtest.mbt —— 合并后的模型路由回归锁
///
/// 覆盖：档位切换阈值、5h 窗口过期重置、**空池 / 非法时间 / 未知档位 / 两池全耗尽**这些
/// 源项目会 panic 或静默出错的边界（边界四问：空输入 / 极值 / 非法输入 / 资源极限），
/// 以及 ISO↔epoch 秒的精确性（源项目用「365 天固定年 + 每月 31 天」近似，跨月/闰年会偏）。

///|
fn rt_at(day : Int, hour : Int) -> String {
  secs_to_iso(1790000000 + day * 86400 + hour * 3600)
}

///|
/// 造一个可控路由器：free 1 个 limit=N、paid 1 个 limit=M
fn rt_router(free_limit : Int, paid_limit : Int) -> ModelRouter {
  let cfg = {
    window_seconds: 18000,
    threshold_pct: 95.0,
    free_models: [ModelQuota::new(name="free-a", tier=Free, limit=free_limit)],
    paid_models: [ModelQuota::new(name="paid-a", tier=Paid, limit=paid_limit)],
    ofm_endpoint: "",
    use_laya: false,
  }
  ModelRouter::from_config(cfg)
}

///|
test "rt_1_ISO 与 epoch 秒换算精确（含闰日、跨年）" {
  assert_eq(iso_to_secs("1970-01-01T00:00:00Z"), 0)
  assert_eq(iso_to_secs("2024-02-29T00:00:00Z"), 1709164800)
  assert_eq(iso_to_secs("2026-01-01T00:00:00Z"), 1767225600)
  assert_eq(iso_to_secs("2026-03-01T00:00:00Z"), 1772323200)
  assert_eq(
    secs_to_iso(iso_to_secs("2026-09-26T13:37:55Z")),
    "2026-09-26T13:37:55Z",
  )
}

///|
test "rt_2_非法时间戳一律 -1，绝不当成 0 秒" {
  let bad_list = [
    "", "not-a-date", "2026-13-01T00:00:00Z", "2026-00-10T00:00:00Z", "2026-01-32T00:00:00Z",
    "2026-09-26T24:00:00Z", "2026-09-26T13:61:00Z", "2026/09/26 13:37:55", "1969-12-31T23:59:59Z",
    "2026-9-6T1:2:3Z", "2026-09-26",
  ]
  for bad in bad_list {
    assert_eq(iso_to_secs(bad), -1)
  }
  assert_eq(secs_to_iso(-1), "")
}

///|
// R12-R6 bugfind（BUG-218）：Y2038 溢出——days_from_civil*86400 在 Int32 下溢出。
// 2038-12-31 → days=25201, *86400 = 2.18e9 > 2^31-1（Y2038 问题）。
// 2037-12-31 → days=24836, *86400 ≈ 2.15e9 < 2^31-1，安全。
test "rt_2b_Y2038 边界：2037 合法、2038 溢出返回 -1（BUG-218）" {
  // 2037 是 Int32 下最大安全年份
  assert_true(iso_to_secs("2037-12-31T00:00:00Z") > 0)
  // 2038 起溢出，修复后返回 -1 而不是乱数
  assert_eq(iso_to_secs("2038-01-01T00:00:00Z"), -1)
  // 极端 9999 也返回 -1（旧代码 y>9999 形同虚设）
  assert_eq(iso_to_secs("9999-12-31T23:59:59Z"), -1)
}

///|
test "rt_3_达 95% 阈值自动切付费，且 reason 是可读文字不是时间戳" {
  let r = rt_router(20, 5)
  let _ = r.pick(now=rt_at(0, 1))
  let mut d = r.pick(now=rt_at(0, 1))
  for _ in 0..<19 {
    d = r.record_call(model="free-a", now=rt_at(0, 1))
  }
  assert_eq(r.current_tier, Paid)
  assert_eq(r.config.free_models[0].used, 19)
  assert_true(d.reason.contains("threshold"))
  assert_eq(d.switched, true)
  assert_eq(r.switch_count, 1)
}

///|
test "rt_4_空池不 panic：current_model=None 且决策显式不可用" {
  let cfg = {
    window_seconds: 18000,
    threshold_pct: 95.0,
    free_models: [],
    paid_models: [],
    ofm_endpoint: "",
    use_laya: false,
  }
  let r = ModelRouter::from_config(cfg)
  assert_eq(r.current_model(), None)
  let d = r.pick(now=rt_at(0, 1))
  assert_eq(d.available, false)
  assert_eq(d.model_name, "")
  assert_true(d.reason.contains("no available model"))
  let d2 = r.force_switch(tier=Paid, now=rt_at(0, 2))
  assert_eq(d2.available, false)
  assert_eq(r.current_tier, Free)
}

///|
test "rt_5_资源极限：两池全耗尽必须显式 unavailable 而非静默回退" {
  let r = rt_router(1, 1)
  assert_eq(r.pick(now=rt_at(0, 1)).model_name, "free-a")
  let _ = r.record_call(model="free-a", now=rt_at(0, 1))
  assert_eq(r.current_tier, Paid)
  assert_eq(r.pick(now=rt_at(0, 2)).model_name, "paid-a")
  let d = r.record_call(model="paid-a", now=rt_at(0, 2))
  assert_eq(d.available, false)
  // 免费池也已打满 ⇒ 不许"切回 free 继续假装可用"（源项目会静默切回）
  assert_eq(r.current_tier, Paid)
  assert_eq(r.config.free_models[0].used, 1)
  // 窗口过期后恢复可用
  let back = r.pick(now=rt_at(0, 8))
  assert_eq(back.available, true)
}

///|
test "rt_6_5h 窗口按每个模型独立过期重置" {
  let r = rt_router(2, 2)
  let _ = r.record_call(model="free-a", now=rt_at(0, 1))
  assert_eq(r.config.free_models[0].used, 1)
  assert_eq(r.window_reset_check(now=rt_at(0, 4)), 0)
  assert_eq(r.config.free_models[0].used, 1)
  assert_eq(r.window_reset_check(now=rt_at(0, 6)), 1)
  assert_eq(r.config.free_models[0].used, 0)
  assert_eq(r.config.free_models[0].window_start, rt_at(0, 6))
  assert_eq(r.window_reset_check(now="garbage"), 0)
  assert_eq(r.config.free_models[0].used, 0)
}

///|
test "rt_7_无限配额 remaining=-1 且永不 exhausted" {
  let m = ModelQuota::new(name="unlimited", tier=Free, limit=0)
  assert_eq(m.remaining(), -1)
  assert_eq(m.is_exhausted(), false)
  assert_eq(m.usage_pct(), 0.0)
  assert_eq(m.to_json().stringify().contains("unlimited"), true)
}

///|
test "rt_8_未知档位字符串返回 None，不静默当免费档" {
  assert_eq(ModelTier::from_string("free"), Some(Free))
  assert_eq(ModelTier::from_string("paid"), Some(Paid))
  assert_eq(ModelTier::from_string("PAID"), None)
  assert_eq(ModelTier::from_string(""), None)
  assert_eq(ModelTier::from_string("enterprise"), None)
}

///|
test "rt_9_record_call 未知模型显式说明且不计入用量" {
  let r = rt_router(5, 5)
  let d = r.record_call(model="ghost", now=rt_at(0, 1))
  assert_true(d.reason.contains("unknown model"))
  assert_eq(r.config.free_models[0].used, 0)
}

///|
/// 直接构造 Json（不走字符串解析：避免转义噪音，也让"坏字段"可精确表达）
fn rt_json_cfg(ws : Json, tp : Json, free : Json, paid : Json) -> Json {
  Json::object({
    "window_seconds": ws,
    "threshold_pct": tp,
    "free_pool": free,
    "paid_pool": paid,
  })
}

///|
test "rt_10_配置逐字段兜底：坏值回落默认且必须留 warning" {
  let good = rt_json_cfg(
    Json::number(3600.0),
    Json::number(80.0),
    Json::array([
      Json::object({ "name": Json::string("f1"), "limit": Json::number(7.0) }),
      Json::object({ "limit": Json::number(3.0) }),
    ]),
    Json::array([]),
  )
  let (cfg, warns) = RouterConfig::from_json(good)
  assert_eq(cfg.window_seconds, 3600)
  assert_eq(cfg.threshold_pct, 80.0)
  assert_eq(cfg.free_models.length(), 1)
  assert_eq(cfg.paid_models.length(), 0)
  assert_true(warns.length() >= 1)

  let bad = rt_json_cfg(
    Json::number(-5.0),
    Json::number(250.0),
    Json::string("nope"),
    Json::number(1.0),
  )
  let (cfg2, warns2) = RouterConfig::from_json(bad)
  assert_eq(cfg2.window_seconds, 18000)
  assert_eq(cfg2.threshold_pct, 95.0)
  assert_eq(cfg2.free_models.length(), 8)
  assert_eq(cfg2.paid_models.length(), 4)
  assert_true(warns2.length() >= 4)

  let (cfg3, warns3) = RouterConfig::from_json(Json::number(1.0))
  assert_eq(cfg3.window_seconds, 18000)
  assert_eq(warns3.length(), 1)

  // 缺字段 ⇒ 用默认池；负 limit ⇒ 当无限并留 warning
  let miss = Json::object({
    "free_pool": Json::array([
      Json::object({ "name": Json::string("x"), "limit": Json::number(-3.0) }),
    ]),
  })
  let (cfg4, warns4) = RouterConfig::from_json(miss)
  assert_eq(cfg4.free_models.length(), 1)
  assert_eq(cfg4.free_models[0].limit, 0)
  assert_eq(cfg4.paid_models.length(), 4)
  assert_true(warns4.length() >= 1)
  assert_eq(cfg4.to_json().stringify().contains("x"), true)
}

///|
test "rt_11_usage_report 形状、占比与当前档位" {
  let r = rt_router(4, 4)
  let _ = r.record_call(model="free-a", now=rt_at(0, 1))
  let _ = r.record_call(model="paid-a", now=rt_at(0, 1))
  let j = r.usage_report()
  match j {
    Json::Object(m) => {
      assert_true(m.contains("free_pool"))
      assert_true(m.contains("total_used"))
      assert_true(m.contains("current_tier"))
      assert_true(m.contains("switch_count"))
    }
    _ => abort("usage_report 应为对象")
  }
  let txt = j.stringify()
  assert_true(txt.contains("free-a"))
  assert_true(txt.contains("paid-a"))
  assert_eq(r.usage_report().stringify() == j.stringify(), true)
}

///|
test "rt_12_手动切档：目标档可用才切，游标环形不越界" {
  let r = rt_router(3, 3)
  let d = r.force_switch(tier=Paid, now=rt_at(0, 1))
  assert_eq(d.switched, true)
  assert_eq(r.current_tier, Paid)
  assert_eq(d.model_name, "paid-a")
  let same = r.force_switch(tier=Paid, now=rt_at(0, 2))
  assert_eq(same.switched, false)
  assert_eq(r.switch_count, 1)
  // 轮询游标越界后取模回绕（空池已被 rt_4 覆盖）
  r.paid_idx = 99
  assert_true(r.current_model() is Some(_))
}

///|
test "rt_13_current_model 报真在用的模型而不是游标位（BUG-56 成对锁）" {
  let cfg = {
    window_seconds: 18000,
    threshold_pct: 95.0,
    free_models: [
      ModelQuota::new(name="free-a", tier=Free, limit=10),
      ModelQuota::new(name="free-b", tier=Free, limit=10),
    ],
    paid_models: [ModelQuota::new(name="paid-a", tier=Paid, limit=10)],
    ofm_endpoint: "",
    use_laya: false,
  }
  let r = ModelRouter::from_config(cfg)
  let d = r.pick(now=rt_at(0, 1))
  assert_eq(d.model_name, "free-a")
  let j = match r.usage_report() {
    Json::Object(m) => m
    _ => abort("usage_report 应为对象")
  }
  let g = fn(k : String) -> String {
    match j.get(k) {
      Some(Json::String(s)) => s
      _ => ""
    }
  }
  assert_eq(g("current_model"), "free-a")
  assert_eq(g("cursor_model"), "free-b")
  assert_eq(g("last_pick"), "free-a")
  // 成对：两个键必须**不同**，否则上面三条等于什么都没锁
  assert_true(g("current_model") != g("cursor_model"))
  // 没决策过的新路由器不该报空模型名：current_model 回落到游标位
  let r2 = ModelRouter::from_config(cfg)
  let j2 = match r2.usage_report() {
    Json::Object(m) => m
    _ => abort("usage_report 应为对象")
  }
  let g2 = fn(k : String) -> String {
    match j2.get(k) {
      Some(Json::String(s)) => s
      _ => ""
    }
  }
  assert_eq(g2("current_model"), "free-a")
  assert_eq(g2("last_pick"), "")
}

///|
/// BUG-65 附带：rt_12 收尾那句 `current_model() is Some(_)` 是弱断言——
/// 返回类型是 ModelQuota? ⇒ 只要返回"任意一个模型"就恒真，越界游标到底绕回哪一格没人管。
/// 这里用**双元池**钉具体名字：单元池里 `99 % 1 == 0`、`-7 % 1 == 0`，两条断言都恒过，
/// 只有池长 >1 时"取模 + 负数绕回"才是一个能被写错的具体结果。
test "rt_14_越界游标取模后 current_model 必须点名（补 rt_12 的弱断言）" {
  let r = ModelRouter::from_config({
    window_seconds: 18000,
    threshold_pct: 95.0,
    free_models: [],
    paid_models: [
      ModelQuota::new(name="paid-a", tier=Paid, limit=7),
      ModelQuota::new(name="paid-b", tier=Paid, limit=7),
    ],
    ofm_endpoint: "",
    use_laya: false,
  })
  r.current_tier = Paid
  r.paid_idx = 98 // 98 % 2 = 0
  match r.current_model() {
    Some(q) => assert_eq(q.name, "paid-a")
    None => abort("付费池非空，current_model 不该为空")
  }
  r.paid_idx = 99 // 99 % 2 = 1 ⇒ 绕回第二格
  match r.current_model() {
    Some(q) => assert_eq(q.name, "paid-b")
    None => abort("越界游标没有点名到具体模型")
  }
  // 负游标：% 与被除数同号 ⇒ -7 % 2 = -1，必须再 +len 绕回正下标（-1+2=1）
  r.paid_idx = -7
  match r.current_model() {
    Some(q) => assert_eq(q.name, "paid-b")
    None => abort("负游标下 current_model 为空")
  }
  // 越界游标先夹紧再决策，否则 99/-7 这类下标直接崩
  assert_true(r.pick(now="2026-09-27T00:00:00Z").available)
}

///|
/// rt_15 池内扫描必须真的扫（新发现 BUG-73）：pool_pick 的循环里 `idx` 只由 start_idx
/// 算出，`i` 从不参与下标 ⇒ 它把同一个格子重测 n 次，游标停在耗尽模型上时**整档判为不可用**，
/// 于是"免费池还有一个健康模型"却被切到付费档（switch_count+1、真金白银的付费配额被消耗）。
/// 修复前三条断言全红（返回 paid-a）。
test "rt_15_同档仍有健康模型时不许跳档（环形扫描要真的扫描）" {
  let cfg = {
    window_seconds: 18000,
    threshold_pct: 95.0,
    free_models: [
      ModelQuota::new(name="free-busy", tier=Free, limit=1, used=1),
      ModelQuota::new(name="free-ok", tier=Free, limit=10),
    ],
    paid_models: [ModelQuota::new(name="paid-a", tier=Paid, limit=10)],
    ofm_endpoint: "",
    use_laya: false,
  }
  let r = ModelRouter::from_config(cfg)
  r.free_idx = 0 // 游标正好停在耗尽那一格
  let d = r.pick(now=rt_at(0, 1))
  assert_eq(d.model_name, "free-ok")
  assert_eq(d.tier, Free)
  assert_eq(r.current_tier, Free)
  assert_eq(r.switch_count, 0)
  // 零回归：选中后游标仍按"下一格"推进（1+1 mod 2 = 0），轮询语义不变
  assert_eq(r.free_idx, 0)
  // 反向成对：整档真的全耗尽时才允许跳付费
  let r2 = ModelRouter::from_config({
    window_seconds: 18000,
    threshold_pct: 95.0,
    free_models: [
      ModelQuota::new(name="f1", tier=Free, limit=1, used=1),
      ModelQuota::new(name="f2", tier=Free, limit=1, used=1),
    ],
    paid_models: [ModelQuota::new(name="p1", tier=Paid, limit=10)],
    ofm_endpoint: "",
    use_laya: false,
  })
  let d2 = r2.pick(now=rt_at(0, 1))
  assert_eq(d2.model_name, "p1")
  assert_eq(r2.current_tier, Paid)
}

///|
/// rt_16 —— 「付费耗尽回退免费」分支**正向锁**（2026-10-11 终审发现此前零覆盖：grep `fallback`
/// 在 src/router 与 src/server 测试面零命中；rt_5 只锁了反向——free 也满时不许**假**回退）。
/// 场景：起点错开 1h 直接摆状态（rt_15 同款手法；**不能**靠 record 自然演化——切档选中
/// paid-a 的那一刻 pick 就给 paid-a 盖窗口起点，与 free-a 同起点永远同窗过期，首版就红在
/// `window_reset_check` 返回 2 而非 1）。rt_at(0,6) 时 free-a 距起点恰 5h（≥窗口）重置为
/// 可用、paid-a 距起点 4h（<窗口）保持耗尽 ⇒ Paid 档无可用模型而免费池已恢复，必须真的回退。
test "rt_16_付费耗尽且免费已恢复_必须回退免费" {
  let r = ModelRouter::from_config({
    window_seconds: 18000,
    threshold_pct: 95.0,
    free_models: [
      ModelQuota::new(
        name="free-a",
        tier=Free,
        limit=1,
        used=1,
        window_start=rt_at(0, 1),
      ),
    ],
    paid_models: [
      ModelQuota::new(
        name="paid-a",
        tier=Paid,
        limit=1,
        used=1,
        window_start=rt_at(0, 2),
      ),
    ],
    ofm_endpoint: "",
    use_laya: false,
  })
  r.current_tier = Paid
  // 铺垫：此刻双池皆尽 → 显式不可用，档位保持 Paid（rt_5 反向，不假回退）
  let d_ex = r.pick(now=rt_at(0, 3))
  assert_eq(d_ex.available, false)
  assert_eq(r.current_tier, Paid)
  // 6h 时点：free-a 距起点 5h（≥窗口）重置为可用（0/1），paid-a 距起点 4h（<窗口）保持耗尽
  assert_eq(r.window_reset_check(now=rt_at(0, 6)), 1)
  let d = r.pick(now=rt_at(0, 6))
  // 正向主断言：paid 耗尽 + free 有容量 ⇒ 回退免费，switched/档位/计数/reason 全对齐
  assert_eq(d.model_name, "free-a")
  assert_eq(d.tier, Free)
  assert_eq(d.switched, true)
  assert_eq(r.current_tier, Free)
  assert_eq(r.switch_count, 1) // 本例只发生 paid→free 一次切换
  assert_true(d.reason.contains("fallback to free"))
  // 回退后档位语义自洽：current_model 报真在用的 free-a（BUG-56），不是耗尽的 paid-a
  assert_eq(r.current_model().unwrap().name, "free-a")
}

///|
/// 502 健康探测：`pick` 传入黑名单时，必须跳过已知不健康的模型选下一个健康的。
test "rt_health_1_pick 跳过黑名单模型" {
  let cfg = {
    window_seconds: 18000,
    threshold_pct: 95.0,
    free_models: [
      ModelQuota::new(name="bad-502", tier=Free, limit=10),
      ModelQuota::new(name="good-1", tier=Free, limit=10),
    ],
    paid_models: [],
    ofm_endpoint: "",
    use_laya: false,
  }
  let r = ModelRouter::from_config(cfg)
  // 黑名单第一个模型 → 应选第二个
  let d = r.pick(now=rt_at(0, 1), unhealthy_ids=["bad-502"])
  assert_eq(d.available, true)
  assert_eq(d.model_name, "good-1")
  // 空黑名单 → 正常选第一个（零回归）
  let r2 = ModelRouter::from_config(cfg)
  let d2 = r2.pick(now=rt_at(0, 1), unhealthy_ids=[])
  assert_eq(d2.model_name, "bad-502")
  // 全在黑名单 → 显式不可用，不静默给空名以外的假成功
  let r3 = ModelRouter::from_config(cfg)
  let d3 = r3.pick(now=rt_at(0, 1), unhealthy_ids=["bad-502", "good-1"])
  assert_eq(d3.available, false)
  assert_eq(d3.model_name, "")
}

///|
/// 502 健康探测：精确匹配，子串/前缀不误伤。
test "rt_health_2_黑名单精确匹配不误伤前缀" {
  let cfg = {
    window_seconds: 18000,
    threshold_pct: 95.0,
    free_models: [ModelQuota::new(name="model-v1", tier=Free, limit=10)],
    paid_models: [],
    ofm_endpoint: "",
    use_laya: false,
  }
  let r = ModelRouter::from_config(cfg)
  // 黑名单是 "model"（前缀）不应命中 "model-v1"
  let d = r.pick(now=rt_at(0, 1), unhealthy_ids=["model"])
  assert_eq(d.model_name, "model-v1")
}

///|
/// P2-1：laya 提示 paid 且当前 free → 切到 paid，laya_reason 标注
test "lp_1_laya_hint_paid_switches_when_current_free" {
  let cfg = {
    window_seconds: 18000,
    threshold_pct: 95.0,
    free_models: [ModelQuota::new(name="free-a", tier=Free, limit=5)],
    paid_models: [ModelQuota::new(name="paid-a", tier=Paid, limit=5)],
    ofm_endpoint: "",
    use_laya: true,
  }
  let r = ModelRouter::from_config(cfg)
  let d = r.pick(now=rt_at(0, 1), laya_prefer_tier="Paid")
  assert_eq(d.model_name, "paid-a")
  assert_eq(d.tier, Paid)
  assert_eq(d.switched, true)
  assert_eq(d.laya_reason, "laya:paid")
  let s = d.to_json().stringify()
  assert_true(s.contains("laya:paid"))
}

///|
/// P2-2：laya 提示 free 且当前 free → 同档，标注 laya:free
test "lp_2_laya_hint_free_already_on_free" {
  let cfg = {
    window_seconds: 18000,
    threshold_pct: 95.0,
    free_models: [ModelQuota::new(name="free-a", tier=Free, limit=5)],
    paid_models: [ModelQuota::new(name="paid-a", tier=Paid, limit=5)],
    ofm_endpoint: "",
    use_laya: true,
  }
  let r = ModelRouter::from_config(cfg)
  let d = r.pick(now=rt_at(0, 1), laya_prefer_tier="Free")
  assert_eq(d.model_name, "free-a")
  assert_eq(d.tier, Free)
  assert_eq(d.switched, false)
  assert_eq(d.laya_reason, "laya:free")
}

///|
/// P2-3：laya 提示档位无容量 → 不破配额，回落正常逻辑（laya_reason 空串）
test "lp_3_laya_hint_tier_exhausted_falls_back" {
  // paid 池已耗尽（used=limit=1）→ laya 建议 paid 但无容量
  let cfg = {
    window_seconds: 18000,
    threshold_pct: 95.0,
    free_models: [ModelQuota::new(name="free-a", tier=Free, limit=5)],
    paid_models: [ModelQuota::new(name="paid-a", tier=Paid, limit=1, used=1)],
    ofm_endpoint: "",
    use_laya: true,
  }
  let r = ModelRouter::from_config(cfg)
  let d = r.pick(now=rt_at(0, 1), laya_prefer_tier="paid")
  // 回落正常逻辑：当前是 Free，free 池有容量 → 选 free-a
  assert_eq(d.model_name, "free-a")
  assert_eq(d.tier, Free)
  assert_eq(d.laya_reason, "")
}

///|
/// P2-4：laya 提示非法档位字符串 → 静默回落正常逻辑，不 panic
test "lp_4_laya_hint_invalid_tier_silent_fallback" {
  let cfg = {
    window_seconds: 18000,
    threshold_pct: 95.0,
    free_models: [ModelQuota::new(name="free-a", tier=Free, limit=5)],
    paid_models: [ModelQuota::new(name="paid-a", tier=Paid, limit=5)],
    ofm_endpoint: "",
    use_laya: true,
  }
  let r = ModelRouter::from_config(cfg)
  let d = r.pick(now=rt_at(0, 1), laya_prefer_tier="banana")
  // 非法档位：走正常逻辑，选当前档位模型
  assert_eq(d.model_name, "free-a")
  assert_eq(d.laya_reason, "")
}

///|
/// P2-5：空提示字符串 == 未提示（stringify 相等证明零回归）
test "lp_5_empty_hint_zero_regression" {
  let cfg = {
    window_seconds: 18000,
    threshold_pct: 95.0,
    free_models: [ModelQuota::new(name="free-a", tier=Free, limit=5)],
    paid_models: [ModelQuota::new(name="paid-a", tier=Paid, limit=5)],
    ofm_endpoint: "",
    use_laya: false,
  }
  let r = ModelRouter::from_config(cfg)
  let d1 = r.pick(now=rt_at(0, 1))
  let d2 = r.pick(now=rt_at(0, 1), laya_prefer_tier="")
  assert_eq(d1.to_json().stringify(), d2.to_json().stringify())
}

///|
/// P2-6：RouterConfig.use_laya 默认 false；from_json 解析 true/false/null/garbage
test "lp_6_routerconfig_uselaya_field" {
  let d = RouterConfig::default()
  assert_eq(d.use_laya, false)
  // true
  let (c1, w1) = RouterConfig::from_json(
    qj([("use_laya", Json::boolean(true))]),
  )
  assert_eq(c1.use_laya, true)
  assert_eq(w1.length(), 0)
  // false
  let (c2, w2) = RouterConfig::from_json(
    qj([("use_laya", Json::boolean(false))]),
  )
  assert_eq(c2.use_laya, false)
  assert_eq(w2.length(), 0)
  // null
  let (c3, w3) = RouterConfig::from_json(qj([("use_laya", Json::null())]))
  assert_eq(c3.use_laya, false)
  assert_eq(w3.length(), 0)
  // garbage → false + warning
  let (c4, w4) = RouterConfig::from_json(
    qj([("use_laya", Json::string("yes"))]),
  )
  assert_eq(c4.use_laya, false)
  assert_eq(w4.length(), 1)
}

///|
/// P1.3-1：cost_performance = rank/(price+1)；价格或排名未知 → 0（不参与比较）
test "cp_1_cost_performance_formula" {
  let m1 = ModelQuota::new(
    name="a",
    tier=Paid,
    limit=10,
    rank=5,
    price_per_call=1.0,
  )
  // 5 / (1.0 + 1.0) = 2.5
  assert_eq(m1.cost_performance(), 2.5)
  let m2 = ModelQuota::new(
    name="b",
    tier=Paid,
    limit=10,
    rank=9,
    price_per_call=3.0,
  )
  // 9 / (3.0 + 1.0) = 2.25 → 便宜高质 wins
  assert_eq(m2.cost_performance(), 2.25)
  // 未知价格 → 0
  let m3 = ModelQuota::new(name="c", tier=Free, limit=10, rank=5)
  assert_eq(m3.cost_performance(), 0.0)
  // 未知排名 → 0
  let m4 = ModelQuota::new(name="d", tier=Paid, limit=10, price_per_call=1.0)
  assert_eq(m4.cost_performance(), 0.0)
}

///|
/// P1.3-2：sort_by_cost_performance 同 tier 内按性价比降序
test "cp_2_sort_by_cost_performance" {
  let a = ModelQuota::new(
    name="cheap-good",
    tier=Paid,
    limit=10,
    rank=5,
    price_per_call=1.0,
  )
  let b = ModelQuota::new(
    name="pricey-good",
    tier=Paid,
    limit=10,
    rank=9,
    price_per_call=3.0,
  )
  let c = ModelQuota::new(
    name="mid",
    tier=Paid,
    limit=10,
    rank=4,
    price_per_call=2.0,
  )
  let pool = [b, a, c]
  let sorted = sort_pool_copy(pool)
  assert_eq(sorted[0].name, "cheap-good")
  assert_eq(sorted[1].name, "pricey-good")
  assert_eq(sorted[2].name, "mid")
}

///|
/// P1.1-1：compute_fallback_chain 同档位→另一档位，过滤主选/耗尽/unhealthy
test "fc_1_compute_fallback_chain" {
  let cfg = {
    window_seconds: 18000,
    threshold_pct: 95.0,
    free_models: [
      ModelQuota::new(name="free-a", tier=Free, limit=5),
      ModelQuota::new(name="free-b", tier=Free, limit=1, used=1),
    ],
    paid_models: [
      ModelQuota::new(
        name="paid-a",
        tier=Paid,
        limit=5,
        rank=5,
        price_per_call=1.0,
      ),
      ModelQuota::new(
        name="paid-b",
        tier=Paid,
        limit=5,
        rank=9,
        price_per_call=3.0,
      ),
    ],
    ofm_endpoint: "",
    use_laya: false,
  }
  // 主选 = free-a；free-b 已耗尽 → 链 = paid-a(2.5) > paid-b(2.25)
  let chain = compute_fallback_chain(cfg, "free-a")
  assert_eq(chain.length(), 2)
  assert_eq(chain[0], "paid-a")
  assert_eq(chain[1], "paid-b")
}

///|
/// P1.1-2：pick 回执带 fallback_chain，含主选被过滤
test "fc_2_route_decision_has_fallback_chain" {
  let cfg = {
    window_seconds: 18000,
    threshold_pct: 95.0,
    free_models: [
      ModelQuota::new(name="free-a", tier=Free, limit=5),
      ModelQuota::new(name="free-b", tier=Free, limit=5),
    ],
    paid_models: [ModelQuota::new(name="paid-a", tier=Paid, limit=5)],
    ofm_endpoint: "",
    use_laya: false,
  }
  let r = ModelRouter::from_config(cfg)
  let d = r.pick(now=rt_at(0, 1))
  assert_eq(d.model_name, "free-a")
  // 备用链 = 同档位 free-b + 另一档位 paid-a
  assert_eq(d.fallback_chain.length(), 2)
  assert_eq(d.fallback_chain[0], "free-b")
  assert_eq(d.fallback_chain[1], "paid-a")
  let s = d.to_json().stringify()
  assert_true(s.contains("free-b"))
}

///|
/// P1.1-3：unhealthy 黑名单从 fallback_chain 中剔除
test "fc_3_fallback_chain_filters_unhealthy" {
  let cfg = {
    window_seconds: 18000,
    threshold_pct: 95.0,
    free_models: [
      ModelQuota::new(name="free-a", tier=Free, limit=5),
      ModelQuota::new(name="free-b", tier=Free, limit=5),
    ],
    paid_models: [],
    ofm_endpoint: "",
    use_laya: false,
  }
  let chain = compute_fallback_chain(cfg, "free-a", unhealthy_ids=["free-b"])
  assert_eq(chain.length(), 0)
}
