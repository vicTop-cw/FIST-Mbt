/// ofm_models_wbtest.mbt —— P0.2 前置白盒锁：`parse_ofm_models`（OpenAI 兼容 /v1/models 解析）
///
/// 钉死的四条硬纪律：
///   1. 给不出清单就 `Err`（空/非法 JSON/非对象/缺 data/data 非数组）——**不静默给空**；
///   2. 单条坏数据只**跳过该项**，不整段拒（一条坏不拖垮整清单）；
///   3. 缺 `owned_by` 允许（可选字段，兜底空串）；
///   4. **不猜 lane**：本层产出只有 `id`/`owned_by`，无 lane 字段——lane 由配置显式声明。
///
/// 与 P0.1 `cfg_ofm_*` / P0.4 `ofm_f_*` 同族续编号，这里起 `ofm_m_*`。

///|
test "ofm_m_1_合法响应体解析出模型清单" {
  let body = "{\"object\":\"list\",\"data\":[" +
    "{\"id\":\"SenseNova/zen-2\",\"object\":\"model\",\"owned_by\":\"sense\"}," +
    "{\"id\":\"SenseNova/kilo-1\",\"object\":\"model\",\"owned_by\":\"sense\"}," +
    "{\"id\":\"SenseNova/eac-3\"}" +
    "]}"
  match parse_ofm_models(body) {
    Ok(list) => {
      assert_eq(list.length(), 3)
      assert_eq(list[0].id, "SenseNova/zen-2")
      assert_eq(list[0].owned_by, "sense")
      assert_eq(list[2].id, "SenseNova/eac-3")
      // 缺 owned_by → 兜底空串，不整段拒
      assert_eq(list[2].owned_by, "")
    }
    Err(e) => abort("合法响应体不应 Err：\{e}")
  }
}

///|
test "ofm_m_2_给不出清单即 Err_不静默给空" {
  assert_eq(parse_ofm_models("").is_err(), true)
  assert_eq(parse_ofm_models("   ").is_err(), true)
  assert_eq(parse_ofm_models("not json").is_err(), true)
  assert_eq(parse_ofm_models("[1,2,3]").is_err(), true) // 是 JSON 但不是对象
  assert_eq(parse_ofm_models("{}").is_err(), true) // 缺 data
  assert_eq(parse_ofm_models("{\"data\": \"not-array\"}").is_err(), true)
}

///|
test "ofm_m_3_单条坏数据只跳过该条_不整段拒" {
  let body = "{\"data\":[" +
    "{\"id\":\"ok-model\"}," +
    "{\"id\":123}," +
    "{}," +
    "{\"id\":\"\"}," +
    "{\"id\":\"  another-ok  \"}" +
    "]}"
  match parse_ofm_models(body) {
    Ok(list) => {
      // 只留下两条 id 合法且非空的
      assert_eq(list.length(), 2)
      assert_eq(list[0].id, "ok-model")
      assert_eq(list[1].id, "another-ok") // trim 后
    }
    Err(e) => abort("单条坏数据不应让整段 Err：\{e}")
  }
}

///|
test "ofm_m_4_空 data 数组给 Ok 空清单_是否可用交调用方" {
  match parse_ofm_models("{\"object\":\"list\",\"data\":[]}") {
    Ok(list) => assert_eq(list.length(), 0)
    Err(e) => abort("空 data 数组应 Ok 空清单而非 Err：\{e}")
  }
}

///|
test "ofm_m_5_解析层绝不产出 lane 字段" {
  // 结构锁：`OfmModel` 只有 `id`/`owned_by` 两字段——lane 没有输出通道。若有人往结构体
  // 加 lane 字段，本测试编译期即失效（字段名不匹配），属硬锁而非运行时软锁。
  // 这里补一条运行时观察：id 带渠道暗示（zen-2），确认解析后只回填 id/owned_by。
  let body = "{\"data\":[{\"id\":\"SenseNova/zen-2\",\"owned_by\":\"sense\"}]}"
  match parse_ofm_models(body) {
    Ok(list) => {
      assert_eq(list[0].id, "SenseNova/zen-2")
      assert_eq(list[0].owned_by, "sense")
    }
    Err(e) => abort("不应 Err：\{e}")
  }
}

///|
/// `filter_unhealthy_models`：过滤掉黑名单中的模型，保留健康模型。
test "ofm_m_6_过滤已知 502 模型" {
  let models = [
    { id: "good-model", owned_by: "A", },
    { id: "bad-502-model", owned_by: "B", },
    { id: "another-good", owned_by: "C", },
  ]
  let blacklist = ["bad-502-model"]
  let filtered = filter_unhealthy_models(models, blacklist)
  assert_eq(filtered.length(), 2)
  assert_eq(filtered[0].id, "good-model")
  assert_eq(filtered[1].id, "another-good")
}

///|
test "ofm_m_7_空黑名单_原样返回_不误伤" {
  let models = [{ id: "m1", owned_by: "A", }]
  let filtered = filter_unhealthy_models(models, [])
  assert_eq(filtered.length(), 1)
  assert_eq(filtered[0].id, "m1")
}

///|
test "ofm_m_8_精确匹配_不匹配前缀或子串" {
  let models = [
    { id: "model-v1", owned_by: "A", },
    { id: "model-v1-beta", owned_by: "B", },
  ]
  // 只过滤 "model-v1"，"model-v1-beta" 应保留（精确匹配）
  let filtered = filter_unhealthy_models(models, ["model-v1"])
  assert_eq(filtered.length(), 1)
  assert_eq(filtered[0].id, "model-v1-beta")
  // is_model_unhealthy 同样精确匹配
  assert_eq(is_model_unhealthy("model-v1", ["model-v1"]), true)
  assert_eq(is_model_unhealthy("model-v1-beta", ["model-v1"]), false)
}
