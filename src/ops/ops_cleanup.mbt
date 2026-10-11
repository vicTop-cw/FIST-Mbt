/// ops_cleanup.mbt —— Archived 过期清理（M4 运维：归档回收）
///
/// 语义参考 FIST(Python) cleanup 模块（Archived 过期任务/历史回传的 DB 级清理）：
/// 已归档（Archived）且归档时间（updated_at）早于保留期（retention_days）的任务，
/// 通过 FistEngine::delete_task 物理删除。未归档任务一律不受影响（引擎层已限定）。

///|
/// 清理一轮：删除超过保留期的已归档任务。返回被清理的任务 id 列表。
pub fn cleanup_archived(
  engine : @engine.FistEngine,
  now : String,
  retention_days? : Int = 30,
) -> Result[Array[String], String] {
  let now_s = iso_to_secs(now)
  // R12-R6 bugfind（BUG-218 同族）：`retention_days * 86400` 无上界——
  // retention_days=25000 时 *86400 = 2.16e9 已接近 Int32 上界，
  // 再大一点（如 30000）就溢出。这里用 Int64 算阈值，再钳回 Int。
  if now_s < 0 || retention_days < 0 {
    return Err("cleanup: 非法时间戳或保留期")
  }
  // retention_days 上限：使 retention_days*86400 <= Int32 上界，即 <= 24855 天
  if retention_days > 24855 {
    return Err("cleanup: 保留期过大（>24855 天，会溢出 32 位秒数）")
  }
  let threshold = now_s - retention_days * 86400
  let removed : Array[String] = []
  for t in engine.list_all() {
    if t.get_status().to_string() == "已归档" {
      let ts_s = iso_to_secs(t.get_updated_at())
      // 时间戳不可解析（ts_s < 0）时保守不清理，避免误删
      if ts_s >= 0 && ts_s < threshold {
        match engine.delete_task(t.get_id()) {
          Ok(_) => removed.push(t.get_id())
          Err(e) => return Err(e)
        }
      }
    }
  }
  Ok(removed)
}
