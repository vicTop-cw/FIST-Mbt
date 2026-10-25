///|
/// 私有键访问辅助件（BUG-361 A 案 · `evolve` **黑盒**作用域 · 批 2）。
///
/// `evolve` 包当前只有黑盒测试面用到 `.value(`（`critic_test.mbt` 10 处），
/// 无生产站点，故只建黑盒作用域这一份。若将来生产面出现站点，再补 `json_get.mbt`。
///
/// 语义与弃用体逐字等价：`if self is Object(obj) { obj.get(key) } else { None }`。
/// 命名一次定死为 `jget`（量尺稿 §7 第 2 件）。
fn jget(j : Json, key : String) -> Json? {
  match j {
    Object(obj) => obj.get(key)
    _ => None
  }
}
