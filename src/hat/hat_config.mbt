/// hat_config.mbt —— HexaMind 六元自驱决策 · 配置解析（纯计算）
///
/// config_json 形状（设计稿 §3.2）：
///   {
///     "topic": "是否该把 X 纳入下一里程碑",
///     "hats": ["wallbreaker","golddigger","stargazer"],   // 六元 id 或六顶帽 id
///     "hat_policy": {
///       "max_rounds": 2,             // 1..10
///       "converge_threshold": 0.6,   // (0,1]
///       "auto_select_hats": true,    // hats 缺省时自动取默认三元
///       "debate_enabled": true       // 是否生成两两辩论计划
///     }
///   }
///
/// 硬门（与 mcp_config_scaffold 同族）：空 topic / 非法 JSON / 非对象顶层 /
/// 未知帽子 / 越界参数一律整笔 Err，**绝不静默用默认值跑出一个"看起来正常"的配置**。
/// 纯计算零网络；非法输入不崩溃，返回 Err。

///|
/// 收敛与迭代策略。
pub struct HatPolicy {
  max_rounds : Int
  converge_threshold : Double
  auto_select_hats : Bool
  debate_enabled : Bool
}

///|
/// 一份已校验的 HexaMind 配置：议题 + 已解析六元 + 策略。
pub struct HatConfig {
  topic : String
  elements : Array[HexaElement]
  policy : HatPolicy
}

///|
/// 默认策略：2 轮上限、0.6 阈值、自动选帽、开辩论。
pub fn default_policy() -> HatPolicy {
  {
    max_rounds: 2,
    converge_threshold: 0.6,
    auto_select_hats: true,
    debate_enabled: true,
  }
}

///|
/// 默认配置：议题 + 默认三元（观星者/破壁者/掘金者）+ 默认策略。
pub fn default_config(topic : String) -> HatConfig {
  { topic, elements: default_elements(), policy: default_policy(), }
}

///|
/// 由六元代号数组取元素（去重保序，任一未知 → Err）。
fn elements_of(ids : Array[String]) -> Result[Array[HexaElement], String] {
  let out : Array[HexaElement] = []
  for id in ids {
    match hexa_for_id(id) {
      Ok(e) => if not(out.any(fn(x) { x.id == e.id })) { out.push(e) }
      Err(m) => return Err(m)
    }
  }
  Ok(out)
}

///|
/// 默认三元对应的元素。
fn default_elements() -> Array[HexaElement] {
  match elements_of(hexa_defaults()) {
    Ok(a) => a
    Err(_) => []
  }
}

///|
/// 解析 config_json；非法输入返回 Err（整笔拒绝，不半生效）。
pub fn parse_config_json(s : String) -> Result[HatConfig, String] {
  if s.trim().is_empty() {
    return Err("config_json 不能为空")
  }
  let form = @json.parse(s) catch {
    _ =>
      return Err("config_json 不是合法 JSON：请检查引号/逗号配平")
  }
  match form {
    Json::Object(_) => ()
    _ => return Err("config_json 顶层必须是 JSON 对象")
  }

  // —— topic（必填，非空）——
  let topic = get_str(form, "topic", "")
  if topic.trim().is_empty() {
    return Err("topic 不能为空：给出要裁决的议题")
  }

  // —— hat_policy ——
  let policy = match parse_policy(get_field(form, "hat_policy")) {
    Err(e) => return Err(e)
    Ok(p) => p
  }

  // —— hats（可缺省；缺省且 auto_select_hats 时取默认三元）——
  let raw_hats = get_str_array(get_field(form, "hats"))
  let ids = if raw_hats.is_empty() {
    if policy.auto_select_hats {
      hexa_defaults()
    } else {
      return Err(
        "hats 为空且 hat_policy.auto_select_hats=false：请显式给帽子",
      )
    }
  } else {
    match resolve_elements(raw_hats) {
      Err(e) => return Err(e)
      Ok(a) => a
    }
  }

  // 六元至少 2 个才有"多视角收敛"（设计稿：六帽选 ≥2）
  if ids.length() < 2 {
    return Err(
      "帽子至少 2 个才能构成多视角收敛（收到 " +
      ids.length().to_string() +
      " 个）",
    )
  }

  let elements = match elements_of(ids) {
    Err(e) => return Err(e)
    Ok(a) => a
  }

  Ok({ topic, elements, policy, })
}

///|
/// 解析 hat_policy 对象；缺省字段回落默认，非法值整笔 Err。
fn parse_policy(j : Json) -> Result[HatPolicy, String] {
  match j {
    Json::Object(_) => ()
    Json::Null => return Ok(default_policy())
    _ => return Err("hat_policy 必须是 JSON 对象")
  }

  let max_rounds = match get_int(j, "max_rounds") {
    Err(e) => return Err("hat_policy.max_rounds: " + e)
    Ok(v) => v
  }
  if max_rounds < 1 || max_rounds > 10 {
    return Err(
      "hat_policy.max_rounds 必须在 1..10 之间（收到 " +
      max_rounds.to_string() +
      "）",
    )
  }

  let threshold = match get_double(j, "converge_threshold") {
    Err(e) => return Err("hat_policy.converge_threshold: " + e)
    Ok(v) => v
  }
  if threshold <= 0.0 || threshold > 1.0 {
    return Err(
      "hat_policy.converge_threshold 必须在 (0,1] 之间（收到 " +
      threshold.to_string() +
      "）",
    )
  }

  Ok({
    max_rounds,
    converge_threshold: threshold,
    auto_select_hats: get_bool(j, "auto_select_hats", true),
    debate_enabled: get_bool(j, "debate_enabled", true),
  })
}

// ---------------------------------------------------------------------------
// JSON 访问小工具（对齐 mcp_config_scaffold 的 mcs_* 约定）
// ---------------------------------------------------------------------------

///|
fn get_field(j : Json, key : String) -> Json {
  match j {
    Json::Object(map) =>
      match map.get(key) {
        Some(v) => v
        None => Json::null()
      }
    _ => Json::null()
  }
}

///|
fn get_str(j : Json, key : String, default : String) -> String {
  match j {
    Json::Object(map) =>
      match map.get(key) {
        Some(Json::String(s)) => s
        _ => default
      }
    _ => default
  }
}

///|
fn get_bool(j : Json, key : String, default : Bool) -> Bool {
  match j {
    Json::Object(map) =>
      match map.get(key) {
        Some(Json::True) => true
        Some(Json::False) => false
        _ => default
      }
    _ => default
  }
}

///|
/// 取整数；非整数或字段类型不符 → Err。
fn get_int(j : Json, key : String) -> Result[Int, String] {
  match j {
    Json::Object(map) =>
      match map.get(key) {
        None => Ok(2)
        Some(Json::Number(n, ..)) => {
          let v = n.to_int()
          if n != v.to_double() {
            Err("必须是整数（收到 " + n.to_string() + "）")
          } else {
            Ok(v)
          }
        }
        Some(_) => Err("必须是整数")
      }
    _ => Err("必须是 JSON 对象")
  }
}

///|
/// 取小数；非数字 → Err。
fn get_double(j : Json, key : String) -> Result[Double, String] {
  match j {
    Json::Object(map) =>
      match map.get(key) {
        None => Ok(0.6)
        Some(Json::Number(n, ..)) => Ok(n)
        Some(_) => Err("必须是数字")
      }
    _ => Err("必须是 JSON 对象")
  }
}

///|
/// 取字符串数组；非数组或未给 → 空数组。
fn get_str_array(j : Json) -> Array[String] {
  match j {
    Json::Array(arr) =>
      arr.map(fn(v) {
        match v {
          Json::String(s) => s
          _ => ""
        }
      })
    _ => []
  }
}
