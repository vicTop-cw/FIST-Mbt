/// soldier_route_wbtest.mbt —— §8.3「兵种/池标签 ↔ model_route 池档位」联动白盒锁
///
/// 覆盖：池标签 → 档位提示的纯函数映射；`pick(soldier_label=…)` 软性提示命中/回落；
/// 空标签零回归；提示档位无容量时的回落不破硬约束。
/// 兵种只是展示层标签，此处只消费池标签字符串，协议与存储零改动。

///|
/// 造一个可控路由器：free 1 个 limit=FL、paid 1 个 limit=PL
fn sr_router(free_limit : Int, paid_limit : Int) -> ModelRouter {
  let cfg = {
    window_seconds: 18000,
    threshold_pct: 95.0,
    free_models: [ModelQuota::new(name="free-a", tier=Free, limit=free_limit)],
    paid_models: [ModelQuota::new(name="paid-a", tier=Paid, limit=paid_limit)],
    ofm_endpoint: "",
    use_laya: false,
    use_caf_memory: false,
    caf_default_preference: [],
    caf_min_evidences: 10,
  }
  ModelRouter::from_config(cfg)
}

///|
fn sr_now() -> String {
  secs_to_iso(1790000000)
}

///|
test "sr_1_池标签 → 档位提示映射（paid-* 付费、其余免费）" {
  assert_eq(pool_label_tier_hint("paid-premium"), "paid")
  assert_eq(pool_label_tier_hint("paid-flagship"), "paid")
  assert_eq(pool_label_tier_hint("Paid-X"), "paid")
  assert_eq(pool_label_tier_hint("特种兵"), "paid")
  assert_eq(pool_label_tier_hint("炮兵"), "paid")
  assert_eq(pool_label_tier_hint("free-fast"), "free")
  assert_eq(pool_label_tier_hint("free-general"), "free")
  assert_eq(pool_label_tier_hint("free-mid"), "free")
  assert_eq(pool_label_tier_hint("工兵"), "free")
  assert_eq(pool_label_tier_hint(""), "free")
  assert_eq(pool_label_tier_hint("未知标签"), "free")
}

///|
test "sr_2_兵种理由文案覆盖 8 兵种 + 未知回退" {
  assert_eq(soldier_label_reason("特种兵").has_prefix("特种兵"), true)
  assert_eq(soldier_label_reason("炮兵").has_prefix("炮兵"), true)
  assert_eq(soldier_label_reason("侦查兵").has_prefix("侦查兵"), true)
  assert_eq(soldier_label_reason("骑兵").has_prefix("骑兵"), true)
  assert_eq(soldier_label_reason("通信兵").has_prefix("通信兵"), true)
  assert_eq(soldier_label_reason("医疗兵").has_prefix("医疗兵"), true)
  assert_eq(soldier_label_reason("后勤兵").has_prefix("后勤兵"), true)
  assert_eq(soldier_label_reason("工兵").has_prefix("工兵"), true)
  assert_eq(soldier_label_reason("某未知").has_prefix("通用"), true)
}

///|
test "sr_3_特种兵提示命中付费池（有容量）" {
  let r = sr_router(10, 10)
  let d = r.pick(now=sr_now(), soldier_label="特种兵")
  assert_eq(d.available, true)
  assert_eq(d.model_name, "paid-a")
  assert_eq(d.tier, Paid)
  assert_eq(d.laya_reason, "soldier:特种兵")
  assert_eq(d.reason.contains("soldier"), true)
  assert_eq(d.switched, true) // 初始 current_tier=Free → 切到 Paid
}

///|
test "sr_4_通信兵提示命中免费池" {
  let r = sr_router(10, 10)
  let d = r.pick(now=sr_now(), soldier_label="通信兵")
  assert_eq(d.available, true)
  assert_eq(d.model_name, "free-a")
  assert_eq(d.tier, Free)
  assert_eq(d.laya_reason, "soldier:通信兵")
  assert_eq(d.switched, false)
}

///|
test "sr_5_空 soldier_label 零回归（与无提示一致）" {
  let r1 = sr_router(10, 10)
  let a = r1.pick(now=sr_now(), soldier_label="")
  let r2 = sr_router(10, 10)
  let b = r2.pick(now=sr_now())
  assert_eq(a.model_name, b.model_name)
  assert_eq(a.tier, b.tier)
  assert_eq(a.reason, b.reason)
  assert_eq(a.laya_reason, "")
  assert_eq(a.switched, b.switched)
}

///|
test "sr_6_提示档位无容量 → 回落正常逻辑，不破硬约束" {
  // 付费池 limit=1/used=1 → exhausted；特种兵想走付费但只能回落免费。
  let cfg = {
    window_seconds: 18000,
    threshold_pct: 95.0,
    free_models: [ModelQuota::new(name="free-a", tier=Free, limit=10)],
    paid_models: [ModelQuota::new(name="paid-a", tier=Paid, limit=1, used=1)],
    ofm_endpoint: "",
    use_laya: false,
    use_caf_memory: false,
    caf_default_preference: [],
    caf_min_evidences: 10,
  }
  let r = ModelRouter::from_config(cfg)
  let d = r.pick(now=sr_now(), soldier_label="特种兵")
  assert_eq(d.available, true) // 绝不静默失败
  assert_eq(d.model_name, "free-a")
  assert_eq(d.tier, Free)
  assert_eq(d.laya_reason, "") // 提示未生效，回落正常逻辑
}

///|
test "sr_7_当前档已是提示档 → 不虚增 switch_count" {
  let r = sr_router(10, 10)
  // 先按默认走到 Free（初始 tier=Free，first pick 无切换）
  let _d0 = r.pick(now=sr_now())
  let sw_before = r.switch_count
  let d = r.pick(now=sr_now(), soldier_label="通信兵") // 提示 free，与当前一致
  assert_eq(d.tier, Free)
  assert_eq(d.switched, false)
  assert_eq(r.switch_count, sw_before)
}
