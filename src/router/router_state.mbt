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
fn st_int(m : Map[String, Json], key : String, default~ : Int) -> Int {
  match m.get(key) {
    Some(Json::Number(n, ..)) => n.to_int()
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
    for p in prev {
      if p.name == d.name {
        u = p.used
        w = p.window_start
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
  config? : Json = Json::null(),
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
  let base_free = if sf.length() == 0 { cfg.free_models } else { sf }
  let base_paid = if sp.length() == 0 { cfg.paid_models } else { sp }
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
