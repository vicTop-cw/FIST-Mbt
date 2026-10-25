///|
/// 私有键访问辅助件（BUG-361 A 案 · `router` 包作用域）。
///
/// **为什么需要它**：`Json::value` 在 core 里被标 deprecated（0020 弃用族），
/// 本仓 430+ 站点全靠它做键访问；而 core **不提供**任何现行替代键访问器。
/// 按 A 案口径，每个作用域持有一份私有件（不进公开 API、不进 `.mbti`）。
/// 语义与弃用体逐字等价：`if self is Object(obj) { obj.get(key) } else { None }`。
///
/// **命名一次定死**：`jget`（量尺稿 §7 第 2 件）。
fn jget(j : Json, key : String) -> Json? {
  match j {
    Object(obj) => obj.get(key)
    _ => None
  }
}
