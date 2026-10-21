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
      let (ws, ws_warns) = num_to_int_safe(
        m.get("window_seconds"),
        "window_seconds",
        d.window_seconds,
      )
      warns = warns + ws_warns
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
      // P2c：CAF 记忆路由开关。缺字段/null → false（零回归）；坏类型 → false + warning。
      let (use_caf_memory, use_caf_memory_warns) = match
        m.get("use_caf_memory") {
        Some(Json::True) => (true, [])
        Some(Json::False) => (false, [])
        Some(Json::Null) | None => (false, [])
        Some(_) => (false, ["use_caf_memory 非布尔，按 false 处理"])
      }
      // P2d：CAF 冷启动偏好模型列表（有序）。缺字段/null → []（零回归）；坏类型 → [] + warning。
      let (caf_default_preference, caf_default_preference_warns) = match
        m.get("caf_default_preference") {
        Some(Json::Array(items)) => {
          let mut models : Array[String] = []
          let mut bad = false
          for it in items {
            match it {
              Json::String(s) => models = models + [s]
              _ => bad = true
            }
          }
          (
            models,
            if bad {
              ["caf_default_preference 含非字符串元素，已忽略"]
            } else {
              []
            },
          )
        }
        Some(Json::Null) | None => ([], [])
        Some(_) => ([], ["caf_default_preference 非数组，按空处理"])
      }
      // P2d：视为「记忆充足」的最小证据数。缺字段/null → 10（零回归）；坏类型 → 10 + warning。
      let (caf_min_evidences, caf_min_evidences_warns) = match
        m.get("caf_min_evidences") {
        Some(Json::Number(n, ..)) => (n.to_int(), [])
        Some(Json::Null) | None => (10, [])
        Some(_) => (10, ["caf_min_evidences 非整数，按 10 处理"])
      }
      (
        {
          window_seconds: ws2,
          threshold_pct: tp2,
          free_models,
          paid_models,
          ofm_endpoint,
          use_laya,
          use_caf_memory,
          caf_default_preference,
          caf_min_evidences,
        },
        w2 +
        ofm_warns +
        use_laya_warns +
        use_caf_memory_warns +
        caf_default_preference_warns +
        caf_min_evidences_warns,
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
fn parse_opt_double(v : Json?, field : String) -> (Double, Array[String]) {
  match v {
    None => (0.0, [])
    Some(Json::Null) => (0.0, [])
    Some(Json::Number(n, ..)) => (n, [])
    Some(_) => (0.0, [field + " 非数字，按 0 处理"])
  }
}

///|
/// JSON Number → Int 的安全转换（BUG-192）。
/// `Double::to_int()` 对超界值**饱和**（BUG-26 实测：1e300 → Int max），带小数值被截断；
/// 这里显式收窄到 Int32 安全域，越界/NaN 一律回落 `dft` 并记 warning。
fn num_to_int_safe(
  v : Json?,
  field : String,
  dft : Int32,
) -> (Int32, Array[String]) {
  match v {
    None | Some(Json::Null) => (dft, [])
    Some(Json::Number(n, ..)) =>
      if n != n || n < -2_000_000_000.0 || n > 2_000_000_000.0 {
        (dft, ["\{field} 数值越界或 NaN，按默认 \{dft} 处理"])
      } else {
        (n.to_int(), [])
      }
    Some(_) => (dft, ["\{field} 非数字，按默认 \{dft} 处理"])
  }
}

///|
fn parse_opt_int(v : Json?, field : String) -> (Int32, Array[String]) {
  match v {
    None => (0, [])
    Some(Json::Null) => (0, [])
    Some(Json::Number(n, ..)) =>
      if n != n || n < -2_000_000_000.0 || n > 2_000_000_000.0 {
        (0, ["\{field} 数值越界或 NaN，按 0 处理"])
      } else {
        (n.to_int(), [])
      }
    Some(_) => (0, ["\{field} 非数字，按 0 处理"])
  }
}

///|
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
              // P1.3：性价比字段可选，缺/null → 0（不参与比较），坏类型 → warning
              let (ppc, ppc_w) = parse_opt_double(
                mm.get("price_per_call"),
                field + "." + name + " price_per_call",
              )
              w = w + ppc_w
              let (pp1k, pp1k_w) = parse_opt_double(
                mm.get("price_per_1k"),
                field + "." + name + " price_per_1k",
              )
              w = w + pp1k_w
              let (rk, rk_w) = parse_opt_int(
                mm.get("rank"),
                field + "." + name + " rank",
              )
              w = w + rk_w
              let dft_limit = if tier == Free { 100 } else { 50 }
              // BUG-192：limit 走 num_to_int_safe，越界/NaN 不 panic。
              // 缺字段/Null → 默认（与旧 None 分支一致）；非数字/越界 → 0 无限（与旧 Some(_)/负值一致）。
              let limit = match mm.get("limit") {
                None => dft_limit
                Some(Json::Null) => dft_limit
                Some(Json::Number(n, ..)) =>
                  if n != n || n > 2_000_000_000.0 {
                    w = w +
                      [
                        field +
                        "." +
                        name +
                        " limit 数值越界或 NaN，按无限(0)处理",
                      ]
                    0
                  } else if n < 0.0 {
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
              }
              out = out +
                [
                  ModelQuota::new(
                    name~,
                    tier~,
                    limit~,
                    lane=lane_v,
                    price_per_call=ppc,
                    price_per_1k=pp1k,
                    rank=rk,
                  ),
                ]
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
    "use_caf_memory": Json::boolean(self.use_caf_memory),
    "caf_default_preference": Json::array(
      self.caf_default_preference.map(fn(s) { Json::string(s) }),
    ),
    "caf_min_evidences": Json::number(self.caf_min_evidences.to_double()),
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
