# R17 · engine/store「第二个实现」普查

> **任务**：① F3 覆盖 `file_locks` ② 角色取数面普查 ③ `MemoryStore` 覆盖复查
> **执行人**：司令-γ · **边界**：只读 + 报告（未改 `src/`，未碰 9 个在途文件）
> **产出**：本报告 + `temp/audit/lane_aq_filelocks.py` + 1 条 `report_bug`

---

## 结论（三任务分开写）

### 任务 1：`file_locks` 对表 → **发现 1 条真 bug（`BUG-438`）**

| 规则对 | 结果 |
|---|---|
`locks_try_acquire`（SQL `:1438`）↔ `rsv_action` 四分支 | **等价** ✓ 三子句逐条对应，两侧均严格 `<`
**`locks_upsert`（SQL `:1311`）↔ 内存版 `locks_upsert`** | **★ 语义相反**（`BUG-438`）

**内存版**（`store_rsv.mbt:299-317`）注释明写「**它永远落库（last-write-wins）**，只在覆盖他人 live 锁时留一条 `lock_taken_over`」。
**SQLite 版**（`:1311`）的 `WHERE status != 'active' OR agent = excluded.agent OR ttl_until < excluded.ts`
让它**在他人 live 锁时不写** ⇒ 变成了「会拒」，且**不记任何违例**。

### 任务 2：角色取数面 → **单一真源链完整，0 条 bug**

```
judged_role(eng, agent)                        ← 唯一取数面（engine_rsv.mbt:48）
  ├─ declared_role_for_judgment(eng, agent)    ← 上游①：查 agents 表（带过滤）
  └─ resolve_agent_role(agent, declared)       ← 上游②（engine_scope_perm.mbt:289）
       └─ infer_role_from_agent(agent_name)    ← 上游③：名字推断（最底层）
```

**四道门全部只走 `judged_role`**（`claim`@engine.mbt:180 / `rsv_set`@79 / `rsv_try_set`@111 / `locks_try_acquire`@219）。
**`resolve_agent_role` 的唯一调用点是 `judged_role` 本身**（其余命中全在注释里）⇒ **无绕行**。
**`estimate_rank`（BUG-432 的第二个实现）已不存在**（`grep -rn 'fn estimate_rank'` → 空）。

### 任务 3：`MemoryStore` 覆盖 → **未降低，6 处，0 条 bug**

```
grep -c 'MemoryStore' src/store/store_rsv_test.mbt  →  6   （曾在落锁前 = 0）
grep -c 'SqliteStore' src/store/store_rsv_test.mbt  →  19
双后端等价测试格：3 格（:993 rsv 四分支 / :1100 锁层 / :1170 locks_sweep）
```

**⇒ 并发 lane 没有删掉别人的双后端锁，反而把它从 0 抬到了 6。**
（该文件仍是 `M` 状态，但内容里 `MemoryStore` 的三处 `::new()` @949/1073/1171 都在。）

---

## 证据

### §1 任务 1：`file_locks` 两条 `ON CONFLICT` 逐字对比

**定位**（`store_sqlite.mbt`）：
```
:1311  →  pub fn SqliteStore::locks_upsert        @1256
:1438  →  pub fn SqliteStore::locks_try_acquire   @1427
```

**A. `locks_upsert` @1311**
```sql
ON CONFLICT(scope) DO UPDATE SET ...
  WHERE file_locks.status != 'active'
     OR file_locks.agent = excluded.agent
     OR file_locks.ttl_until < excluded.ts
```
**C. 内存 `locks_upsert` @299-317**
```moonbit
match self.file_locks.get(lock.scope) {
  Some(old) if old.status == "active" && old.agent != lock.agent &&
               old.ttl_until >= lock.ts =>
    self.lock_violations.push(LockViolation::{ reason: "lock_taken_over", ... })
  _ => ()
}
self.file_locks.set(lock.scope, lock)      // ★ 无条件写
```
| 维度 | 内存 | SQLite |
|---|---|---|
| 他人 live 锁 | **覆盖 + 记违例** | **不写 + 不记** |
| 设计意图 | 注释：「这是底层原语，不是互斥门：**它永远落库（last-write-wins）**」 | 与注释相反 |

**B. `locks_try_acquire` @1438** ↔ **D. 内存 @321-370（`lock_acquire_action` → `rsv_action`）**
```sql
WHERE file_locks.agent = excluded.agent       ↔  owner==agent → renewed        ✓
   OR file_locks.status <> 'active'           ↔  非 active 折成 None → reserved ✓
   OR file_locks.ttl_until < excluded.ts      ↔  ttl < now → taken_over        ✓
   （三子句全 false）                          ↔  else → conflict（不写）      ✓
```
**⇒ 完全对应，均严格 `<`。**

**三条独立旁证支持「`locks_upsert` 应当无条件覆盖」**：
1. 内存版注释（`store_rsv.mbt:296-298`）
2. `store.mbt:637-638`：「`locks_try_acquire`：被他人 live 持有时**拒绝，不覆盖**」—— 两函数职责必须不同
3. `claimguard_wbtest.mbt:1118/1240` 的夹具注释：**「重建物理层 `locks_upsert` 的「覆盖写 + 仅记违例」语义」**

**为什么没被发现（三重盲区）**：
- `locks_upsert` 的测试**只跑内存后端**（`store_rsv_test.mbt:270/341` 均 `StoreBackend::memory()`）⇒ SQLite 面零覆盖
- 工具面已不走它（`server.mbt:5671`：BUG-145 后改走 `locks_try_acquire`）
- 仅剩调用方是测试夹具 ⇒ 切 SQLite 后端时夹具造不出预期状态

**⇒ `BUG-438` [medium] 已上报。**

### §2 任务 2：角色取数面的「形状普查」（不搜注释，搜调用关系）

**搜法**：`grep -rnE 'fn .*(role|rank).*\(.*agent' src/engine/*.mbt src/server/*.mbt`（排除测试）
```
src/engine/engine_rsv.mbt:28       declared_role_for_judgment(eng, agent) -> String?
src/engine/engine_rsv.mbt:48       judged_role(eng, agent) -> (String, String)
src/engine/engine_scope_perm.mbt:187  infer_role_from_agent(agent_name) -> String
```

**调用方向（`grep -rn 'judged_role('` / `grep -rn 'resolve_agent_role('`）**：
```
judged_role 被调 3 处生产代码：engine.mbt:180 / engine_rsv.mbt:79 / :111 / :219
resolve_agent_role 被调 1 处：engine_rsv.mbt:49（= judged_role 函数体内）
estimate_rank        → 不存在
```

**⇒ 链是单向的、无旁路：** 四道门 → `judged_role` → `resolve_agent_role` → `infer_role_from_agent`。
**任何新门若不调 `judged_role`，就取不到 role**（没有第二个函数能返回 role）。**这是收口的正确形状。**

**唯一可讨论点**：`judged_role` 与 `declared_role_for_judgment` 是 `fn`（包内私有），
`resolve_agent_role` 是 `pub`（`engine_scope_perm.mbt:289`）。
⇒ **跨包仍可直接调 `resolve_agent_role`**（绕过 `declared_role_for_judgment` 的过滤）。
**当前无跨包调用方**（grep 为零），但**这是理论上的第二条路**。
建议后续把 `resolve_agent_role` 降为 `fn`（若确认无跨包用户）。

### §3 任务 3 读数

```
src/store/store_rsv_test.mbt:
  :898   // BUG-431 / Lane AJ：**双后端等价性锁**（MemoryStore ↔ SqliteStore）
  :901   //   落锁之前 grep -c 'MemoryStore' = 0
  :907   //   同输入喂 MemoryStore 与 SqliteStore::open(":memory:")
  :949   let mem = @store.MemoryStore::new()
  :1073  let mem = @store.MemoryStore::new()
  :1171  let mem = @store.MemoryStore::new()

测试格：
  :993   test "rsv 双后端等价：B1~B4 四分支 + ttl/now 边界 + agent 三态"
  :1100  test "rsv 双后端等价：锁层无锁/有锁 + status 四种 + ttl 边界"
  :1170  test "rsv 双后端等价：locks_sweep 清扫数（Int32）一致"
```

**⇒ 覆盖从 0 → 6（3 处 `::new()` × 2 次 grep 命中），未降回 0。**

---

## 分析

### 「三子句 ↔ 四分支」这个形状，同一文件里有两份，但只有一份是对的

`file_locks` 的两条 `ON CONFLICT` **长得几乎一样**：

```sql
-- locks_try_acquire（:1438）—— 对的
WHERE agent = excluded.agent OR status <> 'active' OR ttl_until < excluded.ts

-- locks_upsert（:1311）—— 错的
WHERE status != 'active' OR agent = excluded.agent OR ttl_until < excluded.ts
```

**差别只有子句顺序**（`!=` vs `<>` 是同义的）。
**⇒ 光看 SQL 文本，这两条「看起来是同一条规则的两次书写」；但它们的宿主函数职责完全不同**（一个抢、一个覆盖）。

**这正是 R12 说的「按形状搜只能给候选，不能给结论」的又一个实例** ——
而且这次是**更难的形态**：不是「名字撞车」，而是**「两条含义相反的规则写成了同一个形状」**。
⇒ **判据无法只靠 SQL 文本区分，必须绑到宿主函数的语义（`locks_upsert` vs `locks_try_acquire`）。**

**给 `check_two_faces.py` 的 F3 一条改进建议**：
现在的 F3 只对表 `rsv_action ↔ reservations`。扩到 `file_locks` 时，
**必须按「宿主函数名 → 期望语义」建映射表**（`*_try_acquire` ⇒ 对照 `rsv_action`；
`*_upsert` ⇒ 对照「无条件覆盖」），不能只按表名 `file_locks` 匹配 ——
否则这条判据会把 `locks_upsert` 的 WHERE 也当成「与 rsv_action 对应」，**反而判它 PASS**。

### `locks_upsert` 这条的教训：注释说了「无条件」，SQL 说了「有条件」，谁赢？

**没人赢 —— 因为没人比较过。**
- 内存版有测试（`store_rsv_test.mbt:270/341`），SQLite 版没有
- 生产面绕开了这个函数，所以线上也没暴露
- ⇒ **一条「三面都缺一角」的路径**：内存测试有、SQLite 测试无、生产调用无

**这与 R10 的「内存 vs SQLite 两后端等价」是同一根因，但更隐蔽**：
R10 验的是**工具面还在用**的那两个函数（`rsv_try_set` / `locks_try_acquire`），
`locks_upsert` **因为被 BUG-145 弃用，反而没人再验它** ⇒ **弃用 ≠ 无害，弃用 = 失去验证**。

---

## 缺口与风险

### 1. `locks_sweep` 的 SQLite 侧本轮未对表

内存版（`store_rsv.mbt:412`）：`status == "active" && ttl_until < now ⇒ 标 expired`。
SQLite 侧（`store_sqlite.mbt:1671`）**未读、未对表**。
`store_rsv_test.mbt:1170` 有「`locks_sweep` 清扫数（Int32）一致」的双后端格 ⇒ **大概率已覆盖**，
但**我没有逐字核它的谓词**。**建议下轮补。**

### 2. `resolve_agent_role` 是 `pub`，理论上跨包可绕

见 §2。**当前零跨包调用方**，但收口不彻底。建议降 `fn`。

### 3. `file_locks` 的两条 `ON CONFLICT` 未被任何判据对表

`check_two_faces.py` 的 F3 只覆盖 `rsv_action ↔ reservations`。
本条 bug 是**人工对表**发现的 ⇒ **判据缺口仍在**。建议按 §分析 的「宿主函数 → 期望语义」映射表扩展。

### 4. 本轮未跑测试

`store_rsv_test.mbt` 仍在 `M` 状态（并发 lane 在改），**我没有跑 `moon test`**（会干扰且可能读到半成品）。
本报告的读数全部来自**静态形状比对 + 注释/夹具旁证**，**没有动态验证** `BUG-438` 的双后端差异。
**建议落地方**：先写一格双后端锁（同一组 (既有锁, 新锁) 喂两后端，断言 `locks_get` 与
`lock_violations_list` 都相同），**它现在会红**，修完转绿。

---

## 建议入档位置

| 内容 | 位置 |
|---|---|
| 本报告 | `reports/2026-10-27-r17-engine-store-audit.md` |
| `BUG-438` | `memory/bugs.md`（已写入，medium） |
| 对表脚本 | `temp/audit/lane_aq_filelocks.py`（含四条 SQL/内存规则逐条对比） |
| **建议后续** | ① `locks_sweep` SQLite 侧对表 ② `resolve_agent_role` 降 `fn` ③ `check_two_faces.py` F3 扩到 `file_locks`（须带「宿主函数 → 期望语义」映射） |
| **未做** | **未调 `bug_fix`**（代码未落地）· **未改 `src/`** · **未跑测试**（文件在途） |
