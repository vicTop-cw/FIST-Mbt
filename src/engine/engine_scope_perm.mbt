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
/// 权限判定三态（BUG-413）——**三种拒绝面必须能被调用方区分**：
///   · Allowed        已登记且角色够格 ⇒ 正常预订
///   · RoleDenied     已登记但角色不够（HumanSteward 保护等）⇒ **必须继续拒绝，绝不放行**
///   · Unregistered   根本没有匹配规则 ⇒ advisory 登记，不参与授权裁决
///
/// 为什么必须拆开：旧实现把两种 Err 混成同一个 String，调用方无法分辨
/// 「这条路我不能碰」（有规则、我不够格）与「这条路没人管、你自己负责字面不相交」。
/// 后果是 explore 模式的第 4 道并行门恒不可过——`reports/` 这类未登记路径永远拿不到 granted。
///
/// **`Unregistered` 不是放行授权**：它只表示「预订登记成功」；
/// 真实写权限仍由 `RoleDenied` 那一侧决定（HumanSteward 保护路径照旧拒绝）。
///
/// 为什么 `Allowed` 不带 `PermissionRule` 载荷：`PermissionRule` 是包内私有 struct，
/// 作为 `pub enum` 的 variant 载荷会触发可见性错误。需要规则详情时用 `matching_rule()`。
pub enum ScopeVerdict {
  Allowed
  RoleDenied(String)
  Unregistered(String)
}

///|
/// agent 原始名 → 落库主键指纹（BUG-418）。
///
/// **为什么 engine 里要有这一份**：`server.mbt` 的 `agent_fp` 是**包内私有**
/// （`fn agent_fp(raw)`，无 `pub`），engine 包看不到它；而 `reserve_scope` 收到的
/// `agent` 是调用方自由填的**原始名**（文档示例就是 `exec_1`），
/// 而 `agents.agent_id` 落的是 16 位指纹。
///
/// ⇒ 想查 `agents.role` 必须先自己算指纹。**直接传原始名永远查不到**
/// （那会让「查权威角色」静默失效，等于没修）。实现必须与 `server.mbt` 逐字同构：
/// `@omega.fnv1a64("agent_id:" + raw)`。
///
/// 本条被白盒锁 `rswb_4` 钉住：断言「原始名查不到、指纹查得到」。
pub fn agent_fp_of(raw : String) -> String {
  @omega.fnv1a64("agent_id:" + raw)
}

///|
/// 从 agent 名字推断角色（**BUG-418 收窄后：只做缺省提示，不是授权依据**）。
///
/// ⚠️ BUG-418 前的实现用 `contains("commander")` 做**子串**匹配 ⇒
/// 任何自称 `commander-fake` 的 agent 都能拿到 HumanSteward，进而过 HumanSteward 保护门。
/// **那不是「文档不准」，是可主动利用的越权面。**
///
/// 收窄规则（BUG-418 裁决 (b)，按「整名精确匹配」而非「永不返回高角色」）：
///   · **禁止**「前缀/子串命中即给高角色」—— 这才是攻击面
///   · **允许**整名精确匹配：`human_steward` / `human` / `leader` / `lead`
///     人类指挥官与军官自报的就是这几个固定名字，关掉这条路会把合法路径一起关死
///   · 其余一律 Executor
///
/// ⇒ `commander-fake` → Executor（不再靠 commander 子串）；`human_steward` → HumanSteward（合法）
///
/// **权威面仍是 `agents.role`**（见 `resolve_agent_role`）：本函数只在查不到声明时做兜底，
/// 且回执会带 `role_source="inferred"` 让调用方知道这是猜的。
pub fn infer_role_from_agent(agent_name : String) -> String {
  let a = agent_name.to_lower()
  // 整名精确匹配（大小写已归一）。子串/前缀一律不给高角色。
  if a == "human_steward" || a == "human" {
    "HumanSteward"
  } else if a == "leader" || a == "lead" {
    "Leader"
  } else {
    "Executor"
  }
}

///|
/// 解析 agent 的**权威角色**与**来源**（BUG-418 裁决 (a)）。
///
/// 优先级：`agents.role`（显式声明，权威） > `infer_role_from_agent`（缺省提示）。
///
/// `declared` 由调用方查库传入（`agents_get(agent_id).role`），保持本函数纯、可单测、无 IO。
/// 查不到（None / 空串）⇒ 退到推断，且**推断结果只可能是 Executor 或 Leader**（见上）。
///
/// 返回 `(role, source)`，`source` ∈ {`"declared"`, `"inferred"`} ——
/// 调用方据此知道这个角色是**派下来的**还是**猜的**（BUG-418 的可观测性要求）。
pub fn resolve_agent_role(
  agent_name : String,
  declared : String?,
) -> (String, String) {
  match declared {
    Some(r) =>
      if r != "" {
        (r, "declared")
      } else {
        (infer_role_from_agent(agent_name), "inferred")
      }
    None => (infer_role_from_agent(agent_name), "inferred")
  }
}

///|
/// 判断 agent（按角色）是否有权限编辑 scope。
/// **不再用单一 `Result[_, String]` 表达三种不同结论** —— 见 `ScopeVerdict`（BUG-413）。
pub fn check_scope_permission(
  scope : String,
  agent_role : String,
) -> ScopeVerdict {
  match find_matching_rule(scope) {
    None =>
      Unregistered(
        "未登记：scope '" +
        scope +
        "' 无匹配权限规则 ⇒ advisory 登记（不参与授权裁决）；" +
        "并行时须自行保证与其他 lane 的文件字面不相交。",
      )
    Some(rule) =>
      if rule.allowed_roles.contains(agent_role) {
        Allowed
      } else {
        RoleDenied(
          "拒绝：角色 '" +
          agent_role +
          "' 无权编辑 '" +
          scope +
          "'。允许的角色：" +
          rule.allowed_roles.join(", ") +
          "；规则原因：" +
          rule.reason,
        )
      }
  }
}

///|
/// 取 scope 命中的规则（`Allowed` 之外的调用方若需要规则详情，走这里）。
pub fn matching_rule(scope : String) -> PermissionRule? {
  find_matching_rule(scope)
}

///|
/// 匹配规则——**最长 pattern 优先**（最具体的覆盖最宽泛的，BUG-419）。
///
/// 旧实现是「遍历 `scope_permissions`，第一条匹配即返回」，**结果依赖规则表顺序**：
/// 任何人把一条更宽的前缀规则（如 `src/` 保护整棵源码树）插到前面，
/// `src/store/store_sqlite.mbt`、`src/server/server.mbt` 这类 HumanSteward 独占规则
/// 就会被**静默遮蔽**成「Leader 也能改」——两个方向都无报错、无日志、无测试红。
///
/// 实测（BUG-419）：注入 `src/` 到表首后，旧实现让上述两个文件从 HumanSteward 独占
/// 降级为 Leader 可改（与 BUG-418 叠加 = 双重越权口）。
///
/// 现实现按 `pattern.length()` **降序遍历**，只取第一条（= 最长）匹配 ⇒ **对规则表顺序免疫**。
/// 用「只认最长那一条」而不是「收集全部再选」，是为了让语义与注释一致：
/// 最具体的规则**独占**裁决，不做多规则合并（合并会让权限面变成并集，更宽）。
fn find_matching_rule(scope : String) -> PermissionRule? {
  find_matching_rule_in(scope, scope_permissions)
}

///|
/// 同 `find_matching_rule`，但**接受显式规则表** —— 只供白盒锁构造「宽规则排在窄规则前面」
/// 的现场（判例-29：判据必须能测到实现，而不是只测现网那一份恰好正确的表）。
///
/// 生产调用一律只传 `scope_permissions`（见上一函数）⇒ 对现网零回归。
fn find_matching_rule_in(
  scope : String,
  rules : Array[PermissionRule],
) -> PermissionRule? {
  // 按 pattern 长度降序：最长 = 最具体。稳定排序保证同长度时保持原相对顺序。
  let ordered = rules.copy()
  ordered.sort_by(fn(a, b) {
    let la = a.pattern.length()
    let lb = b.pattern.length()
    if la > lb {
      -1
    } else if la < lb {
      1
    } else {
      0
    }
  })
  for rule in ordered {
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
