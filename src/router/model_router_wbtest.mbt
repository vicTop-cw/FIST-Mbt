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
  assert_eq(cfg2.free_models.length(), 2)
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
  })
  let d2 = r2.pick(now=rt_at(0, 1))
  assert_eq(d2.model_name, "p1")
  assert_eq(r2.current_tier, Paid)
}
