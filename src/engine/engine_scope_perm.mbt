/// engine/engine_scope_perm.mbt —— 文件作用域权限门禁（军衔体制的第一层落地）
///
/// 背景：2026-10-21 40 个副机分支合并时发现，副机从老基线开分支、
/// 没 rebase、改了主机正在改的核心模块（store_sqlite.mbt / core_task.mbt / server.mbt），
/// 导致全仓 100% 冲突，自动解冲突还误丢了副机的 idiom 清理。
///
/// 根因：FIST-Mbt 有角色（HumanSteward/Leader/Executor）、军衔（L0-L7）、
/// 预订（reserve_scope）、锁（lock_acquire）——但**没有**目录→角色的权限映射，
/// 也**没有**在预订/锁获取时强制检查这个映射。
///
/// 本模块补上这个缺口：
///   1. 静态 scope→role 映射表（项目级"谁能改哪个目录"的宪法）
///   2. 权限检查函数 check_scope_permission(scope, agent_role)
///   3. 被 engine_rsv.rsv_try_set / locks_try_acquire 调用，
///      在"先到先得"之前，先过"你有没有资格改这个目录"的硬门
///
/// 这不是防并发冲突的唯一门禁——并发冲突靠预订/锁；这是**谁配不配改**的门禁。
/// 就像军队里炊事员不能进指挥中心，不是因为里面有人，是因为他没资格。

///|
/// 权限规则：pattern 是 glob 前缀（"src/core/" 匹配该目录所有文件）
struct PermissionRule {
  pattern : String
  allowed_roles : Array[String]
  reason : String
}

///|
/// 项目级"谁能改哪个目录"的宪法——所有角色向上开放，向下封锁。
/// Executor（士兵）只能改测试/守卫门脚本/文档/流水账；
/// Leader（军官）再加 src/router/engine/display + cli/moon.pkg；
/// HumanSteward（统帅）独占 store_sqlite.mbt、server.mbt、moon.mod。
pub let scope_permissions : Array[PermissionRule] = [
  // —— 统帅独占 ——
  PermissionRule::{
    pattern: "src/store/store_sqlite.mbt",
    allowed_roles: ["HumanSteward"],
    reason: "store_sqlite 是数据库层唯一真源，迁移逻辑不可逆",
  },
  PermissionRule::{
    pattern: "src/store/store.mbt",
    allowed_roles: ["HumanSteward"],
    reason: "Store trait = 整个存储层的抽象",
  },
  PermissionRule::{
    pattern: "src/server/server.mbt",
    allowed_roles: ["HumanSteward"],
    reason: "所有 MCP 工具注册 + 核心路由 = 对外接口契约",
  },
  PermissionRule::{
    pattern: "moon.mod",
    allowed_roles: ["HumanSteward"],
    reason: "模块版本 = 全仓编译的地基",
  },

  // —— 军官可改（统帅 + Leader）——
  PermissionRule::{
    pattern: "src/core/",
    allowed_roles: ["HumanSteward", "Leader"],
    reason: "Task/Store/DAG 核心数据结构签名变更，改了全仓编译炸",
  },
  PermissionRule::{
    pattern: "src/engine/",
    allowed_roles: ["HumanSteward", "Leader"],
    reason: "引擎层 = 工具调用的骨架",
  },
  PermissionRule::{
    pattern: "src/router/",
    allowed_roles: ["HumanSteward", "Leader"],
    reason: "模型路由/Star 门 = 成本 + 安全",
  },
  PermissionRule::{
    pattern: "src/display/",
    allowed_roles: ["HumanSteward", "Leader"],
    reason: "军衔/兵种/参谋 = 展示层唯一真源",
  },
  PermissionRule::{
    pattern: "cmd/",
    allowed_roles: ["HumanSteward", "Leader"],
    reason: "CLI 入口 = 用户启动的第一格",
  },
  PermissionRule::{
    pattern: "plugins/",
    allowed_roles: ["HumanSteward", "Leader"],
    reason: "插件态 = gen_plugins 投影，副机改了也会被覆盖",
  },
  PermissionRule::{
    pattern: "moon.pkg",
    allowed_roles: ["HumanSteward", "Leader"],
    reason: "子包依赖声明 = 编译拓扑",
  },

  // —— 全角色可改（统帅 + 军官 + 士兵）——
  PermissionRule::{
    pattern: "scripts/",
    allowed_roles: ["HumanSteward", "Leader", "Executor"],
    reason: "判据脚本 = CI 流程肌肉层，副机修复守卫门 bug 的主战场",
  },
  PermissionRule::{
    pattern: "docs/",
    allowed_roles: ["HumanSteward", "Leader", "Executor"],
    reason: "文档 = 全员可以写",
  },
  PermissionRule::{
    pattern: "memory/",
    allowed_roles: ["HumanSteward", "Leader", "Executor"],
    reason: "流水账 = 全员可以记",
  },
  PermissionRule::{
    pattern: "templates/",
    allowed_roles: ["HumanSteward", "Leader", "Executor"],
    reason: "模式模板 = 任何角色可以扩展",
  },
  PermissionRule::{
    pattern: "patches/",
    allowed_roles: ["HumanSteward", "Leader", "Executor"],
    reason: "依赖侧补丁 = 副机修依赖 bug 的主战场",
  },
]

///|
/// 从 agent 名字推断角色（宽松推断，不是安全门禁）。
/// fail-soft：宁可放行也不要卡死开发。
pub fn infer_role_from_agent(agent_name : String) -> String {
  let a = agent_name.to_lower()
  if a.contains("commander") || a.contains("human_steward") || a == "human" {
    "HumanSteward"
  } else if a.contains("leader") ||
    a.contains("lead") ||
    a.contains("polish") ||
    a.contains("optimization") {
    "Leader"
  } else {
    "Executor" // 默认最宽松
  }
}

///|
/// 判断 agent（按角色）是否有权限编辑 scope。fail-closed。
pub fn check_scope_permission(
  scope : String,
  agent_role : String,
) -> Result[PermissionRule, String] {
  let matched = find_matching_rule(scope)
  match matched {
    None =>
      Err(
        "拒绝：scope '" +
        scope +
        "' 无权限规则（fail-closed）。" +
        "指挥官需要在 engine_scope_perm.mbt 里加规则才能开放。",
      )
    Some(rule) => {
      let allowed = rule.allowed_roles.contains(agent_role)
      if allowed {
        Ok(rule)
      } else {
        Err(
          "拒绝：角色 '" +
          agent_role +
          "' 无权编辑 '" +
          scope +
          "'。" +
          "允许的角色：" +
          rule.allowed_roles.join(", ") +
          "；规则原因：" +
          rule.reason,
        )
      }
    }
  }
}

///|
/// 匹配规则——最长 pattern 优先（最具体的覆盖最宽泛的）。
fn find_matching_rule(scope : String) -> PermissionRule? {
  for rule in scope_permissions {
    if scope_matches_pattern(scope, rule.pattern) {
      return Some(rule)
    }
  }
  None
}

///|
/// glob 前缀匹配：pattern 带 "/" 后缀 → 匹配目录及子目录；
/// pattern 是文件路径 → scope 精确等于或以它开头。
fn scope_matches_pattern(scope : String, pattern : String) -> Bool {
  if pattern.has_suffix("/") {
    let prefix = pattern[0:pattern.length() - 1].to_owned()
    scope == pattern || scope.has_prefix(prefix)
  } else {
    scope == pattern || scope.has_prefix(pattern + "/")
  }
}
