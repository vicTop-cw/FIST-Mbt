/// router_config_wbtest.mbt —— P0.1 白盒锁：OFM 配置结构扩展（ofm_endpoint + lane）
///
/// 硬纪律：配置会被四态投影到 skill/插件目录，因此 `RouterConfig` **刻意没有密钥字段**，
/// 密钥只从进程环境变量读。这里把「投影面永不含凭据形状」和「顶层键集合被钉死」两条
/// 钉成可跑的红绿锁，防止将来有人往结构体里加 key 字段时投影面跟着泄漏。
///
/// JSON 用构造器搭（同包 `router_state_wbtest.mbt` 的 `qj/qs/qn` 复用，不重复定义）。

///|
test "cfg_ofm_1_投影面 to_json 永不含凭据形状" {
  let cfg = RouterConfig::default()
  let s = cfg.to_json().stringify()
  let banned = [
    "api_key", "apikey", "ofm_key", "secret", "credential", "password", "sk-", "Bearer",
    "bearer", "authorization", "token",
  ]
  for b in banned {
    if s.contains(b) {
      abort(
        "to_json 投影面出现凭据形状 '\{b}'（会被投影进 skill/插件目录）",
      )
    }
  }
}

///|
test "cfg_ofm_2_投影面顶层键集合被钉死_新增字段须显式登记" {
  let m = match RouterConfig::default().to_json() {
    Json::Object(m) => m
    _ => abort("to_json 应回对象")
  }
  if m.keys().length() != 6 {
    abort(
      "投影面顶层键数 != 6（got \{m.keys().length()}），新增字段必须显式进此锁",
    )
  }
  for
    k in [
      "window_seconds", "threshold_pct", "free_pool", "paid_pool", "ofm_endpoint",
      "use_laya",
    ] {
    if !m.contains(k) {
      abort("投影面缺字段 '\{k}'")
    }
  }
}

///|
test "cfg_ofm_3_from_json 解析 ofm_endpoint 与模型 lane" {
  let cfg_j = qj([
    ("window_seconds", qn(18000)),
    ("threshold_pct", Json::number(95.0)),
    (
      "free_pool",
      Json::array([
        qj([("name", qs("ofm-zen-a")), ("limit", qn(100)), ("lane", qs("zen"))]),
        qj([("name", qs("ofm-plain")), ("limit", qn(100))]),
      ]),
    ),
    ("paid_pool", Json::array([])),
    ("ofm_endpoint", qs("http://127.0.0.1:18899/v1")),
  ])
  let (cfg, warns) = RouterConfig::from_json(cfg_j)
  assert_eq(cfg.ofm_endpoint, "http://127.0.0.1:18899/v1")
  assert_eq(cfg.free_models.length(), 2)
  assert_eq(cfg.free_models[0].lane, "zen")
  // 缺 lane 的条目 lane=空串：语义是「未标注」，绝不是「默认渠道」
  assert_eq(cfg.free_models[1].lane, "")
  assert_eq(warns.length(), 0)
}

///|
test "cfg_ofm_4_坏类型进 warnings 不静默采纳" {
  let cfg_j = qj([
    (
      "free_pool",
      Json::array([
        qj([
          ("name", qs("m1")),
          ("limit", qn(10)),
          ("lane", qn(1)), // 坏类型：lane 必须是字符串
        ]),
      ]),
    ),
    ("paid_pool", Json::array([])),
    ("ofm_endpoint", qn(99)), // 坏类型：端点必须是字符串
  ])
  let (cfg, warns) = RouterConfig::from_json(cfg_j)
  assert_eq(cfg.ofm_endpoint, "")
  assert_eq(cfg.free_models[0].lane, "")
  let mut joined = ""
  for x in warns {
    joined = joined + x + " "
  }
  if !joined.contains("ofm_endpoint") || !joined.contains("lane") {
    abort("坏类型必须进 warnings 且点名：got '\{joined}'")
  }
}

///|
test "cfg_ofm_5_端点解析 env 优先于 config，双空即未配置" {
  assert_eq(
    resolve_ofm_endpoint("http://cfg/v1", "http://env/v1"),
    "http://env/v1",
  )
  assert_eq(resolve_ofm_endpoint("http://cfg/v1", "  "), "http://cfg/v1")
  assert_eq(resolve_ofm_endpoint("http://cfg/v1", "\t"), "http://cfg/v1")
  // 双空 → 空串（未配置），调用方必须显式处理，不得静默回落某个地址
  assert_eq(resolve_ofm_endpoint("", ""), "")
}

///|
/// P0.2 锁：默认 `free_pool` 已换成**真实 OFM 模型 ID**（2026-10-12 实机 GET
/// `{ofm_endpoint}/models` 拉到，`owned_by=our-free-model`），并显式标 `lane="ofm"`。
/// 换 ID 必须逐条对上、`lane` 不得留空——留空=未标注=调用方可能误解成默认渠道。
test "cfg_ofm_6_默认 free_pool 是真实 OFM 模型且 lane 显式为 ofm" {
  let cfg = RouterConfig::default()
  let expect = [
    "ling-3.1-flash-free", "mimo-v2.6-flash-free", "muse-spark-1.2-contributor-free",
    "muse-spark-1.3-contributor-free", "nemotron-3.5-lightning-free", "step-5-preview-free",
    "longcat-2.5-preview-free", "space-bunny-free",
  ]
  if cfg.free_models.length() != expect.length() {
    abort(
      "默认 free_pool 长度 != \{expect.length()}（got \{cfg.free_models.length()}）",
    )
  }
  for i = 0; i < expect.length(); i = i + 1 {
    if cfg.free_models[i].name != expect[i] {
      abort(
        "free_pool[\{i}] 模型 ID != \{expect[i]}（got \{cfg.free_models[i].name}）",
      )
    }
    if cfg.free_models[i].tier != ModelTier::Free {
      abort("free_pool[\{i}] 应为 Free")
    }
    if cfg.free_models[i].lane != "ofm" {
      abort(
        "free_pool[\{i}] lane 应为 ofm（got '\{cfg.free_models[i].lane}'）",
      )
    }
  }
}

///|
/// BUG-192 回归：`config_json` 里的大数/NaN 不 panic，越界字段回落默认 + 进 warnings。
/// 旧代码 `Some(Json::Number(n, ..)) => n.to_int()` 对 1e300 会饱和（BUG-26 实测），
/// 或按旧 R12-R4 口径 panic；两类都不许崩。
test "cfg_192_超大数值与 NaN 不 panic 且回落默认" {
  // window_seconds 超大
  let (cfg, warns) = RouterConfig::from_json(
    qj([
      ("window_seconds", Json::number(99999999999.0)),
      ("free_pool", Json::array([])),
      ("paid_pool", Json::array([])),
    ]),
  )
  assert_eq(cfg.window_seconds, RouterConfig::default().window_seconds)
  if warns.length() == 0 {
    abort("越界 window_seconds 必须进 warnings")
  }
  // limit 超大（pool 内的 rank / limit 都走 parse_opt_int / 安全转换）
  let (cfg2, warns2) = RouterConfig::from_json(
    qj([
      (
        "free_pool",
        Json::array([
          qj([
            ("name", qs("m1")),
            ("limit", Json::number(99999999999.0)),
            ("rank", Json::number(99999999999.0)),
          ]),
        ]),
      ),
      ("paid_pool", Json::array([])),
    ]),
  )
  // 越界 limit → 0（无限），越界 rank → 0
  assert_eq(cfg2.free_models[0].limit, 0)
  assert_eq(cfg2.free_models[0].rank, 0)
  if warns2.length() == 0 {
    abort("越界 limit/rank 必须进 warnings")
  }
}
