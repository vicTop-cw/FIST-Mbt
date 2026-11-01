/// router_state.mbt —— 路由状态的序列化与恢复（schema 归本包所有）
///
/// 为什么放在 router 包而不是 server 包：MoonBit 里跨包**不能改 mut 字段、也不能用记录字面量
/// 构造他包类型**。把"状态 ↔ 对象"的映射放在类型定义包内，IO 层（src/server）只负责读文件/写文件，
/// 这样状态 schema 的真源与类型的真源是同一处（一源四态 r2）。
///
/// 状态 JSON schema v1：
/// { schema:1, current_tier:"free"|"paid", free_idx, paid_idx, switch_count,
///   last_switch_at, last_reason, last_pick, window_seconds, threshold_pct,
///   free_pool:[{name,limit,used,window_start}], paid_pool:[{...}] }

///|
/// 序列化为可落盘的状态（不含任何密钥）
pub fn ModelRouter::to_state(self : ModelRouter) -> Json {
  let cfg = self.config
  Json::object({
    "schema": Json::number(1.0),
    "current_tier": Json::string(self.current_tier.to_string()),
    "free_idx": Json::number(self.free_idx.to_double()),
    "paid_idx": Json::number(self.paid_idx.to_double()),
    "switch_count": Json::number(self.switch_count.to_double()),
    "last_switch_at": Json::string(self.last_switch_at),
    "last_reason": Json::string(self.last_reason),
    "last_pick": Json::string(self.last_pick),
    "window_seconds": Json::number(cfg.window_seconds.to_double()),
    "threshold_pct": Json::number(cfg.threshold_pct),
    "free_pool": Json::array(cfg.free_models.map(fn(m) { m.to_json() })),
    "paid_pool": Json::array(cfg.paid_models.map(fn(m) { m.to_json() })),
  })
}

///|
fn st_str(m : Map[String, Json], key : String) -> String {
  match m.get(key) {
    Some(Json::String(s)) => s
    _ => ""
  }
}

///|
/// JSON Number → Int 的读取（BUG-192：越界/NaN 不 panic，回落到默认）。
fn st_int(m : Map[String, Json], key : String, default~ : Int32) -> Int32 {
  match m.get(key) {
    Some(Json::Number(n, ..)) =>
      if n != n || n < -2_000_000_000.0 || n > 2_000_000_000.0 {
        default
      } else {
        n.to_int()
      }
    _ => default
  }
}

///|
fn st_float(m : Map[String, Json], key : String, default~ : Double) -> Double {
  match m.get(key) {
    Some(Json::Number(n, ..)) => n
    _ => default
  }
}

///|
/// 池数组 → ModelQuota 列表。坏条目跳过并留 warning（坏状态不该让整份读废，但也不许静默）。
fn st_pool(j : Json?, tier : ModelTier) -> (Array[ModelQuota], Array[String]) {
  let mut out : Array[ModelQuota] = []
  let mut warns : Array[String] = []
  match j {
    None => warns = warns + ["缺池字段，回落配置池"]
    Some(Json::Array(arr)) =>
      for item in arr {
        match item {
          Json::Object(m) => {
            let name = st_str(m, "name")
            if name.is_empty() {
              warns = warns + ["池内有条目缺 name，已跳过"]
            } else {
              let limit = st_int(m, "limit", default=0)
              let used = st_int(m, "used", default=0)
              out = out +
                [
                  ModelQuota::new(
                    name~,
                    tier~,
                    limit=if limit < 0 { 0 } else { limit },
                    used~,
                    window_start=st_str(m, "window_start"),
                    lane=st_str(m, "lane"),
                    cooldown_until=st_str(m, "cooldown_until"),
                  ),
                ]
            }
          }
          _ => warns = warns + ["池内有条目不是对象，已跳过"]
        }
      }
    Some(_) => warns = warns + ["池字段不是数组，回落配置池"]
  }
  (out, warns)
}

///|
/// 以 config 定义的池为准，沿用 prev 里同名模型的已用配额与窗口起点。
fn merge_usage(
  defs : Array[ModelQuota],
  prev : Array[ModelQuota],
) -> Array[ModelQuota] {
  let mut out : Array[ModelQuota] = []
  for d in defs {
    let mut u = 0
    let mut w = ""
    let mut c = ""
    for p in prev {
      if p.name == d.name {
        u = p.used
        w = p.window_start
        c = p.cooldown_until
      }
    }
    out = out +
      [
        ModelQuota::new(
          name=d.name,
          tier=d.tier,
          limit=d.limit,
          used=u,
          window_start=w,
          // lane 属**定义**（渠道归属），不是用量——必须跟着 config 定义走，
          // 不能沿用 prev（改了渠道就该按新渠道算，否则用量会记到旧渠道头上）。
          lane=d.lane,
          cooldown_until=c,
        ),
      ]
  }
  out
}

///|
/// 从「磁盘状态 + 调用方 config」恢复路由器。
/// - config 显式给池 ⇒ 池定义以 config 为准，同名模型沿用状态里的用量（改定义 ≠ 清零）
/// - 否则 ⇒ 状态里的池优先（它带着真实用量），config 只补 window_seconds/threshold 等缺项
/// - 状态非法/缺失 ⇒ 用 config（或默认）重建，并保留旧文件不删
pub fn router_restore(
  state : Json,
  config~ : Json = Json::null(),
) -> (ModelRouter, Array[String]) {
  let (cfg, mut_warns) = RouterConfig::from_json(config)
  let mut warns = mut_warns
  let cfg_gives_pools = match config {
    Json::Object(cm) => cm.contains("free_pool") || cm.contains("paid_pool")
    _ => false
  }
  let sm : Map[String, Json] = match state {
    Json::Object(m) => m
    _ => Map([])
  }
  let has_state = match state {
    Json::Object(_) => true
    _ => false
  }
  if !has_state {
    warns = warns + ["无有效状态，按配置新建路由器"]
    return (ModelRouter::from_config(cfg), warns)
  }
  let (sf, w1) = st_pool(sm.get("free_pool"), Free)
  let (sp, w2) = st_pool(sm.get("paid_pool"), Paid)
  warns = warns + w1 + w2
  // 标量件也要"兜底且不静默"：静默回落会让一份坏状态看起来像正常状态
  let ws_raw = st_int(sm, "window_seconds", default=cfg.window_seconds)
  let ws = if ws_raw > 0 {
    ws_raw
  } else {
    if ws_raw != cfg.window_seconds {
      warns = warns +
        [
          "window_seconds=\{ws_raw} 非法（必须 >0），回落 \{cfg.window_seconds}",
        ]
    }
    cfg.window_seconds
  }
  let tp_raw = st_float(sm, "threshold_pct", default=cfg.threshold_pct)
  let tp = if tp_raw > 0.0 && tp_raw <= 100.0 {
    tp_raw
  } else {
    if tp_raw != cfg.threshold_pct {
      warns = warns +
        [
          "threshold_pct=\{tp_raw} 非法（须在 (0,100]），回落 \{cfg.threshold_pct}",
        ]
    }
    cfg.threshold_pct
  }
  // 区分「state 里缺字段/非数组」与「state 里有显式数组（含空数组）」：前者回落配置
  // （旧状态兼容 + 坏状态兜底），后者保留实效值（to_state 序列化的空数组必须逐字读回，
  // 否则 b530_1 锁假绿；但字符串"nope"等非数组仍要走 rs_3 的回落配置路径）。
  let base_free = match sm.get("free_pool") {
    Some(Json::Array(_)) => sf
    _ => cfg.free_models
  }
  let base_paid = match sm.get("paid_pool") {
    Some(Json::Array(_)) => sp
    _ => cfg.paid_models
  }
  let (final_free, final_paid) = if cfg_gives_pools {
    warns = warns + ["config 覆盖池定义，同名模型已用配额保留"]
    (
      merge_usage(cfg.free_models, base_free),
      merge_usage(cfg.paid_models, base_paid),
    )
  } else {
    (base_free, base_paid)
  }
  let merged : RouterConfig = {
    window_seconds: ws,
    threshold_pct: tp,
    free_models: final_free,
    paid_models: final_paid,
    // 端点属部署环境配置，不随用量状态走：一律以调用方 config 为准（状态文件里不存端点）。
    ofm_endpoint: cfg.ofm_endpoint,
    use_laya: cfg.use_laya,
    use_caf_memory: cfg.use_caf_memory,
    caf_default_preference: cfg.caf_default_preference,
    caf_min_evidences: cfg.caf_min_evidences,
  }
  let r = ModelRouter::from_config(merged)
  let tier_str = st_str(sm, "current_tier")
  r.current_tier = match ModelTier::from_string(tier_str) {
    Some(t) => t
    None => {
      if !tier_str.is_empty() {
        warns = warns +
          [
            "current_tier='\{tier_str}' 未知档位，回落 free（不会静默当作正常）",
          ]
      }
      Free
    }
  }
  // 越界游标必须夹紧：pick 取 (idx + i) % n，负数取模得负下标 ⇒ 直接 panic
  let free_len = final_free.length()
  let paid_len = final_paid.length()
  let fi = st_int(sm, "free_idx", default=0)
  r.free_idx = if fi >= 0 && (fi < free_len || free_len == 0) {
    fi
  } else {
    warns = warns +
      [
        "free_idx=\{fi} 越界（免费池长 \{free_len}），已夹紧到 0——越界游标取模后会落到负下标",
      ]
    0
  }
  let pi = st_int(sm, "paid_idx", default=0)
  r.paid_idx = if pi >= 0 && (pi < paid_len || paid_len == 0) {
    pi
  } else {
    warns = warns +
      ["paid_idx=\{pi} 越界（付费池长 \{paid_len}），已夹紧到 0"]
    0
  }
  r.switch_count = st_int(sm, "switch_count", default=0)
  r.last_switch_at = st_str(sm, "last_switch_at")
  r.last_reason = st_str(sm, "last_reason")
  r.last_pick = st_str(sm, "last_pick")
  (r, warns)
}

///|
/// 清窗口：所有模型 used/window_start 归零（档位与游标保持）。
pub fn ModelRouter::reset_windows(self : ModelRouter) -> Unit {
  for pool in [self.config.free_models, self.config.paid_models] {
    for m in pool {
      m.used = 0
      m.window_start = ""
      m.cooldown_until = ""
    }
  }
}

///|
/// 硬复位：档位回 Free、游标回 0、切换计数归零，窗口同样清空。
pub fn ModelRouter::hard_reset(self : ModelRouter) -> Unit {
  self.reset_windows()
  self.current_tier = Free
  self.free_idx = 0
  self.paid_idx = 0
  self.switch_count = 0
  self.last_switch_at = ""
  self.last_reason = ""
  self.last_pick = ""
}

// ---------------------------------------------------------------------------
// BUG-530 回归锁：播种池定义「落盘 → 读回」的往返契约（test 块不进产物）
//
// BUG-530 实测形状（2026-10-31，ns=ofm-route-r1）：`model_route(config_json=…)` 回执
// 声称「已按 config_json 播种池定义」但 `persisted=false`，`model_router_status` 读回
// `free_pool: []`。本文件把链路的 src/router 半边钉死：池定义经 router_restore(config~)
// 播种进 ModelRouter，经 to_state()（= server mr_save 落盘的那份 JSON）再
// router_restore(state)（= model_router_status 的读回路径），池形状必须逐字一致，
// 路由决策只能取播种池内的模型。池名刻意用 provider/model 形状（与 relay 命名要求同形），
// 不用默认池的 ling-3.1-flash-free。
// ---------------------------------------------------------------------------

///|
/// 锁一（播种 → status 读回同池）：播种后的状态 JSON 经无 config 的 router_restore
/// 读回，模型名/限额/阈值/用量与播种时逐字一致，读回零告警
/// （`free_pool: []` 形状的静默丢池在此变红）。
test "b530_1_播种后按 status 读回路径还原出同池同名同限同阈值" {
  let cfg : Json = Json::object({
    "window_seconds": Json::number(18000.0),
    "threshold_pct": Json::number(90.0),
    "free_pool": Json::array([
      Json::object({
        "name": Json::string("our-free-model/deepseek-v4.1-flash-free"),
        "limit": Json::number(7.0),
      }),
    ]),
    "paid_pool": Json::array([]),
  })
  let (r0, w0) = router_restore(Json::null(), config=cfg)
  // 注：w0 含"无有效状态，按配置新建路由器"是运行时信息（state 级别），不是配置校验警告。
  // b530_1 回归锁只验"池还原零漂移"，不验 warns 计数——否则与 from_json 校验重复且恒假。
  // 配置校验警告面由 model_router_ops_wbtest 的 mo_4 格覆盖（window_seconds/threshold_pct）。
  assert_eq(r0.config.free_models.length(), 1)
  assert_eq(
    r0.config.free_models[0].name,
    "our-free-model/deepseek-v4.1-flash-free",
  )
  assert_eq(r0.config.free_models[0].limit, 7)
  assert_eq(r0.config.free_models[0].used, 0)
  assert_eq(r0.config.threshold_pct, 90.0)
  // server 落盘 ↔ status 读回：同一份 JSON，无 config（status 不带 config_json）
  let state = r0.to_state()
  let (r1, w1) = router_restore(state)
  assert_eq(w1.length(), 0)
  assert_eq(r1.config.free_models.length(), 1)
  assert_eq(
    r1.config.free_models[0].name,
    "our-free-model/deepseek-v4.1-flash-free",
  )
  assert_eq(r1.config.free_models[0].limit, 7)
  assert_eq(r1.config.free_models[0].used, 0)
  assert_eq(r1.config.threshold_pct, 90.0)
  assert_eq(r1.config.paid_models.length(), 0)
}

///|
/// 锁二（播种 → 路由决策取播种池内模型）：播种池经「落盘→读回」后，pick 只能选出
/// 播种池内的 provider/model 形状模型（默认池的 ling-3.1-flash-free 在此出现即红）；
/// 且记账（executor_run 自动那一笔，不带 config）后再次读回，用量跟播种池走。
test "b530_2_播种后路由决策与记账都落在播种池内模型上" {
  let cfg : Json = Json::object({
    "window_seconds": Json::number(18000.0),
    "threshold_pct": Json::number(90.0),
    "free_pool": Json::array([
      Json::object({
        "name": Json::string("trae/glm-5.3-flash-free"),
        "limit": Json::number(7.0),
      }),
    ]),
    "paid_pool": Json::array([]),
  })
  let (r0, _) = router_restore(Json::null(), config=cfg)
  let state = r0.to_state()
  let (r1, _) = router_restore(state)
  let dec = r1.pick(now="2026-10-31T14:00:00Z")
  assert_eq(dec.available, true)
  assert_eq(dec.model_name, "trae/glm-5.3-flash-free")
  // executor_run 自动记账那一笔（不带 config）：模型在播种池内 → 记上账
  let rec = r1.record_call(
    model="trae/glm-5.3-flash-free",
    now="2026-10-31T14:01:00Z",
  )
  assert_eq(rec.available, true)
  let state2 = r1.to_state()
  let (r2, w2) = router_restore(state2)
  assert_eq(w2.length(), 0)
  assert_eq(r2.config.free_models[0].used, 1)
  // limit=7 ⇒ 1/7≈14% 未越 90% 阈值，仍在免费档
  assert_eq(r2.current_tier, Free)
}
