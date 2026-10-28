# S3 / 身份门**实际**覆盖面权威表（BUG-430 审核）

> **执行人**：司令-γ · **日期**：2026-10-28 · **性质**：**只读审核**（未改任何 `src/` `scripts/`）
> **一句话**：三个数字**都能复现，但只有一个是自洽的** ——
> `3.2%` 分母错、`21%` 与 `64%` 口径不同但各自成立、**权威覆盖率 = 6/177（challenge 声明）· 3/177（真验）· 11/177（有身份门）**。

---

## 结论

| 数字 | 来源 | 数的是什么 | 分母 | 判定 |
|---|---|---|---|---|
| **5 / 156 (3.2%)** | Alpha | 声明 `challenge` 的工具 | 156（**已过时的工具总数**） | ❌ **数字本身可复现但有偏差**：现为 **6 / 177 = 3.4%** |
| **3 / 14 (21%)** | Beta | **真验** `challenge` 的工具 | ❌ **错用**「生命周期工具数」 | ❌ **分子分母不同集合 ⇒ 不自洽** |
| **9 / 14 (64%)** | Beta | 「该有身份门却没有」 | 生命周期 14 | ⚠️ 口径成立，但**「该有」是人为判据**（见 §4） |

### 权威覆盖率（用单一真源分母）

**分母 = 177**（`scripts/_tool_registry.py` 的 `real_tools()`，`mcp_smoke` 也用它）

| 维度 | 读数 | 覆盖率 |
|---|---|---|
| **L0** 声明了 `challenge` | **6 / 177** | **3.4%** |
| **L2** 真把 `challenge` 送进验签器 | **3 / 177** | **1.7%** |
| **身份门**（任意一形态） | **11 / 177** | **6.2%** |
| **生命周期 14** 中有身份门 | **7 / 14** | 50% |

---

## 证据

### §1 分母为什么是 177（判例-32 标定）

| 数法 | 读数 | 说明 |
|---|---|---|
| 裸 `grep -c 'instrumented_tool('` | **160** | 含 1 处**函数定义** ⇒ 注册 159 |
| 我按括号配平切的块 | **159** | 与上一行一致 ✅ |
| `embed_hexa_tools` 另注册 | **+3** | `hat_run`/`hat_*` —— **裸数 `instrumented_tool` 会漏这 3 个** |
| **`_tool_registry.real_tools()`** | **177** | 仓内已收口的单一真源（`mcp_smoke` 同源）⇒ **采用这个** |
| 运行态 `tools/list` | **174** | smoke 报「真源缺 3：`wt_create`/`wt_destroy`/`wt_status`」⇒ **构建产物旧，不是工具少了** |

**⚠️ Alpha 的 156 是**某个更早时点**的工具总数**（今天已 177）。存量工具在增长，**任何写死的分母都会过期** —— 这是本报告的第一个建议。

### §2 `challenge` 声明面（L0 → L2 三层收紧）

| 工具 | L0 声明 | L1 取值 | **L2 真验** | 说明 |
|---|---|---|---|---|
| `claim` | ✅ | ✅ | **✅** | 完整链路 |
| `reserve_scope` | ✅ | ✅ | **✅** | 透传给 engine 的 `judged_role_gated` |
| `lock_acquire` | ✅ | ✅ | **✅** | 同上 |
| `plan` | ✅ | ❌ | ❌ | **schema 声明了 challenge/challenge_sig，实现体里根本没取值** |
| `agent_register_key` | ✅ | ❌ | ❌ | 它有 `rotate_challenge`/`rotate_sig` 的**轮换**语义，不是通用挑战门 |
| `agent_issue_challenge` | ✅ | ❌ | ❌ | 它是**签发器**，不消费 challenge（本就是工具链上游） |

**⇒ Alpha 的「5」很可能是当时把 `plan` 或某个 `agent_*` 排除的结果；今天严格按 schema 数得 6。真正要紧的是 L2：只有 3 个真验。**

**`plan` 这条是**真缺口**：schema 向调用方承诺了 `challenge` + `challenge_sig`（"⚠️ 须配合 challenge_sig"），
而实现体里**一次都没读** —— 调用方传了签名也不会被验证，也**不会被告知没验**。

### §3 身份门面（ACL 维度，11 个）

| 工具 | 门形态 |
|---|---|
| `publish` | `ns_write_gate` + `agent_write_gate` + `acl_` |
| `publish_parallel` | `ns_write_gate` |
| `dag_publish` | `ns_write_gate` |
| `claim` | `acl_claim_identity` + `agent_write_gate` |
| `execute` | `agent_write_gate` + `judged_role_gated` |
| `verify` | `acl_claim_identity` + `agent_write_gate` |
| `archive` / `delete` | `acl_claim_identity` + `agent_write_gate` |
| `agent_acl_grant` | `acl_` + `agent_write_gate` |
| `agent_register_key` | `acl_` + `agent_write_gate` |
| `agent_issue_challenge` | `judged_role_gated` |

**门强度不同**：`ns_write_gate`（弱，只查 ns）< `agent_write_gate`（中，查 ACL 表）< `judged_role_gated`（强，角色+可选验签，S3 唯一改变安全属性的一档）。

### §4 交叉表（生命周期 14 + 双维度）

| 工具 | challenge(L2) | 身份门 | 类型 |
|---|---|---|---|
| `claim` | **✅** | ✅ | **双门** |
| `publish` / `publish_parallel` | ❌ | ✅（弱 `ns_write_gate`） | 只 ACL |
| `execute` | ❌ | ✅（`judged_role_gated`） | 只 ACL（**有 S3 能力但未接 challenge**） |
| `verify` | ❌ | ✅（R28 新） | 只 ACL |
| `archive` / `delete` | ❌ | ✅ | 只 ACL |
| `plan` | ❌（**声明未接线**） | ❌ | **特权路径** |
| `submit` / `reject` / `retry` / `pause` / `resume` / `reopen_task` | ❌ | ❌ | **无门** |

**生命周期 14：真验 challenge 1 · 有身份门 7 · 两者皆无 7**
（`submit`/`reject`/`retry`/`pause`/`resume`/`reopen_task`/`plan`）

**⇒ Beta 的 9/14 与我的 7/14 差 2**：差异在 `plan`（Beta 计「该有」我计「无门」）与 `publish_parallel`（弱门算不算）。**「该有」是人为判据，不是可复现的机械读数** —— 这是 64% 最容易被误读处。

---

## 分析：为什么同一件事会有三个不同百分比

**三个数字分别在数三件不同的事，而分母各不相同：**

```
Alpha 5/156  = 「调用方能在 schema 里看到 challenge 的工具」/ 全部工具
                  → 数的是**声明面**（API 可见性）
Beta  3/14   = 「真的验了 challenge 的工具」/ 生命周期工具
                  → 分子是**全仓**的，分母是**生命周期**的 ⇒ **不同集合，不可比**
Beta  9/14   = 「我判断该有身份门却没有的」/ 生命周期工具
                  → 分子是**人为判据**，换个人数会不同
我的  3/177  = 「真的验了 challenge 的工具」/ 全部工具
我的  11/177 = 「有任何形态身份门的工具」/ 全部工具
                  → 分子分母**同一集合**，可复现
```

**⇒ 三个数字**不是互相矛盾，是**不可比**。**只有分子分母同集合的读数才能比。**

**这也是为什么「3.2%」读起来最刺眼**：它的分子是「声明」而不是「真验」，
**真实防护面比 3.2% 还小（1.7%）**。

---

## 缺口与风险

### 🔴 R1（真缺口，建议 `report_bug`）：`plan` 的 `challenge` 声明未接线

`plan` 的 schema 写明「可选：S3 挑战 nonce。⚠️ 须配合 challenge_sig」，
但实现体**从未读取** `challenge`。后果：
- 调用方以为传了签名就受验，**实际不验、也不报错**（静默降级）；
- 与 `claim`/`reserve_scope`/`lock_acquire` 的**同形声明**让调用方无法区分。

**⇒ 这违反「一源四态」**：schema 声明的能力与实现不一致。

### 🟡 R2：写死的分母会过期

Alpha 的 `156` 与今天 `177` 差 21 —— 期间工具在增加。
**建议**：报告里的百分比**必须同时写「分母来源 + 采集时刻」**，
或直接引用 `_tool_registry.py` 而不是硬编码。

### 🟡 R3：三种门强度被混用

`ns_write_gate`（弱）/ `agent_write_gate`（中）/ `judged_role_gated`（强）
在「有没有门」这个问题下会被**压成一个布尔**，掩盖强度差异。
**建议**：任何「身份门覆盖率」必须说明**门强度口径**。

### 🟡 R4：`execute` 有 S3 能力但未接 challenge

它在 `judged_role_gated` 路径上，但 schema 无 `challenge` 字段
⇒ 无法使用 `+challenge_verified`（只能吃自报 role）。这是 AGENTS.md 已记录的
「`execute`/`verify` 仍未接 challenge」，读数印证了它。

### 未做（边界内）
**未改 `server.mbt`**（Beta 独占）、**未改任何 `src/` `scripts/`**。
本报告全部读数来自只读脚本 `temp/audit/lane_cq_*.py`。

---

## 对「BUG-430 该不该关」的判断

**推荐：拆成 `430a/430b`（FIXED）+ `430c`（保持 OPEN）**，理由是**读数支持「能力已具备，覆盖未铺开」**：

| 关闭条件（AGENTS.md 口径） | 读数是否满足 |
|---|---|
| 「存在至少一条调用方无法自报的路径」 | **✅ 满足** —— `claim`/`reserve_scope`/`lock_acquire` 三个工具真有 `challenge_verified` |
| 「默认要求认证」 | **❌ 不满足** —— 6/177 声明、3/177 真验，且 `plan` 声明未接线 |

**⇒ 技术上「有这条路」已成立（可关 430a/430b）；但「默认安全」远未达到（430c 应保持 OPEN）。**
**⇒ 不要把 3.4% 读成「S3 做了 3.4%」—— 它只是「声明面」，真实防护面 1.7%。**
