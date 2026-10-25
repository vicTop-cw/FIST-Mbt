///|
/// 私有键访问辅助件（BUG-361 A 案 · `store` 包作用域）。
///
/// **为什么需要它**：`Json::value` 在 core 里被标 deprecated（0020 弃用族），
/// 本仓 430+ 站点全靠它做键访问；而 core **不提供**任何现行替代键访问器。
/// 按 A 案口径，每个作用域持有一份私有件（不进公开 API、不进 `.mbti`、
/// 不参与发布产物），语义与弃用体逐字等价：
/// `if self is Object(obj) { obj.get(key) } else { None }`。
///
/// **命名一次定死**：`jget`（量尺稿 §7 第 2 件，实测与 core 的 `Json::get` 无冲突）。
/// 跨 15 份件改名是本仓已记过的漂移面（BUG-330 同族），不要再动。
///
/// **白盒可见、黑盒不可见**：`_wbtest.mbt` 能用本件；`_test.mbt` 看不到包私有件，
/// 故黑盒作用域另持一份 `json_get_test.mbt`（量尺稿 §4 作用域定律）。
fn jget(j : Json, key : String) -> Json? {
  match j {
    Object(obj) => obj.get(key)
    _ => None
  }
}
