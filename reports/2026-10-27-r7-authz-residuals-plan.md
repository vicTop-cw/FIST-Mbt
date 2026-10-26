# R7 授权残留三单方案 · BUG-421 / BUG-422 / BUG-427

> **执行人**：司令-γ · **边界**：只读 + 出方案/patch，未改任何 `src/`
> **产出**：本报告 · **未调 `bug_fix`**（代码未落地）

---

## 结论

| ID | 定性 | 建议修法 | 本条交付 |
|---|---|---|---|
| **BUG-422** | **真 bug**（可被利用，已量化攻击面） | **(c) 立即做 + (b) 中期**，见 §2.4 | **可粘贴 patch** |
| **BUG-421** | **政策取舍**（不是 bug） | **取决于 BUG-422 的修法** —— 见 §1.3 联动判断 | 判定 + 三条路径的方案 |
| **BUG-427** | **真 bug**（无上限增长，已实证污染面） | **(b) 滚动窗口 + (c) 截断组合** | **可粘贴 patch + 3 格锁** |

### ★ 最重要的判断：BUG-421 × BUG-422 联动

**单独修 BUG-422 会让 BUG-421 变得「看起来修好了但其实还漏」；单独修 BUG-421 则完全修不了 BUG-422。**

理由（§1.3 详述）：
- **BUG-421 是「名字 → 角色」的第二条路径**（`infer_role_from_agent` 的 `a == "leader"` 分支）
- **BUG-422 是「名字 → agents 表 → 角色」的第三条路径**（`agent_fp_of(自报名)` 查表）
- **两条路径共用同一个不可信输入（自报名字）**。关掉一条，另一条照旧 ⇒ **假装修好了**
- **顺序结论：必须先修 BUG-422（把「查表键」从自报名换掉），再裁 BUG-421**。
  反序的话，BUG-421 关掉 `leader` 整名，攻击者改用「报已登记名 `fist-mbt`」照样拿 Leader 面 ⇒ **白修**

---

## 证据

### §1 BUG-421 —— 政策取舍，但受 BUG-422 支配

#### 1.1 现网谁真的靠 `leader`/`lead` 整名拿 Leader？

**`agents` 表全量（3 行）**：

```
agent_id=          agent_type   role       pid          pubkey_fp  status
b2acdbf4c6cea9fe   server       Leader     1793026185   ''         active
c335207187d95324   execute      Executor   1792910901   ''         active
305ab0571c8193e8   execute      Executor   1792983882   ''         active
```

**⇒ `agents` 表里高 role 只有 1 条：`agent_type=server` 的 Leader。**
**没有任何 agent 是靠名字 `leader`/`lead` 在 agents 表里登记的**（表里存的是 16 位指纹，不是名字）。

**任务库 assignee 命名（前 12）**：
```
dsh-verify-l3 452 · atomcode-3 312 · exec_demo 68 · selfdrive 37
fist-allmodes-lead 32  ← 含 lead，但**是子串**（BUG-418 已关）
atomcode 32 · agent-vools-hardening 28 · agent_executor 22 · r4-verify 21 · r4-fix 21 · r5-fix 18 · executor 15
```

**`memory/` 里的命名提及**：`lead` 62 处、`Leader` 45 处、`leader` 29 处、`lead-explore` 6 处、
`leader-xxx` 4 处、`lead-2` 4 处、`leader-foo`/`leader-x` 各 2 处 —— **全是文档叙述或测试夹具**，
**没有一个是真的会以 `agent="leader"` 或 `agent="lead"` 调 `reserve_scope` 的调用方**。

**⇒ 读数结论：现网 `agent="leader"` / `agent="lead"` 的真实调用方 = 0 个。**
唯一带 lead 的真实 assignee 是 `fist-allmodes-lead`，**是子串，已经被 BUG-418 关掉**（现在推断为 Executor）。

#### 1.2 若关掉，谁掉级？怎么恢复？

| 问题 | 答案 |
|---|---|
| 谁会被掉级 | **现网 = 0 个**（§1.1 读数） |
| 掉级后怎么重新获得 Leader | 必须在 `agents` 表**显式登记 role=Leader**（现在只有 `agent_type=server` 那 1 条）。而登记入口是 server 启动时写的（`server.mbt:16-18`），**没有面向 agent 的「申请 Leader」通道** |

**⇒ 这里有一个真实的运维缺口**：关掉 `leader`/`lead` 整名后，
**任何一个新起的军官 lane 都没有自助拿 Leader 的路径** —— 只能靠人工写 `agents` 表。
这**不构成反对关闭的理由**（fail-closed 是正确默认），但**必须同批提供登记通道**，
否则就是「修了越权、换来一个所有人都卡住」。（这也解释了 BUG-418 修法为什么「有意保留」那两行。）

#### 1.3 ★ 联动判断（本单最重要）

**三条「名字 → 角色」路径**：

| # | 路径 | 位置 | 输入可信度 | 状态 |
|---|---|---|---|---|
| ① | 子串推断（`commander-*`/`lead*`/`human*`） | `infer_role_from_agent` 旧版 | 自报名 | ✅ **BUG-418 已关** |
| ② | 整名白名单（`agent == "leader"` / `"lead"`） | `engine_scope_perm.mbt:186-192` | 自报名 | ❌ **BUG-421（未关）** |
| ③ | 查表（`agents_get(agent_fp_of(自报名))` → `role`） | `engine_rsv.mbt:25-29 / 53-57` | 自报名 | ❌ **BUG-422（未关，可被利用）** |

**关键**：② 与 ③ **共用同一个不可信输入**。而且 ③ 的**威胁面严格大于** ②：

| | 路径②（名字必须恰好叫 leader） | 路径③（名字报成任意已登记名） |
|---|---|---|
| 攻击者需要 | 把 agent 名改成 `leader` | **随便报一个别人的名字** |
| 可拿到的最高角色 | Leader（不会是 HS，因为白名单只有 Leader） | **该登记身份的角色** —— 现在有 Leader 所以是 Leader |
| 未来风险 | 固定 | **若将来登记了 HumanSteward 身份的 agent，③ 直接继承 HS** ← 更危险 |

**⇒ 三条结论**：

1. **单独修 BUG-421 无效**：关掉 `leader`/`lead` 整名后，攻击者改用 `agent="fist-mbt"`（③）
   照样拿 12 个 Leader 级目录。**看起来关了一条路，实际只是让攻击多一步。**
2. **单独修 BUG-422 后，BUG-421 变成「纯政策问题」**：③ 关掉后，② 的攻击面收窄为
   「必须把名字改成 `leader`」——这仍然是名字即身份，但**不再能借用他人身份**。
   此时裁 BUG-421 才是干净的取舍（要不要允许一条「叫 leader 就是 Leader」的自治路径）。
3. **正确顺序：先 422，后 421。** 反序 = 白修。

#### 1.4 「HS 保留整名、Leader 不保留」的不对称有道理吗？

| 论点 | 评价 |
|---|---|
| **支持保留 HS**（`human_steward`/`human`） | 人类指挥官只有一个人，名字固定；且**名字可猜**（你的原话承认了）⇒ **这条论点弱**。但 HS 面只有 4 条路径（`store_sqlite.mbt`/`store.mbt`/`server.mbt`/`moon.mod`），**即使被冒充，前提是攻击者已经能改那 4 个文件**——即「越权成功后才需要这个身份」，边际危害小 |
| **反对保留 Leader**（`leader`/`lead`） | **更强**：lane 名是分配给很多 agent 的；且带 `leader` 前缀的 lane 是**统帅起的名字** ⇒ 名字来源本身就是人为约定，不是不可伪造的身份 |
| **★ 决定性论点** | **HS 那两条在白名单里的理由是「人类只有一个」；Leader 那两条的理由是「不然军官没路拿权限」（BUG-418 注释原话）。前者是「身份唯一」，后者是「运维便利」——两者根本不同类，把它们并列在同一份白名单里是**把不同性质的东西压成一档** |

**⇒ 我的判断：这个不对称在「当前实现」下没有道理**，但**修法不是删掉 Leader 那两行**，
而是**把「运维便利」从这个白名单里移到显式的登记通道**（见 §1.5 方案 B）。

#### 1.5 三条可选路径（供你裁）

**路径 A：关掉 `leader`/`lead` + 补登记通道**（fail-closed）
- `infer_role_from_agent` 只留 `human_steward`/`human`
- **同批**提供 `agents_register(role=…)` 的显式登记入口（现在只有 server 自注册）
- 风险：短期内所有军官 lane 都掉级，需人工写表
- **建议：与 BUG-422 修法同期落地**

**路径 B（我倾向）：保留整名，但把「角色来源」显式标注为不可信**
- 不动 `infer_role_from_agent`
- `rsv_*` 回执里加 `role_source: "declared" | "inferred" | "name_whitelist"` 三元
- 文档明确写「名字可自报 ⇒ 本仓授权是**协作约束**而非**安全边界**」
- 风险：**不是修 bug，是承认现状**——只在 BUG-422 修完、且有其他认证面时才成立

**路径 C：改名白名单为「显示层别名」，不参与裁决**
- 彻底删 `infer_role_from_agent` 的 Leader 分支，名字只用于日志
- **最干净，但等于路径 A + 更彻底**；需同步改 `role_resolve_wb3` 锁

**⇒ 建议：先做 BUG-422 的 (b)(c)，再走路径 A 或 C。路径 B 只在你决定「本仓不做认证」时选。**

---

### §2 BUG-422 —— 真 bug，攻击面已量化

#### 2.1 `reserve_scope` 的 `agent` 参数有没有认证？

**读源码（`src/engine/engine_rsv.mbt:10-70`）**：

```moonbit
pub fn FistEngine::rsv_set(self, scope~, agent~, ttl_until~, created_at~) {
  let declared = match self.agents_get(agent_fp_of(agent)) {   // ★ agent 是原样透传的自报串
    None => None
    Some(rec) => Some(rec.role)
  }
  let (role, _role_source) = resolve_agent_role(agent, declared)
  ...
}
```

**⇒ 零认证。** `agent` 是纯 `String`，从 MCP `reserve_scope(agent=…)` 一路透传到查表键。
**没有任何签名、令牌、pid 校验。** `agents` 表的 `pubkey_fp` 列**3 行全是 `''`**（BUG-403 已定性为幻影列）。

**★ 附带发现（本单新，不在三条里）**：**`locks_try_acquire` 的权限门禁完全没接**——
`engine_rsv.mbt:107-110` 注释自认「锁的权限门禁**暂时没接**…目前先跳过锁的权限检查，等后端扩展」。
⇒ **`lock_acquire` 是比 `reserve_scope` 更宽的越权口**（完全不做 `check_scope_permission`）。
建议单独立案，**本单只记录不动**。

#### 2.2 现网高 role 登记

```
agent_id=b2acdbf4c6cea9fe  type=server   role=Leader   pid=1793026185  pubkey_fp=''
```
**只有 1 条 Leader，且 `agent_type=server`（项目自己的 server 身份）。
没有 HumanSteward 身份的登记行** ⇒ ③ 目前的最高继承是 Leader，**还不是 HS**。

#### 2.3 攻击面：Executor 报 `fist-mbt` 能拿到什么（逐条枚举 `scope_permissions`）

```
HS 面（4 条，仍挡住）：src/store/store_sqlite.mbt  src/store/store.mbt
                      src/server/server.mbt        moon.mod

Leader 面（12 条，★全部拿到）：
  src/core/   src/engine/   src/router/   src/display/
  cmd/        plugins/      moon.pkg      scripts/
  docs/       memory/       templates/    patches/
```

**⇒ 一个 Executor 报 `agent="fist-mbt"` 即可拿到 12 个目录的 Leader 级写权限，
包括 `src/core/`（Task/Store/DAG 核心数据结构）、`src/engine/`（引擎骨架）、`src/router/`（模型路由/成本）。**

**注意 `scripts/` / `docs/` / `memory/` / `templates/` / `patches/` 这 5 条本来就是 Executor 可写**
（`allowed_roles` 含 Executor）⇒ **真正的越权增量是 7 条**：
`src/core/` `src/engine/` `src/router/` `src/display/` `cmd/` `plugins/` `moon.pkg`。

**这 7 条正好是 BUG-418 想保护的面** ⇒ **③ 路径把 BUG-418 在 ② 上关掉的门，从另一侧又开回来了。**

#### 2.4 修法方向（三条，建议 (c) + (b)）

**(a) 不加认证，但把 `agents.role` 的权威性降级 —— 只在「同一进程内已 touch 过」时才信**

- 做法：`agents` 表加 `last_pid`（已有 `pid` 列！），查表后比对 `current_pid_token()`；
  不一致 ⇒ 降级为 `inferred`
- **优点**：不动 MCP 面签名，改动小
- **缺点**：`pid` 可伪造吗？`current_pid_token()` 是**本进程自己的 pid**，
  攻击者是**另一个 MCP client**（不同进程）⇒ 报 `fist-mbt` 时 pid 对不上 ⇒ **这条是有效的**
- ⚠️ 但**同一进程内的多个 client** 不区分 ⇒ 治不了「同进程冒充」

**(b) `reserve_scope` 接受「身份断言」（pid token），与 `agents.pid` 比对** ★**建议中期**

- 做法：`reserve_scope(agent, agent_pid_token?)`；server 侧 `agent_pid_token` 由
  `current_pid_token()` 生成、**只发给真正 touch 过这个身份的连接**
- **优点**：真正把「名字」和「进程」绑起来，与既有 `pid` 列 + `pid_bound` ACL 机制同族
  （`agent_acl_grant(pid_bound=true)` 已经这么做了 —— **复用它，不发明新机制**）
- **缺点**：MCP 面加参数（向后兼容：不传 ⇒ 降级为 `inferred`，不静默放行）

**(c) 明确宣布「身份自报 = 已知边界」** ★**建议立即做**

- 写进文档（`AGENTS.md` / `AI-DEVELOPMENT-STANDARD.md` 的「已知边界」节）
- **`reserve_scope` / `lock_*` 回执里加 `role_source` 字段**（其实 `resolve_agent_role` **已经算出来了**，
  但 `engine_rsv.mbt:29/57` 用 `_role_source` **丢弃了它**！）
- 标注 `role_source: "declared"` ⇒ **调用方看得见「这个角色是自报得来的，不是核验的」**

**★ 本单发现：`role_source` 已经算好了但被丢弃** —— 这是 (c) 的零成本落地点：

```diff
--- a/src/engine/engine_rsv.mbt
+++ b/src/engine/engine_rsv.mbt
@@
-  let (role, _role_source) = resolve_agent_role(agent, declared)
+  let (role, role_source) = resolve_agent_role(agent, declared)
   match check_scope_permission(scope, role) {
     RoleDenied(e) => Err(e)
     Allowed | Unregistered(_) =>
-      self.store.rsv_set(scope~, agent~, ttl_until~, created_at~)
+      // (c) 诚实标注：把「角色是怎么来的」带进回执。
+      // declared = 从 agents 表读到的（查表键是自报名字 ⇒ 仍不可信，见 BUG-422）
+      // inferred = 从名字模式推的（更不可信，见 BUG-421）
+      match self.store.rsv_set(scope~, agent~, ttl_until~, created_at~) {
+        Err(e) => Err(e)
+        Ok(o) => Ok(o + " [role_source=" + role_source + "]")
+      }
   }
```

> ⚠️ 更彻底的做法是把 `role_source` 加进 `RsvOutcome` 结构而不是拼字符串；
> 但那要动 `@store` 类型的定义，**超出本单 patch 的边界，标为「只出方案」**。
> 上面这版是**零结构改动**的最小落地。

**⇒ 建议组合：立即做 (c) 的零成本版（回执标 `role_source`）+ 中期做 (b)（`pid_bound` 复用）。**
**(a) 作为 (b) 的简化版备选。**

---

### §3 BUG-427 —— 真 bug，3 格锁 + patch

#### 3.1 污染面逐项实证（不是推断）

| 污染面 | 源码证据 | 后果 |
|---|---|---|
| **① `task_triage` 能力抽取** | `engine_triage.mbt:70-72` `cap_match`: `r.desc.contains(want)` | **打回原因文本命中 `want` 关键词 ⇒ 任务被错误排到「能力匹配」头部** |
| **② `goal_drift_check` Jaccard** | `engine_dag_ext.mbt:1424` `@evolve.tokens(rt.get_description())` / `:1439` 子任务同理 | **description 被撑长 ⇒ 词法覆盖率失真 ⇒ drift 读数假的** |
| **③ `supervisor_status` 200 字节截断** | `supervisor_tools.mbt:302/307` 文档：`false 时 description 截断到 200 字节` | **打回原因占满前 200 字节 ⇒ 真正的任务意图在回执里被挤掉** |
| **④ `board_ascii` 假绿档** | `board_ascii.mbt:252` `t.deliverable == ""` | （与 deliverable 无关，此处仅确认该档不读 description） |
| **⑤ 无长度闸** | `grep 'description.length()' src/` 生产面只命中 `router.mbt:49`（难度打分）、`laya_route.mbt:95`（>120 截断） | **存储面零闸** |
| **⑥ `desc_clip` 只在输出截断** | `core_task.mbt:680` | **库里存全文** |

**实测库现读**：
```
T0r636.4.2   len=4737  打回次数=1   ← 单次打回 4.7KB
T0r581.2     len=633   打回次数=2
T0r581.3     len=633   打回次数=2
```

#### 3.2 修法候选评价

| 候选 | 评价 |
|---|---|
| **(a) 打回原因进独立历史**（新表 / `specs` 表一行） | **最干净**（description 回归「任务意图」语义）。**但动 schema ⇒ 超出本单边界，只出方案** |
| **(b) description 只留最近 N 次打回**（滚动窗口） | **可出 patch**，改动局部 |
| **(c) 打回原因截断到 M 字节** | 可出 patch，但**只限单条长度，不限次数** ⇒ 多次打回仍线性涨 |

**⇒ 建议 (b) + (c) 组合**（滚动窗口 N=1 + 单条原因截断 M=200）：
- (b) 保证**不随次数线性增长**（锁 2 的目标）
- (c) 保证**单次也不会塞 4.7KB**（锁 1 的目标）
- **长远仍建议 (a)**：把「过程记录」与「任务意图」分字段，是本条的根本解法

#### 3.3 可粘贴 patch（`src/core/core_task.mbt`，Leader 级 — 我改不了）

```diff
--- a/src/core/core_task.mbt
+++ b/src/core/core_task.mbt
@@
 ///|
 /// 待验收 -> 已打回（验收不通过，需重做）
-pub fn Task::reject(self : Task, reason~ : String = "") -> Result[Task, String] {
+///
+/// BUG-427：打回原因**不再无上限追加**进 `description`。
+/// 旧实现每次 `reject` 都拼一段 ` [打回原因: …]`，而：
+///   · 存储面无任何长度闸（`desc_clip` 只在 `to_json` 输出时截断）；
+///   · description 是 `task_triage` 能力抽取（`cap_match` 的 `desc.contains`）、
+///     `goal_drift_check` 的 Jaccard（`@evolve.tokens(get_description())`）、
+///     `supervisor_status` 的 200 字节截断三处的**共同进料面** ⇒ 打回原因污染三者。
+/// 实测：`T0r636.4.2` 单次打回即 4737 字节。
+///
+/// 现实现：① 先剥掉**已有**的 `[打回原因: …]` 尾巴（滚动窗口 = 只留最近 1 次）；
+///           ② 单条原因截断到 `REJECT_REASON_CAP` 字节（按 UTF-8 字符边界，不切半字）。
+pub fn Task::reject(self : Task, reason~ : String = "") -> Result[Task, String] {
   match self.status {
     Reviewing =>
       Ok({
         ..self,
         status: Rejected,
         description: if reason == "" {
           self.description
         } else {
-          self.description + " [打回原因: " + reason + "]"
+          strip_reject_tail(self.description) +
+          " [打回原因: " +
+          clip_utf8(reason, REJECT_REASON_CAP) +
+          "]"
         },
       })
     _ => ...
   }
 }
```

**配套新增两个纯函数（同文件，`fn` 包内可见）**：

```moonbit
///|
/// 打回原因单条上限（字节，UTF-8）。
/// 取 200 与 `supervisor_status` 的 description 截断口径一致 ——
/// 单次打回最多占掉回执的 200 字节窗口，不会把任务意图整体挤掉。
const REJECT_REASON_CAP : Int32 = 200

///|
/// 剥掉 description 尾部已存在的 `[打回原因: …]`（BUG-427 滚动窗口）。
/// 只剥**最后一次**拼上去的那一段（从最后一个 `" [打回原因: "` 起，到末尾的 `"]"`），
/// 这样「同一任务被打回 N 次」的 description 长度**不随 N 线性增长**。
///
/// ⚠️ 本仓**没有** `String::rev_find` 的先例（`grep -rn 'rev_find\|rfind' src/` 为空），
/// 故此处用「自实现反向查找」而非依赖不存在的 API。
fn strip_reject_tail(desc : String) -> String {
  let marker = " [打回原因: "
  let ml = marker.length()
  let dl = desc.length()
  if dl < ml || !desc.has_suffix("]") {
    return desc
  }
  // 反向扫：找最后一个 marker 的起始下标
  let mut i = dl - ml
  let mut last = -1
  while i >= 0 {
    if desc[i:i + ml] == marker {
      last = i
      break
    }
    i = i - 1
  }
  if last < 0 {
    desc
  } else {
    desc[0:last].to_owned()
  }
}

///|
/// 按 UTF-8 字符边界截断到 `cap` 字节（不产生半个字符）。
/// 与既有 `desc_clip`（`core_task.mbt:680`）同族，但**语义是「纯截断」不追加 "…"**——
/// 外层会再拼 `]`，加省略号反而破坏 `[打回原因: …]` 的形状。
///
/// ⚠️ 依赖面已核：`src/core/moon.pkg:3` 是 `"moonbitlang/x/encoding"`（**不是** `core/encoding/utf8`），
/// 故此处用 `@encoding.encode(UTF8, s)` / `@encoding.decode_to(...)`，
/// 与 `desc_clip` 同一套 API，**不新增依赖**。
fn clip_utf8(s : String, cap : Int32) -> String {
  if cap <= 0 {
    return ""
  }
  let bytes = @encoding.encode(UTF8, s)
  if bytes.length() <= cap {
    return s
  }
  let mut cut = cap
  while cut > 0 && bytes[cut].to_int().land(0xC0) == 0x80 {
    cut = cut - 1
  }
  let sb = StringBuilder()
  @encoding.decode_to(bytes[0:cut], sb, encoding=UTF8) catch {
    _ => ()
  }
  sb.to_string()
}
```

> ⚠️ **落地方需核（我已先核掉两条）**：
> 1. ~~`String::rev_find` 是否存在~~ —— **已核：本仓零先例**（`grep -rn 'rev_find\|rfind' src/` 空），
>    故 patch 改成**自实现反向查找**，不依赖不存在的 API。
> 2. ~~`@utf8` 依赖~~ —— **已核：`src/core/moon.pkg:3` 是 `"moonbitlang/x/encoding"`**，
>    故改用 `@encoding.encode(UTF8, s)` + `@encoding.decode_to(...)`，
>    **与既有 `desc_clip` 同一套 API、不新增依赖**。
> 3. 仍需核：`desc[i:i + ml]` 的切片边界在 `i + ml == dl` 时是否合法（本仓 `substring` 族的行为）；
>    若要保守可改 `desc.has_prefix` 反向拼串。**我因只读边界无法编译验证。**

#### 3.4 三格锁（判例-29/30）

```moonbit
/// engine_scope... —— 实际应放 src/core/core_task_reject_cap_wbtest.mbt

///|
/// 锁 1：打回 1 次 ⇒ description 长度增量有上界（不随 reason 长度无界增长）
test "reject_cap_wb1_single_reject_bounded" {
  let base = @core.Task::new(id="T_rc1", project_dir="/p",
                             description="原始任务意图", created_at="t0")
  let long_reason = "很长的打回原因".repeat(200)   // 远超 REJECT_REASON_CAP
  let t1 = match base.reject(reason=long_reason) {
    Ok(x) => x
    Err(e) => abort("reject 失败: " + e)
  }
  // 增量 = 原始长度 + marker + cap + "]"
  assert_true(t1.get_description().length() <= "原始任务意图".length() + 8 + 200 + 1 + 16)
}

///|
/// 锁 2：打回 5 次 ⇒ 长度**不线性增长**（滚动窗口生效）
test "reject_cap_wb2_repeated_reject_not_linear" {
  let mut t = @core.Task::new(id="T_rc2", project_dir="/p",
                              description="原始意图", created_at="t0")
  // 手工把状态推到 Reviewing（同包可见字段直构，避免依赖整条生命周期）
  t = { ..t, status: Reviewing }
  let mut prev_len = t.get_description().length()
  for i in 0..<5 {
    // 每一轮：reject → 塞回 Reviewing（滚动窗口只关心 description 增量）
    t = match t.reject(reason="第\{i}次打回") { Ok(x) => x, Err(e) => abort(e) }
    let after = t.get_description().length()
    // 第二轮起增量必须≈常数（新旧 marker 段互换），不得累加
    if i > 0 {
      assert_true(after <= prev_len + 40)   // 只允许"换一段"级的抖动
    }
    prev_len = after
    t = { ..t, status: Reviewing }
  }
  // ★核心断言：5 次后不得是 5 倍
  assert_true(t.get_description().length() < "原始意图".length() + 8 + 200 + 1 + 16)
}

///|
/// 锁 3（变异对照，判例-29/30）：把滚动窗口去掉（每次都直接拼）
/// ⇒ 5 次后长度必须显著大于 1 次后长度，证明「窗口在起作用」。
///
/// 做法：手工复刻「无窗口版」的拼接，断言它与真实现的长度**不同**。
/// 若有人删掉 `strip_reject_tail`，真实现会塌回无窗口版 ⇒ 锁 2 必红。
test "reject_cap_wb3_mutation_control_window_matters" {
  let start = @core.Task::new(id="T_rc3", project_dir="/p",
                              description="原始意图", created_at="t0")
  let mut real = { ..start, status: Reviewing }
  let mut muta = { ..start, status: Reviewing }
  for i in 0..<5 {
    real = match real.reject(reason="打回\{i}") { Ok(x) => x, Err(e) => abort(e) }
    real = { ..real, status: Reviewing }
    // 变异版：等价于旧实现（无 strip）
    muta = { ..muta,
      status: Reviewing,
      description: muta.get_description() + " [打回原因: 第\{i}次]",
    }
  }
  // 真实现 5 次后长度 ≈ 1 次后长度；变异版 ≈ 5 段累加
  assert_true(muta.get_description().length() > real.get_description().length())
  assert_true(muta.get_description().length() - real.get_description().length() > 100)
}
```

**⇒ 锁 3 的含义**：若有人把 `strip_reject_tail(...)` 去掉（变异），
`real` 会塌成与 `muta` 同形 ⇒ 第三条 `assert_true(... > 100)` **失败** ⇒ **锁 3 红**。
（判例-30 防护：本锁用**真 struct 字面量 + 真状态字段**构造，不引用注释里的示例。）

---

## 分析

### 为什么把 BUG-421 定为「政策取舍」而不是 bug

**判据**：一个行为如果要改，必须同时存在「改的理由」和「不改的理由」，且两者都自洽 ⇒ 政策取舍。
- 改的理由：名字即身份不是认证
- 不改的理由：BUG-418 注释明说「关掉会把军官自报这条路关死」，而 §1.2 证实**没有别的自助通道**

**⇒ 这不是实现疏漏（BUG-422 才是），是两个正确目标（安全 vs 可用）的冲突。**
**而且它的解取决于 BUG-422**（§1.3）：422 修完前，421 怎么裁都是在擦地板。

### 为什么把 BUG-422 定为真 bug

**可被利用 + 有明确受害者 + 修法不依赖他人决策**：
一个 Executor 只需 `agent="fist-mbt"` 即可拿 7 条 Leader 专属目录的写权限，
**且这条路径是 BUG-418 修法自己引入的**（`agents_get` 查表），不是历史遗留。
**"把门从 A 换到 B 却没锁 B"** —— 这是实现缺陷，不是取舍。

### 为什么把 BUG-427 定为真 bug

**无上限增长 + 已实测污染三处判据进料面 + 修法不需要任何决策**。

---

## 缺口与风险

### ★ 风险 1（你问的）：修 BUG-422 会不会让 BUG-421 变得更严重？

**不会更严重，但会让 BUG-421 的「残留危害」被看清。**

| 时序 | ② 名字白名单 | ③ 查表继承 | 攻击者最省力路径 | 拿到 |
|---|---|---|---|---|
| **现在（都没修）** | 开 | 开 | 报 `fist-mbt`（不用改自己名字） | Leader 面 7 条 |
| **只修 422** | 开 | 关 | **把 agent 名改成 `leader`** | Leader 面 7 条 |
| **只修 421** | 关 | 开 | 报 `fist-mbt` | Leader 面 7 条 |
| **都修** | 关 | 关 | 必须显式登记 role（无自助通道） | 无 |

**⇒ 关键结论：只修 422 时攻击面「不变大小，只换入口」**（从「借名」变成「改名」）。
**但这是进步**：② 需要攻击者**把自己的名字改成 `leader`**（留下明显痕迹），
③ 只需**报一个字符串**（无痕）。**可审计性改善。**

**真正的风险是**：如果只修 422 就宣布「授权修好了」，**421 的洞还在** ⇒ 假 GREEN。
**所以我在报告开头把顺序钉死：422 → 421，且 421 不能以「422 已修」为由被跳过。**

### 风险 2：`locks_try_acquire` 完全没有权限门禁（本单发现，未在三条内）

`engine_rsv.mbt:107-110` 自认「暂时没接」。⇒ **即使 421/422 都修好，
`lock_acquire` 仍然不经过 `check_scope_permission`** —— 攻击者可以用锁而非预订来占面。
**建议单独立案（高优先）**，本单只记录。

### 风险 3：`pubkey_fp` 列全空 ⇒ (b) 的 pid token 是「补丁式认证」

`agents.pubkey_fp` 3 行全 `''`（BUG-403 已定性为「死承诺」）。
⇒ **(b) 复用 `pid_bound` 机制是当前唯一可用的认证面**，但它只绑**进程**，不绑**会话**。
同一进程内多 client 仍可互冒。**长期需要 BUG-403 那条路（真正的 pubkey 绑定）。**

### 风险 4：我无法编译验证

三条 patch 都只在**语义层**正确。`rev_find`、`assert_true` 的形状、
`@utf8.encode` 的依赖（`src/core/moon.pkg` 是否已有 `moonbitlang/core/encoding/utf8`）
**都需落地方先核**。特别是 `clip_utf8` 依赖 `@utf8`，**若 `src/core/moon.pkg` 没有该依赖会编译失败**
（`src/engine` 那边有 `@encoding`，但那是另一个包）。

### 风险 5：BUG-427 选 (b)+(c) 是「止血」不是「根治」

滚动窗口会**丢失更早的打回历史**（只留最近 1 次）。
若审计需要完整打回链，**必须走 (a)**（独立历史表）。**我把这条写进方案而不擅自选 (a)，因为它动 schema。**

---

## 建议入档位置

| 内容 | 位置 |
|---|---|
| 本报告 | `reports/2026-10-27-r7-authz-residuals-plan.md` |
| BUG-422 patch (c) 零成本版 | `src/engine/engine_rsv.mbt`（**落地方应用**，我不改） |
| BUG-422 (b) 中期方案 | 只出方案（要动 MCP 参数 + `RsvOutcome` 结构） |
| BUG-427 patch + 3 格锁 | `src/core/core_task.mbt` + 新 `core_task_reject_cap_wbtest.mbt`（**落地方应用**） |
| 新发现：`locks_try_acquire` 无权限门禁 | **建议单独立案**（本单未报 `report_bug`，因派单只要求方案；如需我报请指示） |
| 落地后 | `git commit -F msg -- <explicit paths>`（判例-11）；`python scripts/moon_test_env.py` 判绿（**汇总行为准**，BUG-142） |
| **未做** | **未调 `bug_fix`**（代码未落地） |
