# 生命周期工具身份门系统普查 · Lane CL · 2026-10-28

> **「按形状搜」而不是「按面挑」。** 上一单我只修了 `verify`，没查同族。
> 本单机械扫了 14 个生命周期工具的**代码面**（跳注释），找出 **9 个无身份门**。

---

## 一、结论

### 1.1 14 个工具完整对照表

| # | 工具 | 有门？ | 门类型 | 该有？ | 结论 |
|---|---|---|---|---|---|
| 1 | `publish` | ⚠️ 仅 `ns_write_gate` | **ns 合法性**（不看调用者）| 特权路径 | **不入本类**（见 §3.2）|
| 2 | `publish_parallel` | ⚠️ 同上 | ns 合法性 | 同上 | 同上 |
| 3 | **`plan`** | ❌ **无** | — | ✅ **写状态** | **🔴 缺陷** |
| 4 | `claim` | ✅ | `judged_role*` + `agent_write_gate` + `acl_claim_identity` | ✅ | OK |
| 5 | `execute` | ✅ | `agent_write_gate` | ✅ | OK |
| 6 | **`submit`** | ❌ **无** | — | ✅ 写状态 | **🔴 缺陷** |
| 7 | `verify` | ✅ | `agent_write_gate` + `acl_claim_identity` | ✅ | OK（**本单前置，上单修的**）|
| 8 | **`reject`** | ❌ **无** | — | ✅ 写状态 | **🔴 缺陷** |
| 9 | **`retry`** | ❌ **无** | — | ✅ 写状态 | **🔴 缺陷** |
| 10 | **`reopen_task`** | ❌ **无** | — | ✅ 写状态 | **🔴 缺陷** |
| 11 | **`pause`** | ❌ **无** | — | ✅ 写状态 | **🔴 缺陷** |
| 12 | **`resume`** | ❌ **无** | — | ✅ 写状态 | **🔴 缺陷** |
| 13 | **`archive`** | ❌ **无** | — | ✅ 写状态（**不可逆**）| **🔴 缺陷（最高危）** |
| 14 | **`delete`** | ❌ **无** | — | ✅ 写状态（**不可逆**）| **🔴 缺陷（最高危）** |

### 1.2 回答派单的核心问题

> **「生命周期 14 个里，几个真有身份门？几个该有没有？分别是哪些？」**

- **真有身份门（ACL / 角色）**：**3 个** —— `claim` / `execute` / `verify`
- **该有而没有**：**9 个** —— `plan` / `submit` / `reject` / `retry` /
  `reopen_task` / `pause` / `resume` / `archive` / `delete`
- **不属此类（特权/合法性门）**：2 个 —— `publish` / `publish_parallel`

**⇒ 14 个里只有 3 个（21%）真有身份门，9 个（64%）该有没有。**

---

## 二、证据

### 2.1 扫描方法（机械，不猜）

脚本 `temp/audit/lane_cl_gate.py`：
1. 用 `instrumented_tool(s1, "name"` 正则切出每个工具的**完整工具块**；
2. **跳过注释行**（判例-30：注释里的标识符不算接线）；
3. 在代码面检测 8 种门形态的出现：
   `judged_role` / `judged_role_gated` / `agent_write_gate` / `agent_acl_check` /
   `acl_claim_identity` / `acl_execute_identity` / `ns_write_gate` / `enforce(`

**扫描输出（原样）**：
```
publish           ns 合法性门(ns_write_gate)
publish_parallel  ns 合法性门(ns_write_gate)
plan              ❌ 无任何身份门
claim             角色门(judged_role*), ACL 写门(agent_write_gate), 身份解析(acl_claim_identity)
execute           ACL 写门(agent_write_gate)
submit            ❌ 无任何身份门
verify            ACL 写门(agent_write_gate), 身份解析(acl_claim_identity)
reject            ❌ 无任何身份门
retry             ❌ 无任何身份门
reopen_task       ❌ 无任何身份门
pause             ❌ 无任何身份门
resume            ❌ 无任何身份门
archive           ❌ 无任何身份门
delete            ❌ 无任何身份门
生命周期工具命中: 14 / 14
无任何身份门: 9 个
```

### 2.2 全仓 `agent_write_gate` 调用点（佐证只有 3 处）

```
$ grep -n "agent_write_gate(" src/server/server.mbt | grep -v "fn agent_write_gate"
2154:      match agent_write_gate(eng, who, ns) {                 ← claim
2287:      match agent_write_gate(eng, who, ns) {                 ← execute
2500:      match agent_write_gate(eng, acl_claim_identity(...))   ← verify
```
**⇒ 确认全仓只有这 3 个工具接了 ACL 门。**

### 2.3 9 个工具的「写状态」证据（判据，不是感觉）

逐个确认它们**真调用了会改任务状态的引擎函数**：

| 工具 | 引擎调用 | 是否改状态 |
|---|---|---|
| `plan` | `eng.plan(...)` → `store.update_task(p2)` + 建子任务 | ✅ 改父任务状态 + 建任务 |
| `submit` | `eng.submit(...)` | ✅ 待验收 |
| `reject` | `eng.reject_task(...)` | ✅ 已打回 |
| `retry` | `eng.retry_task(...)` | ✅ 执行中 |
| `pause` | `eng.pause_task(...)` | ✅ 已暂停 |
| `resume` | `eng.resume_task(...)` | ✅ 已领取 |
| `reopen_task` | `eng.reopen_task(...)` | ✅ 待处理 |
| `archive` | `eng.archive_force(...)` | ✅ **已归档（不可逆）** |
| `delete` | `eng.delete_task(...)` | ✅ **物理删除（不可逆）** |

**⇒ 9 个全部符合「该动作改变任务状态 ⇒ 必须有门」的判据。**

### 2.4 9 个工具的「身份参数」现状（决定修法）

| 工具 | 现有身份参数 |
|---|---|
| `reject` | `by` |
| `archive` | `by` |
| `submit` / `retry` / `pause` / `resume` / `reopen_task` / `delete` / `plan` | **无**（只有 `task_id` + `namespace`）|

**⇒ 7 个连身份参数都没有 ⇒ 修法必须「新增可选 `agent` 参数 + 一道门」，不能照抄 `verify`（它是复用现成的 `verifier`）。**

### 2.5 修法的可行性（已验证，供后续单参考）

`acl_identity_pick` 的兜底：
```moonbit
// src/server/write_gate.mbt:246
for c in cands { if raw != "" { return {...} } }
{ raw: "manual", source: "default-manual", implicit: true }   // ← 空身份 ⇒ "manual"
```
⇒ **新增可选 `agent` 参数、缺省为空 ⇒ 身份 = `manual`**：
- 内存后端：`agent_write_gate` 直接放行 ⇒ **零回归**
- sqlite 面：`manual` 无 `can_write` ⇒ **被拒（fail-closed）** —— 这正是我们要的

**⇒ 9 个都可按同一模式修，但每个要同步 schema / 描述 / 测试 / 文档四处**，
超出派单「改动小才顺手修」的范围 ⇒ **本单只普查 + 上报，不改代码。**

---

## 三、分析

### 3.1 为什么「按形状搜」比「修个案」有效

上一单我修 `verify` 时，**只看了 `verify` 一个工具**。
本单把判据反过来：**先定义「身份门的形状」，再扫全部 14 个** ⇒ 一次找出 9 个。

**这与 gamma R19 用「按形状搜」找出 BUG-441 同族是同一方法。**
「修个案」的隐含假设是「这个 bug 是孤例」，而**系统的同一设计缺陷通常成片存在**。

### 3.2 为什么 `publish` / `publish_parallel` 不算在这 9 个里

它们只有 `ns_write_gate`（**ns 合法性**，拒 default / 空 / 非法字符），**不看调用者**。
但 `engine.publish` 开头有 `created_by` 硬检查 + 发布成功后有 `claim_ready` 预警
（BUG-411 显式设计，BUG-464 已定夺「不是 ACL 缺陷」）⇒ **它们的口子是 S1（`created_by` 自报）**，
与这 9 个「连门都没有」不同类。**不混算，避免稀释。**

### 3.3 9 个缺口的实际危害分级

| 级别 | 工具 | 理由 |
|---|---|---|
| **最高危** | `delete` / `archive` | **不可逆**：物理删除 / 归档后极难恢复 |
| 高危 | `verify`（已修）/ `reject` / `submit` | **质量闸门**：盖章通过或被恶意打回 |
| 中危 | `retry` / `reopen_task` / `pause` / `resume` | 状态操纵，可被后续流程发现 |
| 中危 | `plan` | 结构操纵，污染任务树 |

---

## 四、缺口与风险

1. **9 个工具全无身份门**（本单结论）。按派单要求已逐条上报（`[gate]` 前缀，`publish_task=false`）。
2. **本单未改代码**：9 个同构改动需同步 schema / 描述 / 测试 / 文档四处，
   超出「改动小」范围；且一次性改 9 处回归风险高。
   **建议拆成 3 单**：不可逆类（`delete`+`archive`）→ 质量闸门类（`submit`+`reject`）→ 状态类（其余 5 个）。
3. **角色矩阵仍无 `verify` 等条目**（`enforce` 只认 publish/archive/delete/claim）——
   加门后仍只能查「ns 写权限」，查不到「角色是否够格」。**需另立**。
4. **`by` 参数语义不一致**：`reject` / `archive` 有 `by`，其余 7 个没有 ——
   修的时候要决定「统一新增 `agent`，还是复用 `by`」。

---

## 五、建议入档位置

| 内容 | 位置 |
|---|---|
| 本普查结论（3 有门 / 9 缺陷 / 2 特权） | 账本新条目，关联 BUG-467 |
| **「按形状搜」的方法论** | 判例集（与 gamma BUG-441 同族，本条是**身份门形状**）|
| **「修个案 ≠ 修同族」** | 判例集：上单我只修 `verify` 的教训 |
| 修法建议（新增可选 `agent` + `agent_write_gate`，`manual` 兜底） | 后续 3 单的任务包输入 |
