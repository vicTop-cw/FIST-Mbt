/// ofm_models.mbt —— P0.2 前置：OFM `/v1/models` 响应体解析（OpenAI 兼容形状）
///
/// 纯计算、零 IO、零网络：只吃响应体文本，吐出模型清单。把「拉清单」与「用清单」解耦——
/// 拉清单是部署侧带 Bearer 的一次 `GET /v1/models`（IO，见 P0.3/server 层），本函数只负责
/// 解析与容错。
///
/// **lane 纪律（与 P0.1 一致）**：本函数**不**从模型 id 猜 `lane`。猜错渠道比不标注更糟
/// （会把 zen 流量打进 non-stream 模型，重试一万次仍错）。lane 由配置显式声明，缺 = 未标注。
///
/// 容错（与 `router_config.from_json` 的逐字段兜底同族）：
///   · body 空 / 非合法 JSON / 非对象 → `Err`（给不出清单就别往下走，不静默给空）
///   · 缺 `data` 或 `data` 非数组 → `Err`
///   · `data` 某项缺 `id` / `id` 非字符串 / `id` trim 后为空 → **跳过该项**（不整段拒）
///   · `data` 为空数组 → `Ok(空清单)`（是否可用由调用方决定，parser 不越权）

///|
pub struct OfmModel {
  id : String
  owned_by : String
} derive(Show, Eq, Debug)

///|
/// 解析 OpenAI 兼容的 `GET /v1/models` 响应体，返回模型清单。
pub fn parse_ofm_models(body : String) -> Result[Array[OfmModel], String] {
  let b = body.trim().to_owned()
  if b.is_empty() {
    return Err("响应体为空")
  }
  let json = @json.parse(b) catch {
    _ => return Err("响应体不是合法 JSON")
  }
  let m = match json {
    Json::Object(m) => m
    _ => return Err("响应体不是 JSON 对象")
  }
  let data = match m.get("data") {
    Some(Json::Array(a)) => a
    Some(_) => return Err("data 不是数组")
    None => return Err("缺 data 数组")
  }
  let out : Array[OfmModel] = []
  for item in data {
    match item {
      Json::Object(it) => {
        let id = match it.get("id") {
          Some(Json::String(s)) => s.trim().to_owned()
          _ => continue
        }
        if id.is_empty() {
          continue
        }
        let owned_by = match it.get("owned_by") {
          Some(Json::String(o)) => o.trim().to_owned()
          _ => ""
        }
        out.push({ id, owned_by, })
      }
      _ => continue
    }
  }
  Ok(out)
}
