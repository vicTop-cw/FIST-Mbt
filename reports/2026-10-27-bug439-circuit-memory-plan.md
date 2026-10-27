# BUG-439 熔断器内存后端落地 · Lane AV · 2026-10-27

> **修的是「保护从未生效」，不是「代码写错了」。**
> 修复的可信性不来自「代码看起来对」，而来自 **变异实测**：把实现改回原状 ⇒ **4 格锁全红**。

---

## 一、结论

| 项 | 结果 |
|---|---|
| 根因 | `StoreBackend::cb_get(Mem)` **恒返回 `None`**；`cb_save(Mem)` **是 no-op** |
| 症状 | `failures` 恒 0 ⇒ `nf = 1` ⇒ `1 >= threshold(3)` 永不成立 ⇒ **内存后端永不熔断** |
| 形态 | **假绿**：工具不报错、回执字段齐全、保护从未生效 |
| 修法 | `MemoryStore` 加 `circuit_breakers` 字段；`StoreBackend::cb_get/cb_save` 的 `Mem` 分支改为实读实写 |
| 编译 | `moon check --target js` → **0 errors** |
| 测试 | `src/store` **92/92/0**；全量 **1580/1580/0** |
| 新增锁 | **4 格**，变异实测 **4 格全红** |
| 双后端等价 | ✅ `cb_get` 读回**七元组逐字段相等**（锁 3 真跑证明）|

---

## 二、证据

### 2.1 根因：代码里就有自证的注释

```moonbit
// src/store/store.mbt（修复前）
/// 读取某熔断器记录（R104：**内存后端返回 None**，SQLite 实读）。
pub fn StoreBackend::cb_get(...) -> (...) ? {
  match self {
    Mem(_) => None                    // ← 恒 None
    Sql(s) => s.cb_get(ns, circuit)
  }
}

/// 写入/覆盖熔断器记录（R104：**内存后端为 no-op**，SQLite 幂等 upsert）。
pub fn StoreBackend::cb_save(...) -> Result[Unit, String] {
  match self {
    Mem(_) => Ok(())                  // ← 永远成功，什么也没做
    ...
  }
}
```
**`grep "fn .*cb_get\|fn .*cb_save" src/store/*.mbt` 只命中 `StoreBackend` 与 `SqliteStore`**
—— `MemoryStore` **从未实现过这两个方法**（不是「实现错了」，是「压根没有」）。

### 2.2 推演链（为什么它是「假绿」而非「报错」）

```
cb_get → None           ⇒ failures = 0（引擎侧读到 0）
nf = failures + 1       ⇒ nf = 1（每轮都从 0 开始）
nf >= threshold(3)      ⇒ 1 >= 3 恒 false
cb_save(no-op)          ⇒ 连这 1 也不落
⇒ state 永远 closed，永不 Open，永不 Half-Open
```

**工具不报错、回执字段齐全（`{state:"closed", failures:0, ...}`）、保护从未生效** ——
这正是 gamma 说的「假绿」：**回执越是完整，越没人怀疑它**。

### 2.3 可粘贴 patch

```diff
--- a/src/store/store.mbt
+++ b/src/store/store.mbt
@@ pub struct MemoryStore {
   assistant_reg : Map[String, AssistantReg]
+  // BUG-439：熔断器记录（R104 的资源门，此前内存后端**从未实现**）
+  //   key = "<ns>\u0000<circuit>"（与 SQLite 侧 UNIQUE(ns, circuit) 同口径）
+  //   value = (state, failures, window_secs, threshold, recovery_secs, opened_at, last_fail_ts)
+  circuit_breakers : Map[String, (String, Int32, Int32, Int32, Int32, Int32, Int32)]
 }
+
+///|
+/// BUG-439：熔断器记录的进程内复合键（与 SQLite 的 `UNIQUE(ns, circuit)` 同口径）。
+/// 用 `\u{0}` 分隔而不是 `:` —— ns / circuit 名里可能出现 `:`，用 `:` 会有键碰撞。
+fn cb_key(ns : String, circuit : String) -> String {
+  ns + "\u{0}" + circuit
+}

@@ pub fn MemoryStore::new() -> MemoryStore {
     assistant_reg: Map([]),
+    circuit_breakers: Map([]),
   }
 }

@@ pub fn StoreBackend::cb_get(...
-    Mem(_) => None
+    Mem(m) => m.circuit_breakers.get(cb_key(ns, circuit))
     Sql(s) => s.cb_get(ns, circuit)

@@ pub fn StoreBackend::cb_save(...
-    Mem(_) => Ok(())
+    Mem(m) => {
+      m.circuit_breakers.set(
+        cb_key(ns, circuit),
+        (state, failures, window_secs, threshold, recovery_secs, opened_at, last_fail_ts),
+      )
+      Ok(())
+    }
     Sql(s) => s.cb_save(...)
```

**为什么内存版不存 `updated_at`**：`cb_get` 返回的七元组**不含它**，它只用于库内审计/排序、
**不参与三态判定** ⇒ 两侧读回形状一致（锁 3 真跑证明）。

### 2.4 四格锁 + 变异实测

新文件 `src/store/store_bug439_cb_wbtest.mbt`：

| 锁 | 断言 |
|---|---|
| **锁 1** | `cb_save` 后 `cb_get` **必须读得回**，七个字段逐一相等 |
| **锁 2** | **`failures` 真的会累积到 threshold**（模拟三轮失败：0→1→2→3，断言最终 `3 >= threshold`）|
| **锁 3** | 内存版与 SQLite 版 `cb_get` **七元组逐字段相等**（双后端等价）|
| **锁 4** | 不同 `(ns, circuit)` **不串味**（复合键正确性；用 `a:b`/`c` 与 `a`/`b:c` 这对易碰撞样本）|

**锁 2 是「保护真的生效」的核心证据**：它不是断言「代码看起来对」，
而是**真的跑三轮累积**、断言 `failures` 到达阈值 —— 修前每轮都从 0 开始，永远到不了 3。

**变异实测（真跑，非设计）**：
```
# 把 cb_get 改回 None、cb_save 改回 no-op（= 恢复 BUG-439 原状）
$ python scripts/moon_test_env.py --target js src/store
汇总：Total tests 92 / passed 88 / failed 4
F| bug439_mem_cb_save_then_get_roundtrip          failed
F| bug439_mem_cb_failures_accumulate_to_threshold failed
F| bug439_mem_and_sql_cb_get_same_shape           failed
F| bug439_mem_cb_keys_are_isolated                failed
# 恢复后 92/92/0
```
**⇒ 四格都有判别力；修复是真的在起作用。**

---

## 三、分析（为什么内存后端会失效）

**这不是「弃用后失修」，而是「从未被正确实现」。**

gamma 把它归到「弃用不等同于无害」家族，我给一个更准确的分型：

| 形态 | 例 | 特征 |
|---|---|---|
| **弃用后腐化** | `locks_upsert`（BUG-438）| 曾经对，改走别的路后没人再跑 ⇒ 静默腐化 |
| **从未实现**（本条）| `cb_get`/`cb_save` 的 `Mem` 分支 | **一开始就写成了占位**，且占位的返回值**恰好是合法值** |

**第二条更危险**，原因有二：

1. **占位返回值是「合法值」不是「错误」**：`None`（= 没有记录）和 `Ok(())`（= 写成功）都是
   **类型正确的正常返回**，编译器不会报、调用方不会疑。
   如果它 `panic` 或返回 `Err`，早就在第一次跑的时候被抓了。
2. **它只在「需要累积」的逻辑里暴露**：熔断器是唯一依赖「跨调用状态」的地方。
   单次调用看起来完全正常（failures=0 是合法初值）⇒ **只有把三次失败串起来跑才会发现**。

**⇒ 这类 bug 的唯一可靠防法是「跨调用的状态累积测试」**（锁 2 就是它），
而不是「单次调用的返回值测试」—— 后者对 `None`/`Ok(())` 这两个合法占位值**完全无感**。

---

## 四、缺口与风险

1. **引擎侧的三态判定我未改也未测**：本单只修了**存储层**的读写。
   `circuit_status` 的 half-open 到期判定（`elapsed >= recovery_secs`）依赖真实时间，
   本单的锁**没有覆盖它**（锁里用的是固定的 `recovery_secs` 与人工时间戳）。
   **建议另立一单**：用确定性时间注入测三态迁移（closed→open→half_open→closed）。
2. **`updated_at` 内存版不存**。当前无消费方（`cb_get` 不返回它），但若将来有人要按
   `updated_at` 做库内审计，内存版会缺这一列。**已写进代码注释。**
3. **`MemoryStore` 是无界 Map**：`circuit_breakers` 键数随 `(ns, circuit)` 组合增长，无 GC。
   熔断器数量通常很少（每 ns 每外部依赖一个），但**不设上限是个已知取舍**。
4. **本单未改 `store_sqlite.mbt`**（HumanSteward 独占，且本次不需要改）。

---

## 五、建议入档位置

| 内容 | 位置 |
|---|---|
| BUG-439 修复 | 账本挂 `- fix: reports/2026-10-27-bug439-circuit-memory-plan.md` |
| **「从未实现」vs「弃用后腐化」的分型** | 判例集（补充 gamma 的「弃用 ≠ 无害」，这是**第二种**形态）|
| **「占位返回值是合法值 ⇒ 编译器与单次调用都抓不到」** | 同判例的机理段 |
| **「跨调用状态累积测试」是该族的唯一可靠防法** | 锁 2 的范式，建议写进 AGENTS 的变异对照节 |
| 三态迁移未测 | 建议单开（确定性时间注入）|
