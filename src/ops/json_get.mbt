///|
/// 私有键访问辅助件（BUG-361 A 案 · `ops` 包作用域 · 批 2）。
///
/// `Json::value` 在 core 里被标 deprecated（0020 弃用族），core 不提供现行
/// 替代键访问器；按 A 案口径每作用域持有一份私有件（不进公开 API / `.mbti` / 发布产物）。
/// 语义与弃用体逐字等价：`if self is Object(obj) { obj.get(key) } else { None }`。
///
/// 命名一次定死为 `jget`（量尺稿 §7 第 2 件），跨件不得漂移（BUG-330 同族）。
fn jget(j : Json, key : String) -> Json? {
  match j {
    Object(obj) => obj.get(key)
    _ => None
  }
}
