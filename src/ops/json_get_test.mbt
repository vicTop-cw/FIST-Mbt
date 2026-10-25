///|
/// 私有键访问辅助件（BUG-361 A 案 · `ops` **黑盒**作用域 · 批 2）。
///
/// 黑盒测试（`_test.mbt`）看不到包私有件（`json_get.mbt`），按量尺稿 §4
/// 作用域定律自带一份；实测「生产 + 黑盒」这组不冲突（rc=0 / 0 errors）。
fn jget(j : Json, key : String) -> Json? {
  match j {
    Object(obj) => obj.get(key)
    _ => None
  }
}
