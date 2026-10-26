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
      //
      // BUG-417：但要排除「孤儿 Omega 任务」——本任务自己没开 omega（元数据列 = false），
      // 描述里的标记是从父层切片继承来的残留，且直接父任务已归档。
      // 父都没了 ⇒ 那棵树的验收语境已终结 ⇒ 继续要求它复验是判据错位
      // （与 BUG-389「标记被静默覆盖」正相反，本条是「标记被静默继承」）。
      let orphan = if omega_enabled(t) {
        let parent_st : @core.TaskStatus? = match t.get_parent() {
          None => None
          Some(pid) =>
            match self.get_task(pid) {
              None => None
              Some(p) => Some(p.get_status())
            }
        }
        omega_orphan_of_archived_parent(t, parent_st)
      } else {
        false
      }
      if omega_enabled(t) && !orphan {
        match self.omega_verify_gate(task_id) {
          Err(e) => return Err("Omega 门禁拦截归档: \{e}")
          Ok(_) => ()
        }
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
