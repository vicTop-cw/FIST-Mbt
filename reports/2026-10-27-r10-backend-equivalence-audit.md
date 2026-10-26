# R10 后端裁决等价性审计 · 内存 vs SQLite

> **任务**：① 两后端裁决路径并排画出来 ② **真实执行**同一批输入比对 ③ 查「为什么单测永远绿」
> **执行人**：司令-γ · **边界**：只读 + 写报告（**探针已跑完并从 `src/` 移除**，副本存 `temp/audit/r10_probe/`）
> **产出**：本报告 · **0 条真 bug**（两后端等价）· 1 条结构性盲区（单测只覆盖一个后端）

---

## 结论

| 问题 | 结论 |
|---|---|
| **两个后端等价吗？** | **等价**（真实执行 20 组输入，**0 处不同**） |
| **差在哪？** | **裁决结果没有差异**；差异只在**实现形状**（内存版 `if may_write` 真判、SQLite 版 `ignore(may_write)` 交给 `ON CONFLICT`） |
| **单测覆盖了哪个后端** | **只覆盖 SqliteStore**（`store_rsv_test.mbt`：`SqliteStore` 13 处 / `MemoryStore` **0 处**） |
| **找到几条真 bug** | **0 条** |
| **但有一条结构性盲区** | **★ `MemoryStore` 的 rsv/锁面零测试覆盖** ⇒ 两后端可以静默漂移 |

---

## 证据

### §1 探针怎么跑的（真实执行，不是读代码）

**做法**：在 `src/store/` 下新建临时 `_test.mbt`（必须在 store 包内，因为
`RsvOutcome` / `LockAcquireOutcome` 字段是**包内私有**），
每个用例**真的**构造一个 `MemoryStore` + 一个 `SqliteStore::open(":memory:")`，
同一输入喂两边，把 6 个字段序列化成 JSON **断言相等**；不一致就 `abort` 并带回两侧原文。

**为什么用断言而不是 println**：`moon test` **会吞掉通过测试的 stdout**，
「打印后肉眼比对」在本仓不可行 ⇒ 改成断言（这一条本身也是个坑，记在 §4）。

**实测读数**（`python scripts/moon_test_env.py src/store`，以**汇总行为准**，BUG-142）：

| 阶段 | 读数 |
|---|---|
| 探针前基线 | `Total tests: 79, passed: 79, failed: 0` |
| + rsv 等价格（10 组） | `Total tests: 80, passed: 80, failed: 0` |
| + 锁等价格（10 组） | `Total tests: 81, passed: 81, failed: 0` |
| + 变异对照（2 格） | `Total tests: 83, passed: 83, failed: 0` |

**⇒ 20 组真实输入比对，0 处不同；4 格新增全部通过。**

---

### §2 两后端并排对比（四个函数）

#### 2.1 `rsv_try_set`

| | 内存版（`store_rsv.mbt:113-156`） | SQLite 版（`store_sqlite.mbt:~976-1000`） |
|---|---|---|
| 裁决来源 | `rsv_action(prev, agent, created_at)` → `(may_write, action)` | 同一函数取 `action`；`may_write` **被丢弃** |
| 写不写 | `if may_write { self.rsv_set(...) }` **真判断** | `ON CONFLICT(scope) DO UPDATE ... WHERE agent=excluded.agent OR ttl_until < excluded.created_at` —— **由 SQL 判** |
| 结论来源 | **写后回读** `rsv_get`（`:130`） | **写后回读** `rsv_outcome_after_write` |
| reserved 判定 | `Some((owner,..)) if owner == agent` | 同款写后回读 |
| conflict 的 `agent` 字段 | 库里现值 owner（`:144`） | 库里现值（同口径） |

**⇒ 形状不同（一个在应用层判、一个在 SQL 里判），但两者都**以写后回读定结论** ⇒ 语义等价。**

#### 2.2 `locks_try_acquire`

| | 内存版（`store_rsv.mbt:321-370`） | SQLite 版（`store_sqlite.mbt:1427-1520`） |
|---|---|---|
| 前置归一 | `lock_acquire_action(prev, ...)` → `(may_write, action)` | `lock_acquire_action` 取 `action`；`ignore(may_write)` |
| 写不写 | `if may_write { file_locks.set(scope, lock) }` | `ON CONFLICT(scope) DO UPDATE ... WHERE agent=excluded.agent OR status<>'active' OR ttl_until < excluded.ts` |
| 结论 | 写后回读 `locks_get` | 写后回读 `lock_outcome_after_write` |
| conflict 时违例记录 | `lock_violations.push(...)` | `lock_violation_insert(...)` |

**⇒ 同 §2.1 的结论：形状不同、语义等价。**

#### 2.3 `rsv_set`（非 try）

| | 内存版 | SQLite 版 |
|---|---|---|
| 语义 | 无条件写 | 无条件 `INSERT ... ON CONFLICT DO UPDATE`（无 WHERE）⇒ 等价 |

**⇒ 两者都是「无条件覆盖」，本就不承诺互斥（抢要用 `rsv_try_set`）。**

#### 2.4 `locks_sweep`

| | 内存版（`store_rsv.mbt:407`） | SQLite 版（`store_sqlite.mbt:1671`） |
|---|---|---|
| 语义 | 按 `now` 释放 TTL 过期锁 | 同 |
| **本轮是否比对** | **未比对**（见 §5 盲区 1） | — |

---

### §3 ★ 那条注释的原文与「三子句 ≡ 四分支」的**实测**结论

#### 3.1 `store_rsv.mbt:110-112` 原文

```
/// 内存后端：按裁决写预订，**写后回读**收口。
/// 旧形状（先 rsv_get 判空再无条件 rsv_set）在跨进程下会双方都读到空闲、双方都写成功；
/// 内存后端本来没有那个窗口，但两后端必须同一形状，否则单测永远绿而 SQLite 红（BUG-85/BUG-79 的旧例）。
```

**它警告的是**：**内存后端「本来没有那个窗口」，而 SQLite 有** ——
若内存版按旧形状（先判空再无条件写），**单测（跑内存版）永远绿，而生产（SQLite）红**。
⇒ **这条注释说的正是「测试面只覆盖一个后端」这个盲区**，而 §4 实测证实：**那个盲区今天还在。**

#### 3.2 `may_write` 到底是「同一规则两个执行点」还是「SQLite 版没用这条规则」？

**答：是「同一规则两个执行点」，且 SQLite 版的执行点更权威。**

实测依据 —— 等价格里 `ttl == now` 这一格：

```
输入：prev=("B","t1","t0")，请求 agent="A"，created_at="t1"
rsv_action:  Some((_, ttl, _)) if ttl < now   ← "t1" < "t1" = false ⇒ 落到 _ ⇒ (false,"conflict")
SQL ON CONFLICT WHERE: reservations.ttl_until < excluded.created_at  ← 同一条判断
实测两后端:  mem = {"reserved":false,"action":"conflict","agent":"B",...}
             sql = {"reserved":false,"action":"conflict","agent":"B",...}   ★ 相同
```

**⇒ 两个执行点用的是同一个严格 `<`，且实测结果一致。**

#### 3.3 三子句 ≡ 四分支 的**逐格实测**

| `rsv_action` 分支 | 判据 | 对应 SQL WHERE 子句 | 实测格 | 结果 |
|---|---|---|---|---|
| 分支1 `None ⇒ (true,"reserved")` | 无既有行 | `INSERT` 无冲突 ⇒ 直接插入 | `B1 none→reserved` | **两后端相同** ✅ |
| 分支2 `owner==agent ⇒ (true,"renewed")` | `owner == agent` | `agent = excluded.agent` | `B2 self→renewed` | **相同** ✅ |
| 分支3 `ttl<now ⇒ (true,"taken_over")` | **严格 `ttl < now`** | `ttl_until < excluded.created_at` | `B3 other→taken_over(ttl<now)` | **相同** ✅ |
| 分支4 `else ⇒ (false,"conflict")` | 其余 | WHERE 不成立 ⇒ 不写 | `B4 other→conflict(ttl>now)` | **相同** ✅ |
| **★ 边界** `ttl == now` | 分支4（因为 `<` 不含等于） | WHERE 不成立 | `EDGE other(ttl==now)` | **相同** ✅ |

**⇒ 三子句与四分支逐格对应，且 `ttl == now` 这个最易出错的边界两侧都判「不过期」。**

---

### §4 ★ 任务 3：为什么单测永远绿 —— **实测证实盲区仍在**

```
$ ls src/store/*rsv*
store_rsv.mbt  store_rsv_test.mbt

$ grep -c 'MemoryStore' src/store/store_rsv_test.mbt    → 0
$ grep -c 'SqliteStore' src/store/store_rsv_test.mbt    → 13
```

**⇒ `store_rsv_test.mbt` 13 处全用 `SqliteStore`，`MemoryStore` 零覆盖。**

**这意味着**：
- 内存版 `rsv_try_set` / `locks_try_acquire` 的**应用层裁决逻辑**（`if may_write` 那一段）
  **没有任何测试覆盖**
- 若有人把内存版的 `if may_write` 删掉（变成无条件写）⇒ **测试全绿**，
  而生产（SQLite）行为不变 ⇒ **内存后端静默腐坏，没人发现**
- 反过来，若有人改 SQLite 的 `ON CONFLICT WHERE` ⇒ 有测试抓（13 处）；
  **但内存后端不会被同一批测试覆盖** ⇒ **两后端可以各自漂移而不被同一把尺抓到**

**⇒ 这正是 `store_rsv.mbt:110-112` 注释警告的形状，今天仍然成立。**

> **诚实边界**：`MemoryStore` 在**生产**里是否被用到？
> `MemoryStore::new()` 主要在测试与「内存后端兜底」路径（server 打开 SQLite 失败时）。
> 所以**危害是「测试面与生产面分家」**（内存版腐坏不影响生产，但会让人误以为逻辑正确），
> 不是「生产数据损坏」。**这降低了严重度，但不改变「盲区存在」这个事实。**

---

### §5 变异对照（判例-29/30）—— 证明等价格**不是假锁**

两格等价格若恒绿就毫无价值。为证明它们**真能抓到差异**，加了两格变异对照：

**变异 1：把 `ttl < now` 写成 `ttl <= now`**
```
真 rsv_action(prev=(B,"t1"), agent=A, now="t1")  → (false, "conflict")
变异版（<=）                                       → (true,  "taken_over")
断言：两者必须不同 ✅（通过）⇒ 若真实现被改成 <=，等价格会在 EDGE 格红
```

**变异 2：把锁层 `status == "active"` 折叠条件去掉**
```
active 锁   → lock_acquire_action → (false, "conflict")   ← 有人持
released 锁 → lock_acquire_action → (true,  "reserved")   ← 折成 None
断言：两者必须不同 ✅（通过）⇒ 若折叠条件被删，等价格在 L4 格红
```

**⇒ 两格变异对照都通过，证明等价格具备判别力。**

---

### §6 覆盖维度读数（回答「说相同需要有量」）

**20 组真实输入**，覆盖维度：

| 维度 | 取值 | 覆盖格数 |
|---|---|---|
| **`rsv_action` 四分支** | reserved / renewed / taken_over / conflict | **4/4 全覆盖** |
| **`ttl` 与 `now` 关系** | `< now` / `== now` / `> now` | **3/3 全覆盖**（含最易错的 `==`） |
| **agent 相同/不同/空串** | 自己 / 别人 / `""` | **3/3 全覆盖**（空串双向：`"" → ""`、`"" → "A"`） |
| **无锁 / 有锁** | None / Some | **2/2 全覆盖** |
| **锁 status** | `active` / `released` / `expired` / `violated` | **4/5**（未覆盖 `"weird"` 等非法值） |
| **锁 prev_agent 是自己/别人/空** | A / B / `""` | **3/3 全覆盖** |
| **锁 ttl 边界** | `<` / `==` / `>` | **3/3 全覆盖** |
| **返回字段逐个比对** | `reserved/action/prev_agent/agent/ttl_until`（rsv）· `granted/action/prev_agent/agent/ttl_until/violation_logged`（锁） | **11/11 字段全覆盖** |

**⇒ 等价结论建立在「四分支 + 三处边界 + 11 个返回字段」的完整覆盖上，不是「跑了一堆都过」。**

---

## 分析

### ★ 四者（BUG-420 / 425 / 43x / 本条）有共同根因吗？

**有，而且是同一个词：`单一真源` 只在「算得出」的那一侧被兑现，在「另一侧」靠人守。**

| 缺陷 | 「真源」是什么 | 「第二个面」是什么 | 缺的是什么 |
|---|---|---|---|
| **BUG-420** | `namespace` 是**路由键** | 落库位置（实际写进哪个库） | **路由键没有回执** ⇒ 调用方无法确认它生效 |
| **BUG-425** | 文档/账本的**原文** | 读数面（badge/摘要里的数字） | **没有「原文 ↔ 读数」的对表判据** |
| **43x（本条）** | `rsv_action` / `lock_acquire_action` 是**单一真源** | 内存版应用层 + SQLite 版 SQL 两个执行点 | **没有「两执行点对表」的判据** |
| **BUG-424（你昨天）** | 「互斥由后端定」的纪律 | `legacy_grant` 特判新增的应用层读 | **纪律没有机械化检查** |

**共同根因（一句话）**：

> **本仓的「单一真源」纪律靠注释表达，靠人遵守；而真源与它的**消费面/执行点**之间
> 没有机械化的对表判据。** ⇒ 每一处「两个面」都需要一次专项审计才发现漂移。

**为什么这在本仓特别容易发生**：`一源四态`（MCP/skill/plugin/文档）是本仓的核心设计，
它把「同一规则的多个表达面」当成**特性**而不是**风险**。**四态是设计优势，也是漂移面。**
`check_doc_surface` / `check_plugin_sync` 是对「四态」的机械化对表 —— **但那只覆盖文档面，
没有覆盖「两个后端」和「两处执行点」。**

**⇒ 建议（架构级，非本单）**：把「两后端等价」也变成**机械化判据**（见 §7 建议 1）。

### 为什么本条最终判「等价」而不是「又一个 bug」

因为**执行点在两侧、判据只有一个**：`rsv_action` / `lock_acquire_action` 是**逐字委托**
（`lock_acquire_action` 的注释与代码都明写「逐字委托 `rsv_action`，不另写谓词」），
SQLite 的 `ON CONFLICT WHERE` 是**同一条规则的 SQL 编码**，且**两者都以写后回读定结论**。

**⇒ 这是「一源两投影」的正确做法**（真源 1 个、执行点 2 个、结论回读兜底），
而不是「两份分叉的实现」。**实测 20 组证实投影一致。**

**但**：正确做法**缺一把机械化的尺**来防未来漂移 —— 这才是真正的缺口。

---

## 缺口与风险

### 盲区 1：`locks_sweep` 未做等价比对

本轮只比了 `rsv_try_set` / `locks_try_acquire`（+ 间接覆盖 `rsv_set`）。
**`locks_sweep`（内存 `:407` / SQLite `:1671`）未比对** —— 它是「批量释放过期锁」，
两边的过期判据可能有 `<` vs `<=` 的差异，**未验**。

### 盲区 2：`MemoryStore` 的 rsv/锁面**仍然零测试覆盖**

我**加的是临时探针，跑完已移除**（按派单「禁止改 src/」）。
⇒ **盲区没有被修复，只是被证实了**。
**建议把这两格等价格正式落进 `src/store/store_rsv_test.mbt`**（见 §7 建议 1）。

### 盲区 3：探针只在 `:memory:` SQLite 上跑

`SqliteStore::open(":memory:")` 与**落盘库**在 SQLite 层面行为应当一致，但
**未在真实落盘库上复跑**。若 `returnArrays` 或列读取有差异（Node < 24 的旧已知问题），**未覆盖**。

### 盲区 4：未覆盖多线程/多连接并发

本轮是**单线程顺序**比对。两后端在**真并发**下是否等价（尤其 SQLite 的写锁行为）**未验**。

### 盲区 5：`RsvOutcome` / `LockAcquireOutcome` 之外还有别的双实现面

本轮只比了这两个结构。`store.mbt` 的 **Store trait 有多少个方法有双实现、其中几对没被比对**，
**未做全量普查**（见 §7 建议 2）。

### 盲区 6：二次踩坑——`moon test` 吞 stdout

第一次探针用 `println` 输出比对结果，`moon test` 报 **79/79 全绿但一行输出都没有**。
⇒ **「测试全绿」不等于「测试里的打印被看见」**。这也是「读数面 ≠ 原文面」（BUG-425）的同族形状。
**已改为断言**，记在此处备查。

---

## 建议入档位置

| 内容 | 位置 |
|---|---|
| 本报告 | `reports/2026-10-27-r10-backend-equivalence-audit.md` |
| 探针源码（可复用） | `temp/audit/r10_probe/r10_ah_probe_test.mbt`（rsv 10 组）· `r10_ah_lock_probe_test.mbt`（锁 10 组）· `r10_ah_mutation_test.mbt`（2 格变异对照） |
| **建议 1（最高优先）** | **把 3 个探针正式落进 `src/store/store_rsv_test.mbt`** —— 这是「让盲区不再盲」的唯一办法。落地方：3 个文件内容可直接粘贴，只改 `test "..."` 的名字加 `equiv_` 前缀 |
| **建议 2** | 普查「Store trait 的双实现面」：列出所有 `MemoryStore::x` / `SqliteStore::x` 对，标出**有没有跨后端对表测试** |
| **建议 3（架构级）** | 新建 `scripts/check_backend_equivalence.py`：用上述探针做 CI 门（**判据单一真源 = 探针文件本身**，避免又一次「注释靠人守」） |
| **未做** | **未调 `bug_fix`**（无 bug）· **未改 `src/`**（探针已移除） |
