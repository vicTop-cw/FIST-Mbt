# BUG-469：六工具接 `challenge` 的定夺 + 3 处死参数收尾 · Lane CW · 2026-10-28

> **六个全部不接。** 用我自己在 BUG-472 立的判据核完，六个引擎**都没有 challenge 消费点**。
> 3 处死参数：1 处是判据误报（已修判据）、2 处是设计如此（已改描述），
> **`check_dead_params.py` 现在报 0 处死参数，rc=0**。

---

## 一、结论

### 1.1 任务 1：六工具逐一结论

| 工具 | 引擎函数 | 有挑战消费点？ | 结论 |
|---|---|---|---|
| **`execute`** | `execute_with_meta` | ❌ **无** | **不接**（R23 已证，本单复核仍成立）|
| **`submit`** | `submit` | ❌ **无** | **不接** |
| **`verify`** | `verify` | ❌ **无** | **不接**（BUG-467 加的是 **ACL 门**，不是角色门）|
| **`reject`** | `reject_task` | ❌ **无** | **不接** |
| **`retry`** | `retry_task` | ❌ **无** | **不接** |
| **`archive`** | `archive_force` | ❌ **无** | **不接** |

**判据**：`challenge` 的唯一消费者是 `judged_role_gated` / `judged_role_with_nonce`。
全仓生产代码的消费点（实测清单）：
```
engine.mbt      FistEngine::claim                    （judged_role_with_nonce）
engine_rsv.mbt  rsv_set / rsv_try_set / locks_try_acquire
                / challenge_pending_count            （judged_role_gated）
```
**六个目标工具一个都不在这份清单里** ⇒ 接了也是**死参数**（判例-29 的第三种「假接线」）。

### 1.2 任务 2：3 处死参数收尾

| # | 工具 | 参数 | 派单判的类别 | 实测 | 处置 |
|---|---|---|---|---|---|
| 1 | `loop_create` | `items` | B 该摘 schema | ❌ **误报** | **修判据**（见 §2.2），不摘 |
| 2 | `lock_acquire` | `ts` | C 设计如此 | ✅ 正确 | **改描述** |
| 3 | `lock_renew` | `ts` | C 设计如此 | ✅ 正确 | **改描述** |

**`check_dead_params.py` 最终读数（rc=0）**：
```
[扫描] 工具块 354 · 含 schema 声明的工具 88
       读取干净 23 · opaque 13 · 死参数 0 · 设计如此 2
[设计如此 · 不判死] schema 描述里已写明「服务端覆盖」：
  = server.mbt:6113  lock_acquire               覆盖：ts
  = server.mbt:6187  lock_renew                 覆盖：ts
[结论] 无死参数。**这不等于没有问题** —— opaque 的工具本判据看不见。
```
**selftest 14/14 通过。**

### 1.3 ★ 14 个生命周期工具里，几个真受 S3 保护？

| 档位 | 工具 | 数量 |
|---|---|---|
| **真受 S3（challenge 验签）** | `claim`（+ `reserve_scope` / `lock_acquire` 非生命周期）| **1 个** |
| **有身份门但无 S3** | `execute` / `verify` / `submit` / `reject` / `plan` / `retry` / `pause` / `resume` / `reopen_task` / `archive` / `delete` | **11 个** |
| **特权路径（`created_by` 硬检查）** | `publish` / `publish_parallel` | **2 个** |

**⇒ 14 个里只有 `claim` 1 个真受 S3 保护；剩 13 个不需要 challenge，理由是它们没有角色取数面。**

### 1.4 门禁

| 项 | 结果 |
|---|---|
| 编译 | `moon check --target js` → **0 errors** |
| 测试 | `src/server` + `src/engine` **872/872/0** |
| `check_dead_params.py` | **0 处死参数，rc=0**；selftest **14/14** |
| 变异对照 | **2 个真跑**，都精确打红 |

---

## 二、证据

### 2.1 三格锁（`server_bug469_no_challenge_wbtest.mbt`）

| 锁 | 断言 |
|---|---|
| **`cw_01`** | ★ **双向**：六工具 schema **不许**声明 `challenge`，**且**六个引擎函数里**不许**出现 `judged_role*` |
| **`cw_02`** | ★ **消费点白名单**：六个目标工具的引擎函数**都不在**挑战消费点清单里（按**函数名**断言，不按裸计数）|
| `cw_03` | `lock_acquire.ts` / `lock_renew.ts` 的描述**必须**含「服务端盖章」 |

**变异实测（都真跑）**：

| 变异 | 结果 |
|---|---|
| **M1** 给 `execute` 的 schema 加回 `challenge` | **535/536**，**`cw_01` 精确打红** |
| **M2** 给 `FistEngine::reject_task` 加 `judged_role_gated` | **534/536**，**`cw_01` + `cw_02` 双双打红** |

**M2 是双向断言的价值证明**：只断言「schema 没声明」不会红，只断言「引擎没角色门」也不够
—— 两段都断，才能抓住「引擎加了门但 schema 没接」和「schema 加了但引擎没门」两个方向。

### 2.2 `loop_create.items` 是**误报** —— 修的是判据，不是代码

```moonbit
// loop_create 的 schema（原文）
"steps": Json::object({
  "type": Json::string("array"),
  "description": Json::string("step mode 数组，…"),
  "items": string_prop("单个 step mode"),   // ← 这是 steps 数组的**元素声明**
}),
```
**`items` 是 JSON Schema 里 `steps` 数组的元素类型声明（给客户端看的）**，
**不是工具顶层入参** —— handler 读 `steps` 数组即可，永远不需要读 `items`。

旧判据的 `declared()` 用一条正则扫**整段 schema**，**不区分嵌套层级** ⇒ 把 `items` 判成死参数。

**修法**（`scripts/check_dead_params.py`）：
新增 `_top_level_pairs()`，用**括号深度**跟踪，只在**深度 1**（`schema({...})` 直属层）收集字段名
⇒ `items` 不再被误判。**`loop_create` 不需要改代码。**

### 2.3 `ts` 属 C 类 —— 改描述 + 给判据加 C 类认定

**描述改动**（`lock_acquire` / `lock_renew`）：
```diff
- "ts": string_prop("获取时间戳（可选，默认当前时间）"),
+ "ts": string_prop(
+   "获取时间戳（可选）。⚠️ **时间戳由服务端盖章（BUG-33 政策），此字段不接受覆盖** " +
+   "—— 传了也会被服务端时间覆盖（handler 用 now_default()）",
+ ),
```

**判据改动**：旧判据没有 C 类机制，只会报「未读」。新增 `BY_DESIGN_MARKERS`
（`服务端盖章` / `不接受覆盖` / `会被服务端时间覆盖`）+ `_is_by_design()`：
- 该参数 schema 描述里**已写明**服务端覆盖 ⇒ 归入 `[设计如此]`，**不判死**，但**单独列出**
- 描述被改回去 ⇒ **立刻回到死参数**（不静默消失）

**这就是 C 类的正确形态**：不是「让它消失」，是「让它被明确标注，且标注本身可被变异检测」。

---

## 三、分析

### 3.1 为什么有的接有的不接

**核心判据：引擎有没有 `challenge` 的读者。**

`challenge` 不是「通用的访问令牌」，它只被 `judged_role_gated` / `judged_role_with_nonce` 消费。
这两个函数的语义是「**用签名证明你就是你自称的那个角色**」。

- `claim` / `reserve_scope` / `lock_acquire` 要判**角色**（Leader vs Agent 有不同的权限）
  ⇒ 需要知道「你是谁」⇒ challenge 有意义。
- `execute` / `submit` / `verify` / `reject` / `retry` / `archive` **不判角色**
  ⇒ 它们只需要「你能不能在这个 ns 写」（ACL 门，BUG-471 已加）
  ⇒ **challenge 传进去没人读**。

**⇒ 「有身份门」和「需要 challenge」是两件事**：
前者问「能不能写」（ACL），后者问「你是谁」（角色）。**ACL 不需要签名**。

### 3.2 为什么「不做」比「做了」难写

本单的交付物是两个**锁**而不是代码改动。**这恰恰是正确形态**：

- 若硬接六个 challenge，代码会增加 ~60 行，**功能零变化**（没人读）；
- 而且会给调用方**虚假的安全感**（「我传了签名，应该受保护了」）——
  这正是 BUG-472/473 讨论的「声明了但不验」。

**⇒ 「加锁钉住为什么不做」比「硬加一个没用的参数」有价值得多。**

---

## 四、缺口与风险

1. **S3 覆盖面仍然很窄**：14 个生命周期工具里只有 `claim` 真受 S3 保护。
   **这是设计使然**（其余工具不判角色），但**若将来要「谁能验收」也要按角色判**
   （如只有 Verifier 参谋能 verify），那时才该给 `verify` 接 challenge ——
   **顺序仍是先加角色门，再谈认证**（`cw_01`/`cw_02` 会提醒）。
2. **`opaque` 的 13 个工具本判据看不见**（handler 整包透传 args）
   ⇒ 它们里面可能**仍有**死参数，只是静态判不了。**这是已知边界，不是零风险。**
3. **`loop_create.items` 的误报修正只覆盖「嵌套 JSON Schema 声明」这一种**；
   若还有别的嵌套形态（如 `array_prop(items=...)` 关键字参数），需另判。
4. **本单未改任何业务代码**（只改描述 + 判据），故零回归风险。

---

## 五、建议入档位置

| 内容 | 位置 |
|---|---|
| BUG-469 | 账本判 **FALSE_POSITIVE / 设计如此**（六工具无消费点），附本报告 |
| **「有身份门 ≠ 需要 challenge」** | 判例集 —— ACL 问「能不能写」，challenge 问「你是谁」|
| **「加锁钉住『为什么不做』」** | 判例集（本单交付物是锁不是代码）|
| **判据的两处修正**（嵌套 schema 层级 / C 类认定） | `check_dead_params.py` 注释 + 判例-32 同族「探针要认得出真对象」|
| **S3 最终覆盖面**（14 → 1） | BUG-470（产品决策）的输入：是否要扩大角色门 |
