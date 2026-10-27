# BUG-430 的 S1/S2/S3 落地计划

> **日期**：2026-10-27 · **执行**：Lane AR · 未改 `src/` `scripts/` 任何文件

---

## ⚠️ 开头必须说清

> **BUG-430 不是「修完就安全」的 bug，它是承认一个已知边界：MCP 工具面没有认证层。**
> **S1 做完后系统仍然不安全 —— 只是「不安全」变得可见。**
> **S2 做完仍不安全**（未登记者被拒 ≠ 已登记者不可冒充）。**只有 S3 改变安全属性。**

**建议：S1 落地后 BUG-430 保持 OPEN，状态 `[arch] 边界已公告 / 认证未接入`。**

---

## 结论

| 方案 | 改几处 | 验证方式 | 主要风险 | 工作量 |
|---|---|---|---|---|
| **S1 公告边界** | **7 处**（4 描述 + 2 回执 + 1 文档） | `grep` 描述 + 读回执字段 | **让人以为「写了说明就安全了」** | **~2h，今天可做** |
| **S2 显式授权** | **4 处**（`resolve_agent_role` + `check_scope_permission` + **新工具 `agents_register`** + wbtest） | 造测试：未登记 ⇒ 拒 | **误伤全部未登记调用** | **~1-2 天 + 需裁决** |
| **S3 身份锚点** | **6 处**（生成/登记/挑战/验签/会话/回退） | 造测试：签名挑战 | **向后兼容断裂** | **数周** |

### 推荐顺序：**S1（现在）→ S3（跳过 S2）→ 视情况回补 S2**

**理由**：**S2 价值/成本比最差** —— 误伤全部现网调用，却**不改变安全属性**
（任何调用方仍可自称一个已登记的名字）。

---

## 证据

### S1：现状（本次现读）

六处 agent 参数描述，**无一处提到「自报 / 不可验证」**：

| 工具 | 参数 | 现描述 |
|---|---|---|
| `reserve_scope` | `agent` | 预订者（如 exec_1，必填） |
| `lock_acquire` | `agent` | 持有者（必填） |
| `claim` | `agent` / `assignee` | ACL 判定身份的显式声明 / 认领人（必填） |
| `execute` | `agent` / `executor` | 同上 / 执行器名称（执行元数据） |

**⭐ 但回执面已有一半基础，且改点集中**：

```
engine_rsv.mbt:48  fn judged_role(eng, agent) -> (role, role_source)   ← **四条门共用唯一取数面**
                   role_source = "declared" | "inferred"
调用点：engine_rsv.mbt:79（rsv_set/rsv_try_set）、:107（locks_try_acquire）、engine.mbt:180（claim RANK_GATE）
```

**⇒ `role_source` 已在回执里。S1 不是「四处各加字段」，而是「四条门共用一处」。**
**⚠️ 但 `judged_role` 是高扇出点 ⇒ 我建议**不改签名**，只在**回执拼串处**加 `agent_source`（改 2 处）。**

### S2：现状（本次现读）

```
engine_scope_perm.mbt:305/307   None => (inferred, "inferred")     ← 未登记 ⇒ 名字推断
engine_scope_perm.mbt:319       Unregistered(...)                  ← advisory，不参与授权裁决
engine_scope_perm.mbt:131       Unregistered 不是放行授权，只表示「预订登记成功」
```

**⇒ 未登记者：`agents_get` 返回 None ⇒ 退到 `infer_role_from_agent` ⇒ 最高 Executor。**
**（BUG-421 后推断最高只到整名 `human_steward`/`human`，`leader`/`lead` 已不给高角色。）**

**关键前提**：`agents_register` **当前未暴露为 MCP 工具**（`grep -c agents_register src/server/server.mbt` = 1，仅 server 启动内部调用）。
**⇒ S2 若要做，必须同批新增这个工具，否则「未登记一律拒」之后**没有任何自助补登记的路**。**

### S3：现状（本次现读）

```sql
-- store_sqlite.mbt:133 —— 字段**已存在**
CREATE TABLE IF NOT EXISTS agents (..., pubkey_fp TEXT NOT NULL DEFAULT '', ...)
```

**⚠️ 但 `pubkey_fp` 全仓只作为「传递参数」出现，无任何写入/校验逻辑**：
`store_sqlite.mbt:2724`（结构体字段）、`:2749`（参数）、`server.mbt` 5 处（**硬编码 `pubkey_fp=""` 透传**）。

**⇒ `agents.pubkey_fp` 100% 为空，代码里没有任何签名/验签面。**
**⇒ S3 好消息：schema 无需改（字段已在）；坏消息：生成/登记/挑战/验签整条链路都要新建。**

**MCP 会话面**：`server.mbt` 的 `session` 只出现在**六顶帽辩论** `DebateSession`（`:296-317`），
**与 MCP 连接无关** ⇒ **没有任何 per-connection 上下文可用。**

---

## 改动清单

### S1（7 处，~2h）

| # | 位置 | 改什么 |
|---|---|---|
| 1-4 | `server.mbt` 的 `reserve_scope.agent` / `lock_acquire.agent` / `claim.assignee`+`.agent` / `execute.agent` | 描述各加：`⚠️ 本参数由调用方自报，服务端无法验证真实身份；仅作登记与审计用` |
| 5-6 | `engine_rsv.mbt:89` 与 `rsv_try_set` 的 `Unregistered` 分支（`:319`） | 回执 `[role_source=…]` 扩成 `[role_source=…, agent_source=self-reported]`（**扩现有串，不新增字段**，避免破坏解析） |
| 7 | `AGENTS.md` 新增「已知边界」一节 | 见下 |

**AGENTS.md 该节文字（要点）**：所有 `agent`/`assignee`/`executor` 由调用方自报，服务器无法验证；
`reserve_scope`/`lock_acquire`/`claim`/`execute` 的角色判定是 **advisory**（能防「无意的名字碰撞」，
**不能防「有意的冒充」**）；三条硬约束 = `pubkey_fp` 全空 + `pid` 是 `floor(Unix 秒)%2e9` 可反推 +
无 per-connection 会话绑定；**本边界在 S3 落地前不会消除，S1 只是让它可见**。

### S2（4 处，~1-2 天）

| # | 文件 | 改什么 |
|---|---|---|
| 1 | `engine_scope_perm.mbt` `resolve_agent_role` | `None => (inferred, "inferred")` → `None => ("Executor", "unregistered")`（**仍给 Executor**，否则全拒） |
| 2 | `engine_scope_perm.mbt` `check_scope_permission` | `Unregistered` 从 advisory 改为**拒**（仅当目标 scope 需非 Executor 角色） |
| 3 | `server.mbt` | **新增 MCP 工具 `agents_register`**（当前无自助面，不做则 S2 不可用） |
| 4 | 新 wbtest | 见验证方式 |

**⚠️ S2 最大问题不是代码，是两件需统帅裁决的事**：
- **未登记者「全拒」还是「只禁高权面」**？全拒 ⇒ 现网大部分调用立刻失败
- **`agents_register` 谁能调**？不设门槛 ⇒ 攻击者先登记自己 ⇒ **S2 形同虚设**

### S3（6 处，数周）

| # | 面 | 改什么 |
|---|---|---|
| 1 | `agents` 表 | **不改 schema**（`pubkey_fp` 已在） |
| 2 | 客户端 | 生成密钥对，`agents_register` 时提交 `pubkey_fp` |
| 3-4 | server | 下发 nonce 挑战 + 新增 `verify_challenge(pubkey_fp, nonce, sig)` |
| 5 | 会话上下文 | **新增 per-connection 绑定**（当前无任何连接上下文，最重的一块） |
| 6 | 回退策略 | `pubkey_fp=""` 的旧 agent 如何处理（**向后兼容关键**） |

**S3 最小可行路径（S3-lite，我建议的）**：
> **不引入真密码学**：server 启动生成随机 `session_token` 写到
> `%LOCALAPPDATA%\FIST-Mbt\session.token`，客户端读它并在每次调用带上，`reserve_scope` 校验。
> **⇒ 能挡「跨机器冒充」，挡不住「同机器冒充」**（读同一文件即得）——
> **比 S1 强、比真签名弱，成本约 1-2 天。**

---

## 验证方式

| 方案 | 验证 |
|---|---|
| **S1** | ① `grep -c "由调用方自报" src/server/server.mbt` ≥ 4；② 调 `reserve_scope` 断言回执含 `agent_source=self-reported`；③ `grep -c "已知边界：MCP 工具面无认证层" AGENTS.md` = 1 |
| **S2** | ① 未登记 agent 调 `reserve_scope("src/engine/...")` ⇒ **RoleDenied**；② 已登记 Executor ⇒ 同样 RoleDenied；③ 已登记 Leader ⇒ Allowed（防修过头）；④ **变异对照**：`("unregistered")` 改回 `("inferred")` ⇒ 格①必红 |
| **S3** | ① 正确签名 ⇒ Allowed；② 错误签名 ⇒ RoleDenied；③ **重放同一 nonce ⇒ 拒**；④ 空 `pubkey_fp` 旧 agent ⇒ 按回退策略断言（**这格决定向后兼容**）；⑤ **变异对照**：删验签 ⇒ 格②必红 |

**⚠️ S2/S3 的测试必须清场**（`temp/xxx.db` 残留会让第二跑假红 —— `bug423`/`bug432` 各踩过一次）。

---

## 分析（为什么 S1 最小最安全）

**S1 只改「可见性」** ⇒ 零行为变更、2 小时可做、把「不安全」从隐藏属性变成可见属性。

**但 S1 有个必须警惕的风险**：
> **「写了说明」≠「安全了」。恰恰相反，写了说明可能让人更放心** ——「文档都写了，应该有处理吧？」
> **⇒ 文案必须写成「不安全」而非「有说明」**：用「**不能防有意的冒充**」「**在 S3 落地前不会消除**」，
> 而不是「本参数仅为登记用」。**措辞决定它被读成「警告」还是「免责声明」。**

### 为什么不推荐 S2 作为第二步

| | S1 | **S2** | S3 |
|---|---|---|---|
| 改判定逻辑 | ❌ | ✅ **改** | ✅ 改 |
| 误伤现网 | **0** | **全部未登记调用** | 视回退策略 |
| **是否真的更安全** | ❌（只是可见） | **❌ 仍不安全** | ✅ **是** |

**⇒ S2 是「付出误伤代价却不换来安全」的那一档。**
**⇒ 正确坡道：S1（可见）→ S3-lite（弱凭据）→ 视需要回补 S2。**

---

## 缺口与风险

| # | 项 |
|---|---|
| **R1** | **S2 两个裁决点未定**（全拒/只禁高权、`agents_register` 谁能调）—— 不先定，做出来也是错的 |
| **R2** | **S3-lite 的 token 是否也「可计算」** —— 建议随机生成，但**未实测**本地文件读取面 |
| **R3** | **S1 回执改动可能影响既有解析** —— 若有人按 `]` 截断会坏。**需先 grep 调用方** |
| **R4** | 在途文件（`dist/`、`scripts/run_guards.py`）未触碰；`lock_acquire` 走 `judged_role` 已核实 |

---

## 建议入档位置

**账本建议**：
- **BUG-430 保持 OPEN**，状态 `[arch] 边界已公告（S1 已落地）/ 认证未接入（S3 待做）`
- **S1 落地后只有「工具面未声明自报」这个子项可标 FIXED**，不是 BUG-430 整体

**给后来人的一句话**：
> **BUG-430 的关闭条件不是「S1 做完」，而是「存在至少一条『调用方无法自报』的路径」。**
> 在 S3 落地前，任何 `agent=` 参数都只是**声明**，不是**凭证**。

---

**未改 `src/` `scripts/` 任何文件。未调 `bug_fix`。**
