# `execute` / `verify` 接 challenge 的定夺 · Lane CH · 2026-10-28

> **结论先行：两个都**不**接。** 核完代码后确认它们**都不经过角色取数面**
> ⇒ 接 `challenge` 是**死参数**（没有任何读者）。
> 派单也预判了这一点（引用了 R23 我的判例），我做了核实 + **加了 3 格锁钉住这个事实**。

---

## 一、结论

| 工具 | 属于哪种情况 | 接了吗 | 依据 |
|---|---|---|---|
| **`execute`** | **(a) 引擎层不经过角色取数面** | ❌ **不接** | `execute_with_meta` 里 `judged_role*` 出现 **0 次** |
| **`verify`** | **(a) 同上** | ❌ **不接** | `verify` 里 `judged_role*` 出现 **0 次**；它的门是 `omega_verify_gate` / `gate_verify_gate` / `docs_verify_gate`（**业务闸门，不是身份门**）|

**都不是 (b)「引擎层没接所以要改引擎」，也不是 (c)「接了但语义不同」。**

---

## 二、证据

### 2.1 引擎层实际签名与角色面

```moonbit
// src/engine/engine.mbt
pub fn FistEngine::verify(
  self : FistEngine,
  task_id~ : String,
  verifier~ : String,        // ← 自报字符串
  now~ : String,
  docs_check~ : Bool = false,
) -> Result[@core.Task, String] {
  match self.store.get_task(task_id) { ... }
  match self.omega_verify_gate(task_id) { ... }   // 业务闸门
  match self.gate_verify_gate(task_id)  { ... }   // 业务闸门
  match self.docs_verify_gate(task_id)  { ... }   // 业务闸门
```

```
$ grep -c "judged_role" (execute_with_meta 函数体)  → 0
$ grep -c "judged_role" (verify 函数体)             → 0
```

**`challenge` 的唯一消费者是 `judged_role_gated` / `judged_role_with_nonce`。**
这两个函数体都不调它们 ⇒ **`challenge` 传进来没有任何读者。**

### 2.2 全仓「谁真的有 `challenge` schema」

用判据式扫描（取每个 `"challenge": string_prop` 之前最近的一个工具注册点）：

```
agent_register_key, claim, lock_acquire, plan, reserve_scope
共 5 个工具
```

**⇒ 生命周期 14 个工具里，真正受 S3 保护的是 3 个**（`claim` / `reserve_scope` / `lock_acquire`），
`plan` 与 `agent_register_key` 是「发布/登记」面不属于生命周期 14。

### 2.3 三格锁（新增 `engine_execute_verify_no_challenge_wbtest.mbt`）

| 锁 | 断言 | 作用 |
|---|---|---|
| **`ch_execute_does_not_pass_role_resolution`** | `execute_with_meta` 函数体（**逐行扫、跳过注释**）里没有 `judged_role*` | 若将来 execute 真接入角色门 ⇒ 红 ⇒ 提醒「该接了」 |
| **`ch_verify_does_not_pass_role_resolution`** | `verify` 函数体同上；**并反向确认**它含 `omega_verify_gate(`（防我切错函数体而误判）| 同上 |
| **`ch_tools_do_not_declare_challenge_param`** | `execute`/`verify` 的 **schema 块**里不许有 `"challenge": string_prop(` / `"challenge_sig": string_prop(` | 防「**只加 schema 没接引擎**」的死参数（正是 R25 Alpha 发现的「接口与实现分叉」的**反向**版）|

**这 3 格的价值**：不是「跳过」，而是**把「为什么不接」变成可执行断言** ——
将来谁想改，会先撞上锁，被迫回答「四门清单与 S3 覆盖面是否需要重评」。

### 2.4 变异实测（**真跑**）

给 `verify` 的 schema 加上 `challenge` / `challenge_sig`（模拟「硬接一个死参数」）：
```
MoonBit: 0 errors（能编译 —— 死参数编译期抓不到，这正是要锁的原因）
moon test src/engine:
  汇总：Total tests 328 / passed 323 / failed 5
  F| "ch_tools_do_not_declare_challenge_param"     ← 精确抓住
```
恢复后回到全绿（另 4 格红来自并发 lane 的 `engine_bug430_keyed_must_sign_wbtest.mbt`，非本单改动）。

**⇒ 死参数在编译期完全合法，只有锁能抓。**

---

## 三、分析：生命周期 14 个工具里，几个真受 S3 保护？

| 工具 | 有 `challenge` | 为什么不 / 为什么该有 |
|---|---|---|
| `claim` | ✅ | 有角色门（RANK_GATE）—— 认领是「动手」，要认人 |
| `reserve_scope` | ✅ | 有角色门 —— 占作用域是「动手」 |
| `lock_acquire` | ✅ | 有角色门 —— 抢锁是「动手」 |
| `publish` / `publish_parallel` | ❌ | **特权入口**：`created_by` 硬检查（BUG-464 定夺：那是 S1 同族，不是 ACL 缺陷）|
| `plan` | ✅（但不属生命周期 14）| 拆分是写操作 |
| `execute` | ❌ | **无角色面** —— 不判「你是谁」 |
| `submit` / `verify` / `reject` | ❌ | **无角色面** —— 门是业务闸门 |
| `retry` / `pause` / `resume` / `reopen_task` | ❌ | 状态迁移，无角色面 |
| `archive` / `delete` | ❌ | 状态迁移，无角色面 |

**⇒ 14 个里只有 3 个（21%）真受 S3 保护。**

**这不是「还差 11 个没接」，而是「另外 11 个本来就不需要」。**
S3 保护的是**「谁在动手」**；`verify` / `execute` 这些工具**当前根本不问「你是谁」**，
所以「给它接 challenge」不会让它变安全 —— 它只是接了个没人读的参数。

**真正该问的问题**（本单不解决）：
> **`verify` 该不该有身份门？** 现在的 `verifier` 是自报串，且 `verify` 无任何角色/ACL 检查
> ⇒ **任何调用方都能验收任何任务**。这是 S1 的另一个面（与 `created_by` 同族），
> 但它需要的是**先加身份门**，而不是「先加 challenge」（顺序反了）。

---

## 四、缺口与风险

1. **`verify` 无任何身份门**（比「没有 challenge」严重得多）：
   `verifier` 是自报串，函数体只调 `eng.verify(task_id, verifier, ...)`，
   **无角色门、无 ACL 门** ⇒ 任何调用方都能验收任何任务。
   ⇒ **正确顺序是：先定「verify 该由谁做」（加身份门），再谈 challenge。**
2. **`execute` 有 `agent_write_gate`**（tool 面 ≥36 行处），而 `verify` **没有** ——
   两者不对称，需要在 S1/S2 收口时统一。
3. **「接了死参数」编译期抓不到** —— 只能靠锁。本单补了 3 格。
4. 本单期间并发 lane 的 `engine_bug430_keyed_must_sign_wbtest.mbt` 在途
   （4 格红），非本单改动；已确认我的 3 格全绿。

---

## 五、建议入档位置

| 内容 | 位置 |
|---|---|
| 本单定夺 | 账本：`execute`/`verify` **不接 challenge**（引擎无角色面），附本报告链接 |
| **「死参数编译期合法，只能靠锁抓」** | 判例集（与判例-29「机制格 ≠ 实现路径格」同族：**接上一个没人读的参数**是第三种「假接线」）|
| **「`verify` 无身份门」** | **S1 风险项**（与 `created_by` 同族），建议单开 |
| **「接口与实现分叉」双向** | R25 Alpha 发现「引擎有、schema 没有」；本单防的是反向「schema 有、引擎没有」|
