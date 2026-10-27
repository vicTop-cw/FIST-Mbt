# BUG-441 Saga 内存后端落地 · Lane AZ · 2026-10-27

> **修的是「补偿序列静默为空」，不是「代码写错了」。**
> 可信性来自变异实测：把 `list_saga_actions` 改回 `[]` ⇒ **5 格锁全红**。

---

## 一、结论

| 项 | 结果 |
|---|---|
| 选哪个候选 | **(a) 补内存后端实现**（与 BUG-439 同一修法）|
| 根因 | 三方法在 `Mem` 分支全是占位：`Ok(())` / `[]` / `Ok(())` |
| 改了什么 | `MemoryStore` 加 `saga_log` + `saga_next_id`；三方法的 `Mem` 分支改为实读实写 |
| 编译 | `moon check --target js` → **0 errors** |
| 测试 | `src/store` **97/97/0**；全量 **1585/1585/0** |
| 新增锁 | **5 格**，变异实测 **5 格全红** |
| 与 heartbeat 的关系 | ✅ 补完后 saga **行为与 heartbeat 的 `persisted` 披露口径一致**（见 §3）|

---

## 二、证据

### 2.1 三个占位（修复前的原文）

```moonbit
/// 登记 Saga 补偿步骤（R92：SQLite 落库 durable action log，内存后端为 no-op）。
    Mem(_) => Ok(())                     // ← 静默丢弃
/// 列出某根任务的 Saga 补偿步骤（R92：内存后端返回空，SQLite 前向顺序）。
    Mem(_) => []                         // ← 恒空
/// 把指定 Saga 补偿步骤标记 done（R92：内存后端为 no-op，SQLite 幂等更新）。
    Mem(_) => Ok(())                     // ← 静默无操作
```

**`grep "fn SqliteStore::write_saga_action\|list_saga_actions\|mark_saga_actions_done"`**
只命中 `SqliteStore` —— **`MemoryStore` 从未实现过**（与 BUG-439 同族）。

### 2.2 可粘贴 patch

```diff
--- a/src/store/store.mbt
+++ b/src/store/store.mbt
@@ pub struct MemoryStore {
   circuit_breakers : Map[String, (...)]
+  // BUG-441：Saga 补偿日志
+  //   key = "<ns>\u0000<root_task_id>"（与 SQLite `WHERE ns=? AND root_task_id=?` 同口径）
+  //   value = 步骤数组（按登记顺序 = SQLite 的 ORDER BY id ASC）
+  //   每项 = (id, step, task_id, compensation, status)
+  saga_log : Map[String, Array[(Int32, String, String, String, String)]]
+  // 模拟 AUTOINCREMENT：单调递增、不复用
+  mut saga_next_id : Int32
 }
+
+fn saga_key(ns : String, root_task_id : String) -> String {
+  ns + "\u{0}" + root_task_id
+}

@@ pub fn MemoryStore::new()
+    saga_log: Map([]),
+    saga_next_id: 1,

@@ pub fn StoreBackend::write_saga_action
-    Mem(_) => Ok(())
+    Mem(m) => {
+      let k = saga_key(ns, root_task_id)
+      let rows = match m.saga_log.get(k) { None => [] ; Some(r) => r }
+      // 幂等：同 step 已存在 ⇒ **就地更新**（与 ON CONFLICT DO UPDATE 同口径）
+      let mut found = false
+      for i = 0; i < rows.length(); i = i + 1 {
+        let (old_id, old_step, _, _, _) = rows[i]
+        if old_step == step {
+          rows[i] = (old_id, step, task_id, compensation, "pending")
+          found = true
+          break
+        }
+      }
+      if !found {
+        rows.push((m.saga_next_id, step, task_id, compensation, "pending"))
+        m.saga_next_id = m.saga_next_id + 1
+      }
+      m.saga_log.set(k, rows)
+      Ok(())
+    }

@@ pub fn StoreBackend::list_saga_actions
-    Mem(_) => []
+    Mem(m) => match m.saga_log.get(saga_key(ns, root_task_id)) {
+      None => []
+      Some(r) => r.copy()      // 返回快照，后续 mark 不改变已返还的数组
+    }

@@ pub fn StoreBackend::mark_saga_actions_done
-    Mem(_) => Ok(())
+    Mem(m) => {
+      let k = saga_key(ns, root_task_id)
+      match m.saga_log.get(k) {
+        None => Ok(())          // 幂等无操作（与 SQLite UPDATE 0 行同口径）
+        Some(rows) => {
+          for i = 0; i < rows.length(); i = i + 1 {
+            let (id, step, task_id, compensation, status) = rows[i]
+            if ids.contains(id) && status != "done" {
+              rows[i] = (id, step, task_id, compensation, "done")
+            }
+          }
+          Ok(())
+        }
+      }
+    }
```

**语义对齐的三点**（逐条与 SQLite 版对照）：

| 语义 | SQLite 版 | 内存版（本 patch）|
|---|---|---|
| 幂等登记 | `ON CONFLICT(ns,root_task_id,step) DO UPDATE` | 同 step 就地更新（**保留旧 id**）|
| 顺序 | `ORDER BY id ASC` | 数组按 push 顺序（= 登记顺序）|
| mark done | `UPDATE … SET status='done' WHERE id IN (…)` | 遍历改 status（**不删行**）|

### 2.3 五格锁 + 变异实测

| 锁 | 断言 |
|---|---|
| **锁 1** | 写 3 步 ⇒ 读回 **3 条**，且**前向顺序**为 `s1,s2,s3`（此前恒 0）|
| **锁 2** | `mark_saga_actions_done` 后**列表里对应项 status 变 `done`**（此前 no-op ⇒ 列表不变 ⇒ **会重复补偿**）|
| **锁 3** | 同 step 重复登记 **就地更新**、不新增行、**id 不变** |
| **锁 4** | 不同 `(ns, root_task_id)` **不串味** |
| **锁 5** | 内存版与 SQLite 版 `list_saga_actions` **语义四字段逐项相等**（id 数值可不同）|

**变异实测（真跑，非设计）**：
```
# 把 list_saga_actions 的 Mem 分支改回 []
$ python scripts/moon_test_env.py --target js src/store
汇总：Total tests 97 / passed 92 / failed 5
F| bug441_mem_saga_write_then_list_roundtrip
F| bug441_mem_saga_mark_done_is_visible
F| bug441_mem_saga_write_is_idempotent_by_step
F| bug441_mem_saga_keys_are_isolated
F| bug441_mem_and_sql_saga_same_shape
# 恢复后 97/97/0
```
**⇒ 五格都有判别力。**

### 2.4 过程中一次「假失败」如实记录

首次跑锁时 **4 格红**，我一度以为实现没生效。隔离探针得到 **`1 != 3`**
（写 1 条、读回 1 条 —— **实现是对的**），排查发现是**我自己的测试写错了**：
写入时没传 `ns`（落 `"default"`），读取却查 `"ns1"` ⇒ **ns 不匹配**。
修正后 97/97 全绿。

**⇒ 教训与判例-33 同族**：**红不一定是实现坏，先隔离确认「被测面到底在哪」**。
探针的价值就在这里 —— 它把「4 格红」缩小成「1 != 3」这一个读数。

---

## 三、分析

### 3.1 为什么它比 BUG-439 更隐蔽

| | 熔断器（BUG-439）| Saga（本条）|
|---|---|---|
| 占位返回 | `None` / `Ok(())` | `[]` / `Ok(())` |
| **正常系统里合法吗** | `state` 恒 `closed` **有点异常**（从未熔断过）| **「没有待补偿步骤」完全合法** |
| 暴露时机 | 需要累积到 threshold | **永远不暴露** —— 空列表不是错误信号 |

**⇒ 熔断器至少还有一个「怎么从没开过」的疑点；Saga 的空列表连疑点都没有。**
`list_saga_actions` 返回 `[]` 时，调用方只会想「这一步没有需要补偿的」——
**而这句话在任何正常系统里都是对的**。

**这就是我选 (a) 而不是 (b) 的核心理由**：
(b) 的「加 `persisted:false` 披露」对熔断器有效（有个异常态可对照），
**但对 Saga 无效** —— 因为披露的前提是「有人会去看那个字段」，
而这里的调用方**根本不会怀疑返回为空**。

### 3.2 与 heartbeat 的对照（统帅点名要写）

**heartbeat 做对了**（`server.mbt:3159`）：
```moonbit
"persisted": Json::boolean(store_ok && hb_backend == "sqlite"),
```
—— 它**明确披露**「内存后端不持久化」，调用方能看见。

**saga 之前没做**：三个方法静默返回合法值，**回执里没有任何 `persisted` 字段**。

**补完之后的关系**：
| | heartbeat | saga（本 patch 后）|
|---|---|---|
| 内存后端 | **不持久化**（进程重启丢失）| **不持久化**（同） |
| 是否披露 | ✅ `persisted:false` | ⚠️ **尚未在引擎侧回执披露** |
| 行为是否一致 | — | **功能上一致了**（都能在进程内累积），**披露上还不一致** |

**⇒ 本单只补齐了「能用」；「披露」仍需在引擎侧补 `persisted`** —— 见 §四 缺口 1。

---

## 四、缺口与风险

1. **引擎侧回执尚未披露 `persisted`**。本单修的是 store 层（能累积），
   **但 `saga_register` / `saga_rollback` 的回执里仍然没有「内存后端不持久化」的说明**。
   按 heartbeat 的口径，应在引擎侧（`engine_saga.mbt` / `server.mbt`）加
   `persisted: backend=="sqlite"`。**但 `engine_saga.mbt` 本轮在途，我没有碰。**
   ⇒ **建议另立单**，与 BUG-439 的三态测试一并做。
2. **内存版不存 `created_at`**：`list_saga_actions` 不返回它、它不参与任何判定 ⇒ 两侧读回形状一致。
   **若将来要按 `created_at` 排序/审计，内存版会缺这一列。**
3. **`saga_log` 无界**：按 `(ns, root_task_id)` 累积，无 GC。
   Saga 通常短命（一个根任务补偿完就结束），但**没有清理机制** —— 长跑进程会涨。
4. **`saga_next_id` 是进程级单调计数器**，与 SQLite 的 AUTOINCREMENT 语义一致（不复用），
   但**跨进程不共享**（内存后端本来就不跨进程）。

---

## 五、建议入档位置

| 内容 | 位置 |
|---|---|
| BUG-441 修复 | 账本挂 `- fix: reports/2026-10-27-bug441-saga-memory-plan.md` |
| **「占位返回值恰好合法」的分级** | 判例集：BUG-439（`state` 恒 `closed`，有疑点）vs BUG-441（空列表，**连疑点都没有**）|
| **「披露式修复 (b) 对合法空值无效」** | 同判例：披露的前提是「有人会怀疑」，而空列表不引发怀疑 |
| **「红先隔离再归因」** | 判例-33 补充（本单实测：4 格红 → 探针 `1 != 3` → 是我测试的 ns 写错）|
| 引擎侧 `persisted` 披露 | 建议单开（与 BUG-439 三态测试合并）|
