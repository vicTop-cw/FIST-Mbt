# BUG-464 定夺：`publish` 家族「不查 ns ACL」是**设计**，不是缺陷 · Lane BX · 2026-10-28

> **结论先行：「补 `ns_write_gate`（ACL）」这个派单方向是错的。**
> 我按初判加了 ACL 门，**核完代码后全部回退**。
> 真正的口子不是 ACL，是 **`created_by` 自报**（S1 同族）。

---

## 一、结论

| 问题 | 答案 |
|---|---|
| 是设计还是缺陷？ | **设计**（且带配套弥补机制，见 §2.1） |
| 证据 | ① BUG-411 注释原文 ② `engine.publish` 的 `created_by` 硬检查 ③ 发布成功后有 `claim_ready` 运行时预警 |
| `created_by` 有验证吗？ | **没有**。全仓 `grep` 无任何验签/校验 —— 纯 `get_str(args, …)` |
| 我做了什么 | **回退了自己加的 3 处 ACL 门**，改为代码注释记录「为何刻意不加」 |
| 定夺建议 | **③ 保持 OPEN，作为 S1/S3 的子面锚点**（与 BUG-430 一起收）|

---

## 二、证据

### 2.1 证据①：BUG-411 注释原文（`server.mbt` publish 分支）

```moonbit
// BUG-411：publish 走 human_steward 特权路径（不看 ns ACL），而 claim 走
// agent_write_gate 的 ns ACL —— 同 ns 内「发布成功、认领被拒」是合法组合，
// 但调用方在此之前零预警（无人值守流水线会先发布、再撞墙，排查成本高）。
// 这里在发布成功时**当场**把「该 ns 有没有人能认领」摆出来。
let writable = eng.agents_acl_count_writable(ns~)
```

**关键**：这不只是「一句注释说我们不查 ACL」——
**它还有配套的运行时弥补**：回执里带 `claim_ready`（机器可读布尔）与 `writable_agents`（数量），
并在无人能认领时给出 `agent_acl_grant(...)` 的具体指引。

**⇒ 这是「刻意设计 + 认知成本已被处理」，不是「漏了一个检查」。**

### 2.2 证据②：`engine.publish` 开头的硬检查

```moonbit
// src/engine/engine.mbt
if created_by != "human_steward" && created_by != "human" {
  return Err("publish 仅限人类指挥官（created_by=human_steward）")
}
```
⇒ publish 的**准入条件是人，不是 ns 权限**。给它再叠一道 ns ACL 会**削掉指挥官的跨 ACL 发任务能力**。

### 2.3 证据③：`created_by` 无任何验证

```
$ grep -rn "created_by" src/server/*.mbt src/engine/*.mbt | grep -iE "verify|sig|challenge|auth|valid"
（仅命中一处文档字符串与一处测试夹具，**无任何验证逻辑**）

$ grep -n 'get_str(args, "created_by"' src/server/server.mbt
1968:      let created_by = get_str(args, "created_by", default="human_steward")   ← publish
2064:      let created_by = get_str(args, "created_by", default="selfdrive")       ← publish_parallel
5101:      let created_by = get_str(args, "created_by", default="human_steward")   ← dag_publish
```

**⇒ 任何调用方填 `created_by=human_steward` 就能进特权路径。这才是真实口子。**

### 2.4 我做的回退

```diff
-      // BUG-464：**ns 写权限门（ACL）**
-      match agent_write_gate(eng, acl_claim_identity("", created_by), ns) {
-        Err(e) => return Err(@mcp_types.ToolError(e))
-        Ok(_) => ()
-      }
+      // **BUG-464 定夺：此处刻意不加 ACL 门**
+      //   · engine.publish 开头有 created_by 硬检查 ⇒ 特权入口
+      //   · 发布成功后有 BUG-411 的 claim_ready / writable_agents 配套预警
+      // ⇒ 加强制 ACL 会削掉指挥官的跨 ACL 发任务能力，属于修错方向。
+      // ⚠️ 真正的口子在 S1：created_by 自报、全仓无验证 ⇒ 归 BUG-430 收口。
```
同时删掉了我写的 `server_bug464_publish_acl_wbtest.mbt`（它锁的是错误方向）。

**验证**：`grep` 确认三处 publish 家族里 `agent_write_gate` **只剩注释、无调用**；`moon check` → **0 errors**。

---

## 三、分析

### 3.1 为什么「不查 ACL」是对的

**ACL 管的是「agent 能不能写这个 ns」；publish 管的是「人来下达指令」。**
指挥官的职责恰恰是**跨项目/跨 ns 派活** —— 若 publish 也要过 agent ACL，
那「给一个还没有任何 agent 的新 ns 发第一个任务」就永远做不成（先有鸡还是先有蛋）。

`claim` 才需要 ACL：那是 **agent 在某个 ns 里动手**。**两道门管两件事**，不该合并。

### 3.2 真实的安全境界：**任何人都能自称指挥官**

| 层 | 门 | 现状 |
|---|---|---|
| ns 合法性 | `ns_write_gate`（拒 default/空/非法） | ✅ 有 |
| **特权准入** | `created_by ∈ {human_steward, human}` | ⚠️ **只比字符串，谁都能填** |
| agent 写权限 | `agent_write_gate` | 不适用（publish 是特权路径，非 agent 写） |

**⇒ publish 家族的真实境界 = 「任何能调到 MCP 的人，都能以指挥官身份在任意 ns 发布任务」。**

它**与 `agent` / `assignee` / `executor` 自报是同一类问题** —— 都在 AGENTS.md 的
**S1「已知边界」**之内：*「`agent`…都是调用方自报的字符串，服务端没有任何手段验证它真属于谁」*。
`created_by` 只是**这张清单里被漏写的一个字段**。

---

## 四、缺口与风险

1. **BUG-464 与 BUG-430 是同一件事的两个面**：前者是后者的**一个字段**（`created_by`）。
   **分开记账会导致两次修同一个根**。
2. **AGENTS.md 的 S1 清单没列 `created_by`**（只列了 `agent` / `assignee` / `executor`）。
   ⇒ **建议补进去** —— 这是本轮唯一「值得改」的动作，且是**文档**不是代码。
3. 若真要「加强 `created_by` 校验」（定夺②），那是 **S3 的延伸**：
   要求 `created_by=human_steward` 时附带 challenge 验签。
   **但那会让「人类指挥官」变成「持有指定私钥的人」** —— 这是**产品决策**，不是我能定的。
4. **本轮期间多次遇到并发 lane 的编译中断**（`server_bug430_s3_rotate_wbtest.mbt` 等），
   均等待收口后重跑，**未使用 `--no-verify`**。

---

## 五、建议入档位置

| 内容 | 位置 |
|---|---|
| **BUG-464 → FALSE_POSITIVE（或并入 BUG-430）** | 账本：判 `FALSE_POSITIVE`，`dup_of=BUG-430`；理由是「BUG-411 显式设计 + S1 已知边界」 |
| **「特权路径 vs agent 写路径是两道门」** | 判例集（与「ACL ≠ 角色矩阵」并列，BUG-408 同族）|
| **`created_by` 补进 AGENTS.md S1 清单** | 文档（本轮唯一建议的改动）|
| **「派单说补 ACL，实测是设计」** | 本报告即为实例：**读数优先于派单** |
