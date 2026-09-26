/// router_config.mbt —— 路由配置的 JSON 加载与校验（合并自 fist-model-router 的 config 层）
///
/// 配置只描述"池子与限额"，不含任何 API key/base_url —— 密钥属于运行环境（环境变量注入），
/// 出现在配置里就等于写进文档与投影（四态会把这份 JSON 复制到 skill/插件目录）。

///|
/// 从 JSON 加载配置。语义：**逐字段兜底**——缺字段用默认值，坏字段进 warnings 而不静默采纳。
/// 返回 (config, warnings)。
pub fn RouterConfig::from_json(json : Json) -> (RouterConfig, Array[String]) {
  let d = RouterConfig::default()
  let mut warns : Array[String] = []
  match json {
    Json::Object(m) => {
      let ws = match m.get("window_seconds") {
        Some(Json::Number(n, ..)) => n.to_int()
        Some(_) => {
          warns = warns +
            ["window_seconds 非数字，回落默认 \{d.window_seconds}"]
          d.window_seconds
        }
        None => d.window_seconds
      }
      let ws2 = if ws > 0 {
        ws
      } else {
        warns = warns +
          ["window_seconds=\{ws} 非正，回落默认 \{d.window_seconds}"]
        d.window_seconds
      }
      let tp = match m.get("threshold_pct") {
        Some(Json::Number(n, ..)) => n
        Some(_) => {
          warns = warns +
            ["threshold_pct 非数字，回落默认 \{d.threshold_pct}"]
          d.threshold_pct
        }
        None => d.threshold_pct
      }
      let tp2 = if tp > 0.0 && tp <= 100.0 {
        tp
      } else {
        warns = warns +
          ["threshold_pct=\{tp.to_string()} 越界(0,100]，回落默认"]
        d.threshold_pct
      }
      let (free_models, w1) = parse_pool(
        m.get("free_pool"),
        Free,
        "free_pool",
        warns,
      )
      let (paid_models, w2) = parse_pool(
        m.get("paid_pool"),
        Paid,
        "paid_pool",
        w1,
      )
      (
        { window_seconds: ws2, threshold_pct: tp2, free_models, paid_models, },
        w2,
      )
    }
    Json::Null => (d, []) // null = 没给配置，不算违例、不产噪音 warning
    _ => (d, ["配置不是 JSON 对象，整体回落默认配置"])
  }
}

///|
/// 解析一个模型池。缺 key → 用默认池；数组为空 → **显式空池**（路由会返回 available=false，
/// 不再像源项目那样在空池上索引 [0] 而 panic）。坏元素跳过并记 warning。
/// warning 必须**随返回值传出**：MoonBit 的 `a + [x]` 产生新数组，就地 mut 绑定不会回传调用方
/// （第一版在 parse_pool 里 append 后丢弃，导致坏配置静默通过——rt_10 钉住这条）。
fn parse_pool(
  v : Json?,
  tier : ModelTier,
  field : String,
  warns_in : Array[String],
) -> (Array[ModelQuota], Array[String]) {
  let mut w = warns_in
  match v {
    None =>
      (
        match tier {
          Free => RouterConfig::default().free_models
          Paid => RouterConfig::default().paid_models
        },
        w,
      )
    Some(Json::Array(arr)) => {
      let mut out : Array[ModelQuota] = []
      for item in arr {
        match item {
          Json::Object(mm) => {
            let name = match mm.get("name") {
              Some(Json::String(s)) => s.trim().to_owned()
              _ => ""
            }
            if name == "" {
              w = w + [field + " 含缺 name 的条目，已跳过"]
            } else {
              let limit = match mm.get("limit") {
                Some(Json::Number(n, ..)) =>
                  if n.to_int() < 0 {
                    w = w +
                      [
                        field +
                        "." +
                        name +
                        " limit 为负，按无限(0)处理",
                      ]
                    0
                  } else {
                    n.to_int()
                  }
                Some(_) => {
                  w = w +
                    [
                      field +
                      "." +
                      name +
                      " limit 非数字，按无限(0)处理",
                    ]
                  0
                }
                None => if tier == Free { 100 } else { 50 }
              }
              out = out + [ModelQuota::new(name~, tier~, limit~)]
            }
          }
          _ => w = w + [field + " 含非对象条目，已跳过"]
        }
      }
      (out, w)
    }
    Some(_) => {
      w = w + [field + " 不是数组，回落默认池"]
      (
        match tier {
          Free => RouterConfig::default().free_models
          Paid => RouterConfig::default().paid_models
        },
        w,
      )
    }
  }
}

///|
/// 配置导出（供 skill/文档展示当前生效档位；不含密钥）
pub fn RouterConfig::to_json(self : RouterConfig) -> Json {
  Json::object({
    "window_seconds": Json::number(self.window_seconds.to_double()),
    "threshold_pct": Json::number(self.threshold_pct),
    "free_pool": Json::array(self.free_models.map(fn(m) { m.to_json() })),
    "paid_pool": Json::array(self.paid_models.map(fn(m) { m.to_json() })),
  })
}
