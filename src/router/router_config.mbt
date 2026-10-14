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
      // P0.1：OFM 外部端点。坏类型进 warnings 而非静默采纳（与 window_seconds 同纪律）。
      // 这里**只读端点**：密钥不在此处解析，也不存在于 RouterConfig（见 to_json 注释）。
      // 注意必须把端点警告**拼到 w2 之后再返回**：w1/w2 已经是在本函数早前快照的 warns 上
      // 展开的，回头再往局部 `warns` 追加会丢掉（cfg_ofm_4 实测抓到过这条）。
      let (ofm_endpoint, ofm_warns) = match m.get("ofm_endpoint") {
        Some(Json::String(s)) => (s.trim().to_owned(), [])
        Some(Json::Null) => ("", [])
        Some(_) => ("", ["ofm_endpoint 非字符串，按未配置处理"])
        None => ("", [])
      }
      // P2：laya 判断路由开关。缺字段/null → false（零回归）；坏类型 → false + warning。
      let (use_laya, use_laya_warns) = match m.get("use_laya") {
        Some(Json::True) => (true, [])
        Some(Json::False) => (false, [])
        Some(Json::Null) | None => (false, [])
        Some(_) => (false, ["use_laya 非布尔，按 false 处理"])
      }
      (
        {
          window_seconds: ws2,
          threshold_pct: tp2,
          free_models,
          paid_models,
          ofm_endpoint,
          use_laya,
        },
        w2 + ofm_warns + use_laya_warns,
      )
    }
    Json::Null => (d, []) // null = 没给配置，不算违例、不产噪音 warning
    _ => (d, ["配置不是 JSON 对象，整体回落默认配置"])
  }
}

///|
/// 读单模型的 `lane` 渠道元数据（P0.1）。返回 (lane, warnings)。
/// 缺字段/null → 空串（未标注，语义是"未知"，不算违例）；坏类型 → 空串 + warning。
/// 绝不猜一个渠道名填进去——猜错渠道比留空更危险（会把请求打到别的上游）。
fn parse_lane(
  v : Json?,
  field : String,
  name : String,
) -> (String, Array[String]) {
  match v {
    Some(Json::String(s)) => (s.trim().to_owned(), [])
    Some(Json::Null) | None => ("", [])
    Some(_) =>
      ("", [field + "." + name + " lane 非字符串，按未标注处理"])
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
              let (lane_v, lane_w) = parse_lane(mm.get("lane"), field, name)
              w = w + lane_w
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
              out = out + [ModelQuota::new(name~, tier~, limit~, lane=lane_v)]
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
/// 配置导出（供 skill/文档展示当前生效档位）。
///
/// **投影面硬纪律（P0.1 白盒锁）**：本函数的输出会被四态投影到 skill/插件目录，
/// 因此**不含、也永不许含任何凭据**。`ofm_endpoint` 是端点地址（非密钥），可以投影；
/// `FIST_OFM_KEY` / `ofm_api_key` 一律只存在于进程环境变量，结构体里根本没有这个字段，
/// 所以本函数没有可泄漏的路径——这条由 `router_config_wbtest.mbt` 的 cfg_ofm_1（凭据形状
/// 扫描）与 cfg_ofm_2（顶层键集合钉死）两条锁钉住。
pub fn RouterConfig::to_json(self : RouterConfig) -> Json {
  Json::object({
    "window_seconds": Json::number(self.window_seconds.to_double()),
    "threshold_pct": Json::number(self.threshold_pct),
    "free_pool": Json::array(self.free_models.map(fn(m) { m.to_json() })),
    "paid_pool": Json::array(self.paid_models.map(fn(m) { m.to_json() })),
    "ofm_endpoint": Json::string(self.ofm_endpoint),
    "use_laya": Json::boolean(self.use_laya),
  })
}

///|
/// OFM 端点解析（P0.1，纯计算零 IO）：**env 非空则 env 赢**，否则用 config_json 的值，
/// 两者皆空 → 空串（未配置）。
///
/// 为什么 env 优先：端点属部署环境事实（同机端口可能被改），而 config_json 会随四态
/// 投影进库、进插件目录；让 env 覆盖可以不改仓库文件就完成部署改道。
/// 返回空串**不表示"默认端点"**——调用方必须显式处理"未配置"，不得静默回落某个地址。
pub fn resolve_ofm_endpoint(
  config_value : String,
  env_value : String,
) -> String {
  let e = env_value.trim().to_owned()
  if e != "" {
    e
  } else {
    config_value.trim().to_owned()
  }
}
