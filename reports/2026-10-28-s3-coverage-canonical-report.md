# S3 / 身份门**实际**覆盖面 + 死参数普查（BUG-430 审核）

> 司令-γ · 2026-10-28 · **只读审核**（未改 `src/` 已跟踪文件）
> **三个数字都能复现，但只有分子分母同集合的才可比。**
> **⚠️ 更要紧的发现：全仓 22 处「声明了但从不读」的死参数（见 §5）。**

---

## 结论

| 数字 | 数的是什么 | 分母 | 判定 |
|---|---|---|---|
| **5/156 (3.2%)** Alpha | schema 能看到 `challenge` 的工具 / 全部工具 | 156（**已过时**，今 177） | ⚠️ 数的是**声明面**；今为 **6/177 = 3.4%** |
| **3/14 (21%)** Beta | **真验** `challenge` 的工具 / 生命周期 14 | ❌ **错配** | ❌ **分子分母不同集合 ⇒ 不可比** |
| **9/14 (64%)** Beta | 「该有身份门却没有」/ 生命周期 14 | 生命周期 14 | ⚠️ 口径成立，但「该有」是**人为判据** |

**`3/14` 的硬伤**：那 3 个真验工具是 `claim`/`reserve_scope`/`lock_acquire` ——
**只有 `claim` 属于生命周期 14**，另两个不在该集合。

### 权威覆盖率（分母 = `_tool_registry.real_tools()` = **177**）

| 维度 | 读数 | 覆盖率 |
|---|---|---|
| L0 声明 `challenge` | **6 / 177** | **3.4%** |
| **L2 真验 `challenge`** | **3 / 177** | **1.7%** ← 真实防护面 |
| 任意形态身份门 | **11 / 177** | **6.2%** |
| 生命周期 14 有身份门 | **7 / 14** | 50% |

---

## 证据

### §1 分母标定（判例-32）

| 数法 | 读数 |
|---|---|
| 裸 `grep -c 'instrumented_tool('` | 160（**含 1 处函数定义**）⇒ 注册 159 |
| `embed_hexa_tools` 另注册 `hat_*` | **+3** —— **裸数会漏** |
| 我按括号配平切块 | 159 ✅ 一致 |
| **`_tool_registry.real_tools()`** | **177** ⇒ 采用（`mcp_smoke` 同源） |
| 运行态 `tools/list` | 174（smoke 报真源缺 `wt_*` 三个 ⇒ **构建旧，非工具少**） |

### §2 `challenge` 三层收紧（判例-29：机制格 ≠ 实现路径格）

| 工具 | L0 声明 | L1 取值 | **L2 真验** |
|---|---|---|---|
| `claim` / `reserve_scope` / `lock_acquire` | ✅ | ✅ | **✅**（经 `opt_challenge` → `judged_role_gated`） |
| **`plan`** | ✅ | ❌ | ❌ **声明了、handler 从不读**（BUG-472） |
| `agent_register_key` / `agent_issue_challenge` | ✅ | ❌ | ❌（前者是 `rotate_challenge` 轮换语义、后者是**签发器**，都不是通用门） |

### §3 身份门（11 个）

`ns_write_gate`（弱，只查 ns）：`publish`/`dag_publish`/`publish_parallel` · `agent_write_gate`+`acl_*`（中）：`claim`/`verify`/`archive`/`delete`/`agent_acl_grant`/`agent_register_key` · `judged_role_gated`（强，角色+可选验签 = S3 唯一改变安全属性的一档）：`execute`/`agent_issue_challenge`。
**门强度不可压成一个布尔** —— 混用会掩盖差异（见 R4）。

### §4 生命周期 14 交叉表

| 工具 | challenge(L2) | 身份门 | 类型 |
|---|---|---|---|
| `claim` | **✅** | ✅ | **双门** |
| `publish`/`publish_parallel`/`verify`/`archive`/`delete` | ❌ | ✅ | 只 ACL |
| `execute` | ❌ | ✅（`judged_role_gated`） | 只 ACL（**有 S3 能力未接 challenge**） |
| `plan` | ❌（**声明未接线**） | ❌ | 特权路径 |
| `submit`/`reject`/`retry`/`pause`/`resume`/`reopen_task` | ❌ | ❌ | **无门** |

**⇒ 真验 challenge 1 · 有身份门 7 · 两者皆无 7**（Beta 的 9/14 与此差 2，差在「该有」的定义）。

---

## §5 死参数普查（本单主要发现）

**「声明了但从不读」比「没有认证」严重得多**，因为它**不可见**：调用方以为受保护，实际被静默丢弃。

### 判法（三层，含三处实测踩过的坑）

对每个 `instrumented_tool` 块：schema 段 = `schema(...)` 括号内；handler 段 = 其后。
参数 X 判「死」 ⇔ X 在 schema 被声明，且 **handler 段（剥 `//` 注释后）里 `"X"` 出现 0 次**。
**特例**：`opt_challenge(args)` 一次读 `challenge` + `challenge_sig`。

**三个实测踩过的坑**：①字典 `setdefault` 让同名工具互相覆盖⇒漏报（改 list）②**子串误判**（判例-30）`agent in handler` 被 `agent_touch_first_seen(` 命中⇒假活（只匹配带引号 `"agent"`）③注释里写 `"agent"` 也算命中（剥 `//` 行注释）。

**双向标定**（判例-32）：正向 `claim` 读 `"agent"` ⇒ 必须判活；反向 `execute` 的 `agent` 只在注释/别的标识符 ⇒ 必须判死。**两者都过才出数。**

### 完整清单：**22 处 / 13 个工具**

| 文件 | 工具 | 未读参数 | 块起始行 |
|---|---|---|---|
| `hat_hexa_tools.mbt` | `hat_debate` | `issue`, `left`, `right`, `rounds` | 72 |
| `hat_hexa_tools.mbt` | `hat_merge` | `config_json`, `reports_json`, `round`, `topic` | 48 |
| `hat_hexa_tools.mbt` | `hat_run` | `config_json`, `round` | 26 |
| `server.mbt` | `agent_register_key` | `by` | 7095 |
| `server.mbt` | `cost_budget_check` | `current`, `limit` | 6640 |
| `server.mbt` | `evolve_distill` | `task_id` | 4513 |
| `server.mbt` | `evolve_sample` | `rand` | 4769 |
| `server.mbt` | **`execute`** | **`agent`** | 2223 |
| `server.mbt` | `laya_decide` | `no_sidecar` | 4798 |
| `server.mbt` | `lock_acquire` | `ts` | 6056 |
| `server.mbt` | `lock_renew` | `ts` | 6128 |
| `server.mbt` | `loop_create` | `items` | 3917 |
| `server.mbt` | **`plan`** | **`challenge`, `challenge_sig`** | 2036 |

**人工级复核**（不只信脚本）：

| 项 | handler 里的实际内容 |
|---|---|
| `plan.challenge`/`challenge_sig` | **0 条**（schema 之外从未出现） |
| **`execute.agent`** | 3 条，全是**注释**（`// BUG-436…`）与**别的函数名**（`agent_touch_first_seen(`、`agent_write_gate(`）—— **无 `get_str(args,"agent")`** |
| `lock_acquire.ts` | handler 有 `let ts = now_default()` **覆盖**了调用方传入值 ⇒ **参数被丢弃** |
| `loop_create.items` / `laya_decide.no_sidecar` | **0 条** |

**⚠️ `execute.agent` 是第二个 BUG-472 级发现**：schema 明确写「agent(可选，**ACL 判定身份**)」，
而 handler 从不读它（走的是 `execute_write_identity` 的推断）⇒ **调用方显式指定的身份被静默忽略**。

---

## 分析

### 为什么同一件事有三个百分比

**三个数字不是互相矛盾，是**不可比**（分子分母集合不同）。且「3.2%」的分子是声明不是真验 —— 真实防护面比它还小（1.7%）。**

### 为什么「声明了但不验」比「没有认证」更危险

| | 没有认证 | **声明了但不验** |
|---|---|---|
| 调用方感知 | 能看出没传认证参数 | **传了签名，以为受保护** |
| 失败形态 | 明确 | **静默降级**，无错误无警告 |
| 审计可见性 | 传参里没有就是没有 | **传参里有，只是没生效** |
| 修复触发点 | 加认证 | **没人知道要修** |

**⇒ 这是「假防线」的第二种形态**（第一种是 R25 的无效 `catch`）：**两者都让读代码的人以为已处理。**
同族：BUG-440（文档承诺了不存在的守卫）、BUG-453（`execute` 声明 `challenge` 却不接）。

### 对「BUG-430 该不该关」

| 关闭条件 | 读数 |
|---|---|
| ①「存在至少一条调用方无法自报的路径」 | **✅ 满足**（`claim`/`reserve_scope`/`lock_acquire` 真有 `challenge_verified`） |
| ②「默认要求认证」 | **❌ 不满足**（6/177 声明、3/177 真验） |

**⇒ 建议拆 `430a`/`430b`（FIXED）+ `430c`（保持 OPEN）。不要把 3.4% 读成「S3 做了 3.4%」。**

---

## 缺口与风险

- **R1** `plan` 声明未接线 → **`BUG-472`（OPEN）**
- **R2** `execute` 的 `agent` 声明未读 —— **同级严重，已报 `BUG-473`（OPEN）**
- **R3** 写死分母会过期（Alpha 156 vs 今 177）⇒ 报告必须写**分母来源 + 采集时刻**
- **R4** 三种门强度被压成一个布尔，掩盖差异
- **R5** 其余 20 处死参数未逐个人工复核（脚本已双向标定，仍建议按 `BUG-472` 口径逐个确认）

> **入档**：本报告 · 只读脚本 `temp/audit/lane_cq_{authoritative,dead_v2,manual}.py` · 账本 **BUG-472**(plan) + **BUG-473**(execute.agent)
