///|
/// 私有键访问辅助件（BUG-361 A 案 · `engine` **黑盒**作用域 · 批 8）。
///
/// 黑盒测试（`_test.mbt`）看不到包私有件（`json_get.mbt`），按量尺稿 §4
/// 作用域定律自带一份 —— `engine` 是黑盒站点最多的包（203 处，其中
/// `dag_ext_test.mbt` 单文件 75 处），这一份覆盖全部。
///
/// 语义与弃用体逐字等价：`if self is Object(obj) { obj.get(key) } else { None }`。
fn jget(j : Json, key : String) -> Json? {
  match j {
    Object(obj) => obj.get(key)
    _ => None
  }
}
