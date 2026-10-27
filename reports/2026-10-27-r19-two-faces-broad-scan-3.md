# R19 第二波 · 剩余 7 面普查（形状搜索 + 面扫描）

> **任务**：① 形状搜索补 `src/engine/` ② 面扫描 7 面 ③ 刻意找「假绿」
> **执行人**：司令-γ · **边界**：只读 + 报告（未改 `src/` `scripts/`，未碰 7 个在途文件）

---

## 结论（两部分分开写）

### A. 形状搜索 —— **0 条新 bug**

```
$ grep -rn 'Mem(_) =>' src/store/ src/engine/ --include=*.mbt | grep -vE '_test|_wbtest'
→ 13 个分发点（**全部在 store.mbt，src/engine/ 里一个都没有**）

$ 其中占位形态（None / Ok(()) / [] / "")
→ 10 个
```

**第一波已核 7 个**（`sqlite_store` / `write_heartbeat` / `read_heartbeat` / `delete_heartbeat` /
`list_all_heartbeats` / `list_heartbeat_intervals` / `write_saga_action` / `mark_saga_actions_done`）。

**本波核剩余的 3 个**：

| 行 | 宿主 | 内存分支 | 判定 |
|---|---|---|---|
| 801 | `lock_violations_push` `:784` | `Mem(m) => m.lock_violations_push(v)` | **不是占位**（真实转发到 MemoryStore） |
| 907 | `backend_name` `:902` | `Mem(_) => "memory"` | **不是占位**（返回值就是名字，语义正确） |
| 934 | `write_heartbeat_interval` | `Mem(_) => Ok(())` | 第一波归属 heartbeat 族，**回执已披露 `persisted`** ✓ |

**⇒ 形状搜索**新增 0 bug**。**10 个占位里：8 个已正确处理、2 个是 bug（`BUG-439` 已修 / `BUG-441` 待修）。**

### B. 面扫描 7 面 —— **0 条新 bug**

| # | 面 | 扫了什么 | 读数 | 结论 |
|---|---|---|---|---|
| 1 | **`evolve_*`** | 3 条写入路径 + 3 个前缀函数 + store 面 | 3 路径 / 3 前缀 / 0 处 SQL | **共用真源** ✓ |
| 2 | **`supervisor_*`** | 8 工具 + 树聚合实现 | 1 处聚合 / 2 处 `subtree_*` 产出 | **单一实现** ✓ |
| 3 | **`loop_*`** | 3 工具 + registry | **进程内 Map，无 store 面** | **无双后端问题** ✓ |
| 4 | **`omega_*`** | 6 工具 + spec store 面 | 3 分发点，Mem **真实实现** | **共用真源** ✓ |
| 5 | **`memory_*`** | 4 个函数 | 单文件族，无 store 面 | **单一实现** ✓ |
| 6 | **`debate_*`** | 3 工具 + registry | **进程内 Map** | **无双后端问题** ✓ |
| 7 | **`selfdrive_*`** | 9 工具 | 复用 memory/ops 真源 | **共用真源** ✓ |

**⇒ 面扫描新增 0 bug。**

**本波唯一产出**：**7 个面中 3 个（`loop_*`/`debate_*`/`memory_*`）根本没有 store 面** ——
这不是「扫过没问题」，而是**「这类缺陷在这三个面上不可能存在」**。

---

## 证据

### §1 形状搜索：为什么 `src/engine/` 里一个都不是

```
$ grep -rn 'Mem(_) =>' src/engine/ --include=*.mbt
（空）
```
**原因**：双后端分发**只发生在 `StoreBackend` 这一层**（`src/store/store.mbt`），
`src/engine/` 通过 `self.store.xxx()` 调它，**永远看不到 `Mem`/`Sql` 的分支**。
⇒ **形状搜索的适用范围 = `src/store/store.mbt` 一个文件**。`src/engine/` 纳入 grep 是冗余的（但无害，且**证明了这个边界**）。

### §2 面 1：`evolve_*` —— 3 条写入路径全部汇到 `evolve_upsert`

```
src/evolve/lesson.mbt:68              s.evolve_upsert(...)   ← goal = lesson_goal(cat)      "\[lesson]…"
src/server/evolve_distill.mbt:60      s.evolve_upsert(...)   ← goal = distill_principle_goal(goal)  "\[principle]…"
src/server/self_search_evolve_bridge.mbt:138  s.evolve_upsert(...) ← goal = "[asset]\{source}"
```

**三条路径的差异是「前缀类目」，不是「同一规则的两份实现」**：
- 三个前缀 `[lesson]` / `[principle]` / `[asset]` 是**三个不同类目**（lesson=失败回流、principle=蒸馏、asset=外部资产）
- 三者**都调用同一个** `evolve_upsert`（落库唯一入口）
- **`lesson_goal` 还做了 idempotent 前缀检测**（`if c.has_prefix("[lesson]") { c } else { ... }`），
  `distill_principle_goal` 同理 —— **两个函数的「防重复前缀」逻辑各写一遍**

**⇒ 判定：共用真源 ✓，但「防重复前缀」这个小判据有两份**（现网等价，未报 bug，列建议）。

**读数**：3 条写入路径 · 3 个前缀函数 · 0 处 SQL 谓词（evolve 全走 store 方法，无手写 SQL）。

### §3 面 2：`supervisor_*` —— 树聚合只有一处

```
$ grep -rn 'subtree_total\|subtree_done' src/ --include=*.mbt | grep -vE '_test|_wbtest'
src/engine/engine_supervisor.mbt:98   "subtree_total": Json::number(child_total.to_double()),
src/engine/engine_supervisor.mbt:99   "subtree_done":  Json::number(child_done.to_double()),
src/engine/engine_supervisor.mbt:108  /// 任务树状态与进度汇报：root 起递归，每节点带 subtree_done/subtree_total。
src/server/supervisor_tools.mbt:349   （工具 description 文本，不是实现）
```
**⇒ 聚合逻辑唯一实现在 `engine_supervisor.mbt:98-99`，8 个 supervisor 工具全部转发它。**
**`board_ascii`（另一个「按状态分组渲染」的工具）不走这条** —— 它不做树聚合，
**两者不是同一规则的两个实现**（一个是「树+完成度」，一个是「按状态分组」）。

### §4 面 3/6：`loop_*` / `debate_*` —— **没有 store 面**

```
src/ops/ops_loop.mbt:384   /// LoopRegistry —— 进程内组合环注册表（模仿 AuditLog 模式）
src/server/server.mbt:317  let debate_sessions : DebateRegistry = DebateRegistry::new()
```
**⇒ 状态只在进程内 `Map`，不经 `StoreBackend` ⇒ 「内存版 vs SQLite 版」这个问题在它们身上不存在。**

**但这也意味着另一件事**（不是 bug，是设计边界）：
**进程重启即失** —— 两个工具的 description 都已诚实标注（`debate_convene`：
「会话态进程内保存、重启即失（诚实标注）」；`loop_*` 同类）。
**⇒ 这是「已知且已披露的限制」，不是假绿。**

### §5 面 4：`omega_*` —— spec 面在 Mem 下是**真实实现**

```
$ grep -nE 'fn StoreBackend::(upsert_spec|get_spec|list_specs_by_task)' -A 4 src/store/store.mbt
:1131  Mem(m) => m.upsert_spec(rec)        ← 真实
:1141  Mem(m) => m.get_spec(id)            ← 真实
:1150  Mem(m) => m.list_specs_by_task(...) ← 真实
```
**⇒ 与 saga 形成对照：omega 的 spec 面内存后端是真做的，saga 的没有。**
**（这也回答了一个问题：本仓并非「所有内存后端都只做占位」—— `BUG-441` 是遗漏，不是统一策略。）**

### §6 面 5/7：`memory_*` / `selfdrive_*` —— 文件族与真源复用

`memory_*` 4 个函数（`memory_consolidate` / `memory_gc_logic` / `memory_gc_one` / `memory_gc_all`）
**都是文件读写，不经 store** ⇒ 无双后端问题。
`selfdrive_*` 9 工具复用 memory / ops 既有函数，**无自建实现**。

---

## 分析：形状搜索 vs 面扫描的互补性（本波实测）

| | 形状搜索 | 面扫描 |
|---|---|---|
| **能找什么** | **「占位是合法值」** 这一族（`BUG-439`/`441`） | **「各写一份不等价逻辑」** 那一族（`BUG-438`） |
| **缺陷空间** | **全仓 1 个文件**（`store.mbt`）的 **13 个分发点** | 每面 N 个工具 × M 个函数的**调用关系** |
| **本波产出** | **0**（10 占位 8 正确 2 已知） | **0**（7 面全绿） |
| **耗时** | 3 条 grep | 7 面逐面读实现 |
| **可枚举性** | ✅ **有限且稳定**（13 个点，一次扫完） | ❌ 面数会随新工具增长 |

**⇒ 关键洞见：形状搜索的搜索空间是「有界的」**（`StoreBackend` 分发点数量 ≈ 常数），
**而面扫描的搜索空间随工具数线性增长**。

**这不是说形状搜索更好，而是说：**
> **一个缺陷类一旦被识别出「有界形状」，就应当做成机械判据（一次投入，永久覆盖）；
> 而面扫描只能作为「尚未识别形状」的探索手段。**

**本波同时也证明了面扫描的价值**：它发现了 **3 个面根本不存在这类缺陷**
（`loop_*`/`debate_*`/`memory_*` 无 store 面）—— 这是形状搜索**给不出**的信息
（grep 只能告诉你「这里没有 Mem 分发」，不能告诉你「这个面结构上就不可能有两面」）。

---

## 缺口与风险

### 1. 本波**零 bug** —— 但这不等于「这 7 个面没问题」

面扫描只覆盖了「双实现/重复逻辑」。**以下形状本波未查**：
- **`evolve_critic` 的判据与实现是否对表**（派单点名的）—— 只核了 `evolve_upsert` 三条路径，
  **没核 `critic_review` 的重合阈值 0.70 与 `Archive::novelty` 的实现是否一致**
- **`omega_*` 的「语料审核」与「成果复验」是否各写一遍门禁**（只核了 spec 存储面）
- **`supervisor_*` 8 个工具之间的 ns 寻址逻辑**（R11 已查过主 8 工具，**supervisor 的 ns 寻址未查**）

### 2. `evolve` 的「防重复前缀」两份实现（未报 bug）

`lesson_goal`（`ops` 侧）与 `distill_principle_goal`（`server` 侧）**各写一遍
「若已带前缀则原样返回，否则拼前缀」**。现网等价，但**这是又一个可收拢的小判据**。

### 3. `loop_*` / `debate_*` 的「进程内状态」是设计边界，不是缺陷

但**它有一个未言明的后果**：`debate_convene` → `hat_run` → `hat_merge` 三步若跨进程
（不同 MCP 连接打到不同 server 实例），**会话读不到**。当前单实例部署下无问题。**列入风险备查。**

### 4. 未跑测试

本波全部是静态读数（grep + 读实现）。**零 bug 的结论没有动态验证**，
但**「这 7 个面无双实现」这个判断本身只需要静态证据**（找实现点即可），不需要跑。

---

## 建议入档位置

| 内容 | 位置 |
|---|---|
| 本报告 | `reports/2026-10-27-r19-two-faces-broad-scan-3.md` |
| **建议后续** | ① 把「占位是合法值」做成机械判据（**搜索空间有界 = 13 个分发点**，最适合机械化的一个）② 核 `evolve_critic` 阈值与 `novelty` 实现是否对表 ③ 核 `omega_*` 的语料门禁是否双路径 ④ 收拢 `evolve` 的两份前缀函数 |
| **未做** | **未调 `bug_fix`**（本波零 bug）· **未改 `src/` `scripts/`** · **未跑测试** |
