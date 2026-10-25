///|
/// 私有键访问辅助件（BUG-361 A 案 · `store` **黑盒**作用域）。
///
/// 黑盒测试（`_test.mbt`）看不到包私有件（`json_get.mbt`），故按量尺稿 §4
/// 作用域定律自带一份 —— 实测「生产 + 黑盒」这组不冲突（rc=0 / 0 errors），
/// 「同包两份生产文件各写一份」才 declared twice。
///
/// 语义与包作用域件逐字相同：`if self is Object(obj) { obj.get(key) } else { None }`。
fn jget(j : Json, key : String) -> Json? {
  match j {
    Object(obj) => obj.get(key)
    _ => None
  }
}
