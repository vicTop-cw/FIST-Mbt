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
/// 从 agent 名字推断角色（**BUG-418 收窄 + BUG-421 二次收窄：只做缺省提示，不是授权依据**）。
///
/// ⚠️ BUG-418 前的实现用 `contains("commander")` 做**子串**匹配 ⇒
/// 任何自称 `commander-fake` 的 agent 都能拿到 HumanSteward，进而过 HumanSteward 保护门。
/// **那不是「文档不准」，是可主动利用的越权面。**
///
/// 收窄规则（BUG-418 裁决 (b) + BUG-421 收口，按「整名精确匹配」）：
///   · **禁止**「前缀/子串命中即给高角色」—— 这才是攻击面
///   · **只允许**人类指挥官的整名：`human_steward` / `human` ⇒ HumanSteward
///   · **其余一律 Executor**，**包括整名 `leader` / `lead`**（BUG-421）：
///     那两条白名单写于 BUG-418 修法期，理由是「关掉会把军官自报这条路关死」——
///     但「军官自报」本身就是「名字即身份」，与 BUG-418 要堵的是同一个东西，
///     只是从「任意子串」收窄成了「一个单词」。实测 `agent=leader` 可订
///     `src/engine/` / `src/core/` / `src/router/` / `cmd/`（军官面），
///     与「只有 human_steward/human 两个精确匹配算特权」的口径不一致。
///
/// ⇒ 现在 `leader` / `lead` / `LEADER` → Executor（与 `commander-fake` 同一档）
/// ⇒ `human_steward` / `human` → HumanSteward（人类指挥官唯一路径，保留）
///
/// ⚠️ **硬约束：角色不可从名字推断 Leader。Leader 只来自 `agents.role`（已登记身份）。**
/// 需要 Leader 面的 lane 必须在 `agents` 表被显式登记成 `role="Leader"`
/// （唯一入口是 server 启动注册；当前**没有**面向 agent 的自助登记工具面，
/// 这是 BUG-421 关闭后的既定代价 —— 见 memory/bugs.md BUG-421「风险」段与
/// reports/2026-10-27-bug421-decision-brief.md Q2 的步数推算）。
///
/// **权威面仍是 `agents.role`**（见 `resolve_agent_role`）：本函数只在查不到声明时做兜底，
/// 且回执会带 `role_source="inferred"` 让调用方知道这是猜的。
pub fn infer_role_from_agent(agent_name : String) -> String {
  let a = agent_name.to_lower()
  // 整名精确匹配（大小写已归一）。子串/前缀/军官单词一律不给高角色。
  if a == "human_steward" || a == "human" {
    "HumanSteward"
  } else {
    // ⚠️ 硬约束：此处**不得**再把军官单词（leader / lead）加回整名白名单 —— BUG-421 已删。
    // 判据：`engine_role_resolve_wbtest.mbt::role_resolve_wb3`（纯函数）+
    //       `engine_scope_perm_role_wbtest.mbt::scope_role_wb1/wb7`（端到端）+
    //       `scope_role_wb6` 的函数体扫描（源码级 tripwire）。
    "Executor"
  }
}

///|
/// 角色档位（数值越大权越大）。**未知/拼错的值一律 0（= Executor 档）—— fail-closed。**
///
/// 为什么需要它（BUG-422）：`resolve_agent_role` 要把「名字推断」当作**下限**，
/// 就不能再用字符串相等判「谁更高」。档位表是唯一真源，别处不要再手写比较。
pub fn role_rank(role : String) -> Int32 {
  match role {
    "HumanSteward" => 2
    "Leader" => 1
    "Executor" => 0
    _ => 0
  }
}

///|
/// **角色 → 军衔数字**（BUG-432 正解：`role → rank` 取代 `name → rank`）。
///
/// ⚠️ 别把本函数与 `role_rank` 混成一套：`role_rank` 是**角色档位**（数值越大权越大，2/1/0），
/// 本函数是 **claim 门用的军衔数字**（数值越小权越大，口径见 `rank_can_claim` 的
/// `arank == 0 || arank <= tlevel`）。两者方向**相反**，这正是 BUG-432 立案时被绕进去的地方
/// （抬头写「可能拿到更高档」，实测 rank 6 比默认档 5 **更低权**）。
///
/// | role | rank | 军衔 | 依据 |
/// |---|---|---|---|
/// | `HumanSteward` | 0 | 司令/统帅 | 人类指挥官通吃（与整名白名单 `human_steward`/`human` 同源） |
/// | `Leader` | 4 | 团长 | 军官线：**必须比默认执行者档(5)更高**。旧表把 `leader*` 判成 6（连长）⇒ 军官比普通执行者**更受限**，方向反转 |
/// | `Executor` | 5 | 营长 | 现网默认档，**逐字沿用** `estimate_rank` 的 else 分支 ⇒ 零回归 |
/// | 未知 / 空串 / 拼错 | 5 | — | fail-closed 到默认档：未知值**不提权**（也不误伤） |
///
/// **为什么 Executor 不是 7（排长）/8（士兵）**：门是 `arank <= tlevel`，现网 100% 任务 level=6
/// ⇒ rank 7 会让**所有** Executor 连 level=6 都领不了（门直接焊死，全仓 claim 全线 Err）。
/// 5 是现网实际生效的默认档，平移过来即零回归。
///
/// ⚠️ **硬约束：本函数只接受角色，永不接受「名字」**。`has_prefix("leader") ⇒ 6` 已随 BUG-432 删除；
/// claim 侧要拿军衔，必须先经 `judged_role`（登记优先 + 收窄后推断兜底）拿到角色。
/// 判据见 `claim_rank_wbtest.mbt` 的 G5（行为翻转锁）+ 入档回执里的变异对照（判例-29/30：
/// **不许**写「grep 源码有没有 has_prefix」那种会命中注释的自指判据 —— 它是恒绿的）。
pub fn rank_of_role(role : String) -> Int32 {
  match role {
    "HumanSteward" => 0
    "Leader" => 4
    "Executor" => 5
    // 未知值 ⇒ 默认档：不比今天更宽，绝不因未知/空值提权
    _ => 5
  }
}

///|
/// **哪些角色允许从「自报名字 → agents 登记表」这条路继承**（BUG-422 加固）。
///
///   · `Executor` / `Leader` ⇒ 可继承（Leader 是「派下来的军官」的唯一正道）
///   · `HumanSteward` 与任何未知值 ⇒ **None，永不继承**
///
/// 为什么把 HumanSteward 挡在继承面之外：HS 是**人类指挥官**的唯一身份，
/// 独占 4 条不可逆路径（`store_sqlite.mbt` / `store.mbt` / `server.mbt` / `moon.mod`）。
/// 「报一个已登记名字 ⇒ 继承它的 role」如果能把 HS 交出去，等于把 BUG-418
/// 刚关掉的统帅面从登记表那一侧又开回来，而且这次连 `human_steward` 这个整名都不用猜。
/// 现网 `agents` 表**没有任何 HS 记录**（`agent_touch_first_seen` 只写 Executor，
/// server 启动只写一条 Leader）⇒ 本限制的现实代价为 0，纯属把未来的口先堵上。
pub fn inheritable_role(declared_role : String) -> String? {
  match declared_role {
    "Executor" => Some("Executor")
    "Leader" => Some("Leader")
    _ => None
  }
}

///|
/// 解析 agent 的**裁决角色**与**来源**（BUG-418 裁决 (a) + BUG-422 B 案收口）。
///
/// **BUG-422 前的语义（已废）**：`agents.role` 无条件优先（`declared` > `inferred`）。
/// 那条规则的致命之处不在「读表」，而在**查表键是调用方自报的名字**：
/// 报 `agent="fist-mbt"` 就继承了 `server.mbt` 启动时写下的 `role="Leader"`（实测 ALLOWED）。
///
/// **现在的语义（三件硬约束，缺一不可）**：
///   1. **`inferred` 是下限** —— 声明**不许降级**：名字已经推出 HumanSteward 时，
///      一条 `role="Executor"` 的登记记录不能把它压回 Executor（BUG-423 的注册面毒化同族）。
///   2. **只有可继承角色生效** —— 见 `inheritable_role`：`Executor`/`Leader` 可继承，
///      `HumanSteward` 与未知值一律**忽略声明**（fail-closed 到推断）。
///   3. **声明必须来自「非本进程自身份」的登记记录** —— 这一条不在本纯函数里做，
///      而在它的**取数侧**：`engine_rsv.mbt` 的 `declared_role_for_judgment` 走
///      `SqliteStore::agents_role_for_judgment`，后者把 `agent_type == "server"` 的记录
///      整条剔除（那是**服务器自己**的身份，任何外部 agent 报它的名字都不该继承它）。
///      ⇒ 本函数保持纯、无 IO、可单测；「谁能被冒用」的政策落在 store 那一层，且有单测钉住。
///
/// 返回 `(role, source)`：
///   · `"declared"` = 裁决角色来自一条**通过上述过滤**的登记记录
///   · `"inferred"` = 没有可用声明（未登记 / 被过滤 / 角色不可继承 / 低于推断）
pub fn resolve_agent_role(
  agent_name : String,
  declared : String?,
) -> (String, String) {
  let inferred = infer_role_from_agent(agent_name)
  match declared {
    Some(r) =>
      match inheritable_role(r) {
        // 下限语义：声明只有**不低于**推断时才生效，永不允许把推断结果降级
        Some(d) =>
          if role_rank(d) >= role_rank(inferred) {
            (d, "declared")
          } else {
            (inferred, "inferred")
          }
        // HumanSteward / 未知值 / 空串：不可继承 ⇒ 退推断
        None => (inferred, "inferred")
      }
    None => (inferred, "inferred")
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
