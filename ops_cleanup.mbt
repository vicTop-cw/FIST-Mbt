/// ops_cleanup.mbt —— Archived 过期清理（M4 运维：归档回收）
///
/// 语义参考 FIST(Python) cleanup 模块（Archived 过期任务/历史回传的 DB 级清理）：
/// 已归档（Archived）且归档时间（updated_at）早于保留期（retention_days）的任务，
/// 通过 FistEngine::delete_task 物理删除。未归档任务一律不受影响（引擎层已限定）。

/// 清理一轮：删除超过保留期的已归档任务。返回被清理的任务 id 列表。
pub fn cleanup_archived(
  engine : FistEngine,
  now : String,
  retention_days~ : Int = 30,
) -> Result[Array[String], String] {
  let now_s = iso_to_secs(now)
  if now_s < 0 || retention_days < 0 {
    return Err("cleanup: 非法时间戳或保留期")
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
