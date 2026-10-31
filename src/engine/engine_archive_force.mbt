/// engine_archive_force.mbt —— BUG-227 强制归档引擎旁路。
/// 独立新文件而非改动 engine.mbt：既有 archive 主流程保持零回归，
/// force 能力作为旁路方法挂载（同包可见 store 字段，复用 get_task/update_task）。
/// 权限与人类归档同门：仅 human_steward / human。

///|
/// 强制归档：force=false 与 FistEngine::archive 完全同义（含同一拒绝文案）；
/// force=true 放行 已暂停/已打回 僵尸任务直接入档（在流态仍拒，见 core Task::archive_force）。
pub fn FistEngine::archive_force(
  self : FistEngine,
  task_id~ : String,
  by~ : String,
  force~ : Bool,
  now~ : String,
) -> Result[@core.Task, String] {
  if by != "human_steward" && by != "human" {
    return Err("archive 仅限人类指挥官")
  }
  match self.store.get_task(task_id) {
    None => Err("task not found: \{task_id}")
    Some(t) => {
      if !force && !t.get_status().is_completed() {
        return Err(
          "仅已完成任务可归档，当前状态: \{t.status_to_string()}",
        )
      }
      // Omega 门（验收项：archive 不得绕过验收门）：强验证任务必须先过成果复验门，
      // force 也不能放行——归档即"了账"，未通过 Omega 门就是假了账。
      // 判定与 FistEngine::archive 同一真源（omega_archive_gate，含 BUG-417 孤儿豁免）：
      // 两条路径原先各写一份，第三条（publish_next_round 自动续轮）当时没门。
      match self.omega_archive_gate(t) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      let c = match t.archive_force(force~) {
        Ok(x) => x
        Err(e) => return Err(e)
      }
      let c2 = c.with_updated_at(now)
      match self.store.update_task(c2) {
        Ok(_) => ()
        Err(e) => return Err("归档落库失败: \{e}")
      }
      Ok(c2)
    }
  }
}
