# BUG-438 `locks_upsert` 双后端语义对齐 · Lane AS · 2026-10-27

> **本单的关键结论：BUG-438 在我接手前已由并发 lane 完整收口并提交。**
> 我的职责因此转为**独立验证 + 补变异对照 + 记录分析**，而不是重新实现。
> 本报告的价值在**独立核实**与**变异实测**，不在 patch 本身。

---

## 一、结论

| 项 | 结果 |
|---|---|
| 选哪个候选 | **(a) SQL 去掉 `WHERE`**（并发 lane 已落，我独立核实实现正确）|
| 修复状态 | **已提交** `dab69830`（修复）+ `5c7af75a`（账本标 FIXED）|
| 我的核实 | `grep INSERT INTO file_locks` ⇒ **含 WHERE: False** ✅ |
| 违例记录 | `WHERE scope=? AND status='active' AND agent != ? AND ttl_until >= ?` —— **与内存版条件逐字一致** ✅ |
| 测试 | `src/store` = **88/88/0**，**连跑 3 次全绿** |
| 变异对照 | **真跑**：把 `WHERE` 改回旧形状 ⇒ **锁 1 立刻红** ✅ |
| 生产调用方 | **零**（只有转发层定义与注释）⇒ 影响面最低 |

---

## 二、证据

### 2.1 内存版语义（基准）

```moonbit
// src/store/store_rsv.mbt:299
/// **这是底层原语，不是互斥门**：它永远落库（last-write-wins），只在覆盖他人 live 锁时
/// 留一条 `lock_taken_over` 事后审计。要「抢不到就拒」请用 `locks_try_acquire`。
pub fn MemoryStore::locks_upsert(self : MemoryStore, lock : FileLock) -> Unit {
  match self.file_locks.get(lock.scope) {
    Some(old) if old.status == "active" &&
      old.agent != lock.agent &&
      old.ttl_until >= lock.ts =>        // ← 违例条件（三合一）
      self.lock_violations.push(...reason: "lock_taken_over"...)
    _ => ()
  }
  self.file_locks.set(lock.scope, lock)  // ← **无条件覆盖**
}
```

**关键：`set` 在 `match` 之外** ⇒ 违例记录与落库**互不影响**，永远落库。

### 2.2 SQLite 版修复后的形状（实测）

```moonbit
// src/store/store_sqlite.mbt::locks_upsert
// ① 违例审计（修复保留）
let v_sql = "INSERT INTO lock_violations (ts, agent, scope, reason, lock_id)
             SELECT ?, ?, ?, 'lock_taken_over', ?
             FROM file_locks
             WHERE scope = ? AND status = 'active' AND agent != ? AND ttl_until >= ?"
// ② 无条件 upsert（修复点：**去掉了 WHERE**）
let sql = "INSERT INTO file_locks (…) VALUES (…)
           ON CONFLICT(scope) DO UPDATE SET …"      // ← 无 WHERE
```

**逐字核实**（脚本 `temp/audit/lane_as_sqlcheck.py`）：
```
=== locks_upsert 里的 INSERT 语句 ===
   let sql = "INSERT INTO file_locks (…) … ON CONFLICT(scope) DO UPDATE SET …"
  ⇒ 含 WHERE: False   期望 False（BUG-438 修复后应无 WHERE）
```
两处条件**逐字对齐内存版**：`status='active' AND agent != ? AND ttl_until >= ?`。

### 2.3 改的是哪一格、为什么那一格是错的（统帅点名要的）

**gemma 说「SQL 长得几乎一样，差别只是子句顺序」——实测后要纠正一句**：
两份 SQL 的 `ON CONFLICT … DO UPDATE SET …` 部分确实逐字相同，
**但差别不是「顺序」，是「有无 `WHERE` 子句」**：

| | 旧 SQLite | 新 SQLite | 内存版 |
|---|---|---|---|
| `DO UPDATE SET …` | 相同 | 相同 | — |
| **`WHERE`** | `status != 'active' OR agent = excluded.agent OR ttl_until < excluded.ts` | **无** | **无**（`set` 在 match 外）|

**那一格为什么错**：`WHERE` 的语义是「**条件满足才写**」。
而 `locks_upsert` 是**底层原语**（注释明写「永远落库」）⇒
**`WHERE` 让它在「他人持有 live 锁」时不写** ⇒ 与内存版**行为相反**，
且调用方**无从区分**自己在哪个后端上 —— 同一段业务代码内存里过、SQLite 里静默失效。

### 2.4 变异对照（真跑，非设计）

```
# 把 SQL 的 WHERE 改回旧形状
$ python scripts/moon_test_env.py --target js src/store
汇总：Total tests 88 / passed 87 / failed 1
F| locks_upsert_equiv_test.mbt:35
   "bug438_upsert_overwrites_others_live_lock_on_both_backends" failed
   ⇒ 断言 sql_owner == "B" 失败（SQLite 未覆盖，仍是 "A"）

# 恢复后
汇总：Total tests 88 / passed 88 / failed 0    ← 连跑 3 次均 identical
```
**⇒ 现有锁确实在看这一格，不是恒绿。**

### 2.5 过程中一次「假红」如实记录

首次跑 `src/store` 时 `bug438_…` **报红**，我一度以为修复不完整。
排查发现：**编译产物缓存未刷新**（前一次 `moon check` 因并发 lane 在途而失败，
测试跑的是旧产物）。`moon check` 转为 0 errors 后重跑 ⇒ 88/88 全绿，**连跑 3 次稳定**。

**⇒ 教训（判例-33 同族，Windows 面）**：**判据/测试要先确认被测产物是新鲜的**，
否则「红」可能是缓存的旧产物在说话 —— 与「进程跑的是旧构建」是同一类观测缺陷。

---

## 三、分析

### 3.1 为什么 SQLite 版会错（gamma 的分析，我核实后加强）

> **`locks_upsert` 因 BUG-145 被弃用，反而失去了验证。**
> **弃用不等同于无害，弃用等同于失去验证。**

**我补一条实测佐证**：`locks_upsert` 的**生产调用方为零**（只有 `engine_rsv.mbt:177` 的
转发定义与 `store.mbt:633` 的 StoreBackend 分派，无任何业务调用点）。
BUG-145 把 `lock_acquire` 改走 `locks_try_acquire` 之后，**这个原语就再没人跑过了** ——
于是两后端的语义分叉**没有任何测试会撞到**，直到 gamma 审计才发现。

**⇒ 这给了「弃用」一个新的风险类别**：
- 弃用的是**调用**，不是**代码**；代码还在 `pub` API 面上，会被后来人当「可用原语」调用；
- 而**没有调用 = 没有测试覆盖压力** ⇒ 它的行为可以静默腐化。

### 3.2 与 `locks_try_acquire` 的分工（不能混）

| | `locks_upsert` | `locks_try_acquire` |
|---|---|---|
| 定位 | **底层原语** | **互斥门** |
| 语义 | **永远落库**（last-write-wins） | **抢不到就拒**（conflict 时锁行不动）|
| 违例 | 覆盖他人 live 锁 ⇒ 记 `lock_taken_over`（**事后审计**）| 拒夺 ⇒ 记 `lock_denied`（**拒夺审计**）|
| 返回值 | `Unit` | `LockAcquireOutcome`（含 `granted` / `action`）|
| 谁在用 | **零生产调用方**（已弃用）| `lock_acquire` / `lock_renew` 工具面 |

**旧 SQLite 版的错误就是把两者的行为混在了一起** ——
给底层原语加了互斥门的条件写，导致「原语拒写」而「门以为是原语」。

---

## 四、缺口与风险

1. **本单未产生新代码**：修复已由并发 lane 提交（`dab69830`），我核实其正确性并补了变异实测。
   若统帅要「一名 lane 独立重做」，应明确说 —— 我按「不重复劳动」处理了。
2. **「阑尾 API」缺少护栏**：`locks_upsert` 零调用但仍是 `pub`。
   建议给它加 `#deprecated` 或在 docstring 首行写「**已弃用，仅保留给 `locks_sweep` 等内部路径**」，
   否则下一个调用它的人会以为它是可用原语。
3. **`moon fmt` 的附带改动**：我跑 `moon fmt` 时把 `store_rsv_test.mbt` 重排了 59 行（纯格式），
   已 `git checkout` 还原，未混入任何提交。
4. **stat-dirty 噪声**：`store_rsv.mbt` 显示 `M` 但 `diff --numstat` 为空（判例-21），未动它。

---

## 五、建议入档位置

| 内容 | 位置 |
|---|---|
| BUG-438 的 FIXED 状态 | **已由 `5c7af75a` 标记**，本报告是**独立核实**，不重开 |
| **「弃用 ≠ 无害，弃用 = 失去验证」** | 判例集（统帅点名要写，已在 §3.1 成段）|
| **「假红来自旧产物」** | 判例-33 同族补充（我实测踩到一次）|
| `locks_upsert` 零调用但仍 `pub` | 建议单开：加 `#deprecated` 或 docstring 首行警告 |
| 两后端语义对照表 | `scripts/README.md` 的 check_two_faces / store 条目附近可引用 |
