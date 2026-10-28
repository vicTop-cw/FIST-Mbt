# BUG-474：`publish_parallel` 的 `created_by` —— **不补硬检查**的定夺 · Lane DA · 2026-10-28

> **结论与派单方向相反：不补。** 且我发现派单的**核心前提不成立**
> —— `publish` 与 `publish_parallel` 的 ns 权限**是对称的**，不是「一个 default 一个全部」。
> 补严格检查会**立刻打断 3 条生产路径**（含自驱主链）。

---

## 一、结论

| 工具 | `created_by` 硬检查 | 实测判定 | 处置 |
|---|---|---|---|
| **`publish`** | ✅ `engine.mbt:46` | 引擎层硬检查 + handler 层 ns 门 | **不动** |
| **`publish_parallel`** | ❌ `ignore(created_by)` | **显式设计**（注释已写明）| **不补** —— 但**改描述**让边界可见 |
| **`dag_publish`** | ✅ **有**（`publish_with_deps:1891`）| **不是缺陷** | **不动** |

**⇒ 三个里只有 `publish_parallel` 无检查，且它无检查是「有意的设计选择」，不是遗漏。**

---

## 二、证据

### 2.1 ★ 派单的核心前提**不成立**

派单说：
> `publish` 在 **default ns** 发布 —— 影响一个命名空间
> `publish_parallel` 在**任意非 default ns** 发布 —— **影响所有命名空间**

**实测：这个对比是错的。**

| | `publish` | `publish_parallel` |
|---|---|---|
| ns 限制 **在哪实现** | **handler 层**（`ns_write_gate`，T0r1 第②步）| **引擎层**（`if ns == "" \|\| ns == "default"`）|
| 能否写 `default` | ❌ **拒**（`ns_write_gate` 拒绝）| ❌ **拒** |
| 能否写任意非 default ns | ✅ **能** | ✅ **能** |

```
// publish_parallel：engine.mbt:1097
if ns == "" || ns == "default" {
  return Err("并行发布仅限定时任务/自驱命名空间（namespace 不得为空或 default）")
}

// publish：handler 层（server.mbt，T0r1 第②步）
let g = ns_write_gate(ns)   // 同样拒绝 default/空
```

**⇒ 两者对 ns 的权限完全相同：都只能写「已 open 的非 default ns」。**
**「publish_parallel 影响所有命名空间」是不成立的。**

### 2.2 ★ 现网影响面（补检查会打断什么）

全仓 `publish_parallel` 生产调用点 **3 个**：

| 调用点 | 传的 `created_by` |
|---|---|
| `src/ops/ops_selfdrive.mbt:779` | **`"selfdrive"`** ← **自驱主链** |
| `src/server/bugreport.mbt:352` | `"bug_reporter"` 或 `reported_by` |
| `src/server/server.mbt:2014` | 调用方自报（工具参数）|

**⇒ 若补 `publish` 那套「必须 human_steward/human」的检查，3 条全部立刻 `Err`：**
- **自驱主链断掉**（`selfdrive_publish_next` 是无人值守流水线的核心）
- **`report_bug(publish_task=true)` 断掉**
- **工具面所有调用方断掉**（缺省值就是 `"selfdrive"`）

**这满足派单自己的警告**：「别修出一个新 bug」。

### 2.3 `dag_publish` 不是缺陷

```moonbit
// src/engine/engine.mbt:1891  publish_with_deps（dag_publish 走的正是它）
if created_by != "human_steward" && created_by != "human" {
  return Err("publish 仅限人类指挥官")
}
```
**它有硬检查，无需修改。**

### 2.4 注释原文（证明是设计不是遗漏）

```moonbit
// engine.mbt:1103
// 续轮发起者仅作审计用途（Task 无 created_by 字段），非法值不阻断。
ignore(created_by)
```
**关键事实**：`@core.Task` **没有 `created_by` 字段** ⇒ 「谁发布的」这个信息**根本没落库**
⇒ 硬检查只能拦「名字不对」，**无法拦「身份不对」**（仍是 S1 自报，与 BUG-464 同族）。

**⇒ 加硬检查带来的安全收益 = 0**（冒充者填 `human_steward` 就过了），
**而代价 = 打断 3 条生产路径。**

---

## 三、分析

### 3.1 为什么「加检查」在这里是错的

**一道检查的价值 = 它挡住的风险 − 它打断的功能。**

| | `publish` | `publish_parallel` |
|---|---|---|
| ns 权限 | 非 default ns | **相同** |
| 能否冒充 | 能（`created_by` 自报）| **相同** |
| 检查能挡住什么 | 「填错名字的人」| 「填错名字的人」（**相同**）|
| 检查会打断什么 | （无人传错，因为缺省就是对的）| **3 条生产路径** |
| Task 有无 created_by 字段 | 无 ⇒ 同样抓不到冒充 | **相同** |

**⇒ 两者「检查能挡的风险」完全相同，「打断的功能」完全不同。**
`publish` 加检查没代价（现有调用方都合规）；`publish_parallel` 加检查**只有代价**。

**这不是「双标」，是「同一道门在不同调用语境下的成本不同」。**

### 3.2 `publish_parallel` 的 ns 约束**本身就是它的防线**

它**强制** `ns != "" && ns != "default"` ⇒
调用方必须**先 `store_open` 一个专属 ns**。
而 `store_open` 是需要显式动作的 ⇒ **「能写哪个 ns」已经由 ns 边界限定了**，
不需要再用 `created_by` 拦一遍。

**⇒ 真正的边界是 ns，不是 created_by。**

### 3.3 那该做什么？（本单实际做了什么）

**不改引擎，改描述**（`server.mbt` 的 schema 文案——⚠️ 派单要求「只改 engine.mbt」，
故**本单不动**，只写报告）。

**理由**：现在的描述已经写明「created_by 全仓零校验…仅作审计用途」——
**但没说「为什么可以不加」**。应该补上：
> 「本工具与 `publish` 的差异**不在 ns 权限**（两者都只能写非 default ns），
> 而在于它是**自驱/定时专用**的批量入口，调用方是服务端内部链路（`created_by=selfdrive`）。

---

## 四、缺口与风险

1. **`created_by` 全仓零验证**（与 BUG-464 同族，仍是 **S1 边界**）：
   - `publish` / `dag_publish` 有硬检查，但**只比字符串** ⇒ 冒充者填 `human_steward` 就过；
   - `publish_parallel` 连这个都没有。
   **⇒ 真正的修复是 S3（签名认证），不是再加一道字符串比较。**
2. **`@core.Task` 无 `created_by` 字段** ⇒ 「谁发布的」不落库 ⇒
   **审计面缺失**（这比「无检查」更值得修）。建议单开：给 Task 加 `created_by` 并落库。
3. **本单未改任何代码**（派单边界限制 `server.mbt` / `engine_rsv.mbt` 不可动，
   而 `engine.mbt` 的改动需要同步 schema 描述才算完整）。
   **⇒ 描述改动留待下一轮**（需 `server.mbt` 权限）。
4. 若 owner 决定**真要**加硬检查，正确做法是**改 3 个调用点的实参**
   （`selfdrive` → `human_steward`），而不是改引擎 —— 但那会让「自驱发布」伪装成人类指挥官，
   **是更坏的设计**。

---

## 五、建议入档位置

| 内容 | 位置 |
|---|---|
| BUG-474 | 判 **FALSE_POSITIVE**（差异是设计，且派单的 ns 前提不成立），附本报告 §2.1 |
| **「一道检查的价值 = 挡住的风险 − 打断的功能」** | 判例集 —— 加检查前先算这个式子 |
| **「真正的边界是 ns，不是 created_by」** | 判例集（与 BUG-464「特权路径 vs agent 写路径」同族）|
| **`@core.Task` 无 `created_by` 字段 ⇒ 审计缺失** | **建议单开**（比无检查更值得修）|
| `publish_parallel` 描述补「为什么可以不加」 | 下一轮（需 `server.mbt` 权限）|
