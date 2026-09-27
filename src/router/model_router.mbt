/// model_router.mbt —— 模型路由核心（合并自兄弟项目 fist-model-router v0.1.0）
///
/// 语义：免费优先 + 达阈值(默认 95%)自动切付费 + 付费耗尽切回免费 + 每模型独立 5h 滚动窗口。
///
/// 与源项目的三处**有意差异**（不是随手改，是本轮合并的裁决）：
///   1. 时钟不在这里注入：本文件的纯逻辑接受 `now` 字符串参数，由 `src/server` 用
///      `now_default()` 服务端盖章（对齐 BUG-33「不接受调用方注入 now」政策）。
///   2. 时间戳↔秒改用 civil-days 精确算法：源项目用「365 天固定年 + 每月 31 天」近似，
///      跨月/闰年会把窗口过期判定偏移到错误的时间（见 BUG-52）。
///   3. 空池不再越界取 `[0]`：源项目 `current_model()` 在池为空时索引 panic（BUG-53）。
///
/// 纯计算、零 IO、无绝对路径、无 API key——配额数字来自配置，绝不硬编码密钥。

///|
/// 模型档位：免费池 / 付费池
pub enum ModelTier {
  Free
  Paid
} derive(Eq, Debug)

///|
pub fn ModelTier::to_string(self : ModelTier) -> String {
  match self {
    Free => "free"
    Paid => "paid"
  }
}

///|
/// 未知字符串 → None（调用方必须显式处理，不得静默当免费档）
pub fn ModelTier::from_string(s : String) -> ModelTier? {
  match s.trim() {
    "free" => Some(Free)
    "paid" => Some(Paid)
    _ => None
  }
}

///|
/// 单模型配额追踪（limit<=0 表示无限配额）
pub struct ModelQuota {
  name : String
  tier : ModelTier
  limit : Int
  mut used : Int
  mut window_start : String
} derive(Eq, Debug)

///|
pub fn ModelQuota::new(
  name~ : String,
  tier~ : ModelTier,
  limit? : Int = 0,
  used? : Int = 0,
  window_start? : String = "",
) -> ModelQuota {
  // used/window_start 作为构造参数而非"建完再改"：跨包不得改 mut 字段（MoonBit 只允许
  // 定义包内改），状态恢复必须能在 src/server 里做，所以把入口做成构造函数。
  let u = if used < 0 { 0 } else { used }
  { name, tier, limit, used: u, window_start, }
}

///|
/// 剩余配额。无限配额返回 -1（而不是源项目的 999999 魔数——调用方无法区分"很多"与"无限"）
pub fn ModelQuota::remaining(self : ModelQuota) -> Int {
  if self.limit <= 0 {
    -1
  } else {
    let r = self.limit - self.used
    if r < 0 {
      0
    } else {
      r
    }
  }
}

///|
pub fn ModelQuota::usage_pct(self : ModelQuota) -> Double {
  if self.limit <= 0 {
    0.0
  } else {
    self.used.to_double() * 100.0 / self.limit.to_double()
  }
}

///|
pub fn ModelQuota::is_exhausted(self : ModelQuota) -> Bool {
  if self.limit <= 0 {
    false
  } else {
    self.used >= self.limit
  }
}

///|
pub fn ModelQuota::to_json(self : ModelQuota) -> Json {
  Json::object({
    "name": Json::string(self.name),
    "tier": Json::string(self.tier.to_string()),
    "used": Json::number(self.used.to_double()),
    "limit": Json::number(self.limit.to_double()),
    "remaining": Json::number(self.remaining().to_double()),
    "usage_pct": Json::number(self.usage_pct()),
    "exhausted": Json::boolean(self.is_exhausted()),
    "window_start": Json::string(self.window_start),
  })
}

///|
/// 路由配置（窗口长度 / 切换阈值 / 两个模型池）
pub struct RouterConfig {
  window_seconds : Int
  threshold_pct : Double
  free_models : Array[ModelQuota]
  paid_models : Array[ModelQuota]
} derive(Eq, Debug)

///|
/// 默认配置：与源项目 config/fist-model-router.json 同形的**样例默认值**（不含任何密钥）。
/// 真实部署请用 `model_router_config` 覆盖池与限额。
pub fn RouterConfig::default() -> RouterConfig {
  let free = [
    ModelQuota::new(name="AtomGit-qwen3.8-27b", tier=Free, limit=100),
    ModelQuota::new(name="AtomGit-glm5.3-flash", tier=Free, limit=100),
  ]
  let paid = [
    ModelQuota::new(name="longcat/LongCat-2.0", tier=Paid, limit=50),
    ModelQuota::new(name="deepseek/deepseek-v4-pro", tier=Paid, limit=50),
    ModelQuota::new(name="Kimi/kimi-k3", tier=Paid, limit=50),
    ModelQuota::new(name="Doubao/doubao-seed-2-1-pro", tier=Paid, limit=50),
  ]
  {
    window_seconds: 18000,
    threshold_pct: 95.0,
    free_models: free,
    paid_models: paid,
  }
}

///|
/// 路由决策结果
pub struct RouteDecision {
  model_name : String
  tier : ModelTier
  reason : String
  switched : Bool
  next_switch_at : String
  available : Bool
} derive(Eq, Debug)

///|
pub fn RouteDecision::to_json(self : RouteDecision) -> Json {
  Json::object({
    "model": Json::string(self.model_name),
    "tier": Json::string(self.tier.to_string()),
    "reason": Json::string(self.reason),
    "switched": Json::boolean(self.switched),
    "available": Json::boolean(self.available),
    "next_switch_at": Json::string(self.next_switch_at),
  })
}

// ---------------------------------------------------------------------------
// 时间戳：ISO8601(UTC) ↔ epoch 秒，civil-days 精确算法（无内置时钟，纯函数）
// ---------------------------------------------------------------------------

///|
/// 从 civil 日期到 epoch 天的精确换算（Howard Hinnant days_from_civil）
fn days_from_civil(y : Int, m : Int, d : Int) -> Int {
  let yy = if m <= 2 { y - 1 } else { y }
  let era = (if yy >= 0 { yy } else { yy - 399 }) / 400
  let yoe = yy - era * 400
  let mp = (m + 9) % 12
  let doy = (153 * mp + 2) / 5 + d - 1
  let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
  era * 146097 + doe - 719468
}

///|
/// epoch 天到 civil 日期（inverse）
fn civil_from_days(z : Int) -> (Int, Int, Int) {
  let z2 = z + 719468
  let era = (if z2 >= 0 { z2 } else { z2 - 146096 }) / 146097
  let doe = z2 - era * 146097
  let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  let yy = yoe + era * 400
  let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
  let mp = (5 * doy + 2) / 153
  let d = doy - (153 * mp + 2) / 5 + 1
  let m = if mp < 10 { mp + 3 } else { mp - 9 }
  let y = if m <= 2 { yy + 1 } else { yy }
  (y, m, d)
}

///|
fn two(v : Int) -> String {
  let d1 = v / 10
  let d2 = v % 10
  "\{d1}\{d2}"
}

///|
/// ISO8601 → epoch 秒；非法/越界/缺位一律返回 -1（调用方必须显式处理，不得当作 0 秒）
pub fn iso_to_secs(s : String) -> Int {
  let cs = s.to_array()
  // 最少 "YYYY-MM-DDThh:mm:ss" = 19 个字符
  if cs.length() < 19 {
    return -1
  }
  let mut dig : Array[Int] = []
  for c in cs {
    let o = c.to_int() - 48
    let v = if o >= 0 && o <= 9 { o } else { -1 }
    dig = dig + [v]
  }
  let digit_idx = [0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18]
  let mut bad_digit = false
  for k in digit_idx {
    if dig[k] < 0 {
      bad_digit = true
    }
  }
  if bad_digit {
    return -1
  }
  // 分隔符必须"非数字"，且形状必须是 - - T : : （用显式 String 绑定，避免 StringView/String 混比）
  let dash : Char = '-'
  let colon : Char = ':'
  let t_up : Char = 'T'
  let t_lo : Char = 't'
  let sep_ok = cs[4] == dash &&
    cs[7] == dash &&
    (cs[10] == t_up || cs[10] == t_lo) &&
    cs[13] == colon &&
    cs[16] == colon
  if !sep_ok {
    return -1
  }
  let y = dig[0] * 1000 + dig[1] * 100 + dig[2] * 10 + dig[3]
  let mo = dig[5] * 10 + dig[6]
  let d = dig[8] * 10 + dig[9]
  let h = dig[11] * 10 + dig[12]
  let mi = dig[14] * 10 + dig[15]
  let sec = dig[17] * 10 + dig[18]
  if y < 1970 || y > 9999 || mo < 1 || mo > 12 || d < 1 || d > 31 {
    return -1
  }
  if h > 23 || mi > 59 || sec > 60 {
    return -1
  }
  days_from_civil(y, mo, d) * 86400 + h * 3600 + mi * 60 + sec
}

///|
/// epoch 秒 → ISO8601(UTC)；负秒返回 ""（源项目会产出错误日期）
pub fn secs_to_iso(secs : Int) -> String {
  if secs < 0 {
    return ""
  }
  let days = secs / 86400
  let rem = secs % 86400
  let (y, m, d) = civil_from_days(days)
  let h = rem / 3600
  let mi = rem % 3600 / 60
  let s = rem % 60
  let y4 = if y < 1000 { "0" + y.to_string() } else { y.to_string() }
  "\{y4}-\{two(m)}-\{two(d)}T\{two(h)}:\{two(mi)}:\{two(s)}Z"
}

///|
/// 池内第一个可用模型下标（环形扫描：未达阈值且未耗尽）；空池/全不可用 → None
fn pool_pick(
  pool : Array[ModelQuota],
  start_idx : Int,
  threshold : Double,
) -> Int? {
  let n = pool.length()
  if n == 0 {
    return None
  }
  let mut i = 0
  while i < n {
    // BUG-73：下标必须随 i 走（(start_idx + i)），旧式 `(start_idx % n + n) % n` 把同一个
    // 格子重测 n 次 —— 游标停在耗尽模型上时整档被判不可用，于是"免费池还有健康模型"
    // 却切到付费档（白花钱 + switch_count 假增长）。负数绕回仍要保留（% 与被除数同号）。
    let idx = ((start_idx + i) % n + n) % n
    let m = pool[idx]
    if m.usage_pct() < threshold && !m.is_exhausted() {
      return Some(idx)
    }
    i = i + 1
  }
  None
}

///|
/// 模型路由器（档位状态机 + 池内轮询游标）
pub struct ModelRouter {
  config : RouterConfig
  mut free_idx : Int
  mut paid_idx : Int
  mut current_tier : ModelTier
  mut switch_count : Int
  mut last_switch_at : String
  mut last_reason : String
  // 本次真正选中/使用的模型名（BUG-56：游标 free_idx/paid_idx 指向的是**下一个**候选，
  // 不能拿它当"当前模型"报给调用方，否则同一响应里 decision.model 与 usage.current_model 自相矛盾）
  mut last_pick : String
} derive(Eq, Debug)

///|
pub fn ModelRouter::from_config(config : RouterConfig) -> ModelRouter {
  {
    config,
    free_idx: 0,
    paid_idx: 0,
    current_tier: Free,
    switch_count: 0,
    last_switch_at: "",
    last_reason: "",
    last_pick: "",
  }
}

///|
pub fn ModelRouter::new() -> ModelRouter {
  ModelRouter::from_config(RouterConfig::default())
}

///|
/// 当前档位的池（空池返回空数组，不 panic）
pub fn ModelRouter::active_pool(self : ModelRouter) -> Array[ModelQuota] {
  match self.current_tier {
    Free => self.config.free_models
    Paid => self.config.paid_models
  }
}

///|
/// 当前活跃模型；池为空 → None（源项目在此处越界索引 ⇒ panic）
pub fn ModelRouter::current_model(self : ModelRouter) -> ModelQuota? {
  let pool = self.active_pool()
  let idx = match self.current_tier {
    Free => self.free_idx
    Paid => self.paid_idx
  }
  if pool.length() == 0 {
    None
  } else {
    Some(pool[(idx % pool.length() + pool.length()) % pool.length()])
  }
}

///|
/// 每模型独立窗口过期重置；返回被重置的模型数
pub fn ModelRouter::window_reset_check(
  self : ModelRouter,
  now~ : String,
) -> Int {
  let now_s = iso_to_secs(now)
  if now_s < 0 {
    return 0
  }
  let win = self.config.window_seconds
  let pools = [self.config.free_models, self.config.paid_models]
  let mut reset = 0
  for pool in pools {
    let mut i = 0
    while i < pool.length() {
      let m = pool[i]
      if m.window_start != "" {
        let s = iso_to_secs(m.window_start)
        if s >= 0 && now_s - s >= win {
          pool[i].used = 0
          pool[i].window_start = now
          reset = reset + 1
        }
      }
      i = i + 1
    }
  }
  reset
}

///|
/// 选型（只决策不消耗配额）。全部不可用 → available=false 的决策，绝不静默返回空名。
/// 这里是 last_pick 的**唯一登记点**（BUG-56）：所有成功分支都归一到这一个 choke point，
/// 免得每条分支各写一遍、漏一条就又是一个"报告与实际不一致"的缺陷。
pub fn ModelRouter::pick(self : ModelRouter, now~ : String) -> RouteDecision {
  let d = self.pick_inner(now~)
  if d.available && !d.model_name.is_empty() {
    self.last_pick = d.model_name
  }
  d
}

///|
fn ModelRouter::pick_inner(self : ModelRouter, now~ : String) -> RouteDecision {
  let _ = self.window_reset_check(now~)
  let th = self.config.threshold_pct
  let free = self.config.free_models
  let paid = self.config.paid_models
  let nxt = secs_to_iso(iso_to_secs(now) + self.config.window_seconds)
  match self.current_tier {
    Free =>
      match pool_pick(free, self.free_idx, th) {
        Some(idx) => {
          self.free_idx = (idx + 1) % free.length()
          if free[idx].window_start == "" {
            free[idx].window_start = now
          }
          {
            model_name: free[idx].name,
            tier: Free,
            reason: "free tier has capacity",
            switched: false,
            next_switch_at: nxt,
            available: true,
          }
        }
        None =>
          match pool_pick(paid, self.paid_idx, th) {
            Some(idx) => {
              self.current_tier = Paid
              self.switch_count = self.switch_count + 1
              self.last_switch_at = now
              self.last_reason = "free tier reached \{th}% threshold"
              self.paid_idx = (idx + 1) % paid.length()
              if paid[idx].window_start == "" {
                paid[idx].window_start = now
              }
              {
                model_name: paid[idx].name,
                tier: Paid,
                reason: self.last_reason,
                switched: true,
                next_switch_at: nxt,
                available: true,
              }
            }
            None => {
              self.last_reason = "no available model: both pools exhausted or unconfigured"
              {
                model_name: "",
                tier: self.current_tier,
                reason: self.last_reason,
                switched: false,
                next_switch_at: "",
                available: false,
              }
            }
          }
      }
    Paid =>
      match pool_pick(paid, self.paid_idx, th) {
        Some(idx) => {
          self.paid_idx = (idx + 1) % paid.length()
          if paid[idx].window_start == "" {
            paid[idx].window_start = now
          }
          {
            model_name: paid[idx].name,
            tier: Paid,
            reason: "paid tier has capacity",
            switched: false,
            next_switch_at: nxt,
            available: true,
          }
        }
        None =>
          match pool_pick(free, self.free_idx, th) {
            Some(idx) => {
              self.current_tier = Free
              self.switch_count = self.switch_count + 1
              self.last_switch_at = now
              self.last_reason = "paid pool exhausted, fallback to free"
              self.free_idx = (idx + 1) % free.length()
              if free[idx].window_start == "" {
                free[idx].window_start = now
              }
              {
                model_name: free[idx].name,
                tier: Free,
                reason: self.last_reason,
                switched: true,
                next_switch_at: nxt,
                available: true,
              }
            }
            None => {
              self.last_reason = "no available model: both pools exhausted or unconfigured"
              {
                model_name: "",
                tier: self.current_tier,
                reason: self.last_reason,
                switched: false,
                next_switch_at: "",
                available: false,
              }
            }
          }
      }
  }
}

///|
/// 记录一次真实调用（消耗配额）并返回当前决策
pub fn ModelRouter::record_call(
  self : ModelRouter,
  model~ : String,
  now~ : String,
) -> RouteDecision {
  let _ = self.window_reset_check(now~)
  let pools = [self.config.free_models, self.config.paid_models]
  let mut hit = false
  for pool in pools {
    let mut i = 0
    while i < pool.length() {
      if pool[i].name == model {
        pool[i].used = pool[i].used + 1
        if pool[i].window_start == "" {
          pool[i].window_start = now
        }
        hit = true
      }
      i = i + 1
    }
  }
  let d = self.pick(now~)
  if hit {
    d
  } else {
    {
      model_name: d.model_name,
      tier: d.tier,
      reason: "unknown model '\{model}'（未在任何池中配置，用量未计入）",
      switched: d.switched,
      next_switch_at: d.next_switch_at,
      available: d.available,
    }
  }
}

///|
/// 手动切档（运维出口）。目标档位无可用模型时不切换，返回 available=false 并说明原因。
pub fn ModelRouter::force_switch(
  self : ModelRouter,
  tier~ : ModelTier,
  now~ : String,
) -> RouteDecision {
  let th = self.config.threshold_pct
  let pool = if tier == Free {
    self.config.free_models
  } else {
    self.config.paid_models
  }
  match pool_pick(pool, 0, th) {
    None => {
      self.last_reason = "target tier \{tier.to_string()} 无可用模型，保持原档位"
      {
        model_name: "",
        tier: self.current_tier,
        reason: self.last_reason,
        switched: false,
        next_switch_at: "",
        available: false,
      }
    }
    Some(idx) => {
      // 已在目标档位 ⇒ 显式 no-op（不许把"没切"报成"切了"）
      let noop = self.current_tier == tier
      if !noop {
        self.switch_count = self.switch_count + 1
        self.last_switch_at = now
        self.last_reason = "manual switch"
      }
      self.current_tier = tier
      if tier == Free {
        self.free_idx = (idx + 1) % pool.length()
      } else {
        self.paid_idx = (idx + 1) % pool.length()
      }
      pool[idx].window_start = now
      self.last_pick = pool[idx].name
      {
        model_name: pool[idx].name,
        tier,
        reason: if noop {
          "already on target tier"
        } else {
          "manual switch"
        },
        switched: !noop,
        next_switch_at: secs_to_iso(
          iso_to_secs(now) + self.config.window_seconds,
        ),
        available: true,
      }
    }
  }
}

///|
/// 用量报告（每模型 used/limit/占比/是否超阈值 + 合计）
pub fn ModelRouter::usage_report(self : ModelRouter) -> Json {
  let mut total_used = 0
  for m in self.config.free_models {
    total_used = total_used + m.used
  }
  for m in self.config.paid_models {
    total_used = total_used + m.used
  }
  let with_share = fn(m : ModelQuota) -> Json {
    let share = if total_used <= 0 {
      0.0
    } else {
      m.used.to_double() * 100.0 / total_used.to_double()
    }
    Json::object({
      "name": Json::string(m.name),
      "tier": Json::string(m.tier.to_string()),
      "used": Json::number(m.used.to_double()),
      "limit": Json::number(m.limit.to_double()),
      "remaining": Json::number(m.remaining().to_double()),
      "usage_pct": Json::number(m.usage_pct()),
      "share_pct": Json::number(share),
      "over_threshold": Json::boolean(
        m.usage_pct() >= self.config.threshold_pct,
      ),
      "exhausted": Json::boolean(m.is_exhausted()),
      "window_start": Json::string(m.window_start),
    })
  }
  let cur = self.current_model()
  let cursor_name = match cur {
    Some(m) => m.name
    None => ""
  }
  // BUG-56：current_model 报"真在用哪个"（最近一次选中），游标位另起名 cursor_model
  let in_use = if self.last_pick.is_empty() {
    cursor_name
  } else {
    self.last_pick
  }
  Json::object({
    "window_seconds": Json::number(self.config.window_seconds.to_double()),
    "window_hours": Json::number(
      self.config.window_seconds.to_double() / 3600.0,
    ),
    "threshold_pct": Json::number(self.config.threshold_pct),
    "current_tier": Json::string(self.current_tier.to_string()),
    "current_model": Json::string(in_use),
    "cursor_model": Json::string(cursor_name),
    "last_pick": Json::string(self.last_pick),
    "switch_count": Json::number(self.switch_count.to_double()),
    "last_switch_at": Json::string(self.last_switch_at),
    "last_reason": Json::string(self.last_reason),
    "total_used": Json::number(total_used.to_double()),
    "free_pool": Json::array(self.config.free_models.map(with_share)),
    "paid_pool": Json::array(self.config.paid_models.map(with_share)),
  })
}
