/// decompose.mbt —— AO orchestrator 式递归任务拆解器（M3：AO 式拆解）
///
/// 语义参考 agent-orchestrator（backend/internal/skillassets/using-ao/commands）：
///   1. orchestrator：持久规划 agent，把 plan 拆成 focused tasks
///      —— 映射为 FistEngine::plan_deep 递归拆解器；
///   2. project add：注册仓库 + 配置 worker/orchestrator rules
///      —— 联动：根任务 project_dir 落库，拆出的子任务继承 project_dir，
///         供执行者 claim / execute（即 AO spawn 派发 worker）；
///   3. spawn：派发 worker —— 拆出的子任务挂 parent_id/depth，由执行者 claim；
///   4. review：按 omega spec 验收 —— 每条拆解依据带 spec_hash
///         （取 spec.fingerprint 作验收基准，供后续 omega_verify 对照）。
///
/// 结构定位（拳长那套分层递归）：根任务 depth=K，每拆一层减 1，
/// is_leaf = depth<=1 即停止；任一层可被下一层拳长继续递归拆分。
/// 全过程写 StoreBackend（SQLite 内建数据库），重启后经 get_task 即可恢复完整子树
/// （M3 验收标准）。

/// 从 omega spec JSON 提取切割依据（slices）。
/// 规则：
///   - spec 为对象且 laws 为非空字符串数组 → 以 laws 为准（AO "break into focused
///     tasks"：每条 law 一个聚焦子任务，等价于把 plan 拆成可执行单元）；
///   - 否则 → 退化为按 split_n 生成通用拆解条目。
/// 返回切片描述数组。
pub fn decompose_slices(spec : Json, split_n : Int, parent_desc~ : String) -> Array[String] {
  match spec {
    Object(_) =>
      match spec.value("laws") {
        Some(Array(laws)) => {
          let out : Array[String] = []
          for l in laws {
            match l {
              String(s) if s.trim() != "" => out.push(s)
              _ => ()
            }
          }
          if out.is_empty() {
            default_slices(split_n, parent_desc=parent_desc)
          } else {
            out
          }
        }
        _ => default_slices(split_n, parent_desc=parent_desc)
      }
    _ => default_slices(split_n, parent_desc=parent_desc)
  }
}

/// 无 spec.laws 时的通用切分条目（描述逐层递进派生）。
pub fn default_slices(split_n : Int, parent_desc~ : String) -> Array[String] {
  let out : Array[String] = []
  for i = 1; i <= split_n; i = i + 1 {
    out.push("\{parent_desc} - 子任务单元 \{i}")
  }
  out
}

/// 取 spec 的 fingerprint 作为验收基准 spec_hash；无 spec / 无 fingerprint 为空串。
pub fn spec_hash_of(spec : Json?) -> String {
  match spec {
    Some(s) =>
      match s.value("fingerprint") {
        Some(String(f)) => f
        _ => ""
      }
    None => ""
  }
}
