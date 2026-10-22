///|
/// CAF 记忆逐条持久化层（§2.3 server 接线后，重启恢复记忆的前置）。
///
/// 与 `CafMemory::to_json` 的差异：`to_json` 是**聚合快照**（total/count/by_model），
/// 只用于展示，不含原始记录，**无法恢复记忆**；本层保留逐条记录可完整往返。
///
/// 格式（与 `model-router-{ns}.json` 同形态，落盘 `memory/model-router-caf-{ns}.json`）：
/// {
///   "max_size": Int,
///   "records": [ { "feature_hash": Int, "model": Str, "ok": Bool,
///                  "cost": Double, "ts": Str }, ... ]  // 时间序
/// }
///
/// 坏类型一律降级 + warning（与 `RouterConfig::from_json` 同口径），绝不 panic。
/// `load` 用 `new(max_size)` + 逐条 `push` 重建；因 push 后 `all()` 从 index 0 起遍历，
/// 只要 dump 按 `all()` 顺序导出，load 按序 push，恢复后 `all()` 顺序与原记忆一致。

///|
/// 逐条导出（时间序）。`max_size` 从 `to_json()` 解构读取。
pub fn caf_memory_dump(mem : CafMemory) -> Json {
  let recs = mem.all()
  // to_json 是聚合快照，capacity 字段可读出 max_size（CafMemory 私有字段外部不可直读）
  let capacity = match mem.to_json() {
    Json::Object(m) =>
      match m.get("capacity") {
        Some(Json::Number(n, ..)) => n.to_int()
        _ => 10000
      }
    _ => 10000
  }
  Json::object({
    "max_size": Json::number(capacity.to_double()),
    "records": Json::array(
      recs.map(fn(rec) {
        Json::object({
          "feature_hash": Json::number(rec.feature_hash.to_double()),
          "model": Json::string(rec.model),
          "ok": Json::boolean(rec.ok),
          "cost": Json::number(rec.cost),
          "ts": Json::string(rec.ts),
        })
      }),
    ),
  })
}

///|
/// 从逐条 JSON 恢复记忆。坏字段降级 + warning，绝不 panic。
/// 返回 `(记忆, warnings)`；`warns` 非空说明有字段被忽略，调用方应记日志。
pub fn caf_memory_load(json : Json) -> (CafMemory, Array[String]) {
  let mut warns : Array[String] = []
  let obj = match json {
    Json::Object(m) => m
    _ => {
      warns = warns + ["顶层非对象，按空记忆处理"]
      return (CafMemory::new(max_size=10000), warns)
    }
  }
  let m = match obj.get("max_size") {
    Some(Json::Number(n, ..)) => n.to_int()
    Some(_) => {
      warns = warns + ["max_size 非整数，按默认 10000 处理"]
      10000
    }
    None => 10000
  }
  let mem = CafMemory::new(max_size=m)
  let recs = match obj.get("records") {
    Some(Json::Array(items)) => items
    Some(_) => {
      warns = warns + ["records 非数组，按空处理"]
      []
    }
    None => []
  }
  // 逐条解析：字段坏类型 → 跳过该条 + warning
  let mut skip = 0
  for item in recs {
    match parse_caf_record(item) {
      Some(rec) => mem.push(rec)
      None => skip = skip + 1
    }
  }
  if skip > 0 {
    warns = warns + ["records 含 \{skip} 条坏字段记录，已跳过"]
  }
  (mem, warns)
}

///|
/// 解析单条 CafRecord；缺字段/坏类型 → None（由 load 计数为 warning）。
fn parse_caf_record(item : Json) -> CafRecord? {
  let obj = match item {
    Json::Object(m) => m
    _ => return None
  }
  let feature_hash = match obj.get("feature_hash") {
    Some(Json::Number(n, ..)) => Some(n.to_int())
    _ => None
  }
  let model = match obj.get("model") {
    Some(Json::String(s)) => Some(s)
    _ => None
  }
  let ok = match obj.get("ok") {
    Some(Json::True) => Some(true)
    Some(Json::False) => Some(false)
    _ => None
  }
  let cost = match obj.get("cost") {
    Some(Json::Number(n, ..)) => Some(n)
    _ => None
  }
  let ts = match obj.get("ts") {
    Some(Json::String(s)) => Some(s)
    _ => None
  }
  // 任一字段缺失 → 整条无效（避免半条坏记录污染记忆）
  match (feature_hash, model, ok, cost, ts) {
    (Some(f), Some(md), Some(o), Some(c), Some(t)) =>
      Some(CafRecord::new(feature_hash=f, model=md, ok=o, cost=c, ts=t))
    _ => None
  }
}
